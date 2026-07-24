const std = @import("std");
const lexer = @import("lexer.zig");
const globals = @import("globals.zig");
const logger = @import("logger.zig");

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

const Condition = struct {
    left: []const u8,
    op: enum {
        eq,
        noeq
    },
    right: []const u8,
};

const IfBlock = struct {
    condition: Condition,
    steps: []Step,
};

const Step = union(enum) {
    cmd: []const u8,
    directive: Directive,
    if_block: IfBlock,
};

const Rule = struct {
    name: []const u8,
    steps: []Step,
};

pub const VarMap = std.StringHashMapUnmanaged([]const u8);

pub const Ast = union(enum) {
    VarDecl: Var,
    RuleDecl: Rule,

    pub fn make_var_map(self: []const Ast) !VarMap {
        var vars: VarMap = .{};

        var count: u32 = 0;
        for (self) |node| {
            switch (node) {
                .VarDecl => count += 1,
                else => {},
            }
        }

        try vars.ensureTotalCapacity(globals.init.arena.allocator(), count);

        for (self) |node| {
            switch (node) {
                .VarDecl => |v| {
                    if (vars.contains(v.name)) {
                        logger.out(.syntax, "variable '{s}' redefined", .{v.name});
                        return error.DuplicateVar;
                    }
                    vars.putAssumeCapacity(v.name, v.value);
                },
                else => {},
            }
        }

        return vars;
    }
};

pub const Parser = struct {
    lexer: lexer.Lexer,
    curr: lexer.Token = .{ .value = &[_]u8{}, .type = .TOK__INVALID },
    default_rule: ?[]const u8 = null,

    pub fn parse_all(self: *Parser) ![]Ast {
        const allocator = globals.init.arena.allocator();
        var nodes: std.ArrayList(Ast) = .empty;
        var pending_default = false;

        try self.next_token();

        while (self.curr.type != .TOK_EOF) {
            if (self.curr.type == .TOK_DIRECTIVE) {
                const directive = Directive.parse(self.curr.value);

                if (directive != .default)
                    return self.syntax_error("directive '{s}' is invalid at top level", .{ self.curr.value });

                if (pending_default)
                    return self.syntax_error("expected rule declaration after @default", .{});

                if (self.default_rule != null or pending_default == true) 
                    return self.syntax_error("@default can only be called once", .{});

                pending_default = true;
                try self.next_token();
                continue;
            }

            const node = try self.parse_decl(&pending_default);
            try nodes.append(allocator, node);
        }

        if (pending_default)
            return self.syntax_error("no rule found after @default", .{});

        return nodes.toOwnedSlice(allocator);
    }

    fn parse_decl(self: *Parser, pending_default: *bool) !Ast {
        if (self.curr.type != .TOK_IDENT)
            return self.syntax_error("expected declaration, got '{s}'", .{ @tagName(self.curr.type) });

        const name = self.curr.value;
        try self.next_token();

        switch (self.curr.type) {
            .TOK_EQ => {
                // Variable
                if (pending_default.*)
                    return self.syntax_error("@default must be followed by a rule declaration", .{});

                try self.next_token();
                try self.expect(.TOK_STRING);

                const value = self.curr.value;
                try self.next_token();

                return .{
                    .VarDecl = .{
                        .name = name,
                        .value = value,
                    } 
                };
            },
            .TOK_LBRACE => {
                // Rule
                if (pending_default.* == true) {
                    self.default_rule = name;
                    pending_default.* = false;
                }

                return try self.parse_rule(name);
            },
            else => return self.syntax_error("expected '=' or '{{', got '{s}'", .{ @tagName(self.curr.type) }),
        }
    }

    fn parse_rule(self: *Parser, name: []const u8) !Ast {
        return .{
            .RuleDecl = .{
                .name = name,
                .steps = try self.parse_block()
            }
        };
    }

    fn parse_block(self: *Parser) anyerror![]Step {
        try self.next_token();
        const type_ = &self.curr.type;
        const value = &self.curr.value;
        var steps: std.ArrayList(Step) = .empty;
        const allocator = globals.init.arena.allocator();

        while (type_.* != .TOK_RBRACE) {
            switch (type_.*) {
                .TOK_STRING => {
                    try steps.append(allocator, .{ .cmd = value.* });
                },
                .TOK_DIRECTIVE => {
                    const directive = Directive.parse(value.*);

                    switch (directive) {
                        .parallel, .sequential => |d| try steps.append(allocator, .{ .directive = d }),
                        .@"if" => {
                            // TODO
                            logger.out(.warning, "@if is work in progress", .{});
                            try steps.append(allocator, .{ .if_block = try self.parse_if_block() });
                            continue;
                        },
                        else => return self.syntax_error("directive '@{s}' is invalid inside a rule", .{ value.* }),
                    }
                },
                .TOK_EOF => {
                    return self.syntax_error("expected '}}' got EOF", .{});
                },
                else => return self.syntax_error("unexpected token inside rule declaration: '{s}': '{s}'", .{@tagName(type_.*), value.*}),
            }
            try self.next_token();
        }
        try self.next_token();
        
        return try steps.toOwnedSlice(allocator);
    }

    fn parse_if_block(self: *Parser) !IfBlock {
        // skip @if
        try self.next_token();
        try self.expect(.TOK_IDENT);

        const left = self.curr.value;
        try self.next_token();

        var op: bool = undefined;
        switch (self.curr.type) {
            .TOK_DEQ => op = true,
            .TOK_NOEQ => op = false,
            else => return self.syntax_error("expected '==' or '!=' got '{s}'", .{self.curr.value})
        }

        try self.next_token();
        try self.expect2(.TOK_IDENT, .TOK_STRING);

        const right = self.curr.value;

        try self.next_token();
        try self.expect(.TOK_LBRACE);

        logger.out(.debug, "{s} {s} {s}", .{left, if (op) "==" else "!=", right});

        return .{
            .condition = .{
                .left = left,
                .op = if (op) .eq else .noeq,
                .right = right,
            },
            .steps = try self.parse_block(),
        };
    }

    fn next_token(self: *Parser) !void {
        while (true) {
            self.curr = try self.lexer.next();
            switch (self.curr.type) {
                .TOK_NL, .TOK_COMMENT => continue,
                else => return,
            }
        }
    }

    fn syntax_error(self: *Parser, comptime fmt: []const u8, args: anytype) error{SyntaxError} {
        logger.out_adv(true, .syntax, self.lexer.curr_line, fmt, args);
        return error.SyntaxError;
    }

    fn expect(self: *Parser, t: lexer.TokenType) !void {
        if (self.curr.type != t) {
            logger.out_adv(true, .syntax, self.lexer.curr_line, "expected '{s}' got '{s}'", .{ @tagName(t), @tagName(self.curr.type) });
            return error.SyntaxError;
        }
    } 

    fn expect2(self: *Parser, t1: lexer.TokenType, t2: lexer.TokenType) !void {
        if (self.curr.type != t1 and self.curr.type != t2) {
            logger.out_adv(true, .syntax, self.lexer.curr_line, "expected '{s}' or '{s}' got '{s}'", .{ @tagName(t1), @tagName(t2), @tagName(self.curr.type) });
            return error.SyntaxError;
        }
    }
};
