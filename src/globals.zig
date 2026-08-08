const std = @import("std");
const builtin = @import("builtin");
const os = @tagName(builtin.target.os.tag);
const arch = @tagName(builtin.target.cpu.arch);

pub const default_file = "gritfile";
pub const max_name_length = 256;

pub const ver = std.SemanticVersion{
    .major = 0,
    .minor = 8,
    .patch = 1
};

pub const ver_str = std.fmt.comptimePrint("{d}.{d}.{d}", .{ ver.major, ver.minor, ver.patch });

pub const ver_msg =
    "grit " ++ ver_str ++  " (" ++ os ++ " " ++ arch ++ ")" ++ (if (builtin.mode == .Debug) " [Debug build]" else "") ++
    \\
    \\Copyright (c) 2026 sebii16
    \\Licensed under the MIT License - see LICENSE for more info.
    ;
