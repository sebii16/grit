const std = @import("std");
const builtin = @import("builtin");
const os = @tagName(builtin.target.os.tag);
const arch = @tagName(builtin.target.cpu.arch);

pub const default_file = "gritfile";

pub const ver = std.SemanticVersion{
    .major = 0,
    .minor = 8,
    .patch = 0
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
    \\  grit [task] [flags]
    \\  grit [flags]
    \\
    \\If no task is specified, grit executes the default one (marked with @default).
    \\
    \\Flags:
    \\  -h, --help          Show this help message and exit.
    \\  -v, --version       Show version, license information and exit.
    \\  -d, --dry-run       Print commands without executing them.
    \\  -f, --file FILE     Override file to read from (default: gritfile).
    \\  -t, --threads NUM   Override the max. number of threads (default: CPU core count).
    \\  -e, --eval SRC      Execute SRC instead of reading from a file.          
    \\  -i, --ignore-errors Treat execution errors as warnings.
    \\  -q, --quiet         Only print errors.
    \\  -s, --shell SHELL   Set the shell used to execute commands (e.g. -s "powershell.exe -c").
    \\      --no-colors     Disable colored output.
    \\      --no-expand     Disable variable expansion.
    ;
