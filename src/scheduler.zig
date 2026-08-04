const builtin = @import("builtin");
const std = @import("std");
const runner = @import("runner.zig");
const logger = @import("logger.zig");
const colors = @import("colors.zig");
const config = @import("config.zig");

pub var had_work = false;

pub fn scheduleCommands(io: std.Io, gpa: std.mem.Allocator, items: []const []const u8, cfg: *const config.Config) !void {
    if (items.len == 0) return;

    if (!had_work)
        had_work = true;

    if (cfg.dry_run) {
        for (items) |cmd| {
            logger.info("{s}", .{ cmd });
        }
        return;
    }

    const worker_count = @min(cfg.threads, items.len);

    logger.debug("worker_count = {}", .{ worker_count });

    const worker_type = std.Io.Future(@typeInfo(@TypeOf(worker)).@"fn".return_type.?);
    const workers = try gpa.alloc(worker_type, worker_count);
    
    var spawned: usize = 0;

    defer {
        for (workers[0..spawned]) |*w| {
            _ = w.cancel(io) catch {};
        }
        defer gpa.free(workers);
        logger.debug("all async workers cleaned up", .{});
    }

    var index: usize = 0;

    while (index < items.len) {
        const batch_size = @min(worker_count, items.len - index);
        const batch = items[index..][0..batch_size];

        spawned = 0;

        for (batch, 0..) |cmd, i| {
            workers[i] = io.async(worker, .{
                gpa, io, cmd, batch.len > 1,
            });
        }

        spawned += batch.len;

        for (workers[0..spawned], 0..) |*w, i| {
            w.await(io) catch |e| {
                std.debug.print("\n", .{});
                logger.out(true, if (cfg.ignore_errors) .warning else .err, null, "command {s}'{s}'{s} failed{s}", .{
                    colors.get(.bold), batch[i], colors.get(.reset), if (cfg.ignore_errors) "" else ". stopping"
                });

                if (!cfg.ignore_errors)
                    return e;
            };
        } 

        spawned = 0;
        index += batch.len;
    }
}

fn worker(gpa: std.mem.Allocator, io: std.Io, cmd: []const u8, parallel: bool) !void {
    if (parallel)
        logger.outLocked(io, .info, "{s}", .{ cmd })
    else
        logger.info("{s}", .{ cmd });

    const os = builtin.target.os.tag;

    const args = if (os == .windows)
        [_][]const u8{ "cmd.exe", "/C", cmd }
    else
        [_][]const u8{ "sh", "-c", cmd };

    const res = try std.process.run(gpa, io, .{ .argv = &args });

    defer gpa.free(res.stdout);
    defer gpa.free(res.stderr);
    
    const output = try std.mem.concat(gpa, u8, &.{res.stdout, res.stderr});
    defer gpa.free(output);

    if (parallel) 
        try logger.log_mutex.lock(io);

    defer if (parallel) logger.log_mutex.unlock(io);
    try std.Io.File.stdout().writeStreamingAll(io, output);

    return switch (res.term) {
        .exited => |code| if (code != 0) error.CommandFailed,
        else => error.CommandFailed,
    };
}
