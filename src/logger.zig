const std = @import("std");
const builtin = @import("builtin");
const globals = @import("globals.zig");

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

    colors_enabled: bool = false,
    build_file: []const u8 = "",
};

pub fn init() void {
    if (Config.current.is_inited) return;

    const stdout = std.Io.File.stdout();
    const is_tty = stdout.isTty(globals.init.io) catch false;
    const is_dumb = globals.init.environ_map.get("DUMB");

    const ansi = if (is_tty and builtin.os.tag == .windows) br: {        
        std.Io.File.stdout().enableAnsiEscapeCodes(globals.init.io) catch {};
        break :br stdout.supportsAnsiEscapeCodes(globals.init.io) catch false;
    } else is_tty and (is_dumb == null or !std.mem.eql(u8, is_dumb.?, "dumb"));

    Config.current = .{
        .is_inited = true,
        .colors_enabled = ansi,
    };
}

pub const Colors = struct {
    pub const reset = "\x1b[0m";
    pub const bold = "\x1b[1m";
    pub const red = "\x1b[31m";
    pub const yellow = "\x1b[33m";
    pub const magenta = "\x1b[35m";

    pub fn get(comptime code: []const u8) []const u8 {
        return if (Config.current.colors_enabled) code else "";
    }
};

pub fn out(level: LogLevel, comptime fmt: []const u8, args: anytype) void {
    outAdv(true, level, null, fmt, args);
}

pub var log_mutex: std.Io.Mutex = .init;

pub fn outLocked(level: LogLevel, comptime fmt: []const u8, args: anytype) void {
    log_mutex.lock(globals.init.io) catch return;
    defer log_mutex.unlock(globals.init.io);
    out(level, fmt, args);
}

pub fn outAdv(nl: bool, level: LogLevel, line: ?usize, comptime fmt: []const u8, args: anytype) void {
    if ((level == .debug and builtin.mode != .Debug) or !Config.current.is_inited) return;

    var stdout_writer = std.Io.File.stdout().writer(globals.init.io, &.{});
    var stderr_writer = std.Io.File.stderr().writer(globals.init.io, &.{});

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
        .warning => Colors.get(Colors.yellow),
        .err, .syntax => Colors.get(Colors.red),
        .debug => Colors.get(Colors.magenta),
    };

    if (line != null)
        output.print(
            "{s}:{d}: {s}{s}{s}" ++ fmt ++ "{s}",
            .{
                Config.current.build_file,
                line.?,
                color_code,
                prefix,
                Colors.get(Colors.reset) 
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
                Colors.get(Colors.reset)
            } ++ args ++ .{
                if (nl) "\n" else "" 
            },
        ) catch return;
}
