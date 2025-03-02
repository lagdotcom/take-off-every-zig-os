const std = @import("std");

const block_device = @import("../../block_device.zig");
const fat = @import("fat.zig");
const fs = @import("../fs.zig");
const tools = @import("../../tools.zig");

const CHSAddress = extern struct { c: u8, h: u8, s: u8 };

const PartitionType = enum(u8) {
    Free = 0,
    FAT12 = 1,
    @"XENIX root" = 2,
    @"XENIX usr" = 3,
    FAT16 = 4,
    @"Extended CHS" = 5,
    FAT16B = 6,
    @"IFS, HPFS, NTFS, exFAT, qnx" = 7,
    @"Logical sectored FAT12 or FAT16 (Commodore), AIX, qny, Dell container partition" = 8,
    @"AIX data/boot, qnz, Coherent fs, OS-9" = 9,
    @"OS/2 Boot Manager, Coherent swap" = 0xa,
    FAT32_CHS = 0xb,
    FAT32_LBA = 0xc,
    FAT16B_LBA = 0xe,
    @"Extended LBA" = 0xf,
    @"Logical sectored FAT12 or FAT16 (Leading Edge), hidden FAT12" = 0x11,
    @"Configurable, Recovery, EISA configuration, Hibernation, Diagnostics, Service, Rescue/Recovery" = 0x12,
    @"Logical sectored FAT12 or FAT16 (AST), hidden FAT16, Omega" = 0x14,
    @"Hidden extended CHS, Swap" = 0x15,
    @"Hidden FAT16B" = 0x16,
    @"Hidden IFS, HPFS, NTFS, exFAT" = 0x17,
    @"AST Zero Volt Suspend/SmartSleep" = 0x18,
    @"Willowtech Photon coS" = 0x19,
    @"Hidden FAT32" = 0x1b,
    @"Hidden FAT32 LBA, ASUS recovery" = 0x1c,
    @"Hidden FAT16 LBA" = 0x1e,
    @"Hidden extended LBA" = 0x1f,
    @"Windows Movile update XIP, Willowsoft Overture" = 0x20,
    @"HP Volume Expansion, FSo2" = 0x21,
    @"Oxygen Extended Partition Table" = 0x22,
    @"Windows Mobile boot XIP" = 0x23,
    @"Logical sectored FAT12 or FAT16 (NEC)" = 0x24,
    @"Windows Recovery Environment, Acer Rescue, RooterBOOT" = 0x27,
    AtheOS = 0x2a,
    SyllableOS = 0x2b,
    @"Personal CP/M-86" = 0x30,
    JFS = 0x35,
    @"THEOS v3.2" = 0x38,
    @"Plan 9 edition 3, THEOS v4 spanned" = 0x39,
    @"THEOS v4 4gb" = 0x3a,
    @"THEOS v4 extended" = 0x3b,
    @"PowerQuest Repair" = 0x3c,
    @"Hidden NetWare" = 0x3d,
    @"PICK R83, Venix 80286" = 0x40,
    @"Personal RISC, Linux/Minix, PPC PReP" = 0x41,
    @"SFS, Linux swap, Dynamic extended" = 0x42,
    @"Linux native" = 0x43,

    // etc. etc.
};

const PartitionEntry = extern struct {
    attributes: u8,
    chs_address: CHSAddress,
    type: PartitionType,
    chs_last_partition: CHSAddress,
    lba_start: u32,
    sector_count: u32,
};

const Sector = extern struct {
    bootstrap: [440]u8 align(1),
    unique_disk_id: u32 align(1),
    reserved: u16 align(1),
    partitions: [4]PartitionEntry align(1),
    signature: u16 align(1),
};

fn is_valid_partition(p: PartitionEntry) bool {
    // empty entry
    if (p.lba_start == 0 or p.sector_count == 0 or p.chs_address.c == 0 or p.chs_address.h == 0) return false;

    // seems invalid
    if (p.chs_address.c > p.chs_last_partition.c) return false;

    // ok fine
    return true;
}

pub fn is_valid(raw_sector: []const u8) bool {
    const mbr: *const Sector = @alignCast(@ptrCast(raw_sector.ptr));

    // MBR is an extension over FAT...
    if (mbr.signature == fat.valid_boot_sector_signature) {
        for (mbr.partitions) |p|
            if (is_valid_partition(p)) return true;
    }

    return false;
}

pub fn show_info(logger: tools.log_function, header_buffer: []const u8, maybe_allocator: ?std.mem.Allocator, maybe_dev: ?block_device.BlockDevice) void {
    const mbr: *const Sector = @alignCast(@ptrCast(header_buffer.ptr));

    logger("Disk ID: {x}", .{mbr.unique_disk_id});
    for (mbr.partitions, 0..) |p, i| {
        if (p.lba_start == 0) continue;

        logger("\tpartition {d}: {s}\n\t\tchs: {d},{d},{d} - {d},{d},{d}\n\t\tlba: start {d}, {d} sectors", .{
            i,
            @tagName(p.type),
            p.chs_address.c,
            p.chs_address.h,
            p.chs_address.s,
            p.chs_last_partition.c,
            p.chs_last_partition.h,
            p.chs_last_partition.s,
            p.lba_start,
            p.sector_count,
        });
    }

    // we've done all we can
    if (maybe_allocator == null or maybe_dev == null) return;

    const allocator = maybe_allocator.?;
    const dev = maybe_dev.?;

    const buffer = allocator.alloc(u8, 512) catch unreachable;
    defer allocator.free(buffer);

    for (mbr.partitions, 0..) |p, i| {
        if (!is_valid_partition(p)) continue;

        if (dev.read(@intCast(p.lba_start), 1, buffer)) {
            logger("partition {d}, lba {d} contents:", .{ i, p.lba_start });
            tools.hex_dump(logger, buffer);

            const p_type = fs.identify(buffer);
            logger("partition {d}, lba {d} contains file system type: {s}", .{ i, p.lba_start, @tagName(p_type) });

            fs.show_info(logger, p_type, buffer, maybe_allocator, maybe_dev);
        }
    }
}

const MBRPartition = struct {
    lba: u28,
    sector_count: usize,
};

pub fn get_partitions(allocator: std.mem.Allocator, header_buffer: []const u8) []MBRPartition {
    const mbr: *const Sector = @alignCast(@ptrCast(header_buffer.ptr));
    var partition_list = std.ArrayList(MBRPartition).init(allocator);

    for (mbr.partitions) |p| {
        if (is_valid_partition(p)) {
            partition_list.append(.{ .lba = @intCast(p.lba_start), .sector_count = p.sector_count }) catch unreachable;
        }
    }

    return partition_list.toOwnedSlice() catch unreachable;
}
