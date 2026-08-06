const logger = @import("logger.zig");
const config = @import("config.zig");

const Colors = enum {
    reset,
    bold,
    red,
    red_bold,
    yellow,
    yellow_bold,
    magenta,
    magenta_bold,
    green,
    green_bold,

    const codes = struct {
        const reset = "\x1b[0m";
        const bold = "\x1b[1m";
        const red = "\x1b[31m";
        const red_bold = red ++ bold;
        const yellow = "\x1b[33m";
        const yellow_bold = yellow ++ bold;
        const magenta = "\x1b[35m";
        const magenta_bold = magenta ++ bold;
        const green = "\x1b[32m";
        const green_bold = green ++ bold;
    };
};

pub fn get(comptime color: Colors) []const u8 {
    return if (config.Config.current.no_colors) "" else @field(Colors.codes, @tagName(color));
}
