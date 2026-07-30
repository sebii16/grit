const std = @import("std");
const lexer = @import("lexer.zig");
const logger = @import("logger.zig");
const if_statement = @import("if_statement.zig");
const variables = @import("variables.zig");
const colors = @import("colors.zig");

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
    condition: if_statement.Condition,
    steps: []Step,
};

pub const Step = union(enum) {
    cmd: []const u8,
    directive: Directive,
    if_block: *IfBlock,
};

const Var = struct {
    name: []const u8,
    value: []const u8,
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
    rule_names: std.StringHashMap(usize),
    variable_names: std.StringHashMap(usize),
    allocator: std.mem.Allocator, 
    temp_allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator, gpa: std.mem.Allocator, lexer_src: []const u8) @This() {
        return .{
            .lexer = .{ .src = lexer_src },
            .rule_names = .init(gpa),
            .variable_names = .init(gpa),
            .allocator = allocator,
            .temp_allocator = gpa,
        };
    }

    pub fn parseAll(self: *Parser) ![]Ast {
        defer {
            self.rule_names.deinit();
            self.variable_names.deinit();
            logger.out(.debug, "cleanup rule and variable hashmaps", .{});
        }

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
            try nodes.append(self.allocator, node);
        }

        if (self.pending_default)
            return self.syntaxError("no rule found after @default", .{});

        return nodes.toOwnedSlice(self.allocator);
    }

    fn checkDuplicate(self: *@This(), name: []const u8, decl_type: enum {variable, rule}) !void {
        inline for (variables.builtin_variables) |v| {
            if (std.mem.eql(u8, v.name, name)) {
                logger.syntaxError(
                    self.lexer.line,
                    "redefininition of builtin variable {s}'{s}'{s} is not allowed",
                    .{colors.get(.bold), name, colors.get(.reset)}
                );
                return error.DuplicateVariable;
            }
        }

        const res = try (switch (decl_type) {
            .variable => &self.variable_names,
            .rule => &self.rule_names,
        }).getOrPut(name);

        if (res.found_existing) {
            logger.syntaxError(
                self.lexer.line,
                "{s} {s}'{s}'{s} redefined: first definition on line {d}",
                .{@tagName(decl_type), colors.get(.bold), name, colors.get(.reset), res.value_ptr.*}
            );
            return error.DuplicateDeclaration;
        }

        res.value_ptr.* = self.lexer.line;
    }

    fn parseDecl(self: *Parser) !Ast {
        if (self.curr.type != .TOK_IDENT)
            return self.syntaxError("expected declaration, got '{s}'", .{ @tagName(self.curr.type) });

        const name = self.curr.value;
        try self.nextToken();

        switch (self.curr.type) {
            .TOK_ASSIGN => {
                // Variable
                try self.checkDuplicate(name, .variable);

                if (self.pending_default)
                    return self.syntaxError("@default must be followed by a rule declaration", .{});

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
                // Rule
                try self.checkDuplicate(name, .rule);

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

        var steps: std.ArrayList(Step) = .empty;
        defer steps.deinit(self.temp_allocator);

        while (self.curr.type != .TOK_RBRACE) {
            switch (self.curr.type) {
                .TOK_STRING => {
                    try steps.append(self.temp_allocator, .{ .cmd = self.curr.value });
                },
                .TOK_DIRECTIVE => {
                    const directive = Directive.parse(self.curr.value);

                    switch (directive) {
                        .parallel, .sequential => |d| try steps.append(self.temp_allocator, .{ .directive = d }),
                        .@"if" => {
                            try steps.append(self.temp_allocator, .{ .if_block = try self.parseIfBlock() });
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
        
        return self.allocator.dupe(Step, steps.items);
    }

    fn parseIfBlock(self: *Parser) anyerror!*IfBlock {
        // skip @if
        try self.nextToken();
        try self.expect(&.{ .TOK_IDENT });

        const left = self.curr.value;
        try self.nextToken();

        const op: if_statement.Operator = switch (self.curr.type) {
            .TOK_EQ => .eq,
            .TOK_NEQ => .neq,
            .TOK_LT => .lt,
            .TOK_LTE => .lte,
            .TOK_GT => .gt,
            .TOK_GTE => .gte,
            else => return self.syntaxError("expected comparision operator got '{s}' ({s})", .{@tagName(self.curr.type), self.curr.value})
        };

        try self.nextToken();
        try self.expect(&.{ .TOK_IDENT, .TOK_STRING });

        const right = self.curr.value;
        const right_is_string = switch (self.curr.type) {
            .TOK_IDENT => false,
            .TOK_STRING => true,
            else => unreachable,
        };

        try self.nextToken();
        try self.expect(&.{ .TOK_LBRACE });

        const if_block = try self.allocator.create(IfBlock);
        if_block.* = .{
            .condition = .{
                .line = self.lexer.line,
                .lhs = left,
                .op = op,
                .rhs = right,
                .right_is_string = right_is_string,
            },
            .steps = try self.parseRule(),
        };

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

    inline fn syntaxError(self: *const Parser, comptime fmt: []const u8, args: anytype) error{SyntaxError} {
        logger.syntaxError(self.lexer.line, fmt, args);
        return error.SyntaxError;
    }

    fn expect(self: *Parser, comptime expected: []const lexer.TokenType) !void {
        inline for (expected) |token| {
            if (self.curr.type == token)
                return;
        }

        return self.syntaxError("unexpected token '{s}'", .{ @tagName(self.curr.type) });
    }
};
