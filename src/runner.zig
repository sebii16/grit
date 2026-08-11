const std = @import("std");
const parser = @import("parser.zig");
const logger = @import("logger.zig");
const scheduler = @import("scheduler.zig");
const variables = @import("variables.zig");
const colors = @import("colors.zig");
const config = @import("config.zig");

pub fn runTask(
    arena: std.mem.Allocator,
    gpa: std.mem.Allocator,
    io: std.Io,
    ast: []const parser.Ast,
    cfg: *config.Config,
    prs: *const parser.Parser,
    vars: *const variables.Vars) !void {

    var is_default_task = false;

    if (cfg.task == null) {
        cfg.task = prs.default_task orelse {
            logger.err("no task selected", .{});
            return error.MissingTask;
        };
        is_default_task = true;
    }

    for (ast) |node| {
        switch (node) {
            .TaskDecl => |task| {
                const has_alias = task.alias != null;

                if (!std.mem.eql(u8, task.name, cfg.task.?) and (!has_alias or !std.mem.eql(u8, task.alias.?, cfg.task.?))) continue;

                var parallel_batch: std.ArrayList([]const u8) = .empty;
                var parallel = false;

                logger.info("selected task: {s}{s}{s}{s}", .{colors.get(.bold), if (is_default_task) "@default " else "", task.name, colors.get(.reset)});

                try processSteps(arena, gpa, io, task.steps, cfg, vars, &parallel_batch, &parallel);

                if (parallel_batch.items.len > 0)
                    try scheduler.scheduleCommands(io, gpa, parallel_batch.items, cfg);

                if (!scheduler.had_work)
                    logger.info("nothing to do for task {s}{s}{s}", .{ colors.get(.bold), cfg.task.?, colors.get(.reset) })
                else 
                    logger.info("all done", .{});

                return;
            },
            else => {},
        }
    }

    logger.err("task {s}'{s}'{s} doesn't exist.", .{colors.get(.bold), cfg.task.?, colors.get(.reset)});
    return error.InvalidTask;
}

fn processSteps(
    arena: std.mem.Allocator,
    gpa: std.mem.Allocator,
    io: std.Io,
    steps: []const parser.Step,
    cfg: *config.Config,
    vars: *const variables.Vars,
    parallel_batch: *std.ArrayList([]const u8),
    parallel: *bool) !void {

    for (steps) |step| {
        switch (step) {
            .directive => |d| {
                switch (d) {
                    .sequential => {
                        if (parallel.* and parallel_batch.items.len > 0) {
                            // execute all commands that are already in parallel_batch before changing to sequential mode
                            try scheduler.scheduleCommands(io, gpa, parallel_batch.items, cfg);
                            parallel_batch.clearRetainingCapacity();
                        }
                        parallel.* = false;
                    },
                    .parallel => parallel.* = true,
                    else => unreachable,
                }
                logger.debug("parallel = {}", .{ parallel.* });
            },
            .cmd => |cmd| {
                const expanded = 
                    if (!cfg.no_expand)
                        vars.expand(gpa, cmd, cfg.task.?) catch |e| {
                            logger.err("variable expansion for command {s}'{s}'{s} failed", .{ colors.get(.bold), cmd, colors.get(.reset) });
                            logger.debug("{s}", .{ @errorName(e) });
                            return e;
                        }
                    else cmd;

                if (parallel.*)
                    try parallel_batch.append(arena, expanded)
                else 
                    try scheduler.scheduleCommands(io, gpa, &.{expanded}, cfg);
            },
            .if_block => |block| {
                if (try block.selectBlock(vars)) |selected_steps|
                    try processSteps(arena, gpa, io, selected_steps, cfg, vars, parallel_batch, parallel);
            },
        }
    }
}
