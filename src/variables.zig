const std = @import("std");
const builtin = @import("builtin");
const parser = @import("parser.zig");
const globals = @import("globals.zig");
const logger = @import("logger.zig");
const c = @cImport({
    @cInclude("time.h");
});

const color = logger.Colors;

const BuiltinVariable = struct {
    name: []const u8,
    value: ?[]const u8
};

pub const builtin_variables = [_]BuiltinVariable{
    .{ .name = "OS", .value = @tagName(builtin.os.tag) },
    .{ .name = "ARCH", .value = @tagName(builtin.cpu.arch) },
    .{ .name = "TIME", .value = null }, 
    .{ .name = "DATE", .value = null },
    .{ .name = "CWD", .value = null },
    .{ .name = "GRIT_VER", .value = globals.ver },
};

const RuntimeVariable = enum {
    TIME,
    DATE,
    CWD,

    fn getBuiltinRuntimeVariable(self: @This(), io: std.Io, allocator: std.mem.Allocator) ![]const u8 {
        if (self == .CWD) 
            return try std.process.currentPathAlloc(io, allocator);

        var time: c.time_t = c.time(null);
        const tm = c.localtime(&time) orelse return error.TimeConversionFailed;
        var buf: [10]u8 = undefined;

        const res = switch (self) {
            .DATE => try std.fmt.bufPrint(&buf, "{d:0>2}.{d:0>2}.{d:0>2}", .{
                @as(u32, @intCast(tm.*.tm_mday)),
                @as(u32, @intCast(tm.*.tm_mon + 1)),
                @as(u32, @intCast(tm.*.tm_year + 1900)),
            }),

            .TIME => try std.fmt.bufPrint(&buf, "{d:0>2}:{d:0>2}", .{
                @as(u32, @intCast(tm.*.tm_hour)),
                @as(u32, @intCast(tm.*.tm_min)),
            }),

            .CWD => unreachable,
        };

        return try allocator.dupe(u8, res);
    }
};

pub const VarMap = std.StringHashMap(?[]const u8);

pub const Vars = struct {
    map: VarMap,
    allocator: std.mem.Allocator,
    io: std.Io,

    pub fn init(allocator: std.mem.Allocator, io: std.Io, ast: []const parser.Ast) !@This() {
        var self = @This(){
            .map = VarMap.init(allocator),
            .allocator = allocator, 
            .io = io,
        };

        // disabled because we use an arena allocator right now
        //errdefer self.map.deinit();

        inline for (builtin_variables) |v| try self.map.put(v.name, v.value);

        for (ast) |node| {
            switch (node) {
                .VarDecl => |v| {
                    if (self.map.contains(v.name)) {
                        logger.out(.debug, "ERROR: variable {s}'{s}'{s} redefined THIS IS A BUG AND SHOULD NEVER HAPPEN", .{color.get(color.bold), v.name, color.get(color.reset)});
                        return error.DuplicateVar;
                    }

                    try self.map.put(v.name, v.value);
                },
                else => {},
            }
        }

        return self;
    }

    pub fn expand(self: *const @This(), input: []const u8, rule_name: []const u8) ![]u8 {
        var expanded: std.ArrayList(u8) = .empty;

        const len = input.len;
        var i: usize = 0;

        while (i < len) : (i += 1) {
            const char = input[i];

            // literal '$' when we encounter '$$'
            if (char == '$' and i + 1 < input.len and input[i + 1] == '$') {
                try expanded.append(self.allocator, '$');
                i += 1;
                continue;
            }

            if (char == '$') {
                const start = i + 1;
                var end = start;

                // increment end as long as character is valid [A-Z/a-z/0-9/_]
                while (end < input.len and (std.ascii.isAlphanumeric(input[end]) or input[end] == '_')) : (end += 1) {}

                // literal $ if not followed by valid character
                if (start == end) {
                    try expanded.append(self.allocator, '$');
                    continue;
                }

                const var_name = input[start..end];
                const value = self.getVariable(var_name) catch |err| 
                    return reportBadVariable(input, rule_name, start, end, err);

                try expanded.appendSlice(self.allocator, value);

                i = end - 1;
                continue;
            }
            try expanded.append(self.allocator, char);
        }

        return try expanded.toOwnedSlice(self.allocator);
    }

    pub fn getVariable(self: *const @This(), name: []const u8) ![]const u8 {
        const value = self.map.get(name) orelse return error.InvalidVariable;

        if (value) |res| {
            logger.out(.debug, "found variable: {s}", .{res});
            return res;
        }

        return (std.meta.stringToEnum(RuntimeVariable, name) orelse return error.BuiltinVariableInternal).getBuiltinRuntimeVariable(self.io, self.allocator);
    }
};

fn reportBadVariable(full_input: []const u8, rule_name: []const u8, start: usize, end: usize, err: anyerror) anyerror {
    logger.out(.syntax, "undefined or invalid variable in rule {s}'{s}'{s}:\n", .{ color.get(color.bold), rule_name, color.get(color.reset) });

    logger.out(.info, "{s}", .{full_input});

    if (start > 1) {
        logger.outAdv(false, .info, null, "\x1b[{d}C", .{ start - 1});
    }

    logger.out(.info, "{s}^{s}{s}", .{
        color.get(color.red),
        ([_]u8{'~'} ** 128)[0..@min(end - start, 128)],
        color.get(color.reset) 
    });

    return err;
}
