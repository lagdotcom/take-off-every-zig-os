const std = @import("std");
const log = std.log.scoped(.cmos);

const interrupts = @import("interrupts.zig");
const time = @import("time.zig");
const x86 = @import("../arch/x86.zig");

const io_port: u16 = 0x70;
const data_port: u16 = 0x71;

const StatusA = packed struct {
    rate_select: u4,
    bank_control: u1,
    select_divider: u2,
    update_in_progress: bool,
};

const StatusB = packed struct {
    daylight_savings: bool,
    hours_24: bool,
    binary_mode: bool,
    square_wave_enabled: bool,
    update_ended_interrupt_enabled: bool,
    alarm_interrupt_enabled: bool,
    periodic_interrupt_enabled: bool,
    update_in_progress: bool,
};

const StatusC = packed struct {
    reserved: u4,
    update_ended_interrupt: bool,
    alarm_interrupt: bool,
    periodic_interrupt: bool,
    interrupt_request: bool,
};

fn select_register(index: u7) void {
    const nmi_flag: u8 = if (interrupts.nmi_disabled) 0x80 else 0x00;
    x86.outb(io_port, @as(u8, index) | nmi_flag);
}

fn read_register(index: u7) u8 {
    select_register(index);
    return x86.inb(data_port);
}

pub fn read_status_a() StatusA {
    return @bitCast(read_register(0x0a));
}

pub fn write_status_a(status: StatusA) void {
    select_register(0x0a);
    x86.outb(data_port, @bitCast(status));
}

pub fn read_status_b() StatusB {
    return @bitCast(read_register(0x0b));
}

pub fn write_status_b(status: StatusB) void {
    select_register(0x0b);
    x86.outb(data_port, @bitCast(status));
}

pub fn read_status_c() StatusC {
    return @bitCast(read_register(0x0c));
}

pub fn write_status_c(status: StatusC) void {
    select_register(0x0c);
    x86.outb(data_port, @bitCast(status));
}

pub fn wait_for_update() void {
    while (!read_status_a().update_in_progress) {}
    while (read_status_a().update_in_progress) {}
}

fn bcd_to_binary(bcd: u8) u8 {
    return (bcd >> 4) * 10 + (bcd & 0x0f);
}

pub fn log_status_a(a: StatusA) void {
    log.debug("Status A: RS={d} BC={d} DIV={d}{s}", .{
        a.rate_select,
        a.bank_control,
        a.select_divider,
        if (a.update_in_progress) " SET" else "",
    });
}

pub fn log_status_b(b: StatusB) void {
    log.debug("Status B:{s}{s}{s}{s}{s}{s}{s}{s}", .{
        if (b.daylight_savings) " DSE" else "",
        if (b.hours_24) " 24" else " 12",
        if (b.binary_mode) " BCD" else " BIN",
        if (b.square_wave_enabled) " SQW" else "",
        if (b.update_ended_interrupt_enabled) " UIE" else "",
        if (b.alarm_interrupt_enabled) " AIE" else "",
        if (b.periodic_interrupt_enabled) " PIE" else "",
        if (b.update_in_progress) " SET" else "",
    });
}

pub fn log_status_c(c: StatusC) void {
    log.debug("Status C:{s}{s}{s}{s}", .{
        if (c.update_ended_interrupt) " UF" else "",
        if (c.alarm_interrupt) " AF" else "",
        if (c.periodic_interrupt) " PF" else "",
        if (c.interrupt_request) " IRQ" else "",
    });
}

pub fn read_rtc(b: ?StatusB) time.DateTime {
    const status = b orelse read_status_b();
    const raw_seconds = read_register(0);
    const raw_minutes = read_register(2);
    var raw_hours = read_register(4);
    const raw_day = read_register(7);
    const raw_month = read_register(8);
    const raw_year = read_register(9);
    const raw_century = read_register(0x32);

    if (!status.hours_24) {
        const pm = (raw_hours & 0x80) != 0;
        raw_hours &= 0x7f;
        if (raw_hours == 12 or raw_hours == 0x12) raw_hours = 0;
        if (pm) raw_hours += if (status.binary_mode) 12 else 0x12;
    }

    const seconds = if (status.binary_mode) raw_seconds else bcd_to_binary(raw_seconds);
    const minutes = if (status.binary_mode) raw_minutes else bcd_to_binary(raw_minutes);
    const hours = if (status.binary_mode) raw_hours else bcd_to_binary(raw_hours);
    const day = if (status.binary_mode) raw_day else bcd_to_binary(raw_day);
    const month = if (status.binary_mode) raw_month else bcd_to_binary(raw_month);
    const year = if (status.binary_mode) raw_year else bcd_to_binary(raw_year);
    const century = if (status.binary_mode) raw_century else bcd_to_binary(raw_century);

    const full_year = @as(i32, year) + @as(i32, century) * 100;

    return time.DateTime{
        .year = full_year,
        .month = @intCast(month),
        .day = @intCast(day),
        .hour = @intCast(hours),
        .minute = @intCast(minutes),
        .second = @intCast(seconds),
        .millisecond = 0,
    };
}
