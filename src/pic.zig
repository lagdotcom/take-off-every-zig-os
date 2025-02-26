const std = @import("std");
const log = std.log.scoped(.pic);

const utils = @import("utils.zig");

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
    _8086 = 1,
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
    utils.outb(PIC1_COMMAND, @bitCast(cmd));
    utils.io_wait();
}

fn send_pic2_icw1(cmd: ICW1) void {
    utils.outb(PIC2_COMMAND, @bitCast(cmd));
    utils.io_wait();
}

pub fn clear_mask(irq: u8) void {
    const port = if (irq < 8) PIC1_DATA else PIC2_DATA;
    const shift: u3 = @intCast(irq % 8);
    const mask: u8 = ~(@as(u8, 1) << shift);
    const old_value = utils.inb(port);
    const value = old_value & mask;
    utils.outb(port, value);

    log.debug("clear_mask: port={x} old={x} new={x}", .{ port, old_value, value });
}

pub fn remap(offset_1: u8, offset_2: u8) void {
    send_pic1_icw1(.{ .init = true, .icw4_present = true });
    send_pic2_icw1(.{ .init = true, .icw4_present = true });

    utils.outb(PIC1_DATA, offset_1);
    utils.io_wait();

    utils.outb(PIC2_DATA, offset_2);
    utils.io_wait();

    utils.outb(PIC1_DATA, 4); // PIC2 is at IRQ2
    utils.io_wait();

    utils.outb(PIC2_DATA, 2); // PIC2 identity = 2
    utils.io_wait();

    utils.outb(PIC1_DATA, @intFromEnum(ICW4._8086));
    utils.io_wait();

    utils.outb(PIC2_DATA, @intFromEnum(ICW4._8086));
    utils.io_wait();

    // fully mask both PICs
    utils.outb(PIC1_DATA, 0xff);
    utils.outb(PIC2_DATA, 0xff);
}

pub fn eoi(irq: u8) void {
    if (irq >= 8) send_pic2_icw1(.{ .end_of_interrupt = true });
    send_pic1_icw1(.{ .end_of_interrupt = true });
}

fn pic1_isr() u8 {
    utils.outb(PIC1_COMMAND, @bitCast(OCW3{ .read_isr = true, .act_on_read = true }));
    return utils.inb(PIC1_COMMAND);
}

fn pic2_isr() u8 {
    utils.outb(PIC2_COMMAND, @bitCast(OCW3{ .read_isr = true, .act_on_read = true }));
    return utils.inb(PIC2_COMMAND);
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
