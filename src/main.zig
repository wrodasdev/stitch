const std = @import("std");
const creators = @import("./creators.zig");
const yt = @import("./youtube.zig");
const Io = std.Io;
const Allocator = std.mem.Allocator;

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const allocator = init.gpa;
    const arena = init.arena.allocator();

    const path: []const u8 = "creators.json";
    const yt_key = init.environ_map.get("YOUTUBE_API_KEY") orelse {
        std.debug.print("Make sure to add your Youtube API Key\n", .{});
        return error.MissingApiKey;
    };

    var playlist_videos: std.ArrayList(yt.Video) = .empty;

    const creator_list = try creators.loadCreators(io, path, allocator);
    defer creator_list.deinit();
    for (creator_list.value) |*creator| {
        var videos = try yt.fetchVideos(io, arena, yt_key, creator.playlist_id);
        videos = try yt.filterNewVideos(arena, videos, creator.last_publish_date);
        try playlist_videos.appendSlice(arena, videos);
        creator.last_publish_date = yt.newestDate(videos) orelse continue;
    }
    try creators.saveCreators(io, path, creator_list.value);
}
