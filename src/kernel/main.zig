const std = @import("std");
const log = std.log.scoped(.kernel);

const acpi = @import("../common/acpi.zig");
const ata = @import("ata.zig");
const block_device = @import("block_device.zig");
const console = @import("console.zig");
const cpuid = @import("cpuid.zig");
const file_system = @import("file_system.zig");
const gdt = @import("gdt.zig");
const interrupts = @import("interrupts.zig");
const KernelAllocator = @import("KernelAllocator.zig");
const keyboard = @import("keyboard.zig");
const log_module = @import("log.zig");
const pci = @import("pci.zig");
const ps2 = @import("ps2.zig");
const serial = @import("serial.zig");
const shell = @import("shell.zig");
const video = @import("video.zig");

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

    _ = error_return_trace;
    _ = ret_addr;
    kernel_log_fn(.err, .kernel, "!panic! {s}", .{msg});

    console.set_foreground_colour(video.rgb(255, 255, 0));
    console.set_background_colour(video.rgb(128, 0, 0));
    console.puts("\n!!! KERNEL PANIC !!!\n");
    console.puts(msg);

    const usage = kalloc.report();
    console.printf("\nkalloc: free={d} used={d} reserved={d}\n", .{ usage.free, usage.used, usage.reserved });

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
    console.set_foreground_colour(video.rgb(255, 255, 0));
    console.puts("Take off every 'ZIG'‼\n\n");

    console.set_foreground_colour(video.rgb(255, 255, 255));

    // initialize early so other modules can add their commands to it
    shell.initialize(allocator) catch |e| return kernel_init_error("shell", e);

    gdt.initialize();
    interrupts.initialize();
    ata.initialize() catch |e| return kernel_init_error("ata", e);
    block_device.init(allocator) catch |e| return kernel_init_error("block_device", e);
    file_system.init(allocator) catch |e| return kernel_init_error("file_system", e);
    cpuid.initialize();
    pci.initialize(allocator) catch |e| return kernel_init_error("pci", e); // relies on ATA, BlockDevice
    file_system.scan(allocator) catch |e| return kernel_init_error("file_system", e); // relies on PCI

    var fadt_table: ?*acpi.FixedACPIDescriptionTable = null;

    const tables = acpi.read_acpi_tables(allocator, p.rsdp_entries) catch |e| return kernel_init_error("acpi", e);
    for (tables) |table| {
        switch (table) {
            .fadt => |fadt| {
                console.printf("FADT v{d}.{d} e{d} -- len {d}\n", .{ fadt.header.revision, fadt.fadt_minor_version.minor, fadt.fadt_minor_version.errata, fadt.header.length });
                console.printf("FACS@{x} DSDT@{x} SMI@{x}\n", .{ fadt.firmware_ctrl, fadt.dsdt, fadt.smi_cmd });
                console.printf("IA-PC: {any}\n", .{fadt.ia_pc_boot_arch});
                console.printf("features: {any}\n", .{fadt.flags});

                fadt_table = fadt;
            },
            .unknown => |unk| {
                console.printf("unknown table: {s} v{d}\n", .{ unk.signature, unk.revision });
            },
            else => {
                console.printf("{any}\n", .{table});
            },
        }
    }

    keyboard.initialize(allocator) catch |e| return kernel_init_error("keyboard", e);

    // TODO disable USB legacy support on any controllers before calling this
    ps2.initialize(fadt_table);

    shell.enter(allocator) catch |e| log.err("during shell.enter: {s}", .{@errorName(e)});

    std.debug.panic("end of kernel reached", .{});
}
