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

pub fn findFile(gpa: std.mem.Allocator, arena: std.mem.Allocator, io: std.Io, file_name: []const u8, no_discovery: bool) ![]u8 {
    const cwd = try std.process.currentPathAlloc(io, gpa);
    defer gpa.free(cwd);

    var dir: []const u8 = cwd;

    while (true) {
        const path = try std.fs.path.join(gpa, &.{ dir, file_name });
        defer gpa.free(path);

        logger.debug("trying {s}", .{path});
        
        if (std.Io.Dir.access(std.Io.Dir.cwd(), io, path, .{})) |_| {
            if (!std.mem.eql(u8, dir, cwd))
                logger.info("found {s}/{s}{s}{s}", .{ dir, colors.get(.bold), file_name, colors.get(.reset) });

            return try arena.dupe(u8, dir);
        } else |err| {
            switch (err) {
                error.FileNotFound => if (no_discovery) break,
                else => break,
            }
        }

        dir = std.fs.path.dirname(dir) orelse break;
    }

    logger.err("couldn't find {s}'{s}'{s}", .{ colors.get(.bold), file_name, colors.get(.reset) });
    return error.FileNotFound;
}

pub fn readFile(arena: std.mem.Allocator, gpa: std.mem.Allocator, io: std.Io, dir: []const u8, file_name: []const u8) ![]const u8 {
    const joined_path = try std.fs.path.join(gpa, &.{ dir, file_name });
    defer gpa.free(joined_path);

    return std.Io.Dir.readFileAlloc(std.Io.Dir.cwd(), io, joined_path, arena, .unlimited) catch {
        logger.err("failed to read {s}'{s}'{s}", .{colors.get(.bold), joined_path, colors.get(.reset)});
        return error.FailedFileRead;
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

// uses the levenshtein distance algorithm: https://en.wikipedia.org/wiki/Levenshtein_distance
pub fn getEditDistance(a: []const u8, b: []const u8) ?usize {
    if (a.len == 0 or b.len == 0) return null;

    var row: [64]usize = undefined;

    if (@max(a.len, b.len) > 64) return null;

    for (row[0..b.len + 1], 0..) |*cell, i| 
        cell.* = i;

    for (a, 0..) |ca, i| {
        var diagonal = row[0];
        row[0] = i + 1;

        for (b, 0..) |cb, j| {
            const above = row[j + 1];
            const left = row[j];

            const cost = @intFromBool(ca != cb);

            const delete = above + 1;
            const insert = left + 1;
            const replace = diagonal + cost;

            const min = @min(delete, @min(insert, replace));

            row[j + 1] = min;

            diagonal = above;
        }
    }

    const distance = row[b.len];

    logger.debug("edit distance {s} to {s}: {d}", .{a, b, distance});

    return distance;
}
