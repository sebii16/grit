const std = @import("std");
const parser = @import("parser.zig");
const logger = @import("logger.zig");
const cli = @import("cli.zig");
const builtin = @import("builtin");
const globals = @import("globals.zig");
const builtins = @import("builtins.zig");
const threading = @import("threading.zig");
const color = logger.Colors;

pub const Config = struct {
    build_file: []const u8 = globals.DEFAULT_BUILD_FILE,
    dry_run: bool = false,
    no_expand: bool = false,
    threads: usize = 0,
    parallel: bool = false,
    rule_name: ?[]const u8 = null,
    ignore_errors: bool = false,
};

const VarMap = std.StringHashMap(?[]const u8);

fn makeVarMap(ast: []const parser.Ast) !VarMap {
    var vars = VarMap.init(globals.init.arena.allocator());

    inline for (builtins.builtin_variables) |v| try vars.put(v.name, v.value);

    for (ast) |node| {
        switch (node) {
            .VarDecl => |v| {
                if (vars.contains(v.name)) {
                    logger.out(.syntax, "variable '{s}' redefined", .{v.name});
                    return error.DuplicateVar;
                }
                try vars.put(v.name, v.value);
            },
            else => {},
        }
    }

    if (builtin.mode == .Debug) {
        logger.out(.debug, "VarMap:", .{});

        var it = vars.iterator();
        while (it.next()) |v| {
            logger.out(.debug, "{s}: {s}", .{v.key_ptr.*, if (v.value_ptr.* != null) v.value_ptr.*.? else "<runtime>"});
        }
    }

    return vars;
}

fn expandVars(input: []const u8, rule_name: []const u8, vars: *const VarMap) ![]u8 {
    var expanded: std.ArrayList(u8) = .empty;
    // defer expanded.deinit(globals.init.arena.allocator());

    try expanded.ensureTotalCapacity(globals.init.arena.allocator(), input.len);

    const len = input.len;
    var i: usize = 0;

    while (i < len) : (i += 1) {
        const c = input[i];

        // dont expand if $ is escaped
        if (c == '$' and i + 1 < input.len and input[i + 1] == '$') {
            expanded.appendAssumeCapacity('$');
            i += 1;
            continue;
        }

        if (c == '$') {
            const start = i + 1;
            var end = start;

            // increment end as long as character is valid [A-Z/a-z/0-9/_]
            while (end < input.len and (std.ascii.isAlphanumeric(input[end]) or input[end] == '_')) : (end += 1) {}

            // treat as literal $ if its not followed by valid character
            if (start == end) {
                expanded.appendAssumeCapacity('$');
                continue;
            }

            const var_name = input[start..end];
            const value = vars.get(var_name) orelse 
                try handleUndefinedVar(input, rule_name, var_name, start, end);

            const resolved_value = value orelse 
                try handleUndefinedVar(input, rule_name, var_name, start, end);

            try expanded.appendSlice(globals.init.arena.allocator(), resolved_value);

            i = end - 1;
            continue;
        }
        expanded.appendAssumeCapacity(c);
    }

    return try expanded.toOwnedSlice(globals.init.arena.allocator());
}

fn handleUndefinedVar(full_input: []const u8, rule_name: []const u8, var_name: []const u8, start: usize, end: usize) ![]const u8 {
    const builtin_var = builtins.getBuiltinVariable(var_name) orelse {
        logger.out(.syntax, "undefined variable in rule {s}'{s}'{s}:\n", .{ color.get(color.bold), rule_name, color.get(color.reset) });

        logger.out(.info, "{s}", .{full_input});

        if (start > 1) {
            logger.outAdv(false, .info, null, "\x1b[{d}C", .{ start - 1});
        }

        logger.out(.info, "{s}^{s}{s}", .{
            color.get(color.red),
            ([_]u8{'~'} ** 128)[0..@min(end - start, 128)],
            color.get(color.reset) 
        });

        return error.InvalidVar;
    };

    return builtin_var;
}

pub fn runBuildRule(ast: []const parser.Ast, config: *Config, prs: *const parser.Parser) !void {
    const rule = config.rule_name orelse prs.default_rule orelse {
        logger.out(.err, "no build rule selected", .{});
        return error.InvalidRule;
    };

    const vars = try makeVarMap(ast);
    var batch: std.ArrayList([]const u8) = .empty;

    for (ast) |node| {
        switch (node) {
            .RuleDecl => |r| {
                if (!std.mem.eql(u8, r.name, rule)) continue;

                var has_cmd = false;

                for (r.steps) |step| {
                    switch (step) {
                        .cmd => {
                            has_cmd = true;
                            break;
                        },
                        .if_block => |block| {
                            for (block.steps) |bs| {
                                switch (bs) {
                                    .cmd => {
                                        has_cmd = true;
                                        break;
                                    },
                                    else => {},
                                }
                            }
                        },
                        else => {},
                    }
                }

                if (!has_cmd) {
                    logger.out(.warning, "nothing to do for build rule {s}'{s}'{s}", .{
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

fn runSteps(steps: []parser.Step, config: *Config, vars: *const VarMap, batch: *std.ArrayList([]const u8), rule: []const u8) !void {
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
                const expanded = if (!config.no_expand) try expandVars(cmd, rule, vars) else cmd;

                if (config.parallel)
                    try batch.append(globals.init.arena.allocator(), expanded)
                else 
                    try threading.runCommands(&.{expanded}, config);
            },
            .if_block => |block| {
                if (block.condition.isTrue()) {
                    try runSteps(block.steps, config, vars, batch, rule);
                }
            },
        }
    }
}
