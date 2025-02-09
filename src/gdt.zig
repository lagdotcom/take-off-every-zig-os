const std = @import("std");
const log = std.log.scoped(.gdt);

const utils = @import("utils.zig");

pub const AccessDescriptorType = enum(u1) {
    system,
    code_data,
};

pub const Access = packed struct {
    accessed: bool = false,
    read_write: bool = false,
    direction_conforming: bool = false,
    executable: bool = false,
    descriptor_type: AccessDescriptorType = .code_data,
    privilege: u2 = 0,
    present: bool = false,
};

pub const SystemSegmentType = enum(u4) {
    tss_16bit_available = 1,
    ldt = 2,
    tss_16bit_busy = 3,
    tss_32bit_available = 9,
    tss_32bit_busy = 11,
};

pub const SystemSegmentAccess = packed struct {
    type: SystemSegmentType,
    descriptor_type: AccessDescriptorType = .system,
    dpl: u2 = 0,
    present: bool = false,
};

pub const FlagsGranularity = enum(u1) {
    _1b,
    _4kb,
};

pub const FlagsSize = enum(u1) {
    _16bit,
    _32bit,
};

pub const Flags = packed struct {
    reserved: bool = false,
    long_mode: bool = false,
    size: FlagsSize = ._16bit,
    granularity: FlagsGranularity = ._1b,
};

pub const GDTEntry = packed struct {
    limit_lo: u16,
    base_lo: u24,
    access: u8,
    limit_hi: u4,
    flags: Flags,
    base_hi: u8,
};

pub const GDTDescriptor = packed struct {
    limit: u16,
    base: u32,
};
var gdt_ptr: GDTDescriptor = .{
    .base = 0,
    .limit = 0,
};

pub inline fn lgdt(ptr: *GDTDescriptor) void {
    log.debug("lgdt {*} -- {x}:{d}", .{ ptr, ptr.base, ptr.limit });
    asm volatile ("lgdt (%%eax)"
        :
        : [ptr] "{eax}" (ptr),
    );

    log.debug("setting up segment registers", .{});
    asm volatile ("mov %%bx, %%ds"
        :
        : [KERNEL_DATA_OFFSET] "{bx}" (KERNEL_DATA_OFFSET),
    );

    asm volatile ("mov %%bx, %%es");
    asm volatile ("mov %%bx, %%fs");
    asm volatile ("mov %%bx, %%gs");
    asm volatile ("mov %%bx, %%ss");

    log.debug("performing kernel code jump", .{});
    // 0x08: KERNEL_CODE_OFFSET
    asm volatile (
        \\ljmp $0x08, $1f
        \\1:
    );
}

pub inline fn ltr(offset: u16) void {
    log.debug("ltr {x}", .{offset});

    asm volatile ("ltr %[offset]"
        :
        : [offset] "{ax}" (offset),
    );
}

pub inline fn encode_gdt_entry(base: u32, limit: u20, access: Access, flags: Flags) GDTEntry {
    return GDTEntry{
        .base_lo = @intCast(base & 0xffffff),
        .base_hi = @intCast((base & 0xff000000) >> 24),
        .limit_lo = @intCast(limit & 0xffff),
        .limit_hi = @intCast((limit & 0xf0000) >> 16),
        .access = @bitCast(access),
        .flags = flags,
    };
}

pub inline fn encode_tss_entry(base: u32, access: SystemSegmentAccess, flags: Flags) GDTEntry {
    const limit: u20 = @sizeOf(TaskStateSegment) - 1;

    return GDTEntry{
        .base_lo = @intCast(base & 0xffffff),
        .base_hi = @intCast((base & 0xff000000) >> 24),
        .limit_lo = @intCast(limit & 0xffff),
        .limit_hi = @intCast((limit & 0xf0000) >> 16),
        .access = @bitCast(access),
        .flags = flags,
    };
}

pub const TaskStateSegment = packed struct {
    link: u16,
    reserved_02: u16,

    esp0: u32,
    ss0: u16,
    reserved_0a: u16,

    esp1: u32,
    ss1: u16,
    reserved_12: u16,

    esp2: u32,
    ss2: u16,
    reserved_1a: u16,

    cr3: u32,
    eip: u32,
    eflags: u32,
    eax: u32,
    ecx: u32,
    edx: u32,
    ebx: u32,
    esp: u32,
    ebp: u32,
    esi: u32,
    edi: u32,

    es: u16,
    reserved_4a: u16,

    cs: u16,
    reserved_4e: u16,

    ss: u16,
    reserved_52: u16,

    ds: u16,
    reserved_56: u16,

    fs: u16,
    reserved_5a: u16,

    gs: u16,
    reserved_5e: u16,

    ldtr: u16,
    reserved_62: u16,

    trap: u16,
    iopb: u16,
};

