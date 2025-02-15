const std = @import("std");

const console = @import("console.zig");
const cpuid = @import("cpuid.zig");
const gdt = @import("gdt.zig");
const keyboard = @import("keyboard.zig");
const log = @import("log.zig");
const pci = @import("pci.zig");
const serial = @import("serial.zig");

pub const MemoryBlock = struct {
    addr: u64,
    size: u64,
};

pub const VideoInfo = struct {
    framebuffer_addr: u64,
    framebuffer_size: usize,
    horizontal: usize,
    vertical: usize,
    pixels_per_scan_line: usize,
    framebuffer: [*]volatile u32,
};

pub const BootInfo = struct {
    memory: []MemoryBlock,
    video: VideoInfo,
};

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

pub fn initialize(p: BootInfo) void {
    const com1 = serial.initialize(serial.COM1) catch unreachable;
    log.initialize(com1);

    gdt.initialize();

    console.initialize(&p.video);
    console.puts("Hello Zig Kernel!\n\n");

    cpuid.initialize();

    keyboard.report_status();
    keyboard.set_leds(true, true, true);

    pci.enumerate_buses();

    for (p.memory) |mb|
        log.write(.debug, "mem block: {x} + {x}", .{ mb.addr, mb.size });

    // for (0..255) |y|
    //     for (0..255) |x|
    //         plot_pixel(p.video, x, y, rgb(128, @intCast(x), @intCast(y)));

    // hang forever
    while (true) {}
}

inline fn rgb(r: u8, g: u8, b: u8) u32 {
    const r32: u32 = @intCast(r);
    const g32: u32 = @intCast(g);
    const b32: u32 = @intCast(b);

    return r32 | (g32 << 8) | (b32 << 16) | 0xff000000;
}

fn plot_pixel(v: VideoInfo, x: usize, y: usize, pixel: u32) void {
    v.framebuffer[v.pixels_per_scan_line * y + x] = pixel;
}
