const std = @import("std");
const log = std.log.scoped(.time);

const console = @import("console.zig");
const interrupts = @import("interrupts.zig");
const shell = @import("shell.zig");
const x86 = @import("../arch/x86.zig");

pub const DateTime = struct {
    year: i32,
    month: u4,
    day: u5,
    hour: u5,
    minute: u6,
    second: u6,
    millisecond: u10,

    pub fn format_ymd(self: DateTime, buffer: []u8) ![]u8 {
        return std.fmt.bufPrint(buffer, "{d:0>5}-{d:0>2}-{d:0>2}", .{ self.year, self.month, self.day });
    }

    pub fn format_ymd_hms(self: DateTime, buffer: []u8) ![]u8 {
        return std.fmt.bufPrint(buffer, "{d:0>5}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{ self.year, self.month, self.day, self.hour, self.minute, self.second });
    }
};

const CMOS_IO_PORT: u16 = 0x70;
const CMOS_DATA_PORT: u16 = 0x71;

const CmosStatusA = packed struct {
    rate_select: u4,
    bank_control: u1,
    select_divider: u2,
    update_in_progress: bool,
};

const CmosStatusB = packed struct {
    daylight_savings: bool,
    hours_24: bool,
    binary_mode: bool,
    square_wave_enabled: bool,
    update_ended_interrupt_enabled: bool,
    alarm_interrupt_enabled: bool,
    periodic_interrupt_enabled: bool,
    update_in_progress: bool,
};

fn select_cmos_register(index: u7) void {
    const nmi_flag: u8 = if (interrupts.nmi_disabled) 0x80 else 0x00;
    x86.outb(CMOS_IO_PORT, @as(u8, index) | nmi_flag);
}

fn read_cmos_register(index: u7) u8 {
    select_cmos_register(index);
    return x86.inb(CMOS_DATA_PORT);
}

fn read_cmos_status_a() CmosStatusA {
    return @bitCast(read_cmos_register(0x0a));
}

fn read_cmos_status_b() CmosStatusB {
    return @bitCast(read_cmos_register(0x0b));
}

fn wait_for_cmos_update() void {
    while (!read_cmos_status_a().update_in_progress) {}
    while (read_cmos_status_a().update_in_progress) {}
}

fn bcd_to_binary(bcd: u8) u8 {
    return (bcd >> 4) * 10 + (bcd & 0x0f);
}

fn log_status_b(b: CmosStatusB) void {
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

pub fn read_cmos_rtc() DateTime {
    wait_for_cmos_update();

    const status = read_cmos_status_b();
    log_status_b(status);

    const raw_seconds = read_cmos_register(0);
    const raw_minutes = read_cmos_register(2);
    var raw_hours = read_cmos_register(4);
    const raw_day = read_cmos_register(7);
    const raw_month = read_cmos_register(8);
    const raw_year = read_cmos_register(9);
    const raw_century = read_cmos_register(0x32);

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

    return DateTime{
        .year = full_year,
        .month = @intCast(month),
        .day = @intCast(day),
        .hour = @intCast(hours),
        .minute = @intCast(minutes),
        .second = @intCast(seconds),
        .millisecond = 0,
    };
}

pub fn initialize() !void {
    try shell.add_command(.{
        .name = "time",
        .summary = "Print the current date and time",
        .exec = shell_time,
    });
}

fn shell_time(allocator: std.mem.Allocator, _: []const u8) !void {
    const buffer = try allocator.alloc(u8, 64);
    defer allocator.free(buffer);

    console.printf_nl("Waiting for CMOS update...", .{});
    const time = read_cmos_rtc();
    const formatted = try time.format_ymd_hms(buffer);
    console.printf_nl("{s}", .{formatted});
}
