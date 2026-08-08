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
    expected_arg: ?[]const u8 = null,

    short: ?u8 = null,
    effect: OptionEffect,
    category: OptionCategory = .execution,
};

const cli_options = [_]Option{
    // General
    .{
        .long = "help",
        .short = 'h',
        .effect = .{ .set_mode = .help },
        .description = "Show this help message and exit.",
        .category = .general
    },
    .{
        .long = "version",
        .short = 'v',
        .effect = .{ .set_mode = .version },
        .description = "Show version, license information and exit.",
        .category = .general
    },
    .{ 
        .long = "no-colors",
        .effect = .{ .set_field = "no_colors" },
        .description = "Disable colored output.",
        .category = .general
    },
    // Execution
    .{
        .long = "file",
        .short = 'f',
        .effect = .{ .set_field = "file_name" },
        .description = "Override file to read from (default: gritfile).",
        .expected_arg = "FILE"
    },
    .{
        .long = "dry-run",
        .short = 'd',
        .effect = .{ .set_field = "dry_run" },
        .description = "Print commands without executing them.",
    },
    .{
        .long = "threads", 
        .short = 't',
        .effect = .{ .set_field = "threads" },
        .description = "Set the maximum number of threads (default: CPU core count).",
        .expected_arg = "N"
    },
    .{
        .long = "ignore-errors",
        .short = 'i',
        .effect = .{ .set_field = "ignore_errors" },
        .description = "Treat execution errors as warnings."
    },
    .{
        .long = "eval",
        .short = 'e',
        .effect = .{ .set_field = "src" },
        .description = "Execute SRC instead of reading from a file.",
        .expected_arg = "SRC"
    },
    .{
        .long = "quiet",
        .short = 'q',
        .effect = .{ .set_field = "quiet" },
        .description = "Only print errors."
    },
    .{
        .long = "shell",
        .short = 's',
        .effect = .{ .set_field = "shell" },
        .description = "Set the shell used to execute commands (e.g. -s \"pwsh.exe -c\").",
        .expected_arg = "SHELL"
    },
    .{
        .long = "no-expand",
        .effect = .{ .set_field = "no_expand" },
        .description = "Disable variable expansion.",
    },
    .{
        .long = "dump-vars",
        .effect = .{ .set_mode = .dump_vars},
        .description = "List all variables and exit.",
    },
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

    for (cli_options) |opt| {
        const short = if (opt.short) |s| 
            std.fmt.comptimePrint("-{c}, ", .{s})
        else
            // 4 spaces instead of "-c, "
            "    ";

        const arg = if (opt.expected_arg) |arg|
            std.fmt.comptimePrint("<{s}>", .{arg})
        else 
            "";

        const len = opt.long.len + arg.len;

        const category = switch (opt.category) {
            .general => &general,
            .execution => &execution
        };

        category.* = category.* ++ std.fmt.comptimePrint("  {s}--{s} {s}{s}{s}\n", .{short, opt.long, arg, " " ** (max_len - len + pad), opt.description});
    }

    break :blk general ++ "\n" ++ execution;
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
            } else {
                logger.err("unknown flag {s}'{s}'{s}", .{colors.get(.bold), arg, colors.get(.reset)});
                return error.UnknownFlag;
            }
        };

        switch (option.effect) {
            .set_mode => |mode| {
                if (cfg.task != null) {
                    // dont allow --help and --version after a task has been provided
                    logger.err("flag {s}'{s}'{s} is not allowed after specifying a task", .{colors.get(.bold), arg, colors.get(.reset)});
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
                logger.err("{s}'{s}'{s} is not a valid number", .{ colors.get(.bold), value, colors.get(.reset) });
                return error.InvalidNumber;
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
                    logger.err("'{s}' is not a valid thread count", .{value});
                    return error.InvalidNumber;
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
        logger.err("expected a value after flag {s}'{s}'{s}", .{colors.get(.bold), flag, colors.get(.reset)});
        return error.FlagMissingValue;
    }

    pos.* += 1;
    return args[pos.*];
}
