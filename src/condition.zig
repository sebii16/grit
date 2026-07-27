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

    pub fn isMet(self: *const Condition, io: std.Io, gpa: std.mem.Allocator) bool { 
        for (variables.builtin_variables) |v| {
            if (!std.mem.eql(u8, v.name, self.left))
                continue;

            var allocated_value: ?[]const u8 = null;
            defer if (allocated_value) |value| {
                logger.out(.debug, "free allocated_value", .{});
                gpa.free(value);
            };

            const value = v.value orelse blk: {
                const resolved = 
                    (std.meta.stringToEnum(variables.RuntimeVariable, self.left) orelse break).getBuiltinRuntimeVariable(io, gpa) catch break;
                allocated_value = resolved;
                break :blk resolved;

            };

            return switch (self.op) {
                .eq => std.mem.eql(u8, value, self.right),
                .neq => !std.mem.eql(u8, value, self.right)
            };
        }

        logger.out(.warning, "'{s}' is undefined - skipping if block", .{self.left});

        return false;
    }
};
