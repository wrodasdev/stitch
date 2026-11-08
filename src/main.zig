const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Creator = struct {
    name: []const u8,
    channel_id: []const u8,
    last_publish_date: []const u8,
    playlist_id: []const u8,
};

const Playlist = struct {
    nextPageToken: ?[]const u8 = null,
    items: []Video,
};

const Video = struct {
    snippet: Snippet,
};

const Snippet = struct {
    publishedAt: []const u8,
    resourceId: Resource,
};

const Resource = struct {
    videoId: []const u8,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;
    const path: []const u8 = "creators.json";
    const yt_key = init.environ_map.get("YOUTUBE_API_KEY") orelse {
        std.debug.print("Make sure to add your Youtube API Key\n", .{});
        return error.MissingApiKey;
    };

    const creators = try loadCreators(io, path, allocator);
    defer creators.deinit();

    // for (creators.value) |creator| {
    //     std.debug.print(
    //         "Creator Name: {s}\nChannel Id: {s}\nLast Publish Date: {s}\nPlaylist Id: {s}\n",
    //         .{
    //             creator.name,
    //             creator.channel_id,
    //             creator.last_publish_date,
    //             creator.playlist_id,
    //         },
    //     );
    // }

    try saveCreators(io, path, creators.value);
    const playlist = try fetchPlaylist(io, allocator, yt_key, creators.value[1].playlist_id);
    defer playlist.deinit();

    for (playlist.value.items) |video| {
        std.debug.print("Published At: {s}\nVideo Id: {s}\n", .{ video.snippet.publishedAt, video.snippet.resourceId.videoId });
    }
}

fn loadCreators(io: Io, path: []const u8, allocator: Allocator) !std.json.Parsed([]Creator) {
    const file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    var file_buff: [4096]u8 = undefined;
    var file_reader = file.reader(io, &file_buff);
    const reader = &file_reader.interface;

    const file_len = try file.length(io);
    const file_contents = try reader.readAlloc(allocator, file_len);
    defer allocator.free(file_contents);
    const file_json = try std.json.parseFromSlice([]Creator, allocator, file_contents, .{ .allocate = .alloc_always });
    return file_json;
}

fn saveCreators(io: Io, path: []const u8, creators: []const Creator) !void {
    const file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);

    var file_buff: [4096]u8 = undefined;
    var file_writer = file.writer(io, &file_buff);
    const writer = &file_writer.interface;

    try std.json.Stringify.value(creators, .{ .whitespace = .indent_2 }, writer);
    try writer.flush();
}
fn fetchPlaylist(io: Io, allocator: Allocator, api_key: []const u8, playlist_id: []const u8) !std.json.Parsed(Playlist) {
    //URL BUILDING
    const base_url: []const u8 = "https://www.googleapis.com/youtube/v3/playlistItems?part=snippet";
    var url_buffer: [1024]u8 = undefined;
    const url = try std.mem.print(
        &url_buffer,
        "{s}&playlistId={s}&maxResults=5&key={s}",
        .{ base_url, playlist_id, api_key },
    );
    const uri = try std.Uri.parse(url);

    //HTTP RESPONSE
    var body_buffer = std.Io.Writer.Allocating.init(allocator);
    defer body_buffer.deinit();

    var redirect_buffer: [8192]u8 = undefined;

    var client = std.http.Client{
        .allocator = allocator,
        .io = io,
    };
    defer client.deinit();
    const response = try client.fetch(.{
        .method = .GET,
        .location = .{ .uri = uri },
        .redirect_buffer = &redirect_buffer,
        .response_writer = &body_buffer.writer,
    });

    if (response.status != .ok) {
        std.debug.print("HTTP Error: {any}\n", .{response.status});
        return error.BadStatus;
    }

    const playlist = try std.json.parseFromSlice(
        Playlist,
        allocator,
        body_buffer.written(),
        .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        },
    );
    return playlist;
}
