const std = @import("std");
const logger = @import("logger.zig");
const config = @import("config.zig");
const colors = @import("colors.zig");
const util = @import("util.zig");

pub const Mode = enum {
    help,
    version,
    run,
    dump_vars,
    list_tasks,
};

const OptionEffect = union(enum) {
    set_field: []const u8,
    set_mode: Mode
};

const OptionCategory = union(enum) {
    general,
    execution
};

const Option = struct {
    long: []const u8,
    description: []const u8,
    expected_arg: ?[]const u8,

    short: ?u8,
    effect: OptionEffect,
    category: OptionCategory

};

fn defOpt(long: []const u8, short: ?u8, arg: ?[]const u8, desc: []const u8, effect: OptionEffect, category: OptionCategory) Option {
    return Option{
        .long = long,
        .short = short,
        .expected_arg = arg,
        .description = desc,
        .effect = effect,
        .category = category
    };
}

const cli_options = [_]Option{
    defOpt("help", 'h', null, "Show this help message and exit.", .{ .set_mode = .help }, .general),
    defOpt("version", 'v', null, "Show version, license information and exit.", .{ .set_mode = .version }, .general),
    defOpt("no-colors", null, null, "Disable colored output.", .{ .set_field = "no_colors" }, .general),

    defOpt("no-discovery", null, null, "Only look for a gritfile in the current directory.", .{ .set_field = "no_discovery" }, .execution),
    defOpt("file", 'f', "FILE", "Override file to read from (default: gritfile).", .{ .set_field = "file_name" }, .execution),
    defOpt("dry-run", 'd', null, "Print commands without executing them.", .{ .set_field = "dry_run" }, .execution),
    defOpt("threads", 't', "NUM", "Set the maximum number of threads (default: CPU core count).", .{ .set_field = "threads" }, .execution),
    defOpt("ignore-errors", 'i', null, "Treat execution errors as warnings.", .{ .set_field = "ignore_errors" }, .execution),
    defOpt("eval", 'e', "SRC", "Execute SRC instead of reading from a file.", .{ .set_field = "src" }, .execution),
    defOpt("quiet", 'q', null, "Only print errors.", .{ .set_field = "quiet" }, .execution),
    defOpt("shell", 's', "SHELL", "Set the shell used to execute commands (e.g. -s \"pwsh.exe -c\").", .{ .set_field = "shell" }, .execution),
    defOpt("no-expand", null, null, "Disable variable expansion.", .{ .set_field = "no_expand" }, .execution),
    defOpt("list", 'l', null, "List all tasks and exit.", .{ .set_mode = .list_tasks }, .execution),
    defOpt("dump-vars", null, null, "List all variables and exit.", .{ .set_mode = .dump_vars }, .execution),
};

pub const flag_list = blk: {
    var max_len: usize = 0;
    const pad = 1;

    for (cli_options) |opt| {
        const len = if (opt.expected_arg) |arg| arg.len + opt.long.len else opt.long.len;
        max_len = @max(max_len, len);
    } 

    var general: []const u8 = "General Options:\n";
    var execution: []const u8 = "Execution Options:\n";

    var general_end: []const u8 = "";
    var execution_end: []const u8 = "";

    for (cli_options) |opt| {
        var append_to_end = false;
        const short = blk1: {
            if (opt.short) |s| {
                break :blk1 std.fmt.comptimePrint("-{c}, ", .{s});
            } else {
                // options that have no short version get appended to the end of its category
                append_to_end = true;
                // 4 spaces instead of "-c, "
                break :blk1 "    ";
            }
        };

        const arg = if (opt.expected_arg) |arg|
            std.fmt.comptimePrint("<{s}>", .{arg})
        else 
            "";

        const len = opt.long.len + arg.len;

        const category = switch (opt.category) {
            .general => if (append_to_end) &general_end else &general,
            .execution => if (append_to_end) &execution_end else &execution
        };

        category.* = category.* ++ std.fmt.comptimePrint("  {s}--{s} {s}{s}{s}\n", .{short, opt.long, arg, " " ** (max_len - len + pad), opt.description});
    }

    break :blk general ++ general_end ++ "\n" ++ execution ++ execution_end;
};

pub const help_msg =
    \\Usage:
    \\  grit [TASK] [OPTIONS]
    \\
    \\If TASK is left empty, Grit uses the default task (marked with @default).
    \\Grit automatically searches the current directory and its parents for a gritfile.
    \\
    \\
    ++ flag_list
;

pub fn parseArgs(arena: std.mem.Allocator, args: []const []const u8, cfg: *config.Config) !Mode {
    // start after executable name
    var i: usize = 1;

    while (i < args.len) : (i += 1) {
        const arg = args[i];

        const option = findOption(arg) orelse {
            // if the encountered arg isnt an option treat it as a task name
            if (arg[0] != '-' and cfg.task == null) {
                cfg.task = arg;
                continue;
            } else return usageError(.unknown_option, arg, null);
        };

        switch (option.effect) {
            .set_mode => |mode| {
                if (cfg.task != null) {
                    // dont allow --help and --version after a task has been provided
                    logger.err("option '{s}{s}{s}' is not allowed after specifying a task", .{colors.get(.bold), arg, colors.get(.reset)});
                    return error.InvalidModeFlag;
                }
                return mode;
            },
            .set_field => |field| {
                inline for (@typeInfo(@TypeOf(cfg.*)).@"struct".fields) |struct_field| {
                    if (std.mem.eql(u8, field, struct_field.name)) 
                        try parseField(arena, cfg, struct_field, args, &i);
                }
            }
        }
    }

    return .run;
}

