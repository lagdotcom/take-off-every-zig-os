const std = @import("std");
const fat = @import("kernel/driver/fs/fat.zig");

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const stdout = std.io.getStdOut().writer();

    // sanity checks
    if (@sizeOf(fat.EBPB12_16) != (512 - 36)) std.debug.panic("@sizeof(EBPB12_16) = {d}, should be {d}", .{ @sizeOf(fat.EBPB12_16), 512 - 36 });
    if (@sizeOf(fat.EBPB32) != (512 - 36)) std.debug.panic("@sizeof(EBPB32) = {d}, should be {d}", .{ @sizeOf(fat.EBPB32), 512 - 36 });
    if (@sizeOf(fat.BPB) != 36) std.debug.panic("@sizeOf(BPB) = {d}, should be 36", .{@sizeOf(fat.BPB)});
    if (@sizeOf(fat.NormalDirEntry) != 32) std.debug.panic("@sizeOf(NormalDirEntry) = {d}, should be 32", .{@sizeOf(fat.NormalDirEntry)});

    var file = try std.fs.cwd().openFile("zig-out/bin/disk.bin", .{ .mode = .read_only });
    defer file.close();

    const raw = try file.readToEndAlloc(allocator, 0x168000);
    defer allocator.free(raw);

    const header = fat.get_fat_header(raw);
    const bpb = header.bpb;
    const ebpb = header.ebpb.fat12_16;
    const total_size = bytes_to_kb(@as(u32, bpb.bytes_per_sector) * bpb.sector_count);

    try stdout.print("OEM=\"{s}\" volume=\"{s}\" ({x:8}) sys=\"{s}\" | {d} sectors, {d}b/sector, {d}kb total\n", .{ bpb.oem_identifier, ebpb.volume_label, ebpb.volume_id, ebpb.system_identifier, bpb.sector_count, bpb.bytes_per_sector, total_size });

    const total_sectors = bpb.sector_count;
    const fat_size = bpb.sectors_per_fat;
    const root_dir_sectors = (((@as(u32, bpb.root_directory_entries) * @sizeOf(fat.NormalDirEntry)) + bpb.bytes_per_sector - 1) / bpb.bytes_per_sector);
    const first_data_sector = bpb.reserved_sectors + (bpb.fat_count * fat_size) + root_dir_sectors;
    const first_fat_sector = bpb.reserved_sectors;
    const data_sectors = total_sectors - @as(u32, bpb.reserved_sectors) + (bpb.fat_count * fat_size) + root_dir_sectors;
    const total_clusters = data_sectors / bpb.sectors_per_cluster;
    const first_root_dir_sector = first_data_sector - root_dir_sectors;
    const bytes_per_cluster = bpb.bytes_per_sector * bpb.sectors_per_cluster;
    const root_dir_offset = first_root_dir_sector * bpb.bytes_per_sector;

    try stdout.print("total_sectors={d} fat_size={d} root_dir_sectors={d} first_data_sector={d} first_fat_sector={d} data_sectors={d} total_clusters={d} first_root_dir_sector={d} bytes_per_cluster={d} type={s} root_dir_offset={x}\n", .{ total_sectors, fat_size, root_dir_sectors, first_data_sector, first_fat_sector, data_sectors, total_clusters, first_root_dir_sector, bytes_per_cluster, @tagName(bpb.media_descriptor_type), root_dir_offset });

    const file_name_buffer = try allocator.alloc(u8, 12);
    defer allocator.free(file_name_buffer);

    const root_entries = try read_dir(allocator, raw, root_dir_offset);
    defer allocator.free(root_entries);
    for (root_entries) |entry| {
        const ctime_hundredths = entry.ctime_hundredths % 100;
        const ctime_seconds = @as(u8, entry.ctime_hms.second) * 2 + @divFloor(entry.ctime_hundredths, 100);

        const start_cluster: u32 = entry.cluster_lo | (@as(u32, entry.cluster_hi) << 16);
        const first_sector_of_cluster = ((start_cluster - 2) * bpb.sectors_per_cluster) + first_data_sector;

        try stdout.print("Entry: \"{s}\" {s}{s}{s}{s}{s}{s} {d} bytes ({d}kb), cluster={d} sector={d} @{x} | \nCreated: {d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}.{d} | Modified: {d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2} | Accessed: {d:0>4}-{d:0>2}-{d:0>2}\n", .{
            entry.name,

            if (entry.attributes.read_only) "R" else "-",
            if (entry.attributes.hidden) "H" else "-",
            if (entry.attributes.system) "S" else "-",
            if (entry.attributes.volume_id) "V" else "-",
            if (entry.attributes.directory) "D" else "-",
            if (entry.attributes.archive) "A" else "-",

            entry.size,
            bytes_to_kb(entry.size),
            start_cluster,
            first_sector_of_cluster,
            first_sector_of_cluster * bpb.bytes_per_sector,

            1980 + @as(u16, entry.ctime_ymd.year),
            entry.ctime_ymd.month,
            entry.ctime_ymd.day,
            entry.ctime_hms.hour,
            entry.ctime_hms.minute,
            ctime_seconds,
            ctime_hundredths,

            1980 + @as(u16, entry.mtime_ymd.year),
            entry.mtime_ymd.month,
            entry.mtime_ymd.day,
            entry.mtime_hms.hour,
            entry.mtime_hms.minute,
            @as(u8, entry.mtime_hms.second) * 2,

            1980 + @as(u16, entry.atime_ymd.year),
            entry.atime_ymd.month,
            entry.atime_ymd.day,
        });

        const file_name = get_dos_filename(entry.name, file_name_buffer);

        var out_file = try std.fs.cwd().createFile(file_name, .{});
        errdefer out_file.close();

        try stdout.print("Cluster Ranges: {d}", .{start_cluster});
        var cluster = start_cluster;
        var previous_cluster = cluster;
        var elided: u32 = 0;
        var remaining_size: usize = entry.size;
        while (cluster < fat.fat12_cluster_types.bad) {
            // write current cluster
            const to_write = if (remaining_size > bytes_per_cluster) bytes_per_cluster else remaining_size;
            const sector_number = ((cluster - 2) * bpb.sectors_per_cluster) + first_data_sector;
            const cluster_offset = sector_number * bpb.bytes_per_sector;
            // std.log.debug("cluster {d} @{x}", .{ cluster, cluster_offset });
            remaining_size -= try out_file.write(raw[cluster_offset .. cluster_offset + to_write]);

            previous_cluster = cluster;
            cluster = get_fat_entry(raw, cluster, bpb);
            if (cluster == previous_cluster + 1) {
                if (elided == 0)
                    try stdout.print("..", .{});
                elided += 1;
            } else {
                if (elided > 1) try stdout.print("{d}", .{previous_cluster});
                elided = 0;

                if (cluster == fat.fat12_cluster_types.bad) {
                    try stdout.print("BAD", .{});
                } else if (cluster < fat.fat12_cluster_types.bad) {
                    try stdout.print(" {d}", .{cluster});
                }
            }
        }

        out_file.close();
        try stdout.print(" wrote to {s}\n", .{file_name});
    }
}

