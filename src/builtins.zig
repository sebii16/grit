const std = @import("std");
const c = @cImport({
    @cInclude("time.h");
});
const globals = @import("globals.zig");
const builtin = @import("builtin");

const BuiltinVariable = struct {
    name: []const u8,
    value: ?[]const u8
};

pub const builtin_variables = [_]BuiltinVariable{
    .{ .name = "OS", .value = @tagName(builtin.os.tag) },
    .{ .name = "ARCH", .value = @tagName(builtin.cpu.arch) },
    .{ .name = "TIME", .value = null }, 
    .{ .name = "DATE", .value = null },
};

const RuntimeVariable = enum {
    DATE,
    TIME,
};

pub fn getBuiltinVariable(variable: []const u8) ?[]const u8 {
    for (builtin_variables) |v| {
        if (!std.mem.eql(u8, v.name, variable))
            continue;

        if (v.value) |value| 
            return value;

        const runtime_var = std.meta.stringToEnum(RuntimeVariable, v.name) orelse return null;

        return getRuntimeVariable(runtime_var);
    }
    return null;
}

fn getRuntimeVariable(variable_type: RuntimeVariable) ?[]const u8 {
    var time: c.time_t = c.time(null);
    const tm = c.localtime(&time) orelse return null;
    var buf: [10]u8 = undefined;

    const res = switch (variable_type) {
        .DATE => std.fmt.bufPrint(&buf, "{d:0>2}.{d:0>2}.{d:0>2}", .{
            @as(u32, @intCast(tm.*.tm_mday)),
            @as(u32, @intCast(tm.*.tm_mon + 1)),
            @as(u32, @intCast(tm.*.tm_year + 1900)),
        }) catch return null,

        .TIME => std.fmt.bufPrint(&buf, "{d:0>2}:{d:0>2}", .{
            @as(u32, @intCast(tm.*.tm_hour)),
            @as(u32, @intCast(tm.*.tm_min)),
        }) catch return null,
    };

    return globals.init.arena.allocator().dupe(u8, res) catch null;
}
