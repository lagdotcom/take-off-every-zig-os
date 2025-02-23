const std = @import("std");
const log = std.log.scoped(.console);

const kernel = @import("kernel.zig");
const fonts = @import("fonts.zig");

var video = &kernel.boot_info.video;
var cursor_x: usize = 0;
var cursor_y: usize = 0;
var current_font: *const FontData = undefined;
var fg_colour: u32 = 0xffffffff;
var bg_colour: u32 = 0;

pub fn initialize() void {
    clear();
}

pub fn clear() void {
    video.fill(0);

    cursor_x = 0;
    cursor_y = 0;
    current_font = &fonts.laggy8x8;
}

pub fn set_foreground_colour(colour: u32) void {
    fg_colour = colour;
}

pub fn set_background_colour(colour: u32) void {
    bg_colour = colour;
}

pub fn puts(str: []const u8) void {
    var vi = std.unicode.Utf8Iterator{ .bytes = str, .i = 0 };
    while (vi.nextCodepoint()) |c| putc(c);
}

pub fn putc(c: u21) void {
    if (c == '\n') {
        new_line();
    } else if (c == '\r') {
        cursor_x = 0;
    } else if (c == '\t') {
        const tab_size = current_font.char_width * 4;
        const offset = tab_size - (cursor_x % tab_size);
        const ex = @min(cursor_x + offset, video.horizontal);

        if (ex > cursor_x)
            video.fill_rectangle(cursor_x, cursor_y, ex - cursor_x, current_font.char_height, bg_colour);

        if (ex >= video.horizontal) {
            new_line();
        } else {
            cursor_x = ex;
        }
    } else {
        if (c > ' ') {
            put_font_char(c);
            cursor_x += current_font.char_width;
        } else {
            video.fill_rectangle(cursor_x, cursor_y, current_font.space_width, current_font.char_height, bg_colour);
            cursor_x += current_font.space_width;
        }

        if (cursor_x >= video.horizontal) new_line();
    }
}

pub fn new_line() void {
    cursor_x = 0;
    cursor_y += current_font.char_height;
    if (cursor_y >= video.vertical) scroll_down();
}

pub const printf_writer = std.io.Writer(void, error{}, printf_callback){ .context = {} };

fn printf_callback(_: void, string: []const u8) error{}!usize {
    puts(string);
    return string.len;
}

pub fn printf(comptime format: []const u8, args: anytype) void {
    std.fmt.format(printf_writer, format, args) catch unreachable;
}

fn scroll_down() void {
    const row_size = video.pixels_per_scan_line * current_font.char_height;
    const stop_copying_at = video.pixels_per_scan_line * (video.vertical - current_font.char_height);

    var offset: usize = 0;
    while (offset < stop_copying_at) {
        @memcpy(
            video.framebuffer[offset .. offset + row_size],
            video.framebuffer[offset + row_size .. offset + row_size + row_size],
        );

        offset += row_size;
    }

    @memset(video.framebuffer[stop_copying_at..video.framebuffer_size], 0);

    cursor_y -= current_font.char_height;
}

fn put_font_char(c: u21) void {
    var i = video.get_index(cursor_x, cursor_y);
    const stride = video.pixels_per_scan_line - current_font.char_width;

    const cd = get_char_data(current_font, c);

    var j: usize = 0;
    for (0..current_font.char_height) |_| {
        for (0..current_font.char_width) |_| {
            video.plot(i, if (cd[j]) fg_colour else bg_colour);
            i += 1;
            j += 1;
        }

        i += stride;
    }
}

fn get_char_data(f: *const FontData, c: u21) []const bool {
    const char_size = f.char_width * f.char_height;

    for (f.chars) |*e| {
        if (e.cp == c) return f.glyph_data[e.offset .. e.offset + char_size];

        // TODO make this into a hash table or whatever later
        if (e.cp > c) break;
    }

    // unknown char is always stored first
    return f.glyph_data[0..char_size];
}

pub const CharEntry = extern struct { cp: u32, offset: u32 };

pub const FontData = struct {
    char_width: u16,
    char_height: u16,
    space_width: u16,
    chars: []const CharEntry,
    glyph_data: []const bool,
};
