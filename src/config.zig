const globals = @import("globals.zig");
const builtin = @import("builtin");

pub const ThreadCount = union(enum) {
    auto,
    count: usize,
};

const default_shell: []const []const u8 = switch (globals.os) {
    .windows => &.{ "cmd.exe", "/C" },
    else => &.{ "sh", "-c" },
};

pub const Config = struct {
    pub var current: Config = .{};

    file_dir: ?[]const u8 = null,
    file_name: []const u8 = globals.default_file,
    src: ?[]const u8 = null,
    task: ?[]const u8 = null,
    threads: ThreadCount = .auto,
    shell: []const []const u8 = default_shell,
    dry_run: bool = false,
    no_expand: bool = false,
    ignore_errors: bool = false,
    no_colors: bool = false,
    quiet: bool = false,
    no_discovery: bool = false,
};
