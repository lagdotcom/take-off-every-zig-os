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

const szE = @sizeOf(Entry);

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
            log.debug("write_entry({x}, {x}, @{x})", .{ addr, size, p.addr });
        } else {
            log.debug("write_entry({x}, {x}, null)", .{ addr, size });
        }

        var entry: *Entry = @ptrFromInt(addr);
        entry.magic = entry_magic_number;
        entry.free = true;
        entry.addr = addr + szE;
        entry.size = size - szE;
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
                log.debug("allocated {d} bytes at {x}", .{ e.addr, required_bytes });

                e.free = false;
                e.reserved = required_bytes;

                const remaining_bytes_in_block = e.size - e.reserved;
                if (remaining_bytes_in_block >= minimum_block_size) {
                    // TODO split block
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
        var entry: *Entry = @ptrFromInt(@intFromPtr(memory.ptr) - szE);

        if (entry.magic != entry_magic_number) return error.NotAllocatedHere;

        if (entry.free) {
            log.debug("tried to free already free block at {x}", .{entry.addr});
            return;
        }

        log.debug("freed {d} bytes at {x}", .{ entry.addr, entry.reserved });
        entry.free = true;
        entry.reserved = 0;

        // TODO join adjacent blocks
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
    try std.testing.expect(alloc1.ptr == blk2.ptr + szE);

    const alloc2 = try a.alloc(u8, 8);
    try std.testing.expect(alloc2.ptr == blk1.ptr + szE);

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
