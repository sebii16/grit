const std = @import("std");
const parser = @import("parser.zig");
const logger = @import("logger.zig");
const scheduler = @import("scheduler.zig");
const variables = @import("variables.zig");
const colors = @import("colors.zig");
const config = @import("config.zig");

pub fn runBuildRule(arena: std.mem.Allocator, gpa: std.mem.Allocator, io: std.Io, ast: []const parser.Ast, cfg: *config.Config, prs: *const parser.Parser) !void {
    if (cfg.rule == null) {
        cfg.rule = prs.default_rule orelse {
            logger.err("no build rule selected", .{});
            return error.InvalidRule;
        };
    }

    for (ast) |node| {
        switch (node) {
            .RuleDecl => |rule| {
                if (!std.mem.eql(u8, rule.name, cfg.rule.?)) continue;

                logger.info("executing build rule {s}'{s}'{s}{s}{s}{s}", .{
                    colors.get(.bold),
                    cfg.rule.?,
                    colors.get(.reset),
                    if (cfg.no_expand) " [no-expand]" else "",
                    if (cfg.dry_run) " [dry-run]" else "",
                    if (cfg.ignore_errors) " [ignore-errors]" else ""
                });

                const vars = variables.Vars.buildMap(arena, io, ast) catch |e| {
                    logger.err("failed to build variable map", .{});
                    logger.debug("{s}", .{@errorName(e)});
                    return e;
                };

                var batch: std.ArrayList([]const u8) = .empty;
                var parallel = false;

                try runSteps(arena, gpa, io, rule.steps, cfg, &vars, &batch, &parallel);

                if (batch.items.len > 0)
                    try scheduler.scheduleCommands(io, gpa, batch.items, cfg);

                if (!scheduler.had_work)
                    logger.info("nothing to do for build rule {s}'{s}'{s}", .{ colors.get(.bold), cfg.rule.?, colors.get(.reset) });

                return;
            },
            else => {},
        }
    }

    logger.err("build rule {s}'{s}'{s} doesn't exist.", .{colors.get(.bold), cfg.rule.?, colors.get(.reset)});
    return error.InvalidRule;
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
                const expanded = if (!cfg.no_expand) try vars.expand(cmd, cfg.rule.?) else cmd;

                if (parallel.*)
                    try batch.append(arena, expanded)
                else 
                    try scheduler.scheduleCommands(io, gpa, &.{expanded}, cfg);
            },
            .if_block => |block| {
                if (try block.selectBlock(gpa, vars)) |selected_steps|
                    try runSteps(arena, gpa, io, selected_steps, cfg, vars, batch, parallel);
            },
        }
    }
}
