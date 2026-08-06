const std = @import("std");
const colors = @import("colors.zig");
const logger = @import("logger.zig");

pub fn parseBool(input: []const u8) error{InvalidBoolean}!bool {
    if (std.mem.eql(u8, input, "true"))
        return true;

    if (std.mem.eql(u8, input, "false"))
        return false;

    return error.InvalidBoolean;
}

pub fn readFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]const u8 {
    return std.Io.Dir.readFileAlloc(std.Io.Dir.cwd(), io, path, allocator, .unlimited) catch |e| {
        logger.err("failed to read {s}'{s}'{s}", .{colors.get(.bold), path, colors.get(.reset)});
        return e;
    };
}

pub fn splitString(allocator: std.mem.Allocator, input: []const u8, delimiter: u8) ![]const []const u8 {
    var list: std.ArrayList([]const u8) = .empty;
    errdefer list.deinit(allocator);

    var iter = std.mem.tokenizeScalar(u8, input, delimiter);

    while (iter.next()) |part| {
        if (part.len == 0) continue;
        try list.append(allocator, part);
    }

    return try list.toOwnedSlice(allocator);
}
