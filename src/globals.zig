const std = @import("std");
const builtin = @import("builtin");
pub const os = builtin.target.os.tag;
pub const arch = builtin.target.cpu.arch;

pub const default_file = "gritfile";
pub const max_name_length = 256;

pub const ver = std.SemanticVersion{
    .major = 0,
    .minor = 8,
    .patch = 3
};

pub const ver_str = std.fmt.comptimePrint("{d}.{d}.{d}", .{ ver.major, ver.minor, ver.patch });

pub const ver_msg =
    "grit " ++ ver_str ++  " (" ++ @tagName(os) ++ " " ++ @tagName(arch) ++ ")" ++ (if (builtin.mode == .Debug) " [Debug build]" else "") ++
    \\
    \\Copyright (c) 2026 sebii16
    \\Licensed under the MIT License - see LICENSE for more info.
    ;
