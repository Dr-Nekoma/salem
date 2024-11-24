const std = @import("std");
const Int = std.meta.Int;

const assert = std.debug.assert;

pub fn Padding(comptime size: comptime_int) type {
    return enum(Int(.unsigned, size)) {
        padding = 0,
    };
}

pub const Cell = packed struct(usize) {
    pub const tag_size = 2;
    pub const payload_size = @bitSizeOf(*usize) - tag_size;

    comptime {
        if (@ctz(@as(usize, @alignOf(*usize))) < tag_size) {
            @compileError("Unsupported architecture");
        }
    }

    pub const Union = Cell_Union;
    pub const Tag = Cell_Tag;

    comptime {
        assert(@bitSizeOf(Tag) == tag_size);
    }

    pub const U = Int(.unsigned, payload_size);
    pub const I = Int(.signed, payload_size);

    pub const Fixnum = Int(.signed, payload_size - 1);
    pub const Header = packed struct(Fixnum) {
        _: Fixnum,
    };

    tag: Tag,
    payload: U,

    comptime {
        assert(@typeInfo(Union).@"union".tag_type == Tag);
        assert(tag_size == @bitSizeOf(Tag));
        for (@typeInfo(Union).@"union".fields) |field| {
            if (@typeInfo(field.type) == .pointer) {
                assert(tag_size <= @ctz(@as(usize, @alignOf(field.type))));
            } else {
                assert(@bitSizeOf(field.type) + tag_size == @bitSizeOf(usize));
            }
            const ptr: Cell = .{
                .tag = @unionInit(Union, field.name, undefined),
                .payload = 1 << (@alignOf(*Cell) - tag_size),
            };
            const ptr_roundtrip = Cell.from_union(ptr.to_union());
            assert(ptr.payload == ptr_roundtrip.payload);
            assert(ptr.tag == ptr_roundtrip.tag);
        }
    }

    pub fn from_union(source: Union) Cell {
        switch (source) {
            inline else => |payload| {
                const Payload = @TypeOf(payload);
                return .{
                    .tag = source,
                    .payload = if (@typeInfo(Payload) == .pointer)
                        @intCast(@intFromPtr(payload) >> tag_size)
                    else if (@typeInfo(Payload) == .@"enum")
                        @intFromEnum(payload)
                    else
                        @bitCast(payload),
                };
            },
        }
    }

    pub fn to_union(self: Cell) Union {
        switch (self.tag) {
            inline else => |tag| {
                const Payload = std.meta.TagPayload(Union, tag);
                const mask: usize = comptime @truncate(
                    std.math.maxInt(usize) << @alignOf(*Cell),
                );
                return @unionInit(
                    Union,
                    @tagName(tag),
                    if (@typeInfo(Payload) == .pointer)
                        @ptrFromInt(@as(usize, @bitCast(self)) & mask)
                    else if (@typeInfo(Payload) == .@"enum")
                        @enumFromInt(self.payload)
                    else
                        @bitCast(self.payload),
                );
            },
        }
    }
};

const Cell_Union = union(Cell_Tag) {
    shared_pointer: *Cell,
    unique_pointer: *Cell,
    constant: Constant,
    code: Code,

    pub inline fn from_cell(cell: Cell) Cell.Union {
        return cell.to_union();
    }

    pub inline fn is_ptr(self: Cell.Union) bool {
        return @as(Cell_Tag, self).is_ptr();
    }

    pub inline fn is_immediate(self: Cell.Union) bool {
        return @as(Cell_Tag, self).is_immediate();
    }
};

const Cell_Tag = enum(Int(.unsigned, Cell.tag_size)) {
    shared_pointer = 0b00,
    unique_pointer = 0b10,
    constant = 0b01,
    code = 0b11,

    pub inline fn is_ptr(self: Cell_Tag) bool {
        return @intFromEnum(self) & 0b1 == 0;
    }

    pub inline fn is_immediate(self: Cell_Tag) bool {
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

pub const Code = packed struct(Cell.U) {
    _: Padding(@bitSizeOf(Cell.U) - @bitSizeOf(Payload)) = .padding,
    payload: Payload,

    pub const instructions_per_cell = @bitSizeOf(Cell.U) / @bitSizeOf(Instruction);

    pub const Payload =
        Int(.unsigned, @bitSizeOf(Instruction) * instructions_per_cell);

    pub inline fn current_instruction(self: Code) Instruction {
        return @enumFromInt(
            self.payload >> @bitSizeOf(Payload) - @bitSizeOf(Instruction),
        );
    }
    pub inline fn step(self: Code) Code {
        return .{ .payload = self.payload << @bitSizeOf(Instruction) };
    }
    pub fn to_array(self: Code) [instructions_per_cell]Instruction {
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

pub const Block_Type = enum(Int(.unsigned, 8 - @bitSizeOf(Cell_Tag))) {
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

pub const Header = packed struct(Cell.U) {
    const Safety_Tag = enum(@typeInfo(Cell_Tag).@"enum".tag_type) {
        constant = @intFromEnum(Cell_Tag.constant),
    };
    pub const Size = Int(.unsigned, 8 * (@bitSizeOf(Cell.U) / 32));
    safety_tag: Safety_Tag = .constant,
    type_tag: Block_Type,
    size: Size,

    pub fn to_Block(self: *Header) type {
        return switch (self.type_tag) {
            inline else => |tag| Block(tag),
        };
    }
};

pub const Constant = enum(Cell.U) { _ };

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

test "everything" {
    _ = Cell;
    _ = Instruction;
    _ = Code;
}
