const std = @import("std");
const log = std.log.scoped(.viz);

const mouse = @import("mouse.zig");
const video = @import("video.zig");

const WindowID = u32;

const Rectangle = struct {
    x: usize,
    y: usize,
    w: usize,
    h: usize,
};

const Window = struct {
    id: WindowID,
    name: []const u8,
    size: Rectangle,
    minimum_size: Rectangle,
    maximum_size: Rectangle,
};

var windows: std.ArrayList(Window) = undefined;
var next_window_id: WindowID = undefined;
var framebuffer: []u32 = undefined;
var surface: *video.VideoInfo = undefined;

pub fn enter(allocator: std.mem.Allocator) !void {
    framebuffer = try allocator.alloc(u32, video.vga.framebuffer_size);
    defer allocator.free(framebuffer);
    surface = try allocator.create(video.VideoInfo);
    defer allocator.destroy(surface);

    surface.framebuffer = framebuffer.ptr;
    surface.framebuffer_addr = @intFromPtr(framebuffer.ptr);
    surface.framebuffer_size = video.vga.framebuffer_size;
    surface.format = video.vga.format;
    surface.horizontal = video.vga.horizontal;
    surface.vertical = video.vga.vertical;
    surface.pixels_per_scan_line = video.vga.pixels_per_scan_line;

    windows = std.ArrayList(Window).init(allocator);
    next_window_id = 1;

    const bg_colour = surface.rgb(10, 20, 30);
    const cursor_colour = surface.rgb(255, 255, 255);

    while (true) {
        @memset(framebuffer, bg_colour);

        draw_mouse_cursor(cursor_colour, 8);

        video.vga.swap(framebuffer);
    }
}

pub fn new_window(win: *Window) !void {
    try windows.append(win);
    win.id = next_window_id;
    next_window_id += 1;
}

fn draw_mouse_cursor(colour: u32, size: usize) void {
    for (0..size) |i| {
        surface.plot_xy(mouse.state.x + i, mouse.state.y + i, colour);
        surface.plot_xy(mouse.state.x, mouse.state.y + i, colour);
        surface.plot_xy(mouse.state.x + i, mouse.state.y, colour);
    }
}
