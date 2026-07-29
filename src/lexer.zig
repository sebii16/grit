const std = @import("std");
const logger = @import("logger.zig");

pub const TokenType = enum {
    TOK_EOF,
    TOK_NL,
    TOK_ASSIGN,
    TOK_EQ,
    TOK_NEQ,
    TOK_GT,
    TOK_LT,
    TOK_LTE,
    TOK_GTE,
    TOK_LBRACE,
    TOK_RBRACE,
    TOK_COMMENT,
    TOK_STRING,
    TOK_IDENT,
    TOK_DIRECTIVE,
    TOK_LPAREN,
    TOK_RPAREN,
    TOK_COMMA,
    TOK_EXCL,
    TOK__INVALID
};

pub const Token = struct {
    type: TokenType,
    value: []const u8,
};

pub const Lexer = struct {
    src: []const u8,
    start_index: usize = 0,
    index: usize = 0,
    curr_line: usize = 1,

    pub fn next(self: *Lexer) !Token {
        while (true) {
            self.start_index = self.index;

            const c = self.peekAdvance() orelse return self.makeToken(.TOK_EOF);

            switch (c) {
                '\n' => {
                    self.curr_line += 1;
                    return self.makeToken(.TOK_NL);
                },
                ' ', '\t', '\r' => continue,
                '<', '>', '=', '!' => return self.makeOperatorToken(),
                '{' => return self.makeToken(.TOK_LBRACE),
                '}' => return self.makeToken(.TOK_RBRACE),
                '@' => return self.makeDirectiveToken(),
                '#' => {
                    self.handleComments();
                    continue;
                },
                '(' => return self.makeToken(.TOK_LPAREN),
                ')' => return self.makeToken(.TOK_RPAREN),
                ',' => return self.makeToken(.TOK_COMMA),
                '\'', '"' => return self.handleStrings(),
                else => {
                    if (std.ascii.isAlphanumeric(c) or c == '_') {
                        return self.makeIdentToken();
                    } else {
                        logger.outAdv(true, .syntax, self.curr_line, "unexpected {s}", .{if (c > 127) "non-ASCII character" else "character '" ++ [_]u8{c} ++ "'"});
                        return error.UnexpectedCharacter;
                    }
                },
            }
        }
    }

    fn makeOperatorToken(self: *Lexer) Token {
        const token_type: TokenType = blk: switch (self.peekPrev()) {
            '<' => if (self.peekAdvance() == '=') .TOK_LTE else { self.index -= 1; break :blk .TOK_LT; },
            '>' => if (self.peekAdvance() == '=') .TOK_GTE else { self.index -= 1; break :blk .TOK_GT; },
            '=' => if (self.peekAdvance() == '=') .TOK_EQ else { self.index -= 1; break :blk .TOK_ASSIGN; },
            '!' => if (self.peekAdvance() == '=') .TOK_NEQ else { self.index -= 1; break :blk .TOK_EXCL; },
            else => unreachable,
        };

        return self.makeToken(token_type);
    }

    fn peekAdvance(self: *Lexer) ?u8 {
        if (self.index >= self.src.len) return null;
        defer self.index += 1; // advance after returning the current character 

        return self.peek();
    }

    fn peekPrev(self: *Lexer) u8 {
        return self.src[self.index - 1];
    }

    fn peek(self: *Lexer) u8 {
        return self.src[self.index];
    }

    fn nextIdentifier(self: *Lexer) void {
        while (self.peekAdvance()) |c| {
            if (!std.ascii.isAlphanumeric(c) and c != '_') {
                self.index -= 1; // go back to the last valid character
                break;
            }
        }
    }

    fn makeToken(self: *Lexer, tt: TokenType) Token {
        return Token{ .type = tt, .value = self.src[self.start_index..self.index] };
    }
    
    fn makeIdentToken(self: *Lexer) Token {
        self.nextIdentifier();

        return self.makeToken(.TOK_IDENT);
    }

    fn makeDirectiveToken(self: *Lexer) !Token {
        self.start_index += 1; // start after @
        self.nextIdentifier();

        return self.makeToken(.TOK_DIRECTIVE);
    }

    fn handleComments(self: *Lexer) void {
        while (self.peekAdvance()) |c| {
            if (c == '\n') {
                self.index -= 1; // dont include the new line
                break;
            }
        }
    }
    
    fn handleStrings(self: *Lexer) !Token {
        const q = self.src[self.start_index]; // get which kind of quote opened the string (' or ")

        self.start_index += 1; // start after the opening quote

        while (self.peekAdvance()) |c| {
            if (c == '\n') break;

            if (c == q) {
                self.index -= 1; // end before the closing quote

                defer self.index += 1; // move past the closing quote after returning

                return self.makeToken(.TOK_STRING);
            }
        }

        logger.outAdv(true, .syntax, self.curr_line, "unterminated string", .{});
        return error.UnterminatedString;
    }
};
