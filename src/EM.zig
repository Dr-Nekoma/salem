const data = @import("data.zig");
const Cell = data.Cell;
const Stack = data.Stack;
const std = @import("std");
const Int = std.meta.Int;

const Frame = struct {
    address: Cell,
    offset: data.Header.Size,
    cache: data.Code,
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
