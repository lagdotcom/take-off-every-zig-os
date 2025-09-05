const std = @import("std");
const log = std.log.scoped(.kernel);

const acpi = @import("acpi.zig");
const ata = @import("ata.zig");
const block_device = @import("block_device.zig");
const console = @import("console.zig");
const cpuid = @import("cpuid.zig");
const file_system = @import("file_system.zig");
const fonts = @import("fonts.zig");
const gdt = @import("gdt.zig");
const hpet = @import("hpet.zig");
const interrupts = @import("interrupts.zig");
const KernelAllocator = @import("KernelAllocator.zig");
const keyboard = @import("keyboard.zig");
const log_module = @import("log.zig");
const mem = @import("mem.zig");
const mouse = @import("mouse.zig");
const pci = @import("pci.zig");
const pit = @import("pit.zig");
const ps2 = @import("ps2.zig");
const serial = @import("serial.zig");
const shell = @import("shell.zig");
const time = @import("time.zig");
const video = @import("video.zig");
const viz = @import("viz.zig");

pub const BootInfo = struct {
    memory: []const KernelAllocator.MemoryBlock,
    video: video.VideoInfo,
    rsdp_entries: []const usize,
};

pub const MemoryBlock = KernelAllocator.MemoryBlock;
pub const VideoInfo = video.VideoInfo;

var boot_info: BootInfo = undefined;
var kalloc: KernelAllocator.KernelAllocator = undefined;
var allocator: std.mem.Allocator = undefined;

pub fn kernel_log_fn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    log_module.write(level, "(" ++ @tagName(scope) ++ "): " ++ format, args);
}

pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    @setCold(true);

    kernel_log_fn(.err, .kernel, "!panic! {s}", .{msg});

    console.set_foreground_colour(video.vga.rgb(255, 255, 0));
    console.set_background_colour(video.vga.rgb(128, 0, 0));
    console.puts("\n!!! KERNEL PANIC !!!\n");
    console.puts(msg);

    const usage = kalloc.report();
    console.printf("\nkalloc: free={d} used={d} reserved={d}\n", .{ usage.free, usage.used, usage.reserved });

    if (ret_addr) |addr| console.printf("return address: {x}\n", .{addr});

    if (error_return_trace) |trace|
        for (trace.instruction_addresses) |addr|
            console.printf("  {x:16} ???\n", .{addr});

    infinite_loop();
}

fn infinite_loop() noreturn {
    while (true) {}
}

fn kernel_init_error(module: []const u8, err: anyerror) void {
    log.err("while initializing {s}: {s}", .{ module, @errorName(err) });
}

pub fn initialize(p: BootInfo) void {
    boot_info = p;

    // initialize super early so we have logging
    const com1 = serial.initialize(serial.COM1) catch |e| return kernel_init_error("serial", e);
    log_module.initialize(com1);

    kalloc = KernelAllocator.KernelAllocator.init(p.memory);
    allocator = kalloc.allocator();

    // get something on the screen lol
    video.initialize(&p.video);

    console.initialize();
    console.set_foreground_colour(p.video.rgb(255, 255, 0));
    console.puts("Take off every 'ZIG'‼\n\n");

    console.set_foreground_colour(p.video.rgb(255, 255, 255));

    // initialize early so other modules can add their commands to it
    shell.initialize(allocator) catch |e| return kernel_init_error("shell", e);

    mem.initialize(&kalloc) catch |e| return kernel_init_error("mem", e);
    gdt.initialize();
    interrupts.initialize();
    ata.initialize() catch |e| return kernel_init_error("ata", e);
    block_device.initialize(allocator) catch |e| return kernel_init_error("block_device", e);
    file_system.initialize(allocator) catch |e| return kernel_init_error("file_system", e);
    cpuid.initialize() catch |e| return kernel_init_error("cpuid", e);
    pci.initialize(allocator) catch |e| return kernel_init_error("pci", e); // relies on ATA, BlockDevice
    file_system.scan(allocator) catch |e| return kernel_init_error("file_system", e); // relies on PCI
    acpi.initialize(p.rsdp_entries) catch |e| return kernel_init_error("acpi", e);
    hpet.initialize(acpi.tables.hpet) catch |e| return kernel_init_error("hpet", e);

    pit.initialize();

    keyboard.initialize(allocator) catch |e| return kernel_init_error("keyboard", e);
    mouse.initialize(allocator, p.video.horizontal, p.video.vertical) catch |e| return kernel_init_error("mouse", e);

    // TODO disable USB legacy support on any controllers before calling this
    ps2.initialize(allocator, acpi.tables.fadt) catch |e| return kernel_init_error("ps2", e);

    fonts.initialize(allocator) catch |e| return kernel_init_error("fonts", e);

    time.initialize() catch |e| return kernel_init_error("time", e);

    shell.enter(allocator) catch |e| log.err("during shell.enter: {s}", .{@errorName(e)});
    // viz.enter(allocator) catch |e| log.err("during viz.enter: {s}", .{@errorName(e)});

    std.debug.panic("end of kernel reached", .{});
}

fn do_nothing(ctx: *interrupts.CpuState) usize {
    return @intFromPtr(ctx);
}
