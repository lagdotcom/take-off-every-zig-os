const std = @import("std");

const console = @import("console.zig");
const cpuid = @import("cpuid.zig");
const gdt = @import("gdt.zig");
const keyboard = @import("keyboard.zig");
const log = @import("log.zig");
const pci = @import("pci.zig");
const serial = @import("serial.zig");

pub fn kernel_log_fn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    log.write(level, "(" ++ @tagName(scope) ++ "): " ++ format, args);
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    @setCold(true);

    _ = error_return_trace;
    _ = ret_addr;
    kernel_log_fn(.err, .kernel, "!panic! {s}", .{msg});

    while (true) {}
}

pub fn initialize() void {
    const com1 = serial.initialize(serial.COM1) catch unreachable;
    log.initialize(com1);

    gdt.initialize();

    console.initialize();
    console.puts("Hello Zig Kernel!\n\n");

    cpuid.initialize();

    keyboard.report_status();
    keyboard.set_leds(true, true, true);

    pci.enumerate_buses();

    // hang forever
    while (true) {}
}
