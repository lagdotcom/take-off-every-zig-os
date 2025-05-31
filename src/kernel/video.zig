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

    pub fn get_index(self: VideoInfo, x: usize, y: usize) usize {
        return self.pixels_per_scan_line * y + x;
    }

    pub fn plot(self: VideoInfo, index: usize, colour: u32) void {
        self.framebuffer[index] = colour;
    }

    pub fn plot_xy(self: VideoInfo, x: usize, y: usize, colour: u32) void {
        if (x >= self.horizontal) return;
        if (y >= self.vertical) return;
        self.framebuffer[self.get_index(x, y)] = colour;
    }

    pub fn clip_rectangle(self: VideoInfo, x: usize, y: usize, width: *usize, height: *usize) void {
        if (x >= self.horizontal or y >= self.vertical) {
            width.* = 0;
            height.* = 0;
            return;
        }

        const end_x = x + width.*;
        const end_y = y + height.*;
        width.* = @min(self.horizontal, end_x) - x;
        height.* = @min(self.vertical, end_y) - y;
    }

    pub fn fill_rectangle(self: VideoInfo, x: usize, y: usize, width: usize, height: usize, colour: u32) void {
        var index = self.get_index(x, y);

        for (0..height) |_| {
            @memset(self.framebuffer[index .. index + width], colour);
            index += self.pixels_per_scan_line;
        }
    }

    pub fn fill_clipped_rectangle(self: VideoInfo, x: usize, y: usize, width: usize, height: usize, colour: u32) void {
        var clipped_width = width;
        var clipped_height = height;
        self.clip_rectangle(x, y, &clipped_width, &clipped_height);
        self.fill_rectangle(x, y, clipped_width, clipped_height, colour);
    }

    pub fn fill(self: VideoInfo, colour: u32) void {
        @memset(self.framebuffer[0..self.framebuffer_size], colour);
    }

    pub fn copy_from(self: VideoInfo, buffer: []u32) void {
        @memcpy(self.framebuffer, buffer);
    }

    pub fn rgb(self: VideoInfo, r: u8, g: u8, b: u8) u32 {
        const r32: u32 = @intCast(r);
        const g32: u32 = @intCast(g);
        const b32: u32 = @intCast(b);

        return switch (self.format) {
            .RedGreenBlueReserved8BitPerColor => (r32) | (g32 << 8) | (b32 << 16) | (0xff000000),
            .BlueGreenRedReserved8BitPerColor => (b32) | (g32 << 8) | (r32 << 16) | (0xff000000),

            else => std.debug.panic("unknown pixel format: {s}", .{@tagName(self.format)}),
        };
    }
};

pub var vga: *const VideoInfo = undefined;

pub fn initialize(vi: *const VideoInfo) void {
    log.debug("initializing", .{});
    defer log.debug("done", .{});

    vga = vi;
}
