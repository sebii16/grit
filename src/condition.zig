const std = @import("std");
const variables = @import("variables.zig");
const logger = @import("logger.zig");

pub const Operator = enum {
    eq,     // ==
    neq,    // !=
    lt,     // <
    lte,    // <=
    gt,     // >
    gte,     // >=

    fn asString(self: @This(), buf: []u8) []const u8 {
        const str = switch (self) {
            .eq => "==",
            .neq => "!=",
            .lt => "<",
            .lte => "<=",
            .gt => ">",
            .gte => ">="
        };

        return std.fmt.bufPrint(buf, "{s}", .{str}) catch &.{};
    }
};

pub const Condition = struct {
    left: []const u8,
    op: Operator,
    right: []const u8,
    //right_is_string: bool,

    pub fn isMet(self: *const Condition, io: std.Io, gpa: std.mem.Allocator) bool { 
        for (variables.builtin_variables) |v| {
            if (!std.mem.eql(u8, v.name, self.left))
                continue;

            var allocated_value: ?variables.Value = null;
            defer if (allocated_value) |av| {
                switch (av) {
                    .string => {
                        logger.out(.debug, "free {s}", .{av.string});
                        gpa.free(av.string);
                    },
                    else => unreachable,
                }
            };

            const value = v.value orelse blk: {
                const resolved = variables.Value{.string = variables.getRuntimeVariable(v.name, io, gpa) catch break };
                allocated_value = resolved;
                break :blk resolved;
            };

            return switch (value) {
                .string => |s| compareString(self.op, s, self.right),
                .version => |ver| compareVersion(self.op, ver, self.right),
                else => false,
            } catch |err| {
                switch (err) {
                    error.WrongOperator => {
                        var buf: [2]u8 = undefined;
                        logger.out(
                            .err,
                            "operator '{s}' is invalid for variable '{s}' of type '{s}'",
                            .{self.op.asString(&buf), self.left, ""}
                        );
                    },
                    else => {},
                }
                return false;
            };
        }

        logger.out(.warning, "'{s}' is undefined - skipping if block", .{self.left});

        return false;
    }

    fn compareVersion(op: Operator, lhs: std.SemanticVersion, rhs: []const u8) !bool {
        const rhs_ver = std.SemanticVersion.parse(rhs) catch {
            logger.out(.err, "'{s}' is not a valid version", .{rhs});
            return error.InvalidVersion;
        };

        const order = lhs.order(rhs_ver);

        return switch (op) {
            .eq => order == .eq,
            .neq => order != .eq,
            .lt => order == .lt,
            .lte => order != .gt,
            .gt => order == .gt,
            .gte => order != .lt
        };
    }

    fn compareString(op: Operator, lhs: []const u8, rhs: []const u8) !bool {
        return switch (op) {
            .eq => std.mem.eql(u8, lhs, rhs),
            .neq => !std.mem.eql(u8, lhs, rhs),
            else => error.WrongOperator,
        };
    }
};
