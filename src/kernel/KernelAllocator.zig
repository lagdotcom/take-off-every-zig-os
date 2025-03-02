const std = @import("std");
const log = std.log.scoped(.kalloc);

pub const MemoryBlock = struct { addr: usize, size: usize };

const entry_magic_number: u32 = 0xfeed2dad;

const Entry = struct {
    magic: u32,
    free: bool,
    addr: usize,
    size: usize,
    reserved: usize,
    prev: ?*Entry,
    next: ?*Entry,
};

const szEntry = @sizeOf(Entry);

const minimum_block_size = 1024;
fn round_up_to_block_size(value: usize) usize {
    const required_blocks = std.math.divCeil(usize, value, minimum_block_size) catch unreachable;
    return required_blocks * minimum_block_size;
}

pub const UsageReport = struct {
    free: usize,
    reserved: usize,
    used: usize,
};

pub const KernelAllocator = struct {
    first: *Entry,

    pub fn init(blocks: []const MemoryBlock) KernelAllocator {
        var first: ?*Entry = null;
        var prev: ?*Entry = null;
        for (blocks) |*blk| {
            // this causes NULL pointer issues
            if (blk.addr == 0) continue;

            const entry = write_entry(blk.addr, blk.size, prev);

            if (prev) |p| p.next = entry;
            if (first == null) first = entry;

            prev = entry;
        }

        return KernelAllocator{ .first = first.? };
    }

    pub fn allocator(self: *KernelAllocator) std.mem.Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    fn write_entry(addr: usize, size: usize, prev: ?*Entry) *Entry {
        if (prev) |p| {
            log.debug("write_entry({x}, {d}, @{x})", .{ addr, size, p.addr });
        } else {
            log.debug("write_entry({x}, {d}, null)", .{ addr, size });
        }

        var entry: *Entry = @ptrFromInt(addr);
        entry.magic = entry_magic_number;
        entry.free = true;
        entry.addr = addr + szEntry;
        entry.size = size - szEntry;
        entry.reserved = 0;
        entry.prev = prev;
        entry.next = null;

        return entry;
    }

    pub fn alloc(ctx: *anyopaque, n: usize, log2_ptr_align: u8, return_address: usize) ?[*]u8 {
        _ = return_address;

        const self: *KernelAllocator = @ptrCast(@alignCast(ctx));
        const ptr_align = @as(usize, 1) << @as(std.mem.Allocator.Log2Align, @intCast(log2_ptr_align));
        const required_bytes = n + ptr_align - 1 + @sizeOf(Entry);
        log.debug("trying to alloc {d} bytes, align {d}: requires {d}", .{ n, ptr_align, required_bytes });

        var entry: ?*Entry = self.first;
        while (entry != null) {
            var e = entry.?;

            if (e.free and e.size >= required_bytes) {
                log.debug("allocated {d} bytes at {x}", .{ required_bytes, e.addr });

                e.free = false;
                e.reserved = required_bytes;

                const remaining_bytes_in_block = e.size - required_bytes;
                if (remaining_bytes_in_block >= minimum_block_size) {
                    const taken_size = round_up_to_block_size(required_bytes);
                    const new_block_size = e.size - taken_size;
                    e.size = taken_size;

                    log.debug("splitting block: {d}/{d}", .{ taken_size, new_block_size });

                    const new_entry = write_entry(e.addr + taken_size, new_block_size, e);
                    new_entry.next = e.next;
                    e.next = new_entry;
                }

                return @ptrFromInt(e.addr);
            }

            entry = e.next;
        }

        return null;
    }

    fn get_entry(buf: anytype) *Entry {
        const entry: *Entry = @ptrFromInt(@intFromPtr(buf.ptr) - szEntry);
        std.debug.assert(entry.magic == entry_magic_number);

        return entry;
    }

    fn resize(
        ctx: *anyopaque,
        buf: []u8,
        log2_buf_align: u8,
        new_size: usize,
        return_address: usize,
    ) bool {
        _ = ctx;
        _ = log2_buf_align;
        _ = return_address;

        var entry = get_entry(buf);
        if (entry.size >= new_size) {
            entry.size = new_size;
            return true;
        }

        return false;
    }

    fn free(
        ctx: *anyopaque,
        buf: []u8,
        log2_buf_align: u8,
        return_address: usize,
    ) void {
        _ = ctx;
        _ = log2_buf_align;
        _ = return_address;

        // const self: *KernelAllocator = @ptrCast(@alignCast(ctx));
        var entry = get_entry(buf);

        if (entry.free) {
            log.debug("tried to free already free block at {x}", .{entry.addr});
            return;
        }

        log.debug("freed {d} bytes at {x}", .{ entry.addr, entry.reserved });
        entry.free = true;
        entry.reserved = 0;

        if (entry.next) |n| {
            if (n.free) {
                log.debug("joining with next block: gained {d} bytes", .{n.size});
                entry.size += n.size + szEntry;
                entry.next = n.next;
            }
        }

        if (entry.prev) |p| {
            if (p.free) {
                log.debug("joining with previous block", .{});
                p.size += entry.size + szEntry;
                p.next = entry.next;
            }
        }

        // TODO full compact after certain amounts of frees/allocations?
    }

    pub fn debug(self: *KernelAllocator) void {
        var entry: ?*Entry = self.first;

        while (entry) |e| {
            log.debug("{s}@{x} size={d} reserved={d}", .{ if (e.free) "FREE" else "USED", e.addr, e.size, e.reserved });

            entry = e.next;
        }
    }

    pub fn report(self: *KernelAllocator) UsageReport {
        var entry: ?*Entry = self.first;
        var free_mem: usize = 0;
        var used_mem: usize = 0;
        var reserved_mem: usize = 0;

        while (entry) |e| {
            if (e.free) {
                free_mem += e.size;
            } else {
                used_mem += e.size;
                reserved_mem += e.reserved;
            }

            entry = e.next;
        }

        return .{ .free = free_mem, .used = used_mem, .reserved = reserved_mem };
    }
};

