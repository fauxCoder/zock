const std = @import("std");
const nock = @import("nock.zig");

fn infVar(v: anytype) void {
    std.debug.print("typeName: {s}\n", .{@typeName(@TypeOf(v))});
}

pub fn main() !u8 {
    const stdout = std.io.getStdOut().writer();

    var boss = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = boss.allocator();

    var args = std.process.args();

    var str: [*:0]u8 = undefined;

    var argc: usize = 0;
    while (args.next(allocator)) |arg| : (argc += 1) {
        str = try arg;
    }

    if (argc < 2) {
        try stdout.print("Please provide noun.\n", .{});
        return 1;
    } else if (argc > 2) {
        try stdout.print("Too many arguments. Perhaps you need to wrap in \"\"?\n", .{});
        return 1;
    }

    const rt = nock.Runtime{ .allocator = allocator };
    return try compute(rt, str);
}

fn compute(rt: nock.Runtime, str: [*:0]const u8) !u8 {
    const stdout = std.io.getStdOut().writer();
    const n = try rt.readNoun(str);
    try stdout.print("\n", .{});
    try nock.printNoun(n.*, stdout);
    try stdout.print(", gives\n", .{});
    const r = try rt.nock(n);
    try nock.printNoun(r.*, stdout);
    try stdout.print("\n", .{});
    rt.destroyNoun(r);
    return 0;
}

fn parseOnly(rt: nock.Runtime, str: [*:0]const u8) !u8 {
    const stdout = std.io.getStdOut().writer();
    try stdout.print("\n{s}, is\n", .{str});
    const n = try rt.readNoun(str);
    try nock.printNoun(n.*, stdout);
    try stdout.print("\n", .{});
    rt.destroyNoun(n);
    return 0;
}

fn getTestingRt() nock.Runtime {
    return nock.Runtime{ .allocator = std.testing.allocator };
}

const expect = std.testing.expect;

test "parse-cell" {
    const res = try parseOnly(getTestingRt(), "[0 1]");
    try expect(res == 0);
}

test "parse-list" {
    const res = try parseOnly(getTestingRt(), "[0 [1 [2 [3 [4 5]]]]]");
    try expect(res == 0);
}

test "parse-tree" {
    const res = try parseOnly(getTestingRt(), "[[0 1] [[2 3] 4]]");
    try expect(res == 0);
}

test "parse-terse-list" {
    const res = try parseOnly(getTestingRt(), "[0 1 2 3 4 5]");
    try expect(res == 0);
}

test "parse-terse-tree" {
    const res = try parseOnly(getTestingRt(), "[[0 1 [2 3] 4 5][[0 1] 2 3 4 5]]");
    try expect(res == 0);
}

test "nock-0-slot" {
    const res = try compute(getTestingRt(), "[[1 2 3] 0 7]");
    try expect(res == 0);
}

test "nock-1-id" {
    const res = try compute(getTestingRt(), "[0 1 42]");
    try expect(res == 0);
}

test "nock-3-wut-1" {
    const res = try compute(getTestingRt(), "[0 3 [1 [0 0]]]");
    try expect(res == 0);
}

test "nock-3-wut-2" {
    const res = try compute(getTestingRt(), "[0 3 [1 4]]");
    try expect(res == 0);
}

test "nock-4-lus" {
    const res = try compute(getTestingRt(), "[[99 41] 4 [0 3]]");
    try expect(res == 0);
}

test "nock-5-tis-1" {
    const res = try compute(getTestingRt(), "[[99 99] 5 [0 2] [0 3]]");
    try expect(res == 0);
}

test "nock-5-tis-2" {
    const res = try compute(getTestingRt(), "[[[1 2 3 4 5] [1 2 3 4 4]] 5 [0 2] [0 3]]");
    try expect(res == 0);
}
