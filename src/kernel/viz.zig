const std = @import("std");
const log = std.log.scoped(.viz);

const mouse = @import("mouse.zig");
const video = @import("video.zig");

const chrome_size = 4;
const header_size = 30;

const chrome = .{
    .top = header_size,
    .right = chrome_size,
    .bottom = chrome_size,
    .left = chrome_size,
    .horizontal = chrome_size + chrome_size,
    .vertical = header_size + chrome_size,
};

const WindowID = u32;
const Point = struct { x: usize, y: usize };
const Size = struct { width: usize, height: usize };

const Window = struct {
    id: WindowID,
    name: []const u8,
    position: Point,
    size: Size,
    minimum_size: Size = .{ .width = 0, .height = 0 },
    maximum_size: Size = .{ .width = std.math.maxInt(usize), .height = std.math.maxInt(usize) },

    pub fn deinit(self: *Window) void {
        for (windows.items, 0..) |match, i| {
            if (self.id == match.id) {
                windows.orderedRemove(i);
                self.id = 0;
                return;
            }
        }
    }
};

var windows: std.ArrayList(*Window) = undefined;
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

    windows = std.ArrayList(*Window).init(allocator);
    next_window_id = 1;

    const viz_bg = surface.rgb(10, 20, 30);
    const window_chrome = surface.rgb(60, 120, 180);
    const window_bg = surface.rgb(128, 128, 128);
    const cursor_fg = surface.rgb(255, 255, 255);

    var win_a = Window{
        .id = 0,
        .name = "a",
        .position = .{ .x = 20, .y = 50 },
        .size = .{ .width = 200, .height = 150 },
        .minimum_size = .{ .width = 50, .height = 50 },
        .maximum_size = .{ .width = 300, .height = 300 },
    };

    try new_window(&win_a);

    while (true) {
        @memset(framebuffer, viz_bg);

        for (windows.items) |win| {
            surface.fill_clipped_rectangle(win.position.x, win.position.y, win.size.width + chrome.horizontal, win.size.height + chrome.vertical, window_chrome);
            surface.fill_clipped_rectangle(win.position.x + chrome.left, win.position.y + chrome.top, win.size.width, win.size.height, window_bg);

            // TODO tell window to draw itself
        }

        draw_mouse_cursor(cursor_fg, 8);

        video.vga.copy_from(framebuffer);
    }

    win_a.deinit();
}

pub fn new_window(win: *Window) !void {
    try windows.append(win);
    win.id = next_window_id;
    next_window_id += 1;
}

pub fn move_to_front(win: *Window) void {
    for (windows.items, 0..) |match, i| {
        if (win.id == match.id) {
            _ = windows.orderedRemove(i);
            windows.insertAssumeCapacity(0, win);
            return;
        }
    }
}

fn draw_mouse_cursor(colour: u32, size: usize) void {
    for (0..size) |i| {
        surface.plot_xy(mouse.state.x + i, mouse.state.y + i, colour);
        surface.plot_xy(mouse.state.x, mouse.state.y + i, colour);
        surface.plot_xy(mouse.state.x + i, mouse.state.y, colour);
    }
}
