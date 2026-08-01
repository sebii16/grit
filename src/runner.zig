const std = @import("std");
const parser = @import("parser.zig");
const logger = @import("logger.zig");
const globals = @import("globals.zig");
const threading = @import("threading.zig");
const variables = @import("variables.zig");
const colors = @import("colors.zig");

pub const Config = struct {
    build_file: []const u8 = globals.default_build_file,
    dry_run: bool = false,
    no_expand: bool = false,
    threads: usize = 0,
    parallel: bool = false,
    rule_name: ?[]const u8 = null,
    ignore_errors: bool = false,
};

pub fn runBuildRule(allocator: std.mem.Allocator, io: std.Io, ast: []const parser.Ast, config: *Config, prs: *const parser.Parser) !void {
    const rule_name = config.rule_name orelse prs.default_rule orelse {
        logger.out(.err, "no build rule selected", .{});
        return error.InvalidRule;
    };

    for (ast) |node| {
        switch (node) {
            .RuleDecl => |rule| {
                if (!std.mem.eql(u8, rule.name, rule_name)) continue;

                logger.out(.info, "executing build rule {s}'{s}'{s}{s}{s}{s}", .{
                    colors.get(.bold),
                    rule_name,
                    colors.get(.reset),
                    if (config.no_expand) " [no-expand]" else "",
                    if (config.dry_run) " [dry-run]" else "",
                    if (config.ignore_errors) " [ignore-errors]" else ""
                });

                const vars = variables.Vars.buildMap(allocator, io, ast) catch |e| {
                    logger.out(.err, "failed to build variable map", .{});
                    logger.out(.debug, "{s}", .{@errorName(e)});
                    return e;
                };
                var batch: std.ArrayList([]const u8) = .empty;

                try runSteps(allocator, rule.steps, config, &vars, &batch, rule_name);

                if (batch.items.len > 0) {
                    try threading.runCommands(globals.gpa, batch.items, config);
                }

                return;
            },
            else => {},
        }
    }

    logger.out(.err, "build rule {s}'{s}'{s} doesn't exist.", .{colors.get(.bold), rule_name, colors.get(.reset)});
    return error.InvalidRule;
}

fn runSteps(
    allocator: std.mem.Allocator,
    steps: []const parser.Step,
    config: *Config,
    vars: *const variables.Vars,
    batch: *std.ArrayList([]const u8),
    rule: []const u8) !void {

    for (steps) |step| {
        switch (step) {
            .directive => |d| {
                switch (d) {
                    .sequential => {
                        if (config.parallel and batch.items.len > 0) {
                            try threading.runCommands(globals.gpa, batch.items, config);
                            batch.clearRetainingCapacity();
                        }
                        config.parallel = false;
                    },
                    .parallel => config.parallel = true,
                    .@"if" => {},
                    else => unreachable,
                }
                logger.out(.debug, "parallel = {}", .{ config.parallel });
            },
            .cmd => |cmd| {
                const expanded = if (!config.no_expand) try vars.expand(cmd, rule) else cmd;

                if (config.parallel)
                    try batch.append(allocator, expanded)
                else 
                    try threading.runCommands(globals.gpa, &.{expanded}, config);
            },
            .if_block => |block| {
                if (try block.selectBlock(globals.gpa, vars)) |selected_steps| {
                    if (selected_steps.len == 0) {
                        logger.out(.info, "nothing to do for build rule {s}'{s}'{s}", .{
                            colors.get(.bold),
                            rule,
                            colors.get(.reset)
                        });
                        return;
                    }

                    try runSteps(allocator, selected_steps, config, vars, batch, rule);
                }
            },
        }
    }
}
