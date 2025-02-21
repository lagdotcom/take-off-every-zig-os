const std = @import("std");

const acpi = @import("acpi.zig");
const console = @import("console.zig");
const cpuid = @import("cpuid.zig");
const gdt = @import("gdt.zig");
const interrupts = @import("interrupts.zig");
const KernelAllocator = @import("KernelAllocator.zig").KernelAllocator;
const log = @import("log.zig");
const pci = @import("pci.zig");
const ps2 = @import("ps2.zig");
const serial = @import("serial.zig");

pub const MemoryBlock = struct { addr: usize, size: usize };

pub const VideoInfo = struct {
    framebuffer_addr: u64,
    framebuffer_size: usize,
    horizontal: usize,
    vertical: usize,
    pixels_per_scan_line: usize,
    framebuffer: [*]volatile u32,
    format: std.os.uefi.protocol.GraphicsOutput.PixelFormat,

    pub fn get_index(self: VideoInfo, x: usize, y: usize) usize {
        return self.pixels_per_scan_line * y + x;
    }

    pub fn plot(self: VideoInfo, index: usize, colour: u32) void {
        self.framebuffer[index] = colour;
    }

    pub fn fill_rectangle(self: VideoInfo, x: usize, y: usize, width: usize, height: usize, colour: u32) void {
        var index = self.get_index(x, y);

        for (0..height) |_| {
            @memset(self.framebuffer[index .. index + width], colour);
            index += self.pixels_per_scan_line;
        }
    }

    pub fn fill(self: VideoInfo, colour: u32) void {
        @memset(self.framebuffer[0..self.framebuffer_size], colour);
    }

    pub fn rgb(self: VideoInfo, r: u32, g: u32, b: u32) u32 {
        const r32: u32 = @intCast(r);
        const g32: u32 = @intCast(g);
        const b32: u32 = @intCast(b);

        return switch (self.format) {
            .RedGreenBlueReserved8BitPerColor => (r32) | (g32 << 8) | (b32 << 16) | (0xff000000),
            .BlueGreenRedReserved8BitPerColor => (b32) | (g32 << 8) | (r32 << 16) | (0xff000000),

            else => std.debug.panic("unknown pixel format: {s}", .{@tagName(self.format)}),
        };
    }
};

pub const BootInfo = struct {
    memory: []MemoryBlock,
    video: VideoInfo,
    rsdp_entries: []usize,
};

pub var boot_info: BootInfo = undefined;
pub var kalloc: KernelAllocator = undefined;
pub var allocator: std.mem.Allocator = undefined;

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

    console.set_foreground_colour(boot_info.video.rgb(255, 255, 0));
    console.set_background_colour(boot_info.video.rgb(128, 0, 0));
    console.puts("\n!!! KERNEL PANIC !!!\n");
    console.puts(msg);

    const usage = kalloc.report();
    console.printf("\nkalloc: free={d} used={d} reserved={d}\n", .{ usage.free, usage.used, usage.reserved });

    while (true) {}
}

pub fn initialize(p: BootInfo) void {
    boot_info = p;

    const com1 = serial.initialize(serial.COM1) catch unreachable;
    log.initialize(com1);

    kalloc = KernelAllocator.init(p.memory);
    allocator = kalloc.allocator();

    gdt.initialize();
    interrupts.initialize();

    console.initialize();
    console.set_foreground_colour(boot_info.video.rgb(255, 255, 0));
    console.puts("Take off every 'ZIG'‼\n\n");

    console.set_foreground_colour(boot_info.video.rgb(255, 255, 255));

    cpuid.initialize();

    console.new_line();
    console.set_background_colour(boot_info.video.rgb(64, 64, 64));
    console.puts("Loc.\tVnID:DvID\tVendor\tType\n");
    console.set_background_colour(0);
    pci.enumerate_buses();

    var fadt_table: ?*acpi.FixedACPIDescriptionTable = null;

    const tables = acpi.read_acpi_tables(p.rsdp_entries) catch unreachable;
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

    // TODO disable USB legacy support on any controllers before calling this
    ps2.initialize(fadt_table);

    std.debug.panic("end of kernel reached", .{});
}