fn get_dos_filename(raw_name: [11]u8, buffer: []u8) []const u8 {
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

    return buffer[0..index];
}

fn bytes_to_kb(size: u32) f32 {
    return @divExact(@as(f32, @floatFromInt(size)), 1024);
}

fn get_dir_entry(raw: []u8, offset: usize) *fat.NormalDirEntry {
    // std.log.debug("get_dir_entry @{x}", .{offset});
    return @ptrCast(@alignCast(&raw[offset]));
}

fn get_fat_entry(raw: []u8, cluster: u32, bpb: *const fat.BPB) u16 {
    const first_fat_sector = bpb.reserved_sectors;
    const fat_offset: u32 = cluster + (cluster / 2);
    const fat_sector = first_fat_sector + (fat_offset / bpb.bytes_per_sector);
    const ent_offset = fat_offset % bpb.bytes_per_sector;

    const fat_table = raw[fat_sector * bpb.bytes_per_sector ..];
    const table_value: u16 = (@as(u16, fat_table[ent_offset + 1]) << 8) | fat_table[ent_offset];

    // std.log.debug("get_fat_entry @{x}+{d}, {x}", .{ fat_sector * bpb.bytes_per_sector, ent_offset, table_value });

    return if (cluster & 1 == 1) table_value >> 4 else table_value & 0xfff;
}

fn read_dir(allocator: std.mem.Allocator, raw: []u8, start_offset: usize) ![]fat.NormalDirEntry {
    var list = std.ArrayList(fat.NormalDirEntry).init(allocator);

    var offset = start_offset;
    while (true) {
        const entry = get_dir_entry(raw, offset);
        offset += @sizeOf(fat.NormalDirEntry);

        if (entry.name[0] == fat.FAT_DELETED) continue;
        if (entry.name[0] == fat.FAT_END_OF_DIRECTORY) break;

        // TODO
        // if (entry.attributes == fat.ATTR_LONG_NAME) ...

        try list.append(entry.*);
    }

    return list.toOwnedSlice();
}
