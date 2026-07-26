const std = @import("std");
const logger = @import("logger.zig");

pub const TokenType = enum {
    TOK_EOF,
    TOK_NL,
    TOK_EQ,
    TOK_DEQ,
    TOK_NEQ,
    TOK_LBRACE,
    TOK_RBRACE,
    TOK_COMMENT,
    TOK_STRING,
    TOK_IDENT,
    TOK_DIRECTIVE,
    TOK_LPAREN,
    TOK_RPAREN,
    TOK_COMMA,
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

            const c = self.advance() orelse {
                return self.makeToken(.TOK_EOF);
            };

            switch (c) {
                '\n' => {
                    self.curr_line += 1;
                    return self.makeToken(.TOK_NL);
                },
                ' ', '\t', '\r' => continue,
                '=' => {
                    if (self.advance() != '=') {
                        self.index -= 1;
                        return self.makeToken(.TOK_EQ);
                    }
                    return self.makeToken(.TOK_DEQ);
                },
                '!' => {
                    if (self.advance() != '=') {
                        self.index -= 1;
                        continue;
                    }
                    return self.makeToken(.TOK_NEQ);
                },
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

    fn scanIdentifier(self: *Lexer) void {
        while (self.advance()) |c| {
            if (!std.ascii.isAlphanumeric(c) and c != '_') {
                self.index -= 1;
                break;
            }
        }
    }

    fn makeToken(self: *Lexer, tt: TokenType) Token {
        return Token{ .type = tt, .value = self.src[self.start_index..self.index] };
    }
    
    fn makeIdentToken(self: *Lexer) Token {
        self.scanIdentifier();

        return self.makeToken(.TOK_IDENT);
    }

    fn makeDirectiveToken(self: *Lexer) !Token {
        self.start_index += 1;
        self.scanIdentifier();

        return self.makeToken(.TOK_DIRECTIVE);
    }

    fn advance(self: *Lexer) ?u8 {
        if (self.index >= self.src.len) return null;
        defer self.index += 1;

        return self.src[self.index];
    }

    fn handleComments(self: *Lexer) void {
        while (self.advance()) |c| {
            if (c == '\n') {
                self.index -= 1;
                break;
            }
        }
    }
    
    fn handleStrings(self: *Lexer) !Token {
        const q = self.src[self.start_index]; // get which kind of quote opened the string (' or ")

        self.start_index += 1; // make the string start after the opening quote

        while (self.advance()) |c| {
            if (c == '\n') break;

            if (c == q) {
                self.index -= 1; // move back inside the string so closing quote wont be included

                defer self.index += 1; // move past the closing quote again

                return self.makeToken(.TOK_STRING);
            }
        }

        logger.outAdv(true, .syntax, self.curr_line, "unterminated string", .{});
        return error.UnterminatedString;
    }
};
