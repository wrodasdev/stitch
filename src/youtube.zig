const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const PlaylistPage = struct {
    nextPageToken: ?[]const u8 = null,
    items: []Video,
};

pub const Video = struct {
    snippet: Snippet,
    contentDetails: ContentDetails,
    status: Status,
};

const Snippet = struct {
    channelId: []const u8,
};

const ContentDetails = struct {
    videoId: []const u8,
    videoPublishedAt: ?[]const u8 = null,
};

const Status = struct {
    privacyStatus: []const u8,
};

pub fn fetchVideos(io: Io, allocator: Allocator, api_key: []const u8, playlist_id: []const u8) ![]Video {
    var videos: std.ArrayList(Video) = .empty;
    var page_token: ?[]const u8 = null;
    var url_buf: [1024]u8 = undefined;
    var body_buf = std.Io.Writer.Allocating.init(allocator);

    var client = std.http.Client{
        .allocator = allocator,
        .io = io,
    };
    defer client.deinit();

    while (true) {
        const url = try buildUrl(&url_buf, playlist_id, api_key, page_token);
        const uri = try std.Uri.parse(url);

        const playlist_page = try fetchPage(allocator, &body_buf, &client, uri);

        for (playlist_page.items) |video| {
            if (std.mem.eql(u8, video.status.privacyStatus, "public")) {
                try videos.append(allocator, video);
            }
        }
        page_token = playlist_page.nextPageToken orelse break;
    }

    return videos.items;
}

fn buildUrl(url_buf: []u8, playlist_id: []const u8, api_key: []const u8, page_token: ?[]const u8) ![]const u8 {
    const base_url: []const u8 = "https://www.googleapis.com/youtube/v3/playlistItems?part=snippet,contentDetails,status";

    //URL BUILDING
    const url = if (page_token) |token| try std.mem.print(
        url_buf,
        "{s}&playlistId={s}&maxResults=50&key={s}&pageToken={s}",
        .{ base_url, playlist_id, api_key, token },
    ) else try std.mem.print(
        url_buf,
        "{s}&playlistId={s}&maxResults=50&key={s}",
        .{ base_url, playlist_id, api_key },
    );

    return url;
}

fn fetchPage(allocator: Allocator, body_buf: *std.Io.Writer.Allocating, client: *std.http.Client, uri: std.Uri) !PlaylistPage {
    body_buf.clearRetainingCapacity();

    //HTTP RESPONSE
    const response = try client.fetch(.{
        .method = .GET,
        .location = .{ .uri = uri },
        .response_writer = &body_buf.writer,
    });

    if (response.status != .ok) {
        std.debug.print("HTTP Error: {any}\n{s}\n", .{ response.status, body_buf.written() });
        return error.BadStatus;
    }

    const playlist_page = try std.json.parseFromSliceLeaky(
        PlaylistPage,
        allocator,
        body_buf.written(),
        .{
            .allocate = .alloc_always,
            .ignore_unknown_fields = true,
        },
    );

    return playlist_page;
}

pub fn filterNewVideos(allocator: Allocator, videos: []const Video, since: []const u8) ![]Video {
    var filtered_videos: std.ArrayList(Video) = .empty;
    for (videos) |video| {
        const publish_date = video.contentDetails.videoPublishedAt orelse continue;
        const filter = std.mem.order(u8, publish_date, since);
        if (filter == .gt) {
            try filtered_videos.append(allocator, video);
        }
    }

    return filtered_videos.items;
}

pub fn newestDate(videos: []const Video) ?[]const u8 {
    var newest_date: ?[]const u8 = null;
    for (videos) |video| {
        const pub_date = video.contentDetails.videoPublishedAt orelse continue;
        if (newest_date == null or std.mem.order(u8, newest_date.?, pub_date) == .lt) {
            newest_date = pub_date;
        }
    }

    return newest_date;
}

pub fn videoLessThan(_: void, a: Video, b: Video) bool {
    return std.mem.order(u8, a.contentDetails.videoPublishedAt.?, b.contentDetails.videoPublishedAt.?) == .lt;
}
