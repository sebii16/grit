const globals = @import("globals.zig");

pub const Config = struct {
    pub var current: Config = .{};

    build_file: []const u8 = globals.default_build_file,
    dry_run: bool = false,
    no_expand: bool = false,
    threads: usize = 1,
    parallel: bool = false,
    rule_name: ?[]const u8 = null,
    ignore_errors: bool = false,
    no_colors: bool = false,
};
