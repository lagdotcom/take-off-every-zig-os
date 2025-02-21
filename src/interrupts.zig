const std = @import("std");
const log = std.log.scoped(.interrupts);

const gdt = @import("gdt.zig");

pub const IRQ = enum(u8) {
    pit,
    keyboard,
    cascade,
    com2,
    com1,
    lpt2,
    floppy,
    lpt1_spurious,
    cmos_rtc,
    _9,
    _10,
    _11,
    mouse,
    fpu,
    primary_ata,
    secondary_ata,
};

const GateType = enum(u4) {
    task = 5,
    interrupt_16 = 6,
    trap_16 = 7,
    interrupt_32 = 14,
    trap_32 = 15,
};

const IDTAttributes = packed struct {
    gate_type: GateType,
    zero: u1,
    privilege: u2,
    present: bool,
};

const IDTEntry32 = extern struct {
    isr_lo: u16,
    kernel_cs: u16,
    reserved: u8,
    attributes: IDTAttributes,
    isr_hi: u16,
};

// const IDTEntry64 = extern struct {
//     isr_lo: u16,
//     kernel_cs: u16,
//     ist: u8,
//     attributes: IDTAttributes,
//     isr_mid: u16,
//     isr_hi: u32,
//     reserved: u32,
// };

const MAX_DESCRIPTORS = 256;
var idt: [MAX_DESCRIPTORS]IDTEntry32 align(16) = undefined;

pub const IRQHandler = *const fn () void;
var handlers: [MAX_DESCRIPTORS]IRQHandler = undefined;

pub const IDTDescriptor = packed struct {
    limit: u16,
    base: u32,
};
var idt_ptr: IDTDescriptor = .{
    .base = 0,
    .limit = 0,
};

fn lidt(ptr: *IDTDescriptor) void {
    log.debug("lidt {*} -- {x}:{d}", .{ ptr, ptr.base, ptr.limit });
    asm volatile ("lidt (%%eax)"
        :
        : [ptr] "{eax}" (ptr),
    );
}

fn null_handler() void {
    // TODO
    log.debug("null_handler", .{});
}

fn set_descriptor(vector: usize, handler: IRQHandler, flags: IDTAttributes) void {
    const ptr = @intFromPtr(handler);

    idt[vector].isr_lo = @intCast(ptr & 0xffff);
    idt[vector].kernel_cs = gdt.KERNEL_CODE_OFFSET;
    idt[vector].attributes = flags;
    idt[vector].isr_hi = @intCast(ptr >> 16);
    idt[vector].reserved = 0;

    log.debug("#{d} => {x} ({s})", .{ vector, ptr, @tagName(flags.gate_type) });
}

pub fn initialize() void {
    log.debug("initializing", .{});
    defer log.debug("done", .{});

    idt_ptr.base = @intFromPtr(&idt[0]);
    idt_ptr.limit = @sizeOf(IDTEntry32) * MAX_DESCRIPTORS - 1;

    for (0..32) |vector| {
        set_descriptor(vector, &null_handler, .{ .gate_type = .interrupt_32, .present = true, .privilege = 0, .zero = 0 });
    }

    lidt(&idt_ptr);
}