fn findOption(arg: []const u8) ?Option {
    if (std.mem.startsWith(u8, arg, "--")) {
        // name starts after --
        const name = arg[2..];

        for (cli_options) |opt| {
            if (std.mem.eql(u8, opt.long, name))
                return opt;
        }
    } else if (arg.len == 2 and arg[0] == '-') {
        for (cli_options) |opt| {
            if (opt.short == arg[1])
                return opt;
        }
    }

    return null;
}

fn parseField(arena: std.mem.Allocator, cfg: *config.Config, comptime field: std.builtin.Type.StructField, args: []const []const u8, index: *usize) !void {
    const field_value = &@field(cfg, field.name);

    switch (@typeInfo(field.type)) {
        .bool => {
            field_value.* = true;
        },
        .int => {
            const value = try getValue(index, args);
            field_value.* = std.fmt.parseInt(field.type, value, 10) catch {
                return usageError(.invalid_value, args[index.* - 1], args[index.*]);
            };
        },
        .optional => |optional| {
            if (optional.child == []const u8) {
                field_value.* = try getValue(index, args);
            } else {
                @compileError("unhandled type: " ++ @typeName(field.type));
            }
        },
        .pointer => |pointer| {
            if (pointer.size == .slice and pointer.child == u8) {
                field_value.* = try getValue(index, args);
            } else if (pointer.size == .slice and pointer.child == []const u8) {
                const value = try getValue(index, args);

                field_value.* = try util.splitString(arena, value, ' ');
            } else {
                @compileError("unhandled type: " ++ @typeName(field.type));
            }
        },
        .@"union" => {
            if (field.type == config.ThreadCount) {
                const value = try getValue(index, args);

                const n = std.fmt.parseUnsigned(usize, value, 10) catch {
                    return usageError(.invalid_value, args[index.* - 1], args[index.*]);
                };

                if (n == 0) {
                    logger.warning("thread count of 0 ignored", .{});
                    field_value.* = .auto;
                    return;
                }

                field_value.* = .{ .count = n };
            } else {
                @compileError("unhandled union type: " ++ @typeName(field.type));
            }
        },
        else => @compileError("unhandled type: " ++ @typeName(field.type)),
    }
}

fn getValue(pos: *usize, args: []const []const u8) ![]const u8 {
    const flag = args[pos.*];

    if (pos.* + 1 >= args.len) {
        return usageError(.missing_value, flag, null);
    }

    pos.* += 1;
    return args[pos.*];
}

const WrongUsageType = union(enum) {
    unknown_option,
    missing_value,
    invalid_value
};

fn usageError(wrong_usage_type: WrongUsageType, option: []const u8, arg: ?[]const u8) anyerror {
    defer {
        logger.out(true, .none, null, "\nfor more information use '{s}--help{s}'", .{
            colors.get(.green_bold), colors.get(.reset)
        });
    }

    switch (wrong_usage_type) {
        .unknown_option => {
            logger.err("unknown option '{s}{s}{s}'", .{ colors.get(.red_bold), option, colors.get(.reset) });
            const similar = getSimilarOption(option);
            if (similar) |opt| 
                logger.out(true, .none, null, "\ndid you mean '{s}--{s}{s}'?", .{ colors.get(.green_bold), opt, colors.get(.reset) });

            return error.UnknownOption;
        },
        .missing_value, .invalid_value => {
            const expected_arg = getExpectedArg(option);
            defer logger.out(true, .none, null, "\nusage: '{s}{s} <{s}>{s}'", .{
                colors.get(.green_bold), option, expected_arg, colors.get(.reset)
            });

            switch (wrong_usage_type) {
                .missing_value => {
                    logger.err("option '{s}{s}{s}' expects a value", .{
                        colors.get(.red_bold), option, colors.get(.reset),
                    });
                    return error.OptionMissingValue;
                },
                .invalid_value => {
                    if (arg) |a| {
                        logger.err("invalid value '{s}{s}{s}' for option '{s}{s}{s}'", .{
                            colors.get(.red_bold), a, colors.get(.reset),
                            colors.get(.bold), option, colors.get(.reset)
                        });
                    } else unreachable;

                    return error.OptionReceivedInvalidValue;
                },
                else => unreachable,
            }
        },
    }
}

const SimilarOptions = struct {
    str: ?[]const u8 = null,
    edit_distance: usize = 3
};

fn getSimilarOption(option: []const u8) ?[]const u8 {
    const stripped = std.mem.trimStart(u8, option, "-");
    var best_match: SimilarOptions = .{};

    for (cli_options) |opt| {
        const edit_distance = util.getEditDistance(stripped, opt.long) orelse continue;

        if (edit_distance <= 2 and edit_distance < best_match.edit_distance)
            best_match = .{ .edit_distance = edit_distance, .str = opt.long };
    }

    return best_match.str;
}

fn getExpectedArg(option: []const u8) []const u8 {
    const stripped = std.mem.trimStart(u8, option, "-");

    for (cli_options) |opt| {
        if (!std.mem.eql(u8, if (stripped.len == 1 and opt.short != null) &.{opt.short.?} else opt.long, stripped)) continue;

        return opt.expected_arg orelse break;
    }

    // unreachable because option should be guaranteed to exist and have a expected_arg value set when this function gets called
    unreachable;
}
