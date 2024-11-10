const std = @import("std");
const assert = std.debug.assert;

const data = @import("data.zig");

const Cell = data.Cell;
const Tag = data.Cell.Tag;
const Header = data.Header;

const EM = @import("EM.zig");

pub fn main() !void {}

test "simple test" {
    _ = data;
    _ = EM;
}
