const std = @import("std");
const log = std.log.scoped(.file_system);

const block_device = @import("block_device.zig");
const console = @import("console.zig");
const fs = @import("driver/fs.zig");
const fs_fat = @import("driver/fs/fat.zig");
const fs_mbr = @import("driver/fs/mbr.zig");
const shell = @import("shell.zig");
const tools = @import("tools.zig");

pub const FileSystem = struct {
    ptr: *anyopaque,
    name: []const u8,
    fs_name: []const u8,
    vtable: *const VTable,

    pub fn list_directory(self: *const FileSystem, path: []const u8, allocator: std.mem.Allocator) []DirectoryEntry {
        return self.vtable.list_directory(self.ptr, path, allocator);
    }
};

pub const VTable = struct {
    list_directory: *const fn (ctx: *anyopaque, path: []const u8, allocator: std.mem.Allocator) []DirectoryEntry,
};

pub const EntryType = enum(u8) {
    directory,
    file,
};

pub const DirectoryEntry = struct {
    name: []const u8,
    size: u64,
    type: EntryType,
};

const FileSystemList = std.ArrayList(FileSystem);

pub var file_systems: FileSystemList = undefined;

pub fn init(allocator: std.mem.Allocator) void {
    file_systems = FileSystemList.init(allocator);

    shell.add_command(.{ .name = "fs", .summary = "Get file system information", .sub_commands = &.{ .{
        .name = "list",
        .summary = "List available file systems",
        .exec = shell_list,
    }, .{
        .name = "dir",
        .summary = "Get file system listing for given path",
        .exec = shell_dir,
    } } });
}

pub fn add(sys: FileSystem) !void {
    try file_systems.append(sys);
    log.debug("added {s}", .{sys.name});
}

pub fn get_by_name(name: []const u8) ?FileSystem {
    for (file_systems.items) |sys| {
        if (std.mem.eql(u8, name, sys.name)) return sys;
    }
    return null;
}

fn shell_list(_: []const u8) void {
    for (file_systems.items) |sys|
        console.printf("{s} ({s})\n", .{ sys.name, sys.fs_name });
}

fn shell_dir(args: []const u8) void {
    const parts = tools.split_by_space(args);

    if (parts[0].len < 1 or parts[1].len < 1) {
        console.puts("syntax: fs dir <name> <path>\n");
        return;
    }

    const maybe_sys = get_by_name(parts[0]);
    if (maybe_sys == null) {
        console.printf("unknown file system: {s}\n", .{parts[0]});
        return;
    }
    const sys = maybe_sys.?;

    const entries = sys.list_directory(parts[1], file_systems.allocator);
    defer file_systems.allocator.free(entries);

    if (entries.len == 0) {
        console.printf("no entries found\n", .{});
    } else {
        console.printf("{s}:\n", .{parts[1]});
        for (entries) |e| {
            if (e.type == .directory) {
                console.printf("  {s}/\n", .{e.name});
            } else {
                console.printf("  {s}, {d}b\n", .{ e.name, e.size });
            }
        }
    }
}

pub fn scan() void {
    const buffer = file_systems.allocator.alloc(u8, 512) catch unreachable;
    defer file_systems.allocator.free(buffer);

    for (block_device.block_devices.items) |*dev| {
        if (dev.read(0, 1, buffer)) scan_for_file_systems(dev, buffer);
    }
}

pub fn scan_for_file_systems(dev: *const block_device.BlockDevice, buffer: []const u8) void {
    switch (fs.identify(buffer)) {
        .MBR => {
            const partition_buffer = file_systems.allocator.alloc(u8, 512) catch unreachable;
            defer file_systems.allocator.free(partition_buffer);

            const partitions = fs_mbr.get_partitions(buffer, file_systems.allocator);
            defer file_systems.allocator.free(partitions);

            for (partitions) |p| {
                if (dev.read(p.lba, 1, partition_buffer)) scan_for_file_systems(dev, partition_buffer);
            }
        },

        .FAT => fs_fat.add(dev, buffer, file_systems.allocator),

        else => {},
    }
}
