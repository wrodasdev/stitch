const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Playlist = struct {
    nextPageToken: ?[]const u8 = null,
    items: []Video,
};

const Video = struct {
    contentDetails: ContentDetails,
    status: Status,
};

const ContentDetails = struct {
    videoId: []const u8,
    videoPublishedAt: ?[]const u8,
};

const Status = struct {
    privacyStatus: []const u8,
};

const Resource = struct {
    videoId: []const u8,
};

pub fn fetchVideos(io: Io, allocator: Allocator, api_key: []const u8, playlist_id: []const u8) !std.ArrayList(Video) {
    var videos: std.ArrayList(Video) = .empty;
    var page_token: ?[]const u8 = null;

    //HTTP RESPONSE
    var body_buffer = std.Io.Writer.Allocating.init(allocator);
    var redirect_buffer: [8192]u8 = undefined;
    var client = std.http.Client{
        .allocator = allocator,
        .io = io,
    };
    defer client.deinit();

    var url_buf: [1024]u8 = undefined;

    while (true) {
        body_buffer.clearRetainingCapacity();

        const url = try buildUrl(&url_buf, playlist_id, api_key, page_token);
        const uri = try std.Uri.parse(url);

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

        const playlist = try fetchPage(allocator, io, uri);

        for (playlist.items) |video| {
            if (std.mem.eql(u8, video.status.privacyStatus, "public")) {
                try videos.append(allocator, video);
            }
        }
        page_token = playlist.nextPageToken orelse break;
    }

    return videos;
}

fn buildUrl(buf: []u8, playlist_id: []const u8, api_key: []const u8, page_token: ?[]const u8) ![]const u8 {
    const base_url: []const u8 = "https://www.googleapis.com/youtube/v3/playlistItems?part=contentDetails,status";

    //URL BUILDING
    const url = if (page_token) |token| try std.mem.print(
        buf,
        "{s}&playlistId={s}&maxResults=50&key={s}&pageToken={s}",
        .{ base_url, playlist_id, api_key, token },
    ) else try std.mem.print(
        buf,
        "{s}&playlistId={s}&maxResults=50&key={s}",
        .{ base_url, playlist_id, api_key },
    );

    return url;
}

fn fetchPage(allocator: Allocator, io: Io, uri: std.Uri) !Playlist {
    //HTTP RESPONSE
    var body_buffer = std.Io.Writer.Allocating.init(allocator);
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

    const playlist = try std.json.parseFromSliceLeaky(
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
