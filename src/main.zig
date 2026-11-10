const std = @import("std");
const creator = @import("./creators.zig");
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

    const creators = try creator.loadCreators(io, path, allocator);
    defer creators.deinit();

    try creator.saveCreators(io, path, creators.value);
    const videos = try yt.fetchVideos(io, arena, yt_key, creators.value[1].playlist_id);

    for (videos.items) |video| {
        std.debug.print("Published At: {s}\nVideo Id: {s}\n", .{ video.contentDetails.videoPublishedAt.?, video.contentDetails.videoId });
    }
}
