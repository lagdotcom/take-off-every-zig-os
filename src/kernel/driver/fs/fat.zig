const std = @import("std");
const log = std.log.scoped(.fat);

const block_device = @import("../../block_device.zig");
const fat = @import("fat.zig");
const file_system = @import("../../file_system.zig");
const time = @import("../../time.zig");
const tools = @import("../../tools.zig");

// this used to be important in DOS 1.0
const MediaType = enum(u8) {
    non_partitioned_removable_disk = 0xf0,
    non_removable_disk = 0xf8,

    obsolete_f9 = 0xf9,
    obsolete_fa,
    obsolete_fb,
    obsolete_fc,
    obsolete_fd,
    obsolete_fe,
    obsolete_ff,
};

pub const BPB = extern struct {
    jump_instruction: [3]u8,
    oem_identifier: [8]u8,
    bytes_per_sector: u16 align(1),
    sectors_per_cluster: u8,
    reserved_sectors: u16,
    fat_count: u8,
    root_directory_entries: u16 align(1),
    sector_count: u16 align(1),
    media_descriptor_type: MediaType,
    sectors_per_fat: u16,
    sectors_per_track: u16,
    head_count: u16,
    hidden_sectors: u32,
    large_sector_count: u32,
};

pub const EBPB12_16 = extern struct {
    drive_number: u8,
    reserved: u8,
    boot_signature: u8,
    volume_id: u32 align(1),
    volume_label: [11]u8,
    system_identifier: [8]u8,
    boot_code: [448]u8,
    bootable_partition_signature: u16,
};

const ExtraFlags = packed struct {
    active_fat: u4,
    reserved_4: u3,
    fat_is_mirrored_at_runtime: bool,
    reserved_8: u8,
};

pub const EBPB32 = extern struct {
    sectors_per_fat: u32,
    extra_flags: ExtraFlags,
    major_version: u8,
    minor_version: u8,
    root_cluster: u32,
    fsinfo_sector: u16,
    backup_boot_sector: u16,
    reserved_52: [12]u8,
    drive_number: u8,
    reserved_65: u8,
    boot_signature: u8,
    volume_id: u32 align(1),
    volume_label: [11]u8,
    system_identifier: [8]u8,
    boot_code: [420]u8,
    bootable_partition_signature: u16,
};

const FATHeader = struct {
    bpb: *const BPB,
    ebpb: union(enum) { fat12_16: *const EBPB12_16, fat32: *const EBPB32 },
};

const Attributes = packed struct {
    read_only: bool = false,
    hidden: bool = false,
    system: bool = false,
    volume_id: bool = false,
    directory: bool = false,
    archive: bool = false,
    _40: bool = false,
    _80: bool = false,
};

const long_name_attributes = Attributes{ .read_only = true, .hidden = true, .system = true, .volume_id = true };

const HourMinuteSecond = packed struct {
    second: u5,
    minute: u6,
    hour: u5,
};

const YearMinuteDay = packed struct {
    day: u5,
    month: u4,
    year: u7,
};

pub const FAT_DELETED = 0xe5;
pub const FAT_END_OF_DIRECTORY = 0;

pub const NormalDirEntry = extern struct {
    name: [11]u8,
    attributes: Attributes,
    reserved: u8,
    ctime_hundredths: u8,
    ctime_hms: HourMinuteSecond,
    ctime_ymd: YearMinuteDay,
    atime_ymd: YearMinuteDay,
    cluster_hi: u16,
    mtime_hms: HourMinuteSecond,
    mtime_ymd: YearMinuteDay,
    cluster_lo: u16,
    size: u32,
};

const ATTR_LONG_NAME: u8 = @bitCast(long_name_attributes);
const LAST_LONG_ENTRY = 0x40;
const LFN_COUNT_MASK = 0x3f;
const LFN_WORDS_PER_ENTRY = 13;
const MAX_LFN_SIZE = LFN_COUNT_MASK * LFN_WORDS_PER_ENTRY;

const LFNOrdinal = packed struct {
    ordinal: u6,
    final: bool,
    reserved: u1,
};

