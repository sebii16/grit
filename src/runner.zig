const std = @import("std");
const parser = @import("parser.zig");
const logger = @import("logger.zig");
const cli = @import("cli.zig");
const builtin = @import("builtin");
const globals = @import("globals.zig");
const threading = @import("threading.zig");
const variables = @import("variables.zig");
const color = logger.Colors;

pub const Config = struct {
    build_file: []const u8 = globals.default_build_file,
    dry_run: bool = false,
    no_expand: bool = false,
    threads: usize = 0,
    parallel: bool = false,
    rule_name: ?[]const u8 = null,
    ignore_errors: bool = false,
};

pub fn runBuildRule(ast: []const parser.Ast, config: *Config, prs: *const parser.Parser) !void {
    const rule = config.rule_name orelse prs.default_rule orelse {
        logger.out(.err, "no build rule selected", .{});
        return error.InvalidRule;
    };

    for (ast) |node| {
        switch (node) {
            .RuleDecl => |r| {
                if (!std.mem.eql(u8, r.name, rule)) continue;

                var has_cmd = false;

                for (r.steps) |*step| {
                    switch (step.*) {
                        .cmd => {
                            has_cmd = true;
                            break;
                        },
                        .if_block => |*block| {
                            if (block.condition.evaluate()) {
                                block.*.condition.is_met = true;
                                for (block.steps) |bs| {
                                    switch (bs) {
                                        .cmd => {
                                            has_cmd = true;
                                            break;
                                        },
                                        else => {},
                                    }
                                }
                            }
                        },
                        else => {},
                    }
                }

                if (!has_cmd) {
                    logger.out(.info, "nothing to do for build rule {s}'{s}'{s}", .{
                        color.get(color.bold),
                        r.name,
                        color.get(color.reset)
                    });
                    return;
                }

                logger.out(.info, "executing build rule {s}'{s}'{s}{s}{s}{s}", .{
                    color.get(color.bold),
                    rule,
                    color.get(color.reset),
                    if (config.no_expand) " [no-expand]" else "",
                    if (config.dry_run) " [dry-run]" else "",
                    if (config.ignore_errors) " [ignore-errors]" else ""
                });

                const vars = try variables.Vars.init(globals.init.arena.allocator(), globals.init.io, ast);
                var batch: std.ArrayList([]const u8) = .empty;

                try runSteps(r.steps, config, &vars, &batch, rule);

                if (batch.items.len > 0) {
                    try threading.runCommands(batch.items, config);
                }

                return;
            },
            else => {},
        }
    }

    logger.out(.err, "build rule {s}'{s}'{s} doesn't exist.", .{color.get(color.bold), rule, color.get(color.reset)});
    return error.InvalidRule;
}

fn runSteps(steps: []parser.Step, config: *Config, vars: *const variables.Vars, batch: *std.ArrayList([]const u8), rule: []const u8) !void {
    for (steps) |step| {
        switch (step) {
            .directive => |d| {
                switch (d) {
                    .sequential => {
                        if (config.parallel and batch.items.len > 0) {
                            try threading.runCommands(batch.items, config);
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
                    try batch.append(globals.init.arena.allocator(), expanded)
                else 
                    try threading.runCommands(&.{expanded}, config);
            },
            .if_block => |block| {
                if (block.condition.is_met)
                    try runSteps(block.steps, config, vars, batch, rule);
            },
        }
    }
}
