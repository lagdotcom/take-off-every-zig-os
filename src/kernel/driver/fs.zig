const std = @import("std");

const block_device = @import("../block_device.zig");
const fat = @import("fs/fat.zig");
const mbr = @import("fs/mbr.zig");
const tools = @import("../tools.zig");

pub const FileSystem = enum {
    FAT,
    MBR,

    unknown,
};

pub fn identify(raw_sector: []const u8) FileSystem {
    if (fat.is_valid(raw_sector)) return .FAT;
    if (mbr.is_valid(raw_sector)) return .MBR;

    return .unknown;
}

pub fn show_info(logger: tools.log_function, fs_type: FileSystem, header_buffer: []const u8, maybe_allocator: ?std.mem.Allocator, maybe_dev: ?block_device.BlockDevice) !void {
    switch (fs_type) {
        .FAT => fat.show_info(logger, header_buffer, maybe_allocator, maybe_dev),
        .MBR => try mbr.show_info(logger, header_buffer, maybe_allocator, maybe_dev),
        else => logger("cannot show info for unknown filesystem", .{}),
    }
}
