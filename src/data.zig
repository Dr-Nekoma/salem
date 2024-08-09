const std = @import("std");
const Int = std.meta.Int;

const assert = std.debug.assert;

pub const Tag = enum(u2) {
    shared_pointer = 0b00,
    unique_pointer = 0b10,
    constant = 0b01,
    code = 0b11,

    pub inline fn is_unique(self: Tag) bool {
        return self == .unique_pointer;
    }

    pub inline fn is_ptr(self: Tag) bool {
        return @as(u1, @truncate(@intFromEnum(self))) == 0;
    }

    pub inline fn is_immediate(self: Tag) bool {
        return !self.is_ptr();
    }
};

pub const Instruction = enum(u5) {
    skip = 0, // normally not explicitly used

    // stack manipulation
    dup,
    pop,
    swap,
    hide,
    show,
    forget,

    // data primitives
    lit,
    self,
    @"var",
    unvar,
    tag,
    untag,

    // basic operations
    ord,
    is_zero,
    bit_not,
    bit_and,
    arithmetic_shift,
    add,
    mul,
    sub,
    div,
    divmod,

    // control flow
    // skip technically belongs here
    if_else,
    then,
    call,
    recur,
    tailcall,
    tailrecur,
    ret,
};

pub const Code = packed struct(Cell.u) {
    tag: Tag = .code,
    _: Padding = 0,
    payload: Payload,

    pub const instructions_per_cell = @bitSizeOf(Cell.udata) / @bitSizeOf(Instruction);

    pub const Payload =
        Int(.unsigned, @bitSizeOf(Instruction) * instructions_per_cell);

    pub const Padding =
        Int(.unsigned, @bitSizeOf(Cell.u) - @bitSizeOf(Payload) - @bitSizeOf(Tag));

    pub inline fn current_instruction(self: Code) Instruction {
        assert(self.tag == .code);
        return @enumFromInt(
            self.payload >> @bitSizeOf(Payload) - @bitSizeOf(Instruction),
        );
    }
    pub inline fn step(self: Code) Code {
        assert(self.tag == .code);
        return .{ .payload = self.payload << @bitSizeOf(Instruction) };
    }
    pub fn to_array(self: Code) [instructions_per_cell]Instruction {
        assert(self.tag == .code);
        // for debugging
        var code = self;
        var instructions: [instructions_per_cell]Instruction = undefined;
        for (instructions, 0..) |_, index| {
            instructions[index] = code.current_instruction();
            code = code.step();
        }
        return instructions;
    }
    pub fn from_array(instructions: [instructions_per_cell]Instruction) Code {
        var code: Payload = 0;
        for (instructions) |inst| {
            code <<= @bitSizeOf(Instruction);
            code |= @intFromEnum(inst);
        }
        return .{ .payload = code };
    }
};

pub const Block_Type = enum(Int(.unsigned, 8 - @bitSizeOf(Tag))) {
    short_str,
    str_branch,
    str,
    short_list,
    list_branch,
    list,
    short_dict,
    dict_branch,
    dict,
    short_set,
    set_branch,
    set,
    short_mset,
    mset_branch,
    mset,
    @"fn",
};

pub const Header = packed struct(Cell.u) {
    pub const Size = Int(.unsigned, 8 * (@bitSizeOf(Cell.u) / 32));
    safety_tag: Tag = .constant,
    type_tag: Block_Type,
    size: Size,
    rc: Int(.signed, @bitSizeOf(Cell.u) - @bitSizeOf(u8) - @bitSizeOf(Size)),

    pub fn to_Block(self: *Header) type {
        return switch (self.type_tag) {
            inline else => |tag| Block(tag),
        };
    }
};

pub const Constant = enum(Cell.udata) { _ };

// it would be nice if we could use a tagged union for this
pub const Cell = packed struct(usize) {
    const data_size = @bitSizeOf(u) - @bitSizeOf(Tag);

    tag: Tag,
    data: idata,

    pub const u = usize;
    pub const i = isize;
    pub const udata = Int(.unsigned, data_size);
    pub const idata = Int(.signed, data_size);

    pub inline fn is_ptr(self: Cell) bool {
        return self.tag.is_ptr();
    }

    pub inline fn is_immediate(self: Cell) bool {
        return self.tag.is_immediate();
    }

    pub inline fn to_udata(self: Cell) udata {
        return @as(udata, @bitCast(self.data));
    }

    pub inline fn to_mutable(self: Cell) ?*Header {
        return if (self.is_unique())
            @constCast(self.to_ptr().?)
        else
            null;
    }

    pub inline fn to_ptr(self: Cell) ?*const Header {
        return if (self.is_ptr())
            @as(?*const Header, @bitCast(@as(u, self.data) << @bitSizeOf(Tag)))
        else
            null;
    }

    pub const unspecified = Cell{ .tag = .constant, .data = 0 };
};

pub fn Block(comptime block_type: Block_Type) type {
    const size = switch (block_type) {
        .Str, .List, .Small => 4,
        .ShortStr, .ShortList, .ShortSet, .Fn => 16,
        .StrBranch, .ListBranch => 18,
        .Set, .Dict, .Mset => 20,
        .ShortDict, .ShortMset => 32,
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
    const Stack_Index = Int(.unsigned, stack_index_width);
    const stack_depth = 1 << stack_index_width;
    return struct {
        overflow: Cell,
        base: Stack_Index,
        next: Stack_Index,
        is_full: bool,
        stack: [stack_depth]Element,

        pub fn top(self: *const @This()) ?*Element {
            const base = self.base;
            const next = self.next;
            if (base == next and !self.is_full) return null;
            return &(self.stack[next -% 1]);
        }
    };
}
