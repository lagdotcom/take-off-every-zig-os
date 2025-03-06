const std = @import("std");
const log = std.log.scoped(.interrupts);

const gdt = @import("gdt.zig");
const pic = @import("pic.zig");
const x86 = @import("../arch/x86.zig");

pub const ErrorInterrupt = enum(u8) {
    divide_error = 0,
    debug,
    nmi,
    int_3,
    overflow,
    bounds,
    invalid_op,
    device_not_available,
    double_fault,
    coprocessor_segment_overrun,
    invalid_tss,
    segment_not_present,
    stack_segment,
    general_protection,
    page_fault,
    coprocessor_error = 16,
};

const IRQ_START_INDEX = 0x20;

pub const IRQ = enum(u8) {
    pit = 0,
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
    zero: u1 = 0,
    privilege: u2 = 0,
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

pub const IDTHandler = fn () callconv(.Naked) void;
pub const InterruptHandler = *const fn (ctx: *CpuState) usize;
var interrupt_handlers: [MAX_DESCRIPTORS]?InterruptHandler = [_]?InterruptHandler{null} ** MAX_DESCRIPTORS;

var idt_ptr: x86.IDTDescriptor = .{
    .base = 0,
    .limit = 0,
};

// TODO move majority of this into arch/x86 lol
pub const CpuState = packed struct {
    // Page directory
    cr3: usize,

    // Extra segments
    gs: u32,
    fs: u32,
    es: u32,
    ds: u32,

    // Destination, source, base pointer
    edi: u32,
    esi: u32,
    ebp: u32,
    esp: u32,

    // General registers
    ebx: u32,
    edx: u32,
    ecx: u32,
    eax: u32,

    // Interrupt number and error code
    int_num: u32,
    error_code: u32,

    // Instruction pointer, code segment and flags
    eip: u32,
    cs: u32,
    eflags: x86.EFLAGS,
    user_esp: u32,
    user_ss: u32,
};

fn isrHandler(ctx: *CpuState) usize {
    var ret_esp = @intFromPtr(ctx);

    if (interrupt_handlers[ctx.int_num]) |handler|
        ret_esp = handler(ctx);

    return ret_esp;
}

fn irqHandler(ctx: *CpuState) usize {
    var ret_esp = @intFromPtr(ctx);

    const irq: u8 = @truncate(ctx.int_num - IRQ_START_INDEX);
    if (interrupt_handlers[ctx.int_num]) |handler| {
        if (!pic.is_spurious(irq)) {
            ret_esp = handler(ctx);
            pic.eoi(irq);
        }
    }

    return ret_esp;
}

pub export fn interrupt_handler(ctx: *CpuState) usize {
    // ctx.debug();

    if (ctx.int_num > IRQ_START_INDEX) {
        // const irq: IRQ = @enumFromInt(ctx.int_num - IRQ_START_INDEX);
        // log.debug("IRQ: {s}", .{@tagName(irq)});
        return irqHandler(ctx);
    } else {
        // const int: ErrorInterrupt = @enumFromInt(ctx.int_num);
        // log.debug("Error: {s}", .{@tagName(int)});
        return isrHandler(ctx);
    }
}

pub export fn interrupt_common() callconv(.Naked) void {
    asm volatile (
        \\    # preserve registers
        \\    pusha
        \\    push %ds
        \\    push %es
        \\    push %fs
        \\    push %gs
        \\    mov %cr3,%eax
        \\    push %eax
        \\    mov $0x10,%ax
        \\    mov %ax,%ds
        \\    mov %ax,%es
        \\    mov %ax,%fs
        \\    mov %ax,%gs
        \\    mov %esp,%eax
        \\    push %eax
        \\    call %[interrupt_handler:P]
        \\    mov %eax,%esp
        \\
        \\    # pop new cr3, check if same as old cr3
        \\    pop %eax
        \\    mov %cr3,%ebx
        \\    cmp %eax,%ebx
        \\    je .same_cr3
        \\    mov %eax,%cr3
        \\.same_cr3:
        \\    pop %gs
        \\    pop %fs
        \\    pop %es
        \\    pop %ds
        \\    popa
        \\
        \\    # pop interrupt number, error value
        \\    add $8,%esp
        \\
        \\    # TODO: deal with tss.esp0 somehow
        \\    # add $0x1c,%esp
        \\    # .extern main_tss_entry
        \\    # mov %esp,(main_tss_entry+4)
        \\    # sub %esp,$0x14
        \\
        \\    iret
        :
        : [interrupt_handler] "X" (&interrupt_handler),
    );
}

fn generate_int_stub(comptime vector: u8) IDTHandler {
    return struct {
        fn handler() callconv(.Naked) void {
            asm volatile ("cli");

            switch (vector) {
                8, 10...14, 17 => {},
                else => asm volatile ("push $0"),
            }

            asm volatile (
                \\ push %[vector]
                \\ jmp %[interrupt_common:P]
                :
                : [vector] "n" (vector),
                  [interrupt_common] "X" (&interrupt_common),
            );
        }
    }.handler;
}

fn set_descriptor(vector: u8, handler: *const IDTHandler, flags: IDTAttributes) void {
    const ptr = @intFromPtr(handler);

    idt[vector].isr_lo = @intCast(ptr & 0xffff);
    idt[vector].kernel_cs = gdt.KERNEL_CODE_OFFSET;
    idt[vector].attributes = flags;
    idt[vector].isr_hi = @intCast(ptr >> 16);
    idt[vector].reserved = 0;

    log.debug("descriptor #{d} => {x} ({s})", .{ vector, ptr, @tagName(flags.gate_type) });
}

pub fn set_error_handler(err: ErrorInterrupt, handler: InterruptHandler, name: []const u8) void {
    interrupt_handlers[@intFromEnum(err)] = handler;
    log.debug("{s} => {x} ({s})", .{ @tagName(err), @intFromPtr(handler), name });
}

pub fn set_irq_handler(irq: IRQ, handler: InterruptHandler, name: []const u8) void {
    interrupt_handlers[@intFromEnum(irq) + IRQ_START_INDEX] = handler;
    log.debug("{s} => {x} ({s})", .{ @tagName(irq), @intFromPtr(handler), name });
}

fn setup_idt() void {
    idt_ptr.base = @intFromPtr(&idt[0]);
    idt_ptr.limit = @sizeOf(IDTEntry32) * MAX_DESCRIPTORS - 1;

    inline for (0..48) |vector|
        set_descriptor(vector, generate_int_stub(vector), .{ .present = true, .gate_type = if (vector < IRQ_START_INDEX) .trap_32 else .interrupt_32 });

    x86.lidt(&idt_ptr);
    x86.sti();
}

fn setup_pic() void {
    pic.remap(IRQ_START_INDEX, IRQ_START_INDEX + 8);
}

pub fn initialize() void {
    log.debug("initializing", .{});
    defer log.debug("done", .{});

    setup_idt();
    setup_pic();
}