pub const LongFilenameDirEntry = extern struct {
    ordinal: LFNOrdinal,
    name_1: [5]u16 align(1),
    attributes: Attributes,
    reserved: u8,
    checksum: u8,
    name_2: [6]u16 align(1),
    zero: u16,
    name_3: [2]u16 align(1),
};

const DirEntry = union(enum) {
    normal: *NormalDirEntry,
    long: *LongFilenameDirEntry,
};

pub const fat12_cluster_types = struct {
    pub const free = 0;
    pub const bad = 0xff7;
    pub const end = 0xfff;
};

pub const valid_boot_sector_signature: u16 = 0xaa55;

pub fn is_valid(raw_sector: []const u8) bool {
    const bpb: *const BPB = @alignCast(@ptrCast(raw_sector[0..@sizeOf(BPB)]));

    // if (bpb.bootable_partition_signature != valid_boot_sector_signature) return false;
    if (raw_sector[510] != 0x55 or raw_sector[511] != 0xaa) return false;

    if (!((bpb.jump_instruction[0] == 0xeb and bpb.jump_instruction[2] == 0x90) or bpb.jump_instruction[0] == 0xe9)) return false;

    if (bpb.bytes_per_sector != 512 and bpb.bytes_per_sector != 1024 and bpb.bytes_per_sector != 2048 and bpb.bytes_per_sector != 4096) return false;

    if (bpb.sectors_per_cluster != 1 and bpb.sectors_per_cluster != 2 and bpb.sectors_per_cluster != 4 and bpb.sectors_per_cluster != 8 and bpb.sectors_per_cluster != 16 and bpb.sectors_per_cluster != 32 and bpb.sectors_per_cluster != 64 and bpb.sectors_per_cluster != 128) return false;

    if (bpb.reserved_sectors == 0) return false;

    if (bpb.fat_count == 0) return false;

    if (bpb.sector_count == 0 and bpb.large_sector_count == 0) return false;
    if (bpb.sector_count != 0 and bpb.large_sector_count != 0) return false;

    // close enough
    return true;
}

pub fn show_info(logger: tools.log_function, header_buffer: []const u8, maybe_allocator: ?std.mem.Allocator, maybe_dev: ?block_device.BlockDevice) void {
    const h = get_fat_header(header_buffer);

    const root_dir_size = (h.bpb.root_directory_entries * 32);
    const root_dir_sectors = (root_dir_size + (h.bpb.bytes_per_sector - 1)) / h.bpb.bytes_per_sector;
    const total_sectors = if (h.bpb.sector_count == 0) h.bpb.large_sector_count else h.bpb.sector_count;
    const sectors_per_fat = switch (h.ebpb) {
        .fat12_16 => |_| h.bpb.sectors_per_fat,
        .fat32 => |e| e.sectors_per_fat,
    };

    const fat_size: u64 = h.bpb.fat_count * sectors_per_fat;
    const data_sectors: u64 = total_sectors - (h.bpb.reserved_sectors + fat_size) + root_dir_sectors;
    const cluster_count: u64 = data_sectors / h.bpb.sectors_per_cluster;

    logger("type: {s} fat_size={d} total_sectors={d} data_sectors={d} cluster_count={d}", .{ @tagName(h.ebpb), sectors_per_fat, total_sectors, data_sectors, cluster_count });

    _ = maybe_allocator;
    _ = maybe_dev;
}

pub fn get_fat_header(raw_sector: []const u8) FATHeader {
    const bpb_slice = raw_sector[0..@sizeOf(BPB)];
    const ebpb_slice = raw_sector[@sizeOf(BPB)..];

    const bpb: *const BPB = @alignCast(@ptrCast(bpb_slice));

    if (bpb.root_directory_entries == 0) {
        const ebpb: *const EBPB32 = @alignCast(@ptrCast(ebpb_slice));
        return .{ .bpb = bpb, .ebpb = .{ .fat32 = ebpb } };
    }

    const ebpb: *const EBPB12_16 = @alignCast(@ptrCast(ebpb_slice));
    return .{ .bpb = bpb, .ebpb = .{ .fat12_16 = ebpb } };
}

