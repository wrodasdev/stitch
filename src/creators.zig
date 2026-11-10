const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;

const Creator = struct {
    name: []const u8,
    channel_id: []const u8,
    last_publish_date: []const u8,
    playlist_id: []const u8,
};

pub fn loadCreators(io: Io, path: []const u8, allocator: Allocator) !std.json.Parsed([]Creator) {
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

pub fn saveCreators(io: Io, path: []const u8, creators: []const Creator) !void {
    const file = try std.Io.Dir.cwd().createFile(io, path, .{});
    defer file.close(io);

    var file_buff: [4096]u8 = undefined;
    var file_writer = file.writer(io, &file_buff);
    const writer = &file_writer.interface;

    try std.json.Stringify.value(creators, .{ .whitespace = .indent_2 }, writer);
    try writer.flush();
}
