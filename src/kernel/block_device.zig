const std = @import("std");
const log = std.log.scoped(.block_device);

const ata = @import("ata.zig");
const console = @import("console.zig");
const fs = @import("driver/fs.zig");
const mbr = @import("driver/fs/mbr.zig");
const shell = @import("shell.zig");
const tools = @import("tools.zig");

pub const BlockDevice = struct {
    ptr: *anyopaque,
    name: []const u8,
    vtable: *const VTable,

    pub fn read(self: *const BlockDevice, lba: u28, sector_count: u8, buffer: []u8) bool {
        log.debug("{s}.read({d}, {d}, {x})", .{ self.name, lba, sector_count, @intFromPtr(buffer.ptr) });
        return self.vtable.read(self.ptr, lba, sector_count, buffer);
    }
};

pub const VTable = struct {
    read: *const fn (ctx: *anyopaque, lba: u28, sector_count: u8, buffer: []u8) bool,
};

const BlockDeviceList = std.ArrayList(BlockDevice);

pub var block_devices: BlockDeviceList = undefined;

pub fn init(allocator: std.mem.Allocator) void {
    block_devices = BlockDeviceList.init(allocator);
    shell.add_command(.{
        .name = "block",
        .summary = "Get information on block IO devices",
        .sub_commands = &.{ .{
            .name = "list",
            .summary = "List available devices",
            .exec = list_block_devices,
        }, .{
            .name = "fs",
            .summary = "Try to identify file system on drive",
            .exec = identify_block_device_fs,
        } },
    });
}

pub fn add(device: BlockDevice) !void {
    try block_devices.append(device);
    log.debug("added {s}", .{device.name});
}

pub fn get_by_name(name: []const u8) ?BlockDevice {
    for (block_devices.items) |dev| {
        if (std.mem.eql(u8, name, dev.name)) return dev;
    }
    return null;
}

fn list_block_devices(_: []const u8) void {
    for (block_devices.items) |dev|
        console.printf("{s}\n", .{dev.name});
}

fn identify_block_device_fs(name: []const u8) void {
    const maybe_dev = get_by_name(name);
    if (maybe_dev == null) {
        console.printf("unknown device name: {s}\n", .{name});
        return;
    }
    const dev = maybe_dev.?;

    const buffer = block_devices.allocator.alloc(u8, ata.sector_size) catch unreachable;
    defer block_devices.allocator.free(buffer);

    console.printf("attempting read at lba 0, {d} bytes\n", .{buffer.len});
    if (!dev.read(0, 1, buffer)) {
        console.printf("read failed\n", .{});
        return;
    }

    tools.hex_dump(console.printf_nl, buffer);

    const fs_type = fs.identify(buffer);
    console.printf("file system: {s}\n", .{@tagName(fs_type)});
    fs.show_info(console.printf_nl, fs_type, buffer, block_devices.allocator, dev);
}
