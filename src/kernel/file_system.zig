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

    pub fn list_directory(self: *const FileSystem, allocator: std.mem.Allocator, path: []const u8) ![]DirectoryEntry {
        return self.vtable.list_directory(self.ptr, allocator, path);
    }
};

pub const VTable = struct {
    list_directory: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, path: []const u8) anyerror![]DirectoryEntry,
};

pub const EntryType = enum(u8) {
    directory,
    file,
};

pub const DirectoryEntry = struct {
    name: []const u8,
    size: u64,
    type: EntryType,
    address: union { lba28: u28, cluster: u32 },
    created: ?time.DateTime,
    modified: ?time.DateTime,
};

const FileSystemList = std.ArrayList(FileSystem);

var file_systems: FileSystemList = undefined;

pub fn init(allocator: std.mem.Allocator) !void {
    file_systems = FileSystemList.init(allocator);

    try shell.add_command(.{
        .name = "fs",
        .summary = "Get file system information",
        .sub_commands = &.{ .{
            .name = "list",
            .summary = "List available file systems",
            .exec = shell_fs_list,
        }, .{
            .name = "dir",
            .summary = "Get file system listing for given path",
            .exec = shell_fs_dir,
        } },
    });
}

pub fn add(sys: FileSystem) !void {
    try file_systems.append(sys);
    log.debug("added {s}", .{sys.name});
}

pub fn get_list() []FileSystem {
    return file_systems.items;
}

pub fn get_by_name(name: []const u8) ?FileSystem {
    for (file_systems.items) |sys| {
        if (std.mem.eql(u8, name, sys.name)) return sys;
    }
    return null;
}

fn shell_fs_list(_: std.mem.Allocator, _: []const u8) !void {
    for (file_systems.items) |sys|
        console.printf("{s} ({s})\n", .{ sys.name, sys.fs_name });
}

fn shell_fs_dir(allocator: std.mem.Allocator, args: []const u8) !void {
    const parts = tools.split_by_whitespace(args);

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

    const entries = try sys.list_directory(allocator, parts[1]);
    defer allocator.free(entries);

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
            const ctime = if (e.created) |ct| try ct.format_ymd(ctime_buffer[0..11]) else "unknown";
            const mtime = if (e.modified) |mt| try mt.format_ymd(mtime_buffer[0..11]) else "unknown";

            if (e.type == .directory) {
                console.printf("        {s} {s} {s}/\n", .{ ctime, mtime, e.name });
            } else {
                console.printf("{s:7} {s} {s} {s}\n", .{ try tools.nice_size(size_buffer[0..6], e.size), ctime, mtime, e.name });
            }
        }
    }
}

pub fn scan(allocator: std.mem.Allocator) !void {
    const buffer = try allocator.alloc(u8, 512);
    defer allocator.free(buffer);

    for (block_device.get_list()) |*dev| {
        if (dev.read(0, 1, buffer)) try scan_for_file_systems(allocator, dev, buffer);
    }
}

pub fn scan_for_file_systems(allocator: std.mem.Allocator, dev: *const block_device.BlockDevice, buffer: []const u8) !void {
    switch (fs.identify(buffer)) {
        .MBR => {
            const partition_buffer = try allocator.alloc(u8, 512);
            defer allocator.free(partition_buffer);

            const partitions = try fs_mbr.get_partitions(allocator, buffer);
            defer allocator.free(partitions);

            for (partitions) |p| {
                if (dev.read(p.lba, 1, partition_buffer)) try scan_for_file_systems(allocator, dev, partition_buffer);
            }
        },

        .FAT => try fs_fat.add(allocator, dev, buffer),

        else => {},
    }
}

pub const PathIterator = struct {
    string: []const u8,
    index: usize,

    pub fn init(string: []const u8) PathIterator {
        return .{ .string = string, .index = 0 };
    }

    fn ch(self: *PathIterator) ?u8 {
        if (self.eos()) return null;
        return self.string[self.index];
    }

    fn advance(self: *PathIterator) void {
        if (!self.eos()) self.index += 1;
    }

    fn eos(self: *PathIterator) bool {
        return self.index >= self.string.len;
    }

    pub fn next(self: *PathIterator) ?[]const u8 {
        // Skip leading separators
        while (self.ch() == '/' or self.ch() == '\\') {
            self.advance();
            if (self.eos()) return null;
        }

        const start_index = self.index;

        // Read until the next separator or end of string
        while (self.ch() != null and self.ch() != '/' and self.ch() != '\\') {
            self.advance();
        }

        return if (self.index > start_index) self.string[start_index..self.index] else null;
    }
};
