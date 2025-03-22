pub const Cell = packed struct(usize) {
    tag: Tag,
    payload: Payload,

    pub fn init(tag: Tag, payload: Payload) Cell {
        return .{ .tag = tag, .payload = payload };
    }

    pub const Tag = enum(utag) {
        shared_pointer = 0b00,
        unique_pointer = 0b10,
        constant = 0b01,
        code = 0b11,

        pub fn is_ptr(self: Tag) bool {
            return @intFromEnum(self) & 0b1 == 0;
        }

        pub fn is_immediate(self: Tag) bool {
            return !self.is_ptr();
        }
    };

    pub const upayload = Int(.unsigned, payload_size);
    pub const utag = Int(.unsigned, tag_size);

    pub const Payload = enum(upayload) {
        _,
    };

    pub const tag_size = 2;
    pub const payload_size = @bitSizeOf(*usize) - tag_size;

    comptime {
        if (@ctz(@as(usize, @alignOf(*usize))) < tag_size) {
            @compileError("Unsupported architecture");
        }
    }
    pub const zero: Cell = .from_union(.{
        .constant = .{
            .is_fixnum = true,
            .payload = 0,
        },
    });
    pub const Union = union(Tag) {
        shared_pointer: *Header,
        unique_pointer: *Header,
        constant: Constant,
        code: Code,

        pub fn from_cell(cell: Cell) Union {
            return cell.to_union();
        }

        pub fn to_cell(self: Union) Cell {
            return .from_union(self);
        }

        pub fn is_ptr(self: Union) bool {
            return @as(Tag, self).is_ptr();
        }

        pub fn is_immediate(self: Union) bool {
            return @as(Tag, self).is_immediate();
        }
    };

    pub const ifixnum = Int(.signed, payload_size - 1);
    pub const ufixnum = Int(.unsigned, payload_size - 1);

    pub const Constant = packed struct(upayload) {
        is_fixnum: bool,
        payload: ufixnum,
    };

    pub const Fixnum = enum(ifixnum) {
        _,
    };

    pub const Header = packed struct(usize) {
        cell_tag: Safety_Cell_Tag = .constant,
        fixnum_tag: Safety_Fixnum_Tag = .fixnum,
        gc_bits: GC_Bits,
        type: Type,
        size: Size,
        capacity: Capacity,

        const gc_bits_size = @bitSizeOf(u8) -
            @bitSizeOf(Safety_Cell_Tag) -
            @bitSizeOf(Safety_Fixnum_Tag);

        pub const GC_Bits = packed struct(Int(.unsigned, gc_bits_size)) {
            is_binary: bool,
            has_binary_word: bool,
            _: Padding(gc_bits_size - 2) = .padding,
        };
        pub const Type = enum(u8) {
            short_string,
            string,
            symbol,
            short_combo,
            combo,
            short_list,
            list,
            short_set,
            set,
            short_dict,
            dict,
            function,
            object,
        };
        const length_size = (8 * (@sizeOf(Cell) - 2)) / 2;
        const ulength = Int(.unsigned, length_size);

        pub const Size = enum(ulength) {
            _,
        };

        pub const Capacity = enum(ulength) {
            _,
        };

        const Safety_Cell_Tag = enum(@typeInfo(Cell.Tag).@"enum".tag_type) {
            constant = @intFromEnum(Cell.Tag.constant),
        };

        const Safety_Fixnum_Tag = enum(u1) {
            fixnum = @intFromBool(true),
        };
    };

    comptime {
        assert(@typeInfo(Union).@"union".tag_type == Tag);
        assert(tag_size == @bitSizeOf(Tag));
        for (@typeInfo(Union).@"union".fields) |field| {
            if (@typeInfo(field.type) == .pointer) {
                assert(tag_size <= @ctz(@as(usize, @alignOf(field.type))));
            } else {
                assert(@bitSizeOf(field.type) + tag_size == @bitSizeOf(usize));
            }
            const cell: Cell = .init(
                @unionInit(Union, field.name, undefined),
                // We can't just use 0 because of null pointers.
                @enumFromInt(1 << (@alignOf(*Cell) - tag_size)),
            );
            const cell_roundtrip: Cell = .from_union(.from_cell(cell));
            assert(cell == cell_roundtrip);
        }
    }

    pub fn from_union(source: Union) Cell {
        return .{
            .tag = source,
            .payload = @enumFromInt(switch (source) {
                .unique_pointer,
                .shared_pointer,
                => |ptr| @intFromPtr(ptr) >> tag_size,

                inline else => |payload| @as(upayload, @bitCast(payload)),
            }),
        };
    }

    pub fn to_union(self: Cell) Union {
        const mask: usize = comptime @truncate(
            std.math.maxInt(usize) << @alignOf(*Cell),
        );
        return switch (self.tag) {
            inline else => |tag| @unionInit(
                Union,
                @tagName(tag),
                switch (tag) {
                    .unique_pointer,
                    .shared_pointer,
                    => @ptrFromInt(@as(usize, @bitCast(self)) & mask),

                    .constant, .code => @bitCast(@intFromEnum(self.payload)),
                },
            ),
        };
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

pub const Code = packed struct(Cell.upayload) {
    payload: Payload,
    _: Padding(@bitSizeOf(Cell.Payload) - @bitSizeOf(Payload)) = .padding,

    pub const instructions_per_cell =
        @bitSizeOf(Cell.Payload) / @bitSizeOf(Instruction);

    pub const Payload =
        Int(.unsigned, @bitSizeOf(Instruction) * instructions_per_cell);

    pub const empty: Code = .{ .payload = 0 };

    pub fn prepend(self: Code, inst: Instruction) Code {
        return .{
            .payload = self.payload << @bitSizeOf(Instruction) |
                @intFromEnum(inst),
        };
    }

    pub fn current(self: Code) Instruction {
        return @enumFromInt(self.payload &
            std.math.maxInt(@typeInfo(Instruction).@"enum".tag_type));
    }

    test "interactions between prepend, current and next" {
        const sample = prepend(.empty, .tailcall);

        try std.testing.expectEqual(sample.current(), .tailcall);
        try std.testing.expectEqual(sample.next(), Code.empty);
    }

    pub fn next(self: Code) Code {
        return .{ .payload = self.payload >> @bitSizeOf(Instruction) };
    }

    pub fn to_array(self: Code) [instructions_per_cell]Instruction {
        var code = self;
        var instructions: [instructions_per_cell]Instruction = undefined;
        for (&instructions) |*inst| {
            inst.* = code.current();
            code = code.next();
        }
        return instructions;
    }
    pub fn from_array(instructions: [instructions_per_cell]Instruction) Code {
        var code: Code = .empty;
        var iter = std.mem.reverseIterator(&instructions);
        while (iter.next()) |inst| {
            code = code.prepend(inst);
        }
        return code;
    }

    test "array roundtrip" {
        const code = comptime Code.empty.prepend(.tailcall);
        const inst_array = comptime code.to_array();
        const converted_code: Code = comptime .from_array(inst_array);

        try comptime std.testing.expectEqual(code, converted_code);
    }
};

pub fn Padding(comptime size: comptime_int) type {
    return enum(Int(.unsigned, size)) { padding = 0 };
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

const std = @import("std");
const Int = std.meta.Int;

const assert = std.debug.assert;
