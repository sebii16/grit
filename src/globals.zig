const std = @import("std");
const logger = @import("logger.zig");
const builtin = @import("builtin");
const os = @tagName(builtin.target.os.tag);
const arch = @tagName(builtin.target.cpu.arch);

pub var init: std.process.Init = undefined;

pub const default_build_file = "build.grit";

pub const ver = "0.6.1";

pub const ver_msg =
    "grit " ++ ver ++  " (" ++ os ++ " " ++ arch ++ ")" ++ if (builtin.mode == .Debug) " [Debug build]" else "" ++
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
    \\  -d, --dry       Print commands without executing them.
    \\  -f, --file      Specify the build file (default = build.grit).
    \\  -r, --rule      Specify the build rule.
    \\  -t, --threads   Specify the max. amount of threads (default = CPU core count).
    \\  --ignore-errors Ignore execution errors.
    \\  --no-colors     Disable colors.
    \\  --no-expand     Disable variable expansion.
    \\
    \\Global flags: 
    \\  -h, --help      Print help message.
    \\  -v, --version   Print version and license information.
    ;
