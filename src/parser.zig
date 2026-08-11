const std = @import("std");
const lexer = @import("lexer.zig");
const logger = @import("logger.zig");
const if_statement = @import("if_statement.zig");
const variables = @import("variables.zig");
const colors = @import("colors.zig");
const globals = @import("globals.zig");

pub const Directive = enum {
    invalid,
    default,
    parallel,
    sequential,
    @"if",
    elif,
    @"else",

    inline fn parse(name: []const u8) Directive {
        return std.meta.stringToEnum(Directive, name) orelse .invalid;
    }
};

pub const Step = union(enum) {
    cmd: []const u8,
    directive: Directive,
    if_block: *if_statement.IfBlock,
};

const Var = struct {
    name: []const u8,
    value: []const u8,
};

const Task = struct {
    name: []const u8,
    steps: []Step,
};

pub const Ast = union(enum) {
    VarDecl: Var,
    TaskDecl: Task,
};


pub fn listAllTasks(self: []const Ast) void {
    if (self.len == 0) {
        logger.err("there are no tasks", .{});
        return;
    }

    for (self) |node| {
        switch (node) {
            .VarDecl => {},
            .TaskDecl => |task| {
                //if (task.description) |desc| logger.out(true, .none, null, "{s}", .{desc});
                logger.out(true, .none, null, "{s}", .{task.name});
            }
        }
    }
}

