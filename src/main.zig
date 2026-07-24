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

    var args = cli.parse_args() catch return 1;

    logger.Config.current.build_file = args.config.build_file;

    args.config.threads = if (args.config.threads > 0) args.config.threads else std.Thread.getCpuCount() catch 1;

    defer logger.out_adv(true, .debug, null, "arena: {} bytes allocated", .{init.arena.queryCapacity()});

    switch (args.action) {
        .Help => {
            logger.out(.info, "{s}", .{ globals.help_msg });
        },
        .Version => {
            logger.out(.info, "{s}", .{ globals.ver_msg });
        },
        .List, .Run => {  
            const src = read_file(args.config.build_file) catch return 1;
            var parser = p.Parser{ .lexer = .{ .src = src }};
            const ast = parser.parse_all() catch return 1;
            switch (args.action) {
                .List => {
                    logger.out(.info, "{s}available rules:{s}", .{ logger.Colors.get(logger.Colors.bold), logger.Colors.get(logger.Colors.reset) });
                    for (ast) |n| {
                        switch (n) {
                            .RuleDecl => |r| {
                                logger.out(.info, "  {s} {{", .{r.name});
                                for (r.steps) |step| {
                                    switch (step) {
                                        .cmd => |c| logger.out(.info, "    {s}", .{c}),
                                        else => {},
                                    }
                                }
                                logger.out(.info, "  }}\n", .{});
                            },
                            else => {},
                        }
                    }
                },
                .Run => runner.run_build_rule(ast, &args.config, &parser) catch return 1,
                else => unreachable,
            }
        },
    }

    return 0;
}

fn read_file(path: []const u8) ![]const u8 {
    return std.Io.Dir.readFileAlloc(std.Io.Dir.cwd(), globals.init.io, path, globals.init.arena.allocator(), .unlimited) catch |e| {
        logger.out_adv(true, .err, null, "failed to read '{s}'", .{path});
        return e;
    };
}
