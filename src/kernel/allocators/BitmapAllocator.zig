const std = @import("std");
const log = std.log.scoped(.bitmap_alloc);

const shell = @import("../shell.zig");
const types = @import("types.zig");
const x86 = @import("../../arch/x86.zig");

const Block = struct {
    next: ?*Block,
    size: usize,
    used: usize,
    block_size: usize,
    lfb: usize,

    fn get_block_count(self: *const Block) usize {
        return self.size / self.block_size;
    }

    fn get_bitmap_pointer(self: *const Block) [*]u8 {
        return @ptrFromInt(@intFromPtr(self) + @sizeOf(Block));
    }

    fn get_bitmap_size(self: *const Block) usize {
        const block_count = self.get_block_count();
        return if ((block_count / self.block_size) * self.block_size < block_count) block_count / self.block_size + 1 else block_count / self.block_size;
    }
};

const BitmapAllocator = @This();

first_block: ?*Block,

pub fn init(blocks: []const types.MemoryBlock) BitmapAllocator {
    var h = BitmapAllocator{ .first_block = null };

    for (blocks) |*block| {
        // this causes NULL pointer issues
        if (block.addr == 0) continue;

        h.add_block(block, 16);
    }

    return h;
}

pub fn add_block(self: *BitmapAllocator, block: *const types.MemoryBlock, bsize: usize) void {
    const status = x86.pause_interrupts();
    defer x86.resume_interrupts(status);

    var b: *Block = @ptrFromInt(block.addr);
    b.size = block.size - @sizeOf(Block);
    b.block_size = bsize;

    b.next = self.first_block;
    self.first_block = b;

    var block_count = b.get_block_count();
    var bm = b.get_bitmap_pointer();

    // clear bitmap
    @memset(bm[0..block_count], 0);

    // reserve room for bitmap
    block_count = b.get_bitmap_size();
    @memset(bm[0..block_count], 5);

    b.lfb = block_count - 1;
    b.used = block_count;
}

fn get_new_block_id(a: u8, b: u8) u8 {
    var c: u8 = a + 1;
    while (c == b or c == 0) c += 1;
    return c;
}

pub fn alloc(self: *BitmapAllocator, size: usize) ?[*]u8 {
    const status = x86.pause_interrupts();
    defer x86.resume_interrupts(status);

    // log.debug("trying to alloc {d} bytes", .{size});

    var block = self.first_block;
    while (block) |b| {
        // check if block has enough room
        if (b.size - (b.used * b.block_size) >= size) {
            const block_count = b.get_block_count();
            const blocks_needed = if ((size / b.block_size) * b.block_size < size) size / b.block_size + 1 else size / b.block_size;
            var bm = b.get_bitmap_pointer();

            var x = if (b.lfb + 1 >= block_count) 0 else b.lfb + 1;

            while (x != b.lfb) {
                // just wrap around
                if (x >= block_count) x = 0;

                if (bm[x] == 0) {
                    // count free blocks
                    var y: usize = 0;
                    while (bm[x + y] == 0 and y < blocks_needed and (x + y) < block_count) y += 1;

                    // we have enough, allocate
                    if (y == blocks_needed) {
                        // find new id
                        const nid = get_new_block_id(bm[x - 1], bm[x + y]);

                        // allocate
                        @memset(bm[x .. x + y], nid);

                        // optimization for future allocations
                        b.lfb = (x + blocks_needed) - 2;

                        // count used blocks, not bytes
                        b.used += y;

                        const address = x * b.block_size + @intFromPtr(bm);
                        log.debug("allocated {d} bytes at {x}", .{ size, address });
                        return @ptrFromInt(address);
                    }

                    // skip over too-small span
                    x += y;
                    continue;
                }

                x += 1;
            }
        }

        block = b.next;
    }

    log.warn("failed to alloc {d} bytes", .{size});
    return null;
}

pub fn free(self: *BitmapAllocator, ptr: [*]u8) void {
    const status = x86.pause_interrupts();
    defer x86.resume_interrupts(status);

    const ptr_int = @intFromPtr(ptr);

    var block = self.first_block;
    while (block) |b| {
        const b_int = @intFromPtr(b);
        const after_b = b_int + @sizeOf(Block);
        if (ptr_int > b_int and ptr_int < after_b + b.size) {
            // found block
            const offset = ptr_int - after_b;

            // block offset
            const bi = offset / b.block_size;
            var bm = b.get_bitmap_pointer();

            // clear allocation
            const id = bm[bi];
            const max = b.get_block_count();
            var x = bi;
            while (bm[x] == id and x < max) {
                bm[x] = 0;
                x += 1;
            }

            // update free block count
            b.used -= x - bi;
            return;
        }

        block = b.next;
    }

    // TODO raise error?
    log.warn("failed to free mem @{x}", .{@intFromPtr(ptr)});
}

pub fn allocator(self: *BitmapAllocator) std.mem.Allocator {
    return .{
        .ptr = self,
        .vtable = &.{
            .alloc = api_alloc,
            .resize = api_resize,
            .free = api_free,
        },
    };
}

fn api_alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
    const self: *BitmapAllocator = @alignCast(@ptrCast(ctx));

    // TODO
    _ = ptr_align;
    _ = ret_addr;

    return self.alloc(len);
}

fn api_resize(_: *anyopaque, _: []u8, _: u8, _: usize, _: usize) bool {
    // TODO
    return false;
}

fn api_free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
    const self: *BitmapAllocator = @alignCast(@ptrCast(ctx));

    // TODO
    _ = buf_align;
    _ = ret_addr;

    return self.free(buf.ptr);
}

pub fn report(self: *const BitmapAllocator) types.UsageReport {
    var block = self.first_block;
    var free_mem: usize = 0;
    var used_mem: usize = 0;
    var reserved_mem: usize = 0;

    while (block) |b| {
        const block_count = b.get_block_count();
        const reserved = b.get_bitmap_size();

        used_mem += (b.used - reserved) * b.block_size;
        free_mem += (block_count - b.used) * b.block_size;
        reserved_mem += reserved * b.block_size;

        block = b.next;
    }

    return .{ .free = free_mem, .used = used_mem, .reserved = reserved_mem };
}

pub fn report_table(self: *const BitmapAllocator, t: *shell.Table) !void {
    try t.add_heading(.{ .name = "Offset", .justify = .right });
    try t.add_heading(.{ .name = "Size" });
    try t.add_heading(.{ .name = "Block Size" });
    try t.add_heading(.{ .name = "Used" });
    try t.add_heading(.{ .name = "Reserved" });

    var block = self.first_block;
    while (block) |b| {
        const reserved = b.get_bitmap_size();

        try t.add_number(@intFromPtr(b), 16);
        try t.add_size(b.size);
        try t.add_size(b.block_size);
        try t.add_size((b.used - reserved) * b.block_size);
        try t.add_size(reserved * b.block_size);
        try t.end_row();

        block = b.next;
    }
    t.print();
}
