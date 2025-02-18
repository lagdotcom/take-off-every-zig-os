const std = @import("std");
const log = std.log.scoped(.kalloc);

const kernel = @import("kernel.zig");

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

// TODO make this conform with std.mem.Allocator
pub const KernelAllocator = struct {
    first: *Entry,

    pub fn init(blocks: []const kernel.MemoryBlock) KernelAllocator {
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

    pub fn alloc(self: *KernelAllocator, comptime T: type, n: usize) ![]T {
        const required_bytes = @sizeOf(T) * n;

        var entry: ?*Entry = self.first;
        while (entry != null) {
            var e = entry.?;

            if (e.free and e.size >= required_bytes) {
                log.debug("allocated {d} bytes at {x}", .{ required_bytes, e.addr });

                e.free = false;
                e.reserved = required_bytes;

                const remaining_bytes_in_block = e.size - required_bytes;
                if (remaining_bytes_in_block >= minimum_block_size) {
                    const taken_size = @max(minimum_block_size, required_bytes);
                    const new_block_size = e.size - taken_size;
                    e.size = taken_size;

                    log.debug("splitting block: {d}/{d}", .{ taken_size, new_block_size });

                    const new_entry = write_entry(e.addr + taken_size, new_block_size, e);
                    new_entry.next = e.next;
                    e.next = new_entry;
                }

                const ptr: [*]T = @ptrFromInt(e.addr);
                // TODO are you meant to zero this?
                return ptr[0..n];
            }

            entry = e.next;
        }

        return error.OutOfMemory;
    }

    pub fn free(_: *KernelAllocator, memory: anytype) !void {
        var entry: *Entry = @ptrFromInt(@intFromPtr(memory.ptr) - szEntry);

        if (entry.magic != entry_magic_number) return error.NotAllocatedHere;

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

        // TODO join with previous block?
    }

    pub fn debug(self: *KernelAllocator) void {
        var entry: ?*Entry = self.first;

        while (entry) |e| {
            log.debug("{s}@{x} size={d} reserved={d}", .{ if (e.free) "FREE" else "USED", e.addr, e.size, e.reserved });

            entry = e.next;
        }
    }
};

test "allocation" {
    var ta = std.testing.allocator;

    const blk1 = try ta.alloc(u8, 128);
    const blk2 = try ta.alloc(u8, 1024);

    var a = KernelAllocator.init(&.{
        .{ .addr = @intFromPtr(blk1.ptr), .size = blk1.len },
        .{ .addr = @intFromPtr(blk2.ptr), .size = blk2.len },
    });

    const alloc1 = try a.alloc(u8, 200);
    try std.testing.expect(alloc1.ptr == blk2.ptr + szEntry);

    const alloc2 = try a.alloc(u8, 8);
    try std.testing.expect(alloc2.ptr == blk1.ptr + szEntry);

    try a.free(alloc2);

    const alloc3 = try a.alloc(u8, 16);
    try std.testing.expect(alloc2.ptr == alloc3.ptr);

    const alloc_fail = a.alloc(u8, 10000);
    try std.testing.expectError(error.OutOfMemory, alloc_fail);

    try a.free(alloc1);
    try a.free(alloc2);
    try a.free(alloc3);

    ta.free(blk1);
    ta.free(blk2);
}

test "block splitting and joining" {
    var ta = std.testing.allocator;

    const blk = try ta.alloc(u8, 10240);
    var a = KernelAllocator.init(&.{.{ .addr = @intFromPtr(blk.ptr), .size = blk.len }});
    const original_size = a.first.size;

    const alloc1 = try a.alloc(u8, 100);
    try std.testing.expect(a.first.size < blk.len);

    const alloc2 = try a.alloc(u8, 100);
    try std.testing.expect(a.first.next.?.addr == @intFromPtr(alloc2.ptr));

    try a.free(alloc2);
    try std.testing.expect(a.first.next.?.next == null);

    try a.free(alloc1);
    try std.testing.expect(a.first.size == original_size);

    ta.free(blk);
}
