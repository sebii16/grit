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
const variables = @import("variables.zig");

pub fn main(init: std.process.Init) u8 {
    const arena = init.arena.allocator();
    const gpa = init.gpa;
    const io = init.io;

    const cfg = &config.Config.current;
    logger.init(cfg, io, init.environ_map);

    const args = init.minimal.args.toSlice(arena) catch return 1;
    const mode = cli.parseArgs(arena, args, cfg) catch return 1;
    
    defer logger.debug("arena: {} bytes allocated", .{init.arena.queryCapacity()});

    switch (mode) {
        .help => {
            logger.out(false, .none, null, "{s}", .{ cli.help_msg });
        },
        .version => {
            logger.out(true, .none, null, "{s}", .{ globals.ver_msg });
        },
        .run, .dump_vars => {
            const src = blk: {
                if (cfg.src) |src| {
                    cfg.file_name = "<eval>";
                    break :blk src;
                }
                cfg.file_dir = util.findFile(gpa, arena, io, cfg.file_name) catch return 1;
                break :blk util.readFile(arena, gpa, io, cfg.file_dir.?, cfg.file_name) catch return 1;
            };

            var parser = p.Parser.init(arena, gpa, src);
            const ast = parser.parseAll() catch return 1;
            
            const vars = variables.Vars.buildMap(arena, io, ast, cfg) catch {
                logger.err("failed to build variable map", .{});
                return 1;
            };

            switch (mode) {
                .run => runner.runTask(arena, gpa, io, ast, cfg, &parser, &vars) catch return 1,
                .dump_vars => vars.dump(gpa) catch return 1,
                else => unreachable,
            }
        },
    }

    return 0;
}

