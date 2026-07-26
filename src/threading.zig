const builtin = @import("builtin");
const std = @import("std");
const runner = @import("runner.zig");
const logger = @import("logger.zig");
const globals = @import("globals.zig");

var cmd_failed: std.atomic.Value(bool) = .init(false);

pub fn runCommands(gpa: std.mem.Allocator, items: []const []const u8, config: *const runner.Config) !void {
    if (items.len == 0) return;

    if (config.dry_run) {
        for (items) |item| {
            logger.out(.info, "{s}", .{item});
        }
        return;
    }

    const thread_count = @min(config.threads, items.len);
    const threads = try gpa.alloc(std.Thread, thread_count);
    defer gpa.free(threads);

    logger.out(.debug, "thread_count = {}", .{ thread_count });

    var index: usize = 0;

    while (index < items.len) {
        const batch_size = @min(thread_count, items.len - index);

        for (0..batch_size) |i| {
            threads[i] = try std.Thread.spawn(.{}, worker, .{gpa, globals.io, items[index + i], batch_size > 1});
        }

        for (0..batch_size) |i| {
            threads[i].join();
        }

        index += batch_size;
    }

    if (cmd_failed.load(.monotonic)) {
	logger.outAdv(false, .info, null, "\n", .{});
        logger.out(if (config.ignore_errors) .warning else .err, "one or more commands failed{s}", .{if (config.ignore_errors) "" else ". stopping"});

        if (!config.ignore_errors)
            return error.CommandFailed;
    }
}

fn worker(gpa: std.mem.Allocator, io: std.Io, cmd: []const u8, needs_lock: bool) void {
    if (needs_lock)
        logger.outLocked(io, .info, "{s}", .{cmd})
    else
        logger.out(.info, "{s}", .{cmd});

    const res = createProcess(gpa, io, cmd) catch {
        cmd_failed.store(true, .monotonic);
        return;
    };

    defer gpa.free(res.stdout);
    defer gpa.free(res.stderr);

    const failed = switch (res.term) {
        .exited => |code| code != 0,
        else => true,
    };
    
    if (failed) cmd_failed.store(true, .monotonic);

    const output = std.mem.concat(gpa, u8, &.{res.stdout, res.stderr}) catch return;
    defer gpa.free(output);

    if (needs_lock) {
        logger.log_mutex.lock(io) catch return;
    }
    defer if (needs_lock) logger.log_mutex.unlock(io);
    std.Io.File.stdout().writeStreamingAll(io, output) catch return;
}

fn createProcess(gpa: std.mem.Allocator, io: std.Io, cmd: []const u8) !std.process.RunResult {
    const args = if (builtin.target.os.tag == .windows)
        [_][]const u8{ "cmd.exe", "/C", cmd }
    else
        [_][]const u8{ "sh", "-c", cmd };

    return try std.process.run(gpa, io, .{ .argv = &args });
}
