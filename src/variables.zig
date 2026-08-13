const std = @import("std");
const builtin = @import("builtin");
const parser = @import("parser.zig");
const globals = @import("globals.zig");
const logger = @import("logger.zig");
const colors = @import("colors.zig");
const config = @import("config.zig");
const c = @cImport({
    @cInclude("time.h");
});

pub const Value = union(enum) {
    string: []const u8,
    version: std.SemanticVersion,
    boolean: bool,

    const AsStringResult = struct {
        str: []const u8 = &.{},
        allocated: bool = false
    };

    pub fn asString(self: @This(), gpa: std.mem.Allocator) !AsStringResult {
        var res = AsStringResult{};

        switch (self) {
            .string => |s| {
                res.str = s;
            },
            .version => |v| {
                res.str = try std.fmt.allocPrint(gpa, "{d}.{d}.{d}", .{v.major, v.minor, v.patch});
                res.allocated = true;
            },
            .boolean => |b| {
                res.str = try std.fmt.allocPrint(gpa, "{}", .{b});
                res.allocated = true;
            }
        }

        return res;
    }
};

pub const VarMap = std.StringHashMap(Value);

pub const builtin_variables = [_][]const u8 {
    "OS",
    "ARCH",
    "CWD",
    "GRIT_VER",
    "ROOT_DIR",
};

pub const Vars = struct {
    map: VarMap,
    allocator: std.mem.Allocator,
    io: std.Io,

    pub fn dump(self: *const @This(), gpa: std.mem.Allocator) !void {
        if (self.map.count() == 0) return;

        var iter = self.map.iterator();

        while (iter.next()) |entry| {
            const value = entry.value_ptr.*.asString(gpa) catch continue;
            defer if (value.allocated) gpa.free(value.str);

            logger.out(true, .none, null, "{s} = {s}", .{entry.key_ptr.*, value.str});
        }
    }

    fn addBuiltinVariables(self: *@This(), cfg: *const config.Config) !void {
        const cwd = try std.process.currentPathAlloc(self.io, self.allocator);
        const root_dir = cfg.file_dir orelse cwd;

        try self.map.put("OS", .{ .string = @tagName(globals.os) });
        try self.map.put("ARCH", .{ .string = @tagName(globals.arch) });
        try self.map.put("CWD", .{ .string = cwd });
        try self.map.put("GRIT_VER", .{ .version = globals.ver });
        try self.map.put("ROOT_DIR", .{ .string = root_dir });

        logger.debug("builtin variables added", .{});
    }

    pub fn buildMap(allocator: std.mem.Allocator, io: std.Io, ast: []const parser.Ast, cfg: *const config.Config) !@This() {
        var self = @This(){
            .map = VarMap.init(allocator),
            .allocator = allocator, 
            .io = io,
        };

        try self.addBuiltinVariables(cfg);

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

    pub fn expand(self: *const @This(), gpa: std.mem.Allocator, input: []const u8, task_name: []const u8) !?[]u8 {
        // return null if there is nothing to expand
        _ = std.mem.findScalar(u8, input, '$') orelse return null;

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

                const value_string = try value.asString(gpa);
                defer if (value_string.allocated) gpa.free(value_string.str);

                try expanded.appendSlice(self.allocator, value_string.str);

                i = end - 1;
                continue;
            }
            try expanded.append(self.allocator, char);
        }

        return expanded.items;
    }

    pub fn getVariable(self: *const @This(), name: []const u8) !Value {
        return self.map.get(name) orelse return error.InvalidVariable;
    }
};

fn reportBadVariable(full_input: []const u8, task_name: []const u8, start: usize, end: usize, err: anyerror) anyerror {
    logger.syntax(null, "undefined or invalid variable in task {s}'{s}'{s}:\n", .{ colors.get(.bold), task_name, colors.get(.reset) });

    const start_input = full_input[0..start - 1];
    const variable = full_input[start - 1..end];
    const rest_input = full_input[end..];

    logger.out(true, .none, null, "{s}{s}{s}{s}{s}", .{start_input, colors.get(.red_bold), variable, colors.get(.reset), rest_input});

    if (start > 1) {
        logger.out(false, .none, null, "\x1b[{d}C", .{ start - 1});
    }

    const tildes = [_]u8{'~'} ** 128;

    logger.out(true, .none, null, "{s}^{s}{s}", .{
        colors.get(.red_bold),
       // ([_]u8{'~'} ** 128)[0..@min(end - start, 128)],
        tildes[0..@min(end -| start, tildes.len)],
        colors.get(.reset) 
    });

    return err;
}