pub fn add(allocator: std.mem.Allocator, dev: *const block_device.BlockDevice, buffer: []const u8) !void {
    const h = get_fat_header(buffer);

    const root_dir_size = h.bpb.root_directory_entries * 32;
    const root_dir_sectors = (root_dir_size + (h.bpb.bytes_per_sector - 1)) / h.bpb.bytes_per_sector;
    const total_sectors = if (h.bpb.sector_count == 0) h.bpb.large_sector_count else h.bpb.sector_count;
    const sectors_per_fat = switch (h.ebpb) {
        .fat12_16 => |_| h.bpb.sectors_per_fat,
        .fat32 => |e| e.sectors_per_fat,
    };

    const fat_size: u64 = h.bpb.fat_count * sectors_per_fat;
    const data_sectors: u64 = total_sectors - (h.bpb.reserved_sectors + fat_size) + root_dir_sectors;
    const cluster_count: u64 = data_sectors / h.bpb.sectors_per_cluster;

    if (cluster_count < 4085) {
        // TODO FAT12
    } else if (cluster_count < 65525) {
        var vol = try FAT16Volume.init(allocator, dev, h.bpb, h.ebpb.fat12_16);
        try file_system.add(vol.fs());
    } else {
        // TODO FAT32
    }
}

const FAT16Volume = struct {
    name: []const u8,
    dev: *const block_device.BlockDevice,
    bpb: *const BPB,
    ebpb: *const EBPB12_16,

    pub fn init(allocator: std.mem.Allocator, dev: *const block_device.BlockDevice, original_bpb: *const BPB, original_ebpb: *const EBPB12_16) !*FAT16Volume {
        const bpb = try allocator.create(BPB);
        bpb.* = original_bpb.*;

        const ebpb = try allocator.create(EBPB12_16);
        ebpb.* = original_ebpb.*;

        const fat16 = try allocator.create(FAT16Volume);
        fat16.name = "hd0"; // TODO
        fat16.dev = dev;
        fat16.bpb = bpb;
        fat16.ebpb = ebpb;
        return fat16;
    }

    pub fn fs(self: *FAT16Volume) file_system.FileSystem {
        return .{
            .ptr = self,
            .name = self.name,
            .fs_name = "FAT16",
            .vtable = &.{ .list_directory = list_directory },
        };
    }

    pub fn list_directory(ctx: *anyopaque, allocator: std.mem.Allocator, path: []const u8) ![]file_system.DirectoryEntry {
        const self: *FAT16Volume = @ptrCast(@alignCast(ctx));
        var list = std.ArrayList(file_system.DirectoryEntry).init(allocator);
        _ = path;

        const bpb = self.bpb;
        // tools.struct_dump(BPB, log.debug, bpb);

        // const root_dir_size: usize = bpb.root_directory_entries * 32;
        // const root_dir_sectors = (root_dir_size + (bpb.bytes_per_sector - 1)) / bpb.bytes_per_sector;
        const first_root_dir_sector: u28 = @intCast(bpb.hidden_sectors + bpb.reserved_sectors + (bpb.fat_count * bpb.sectors_per_fat));

        const buffer = try allocator.alloc(u8, bpb.bytes_per_sector);
        defer allocator.free(buffer);

        const lfn_buffer = try allocator.alloc(u16, MAX_LFN_SIZE);
        var lfn_pending = false;
        defer allocator.free(lfn_buffer);

        const lfn_final_buffer = try allocator.alloc(u8, MAX_LFN_SIZE * 4);
        defer allocator.free(lfn_final_buffer);

        var iter = DirEntryIterator.init(buffer, self.dev, first_root_dir_sector, bpb.bytes_per_sector);
        while (iter.next()) |e| {
            switch (e) {
                .normal => |entry| {
                    // tools.struct_dump(NormalDirEntry, log.debug, entry);
                    if (e.normal.attributes.volume_id) continue;

                    try list.append(.{
                        .name = try if (lfn_pending) parse_lfn(allocator, lfn_buffer) else convert_8_3_name(allocator, entry.name),
                        .size = entry.size,
                        .type = if (entry.attributes.directory) .directory else .file,
                        .created = convert_time(entry.ctime_ymd, entry.ctime_hms, entry.ctime_hundredths),
                        .modified = convert_time(entry.mtime_ymd, entry.mtime_hms, 0),
                    });
                    lfn_pending = false;
                },

                .long => |entry| {
                    // tools.struct_dump(LongFilenameDirEntry, log.debug, entry);
                    var index: usize = (entry.ordinal.ordinal - 1) * LFN_WORDS_PER_ENTRY;
                    append_lfn(lfn_buffer, &index, entry);
                    lfn_pending = true;
                },
            }
        }

        return try list.toOwnedSlice();
    }
};