pub inline fn get_tss() TaskStateSegment {
    return TaskStateSegment{
        .link = 0,
        .reserved_02 = 0,
        .esp0 = 0,
        .ss0 = 0,
        .reserved_0a = 0,
        .esp1 = 0,
        .ss1 = 0,
        .reserved_12 = 0,
        .esp2 = 0,
        .ss2 = 0,
        .reserved_1a = 0,
        .cr3 = 0,
        .eip = 0,
        .eflags = 0,
        .eax = 0,
        .ecx = 0,
        .edx = 0,
        .ebx = 0,
        .esp = 0,
        .ebp = 0,
        .esi = 0,
        .edi = 0,
        .es = 0,
        .reserved_4a = 0,
        .cs = 0,
        .reserved_4e = 0,
        .ss = 0,
        .reserved_52 = 0,
        .ds = 0,
        .reserved_56 = 0,
        .fs = 0,
        .reserved_5a = 0,
        .gs = 0,
        .reserved_5e = 0,
        .ldtr = 0,
        .reserved_62 = 0,
        .reserved_64 = 0,
        .iopb = 0,
        .ssp = 0,
    };
}

/// The total number of entries in the GDT including: null, kernel code, kernel data, user code,
/// user data and the TSS.
const NUMBER_OF_ENTRIES: u16 = 0x06;

/// The size of the GTD in bytes (minus 1).
const TABLE_SIZE: u16 = @sizeOf(GDTEntry) * NUMBER_OF_ENTRIES - 1;

/// The index of the NULL GDT entry.
const NULL_INDEX: u16 = 0x00;

/// The index of the kernel code GDT entry.
const KERNEL_CODE_INDEX: u16 = 0x01;

/// The index of the kernel data GDT entry.
const KERNEL_DATA_INDEX: u16 = 0x02;

/// The index of the user code GDT entry.
const USER_CODE_INDEX: u16 = 0x03;

/// The index of the user data GDT entry.
const USER_DATA_INDEX: u16 = 0x04;

/// The index of the task state segment GDT entry.
const TSS_INDEX: u16 = 0x05;

/// The offset of the NULL GDT entry.
pub const NULL_OFFSET: u16 = 0x00;

/// The offset of the kernel code GDT entry.
pub const KERNEL_CODE_OFFSET: u16 = 0x08;

/// The offset of the kernel data GDT entry.
pub const KERNEL_DATA_OFFSET: u16 = 0x10;

/// The offset of the user code GDT entry.
pub const USER_CODE_OFFSET: u16 = 0x18;

/// The offset of the user data GDT entry.
pub const USER_DATA_OFFSET: u16 = 0x20;

/// The offset of the TTS GDT entry.
pub const TSS_OFFSET: u16 = 0x28;

var main_tss_entry = init: {
    var entry = std.mem.zeroes(TaskStateSegment);
    entry.ss0 = KERNEL_DATA_OFFSET;
    entry.iopb = @sizeOf(TaskStateSegment);
    break :init entry;
};

var gdt_entries: [6]GDTEntry = init: {
    const flags_4kb_32bit = Flags{ .granularity = ._4kb, .size = ._32bit };

    var entries: [6]GDTEntry = undefined;

    // null entry
    entries[NULL_INDEX] = encode_gdt_entry(0, 0, .{}, .{});

    // kernel mode code segment
    entries[KERNEL_CODE_INDEX] = encode_gdt_entry(0, 0xfffff, .{
        .present = true,
        .read_write = true,
        .executable = true,
    }, flags_4kb_32bit);

    // kernel mode data segment
    entries[KERNEL_DATA_INDEX] = encode_gdt_entry(0, 0xfffff, .{
        .present = true,
        .read_write = true,
        .executable = false,
    }, flags_4kb_32bit);

    // user mode code segment
    entries[USER_CODE_INDEX] = encode_gdt_entry(0, 0xfffff, .{
        .present = true,
        .read_write = true,
        .executable = true,
        .privilege = 3,
    }, flags_4kb_32bit);

    // user mode data segment
    entries[USER_DATA_INDEX] = encode_gdt_entry(0, 0xfffff, .{
        .present = true,
        .read_write = true,
        .executable = false,
        .privilege = 3,
    }, flags_4kb_32bit);

    // tss
    entries[TSS_INDEX] = encode_tss_entry(0, .{ .present = true, .type = .tss_32bit_available }, .{});

    break :init entries;
};

pub fn initialize() void {
    log.debug("initializing", .{});
    defer log.debug("done", .{});

    gdt_entries[TSS_INDEX] = encode_tss_entry(@intFromPtr(&main_tss_entry), .{ .present = true, .type = .tss_32bit_available }, .{});

    gdt_ptr.base = @intFromPtr(&gdt_entries[0]);
    gdt_ptr.limit = @sizeOf(GDTEntry) * NUMBER_OF_ENTRIES - 1;
    lgdt(&gdt_ptr);

    ltr(TSS_OFFSET); // tss offset
}

