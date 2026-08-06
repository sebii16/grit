const std = @import("std");
const variables = @import("variables.zig");
const logger = @import("logger.zig");
const util = @import("util.zig");
const colors = @import("colors.zig");
const parser = @import("parser.zig");

pub const Operator = enum {
    eq,     // ==
    neq,    // !=
    lt,     // <
    lte,    // <=
    gt,     // >
    gte,    // >=

    fn asString(self: @This(), buf: []u8) []const u8 {
        const str = switch (self) {
            .eq => "==",
            .neq => "!=",
            .lt => "<",
            .lte => "<=",
            .gt => ">",
            .gte => ">="
        };

        return std.fmt.bufPrint(buf, "{s}", .{str}) catch "";
    }
};

pub const IfBlock = struct {
    condition: ?Condition,
    steps: []parser.Step,
    next: ?*IfBlock = null,

    pub fn selectBlock(self: *const @This(), vars: *const variables.Vars) !?[]const parser.Step {
        var current: ?*const @This() = self;

        while (current) |block| : (current = block.next) {
            if (block.condition == null) {
                return block.steps;
            }

            if (try block.condition.?.evaluate(vars)) {
                return block.steps;
            }
        }

        return null;
    }
};

pub const Condition = struct {
    line: u32,

    lhs: []const u8,
    op: Operator,
    rhs: []const u8,
    right_is_string: bool,
    result: ?bool = null,

    pub fn create(line: u32, lhs: []const u8, op: Operator, rhs: []const u8, right_is_string: bool) Condition {
        return .{ 
            .line = line,
            .lhs = lhs,
            .op = op,
            .rhs = rhs,
            .right_is_string = right_is_string,
        };
    }

    pub fn evaluate(self: *const @This(), vars: *const variables.Vars) !bool { 
        if (self.result) |res|
            return res;

        const value = variables.Vars.getVariable(vars, self.lhs) catch {
            logger.syntax(self.line, "'{s}' is undefined", .{self.lhs});
            return error.UndefinedVariable;
        };

        return switch (value) {
            .string => |s| blk: {
                if (!self.right_is_string) {
                    logger.syntax(
                        self.line,
                        "expected a string, got identifier {s}'{s}'{s}. did you mean {s}\"{s}\"{s}?",
                        .{colors.get(.bold), self.rhs, colors.get(.reset), colors.get(.bold), self.rhs, colors.get(.reset)}
                    );
                    return error.TypeMismatch;
                }
                break :blk compareString(s, self.op, self.rhs);
            },
            .version => |ver| self.compareVersion(ver),
            .boolean => |b| self.compareBool(b),
        } catch |err| {
            switch (err) {
                error.WrongOperator => {
                    var buf: [2]u8 = undefined;
                    logger.syntax(
                        self.line,
                        "invalid operator {s}'{s}'{s} for variable {s}'{s}'{s} of underlying type {s}'{s}'{s}",
                        .{
                            colors.get(.bold),
                            self.op.asString(&buf),
                            colors.get(.reset),
                            colors.get(.bold),
                            self.lhs,
                            colors.get(.reset),
                            colors.get(.bold),
                            @tagName(std.meta.activeTag(value)),
                            colors.get(.reset),
                        }
                    );
                },
                else => {},
            }
            return err;
        };
    }

    fn compareBool(self: *const @This(), lhs: bool) !bool {
        const rhs_parsed = util.parseBool(self.rhs) catch |e| {
            logger.syntax(self.line, "'{s}' is not a valid boolean", .{self.rhs});
            return e;
        };

        return switch (self.op) {
            .eq => rhs_parsed == lhs,
            .neq => rhs_parsed != lhs,
            else => error.WrongOperator,
        };
    }

    fn compareVersion(self: *const @This(), lhs: std.SemanticVersion) !bool {
        const rhs_ver = std.SemanticVersion.parse(self.rhs) catch |e| {
            logger.syntax(self.line, "'{s}' is not a valid version", .{self.rhs});
            return e;
        };

        const order = lhs.order(rhs_ver);

        return switch (self.op) {
            .eq => order == .eq,
            .neq => order != .eq,
            .lt => order == .lt,
            .lte => order != .gt,
            .gt => order == .gt,
            .gte => order != .lt,
        };
    }

    fn compareString(lhs: []const u8, op: Operator, rhs: []const u8) !bool {
        return switch (op) {
            .eq => std.mem.eql(u8, lhs, rhs),
            .neq => !std.mem.eql(u8, lhs, rhs),
            else => error.WrongOperator,
        };
    }
};