fn convert_time(ymd: YearMinuteDay, hms: HourMinuteSecond, ms: u8) time.DateTime {
    const hundredths = ms % 100;
    const seconds = (@as(usize, hms.second) * 2) + ms / 100;

    return .{
        .year = @as(i32, ymd.year) + 1980,
        .month = @intCast(ymd.month),
        .day = @intCast(ymd.day),
        .hour = @intCast(hms.hour),
        .minute = @intCast(hms.minute),
        .second = @intCast(seconds),
        .millisecond = @intCast(hundredths * 10),
    };
}

fn convert_8_3_name(allocator: std.mem.Allocator, raw_name: [11]u8) ![]u8 {
    var buffer: [12]u8 = undefined;

    var index: usize = 0;
    var has_dot = false;
    for (raw_name, 0..) |c, i| {
        if (c == ' ') continue;

        if (i >= 8 and !has_dot) {
            has_dot = true;
            buffer[index] = '.';
            index += 1;
        }

        buffer[index] = c;
        index += 1;
    }

    return allocator.dupe(u8, buffer[0..index]);
}

fn append_lfn(lfn_buffer: []u16, index: *usize, entry: *const LongFilenameDirEntry) void {
    if (append_lfn_part(lfn_buffer, index, entry.name_1[0..5])) return;
    if (append_lfn_part(lfn_buffer, index, entry.name_2[0..6])) return;
    if (append_lfn_part(lfn_buffer, index, entry.name_3[0..2])) return;
}

fn append_lfn_part(lfn_buffer: []u16, index: *usize, words: []align(1) const u16) bool {
    for (words) |w| {
        lfn_buffer[index.*] = w;
        index.* += 1;
        if (w == 0 or w == 0xffff) return true;
    }

    return false;
}

fn parse_lfn(allocator: std.mem.Allocator, buffer: []const u16) ![]u8 {
    var len = buffer.len;
    for (buffer, 0..) |w, i| {
        if (w == 0) {
            len = i;
            break;
        }
    }

    // const buf_ptr8: [*]const u8 = @ptrCast(buffer);
    // tools.hex_dump(log.debug, buf_ptr8[0 .. len * 2]);

    return std.unicode.utf16LeToUtf8Alloc(allocator, buffer[0..len]);
}

const DirEntryIterator = struct {
    buffer: []u8,
    dev: *const block_device.BlockDevice,
    lba: u28,
    read_lba: u28,
    sector_size: usize,
    index: usize,
    // TODO limit to root_directory_entries?

    pub fn init(buffer: []u8, dev: *const block_device.BlockDevice, lba: u28, sector_size: usize) DirEntryIterator {
        return .{
            .buffer = buffer,
            .dev = dev,
            .lba = lba,
            .read_lba = 0,
            .sector_size = sector_size,
            .index = 0,
        };
    }

    pub fn next(self: *DirEntryIterator) ?DirEntry {
        // are we out of bounds?
        if (self.index >= self.sector_size) {
            self.lba += 1;
            self.index = 0;
        }

        // read next sector if we need it
        if (self.read_lba != self.lba) {
            if (!self.dev.read(self.lba, 1, self.buffer)) return null;

            // log.debug("sector {d}:", .{self.lba});
            // tools.hex_dump(log.debug, self.buffer);

            self.read_lba = self.lba;
        }

        // read entry
        const raw = self.buffer[self.index .. self.index + @sizeOf(NormalDirEntry)];
        self.index += @sizeOf(NormalDirEntry);

        // are we done?
        if (raw[0] == FAT_END_OF_DIRECTORY) return null;

        // do we have a lfn?
        if (raw[@offsetOf(NormalDirEntry, "attributes")] == ATTR_LONG_NAME)
            return .{ .long = @alignCast(@ptrCast(raw)) };

        return .{ .normal = @alignCast(@ptrCast(raw)) };
    }
};
