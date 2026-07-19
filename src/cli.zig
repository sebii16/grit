const std = @import("std");
const globals = @import("globals.zig");
const logger = @import("logger.zig");
const builtin = @import("builtin");
const runner = @import("runner.zig");

pub const Actions = enum {
    Help,
    Version,
    Run,
    List,
};

pub const ParsedArgs = struct {
    config: runner.Config = .{},
    action: Actions = .Run,
};

pub fn parse_args() !ParsedArgs {
    var res = ParsedArgs{};

    const args = try globals.init.minimal.args.toSlice(globals.init.arena.allocator());

    for (args, 0..) |a, i| {
        logger.out_adv(true, .debug, null, "argv[{d}]={s}", .{i, a});
    } 

    var i: usize = 1; // skip exe name

    if (i + 1 > args.len) return res;

    if (args[i][0] != '-') {
        defer i += 1;
        res.config.rule_name = args[i];
    }

    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (arg.len < 2 or arg[0] != '-')
            return cli_error(error.InvalidFlag, "invalid flag '{s}'", .{arg});

        if (res.config.rule_name == null) {
            if (cmp(arg, "--help") or cmp(arg, "-h")) {
                res.action = .Help;
                return res;
            } else if (cmp(arg, "--version") or cmp(arg, "-v")) {
                res.action = .Version;
                return res;
            } else if (cmp(arg, "--list") or cmp(arg, "-l")) {
                res.action = .List;
                return res;
            }
        }

        if (cmp(arg, "--dry") or cmp(arg, "-d")) {
            res.config.dry_run = true;
        } else if (cmp(arg, "--no-expand")) {
            res.config.no_expand = true;
        } else if (cmp(arg, "--file") or cmp(arg, "-f")) {
            res.config.build_file = get_value(&i, args) catch |e| {
                return cli_error(e, "please specify a file after '{s}'", .{arg});
            };
        } else if (cmp(arg, "--rule") or cmp(arg, "-r")) {
            res.config.rule_name = get_value(&i, args) catch |e| {
                return cli_error(e, "please specify a rule name after '{s}'", .{arg});
            };
        } else if (cmp(arg, "--threads") or cmp(arg, "-t")) {
            const value = get_value(&i, args) catch |e| {
                return cli_error(e, "please specify a number after '{s}'", .{arg});
            };

            const thread_count = std.fmt.parseInt(usize, value, 10) catch |e| {
                return cli_error(e, "'{s}' is not a valid number", .{value});
            };

            if (thread_count == 0) {
                logger.out_adv(true, .warning, null, "thread count of 0 ignored, using default", .{});
            }
            res.config.threads = if (thread_count > 0) thread_count else null;
        } else if (cmp(arg, "--ignore-errors")) {
            res.config.ignore_errors = true;
        } else if (cmp(arg, "--no-colors")) {
            logger.Config.current.colors_enabled = false;
        } else return cli_error(error.InvalidFlag, "invalid flag '{s}'", .{arg});
    }

    return res;
}

inline fn cmp(first: []const u8, second: []const u8) bool {
    return std.mem.eql(u8, first, second);
}

fn get_value(pos: *usize, args: []const [:0]const u8) ![:0]const u8 {
    if (pos.* + 1 >= args.len) return error.FlagMissingValue;

    pos.* += 1;
    return args[pos.*];
}

inline fn cli_error(err: anyerror, comptime fmt: []const u8, args: anytype) anyerror {
    logger.out_adv(true, .err, null, fmt, args);
    return err;
}