pub const Parser = struct {
    lexer: lexer.Lexer,
    curr: lexer.Token = .{ .value = &[_]u8{}, .type = .TOK__INVALID },
    default_task: ?[]const u8 = null,
    pending_default: bool = false,
    task_names: std.StringHashMap(usize),
    variable_names: std.StringHashMap(usize),
    allocator: std.mem.Allocator, 
    temp_allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, gpa: std.mem.Allocator, lexer_src: []const u8) @This() {
        return .{
            .lexer = .{ .src = lexer_src },
            .task_names = .init(gpa),
            .variable_names = .init(gpa),
            .allocator = allocator,
            .temp_allocator = gpa,
        };
    }

    pub fn parseAll(self: *Parser) ![]Ast {
        defer {
            self.task_names.deinit();
            self.variable_names.deinit();
            logger.debug("cleanup temporary task and variable hashmaps", .{});
        }

        var nodes: std.ArrayList(Ast) = .empty;
        try self.nextToken();

        while (self.curr.type != .TOK_EOF) {
            if (self.curr.type == .TOK_DIRECTIVE) {
                const directive = Directive.parse(self.curr.value);

                if (directive == .invalid) 
                    return self.parsingError("directive '@{s}' doesn't exist", .{ self.curr.value });

                if (directive != .default)
                    return self.parsingError("directive '@{s}' is invalid at top level", .{ self.curr.value });

                if (self.default_task != null or self.pending_default) 
                    return self.parsingError("@default can only be called once", .{});

                self.pending_default = true;
                try self.nextToken();
                continue;
            }

            const node = try self.parseDecl();
            try nodes.append(self.allocator, node);
        }

        if (self.pending_default)
            return self.parsingError("no task found after @default", .{});

        return nodes.toOwnedSlice(self.allocator);
    }

    fn validateDeclaration(self: *@This(), name: []const u8, decl_type: enum {variable, task}) !void {
        if (name.len > globals.max_name_length)
            return self.parsingError("variable name exceeds maximum length of {d} characters", .{globals.max_name_length});

        if (decl_type == .variable) {
            inline for (variables.builtin_variables) |v| {
                if (std.mem.eql(u8, v, name)) {
                    return self.parsingError(
                        "redefinition of builtin variable {s}'{s}'{s} is not allowed",
                        .{colors.get(.bold), name, colors.get(.reset)}
                    );
                }
            }
        }

        const res = try (switch (decl_type) {
            .variable => &self.variable_names,
            .task => &self.task_names,
        }).getOrPut(name);

        if (res.found_existing) {
            return self.parsingError(
                "{s} {s}'{s}'{s} redefined: first definition on line {d}",
                .{@tagName(decl_type), colors.get(.bold), name, colors.get(.reset), res.value_ptr.*}
            );
        }

        res.value_ptr.* = self.lexer.line;
    }

    fn parseDecl(self: *Parser) !Ast {
        if (self.curr.type != .TOK_IDENT)
            return self.parsingError("expected declaration, got '{s}'", .{ @tagName(self.curr.type) });

        const name = self.curr.value;
        try self.nextToken();

        switch (self.curr.type) {
            .TOK_ASSIGN => {
                // Variable
                try self.validateDeclaration(name, .variable);

                if (self.pending_default)
                    return self.parsingError("@default must be followed by a task declaration", .{});

                try self.nextToken();
                try self.expect(&.{ .TOK_STRING });

                const value = self.curr.value;
                try self.nextToken();

                return .{
                    .VarDecl = .{
                        .name = name,
                        .value = value,
                    } 
                };
            },
            .TOK_LBRACE => {
                // Task
                try self.validateDeclaration(name, .task);

                if (self.pending_default) {
                    self.default_task = name;
                    self.pending_default = false;
                }

                return .{
                    .TaskDecl = .{
                        .name = name, 
                        .steps = try self.parseTask(),
                    }
                };
            },
            else => return self.parsingError("expected '=' or '{{', got '{s}'", .{ @tagName(self.curr.type) }),
        }
    }

    fn parseTask(self: *Parser) ![]Step {
        try self.nextToken();

        var steps: std.ArrayList(Step) = .empty;
        defer steps.deinit(self.temp_allocator);

        outer: while (self.curr.type != .TOK_RBRACE) {
            switch (self.curr.type) {
                .TOK_STRING => {
                    try steps.append(self.temp_allocator, .{ .cmd = self.curr.value });
                },
                .TOK_DIRECTIVE => {
                    const directive = Directive.parse(self.curr.value);

                    switch (directive) {
                        .parallel, .sequential => |d| try steps.append(self.temp_allocator, .{ .directive = d }),
                        .@"if" => {
                            const first_block = try self.parseIfBlock(.@"if");
                            var current_block = first_block;

                            while (true) {
                                if (self.curr.type != .TOK_DIRECTIVE) {
                                    break;
                                }

                                const next_directive = Directive.parse(self.curr.value);

                                switch (next_directive) {
                                    .elif => {
                                        const elif_block = try self.parseIfBlock(.elif);
                                        current_block.next = elif_block;
                                        current_block = elif_block;
                                    },
                                    .@"else" => {
                                        const else_block = try self.parseIfBlock(.@"else");
                                        current_block.next = else_block;
                                        current_block = else_block;
                                        break;
                                    },
                                    else => {
                                        break;
                                    }
                                }
                            }

                            try steps.append(self.temp_allocator, .{.if_block = first_block});
                            continue :outer;
                        },
                        .elif, .@"else" => |e| {
                            return self.parsingError("@{s} has no matching @if", .{@tagName(e)});
                        },
                        else => return self.parsingError("directive '@{s}' is invalid here", .{ self.curr.value }),
                    }
                },
                .TOK_EOF => {
                    return self.parsingError("expected '}}' got EOF", .{});
                },
                else => return self.parsingError("unexpected token inside task declaration: '{s}': '{s}'", .{@tagName(self.curr.type), self.curr.value}),
            }
            try self.nextToken();
        }
        try self.nextToken();

        if (steps.items.len == 0)
            return &.{};
        
        return self.allocator.dupe(Step, steps.items);
    }

    const IfType = enum {
        @"if",
        elif,
        @"else",
    };

    fn parseIfBlock(self: *Parser, if_type: IfType) anyerror!*if_statement.IfBlock {
        // skip opener
        try self.nextToken();

        const if_block = try self.allocator.create(if_statement.IfBlock);

        switch (if_type) {
            .@"if", .elif => {
                try self.expect(&.{ .TOK_IDENT });

                const lhs = self.curr.value;
                try self.nextToken();

                const op: if_statement.Operator = switch (self.curr.type) {
                    .TOK_EQ => .eq,
                    .TOK_NEQ => .neq,
                    .TOK_LT => .lt,
                    .TOK_LTE => .lte,
                    .TOK_GT => .gt,
                    .TOK_GTE => .gte,
                    else => return self.parsingError("expected comparison operator got '{s}'", .{@tagName(self.curr.type) })
                };

                try self.nextToken();
                try self.expect(&.{ .TOK_IDENT, .TOK_STRING });

                const rhs = self.curr.value;
                const rhs_is_string = self.curr.type == .TOK_STRING;

                try self.nextToken();
                try self.expect(&.{ .TOK_LBRACE });

                if_block.* = .{
                    .condition = if_statement.Condition.create(
                        self.lexer.line,
                        lhs,
                        op,
                        rhs,
                        rhs_is_string,
                    ),
                    .steps = try self.parseTask(),
                };
            },
            .@"else" => {
                try self.expect(&.{ .TOK_LBRACE });
                if_block.* = .{
                    .condition = null,
                    .steps = try self.parseTask(),
                };
            }
        }
        
        return if_block;
    }

    fn nextToken(self: *Parser) !void {
        while (true) {
            self.curr = try self.lexer.next();
            switch (self.curr.type) {
                .TOK_NL, .TOK_COMMENT => continue,
                else => return,
            }
        }
    }

    inline fn parsingError(self: *const Parser, comptime fmt: []const u8, args: anytype) error{SyntaxError} {
        logger.syntax(self.lexer.line, fmt, args);
        return error.SyntaxError;
    }

    fn expect(self: *Parser, comptime tokens: []const lexer.TokenType) !void {
        inline for (tokens) |token| {
            if (self.curr.type == token)
                return;
        }

        return self.parsingError("unexpected token '{s}'", .{ @tagName(self.curr.type) });
    }
};