const expect = std.testing.expect;
const expectEqual = std.testing.expectEqual;

test "GDT entries" {
    try expectEqual(@as(u32, 1), @sizeOf(Access));
    try expectEqual(@as(u32, 1), @sizeOf(Flags));
    try expectEqual(@as(u32, 8), @sizeOf(GDTEntry));
    try expectEqual(@as(u32, 112), @sizeOf(TaskStateSegment));
    try expectEqual(@as(u32, 6), @sizeOf(GDTDescriptor));

    const null_entry = gdt_entries[NULL_INDEX];
    try expectEqual(@as(u64, 0), @as(u64, @bitCast(null_entry)));

    const kernel_code_entry = gdt_entries[KERNEL_CODE_INDEX];
    try expectEqual(@as(u64, 0xCF9A000000FFFF), @as(u64, @bitCast(kernel_code_entry)));

    const kernel_data_entry = gdt_entries[KERNEL_DATA_INDEX];
    try expectEqual(@as(u64, 0xCF92000000FFFF), @as(u64, @bitCast(kernel_data_entry)));

    const user_code_entry = gdt_entries[USER_CODE_INDEX];
    try expectEqual(@as(u64, 0xCFFA000000FFFF), @as(u64, @bitCast(user_code_entry)));

    const user_data_entry = gdt_entries[USER_DATA_INDEX];
    try expectEqual(@as(u64, 0xCFF2000000FFFF), @as(u64, @bitCast(user_data_entry)));

    const tss_entry = gdt_entries[TSS_INDEX];
    try expectEqual(@as(u64, 0), @as(u64, @bitCast(tss_entry)));

    try expectEqual(TABLE_SIZE, gdt_ptr.limit);

    try expectEqual(@as(u32, 0), main_tss_entry.link);
    try expectEqual(@as(u32, 0), main_tss_entry.esp0);
    try expectEqual(@as(u32, KERNEL_DATA_OFFSET), main_tss_entry.ss0);
    try expectEqual(@as(u32, 0), main_tss_entry.esp1);
    try expectEqual(@as(u32, 0), main_tss_entry.ss1);
    try expectEqual(@as(u32, 0), main_tss_entry.esp2);
    try expectEqual(@as(u32, 0), main_tss_entry.ss2);
    try expectEqual(@as(u32, 0), main_tss_entry.cr3);
    try expectEqual(@as(u32, 0), main_tss_entry.eip);
    try expectEqual(@as(u32, 0), main_tss_entry.eflags);
    try expectEqual(@as(u32, 0), main_tss_entry.eax);
    try expectEqual(@as(u32, 0), main_tss_entry.ecx);
    try expectEqual(@as(u32, 0), main_tss_entry.edx);
    try expectEqual(@as(u32, 0), main_tss_entry.ebx);
    try expectEqual(@as(u32, 0), main_tss_entry.esp);
    try expectEqual(@as(u32, 0), main_tss_entry.ebp);
    try expectEqual(@as(u32, 0), main_tss_entry.esi);
    try expectEqual(@as(u32, 0), main_tss_entry.edi);
    try expectEqual(@as(u32, 0), main_tss_entry.es);
    try expectEqual(@as(u32, 0), main_tss_entry.cs);
    try expectEqual(@as(u32, 0), main_tss_entry.ss);
    try expectEqual(@as(u32, 0), main_tss_entry.ds);
    try expectEqual(@as(u32, 0), main_tss_entry.fs);
    try expectEqual(@as(u32, 0), main_tss_entry.gs);
    try expectEqual(@as(u32, 0), main_tss_entry.ldtr);
    try expectEqual(@as(u16, 0), main_tss_entry.trap);

    // Size of Tss will fit in a u16 as 104 < 65535 (2^16)
    try expectEqual(@as(u16, @sizeOf(TaskStateSegment)), main_tss_entry.iopb);
}

test "makeGdtEntry alternating bit pattern" {
    const alt_access = Access{
        .accessed = true,
        .read_write = false,
        .direction_conforming = true,
        .executable = false,
        .descriptor_type = .code_data,
        .privilege = 0b10,
        .present = false,
    };

    try expectEqual(@as(u8, 0b01010101), @as(u8, @bitCast(alt_access)));

    const alt_flag = Flags{
        .reserved = true,
        .long_mode = false,
        .size = ._32bit,
        .granularity = ._1b,
    };

    try expectEqual(@as(u4, 0b0101), @as(u4, @bitCast(alt_flag)));

    const actual = encode_gdt_entry(0b01010101010101010101010101010101, 0b01010101010101010101, alt_access, alt_flag);

    const expected: u64 = 0b0101010101010101010101010101010101010101010101010101010101010101;
    try expectEqual(expected, @as(u64, @bitCast(actual)));
}
