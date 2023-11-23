const std = @import("std");
const builtin = @import("builtin");
const ArrayList = std.ArrayList;
const Int = std.meta.Int;
const assert = std.debug.assert;

const data = @import("data.zig");

const Cell = data.Cell;
const Tag = data.Tag;
const Header = data.Header;

const EM = @import("EM.zig");

pub fn main() !void {
    const stdout_file = std.io.getStdOut().writer();
    var bw = std.io.bufferedWriter(stdout_file);
    const stdout = bw.writer();

    try stdout.print(
        "EM size: {}\nFixnum size: {}\nCell size: {}\nHeader size: {}\n",
        .{
            @sizeOf(EM),
            @bitSizeOf(Cell.IData),
            @bitSizeOf(Cell),
            @bitSizeOf(Header),
        },
    );
    const byte: u8 = 255;
    const shiftable: u2 = 2;
    try stdout.print("Shift: {any}\n", .{shiftable << 1});
    try stdout.print(
        "Sample fixnums: {}, {}, {}, {}, {}, {}\n",
        .{
            Cell.fixnum(0).data,
            Cell.fixnum(1).data,
            Cell.fixnum(2).data,
            Cell.fixnum(byte).data,
            Cell.fixnum(33).data,
            Cell.fixnum(-1).data,
        },
    );
    //_ = EM.init(???);
    try stdout.print("Optional Cell size: {}\n", .{@bitSizeOf(?Cell)});
    try stdout.print("align: {}\n", .{@alignOf(Cell)});
    const num = Cell.fixnum(413).data;
    try stdout.print("413: {?}\n", .{num});
    try stdout.print("endianness: {}, {}\n", .{ 4, @as(Cell.U, @bitCast(Cell.fixnum(4))) });
    try bw.flush();
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit();
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
