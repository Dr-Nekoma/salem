const sal_data = @import("data.zig"); // FIXME: find better name
const Cell = sal_data.Cell;
const Stack = sal_data.Stack;
const std = @import("std");
const Int = std.meta.Int;

const Frame = struct {
    address: Cell,
    offset: sal_data.Header.Size,
    cache: sal_data.Code,
};

const Backtrack = struct {
    data: Cell,
    call: Cell,
    alt: Cell,
    handler: Cell,
};

alt: Stack(Cell),
back: Stack(Backtrack),
call: Stack(Frame),
data: Stack(Cell),
