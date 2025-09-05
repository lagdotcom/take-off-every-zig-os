const std = @import("std");
const log = std.log.scoped(.acpi);

const console = @import("console.zig");
const KernelAllocator = @import("KernelAllocator.zig");
const shell = @import("shell.zig");
const tools = @import("tools.zig");

var kalloc: *const KernelAllocator.KernelAllocator = undefined;

fn shell_mem(sh: *shell.Context, _: []const u8) !void {
    var t = try sh.table();
    defer t.deinit();

    try t.add_heading(.{ .name = "Type" });
    try t.add_heading(.{ .name = "Offset", .justify = .right });
    try t.add_heading(.{ .name = "Size" });
    try t.add_heading(.{ .name = "Reserved" });
    try t.add_heading(.{ .name = "End", .justify = .right });

    var total_free: u64 = 0;
    var total_used: u64 = 0;
    var total_reserved: u64 = 0;
    var size_buffer: [6]u8 = undefined;
    var entry: ?*KernelAllocator.Entry = kalloc.first;
    while (entry) |e| {
        if (e.free) {
            total_free += e.size;
        } else {
            total_used += e.size;
            total_reserved += e.size;
        }

        try t.add_string(if (e.free) "FREE" else "USED");

        try t.add_number(e.addr, 16);

        var size = try tools.nice_size(size_buffer[0..6], e.size);
        try t.add_string(size);

        size = try tools.nice_size(size_buffer[0..6], e.reserved);
        try t.add_string(size);

        try t.add_number(e.addr + e.size, 16);

        try t.end_row();
        entry = e.next;
    }
    t.print();

    console.printf("Total free:", .{});

    var size = try tools.nice_size(size_buffer[0..6], total_free);
    try t.add_string(size);
    console.printf("{s}, used:", .{size});

    size = try tools.nice_size(size_buffer[0..6], total_used);
    try t.add_string(size);
    console.printf("{s}, reserved:", .{size});

    size = try tools.nice_size(size_buffer[0..6], total_reserved);
    try t.add_string(size);
    console.printf_nl("{s}", .{size});
}

pub fn initialize(k: *const KernelAllocator.KernelAllocator) !void {
    log.debug("initializing", .{});
    defer log.debug("done", .{});

    kalloc = k;

    try shell.add_command(.{
        .name = "mem",
        .summary = "Memory information",
        .exec = shell_mem,
    });
}
