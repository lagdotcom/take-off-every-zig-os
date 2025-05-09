const std = @import("std");
const log = std.log.scoped(.pit);

const interrupts = @import("interrupts.zig");
const pic = @import("pic.zig");
const x86 = @import("../arch/x86.zig");

const pit_frequency = 3579545 / 3;

const command: u16 = 0x43;

const ChannelNumberMode = enum(u1) { binary = 0, bcd = 1 };

const ChannelOperation = enum(u3) {
    interrupt_on_terminal_count = 0,
    hardware_retriggerable_one_shot,
    rate_generator,
    square_wave_generator,
    software_triggered_strobe,
    hardware_triggered_strobe,
};

const ChannelAccess = enum(u2) {
    latch_count_value_command,
    lo_byte_only,
    hi_byte_only,
    both_bytes,
};

const Command = packed struct {
    number: ChannelNumberMode,
    operation: ChannelOperation,
    access: ChannelAccess,
    channel: u2,
};

const ReadBackCommand = packed struct {
    reserved: u1 = 0,
    channel_0: bool,
    channel_1: bool,
    channel_2: bool,
    latch_status: bool,
    latch_count: bool,
    read_back: u2 = 3,
};

const Status = packed struct {
    number: ChannelNumberMode,
    operation: ChannelOperation,
    access: ChannelAccess,
    null_count_flags: bool,
    output_pin_state: bool,
};

fn write_command(cmd: Command) void {
    x86.outb(command, @bitCast(cmd));
    log.debug("write: ch={d} a={s} n={s} o={d}", .{ cmd.channel, @tagName(cmd.access), @tagName(cmd.number), @tagName(cmd.operation) });
}

fn write_read_back_command(cmd: ReadBackCommand) void {
    x86.outb(command, @bitCast(cmd));
    log.debug("read back:{s}{s}{s}{s}{s}", .{
        if (cmd.latch_count) " latch_count" else "",
        if (cmd.latch_status) " latch_status" else "",
        if (cmd.channel_0) " channel_0" else "",
        if (cmd.channel_1) " channel_1" else "",
        if (cmd.channel_2) " channel_2" else "",
    });
}

fn get_status(channel: u2) Status {
    const status: Status = @bitCast(x86.inb(@as(u16, 0x40) + channel));

    log.debug("channel {d} status: n={s} o={s} a={s} {s} {s}", .{
        channel,
        @tagName(status.number),
        @tagName(status.operation),
        @tagName(status.access),
        if (status.null_count_flags) "waiting_for_divisor" else "programmed",
        if (status.output_pin_state) "output_hi" else "output_lo",
    });

    return status;
}

const PITChannel = struct {
    channel: u2,
    port: u16,
    number: ChannelNumberMode,
    operation: ChannelOperation,
    access: ChannelAccess,

    pub fn init(channel: u2, status: Status) PITChannel {
        std.debug.assert(channel < 3);

        return .{ .channel = channel, .port = 0x40 + @as(u16, channel), .number = status.number, .operation = status.operation, .access = status.access };
    }

    pub fn read_count(self: PITChannel) u16 {
        if (self.access == .lo_byte_only or self.access == .hi_byte_only) {
            var count: u16 = @bitCast(x86.inb(self.port));
            if (self.access == .hi_byte_only) count <<= 8;
            return count;
        }

        const status = x86.pause_interrupts();
        defer x86.resume_interrupts(status);

        write_command(.{
            .access = .latch_count_value_command,
            .channel = self.channel,
            .number = .binary,
            .operation = .interrupt_on_terminal_count,
        });

        var count: u16 = @bitCast(x86.inb(self.port));
        count |= @as(u16, x86.inb(self.port)) << 8;

        return count;
    }

    pub fn read_status(self: PITChannel, latch_count: bool, latch_status: bool) Status {
        write_read_back_command(.{
            .latch_count = !latch_count,
            .latch_status = !latch_status,
            .channel_0 = self.channel == 0,
            .channel_1 = self.channel == 1,
            .channel_2 = self.channel == 2,
        });

        const status = get_status(self.channel);
        self.access = status.access;
        self.number = status.number;
        self.operation = status.operation;
        return status;
    }

    pub fn set_reload_value(self: PITChannel, count: u16) void {
        const status = x86.pause_interrupts();
        defer x86.resume_interrupts(status);

        // note: a reload value of 0 means 65536

        if (self.access == .lo_byte_only or self.access == .both_bytes) x86.outb(self.port, @intCast(count & 0xff));
        if (self.access == .hi_byte_only or self.access == .both_bytes) x86.outb(self.port, @intCast((count >> 8) & 0xff));
    }

    pub fn set_frequency(self: PITChannel, frequency: u32) void {
        const reload_value: u16 = @intCast(pit_frequency / frequency);
        log.debug("channel {d}: desired={d}Hz, reload={d}, actual={d:.1}Hz", .{
            self.channel,
            frequency,
            reload_value,
            pit_frequency / @as(u32, reload_value),
        });

        self.set_reload_value(reload_value);
    }
};

pub var channel_0: PITChannel = undefined;
pub var channel_1: PITChannel = undefined;
pub var channel_2: PITChannel = undefined;

pub fn initialize() void {
    write_read_back_command(.{
        .latch_count = false,
        .latch_status = false,
        .channel_0 = true,
        .channel_1 = true,
        .channel_2 = true,
    });

    const status_0 = get_status(0);
    const status_1 = get_status(1);
    const status_2 = get_status(2);

    channel_0 = PITChannel.init(0, status_0);
    channel_1 = PITChannel.init(1, status_1);
    channel_2 = PITChannel.init(2, status_2);
}

pub fn enable(frequency: u32, handler: interrupts.InterruptHandler, name: []const u8) void {
    channel_0.set_frequency(frequency);
    interrupts.set_irq_handler(.pit, handler, name);
    pic.clear_mask(.pit);
}
