const logger = @import("logger.zig");
const config = @import("config.zig");

const Colors = enum {
    reset,
    bold,
    red,
    yellow,
    magenta,

    const codes = struct {
        const reset = "\x1b[0m";
        const bold = "\x1b[1m";
        const red = "\x1b[31m";
        const yellow = "\x1b[33m";
        const magenta = "\x1b[35m";
    };
};

pub fn get(comptime color: Colors) []const u8 {
    return if (config.Config.current.no_colors) "" else @field(Colors.codes, @tagName(color));
}
