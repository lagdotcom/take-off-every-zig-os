const std = @import("std");
const log = std.log.scoped(.pic);

const interrupts = @import("interrupts.zig");
const x86 = @import("../arch/x86.zig");

const PIC1_COMMAND: u16 = 0x20;
const PIC1_DATA: u16 = 0x21;
const PIC2_COMMAND: u16 = 0xa0;
const PIC2_DATA: u16 = 0xa1;

const ICW1 = packed struct {
    icw4_present: bool = false,
    single: bool = false,
    interval_4: bool = false,
    level: bool = false,
    init: bool = false,
    end_of_interrupt: bool = false,
    unused: u2 = 0,
};

const ICW4 = enum(u8) {
    @"8086" = 1,
    auto = 2,
    buffered_slave = 8,
    buffered_master = 0x0c,
    not_special_fully_nested = 0x10,
};

const OCW3 = packed struct {
    read_isr: bool = false,
    act_on_read: bool = false,
    poll_command_issued: bool = false,
    default: bool = true,
    reserved_4: bool = false,
    special_mask: bool = false,
    ack_on_special_mask: bool = false,
    reserved_7: bool = false,
};

fn send_pic1_icw1(cmd: ICW1) void {
    x86.outb(PIC1_COMMAND, @bitCast(cmd));
    x86.io_wait();
}

fn send_pic2_icw1(cmd: ICW1) void {
    x86.outb(PIC2_COMMAND, @bitCast(cmd));
    x86.io_wait();
}

pub fn clear_mask(irq: interrupts.IRQ) void {
    const raw: u8 = @intFromEnum(irq);
    const port = if (raw < 8) PIC1_DATA else PIC2_DATA;
    const shift: u3 = @intCast(raw % 8);
    const mask: u8 = ~(@as(u8, 1) << shift);
    const old_value = x86.inb(port);
    const value = old_value & mask;
    x86.outb(port, value);

    log.debug("clear_mask: port={x} old={x} new={x}", .{ port, old_value, value });
}

pub fn remap(offset_1: u8, offset_2: u8) void {
    send_pic1_icw1(.{ .init = true, .icw4_present = true });
    send_pic2_icw1(.{ .init = true, .icw4_present = true });

    x86.outb(PIC1_DATA, offset_1);
    x86.io_wait();

    x86.outb(PIC2_DATA, offset_2);
    x86.io_wait();

    x86.outb(PIC1_DATA, 4); // PIC2 is at IRQ2
    x86.io_wait();

    x86.outb(PIC2_DATA, 2); // PIC2 identity = 2
    x86.io_wait();

    x86.outb(PIC1_DATA, @intFromEnum(ICW4.@"8086"));
    x86.io_wait();

    x86.outb(PIC2_DATA, @intFromEnum(ICW4.@"8086"));
    x86.io_wait();

    // fully mask both PICs
    x86.outb(PIC1_DATA, 0xff);
    x86.outb(PIC2_DATA, 0xff);
}

pub fn eoi(irq: u8) void {
    if (irq >= 8) send_pic2_icw1(.{ .end_of_interrupt = true });
    send_pic1_icw1(.{ .end_of_interrupt = true });

    log.debug("end of interrupt: {d}", .{irq});
}

fn pic1_isr() u8 {
    x86.outb(PIC1_COMMAND, @bitCast(OCW3{ .read_isr = true, .act_on_read = true }));
    return x86.inb(PIC1_COMMAND);
}

fn pic2_isr() u8 {
    x86.outb(PIC2_COMMAND, @bitCast(OCW3{ .read_isr = true, .act_on_read = true }));
    return x86.inb(PIC2_COMMAND);
}

pub fn is_spurious(irq: u8) bool {
    return switch (irq) {
        7 => {
            if ((pic1_isr() & 0x80) == 0) return true;
            return false;
        },
        15 => {
            if ((pic2_isr() & 0x80) == 0) {
                send_pic1_icw1(.{ .end_of_interrupt = true });
                return true;
            }
            return false;
        },

        else => false,
    };
}
