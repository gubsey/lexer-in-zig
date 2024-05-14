const std = @import("std");

const Symbol = enum {
    @"if",
    then,
    @"else",
    where,

    @"(",
    @")",
    @"[",
    @"]",

    @"=",
    @"+",
    @"-",
    @"*",
    @":",
    @"..",
    @"`",
    @"|",
    @"<-",
    @"==",
    @"/=",
    @",",
};

const Scalar = union(enum) {
    string: []const u8,
    number: []const u8,
};

const Lexeme = union(enum) {
    symbol: Symbol,
    name: []const u8,
    unknown: u8,
};

const State = enum {
    New,
    String,
    Operator,
};

const Lexemes = struct {
    items: []Lexeme,
    alloc: std.mem.Allocator,

    fn deinit(self: @This()) void {
        for (self.items) |x| {
            switch (x) {
                .name => |n| self.alloc.free(n),
                else => {},
            }
        }

        self.alloc.free(self.items);
    }
};

fn lex(file: []const u8, alloc: std.mem.Allocator) !Lexemes {
    var r = std.ArrayList(Lexeme).init(alloc);
    defer r.deinit();

    var lb = LexemeBuilder.init(alloc);
    defer lb.deinit();
    lb.iter(file);

    while (try lb.next()) |x| {
        try r.append(x);
    }

    return Lexemes{
        .items = try r.toOwnedSlice(),
        .alloc = alloc,
    };
}

const LexemeBuilder = struct {
    acc: std.ArrayList(u8),
    alloc: std.mem.Allocator,
    state: State = .New,
    buffer: ?[]const u8 = null,
    buffer_pos: usize = 0,

    fn init(alloc: std.mem.Allocator) @This() {
        return .{
            .acc = std.ArrayList(u8).init(alloc),
            .alloc = alloc,
        };
    }

    fn deinit(self: *@This()) void {
        self.acc.deinit();
    }

    fn iter(self: *@This(), buffer: []const u8) void {
        self.buffer = buffer;
        self.buffer_pos = 0;
    }

    fn next(self: *@This()) !?Lexeme {
        var r: ?Lexeme = null;
        const buf = self.buffer orelse return error.iter_not_initialized;
        while (self.buffer_pos < buf.len) : (self.buffer_pos += 1) {
            if (r) |_| {
                break;
            }
            switch (buf[self.buffer_pos]) {
                'a'...'z',
                'A'...'Z',
                '0'...'9',
                => |b| {
                    switch (self.state) {
                        .Operator => {
                            r = try self.complete_acc();
                        },
                        .New, .String => {},
                    }

                    self.state = .String;
                    try self.acc.append(b);
                },
                '=',
                '/',
                '+',
                '-',
                '*',
                '.',
                ',',
                ':',
                '|',
                '<',
                '`',
                => |b| {
                    switch (self.state) {
                        .String => {
                            r = try self.complete_acc();
                        },
                        .New, .Operator => {},
                    }

                    self.state = .Operator;
                    try self.acc.append(b);
                },
                '[',
                ']',
                '(',
                ')',
                => |b| {
                    switch (self.state) {
                        .New => {
                            try self.acc.append(b);
                            r = try self.complete_acc();
                        },
                        else => {
                            r = try self.complete_acc();
                            break;
                        },
                    }
                },
                ' ',
                '\t',
                '\r',
                '\n',
                => {
                    switch (self.state) {
                        .New => {},
                        else => {
                            r = try self.complete_acc();
                        },
                    }
                },
                else => |b| {
                    self.buffer_pos += 1;
                    return Lexeme{ .unknown = b };
                },
            }
        }

        if (r) |_| {} else {
            if (self.acc.items.len > 0) {
                r = try self.complete_acc();
            }
        }

        return r;
    }

    fn complete_acc(self: *@This()) !Lexeme {
        const str = try self.acc.toOwnedSlice();

        self.state = .New;

        if (std.meta.stringToEnum(Symbol, str)) |case| {
            self.alloc.free(str);
            return .{ .symbol = case };
        } else {
            return .{ .name = str };
        }
    }
};

test "haskell example" {
    const code =
        \\primes = filterPrime [2..] where
        \\filterPrime (p:xs) =
        \\p : filterPrime [x | x <- xs, x `mod` p /= 0]
    ;
    const lexemes = try lex(code, std.testing.allocator);
    defer lexemes.deinit();
}

test "if then else" {
    const stderr = std.io.getStdErr().writer();
    try stderr.writeByte('\n');

    const lexemes = try lex("if x== y then x else y", std.testing.allocator);
    defer lexemes.deinit();

    const expected = [_]Lexeme{
        .{ .symbol = Symbol.@"if" },
        .{ .name = "x" },
        .{ .symbol = .@"==" },
        .{ .name = "y" },
        .{ .symbol = .then },
        .{ .name = "x" },
        .{ .symbol = Symbol.@"else" },
        .{ .name = "y" },
    };

    if (lexemes.items.len != expected.len) {
        return error.@"lexemes len != expected len";
    }

    for (lexemes.items, expected) |l, e| {
        if (@intFromEnum(l) != @intFromEnum(e)) {
            std.log.err("{s} != {s}", .{ @tagName(l), @tagName(e) });
            return error.different_lexeme_types;
        }

        switch (l) {
            .name => {
                if (!std.mem.eql(u8, l.name, e.name)) {
                    std.log.err("name inequality {s} != {s}", .{ l.name, e.name });
                    return error.name_inequality;
                }
            },
            .symbol => {
                if (l.symbol != e.symbol) {
                    std.log.err("symbol inequality {} != {}", .{ l, e });
                    return error.symbol_inequality;
                }
            },
            .unknown => {
                if (l.unknown != e.unknown) {
                    std.log.err("other inequality", .{});
                }
            },
        }
    }
}