test "allocation" {
    var ta = std.testing.allocator;

    const blk1 = try ta.alloc(u8, 128);
    const blk2 = try ta.alloc(u8, 1024);

    var kalloc = KernelAllocator.init(&.{
        .{ .addr = @intFromPtr(blk1.ptr), .size = blk1.len },
        .{ .addr = @intFromPtr(blk2.ptr), .size = blk2.len },
    });
    var a = kalloc.allocator();

    const alloc1 = try a.alloc(u8, 200);
    try std.testing.expect(alloc1.ptr == blk2.ptr + szEntry);

    const alloc2 = try a.alloc(u8, 8);
    try std.testing.expect(alloc2.ptr == blk1.ptr + szEntry);

    a.free(alloc2);

    const alloc3 = try a.alloc(u8, 16);
    try std.testing.expect(alloc2.ptr == alloc3.ptr);

    const alloc_fail = a.alloc(u8, 10000);
    try std.testing.expectError(std.mem.Allocator.Error.OutOfMemory, alloc_fail);

    a.free(alloc1);
    a.free(alloc2);
    a.free(alloc3);

    ta.free(blk1);
    ta.free(blk2);
}

test "block splitting and joining" {
    var ta = std.testing.allocator;

    const blk = try ta.alloc(u8, 10240);
    var kalloc = KernelAllocator.init(&.{.{ .addr = @intFromPtr(blk.ptr), .size = blk.len }});
    var a = kalloc.allocator();
    const original_size = kalloc.first.size;

    // check join right
    const alloc1 = try a.alloc(u8, 100);
    try std.testing.expect(kalloc.first.size < blk.len);

    const alloc2 = try a.alloc(u8, 100);
    try std.testing.expect(kalloc.first.next.?.addr == @intFromPtr(alloc2.ptr));

    a.free(alloc2);
    try std.testing.expect(kalloc.first.next.?.next == null);

    a.free(alloc1);
    try std.testing.expect(kalloc.first.size == original_size);

    // check join left
    const alloc3 = try a.alloc(u8, 100);
    const alloc4 = try a.alloc(u8, 100);

    a.free(alloc3);
    a.free(alloc4);
    try std.testing.expect(kalloc.first.size == original_size);

    ta.free(blk);
}

test "round up to block size" {
    try std.testing.expect(round_up_to_block_size(1) == minimum_block_size);
    try std.testing.expect(round_up_to_block_size(minimum_block_size) == minimum_block_size);
    try std.testing.expect(round_up_to_block_size(minimum_block_size + 1) == minimum_block_size * 2);
    try std.testing.expect(round_up_to_block_size(minimum_block_size * 5) == minimum_block_size * 5);
}
