const std = @import("std");
const log = std.log.scoped(.acpi);

const console = @import("console.zig");
const KernelAllocator = @import("main.zig").KernelAllocator;
const shell = @import("shell.zig");
const tools = @import("tools.zig");

var kalloc: *const KernelAllocator = undefined;

fn shell_mem(sh: *shell.Context, _: []const u8) !void {
    var t = try sh.table();
    defer t.deinit();
    try kalloc.report_table(&t);

    const report = kalloc.report();

    var size_buffer: [18]u8 = undefined;
    const free = try tools.nice_size(size_buffer[0..6], report.free);
    const used = try tools.nice_size(size_buffer[6..12], report.used);
    const reserved = try tools.nice_size(size_buffer[12..18], report.reserved);

    console.printf("Total free: {s}, used: {s}, reserved: {s}", .{ free, used, reserved });
}

pub fn initialize(k: *KernelAllocator) !void {
    log.debug("initializing", .{});
    defer log.debug("done", .{});

    kalloc = k;

    try shell.add_command(.{
        .name = "mem",
        .summary = "Memory information",
        .exec = shell_mem,
    });
}
