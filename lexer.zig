const std = @import("std");

const Symbol = enum {
    @"if",
    then,
    @"else",
    @"==",
};

const Scalar = union(enum) {
    string: []const u8,
    number: []const u8,
};

const Lexeme = union(enum) {
    symbol: Symbol,
    name: []const u8,
};

const State = enum {
    New,
    String,
    Operator,
};

const LexemeBuilder = struct {
    acc: std.ArrayList(Lexeme),
    alloc: std.mem.Allocator,
    state: State = .New,
    buffer: ?[]const u8,
    buffer_pos: usize = 0,

    fn init(alloc: std.mem.Allocator) @This() {
        return .{
            .acc = std.ArrayList(Lexeme).init(alloc),
            .alloc = alloc,
        };
    }

    fn deinit(self: @This()) void {
        self.acc.deinit();
    }

    fn iter(self: @This(), buffer: []const u8) void {
        self.buffer = buffer;
    }

    fn next(self: @This()) !?Lexeme {
        var r: ?Lexeme = null;
        const buf = self.buffer orelse return error.iter_not_initialized;
        while (self.buffer_pos < buf.len and !r) : (self.buffer_pos += 1) {
            switch (buf[self.buffer_pos]) {
                'a'...'z',
                'A'...'Z',
                => |b| {
                    switch (self.state) {
                        .Operator => {
                            r = try self.complete_acc();
                            continue;
                        },
                        .New, .String => {},
                    }

                    self.state = .String;
                    try self.acc.append(b);
                },
                '=' => |b| {
                    switch (self.state) {
                        .String => {
                            r = try self.complete_acc();
                            continue;
                        },
                        .String, .Operator => {},
                    }

                    self.state = .Operator;
                    try self.acc.append(b);
                },
                ' ' => {
                    switch (self.state) {
                        .New => {},
                        .String, .Operator => {
                            r = try self.complete_acc();
                            continue;
                        },
                    }

                    self.state = .New;
                },
            }
        }

        return r;
    }

    fn complete_acc(self: @This()) !Lexeme {
        const str = try self.acc.toOwnedSlice();
        defer self.alloc.free(str);
        self.state = .New;

        if (std.meta.stringToEnum(Symbol, str)) |case| {
            return .{ .symbol = case };
        } else {
            return .{ .name = str };
        }
    }
};

fn lex(file: []const u8, alloc: std.mem.Allocator) ![]Lexeme {
    var state = State.New;

    var r = std.ArrayList(Lexeme).init(alloc);
    defer r.deinit();

    var acc = std.ArrayList(u8).init(alloc);

    for (file) |b| {
        switch (b) {
            'a'...'z',
            'A'...'Z',
            => {
                try acc.append(b);
                state = .String;
            },
            ' ',
            '\n',
            '\t',
            => {
                switch (state) {
                    .New => {},
                    .String, .Operator => {},
                }
            },
            '=',
            => {
                switch (state) {
                    .New => {
                        try acc.append(b);
                        state = .Operator;
                    },
                    .String => {
                        const str = try acc.toOwnedSlice();
                        if (std.meta.stringToEnum(Symbol, str)) |case| {
                            try r.append(.{ .symbol = case });
                            alloc.free(str);
                        } else {
                            try r.append(.{ .name = str });
                        }

                        state = .Operator;
                        try acc.append(b);
                    },
                    .Operator => {
                        try acc.append(b);
                    },
                }
            },
            else => |x| {
                std.log.err("else {}", .{x});
                unreachable;
            },
        }
    }
    return try r.toOwnedSlice();
}

test "if then else" {
    const lexemes = try lex("if x == y then x else y", std.testing.allocator);

    for (lexemes) |l| {
        switch (l) {
            .name => |n| std.log.err("name: {s}", .{n}),
            .symbol => |s| std.log.err("symb: {}", .{s}),
        }
    }

    std.testing.allocator.free(lexemes);
}
