const std = @import("std");
const Int = std.meta.Int;

pub const Tag = enum(u2) {
    const Self = @This();

    Code,
    Fixnum,
    Constant,
    Pointer,

    pub inline fn is_ptr(self: Self) bool {
        return self == .Pointer;
    }

    pub inline fn is_immediate(self: Self) bool {
        return !self.is_ptr();
    }
};

pub const Instruction = u6; // not sure the exact size to use here
const instructions_per_cell = (@bitSizeOf(usize) - @bitSizeOf(Tag)) / @bitSizeOf(Instruction);
pub const Code = [instructions_per_cell]Instruction;

pub const Block_Type = enum(Int(.unsigned, 8 - @bitSizeOf(Tag))) {
    ShortStr,
    Str,
    StrBranch,
    ShortList,
    List,
    ListBranch,
    ShortDict,
    DictBranch,
    Dict,
    ShortSet,
    SetBranch,
    Set,
    ShortMset,
    MsetBranch,
    Mset,
    Fn,
    _,
};

pub const Header = packed struct(usize) {
    pub const Size = Int(.unsigned, 8 * (@bitSizeOf(usize) / 32));
    safety_tag: Tag = .Fixnum,
    type_tag: Block_Type,
    size: Size,
    rc: Int(.signed, @bitSizeOf(usize) - @bitSizeOf(u8) - @bitSizeOf(Size)),

    const Self = @This();
    pub fn to_Block(self: *Self) type {
        return switch (self.type_tag) {
            inline else => |tag| Block(tag),
        };
    }
};

pub const Constant = enum (Cell.Udata) {
    _
};

// it would be nice if we could use a tagged union for this
pub const Cell = packed struct(usize) {
    const Self = @This();
    const size = @bitSizeOf(usize);
    const data_size = size - @bitSizeOf(Tag);

    tag: Tag,
    data: IData,

    pub const U = usize;
    pub const I = isize;
    pub const UData = Int(.unsigned, data_size);
    pub const IData = Int(.signed, data_size);

    pub inline fn is_ptr(self: Self) bool {
        return self.tag.is_ptr();
    }

    pub inline fn is_fixnum(self: Self) bool {
        return self.tag == .Fixnum;
    }

    pub inline fn is_immediate(self: Self) bool {
        return self.tag.is_immediate();
    }

    pub inline fn to_UData(self: Self) UData {
        return @as(UData, @bitCast(self.data));
    }

    pub inline fn fixnum(n: IData) Self {
        return .{ .tag = .Fixnum, .data = n };
    }

    pub inline fn to_ptr(self: Self) ?*Header {
        return if (self.is_ptr)
            @as(?*Header, @bitCast(Self{ .data = self.data, .tag = 0 }))
        else
            null;
    }

    pub const unspecified = Self{ .tag = .constant, .data = 0 };
};

pub fn Block(comptime block_type: Block_Type) type {
    const size = switch (block_type) {
        .Str, .List, .Small => 4,
        .ShortStr, .ShortList, .ShortSet, .Fn => 16,
        .StrBranch, .ListBranch => 18,
        .Set, .Dict, .Mset => 20,
        .ShortDict, .ShortMset => 32,
        else => @compileError("Unknown block type"),
    };
    if (size < 1) @compileError("Blocks must have at least one element");
    return extern struct {
        header: Header,
        body: [capacity]Element,

        pub const is_binary = block_type == .ShortStr;
        pub const capacity = if (is_binary) size * @sizeOf(Cell) else size;
        const Element = if (is_binary) u8 else Cell;
    };
}

pub fn Stack(comptime Element: type) type {
    const stack_index_width = 4;
    const StackIndex = Int(.unsigned, stack_index_width);
    const stack_depth = 1 << stack_index_width;
    return struct {
        const Self = @This();

        overflow: Cell,
        base: StackIndex,
        next: StackIndex,
        is_full: bool,
        stack: [stack_depth]Element,

        pub fn top(self: *const Self) ?*Element {
            const base = self.base;
            const next = self.next;
            if (base == next and !self.is_full) return null;
            return &(self.stack[next -% 1]);
        }
    };
}
