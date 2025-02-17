const std = @import("std");
const uefi = std.os.uefi;
const L = std.unicode.utf8ToUtf16LeStringLiteral;

const kernel = @import("kernel.zig");

pub const std_options = .{ .log_level = .debug, .logFn = kernel.kernel_log_fn };

// Define root.panic to override the std implementation
pub const panic = kernel.panic;

fn print_safe(utf8_buf: []u8, ucs2: []u16, con: *uefi.protocol.SimpleTextOutput, comptime fmt: []const u8, args: anytype) !uefi.Status {
    const utf8 = try std.fmt.bufPrintZ(utf8_buf, fmt, args);
    const len = try std.unicode.utf8ToUtf16Le(ucs2, utf8);

    ucs2[len] = 0;

    return con.outputString(@ptrCast(ucs2));
}

fn get_protocol(boot: *uefi.tables.BootServices, protocol: type) !*protocol {
    var object: *protocol = undefined;

    if (boot.locateProtocol(&protocol.guid, null, @ptrCast(&object)) != .Success) {
        return error.MissingProtocol;
    }

    return object;
}

const Printer = struct {
    sto: *uefi.protocol.SimpleTextOutput,
    buf_utf8: []u8,
    buf_ucs2: []u16,

    pub fn init(allocator: std.mem.Allocator, sto: *uefi.protocol.SimpleTextOutput) !Printer {
        const buf_utf8 = try allocator.alloc(u8, 256);
        const buf_ucs2 = try allocator.alloc(u16, 256);

        return Printer{ .sto = sto, .buf_utf8 = buf_utf8, .buf_ucs2 = buf_ucs2 };
    }

    pub fn clear(self: Printer) void {
        _ = self.sto.reset(false);
    }

    pub fn print(self: Printer, comptime fmt: []const u8, args: anytype) void {
        _ = print_safe(self.buf_utf8, self.buf_ucs2, self.sto, fmt, args) catch unreachable;
    }
};

pub fn main() uefi.Status {
    const allocator = uefi.pool_allocator;
    const boot = uefi.system_table.boot_services.?;

    const con = get_protocol(boot, uefi.protocol.SimpleTextOutput) catch unreachable;
    const printer = Printer.init(uefi.pool_allocator, con) catch unreachable;

    printer.clear();

    // printer.print("console max mode: {d}\r\n", .{con.mode.max_mode});
    // for (0..con.mode.max_mode) |mode| {
    //     var columns: usize = undefined;
    //     var rows: usize = undefined;
    //     _ = con.queryMode(mode, &columns, &rows);

    //     printer.print("console mode {d}: {d}x{d}\r\n", .{ mode, columns, rows });
    // }

    var map_size: usize = 0;
    var map_key: usize = undefined;
    var descriptor_size: usize = undefined;
    var descriptor_version: u32 = undefined;

    var map_block: [*]align(8) u8 = undefined;

    // Fetch the memory map.
    // Careful! Every call to boot services can alter the memory map.
    while (uefi.Status.BufferTooSmall == boot.getMemoryMap(&map_size, @ptrCast(map_block), &map_key, &descriptor_size, &descriptor_version)) {
        // allocatePool is the UEFI equivalent of malloc. allocatePool may
        // alter the size of the memory map, so we must check the return
        // value of getMemoryMap every time.
        if (uefi.Status.Success != boot.allocatePool(uefi.tables.MemoryType.BootServicesData, map_size, &map_block)) {
            return .BufferTooSmall;
        }
    }

    var mem_block_count: usize = 0;

    var total_available: u64 = 0;
    _ = con.outputString(L("enumerating usable memory:\r\n"));
    for (0..map_size / descriptor_size) |i| {
        const offset = i * descriptor_size;
        const d: *uefi.tables.MemoryDescriptor = @alignCast(@ptrCast(map_block[offset .. offset + @sizeOf(uefi.tables.MemoryDescriptor)]));

        if (d.type == .ConventionalMemory or d.type == .BootServicesCode or d.type == .BootServicesData) {
            const size = 4 * 1024 * d.number_of_pages;
            total_available += size;
            mem_block_count += 1;
        }
    }
    printer.print("total available: {x} bytes\r\n", .{total_available});

    // get the current video mode
    const gfx = get_protocol(boot, uefi.protocol.GraphicsOutput) catch unreachable;
    const video = kernel.VideoInfo{
        .framebuffer_addr = gfx.mode.frame_buffer_base,
        .framebuffer_size = gfx.mode.frame_buffer_size,
        .horizontal = gfx.mode.info.horizontal_resolution,
        .vertical = gfx.mode.info.vertical_resolution,
        .pixels_per_scan_line = gfx.mode.info.pixels_per_scan_line,
        .framebuffer = @ptrFromInt(@as(usize, @intCast(gfx.mode.frame_buffer_base))),
        .format = gfx.mode.info.pixel_format,
    };

    printer.print("framebuffer: @{x}+{x}, {d}x{d}, {d} per line, format={s}\r\n", .{ video.framebuffer_addr, video.framebuffer_size, video.horizontal, video.vertical, video.pixels_per_scan_line, @tagName(gfx.mode.info.pixel_format) });

    // get space for our memory block list
    const memory = allocator.alloc(kernel.MemoryBlock, mem_block_count) catch return .BufferTooSmall;

    // get the latest memory map
    while (boot.getMemoryMap(&map_size, @ptrCast(map_block), &map_key, &descriptor_size, &descriptor_version) != .Success) {
        if (uefi.Status.Success != boot.allocatePool(uefi.tables.MemoryType.BootServicesData, map_size, &map_block)) {
            return .BufferTooSmall;
        }
    }

    // fill in the memory block list
    // TODO: merge contiguous blocks
    var mi: usize = 0;
    for (0..map_size / descriptor_size) |i| {
        const offset = i * descriptor_size;
        const d: *uefi.tables.MemoryDescriptor = @alignCast(@ptrCast(map_block[offset .. offset + @sizeOf(uefi.tables.MemoryDescriptor)]));

        const size = 4 * 1024 * d.number_of_pages;
        const addr = d.physical_start;

        if (d.type == .ConventionalMemory or d.type == .BootServicesCode or d.type == .BootServicesData) {
            memory[mi] = .{ .addr = addr, .size = size };
            mi += 1;
        }
    }

    if (boot.exitBootServices(uefi.handle, map_key) != .Success) return .LoadError;

    // and run the OS kernel!
    kernel.initialize(.{ .memory = memory, .video = video });

    return .LoadError;
}
