const std = @import("std");
const lexer = @import("lexer.zig");
const globals = @import("globals.zig");
const logger = @import("logger.zig");
const condition = @import("condition.zig");

const Var = struct {
    name: []const u8,
    value: []const u8,
};

pub const Directive = enum {
    invalid,
    default,
    parallel,
    sequential,
    @"if",

    inline fn parse(name: []const u8) Directive {
        return std.meta.stringToEnum(Directive, name) orelse .invalid;
    }
};

const IfBlock = struct {
    condition: condition.Condition,
    steps: []Step,
};

pub const Step = union(enum) {
    cmd: []const u8,
    directive: Directive,
    if_block: IfBlock,
};

const Rule = struct {
    name: []const u8,
    steps: []Step,
};

pub const Ast = union(enum) {
    VarDecl: Var,
    RuleDecl: Rule,
};

pub const Parser = struct {
    lexer: lexer.Lexer,
    curr: lexer.Token = .{ .value = &[_]u8{}, .type = .TOK__INVALID },
    default_rule: ?[]const u8 = null,
    pending_default: bool = false,
    rule_names: std.StringHashMapUnmanaged(usize) = .{},
    variable_names: std.StringHashMapUnmanaged(usize) = .{},

    pub fn parseAll(self: *Parser) ![]Ast {
        defer {
            self.rule_names.deinit(globals.init.gpa);
            self.variable_names.deinit(globals.init.gpa);
            logger.out(.debug, "cleanup rule and variable hashmaps", .{});
        }

        const allocator = globals.init.arena.allocator();
        var nodes: std.ArrayList(Ast) = .empty;
        try self.nextToken();

        while (self.curr.type != .TOK_EOF) {
            if (self.curr.type == .TOK_DIRECTIVE) {
                const directive = Directive.parse(self.curr.value);

                if (directive == .invalid) 
                    return self.syntaxError("directive '@{s}' doesn't exist", .{ self.curr.value });

                if (directive != .default)
                    return self.syntaxError("directive '@{s}' is invalid at top level", .{ self.curr.value });

                if (self.default_rule != null or self.pending_default) 
                    return self.syntaxError("@default can only be called once", .{});

                self.pending_default = true;
                try self.nextToken();
                continue;
            }

            const node = try self.parseDecl();
            try nodes.append(allocator, node);
        }

        if (self.pending_default)
            return self.syntaxError("no rule found after @default", .{});

        return nodes.toOwnedSlice(allocator);
    }

    fn checkDuplicate(self: *@This(), allocator: std.mem.Allocator, name: []const u8, decl_type: enum {variable, rule}) !void {
        const res = try (switch (decl_type) {
            .variable => &self.variable_names,
            .rule => &self.rule_names,
        }).getOrPut(allocator, name);

        if (res.found_existing) {
            logger.outAdv(
                true,
                .syntax,
                self.lexer.curr_line,
                "{s} {s}'{s}'{s} redefined: first definition on line {d}",
                .{@tagName(decl_type), logger.Colors.get(logger.Colors.bold), name, logger.Colors.get(logger.Colors.reset), res.value_ptr.*}
            );
            return error.DuplicateDeclaration;
        }

        res.value_ptr.* = self.lexer.curr_line;
    }

    fn parseDecl(self: *Parser) !Ast {
        if (self.curr.type != .TOK_IDENT)
            return self.syntaxError("expected declaration, got '{s}'", .{ @tagName(self.curr.type) });

        const name = self.curr.value;
        try self.nextToken();

        switch (self.curr.type) {
            .TOK_EQ => {
                // Variable
                try self.checkDuplicate(globals.init.gpa, name, .variable);

                if (self.pending_default)
                    return self.syntaxError("@default must be followed by a rule declaration", .{});

                try self.nextToken();
                try self.expect(.TOK_STRING);

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
                // Rule
                try self.checkDuplicate(globals.init.gpa, name, .rule);

                if (self.pending_default) {
                    self.default_rule = name;
                    self.pending_default = false;
                }

                return .{
                    .RuleDecl = .{
                        .name = name, 
                        .steps = try self.parseRule(),
                    }
                };
            },
            else => return self.syntaxError("expected '=' or '{{', got '{s}'", .{ @tagName(self.curr.type) }),
        }
    }

    fn parseRule(self: *Parser) ![]Step {
        try self.nextToken();
        const temp_allocator = globals.init.gpa;
        const allocator = globals.init.arena.allocator();

        var steps: std.ArrayList(Step) = .empty;
        defer steps.deinit(temp_allocator);

        while (self.curr.type != .TOK_RBRACE) {
            switch (self.curr.type) {
                .TOK_STRING => {
                    try steps.append(temp_allocator, .{ .cmd = self.curr.value });
                },
                .TOK_DIRECTIVE => {
                    const directive = Directive.parse(self.curr.value);

                    switch (directive) {
                        .parallel, .sequential => |d| try steps.append(temp_allocator, .{ .directive = d }),
                        .@"if" => {
                            // TODO
                            try steps.append(temp_allocator, .{ .if_block = try self.parse_if_block() });
                            continue;
                        },
                        else => return self.syntaxError("directive '@{s}' is invalid inside a rule", .{ self.curr.value }),
                    }
                },
                .TOK_EOF => {
                    return self.syntaxError("expected '}}' got EOF", .{});
                },
                else => return self.syntaxError("unexpected token inside rule declaration: '{s}': '{s}'", .{@tagName(self.curr.type), self.curr.value}),
            }
            try self.nextToken();
        }
        try self.nextToken();

        if (steps.items.len == 0)
            return &.{};
        
        return try allocator.dupe(Step, steps.items);
    }

    fn parse_if_block(self: *Parser) anyerror!IfBlock {
        // skip @if
        try self.nextToken();
        try self.expect(.TOK_IDENT);

        const left = self.curr.value;
        try self.nextToken();

        const op: condition.Operator = switch (self.curr.type) {
            .TOK_DEQ => .eq,
            .TOK_NEQ => .neq,
            else => return self.syntaxError("expected '==' or '!=' got '{s}'", .{self.curr.value})
        };

        try self.nextToken();
        try self.expectEither(.TOK_IDENT, .TOK_STRING);

        const right = self.curr.value;
        const right_is_string = switch (self.curr.type) {
            .TOK_IDENT => false,
            .TOK_STRING => true,
            else => unreachable,
        };

        try self.nextToken();
        try self.expect(.TOK_LBRACE);

        return .{
            .condition = .{
                .left = left,
                .op = op,
                .right = right,
                .right_is_string = right_is_string,
                .is_met = false,
            },
            .steps = try self.parseRule(),
        };
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

    inline fn syntaxError(self: *Parser, comptime fmt: []const u8, args: anytype) error{SyntaxError} {
        logger.outAdv(true, .syntax, self.lexer.curr_line, fmt, args);
        return error.SyntaxError;
    }

    fn expect(self: *Parser, t: lexer.TokenType) !void {
        if (self.curr.type != t) {
            logger.outAdv(true, .syntax, self.lexer.curr_line, "expected '{s}' got '{s}'", .{ @tagName(t), @tagName(self.curr.type) });
            return error.SyntaxError;
        }
    } 

    fn expectEither(self: *Parser, t1: lexer.TokenType, t2: lexer.TokenType) !void {
        if (self.curr.type != t1 and self.curr.type != t2) {
            logger.outAdv(true, .syntax, self.lexer.curr_line, "expected '{s}' or '{s}' got '{s}'", .{ @tagName(t1), @tagName(t2), @tagName(self.curr.type) });
            return error.SyntaxError;
        }
    }
};
