const std = @import("std");
const nock = @import("nock.zig");

pub fn main() !u8 {
    const cerr = std.io.getStdErr().writer();

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var args = try std.process.argsWithAllocator(allocator);
    defer args.deinit();

    var str: [:0]const u8 = undefined;

    var argc: usize = 0;
    while (args.next()) |arg| : (argc += 1) {
        str = arg;
    }

    if (argc < 2) {
        try cerr.print("Please provide noun.\n", .{});
        return 1;
    } else if (argc > 2) {
        try cerr.print("Too many arguments. Perhaps you need to wrap in \"\"?\n", .{});
        return 1;
    }

    const rt = nock.Runtime{ .allocator = allocator };
    return try compute(rt, str);
}

fn compute(rt: nock.Runtime, str: [*:0]const u8) !u8 {
    const cerr = std.io.getStdErr().writer();
    const n = try rt.readNoun(str);
    try cerr.print("\n", .{});
    try nock.printNoun(n.*, cerr);
    try cerr.print(", gives\n", .{});
    const r = try rt.nock(n);
    defer rt.destroyNoun(r);
    try nock.printNoun(r.*, cerr);
    try cerr.print("\n", .{});
    return 0;
}

fn parseOnly(rt: nock.Runtime, str: [*:0]const u8) !u8 {
    const cerr = std.io.getStdErr().writer();
    try cerr.print("\n{s}, is\n", .{str});
    const n = try rt.readNoun(str);
    defer rt.destroyNoun(n);
    try nock.printNoun(n.*, cerr);
    try cerr.print("\n", .{});
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
