const globals = @import("globals.zig");
const builtin = @import("builtin");

pub const ThreadCount = union(enum) {
    auto,
    count: usize,
};

const default_shell: []const []const u8 = switch (builtin.os.tag) {
    .windows => &.{ "cmd.exe", "/C" },
    else => &.{ "sh", "-c" },
};

pub const Config = struct {
    pub var current: Config = .{};

    file_name: []const u8 = globals.default_file,
    file_dir: ?[]const u8 = null,
    dry_run: bool = false,
    no_expand: bool = false,
    threads: ThreadCount = .auto,
    task: ?[]const u8 = null,
    ignore_errors: bool = false,
    no_colors: bool = false,
    quiet: bool = false,
    src: ?[]const u8 = null,
    shell: []const []const u8 = default_shell,
};
