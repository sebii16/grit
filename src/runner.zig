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
    threads: ?usize = null,
    parallel: bool = false,
    rule_name: ?[]const u8 = null,
    ignore_errors: bool = false,
};

fn expand_vars(input: []const u8, rule_name: []const u8, vars: *const parser.VarMap) ![]u8 {
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
                try handle_undefined_var(input, rule_name, var_name, start, end);

            try expanded.appendSlice(globals.init.arena.allocator(), value);

            i = end - 1;
            continue;
        }
        expanded.appendAssumeCapacity(c);
    }

    return try expanded.toOwnedSlice(globals.init.arena.allocator());
}

fn handle_undefined_var(full_input: []const u8, rule_name: []const u8, var_name: []const u8, start: usize, end: usize) ![]const u8 {
    const builtin_var = builtins.get_variables(var_name) orelse {
        logger.out(.syntax, "undefined variable in rule {s}'{s}'{s}:\n", .{ color.get(color.bold), rule_name, color.get(color.reset) });

        logger.out(.info, "{s}", .{full_input});

        if (start > 1) {
            logger.out_adv(false, .info, null, "\x1b[{d}C", .{ start - 1});
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

pub fn run_build_rule(ast: []const parser.Ast, config: *Config, prs: *const parser.Parser) !void {
    const rule = config.rule_name orelse prs.default_rule orelse {
        logger.out(.err, "no build rule selected", .{});
        return error.InvalidRule;
    };

    const vars = try parser.Ast.make_var_map(ast);
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
                        .parallel => {},
                    }
                }

                if (!has_cmd) {
                    logger.out(.warning, "build rule {s}'{s}'{s} is empty", .{
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

                for (r.steps) |step| {
                    switch (step) {
                        .parallel => |enabled| {
                            if (config.parallel and !enabled and batch.items.len > 0) {
                                try threading.run_commands(batch.items, config);
                                batch.clearRetainingCapacity();
                            }

                            config.parallel = enabled;
                        },
                        .cmd => |cmd| {
                            const expanded = if (!config.no_expand) try expand_vars(cmd, rule, &vars) else cmd;

                            if (config.parallel)
                                try batch.append(globals.init.arena.allocator(), expanded)
                            else 
                                try threading.run_commands(&.{expanded}, config);
                        },
                    }
                }

                if (batch.items.len > 0) {
                    try threading.run_commands(batch.items, config);
                }

                return;
            },
            else => {},
        }
    }

    logger.out_adv(true, .err, null, "build rule {s}'{s}'{s} doesn't exist.", .{color.get(color.bold), rule, color.get(color.reset)});
    return error.InvalidRule;
}
