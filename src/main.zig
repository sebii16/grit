const std = @import("std");
const lexer = @import("lexer.zig");
const cli = @import("cli.zig");
const p = @import("parser.zig");
const runner = @import("runner.zig");
const logger = @import("logger.zig");
const globals = @import("globals.zig");
const config = @import("config.zig");
const colors = @import("colors.zig");

pub fn main(init: std.process.Init) u8 {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;

    globals.init(arena, gpa, io);

    const cfg = &config.Config.current;
    logger.init(cfg, io, init.environ_map);

    const args = init.minimal.args.toSlice(arena) catch return 1;
    const action = cli.parseArgs(args, cfg) catch return 1;

    // validate thread count
    if (cfg.threads == 0) {
        cfg.threads = std.Thread.getCpuCount() catch 1;
        logger.warning("thread count of 0 ignored, using default: {d}", .{cfg.threads});
    }
    
    defer logger.debug("arena: {} bytes allocated", .{init.arena.queryCapacity()});

    switch (action) {
        .help => {
            logger.info("{s}", .{ globals.help_msg });
        },
        .version => {
            logger.info("{s}", .{ globals.ver_msg });
        },
        .run => {
            const src = cfg.src orelse readFile(arena, io, cfg.build_file) catch return 1;
            var parser = p.Parser.init(arena, gpa, src);
            const ast = parser.parseAll() catch return 1;
            
            runner.runBuildRule(arena, gpa, io, ast, cfg, &parser) catch return 1;
        },
    }

    return 0;
}

fn readFile(allocator: std.mem.Allocator, io: std.Io, path: []const u8) ![]const u8 {
    return std.Io.Dir.readFileAlloc(std.Io.Dir.cwd(), io, path, allocator, .unlimited) catch |e| {
        logger.err("failed to read {s}'{s}'{s}", .{colors.get(.bold), path, colors.get(.reset)});
        return e;
    };
}
