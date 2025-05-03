const std = @import("std");
const log = std.log.scoped(.cpuid_cache_tlb);

const x86 = @import("../../arch/x86.zig");

pub const TLB = struct {
    type: enum(u1) { instruction, data },
    entries: u8,
    page_size: []const u8,
    associativity: u8,
};

pub const Cache = struct {
    level: u2,
    type: enum(u2) { instruction, data, unified },
    size: u32,
    associativity: u8,
    line_size: u32,
    sector_size: u32 = 0,
};

const KnownType = struct {
    value: u8,
    entry: union(enum) { tlb: TLB, cache: Cache },
};

const K = 1024;
const M = 1024 * 1024;

const known_cache_types: []const KnownType = &.{
    .{ .value = 0x01, .entry = .{ .tlb = .{ .type = .instruction, .entries = 32, .page_size = "4Kp", .associativity = 4 } } },
    .{ .value = 0x02, .entry = .{ .tlb = .{ .type = .instruction, .entries = 2, .page_size = "4Mp", .associativity = 0 } } },
    .{ .value = 0x03, .entry = .{ .tlb = .{ .type = .data, .entries = 64, .page_size = "4Kp", .associativity = 4 } } },
    .{ .value = 0x2c, .entry = .{ .cache = .{ .level = 1, .type = .data, .size = 32 * K, .associativity = 8, .line_size = 64 } } },
    .{ .value = 0x30, .entry = .{ .cache = .{ .level = 1, .type = .instruction, .size = 32 * K, .associativity = 8, .line_size = 64 } } },
    .{ .value = 0x4d, .entry = .{ .cache = .{ .level = 3, .type = .unified, .size = 16 * M, .associativity = 16, .line_size = 64 } } },
    .{ .value = 0x7d, .entry = .{ .cache = .{ .level = 2, .type = .unified, .size = 2 * M, .associativity = 8, .line_size = 64 } } },
};

pub const Info = struct {
    tlb: []TLB,
    cache: []Cache,
    no_l3_cache: bool,
    prefetch_64: bool,
    prefetch_128: bool,
    use_leaf_4: bool,
    use_leaf_18: bool,
};

const Enumerator = struct {
    allocator: std.mem.Allocator,
    tlb: std.ArrayList(TLB),
    cache: std.ArrayList(Cache),
    no_l3_cache: bool,
    prefetch_64: bool,
    prefetch_128: bool,
    use_leaf_4: bool,
    use_leaf_18: bool,

    pub fn init(allocator: std.mem.Allocator) Enumerator {
        return .{
            .allocator = allocator,
            .tlb = std.ArrayList(TLB).init(allocator),
            .cache = std.ArrayList(Cache).init(allocator),
            .no_l3_cache = false,
            .prefetch_128 = false,
            .prefetch_64 = false,
            .use_leaf_18 = false,
            .use_leaf_4 = false,
        };
    }

    pub fn process(self: *Enumerator, res: x86.CPUIDResults) !Info {
        if (res.a & 0x80000000 == 0) {
            try self.add_entry(@intCast((res.a & 0xff00) >> 8));
            try self.add_entry(@intCast((res.a & 0xff0000) >> 16));
            try self.add_entry(@intCast((res.a & 0xff000000) >> 24));
        }
        if (res.b & 0x80000000 == 0) {
            try self.add_entry(@intCast(res.b & 0xff));
            try self.add_entry(@intCast((res.b & 0xff00) >> 8));
            try self.add_entry(@intCast((res.b & 0xff0000) >> 16));
            try self.add_entry(@intCast((res.b & 0xff000000) >> 24));
        }
        if (res.c & 0x80000000 == 0) {
            try self.add_entry(@intCast(res.c & 0xff));
            try self.add_entry(@intCast((res.c & 0xff00) >> 8));
            try self.add_entry(@intCast((res.c & 0xff0000) >> 16));
            try self.add_entry(@intCast((res.c & 0xff000000) >> 24));
        }
        if (res.d & 0x80000000 == 0) {
            try self.add_entry(@intCast(res.d & 0xff));
            try self.add_entry(@intCast((res.d & 0xff00) >> 8));
            try self.add_entry(@intCast((res.d & 0xff0000) >> 16));
            try self.add_entry(@intCast((res.d & 0xff000000) >> 24));
        }

        return .{
            .tlb = try self.tlb.toOwnedSlice(),
            .cache = try self.cache.toOwnedSlice(),
            .no_l3_cache = self.no_l3_cache,
            .prefetch_64 = self.prefetch_64,
            .prefetch_128 = self.prefetch_128,
            .use_leaf_4 = self.use_leaf_4,
            .use_leaf_18 = self.use_leaf_18,
        };
    }

    fn add_entry(self: *Enumerator, value: u8) !void {
        switch (value) {
            0 => return,
            0x40 => self.no_l3_cache = true,
            0xf0 => self.prefetch_64 = true,
            0xf1 => self.prefetch_128 = true,
            0xfe => self.use_leaf_18 = true,
            0xff => self.use_leaf_4 = true,
            else => {
                for (known_cache_types) |kt| {
                    if (kt.value == value) {
                        switch (kt.entry) {
                            .tlb => |tlb| try self.tlb.append(tlb),
                            .cache => |cache| try self.cache.append(cache),
                        }
                        return;
                    }
                }

                log.warn("unknown descriptor: {x}", .{value});
            },
        }
    }
};

pub fn get_info(allocator: std.mem.Allocator, res: x86.CPUIDResults) !Info {
    var e = Enumerator.init(allocator);
    return try e.process(res);
}
