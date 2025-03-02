const std = @import("std");
const log = std.log.scoped(.file_system);

const block_device = @import("block_device.zig");
const console = @import("console.zig");
const fs = @import("driver/fs.zig");
const fs_fat = @import("driver/fs/fat.zig");
const fs_mbr = @import("driver/fs/mbr.zig");
const shell = @import("shell.zig");
const time = @import("time.zig");
const tools = @import("tools.zig");
const video = @import("video.zig");

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
    created: ?time.DateTime,
    modified: ?time.DateTime,
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
        var ctime_buffer: [11]u8 = undefined;
        var mtime_buffer: [11]u8 = undefined;
        var size_buffer: [6]u8 = undefined;

        console.set_background_colour(video.rgb(64, 64, 64));
        console.printf("SIZE    CREATED     MODIFIED    NAME\n", .{});
        console.set_background_colour(0);
        for (entries) |e| {
            const ctime = if (e.created) |ct| ct.format_ymd(ctime_buffer[0..11]) catch unreachable else "unknown";
            const mtime = if (e.modified) |mt| mt.format_ymd(mtime_buffer[0..11]) catch unreachable else "unknown";

            if (e.type == .directory) {
                console.printf("        {s} {s} {s}/\n", .{ ctime, mtime, e.name });
            } else {
                console.printf("{s:7} {s} {s} {s}\n", .{ tools.nice_size(size_buffer[0..6], e.size) catch unreachable, ctime, mtime, e.name });
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
