const std = @import("std");

pub fn parseBool(input: []const u8) error{InvalidBoolean}!bool {
    if (std.mem.eql(u8, input, "true"))
        return true;

    if (std.mem.eql(u8, input, "false"))
        return false;

    return error.InvalidBoolean;
}
