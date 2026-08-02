const std = @import("std");
const logger = @import("logger.zig");
const config = @import("config.zig");
const colors = @import("colors.zig");

pub const Action = enum {
    help,
    version,
    run,
};

const OptionEffect = union(enum) {
    set_field: []const u8,
    set_action: Action
};

const Option = struct {
    long: []const u8,
    short: ?u8 = null,
    effect: OptionEffect,
};

const cli_options = [_]Option{
    .{ .long = "file", .short = 'f', .effect = .{ .set_field = "build_file" } },
    .{ .long = "dry-run", .short = 'd', .effect = .{ .set_field = "dry_run" } },
    .{ .long = "no-expand", .effect = .{ .set_field = "no_expand" } },
    .{ .long = "threads", .short = 't', .effect = .{ .set_field = "threads" } },
    .{ .long = "ignore-errors", .effect = .{ .set_field = "ignore_errors" } },
    .{ .long = "no-colors", .effect = .{ .set_field = "no_colors" } },
    .{ .long = "help", .short = 'h', .effect = .{ .set_action = .help } },
    .{ .long = "version", .short = 'v', .effect = .{ .set_action = .version } },
};

pub fn parseArgs(args: []const []const u8, cfg: *config.Config) !Action {
    // start after executable name
    var i: usize = 1;

    while (i < args.len) : (i += 1) {
        const arg = args[i];

        const option = findOption(arg) orelse {
            // if the first arg isnt an option treat it as a rule name
            if (i == 1 and arg[0] != '-') {
                cfg.rule_name = arg;
                continue;
            } else {
                logger.out(.err, "unknown flag {s}'{s}'{s}", .{colors.get(.bold), arg, colors.get(.reset)});
                return error.UnknownFlag;
            }
        };

        switch (option.effect) {
            .set_action => |action| {
                if (cfg.rule_name != null) {
                    // dont allow --help and --version after a rule has been provided
                    logger.out(.err, "flag {s}'{s}'{s} is not allowed after declaring a rule", .{colors.get(.bold), arg, colors.get(.reset)});
                    return error.InvalidActionFlag;
                }
                return action;
            },
            .set_field => |field| {
                inline for (@typeInfo(@TypeOf(cfg.*)).@"struct".fields) |struct_field| {
                    if (std.mem.eql(u8, field, struct_field.name)) 
                        try parseField(cfg, struct_field, args, &i);
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

fn parseField(cfg: *config.Config, comptime field: std.builtin.Type.StructField, args: []const []const u8, index: *usize) !void {
    const field_value = &@field(cfg, field.name);

    switch (@typeInfo(field.type)) {
        .bool => {
            field_value.* = true;
        },
        .int => {
            const value = try getValue(index, args);
            field_value.* = std.fmt.parseInt(field.type, value, 10) catch {
                logger.out(.err, "'{s}' is not a valid number", .{value});
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
            } else {
                @compileError("unhandled type: " ++ @typeName(field.type));
            }
        },
        else => @compileError("unhandled type: " ++ @typeName(field.type)),
    }
}

fn getValue(pos: *usize, args: []const []const u8) ![]const u8 {
    const flag = args[pos.*];

    if (pos.* + 1 >= args.len) {
        logger.out(.err, "expected a value after flag {s}'{s}'{s}", .{colors.get(.bold), flag, colors.get(.reset)});
        return error.FlagMissingValue;
    }

    pos.* += 1;
    return args[pos.*];
}
