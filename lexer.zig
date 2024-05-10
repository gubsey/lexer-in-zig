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
                    .String, .Operator => {
                        const str = try acc.toOwnedSlice();
                        defer alloc.free(str);
                        if (std.meta.stringToEnum(Symbol, str)) |case| {
                            try r.append(.{ .symbol = case });
                        } else {
                            try r.append(.{ .name = str });
                        }

                        state = .New;
                        acc.clearAndFree();
                    },
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
            else => unreachable,
        }
    }
    return try r.toOwnedSlice();
}

test "if then else" {
    const lexemes = try lex("if x== y then x else y", std.testing.allocator);

    for (lexemes) |l| {
        switch (l) {
            .name => |n| std.log.err("name: {s}", .{n}),
            .symbol => |s| std.log.err("symb: {}", .{s}),
        }
    }

    std.testing.allocator.free(lexemes);
}
