const std = @import("std");
const log = std.log.scoped(.video);

pub const VideoInfo = struct {
    framebuffer_addr: u64,
    framebuffer_size: usize,
    horizontal: usize,
    vertical: usize,
    pixels_per_scan_line: usize,
    framebuffer: [*]volatile u32,
    format: std.os.uefi.protocol.GraphicsOutput.PixelFormat,
};

pub var vga: *const VideoInfo = undefined;

pub fn initialize(vi: *const VideoInfo) void {
    log.debug("initializing", .{});
    defer log.debug("done", .{});

    vga = vi;
}

pub fn get_index(x: usize, y: usize) usize {
    return vga.pixels_per_scan_line * y + x;
}

pub fn plot(index: usize, colour: u32) void {
    vga.framebuffer[index] = colour;
}

pub fn fill_rectangle(x: usize, y: usize, width: usize, height: usize, colour: u32) void {
    var index = get_index(x, y);

    for (0..height) |_| {
        @memset(vga.framebuffer[index .. index + width], colour);
        index += vga.pixels_per_scan_line;
    }
}

pub fn fill(colour: u32) void {
    @memset(vga.framebuffer[0..vga.framebuffer_size], colour);
}

pub fn rgb(r: u32, g: u32, b: u32) u32 {
    const r32: u32 = @intCast(r);
    const g32: u32 = @intCast(g);
    const b32: u32 = @intCast(b);

    return switch (vga.format) {
        .RedGreenBlueReserved8BitPerColor => (r32) | (g32 << 8) | (b32 << 16) | (0xff000000),
        .BlueGreenRedReserved8BitPerColor => (b32) | (g32 << 8) | (r32 << 16) | (0xff000000),

        else => std.debug.panic("unknown pixel format: {s}", .{@tagName(vga.format)}),
    };
}
