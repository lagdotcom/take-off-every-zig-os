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

pub const FileSystem = struct {
    ptr: *anyopaque,
    name: []const u8,
    fs_name: []const u8,
    vtable: *const VTable,

    pub fn list_directory(self: *const FileSystem, allocator: std.mem.Allocator, path: []const u8) ![]DirectoryEntry {
        return self.vtable.list_directory(self.ptr, allocator, path);
    }

    pub fn read_file(self: *const FileSystem, allocator: std.mem.Allocator, path: []const u8) ![]u8 {
        return self.vtable.read_file(self.ptr, allocator, path);
    }
};

pub const VTable = struct {
    list_directory: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, path: []const u8) anyerror![]DirectoryEntry,
    read_file: *const fn (ctx: *anyopaque, allocator: std.mem.Allocator, path: []const u8) anyerror![]u8,
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

pub fn initialize(allocator: std.mem.Allocator) !void {
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
        }, .{
            .name = "read",
            .summary = "Read file contents",
            .exec = shell_fs_read,
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

fn shell_fs_list(sh: *shell.Context, _: []const u8) !void {
    var t = try sh.table();
    defer t.deinit();
    try t.add_heading(.{ .name = "Name" });
    try t.add_heading(.{ .name = "File System" });

    for (file_systems.items) |sys| {
        try t.add_string(sys.name);
        try t.add_string(sys.fs_name);
        try t.end_row();
    }
    t.print();
}

fn shell_fs_dir(sh: *shell.Context, args: []const u8) !void {
    const parts = tools.split_by_whitespace(args);

    if (parts[0].len < 1) {
        console.puts("syntax: fs dir <name> [path]\n");
        return;
    }

    const maybe_sys = get_by_name(parts[0]);
    if (maybe_sys == null) {
        console.printf("unknown file system: {s}\n", .{parts[0]});
        return;
    }
    const sys = maybe_sys.?;

    const entries = try sys.list_directory(sh.allocator, if (parts[1].len > 0) parts[1] else "/");
    defer sh.allocator.free(entries);

    if (entries.len == 0) {
        console.printf("no entries found\n", .{});
    } else {
        var ctime_buffer: [11]u8 = undefined;
        var mtime_buffer: [11]u8 = undefined;
        var size_buffer: [6]u8 = undefined;

        var t = try sh.table();
        defer t.deinit();
        try t.add_heading(.{ .name = "Size" });
        try t.add_heading(.{ .name = "Created" });
        try t.add_heading(.{ .name = "Modified" });
        try t.add_heading(.{ .name = "Name" });

        for (entries) |e| {
            const ctime = if (e.created) |ct| try ct.format_ymd(ctime_buffer[0..11]) else "unknown";
            const mtime = if (e.modified) |mt| try mt.format_ymd(mtime_buffer[0..11]) else "unknown";

            try t.add_string(if (e.type == .directory) "" else try tools.nice_size(size_buffer[0..6], e.size));
            try t.add_string(ctime);
            try t.add_string(mtime);
            if (e.type == .directory) try t.add_fmt("{s}/", .{e.name}) else try t.add_string(e.name);
            try t.end_row();
        }

        t.print();
    }
}

fn shell_fs_read(sh: *shell.Context, args: []const u8) !void {
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

    const buffer = try sys.read_file(sh.allocator, parts[1]);
    defer sh.allocator.free(buffer);

    tools.hex_dump(console.printf_nl, buffer);
}

pub fn scan(allocator: std.mem.Allocator) !void {
    for (block_device.get_list()) |*dev| {
        const buffer = try dev.alloc_sector_buffer(allocator, 1);
        if (dev.read(0, 1, buffer)) try scan_for_file_systems(allocator, dev, buffer);
        allocator.free(buffer);
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

pub fn is_empty_path(path: []const u8) bool {
    var iter = PathIterator.init(path);
    while (iter.next()) |_|
        return false;

    return true;
}
