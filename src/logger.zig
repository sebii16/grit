const std = @import("std");
const builtin = @import("builtin");
const colors = @import("colors.zig");
const config = @import("config.zig");
const globals = @import("globals.zig");

var io: std.Io = undefined;

pub fn init(cfg: *config.Config, io_: std.Io, env: *std.process.Environ.Map) void {
    io = io_;

    const stdout = std.Io.File.stdout();
    const is_tty = stdout.isTty(io) catch false;
    const term_env = env.get("TERM");

    cfg.no_colors = !if (is_tty and comptime globals.os == .windows) br: {
        std.Io.File.stdout().enableAnsiEscapeCodes(io) catch {};
        break :br stdout.supportsAnsiEscapeCodes(io) catch false;
    } else is_tty and (term_env == null or !std.mem.eql(u8, term_env.?, "dumb"));
}

const LogLevel = enum {
    none,
    info,
    debug,
    warning,
    err,
    syntax,
};

pub fn info(comptime fmt: []const u8, args: anytype) void {
    out(true, .info, null, fmt, args);
}

pub inline fn debug(comptime fmt: []const u8, args: anytype) void {
    if (comptime builtin.mode == .Debug)
        out(true, .debug, null, fmt, args);
}

pub fn warning(comptime fmt: []const u8, args: anytype) void {
    out(true, .warning, null, fmt, args);
}

pub fn err(comptime fmt: []const u8, args: anytype) void {
    out(true, .err, null, fmt, args);
}

pub fn syntax(line: ?u32, comptime fmt: []const u8, args: anytype) void {
    out(true, .syntax, line, fmt, args);
}

pub var log_mutex: std.Io.Mutex = .init;

pub fn outLocked(level: LogLevel, lock: bool, comptime fmt: []const u8, args: anytype) void {
    if (lock)
        log_mutex.lock(io) catch return;

    defer if (lock)
        log_mutex.unlock(io);

    out(true, level, null, fmt, args);
}

pub fn out(nl: bool, level: LogLevel, line: ?u32, comptime fmt: []const u8, args: anytype) void {
    if (builtin.is_test or (level != .err and config.Config.current.quiet)) return;
    
    var stdout_writer = std.Io.File.stdout().writer(io, &.{});
    var stderr_writer = std.Io.File.stderr().writer(io, &.{});
    
    var output = switch (level) {
        .err, .warning => &stderr_writer.interface,
        else => &stdout_writer.interface,
    };

    const prefix = switch (level) {
        .none => "",
        .info => "[info] ",
        .debug => "[debug] ",
        .warning => "warning: ",
        .err => "error: ",
        .syntax => "syntax error: ",
    };

    const color_code = switch (level) {
        .none => "",
        .info => colors.get(.green_bold),
        .warning => colors.get(.yellow_bold),
        .err, .syntax => colors.get(.red_bold),
        .debug => colors.get(.magenta_bold)
    };

    if (line != null)
        output.print(
            "{s}:{d}: {s}{s}{s}" ++ fmt ++ "{s}",
            .{
                config.Config.current.file_name,
                line.?,
                color_code,
                prefix,
                colors.get(.reset)
            } ++ args ++ .{
                if (nl) "\n" else "" 
            },
        ) catch return
    else
        output.print(
            "{s}{s}{s}" ++ fmt ++ "{s}",
            .{
                color_code,
                prefix,
                colors.get(.reset)
            } ++ args ++ .{
                if (nl) "\n" else "" 
            },
        ) catch return;
}
