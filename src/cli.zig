const std = @import("std");
const logger = @import("logger.zig");
const runner = @import("runner.zig");

pub const Actions = enum {
    help,
    version,
    run,
};

pub const ParsedArgs = struct {
    config: runner.Config = .{},
    action: Actions = .run,
};

pub fn parseArgs(allocator: std.mem.Allocator, args_: std.process.Args) !ParsedArgs {
    var res = ParsedArgs{};

    const args = try args_.toSlice(allocator);

    // skip executable
    var i: usize = 1;

    if (i >= args.len) return res;

    if (args[i][0] != '-') {
        res.config.rule_name = args[i];
        i += 1;
    }

    while (i < args.len) : (i += 1) {
        const arg = args[i];

        if (arg.len < 2 or arg[0] != '-') 
            return cliError("invalid flag '{s}'", .{arg});

        if (res.config.rule_name == null) {
            if (cmp2(arg, "--help", "-h")) {
                res.action = .help;
                return res;
            } else if (cmp2(arg, "--version", "-v")) {
                res.action = .version;
                return res;
            }
        }

        if (cmp2(arg, "--dry-run", "-d")) {
            res.config.dry_run = true;
        } else if (cmp(arg, "--no-expand")) {
            res.config.no_expand = true;
        } else if (cmp2(arg, "--file", "-f")) {
            res.config.build_file = getValue(&i, args) catch return cliError("must specify a file after '{s}'", .{arg});
        } else if (cmp2(arg, "--threads", "-t")) {
            const value = getValue(&i, args) catch return cliError("must specify a number after '{s}'", .{arg});
            const thread_count = std.fmt.parseInt(usize, value, 10) catch return cliError("'{s}' is not a valid number", .{value});

            if (thread_count == 0) {
                logger.out(.warning, "thread count of 0 ignored, using default", .{});
            }
            res.config.threads = thread_count;
        } else if (cmp(arg, "--ignore-errors")) {
            res.config.ignore_errors = true;
        } else if (cmp(arg, "--no-colors")) {
            logger.Config.current.colors = false;
        } else return cliError("invalid flag '{s}'", .{arg});
    }

    return res;
}

inline fn cmp2(haystack: []const u8, needle1: []const u8, needle2: []const u8) bool {
    return std.mem.eql(u8, haystack, needle1) or std.mem.eql(u8, haystack, needle2);
}

inline fn cmp(first: []const u8, second: []const u8) bool {
    return std.mem.eql(u8, first, second);
}

fn getValue(pos: *usize, args: []const []const u8) ![]const u8 {
    if (pos.* + 1 >= args.len) return error.FlagMissingValue;

    pos.* += 1;
    return args[pos.*];
}

inline fn cliError(comptime fmt: []const u8, args: anytype) error{CliError} {
    logger.out(.err, fmt, args);
    return error.CliError;
}
