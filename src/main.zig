const std = @import("std");
const lexer = @import("lexer.zig");
const cli = @import("cli.zig");
const p = @import("parser.zig");
const runner = @import("runner.zig");
const logger = @import("logger.zig");
const globals = @import("globals.zig");

pub fn main(init: std.process.Init) u8 {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;

    globals.init(arena, gpa, io);

    logger.init(io, init.environ_map);

    var args = cli.parseArgs(arena, init.minimal.args) catch return 1;

    logger.Config.current.build_file = args.config.build_file;

    args.config.threads = if (args.config.threads > 0) args.config.threads else std.Thread.getCpuCount() catch 1;

    defer logger.out(.debug, "arena: {} bytes allocated", .{init.arena.queryCapacity()});

    switch (args.action) {
        .Help => {
            logger.out(.info, "{s}", .{ globals.help_msg });
        },
        .Version => {
            logger.out(.info, "{s}", .{ globals.ver_msg });
        },
        .Run => {  
            const src = readFile(arena, io, args.config.build_file) catch return 1;
            var parser = p.Parser.init(arena, gpa, src);
            const ast = parser.parseAll() catch return 1;
            
            runner.runBuildRule(arena, io, ast, &args.config, &parser) catch return 1;
        },
    }

    return 0;
}

fn readFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]const u8 {
    return std.Io.Dir.readFileAlloc(std.Io.Dir.cwd(), io, path, allocator, .unlimited) catch |e| {
        logger.out(.err, "failed to read '{s}'", .{path});
        return e;
    };
}
