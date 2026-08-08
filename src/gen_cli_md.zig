const std = @import("std");
const flags = @import("cli.zig").flag_list;

const data = "```text\n" ++ flags ++ "```";

pub fn main(init: std.process.Init) !void {
    try std.Io.Dir.cwd().writeFile(init.io, .{
        .sub_path = "CLI.md",
        .data = data
    });

    std.debug.print("{s}\n", .{data});
}
