const std = @import("std");
const Allocator = std.mem.Allocator;

const NounError = error{
    ReadError,
    UnnamedError,
};

pub const NounTag = enum {
    atom,
    cell,
};

pub const Noun = union(NounTag) {
    atom: u32,
    cell: struct {
        head: *Noun,
        tail: *Noun,
    },
};

pub fn printNoun(noun: Noun, writer: anytype) anyerror!void {
    switch (noun) {
        NounTag.atom => {
            try writer.print("{}", .{noun.atom});
        },
        NounTag.cell => {
            try writer.print("[", .{});
            try printNoun(noun.cell.head.*, writer);
            try writer.print(" ", .{});
            try printNoun(noun.cell.tail.*, writer);
            try writer.print("]", .{});
        },
    }
}

fn isDigit(c: u8) bool {
    return c >= '0' and c <= '9';
}

fn isOpen(c: u8) bool {
    return c == '[';
}

fn isClose(c: u8) bool {
    return c == ']';
}

fn isValid(c: u8) bool {
    return isDigit(c) or isOpen(c) or isClose(c);
}

fn isWhite(c: u8) bool {
    return c == ' ' or c == '\n';
}

pub const Runtime = struct {
    allocator: Allocator,

    pub fn readNoun(self: Runtime, s: [*:0]const u8) !*Noun {
        var input = s;

        var ready = std.ArrayList(?*Noun).init(self.allocator);
        defer ready.deinit();

        var current: usize = 0;
        while (input[current] != 0) {
            while (isWhite(input[current])) {
                current += 1;
            }

            var end: usize = current;
            while (isDigit(input[end])) {
                end += 1;
            }

            if (end > current) {
                defer current = end;
                const number = try std.fmt.parseInt(u32, input[current..end], 0);
                const atom = try self.allocator.create(Noun);
                atom.* = Noun{ .atom = number };
                try ready.append(atom);
            } else if (isOpen(input[current])) {
                defer current += 1;
                try ready.append(null);
            } else if (isClose(input[current])) {
                defer input += 1;
                if (ready.items.len < 3) {
                    return NounError.UnnamedError;
                }

                while (true) {
                    const t = ready.pop();
                    const h = ready.pop();
                    const cell = ready.items[ready.items.len - 1];
                    const new = try self.allocator.create(Noun);
                    new.* = Noun{ .cell = .{ .head = h.?, .tail = t.? } };

                    if (cell != null) {
                        try ready.append(new);
                    } else {
                        ready.items[ready.items.len - 1] = new;
                        break;
                    }
                }
            }
        }

        return ready.items[0].?;
    }

    pub fn createAtom(self: Runtime, number: u32) !*Noun {
        const ret = try self.allocator.create(Noun);
        ret.* = Noun{ .atom = number };
        return ret;
    }

    pub fn createCell(self: Runtime, head: *Noun, tail: *Noun) !*Noun {
        const ret = try self.allocator.create(Noun);
        ret.* = Noun{ .cell = .{ .head = head, .tail = tail } };
        return ret;
    }

    pub fn createCellOfAtoms(self: Runtime, head: u32, tail: u32) !*Noun {
        const ret = try self.allocator.create(Noun);
        ret.* = Noun{ .cell = .{ .head = try self.createAtom(head), .tail = try self.createAtom(tail) } };
        return ret;
    }

    pub fn createList(self: Runtime, list: []const *Noun) !*Noun {
        if (list.len > 1) {
            const ret = try self.allocator.create(Noun);
            ret.* = Noun{ .cell = .{ .head = list[0], .tail = try self.createList(list[1..]) } };
            return ret;
        } else if (list.len == 1) {
            return self.createCopy(list[0]);
        } else {
            return NockError.EmptySourceList;
        }
    }

    pub fn createCopy(self: Runtime, noun: *Noun) Allocator.Error!*Noun {
        switch (noun.*) {
            NounTag.atom => {
                return self.createAtom(noun.atom);
            },
            NounTag.cell => {
                const h = try self.createCopy(noun.cell.head);
                const t = try self.createCopy(noun.cell.tail);
                return self.createCell(h, t);
            },
        }
    }

    pub fn destroyNoun(self: Runtime, noun: *Noun) void {
        switch (noun.*) {
            NounTag.cell => {
                self.destroyNoun(noun.cell.tail);
                self.destroyNoun(noun.cell.head);
            },
            else => {},
        }
        self.allocator.destroy(noun);
    }

    const NockError = error{
        HaxZero,
        SlotZero,

        ArgumentMustBeCell,
        FormulaMustBeCell,
        FormulaTailMustBeCellFor11,

        EmptySourceList,

        UnnamedError,
    };
    const NockInnerError = NockError || Allocator.Error;
    pub fn nock(self: Runtime, n: *Noun) NockInnerError!*Noun {
        if (n.* != NounTag.cell) {
            return NockError.ArgumentMustBeCell;
        }
        const subj = n.cell.head;
        const form = n.cell.tail;

        if (form.* != NounTag.cell) {
            return NockError.FormulaMustBeCell;
        } else if (form.cell.head.* == NounTag.cell) {
            //      *[a [b c] d]            [*[a b c] *[a d]]
            const a1 = try self.createCopy(subj);
            const a2 = try self.createCopy(subj);
            const b = try self.createCopy(form.cell.head.cell.head);
            const c = try self.createCopy(form.cell.head.cell.tail);
            const d = try self.createCopy(form.cell.tail);
            self.destroyNoun(n);
            // zig fmt: off
            return self.createCell(
                try self.nock(try self.createList(&[_]*Noun{
                    a1,
                    b,
                    c,
                })),
                try self.nock(try self.createCell(
                    a2,
                    d,
                )),
            );
            // zig fmt: on
        }

        switch (form.cell.head.atom) {
            0 => {  //      *[a 0 b]                 /[b a]
                const a = try self.createCopy(subj);
                const b = try self.createCopy(form.cell.tail);
                self.destroyNoun(n);
                return self.slot(try self.createCell(b, a));
            },
            1 => {  //      *[a 1 b]                 b
                const b = try self.createCopy(form.cell.tail);
                self.destroyNoun(n);
                return b;
            },
            2 => {  //      *[a 2 b c]               *[*[a b] *[a c]]
                const a1 = try self.createCopy(subj);
                const a2 = try self.createCopy(subj);
                const b = try self.createCopy(form.cell.tail.cell.head);
                const c = try self.createCopy(form.cell.tail.cell.tail);
                self.destroyNoun(n);
                // zig fmt: off
                return self.nock(try self.createCell(
                    try self.nock(try self.createCell(
                        a1,
                        b,
                    )),
                    try self.nock(try self.createCell(
                        a2,
                        c,
                    )),
                ));
                // zig fmt: on
            },
            3 => {  //      *[a 3 b]                 ?*[a b]
                const a = try self.createCopy(subj);
                const b = try self.createCopy(form.cell.tail);
                self.destroyNoun(n);
                return self.wut(try self.nock(try self.createCell(a, b)));
            },
            4 => {  //      *[a 4 b]                 +*[a b]
                const a = try self.createCopy(subj);
                const b = try self.createCopy(form.cell.tail);
                self.destroyNoun(n);
                return self.lus(try self.nock(try self.createCell(a, b)));
            },
            5 => {  //      *[a 5 b c]               =[*[a b] *[a c]]
                const a1 = try self.createCopy(subj);
                const a2 = try self.createCopy(subj);
                const b = try self.createCopy(form.cell.tail.cell.head);
                const c = try self.createCopy(form.cell.tail.cell.tail);
                self.destroyNoun(n);
                // zig fmt: off
                return self.tis(try self.createCell(
                    try self.nock(try self.createCell(
                        a1,
                        b,
                    )),
                    try self.nock(try self.createCell(
                        a2,
                        c,
                    )),
                ));
                // zig fmt: on
            },
            6 => {  //      *[a 6 b c d]            *[a *[[c d] 0 *[[2 3] 0 *[a 4 4 b]]]]
                const a1 = try self.createCopy(subj);
                const a2 = try self.createCopy(subj);
                const b = try self.createCopy(form.cell.tail.cell.head);
                const c = try self.createCopy(form.cell.tail.cell.tail.cell.head);
                const d = try self.createCopy(form.cell.tail.cell.tail.cell.tail);
                self.destroyNoun(n);
                // zig fmt: off
                return try self.nock(try self.createCell(
                    a1,
                    try self.nock(try self.createList(&[_]*Noun{
                        try self.createCell(c, d),
                        try self.createAtom(0),
                        try self.nock(try self.createList(&[_]*Noun{
                            try self.createCellOfAtoms(2, 3),
                            try self.createAtom(0),
                            try self.nock(try self.createList(&[_]*Noun{
                                a2,
                                try self.createAtom(4),
                                try self.createAtom(4),
                                b,
                            })),
                        })),
                    }))
                ));
                // zig fmt: on
            },
            7 => {  //      *[a 7 b c]              *[*[a b] c]
                const a = try self.createCopy(subj);
                const b = try self.createCopy(form.cell.tail.cell.head);
                const c = try self.createCopy(form.cell.tail.cell.tail);
                self.destroyNoun(n);
                // zig fmt: off
                return try self.nock(try self.createCell(
                    try self.nock(try self.createCell(a, b)),
                    c
                ));
                // zig fmt: on
            },
            8 => {  //      *[a 8 b c]              *[[*[a b] a] c]
                const a1 = try self.createCopy(subj);
                const a2 = try self.createCopy(subj);
                const b = try self.createCopy(form.cell.tail.cell.head);
                const c = try self.createCopy(form.cell.tail.cell.tail);
                self.destroyNoun(n);
                // zig fmt: off
                return try self.nock(try self.createCell(
                    try self.createCell(
                        try self.nock(try self.createCell(
                            a1,
                            b
                        )),
                        a2
                    ),
                    c
                ));
                // zig fmt: on
            },
            9 => {  //      *[a 9 b c]              *[*[a c] 2 [0 1] 0 b]
                const a = try self.createCopy(subj);
                const b = try self.createCopy(form.cell.tail.cell.head);
                const c = try self.createCopy(form.cell.tail.cell.tail);
                self.destroyNoun(n);
                // zig fmt: off
                return try self.nock(try self.createList(&[_]*Noun{
                    try self.nock(try self.createCell(a, c)),
                    try self.createAtom(2),
                    try self.createCellOfAtoms(0, 1),
                    try self.createAtom(0),
                    b
                }));
                // zig fmt: on
            },
            10 => { //      *[a 10 [b c] d]         #[b *[a c] *[a d]]
                const a1 = try self.createCopy(subj);
                const a2 = try self.createCopy(subj);
                const b = try self.createCopy(form.cell.tail.cell.head.cell.tail);
                const c = try self.createCopy(form.cell.tail.cell.head.cell.tail);
                const d = try self.createCopy(form.cell.tail.cell.tail);
                self.destroyNoun(n);
                // zig fmt: off
                return self.hax(try self.createCell(
                    b,
                    try self.createCell(
                        try self.nock(try self.createCell(
                            a1,
                            c,
                        )),
                        try self.nock(try self.createCell(
                            a2,
                            d,
                        )),
                    ),
                ));
                // zig fmt: on
            },
            11 => {
                if (form.cell.tail.* == NounTag.cell) {
                    return NockError.FormulaTailMustBeCellFor11;
                } else if(form.cell.tail.cell.head.* == NounTag.cell) {
                    //      *[a 11 [b c] d]         *[[*[a c] *[a d]] 0 3]
                    const a1 = try self.createCopy(subj);
                    const a2 = try self.createCopy(subj);
                    const c = try self.createCopy(form.cell.tail.cell.head.cell.tail);
                    const d = try self.createCopy(form.cell.tail.cell.tail);
                    self.destroyNoun(n);
                    // zig fmt: off
                    return try self.nock(try self.createList(&[_]*Noun{
                        try self.createCell(
                            try self.nock(try self.createCell(a1, c)),
                            try self.nock(try self.createCell(a2, d))
                        ),
                        try self.createAtom(0),
                        try self.createAtom(3),
                    }));
                    // zig fmt: on
                } else {
                    //      *[a 11 b c]             *[a c]
                    const a = try self.createCopy(subj);
                    const c = try self.createCopy(form.cell.tail.cell.tail);
                    self.destroyNoun(n);
                    return try self.nock(try self.createCell(a, c));
                }
            },
            else => {
                return n;
            },
        }
    }

    fn slot(self: Runtime, n: *Noun) NockInnerError!*Noun {
        if (n.* != NounTag.cell) {
            return NockError.UnnamedError;
        }
        if (n.cell.head.* != NounTag.atom) {
            return NockError.UnnamedError;
        }
        const i = n.cell.head.atom;
        if (i == 0) {
            return NockError.SlotZero;
        } else if (i == 1) {
            const a = try self.createCopy(n.cell.tail);
            self.destroyNoun(n);
            return a;
        } else if (i == 2) {
            if (n.cell.tail.* != NounTag.cell) {
                return NockError.UnnamedError;
            }
            const a = try self.createCopy(n.cell.tail.cell.head);
            self.destroyNoun(n);
            return a;
        } else if (i == 3) {
            if (n.cell.tail.* != NounTag.cell) {
                return NockError.UnnamedError;
            }
            const a = try self.createCopy(n.cell.tail.cell.tail);
            self.destroyNoun(n);
            return a;
        } else if (i % 2 == 0) {
            const b = try self.createCopy(n.cell.tail);
            self.destroyNoun(n);
            // zig fmt: off
            return self.slot(try self.createCell(
                try self.createAtom(2),
                try self.slot(try self.createCell(
                    try self.createAtom(i / 2),
                    b,
                )),
            ));
            // zig fmt: on
        } else {
            const b = try self.createCopy(n.cell.tail);
            self.destroyNoun(n);
            // zig fmt: off
            return self.slot(try self.createCell(
                try self.createAtom(3),
                try self.slot(try self.createCell(
                    try self.createAtom(i / 2),
                    b,
                )),
            ));
            // zig fmt: on
        }
    }

    fn wut(self: Runtime, n: *Noun) NockInnerError!*Noun {
        const ret = self.createAtom(if (n.* == NounTag.cell) 0 else 1);
        self.destroyNoun(n);
        return ret;
    }

    fn lus(self: Runtime, n: *Noun) NockInnerError!*Noun {
        _ = self;
        if (n.* == NounTag.cell) {
            return NockError.UnnamedError;
        }
        n.atom += 1;
        return n;
    }

    fn same(self: Runtime, h: *Noun, t: *Noun) bool {
        if (h.* == NounTag.atom) {
            if (t.* == NounTag.atom) {
                return h.atom == t.atom;
            } else {
                return false;
            }
        } else if (t.* == Noun.atom) {
            return false;
        }

        return self.same(h.cell.head, t.cell.head) and self.same(h.cell.tail, t.cell.tail);
    }

    fn tis(self: Runtime, n: *Noun) NockInnerError!*Noun {
        if (n.* == NounTag.atom) {
            return NockError.UnnamedError;
        }

        const ret = self.same(n.cell.head, n.cell.tail);
        self.destroyNoun(n);
        return if (ret) try self.createAtom(0) else try self.createAtom(1);
    }

    fn hax(self: Runtime, n: *Noun) NockInnerError!*Noun {
        if (n.* != NounTag.cell) {
            return NockError.UnnamedError;
        }
        if (n.cell.head.* != NounTag.atom) {
            return NockError.UnnamedError;
        }
        const i = n.cell.head.atom;
        if (i == 0) {
            return NockError.HaxZero;
        } else if (i == 1) {
            const a = try self.createCopy(n.cell.tail.cell.head);
            self.destroyNoun(n);
            return a;
        } else if (i % 2 == 0) {
            const b = try self.createCopy(n.cell.tail.cell.head);
            const c1 = try self.createCopy(n.cell.tail.cell.tail);
            const c2 = try self.createCopy(n.cell.tail.cell.tail);
            self.destroyNoun(n);
            // zig fmt: off
            return self.hax(try self.createCell(
                try self.createAtom(i / 2),
                try self.createCell(
                    try self.createCell(
                        b,
                        try self.slot(try self.createCell(
                            try self.createAtom(i + 1),
                            c1,
                        )),
                    ),
                    c2,
                )
            ));
            // zig fmt: on
        } else {
            const b = try self.createCopy(n.cell.tail.cell.head);
            const c1 = try self.createCopy(n.cell.tail.cell.tail);
            const c2 = try self.createCopy(n.cell.tail.cell.tail);
            self.destroyNoun(n);
            // zig fmt: off
            return self.hax(try self.createCell(
                try self.createAtom(i / 2),
                try self.createCell(
                    try self.createCell(
                        b,
                        try self.slot(try self.createCell(
                            try self.createAtom(i - 1),
                            c1,
                        )),
                    ),
                    c2,
                )
            ));
            // zig fmt: on
        }
    }
};
