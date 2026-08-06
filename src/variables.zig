const std = @import("std");
const builtin = @import("builtin");
const parser = @import("parser.zig");
const globals = @import("globals.zig");
const logger = @import("logger.zig");
const colors = @import("colors.zig");
const c = @cImport({
    @cInclude("time.h");
});

pub const Value = union(enum) {
    string: []const u8,
    version: std.SemanticVersion,
    boolean: bool,

    pub fn asString(self: @This(), buf: []u8) ![]const u8 {
        return switch (self) {
            .string => |s| s,
            .version => |v| std.fmt.bufPrint(buf, "{d}.{d}.{d}", .{v.major, v.minor, v.patch}),
            .boolean => |b| std.fmt.bufPrint(buf, "{}", .{b}),
        };
    }
};

pub const VarMap = std.StringHashMap(Value);

pub const builtin_variables = [_][]const u8 {
    "OS",
    "ARCH",
    "CWD",
    "GRIT_VER",
    "TIME",
    "DATE",
};


pub const Vars = struct {
    map: VarMap,
    allocator: std.mem.Allocator,
    io: std.Io,

    fn addBuiltinVariables(self: *@This(), io: std.Io, allocator: std.mem.Allocator) !void {
        const cwd = try std.process.currentPathAlloc(io, allocator);

        try self.map.put("OS", .{ .string = @tagName(builtin.os.tag) });
        try self.map.put("ARCH", .{ .string = @tagName(builtin.cpu.arch) });
        try self.map.put("CWD", .{ .string = cwd });
        try self.map.put("GRIT_VER", .{ .version = globals.ver });

        logger.debug("builtin variables added", .{});
    }

    pub fn buildMap(allocator: std.mem.Allocator, io: std.Io, ast: []const parser.Ast) !@This() {
        var self = @This(){
            .map = VarMap.init(allocator),
            .allocator = allocator, 
            .io = io,
        };

        try self.addBuiltinVariables(io, allocator);

        for (ast) |node| {
            switch (node) {
                .VarDecl => |v| {
                    if (self.map.contains(v.name)) {
                        // this error shouldn't be able to happen because parser avoids it
                        logger.debug("ERROR: variable '{s}' redefined THIS IS A BUG AND SHOULD NEVER HAPPEN HERE", .{v.name});
                    }

                    try self.map.put(v.name, .{ .string = v.value });
                },
                else => {},
            }
        }

        logger.debug("all variables initialized", .{});

        return self;
    }

    pub fn expand(self: *const @This(), input: []const u8, task_name: []const u8) ![]u8 {
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
                    return reportBadVariable(input, task_name, start, end, err);

                const value_string: []const u8 = blk: switch (value) {
                    .string => |s| s,
                    .version => {
                        var buf: [10]u8 = undefined;
                        break :blk try value.asString(&buf);
                    },
                    .boolean => {
                        var buf: [5]u8 = undefined;
                        break :blk try value.asString(&buf);
                    }
                };

                try expanded.appendSlice(self.allocator, value_string);

                i = end - 1;
                continue;
            }
            try expanded.append(self.allocator, char);
        }

        return try expanded.toOwnedSlice(self.allocator);
    }

    pub fn getVariable(self: *const @This(), name: []const u8) !Value {
        return self.map.get(name) orelse Value{ .string = getRuntimeVariable(name, self.allocator) catch return error.InvalidVariable };
    }
};

pub fn getRuntimeVariable(name: []const u8, allocator: std.mem.Allocator) ![]const u8 {
    const type_ = std.meta.stringToEnum(enum{TIME, DATE}, name) orelse return error.UnknownVariable;

    var time: c.time_t = c.time(null);
    const tm = c.localtime(&time) orelse return error.TimeConversionFailed;
    var buf: [10]u8 = undefined;

    const res = switch (type_) {
        .DATE => try std.fmt.bufPrint(&buf, "{d:0>2}.{d:0>2}.{d:0>2}", .{
            @as(u32, @intCast(tm.*.tm_mday)),
            @as(u32, @intCast(tm.*.tm_mon + 1)),
            @as(u32, @intCast(tm.*.tm_year + 1900)),
        }),

        .TIME => try std.fmt.bufPrint(&buf, "{d:0>2}:{d:0>2}", .{
            @as(u32, @intCast(tm.*.tm_hour)),
            @as(u32, @intCast(tm.*.tm_min)),
        }),
    };

    return allocator.dupe(u8, res);
}

fn reportBadVariable(full_input: []const u8, task_name: []const u8, start: usize, end: usize, err: anyerror) anyerror {
    logger.syntax(null, "undefined or invalid variable in task {s}'{s}'{s}:\n", .{ colors.get(.bold), task_name, colors.get(.reset) });

    logger.info("{s}", .{full_input});

    if (start > 1) {
        logger.out(false, .info, null, "\x1b[{d}C", .{ start - 1});
    }

    logger.info("{s}^{s}{s}", .{
        colors.get(.red),
        ([_]u8{'~'} ** 128)[0..@min(end - start, 128)],
        colors.get(.reset) 
    });

    return err;
}
