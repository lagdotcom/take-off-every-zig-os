const std = @import("std");
const log = std.log.scoped(.time);

const cmos = @import("cmos.zig");
const console = @import("console.zig");
const interrupts = @import("interrupts.zig");
const pic = @import("pic.zig");
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

var current_time: DateTime = undefined;

pub fn initialize() !void {
    log.debug("initializing", .{});
    defer log.debug("done", .{});

    try shell.add_command(.{
        .name = "time",
        .summary = "Print the current date and time",
        .exec = shell_time,
    });

    const status = x86.pause_interrupts();
    defer x86.resume_interrupts(status);
    interrupts.set_irq_handler(.cmos_rtc, cmos_rtc_handler, "cmos_rtc_handler");
    pic.clear_mask(.cmos_rtc);
    pic.clear_mask(.cascade);

    var cmos_b = cmos.read_status_b();
    cmos_b.update_ended_interrupt_enabled = true;
    cmos.write_status_b(cmos_b);
    cmos.log_status_b(cmos_b);

    const cmos_c = cmos.read_status_c(); // clear any pending interrupt
    cmos.log_status_c(cmos_c);

    // get the starting time just in case
    cmos.wait_for_update();
    current_time = cmos.read_rtc(null);
}

fn cmos_rtc_handler(ctx: *interrupts.CpuState) usize {
    const status = cmos.read_status_c();
    // cmos.log_status_c(status);

    if (status.update_ended_interrupt)
        current_time = cmos.read_rtc(null);

    return @intFromPtr(ctx);
}

fn shell_time(sh: *shell.Context, _: []const u8) !void {
    const buffer = try sh.allocator.alloc(u8, 64);
    defer sh.allocator.free(buffer);

    const formatted = try current_time.format_ymd_hms(buffer);
    console.printf_nl("{s}", .{formatted});
}
