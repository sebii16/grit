const std = @import("std");
const builtin = @import("builtin");
const os = @tagName(builtin.target.os.tag);
const arch = @tagName(builtin.target.cpu.arch);

pub var arena: std.mem.Allocator = undefined;
pub var gpa: std.mem.Allocator = undefined;
pub var io: std.Io = undefined;

pub fn init(arena_: std.mem.Allocator, gpa_: std.mem.Allocator, io_: std.Io) void {
    arena = arena_;
    gpa = gpa_;
    io = io_;
}

pub const default_build_file = "build.grit";

pub const ver = std.SemanticVersion{
    .major = 0,
    .minor = 7,
    .patch = 1
};

pub const ver_str = std.fmt.comptimePrint("{d}.{d}.{d}", .{ ver.major, ver.minor, ver.patch });

pub const ver_msg =
    "grit " ++ ver_str ++  " (" ++ os ++ " " ++ arch ++ ")" ++ (if (builtin.mode == .Debug) " [Debug build]" else "") ++
    \\
    \\Copyright (c) 2026 sebii16
    \\Licensed under the MIT License - see LICENSE for more info.
    ;

pub const help_msg =
    \\Usage:
    \\  grit [rule] [build flags]
    \\  grit [build flags]
    \\  grit [global flag]
    \\
    \\If no rule is specified, grit executes the default rule (marked with @default).
    \\
    \\Build flags:
    \\  -d, --dry-run       Print commands without executing them.
    \\  -f, --file FILE     Build file to use (default: build.grit).
    //\\  -r, --rule RULE     Build rule to execute.
    \\  -t, --threads N     Max. number of threads (default: CPU core count).
    \\      --ignore-errors Continue executing after a command fails.
    \\      --no-colors     Disable colored output.
    \\      --no-expand     Disable variable expansion.
    \\
    \\Global flags: 
    \\  -h, --help          Show this help message.
    \\  -v, --version       Show version and license information.
    ;
