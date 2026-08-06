const std = @import("std");
const lexer = @import("lexer.zig");
const cli = @import("cli.zig");
const p = @import("parser.zig");
const runner = @import("runner.zig");
const logger = @import("logger.zig");
const globals = @import("globals.zig");
const config = @import("config.zig");
const colors = @import("colors.zig");
const util = @import("util.zig");

pub fn main(init: std.process.Init) u8 {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;

    const cfg = &config.Config.current;
    logger.init(cfg, io, init.environ_map);

    const args = init.minimal.args.toSlice(arena) catch return 1;
    const action = cli.parseArgs(arena, args, cfg) catch return 1;
    
    defer logger.debug("arena: {} bytes allocated", .{init.arena.queryCapacity()});

    switch (action) {
        .help => {
            logger.out(true, .none, null, "{s}", .{ globals.help_msg });
        },
        .version => {
            logger.out(true, .none, null, "{s}", .{ globals.ver_msg });
        },
        .run => {
            const src = blk: {
                if (cfg.src) |src| {
                    cfg.file = "<eval>";
                    break :blk src;
                }
                break :blk util.readFile(arena, io, cfg.file) catch return 1;
            };
            var parser = p.Parser.init(arena, gpa, src);
            const ast = parser.parseAll() catch return 1;
            
            runner.runTask(arena, gpa, io, ast, cfg, &parser) catch return 1;
        },
    }

    return 0;
}

