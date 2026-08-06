const std = @import("std");
const parser = @import("parser.zig");
const logger = @import("logger.zig");
const scheduler = @import("scheduler.zig");
const variables = @import("variables.zig");
const colors = @import("colors.zig");
const config = @import("config.zig");

pub fn runTask(arena: std.mem.Allocator, gpa: std.mem.Allocator, io: std.Io, ast: []const parser.Ast, cfg: *config.Config, prs: *const parser.Parser) !void {
    if (cfg.task == null) {
        cfg.task = prs.default_task orelse {
            logger.err("no task selected", .{});
            return error.MissingTask;
        };
    }

    for (ast) |node| {
        switch (node) {
            .TaskDecl => |task| {
                if (!std.mem.eql(u8, task.name, cfg.task.?)) continue;

                const vars = variables.Vars.buildMap(arena, io, ast) catch |e| {
                    logger.err("failed to build variable map", .{});
                    logger.debug("{s}", .{@errorName(e)});
                    return e;
                };

                var batch: std.ArrayList([]const u8) = .empty;
                var parallel = false;

                try runSteps(arena, gpa, io, task.steps, cfg, &vars, &batch, &parallel);

                if (batch.items.len > 0)
                    try scheduler.scheduleCommands(io, gpa, batch.items, cfg);

                if (!scheduler.had_work)
                    logger.info("nothing to do for task {s}'{s}'{s}", .{ colors.get(.bold), cfg.task.?, colors.get(.reset) });

                return;
            },
            else => {},
        }
    }

    logger.err("task {s}'{s}'{s} doesn't exist.", .{colors.get(.bold), cfg.task.?, colors.get(.reset)});
    return error.InvalidTask;
}

fn runSteps(
    arena: std.mem.Allocator,
    gpa: std.mem.Allocator,
    io: std.Io,
    steps: []const parser.Step,
    cfg: *config.Config,
    vars: *const variables.Vars,
    batch: *std.ArrayList([]const u8),
    parallel: *bool) !void {

    for (steps) |step| {
        switch (step) {
            .directive => |d| {
                switch (d) {
                    .sequential => {
                        if (parallel.* and batch.items.len > 0) {
                            try scheduler.scheduleCommands(io, gpa, batch.items, cfg);
                            batch.clearRetainingCapacity();
                        }
                        parallel.* = false;
                    },
                    .parallel => parallel.* = true,
                    else => unreachable,
                }
                logger.debug("parallel = {}", .{ parallel.* });
            },
            .cmd => |cmd| {
                const expanded = if (!cfg.no_expand) try vars.expand(cmd, cfg.task.?) else cmd;

                if (parallel.*)
                    try batch.append(arena, expanded)
                else 
                    try scheduler.scheduleCommands(io, gpa, &.{expanded}, cfg);
            },
            .if_block => |block| {
                if (try block.selectBlock(vars)) |selected_steps|
                    try runSteps(arena, gpa, io, selected_steps, cfg, vars, batch, parallel);
            },
        }
    }
}
