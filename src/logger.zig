const std = @import("std");
const builtin = @import("builtin");
const globals = @import("globals.zig");
const colors = @import("colors.zig");

pub const LogLevel = enum {
    info,
    debug,
    warning,
    err,
    syntax,
};

pub const Config = struct {
    pub var current: Config = .{};
    
    is_inited: bool = false,

    colors: bool = false,
    build_file: []const u8 = "",
};

pub fn init(io: std.Io, env: *std.process.Environ.Map) void {
    if (Config.current.is_inited) return;

    const stdout = std.Io.File.stdout();
    const is_tty = stdout.isTty(io) catch false;
    const is_dumb = env.get("DUMB");

    const ansi = if (is_tty and builtin.os.tag == .windows) br: {        
        std.Io.File.stdout().enableAnsiEscapeCodes(io) catch {};
        break :br stdout.supportsAnsiEscapeCodes(io) catch false;
    } else is_tty and (is_dumb == null or !std.mem.eql(u8, is_dumb.?, "dumb"));

    Config.current = .{
        .is_inited = true,
        .colors = ansi,
    };
}

pub fn out(level: LogLevel, comptime fmt: []const u8, args: anytype) void {
    outAdv(true, level, null, fmt, args);
}

pub var log_mutex: std.Io.Mutex = .init;

pub fn outLocked(io: std.Io, level: LogLevel, comptime fmt: []const u8, args: anytype) void {
    log_mutex.lock(io) catch return;
    defer log_mutex.unlock(io);
    out(level, fmt, args);
}

pub fn syntaxError(line: u32, comptime fmt: []const u8, args: anytype) void {
    outAdv(true, .syntax, line, fmt, args);
}

pub fn outAdv(nl: bool, level: LogLevel, line: ?u32, comptime fmt: []const u8, args: anytype) void {
    if ((level == .debug and builtin.mode != .Debug) or !Config.current.is_inited) return;

    var stdout_writer = std.Io.File.stdout().writer(globals.io, &.{});
    var stderr_writer = std.Io.File.stderr().writer(globals.io, &.{});

    var output = if (level == .err or level == .warning)
        &stderr_writer.interface
    else
        &stdout_writer.interface;

    const prefix = switch (level) {
        .info => "",
        .warning => "warning: ",
        .err => "error: ",
        .syntax => "syntax error: ",
        .debug => "debug: ",
    };

    const color_code = switch (level) {
        .info => "",
        .warning => colors.get(.yellow),
        .err, .syntax => colors.get(.red),
        .debug => colors.get(.magenta)
    };

    if (line != null)
        output.print(
            "{s}:{d}: {s}{s}{s}" ++ fmt ++ "{s}",
            .{
                Config.current.build_file,
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
