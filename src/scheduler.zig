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
            logger.out(true, .none, null, "{s} [dry_run]", .{ cmd });
        }
        return;
    }

    const thread_count = switch (cfg.threads) {
        .auto => std.Thread.getCpuCount() catch 1,
        .count => |n| n,
    };
    const worker_count = @min(thread_count, items.len);

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
                gpa, io, cfg, cmd, batch.len > 1,
            });
        }

        spawned += batch.len;

        for (workers[0..spawned], 0..) |*w, i| {
            w.await(io) catch |e| {
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

fn worker(gpa: std.mem.Allocator, io: std.Io, cfg: *const config.Config, cmd: []const u8, parallel: bool) !void {
    if (parallel)
        logger.outLocked(.none, "{s}", .{ cmd })
    else
        logger.out(true, .none, null, "{s}", .{ cmd });


    const argv = try gpa.alloc([]const u8, cfg.shell.len + 1);
    defer gpa.free(argv);

    // copy the bytes from cfg.shell into argv and append the cmd
    @memcpy(argv[0..cfg.shell.len], cfg.shell);
    argv[cfg.shell.len] = cmd;

    if (comptime builtin.mode == .Debug) {
        const argv_joined = try std.mem.join(gpa, " ", argv);
        defer gpa.free(argv_joined);
        logger.debug("child process argv: {s}", .{argv_joined});
    }

    const res = if (cfg.file_dir) |cwd| 
        try std.process.run(gpa, io, .{ .argv = argv, .cwd = .{ .path = cwd } })
    else
        try std.process.run(gpa, io, .{ .argv = argv });

    defer gpa.free(res.stdout);
    defer gpa.free(res.stderr);
    
    if (!cfg.quiet) {
        const output = try std.mem.concat(gpa, u8, &.{res.stdout, res.stderr});
        defer gpa.free(output);

        if (parallel) 
            try logger.log_mutex.lock(io);

        defer if (parallel) logger.log_mutex.unlock(io);
        try std.Io.File.stdout().writeStreamingAll(io, output);
    }

    return switch (res.term) {
        .exited => |code| if (code != 0) error.CommandFailed,
        else => error.CommandFailed,
    };
}
