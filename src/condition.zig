const std = @import("std");
const variables = @import("variables.zig");
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
    is_met: bool,

    pub fn evaluate(self: *const Condition) bool { 
        for (variables.builtin_variables) |v| {
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
