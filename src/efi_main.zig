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

    var total_size: u64 = 0;
    _ = con.outputString(L("enumerating usable memory:\r\n"));
    for (0..map_size / descriptor_size) |i| {
        const offset = i * descriptor_size;
        const d: *uefi.tables.MemoryDescriptor = @alignCast(@ptrCast(map_block[offset .. offset + @sizeOf(uefi.tables.MemoryDescriptor)]));

        const size = 4 * 1024 * d.number_of_pages;
        const start = d.physical_start;
        const end = start + size;
        total_size += size;

        if (d.type == .ConventionalMemory or d.type == .BootServicesCode or d.type == .BootServicesData)
            printer.print("{d:3} {s:23} addr={x:0>8}-{x:0>8} size={x:0>8}\r\n", .{ i, @tagName(d.type), start, end, size });
    }
    printer.print("total available: {x} bytes\r\n", .{total_size});

    // let's do some video mode querying

    const gfx = get_protocol(boot, uefi.protocol.GraphicsOutput) catch unreachable;
    var info: *uefi.protocol.GraphicsOutput.Mode.Info = undefined;
    var info_size: usize = undefined;

    const min_width = 640;
    const min_height = 480;
    const max_width = 1024;
    const max_height = 768;

    _ = con.outputString(L("enumerating video modes:\r\n"));
    for (0..gfx.mode.max_mode) |i| {
        if (gfx.queryMode(@intCast(i), &info_size, &info) != .Success) continue;
        if (info.horizontal_resolution < min_width or info.horizontal_resolution > max_width or info.vertical_resolution < min_height or info.vertical_resolution > max_height) continue;

        printer.print("{d:3} {d:5}x{d:<5} {s}\r\n", .{ i, info.horizontal_resolution, info.vertical_resolution, @tagName(info.pixel_format) });
    }

    // ok it's time to break free from UEFI land
    _ = con.clearScreen();

    // get the latest memory map key in case it changed
    while (boot.getMemoryMap(&map_size, @ptrCast(map_block), &map_key, &descriptor_size, &descriptor_version) != .Success) {
        if (uefi.Status.Success != boot.allocatePool(uefi.tables.MemoryType.BootServicesData, map_size, &map_block)) {
            return .BufferTooSmall;
        }
    }

    if (boot.exitBootServices(uefi.handle, map_key) != .Success) return .LoadError;

    // and run the OS kernel!
    // TODO pass the info the kernel needs...
    kernel.initialize();

    return .LoadError;
}
