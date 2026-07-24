const std = @import("std");
const lexer = @import("lexer.zig");
const cli = @import("cli.zig");
const p = @import("parser.zig");
const runner = @import("runner.zig");
const logger = @import("logger.zig");
const globals = @import("globals.zig");

pub fn main(init: std.process.Init) u8 {
    globals.init = init;

    logger.init();

    var args = cli.parseArgs() catch return 1;

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
            const src = readFile(args.config.build_file) catch return 1;
            var parser = p.Parser{ .lexer = .{ .src = src }};
            const ast = parser.parseAll() catch return 1;
            
            runner.runBuildRule(ast, &args.config, &parser) catch return 1;
        },
    }

    return 0;
}

fn readFile(path: []const u8) ![]const u8 {
    return std.Io.Dir.readFileAlloc(std.Io.Dir.cwd(), globals.init.io, path, globals.init.arena.allocator(), .unlimited) catch |e| {
        logger.out(.err, "failed to read '{s}'", .{path});
        return e;
    };
}
