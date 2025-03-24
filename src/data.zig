pub const Cell = packed struct(usize) {
    tag: Tag,
    payload: Payload,

    pub fn init(tag: Tag, payload: Payload) Cell {
        return .{ .tag = tag, .payload = payload };
    }

    pub fn share(self: *Cell) void {
        switch (self.tag) {
            .unique_pointer => self.tag = .shared_pointer,
            else => {},
        }
    }

    pub fn format(
        self: Cell,
        comptime _: []const u8,
        _: std.fmt.FormatOptions,
        writer: anytype,
    ) !void {
        switch (self.to_union()) {
            .code => |code| {
                try writer.writeAll("($code");
                for (code.to_array()) |instruction| {
                    try writer.print(" {s}", .{@tagName(instruction)});
                }
                try writer.writeAll(")");
            },
            .constant => |constant| {
                assert(constant.is_fixnum); // FIXME
                try writer.print("#d{}", .{constant.payload});
            },
            .shared_pointer, .unique_pointer => |header| {
                assert(header.?.type == .short_list); // FIXME
                const list: *const Short_List = @constCast(@ptrCast(header));
                switch (list.header.size) {
                    .empty => unreachable,
                    else => |size| {
                        try writer.writeAll("[");
                        try writer.print("{}", .{list.contents[0]});
                        for (
                            list.contents[1..size.to_int()],
                            1..size.to_int(),
                        ) |cell, _| {
                            try writer.print(" {}", .{cell});
                        }
                        try writer.writeAll("]");
                    },
                }
            },
        }
    }

    const length_size = (8 * (@sizeOf(Cell) - 2)) / 2;
    const ulength = Int(.unsigned, length_size);

    pub const Index = enum(ulength) {
        _,

        pub inline fn from_int(n: ulength) Index {
            return @enumFromInt(n);
        }
        pub inline fn to_int(self: Index) ulength {
            return @intFromEnum(self);
        }

        pub inline fn in_range(self: Index, size: Size) bool {
            return self.to_int() < size.to_int();
        }
    };

    pub const Size = enum(ulength) {
        empty = 0,
        _,

        pub inline fn from_int(n: ulength) Size {
            return @enumFromInt(n);
        }
        pub inline fn to_int(self: Size) ulength {
            return @intFromEnum(self);
        }

        pub inline fn can_grow(self: Size, capacity: Capacity) bool {
            return self.to_int() < capacity.to_int();
        }
    };

    pub const Capacity = enum(ulength) {
        _,

        pub inline fn from_int(n: ulength) Capacity {
            return @enumFromInt(n);
        }
        pub inline fn to_int(self: Capacity) ulength {
            return @intFromEnum(self);
        }
    };

    pub fn nth(self: Cell, idx: Index) Cell {
        std.debug.print("Cell.init({}, {b})\n", .{ self.tag, @intFromEnum(self.payload) });
        switch (self.to_union()) {
            .code, .constant => return .nil,
            .shared_pointer => |ptr| {
                const cell = nth_unique(@ptrCast(ptr), idx);
                return .{
                    .tag = if (cell.tag == .unique_pointer)
                        .shared_pointer
                    else
                        cell.tag,
                    .payload = cell.payload,
                };
            },
            .unique_pointer => |ptr| return nth_unique(@ptrCast(ptr), idx),
        }
    }

    pub const Tag = enum(Int(.unsigned, tag_size)) {
        shared_pointer = 0b00,
        unique_pointer = 0b10,
        constant = 0b01,
        code = 0b11,
    };

    pub const Payload = enum(upayload) {
        _,
    };

    pub const zero: Cell = .from_union(.{
        .constant = .{
            .is_fixnum = true,
            .payload = 0,
        },
    });
    pub const nil: Cell = .from_union(.{ .shared_pointer = null });

    pub const Union = union(Tag) {
        shared_pointer: ?*Header,
        unique_pointer: *Header,
        constant: Constant,
        code: Code,

        pub fn from_cell(cell: Cell) Union {
            return cell.to_union();
        }

        pub fn to_cell(self: Union) Cell {
            return .from_union(self);
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

            pub const normal: GC_Bits = .{
                .is_binary = false,
                .has_binary_word = false,
            };
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
        const Safety_Cell_Tag = enum(@typeInfo(Cell.Tag).@"enum".tag_type) {
            constant = @intFromEnum(Cell.Tag.constant),
        };

        const Safety_Fixnum_Tag = enum(u1) {
            fixnum = @intFromBool(true),
        };
    };

    pub fn from_union(source: Union) Cell {
        return .{
            .tag = source,
            .payload = @enumFromInt(switch (source) {
                .unique_pointer,
                .shared_pointer,
                => |ptr| @intFromPtr(ptr) >> tag_size,

                inline .constant,
                .code,
                => |payload| @as(upayload, @bitCast(payload)),
            }),
        };
    }

    pub fn to_union(self: Cell) Union {
        return switch (self.tag) {
            inline else => |tag| @unionInit(
                Union,
                @tagName(tag),
                switch (tag) {
                    .unique_pointer,
                    .shared_pointer,
                    => @ptrFromInt(
                        @as(usize, @intFromEnum(self.payload)) << tag_size,
                    ),
                    .constant, .code => @bitCast(
                        @intFromEnum(self.payload),
                    ),
                },
            ),
        };
    }

    fn nth_unique(header: [*]const Cell.Header, idx: Index) Cell {
        if (header[0].gc_bits.is_binary) return .nil;
        const size = header[0].size;
        if (idx.in_range(size)) return .nil;
        const has_binary_word = @intFromBool(header[0].gc_bits.has_binary_word);
        const header_slice = header[1 + has_binary_word .. size.to_int() + 1 + has_binary_word];
        return @as(
            Cell,
            @bitCast(header_slice[idx.to_int() + has_binary_word]),
        );
    }

    const upayload = Int(.unsigned, payload_size);
    const tag_size = 2;
    const payload_size = @bitSizeOf(*usize) - tag_size;

    comptime {
        if (@ctz(@as(usize, @alignOf(*usize))) < tag_size) {
            @compileError(
                \\Unsupported architecture: tag cannot fit in pointer alignment bits.
            );
        }
        for (@typeInfo(Union).@"union".fields) |field| {
            const T = field.type;
            size_check: switch (@typeInfo(T)) {
                .pointer => {
                    assert(tag_size <= @ctz(@as(usize, @alignOf(T))));
                },
                .optional => |Optional| {
                    const nested_type = @typeInfo(Optional.child);
                    assert(nested_type == .pointer);
                    continue :size_check nested_type;
                },
                else => {
                    assert(@bitSizeOf(T) + tag_size == @bitSizeOf(Cell));
                },
            }
            const cell: Cell = .init(
                @field(Tag, field.name),
                // We can't just use 0 because of null pointers.
                @enumFromInt(1 << (@alignOf(*Cell) - tag_size)),
            );
            assert(cell == cell.to_union().to_cell());
        }
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

pub const Code = packed struct(std.meta.Tag(Cell.Payload)) {
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

const base_size = 16;

fn unique(comptime T: type) fn (self: *T) Cell {
    return struct {
        pub fn f(self: *T) Cell {
            return .from_union(.{ .unique_pointer = @ptrCast(self) });
        }
    }.f;
}
fn shared(comptime T: type) fn (self: *T) Cell {
    return struct {
        pub fn f(self: *T) Cell {
            return .from_union(.{ .shared_pointer = @ptrCast(self) });
        }
    }.f;
}
fn as_slice(comptime T: type) fn (self: *T) []Cell {
    return struct {
        pub fn f(self: *T) []Cell {
            return self.contents[0..self.header.size.to_int()];
        }
    }.f;
}

const Short_List = extern struct {
    header: Cell.Header,
    contents: [base_size]Cell,

    pub const empty: Short_List = .{
        .header = .{
            .gc_bits = .normal,
            .type = .short_list,
            .size = @enumFromInt(0),
            .capacity = @enumFromInt(base_size),
        },
        .contents = undefined,
    };

    pub const to_shared = shared(Short_List);
    pub const to_unique = unique(Short_List);
    pub const to_slice = as_slice(Short_List);

    pub fn pushr(self: *Short_List, value: Cell) bool {
        const size = self.header.size;
        if (size.can_grow(self.header.capacity)) {
            self.contents[size.to_int()] = value;
            self.header.size = @enumFromInt(size.to_int() + 1);
            return true;
        } else return false;
    }
};

test Short_List {
    var list: Short_List = .empty;
    try std.testing.expect(list.pushr(.zero));
    try std.testing.expect(list.header.size.to_int() == 1);
    try std.testing.expect(@intFromPtr(&list.header) == @intFromPtr(&list));
    try std.testing.expect(@intFromPtr(&list) == @as(usize, @bitCast(list.to_shared())));
    try std.testing.expect(@intFromPtr(&list) == @intFromPtr(list.to_shared().to_union().shared_pointer));
}

const std = @import("std");
const Int = std.meta.Int;

const assert = std.debug.assert;

test "everything" {
    _ = Cell;
    _ = Instruction;
    _ = Code;
}
