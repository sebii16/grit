const std = @import("std");
const builtins = @import("builtins.zig");
const logger = @import("logger.zig");

pub const Operator = enum {
    eq,
    neq,
};

pub const Condition = struct {
    left: []const u8,
    op: Operator,
    right: []const u8,
    right_is_string: bool,

    pub fn isTrue(self: *const Condition) bool { 
        for (builtins.builtin_variables) |v| {
            if (!std.mem.eql(u8, v.name, self.left))
                continue;

            return switch (self.op) {
                .eq => std.mem.eql(u8, v.value.?, self.right),
                .neq => !std.mem.eql(u8, v.value.?, self.right)
            };
        }

        logger.out(.warning, "{s} is undefined and if statement is therefore always false", .{self.left});

        return false;
    }
};
