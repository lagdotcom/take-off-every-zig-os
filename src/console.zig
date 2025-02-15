const std = @import("std");
const log = std.log.scoped(.console);

const kernel = @import("kernel.zig");
const fonts = @import("fonts.zig");

var video: *const kernel.VideoInfo = undefined;
var cursor_x: usize = 0;
var cursor_y: usize = 0;
var current_font: *const FontData = undefined;

pub fn initialize(v: *const kernel.VideoInfo) void {
    video = v;

    clear();
}

pub fn clear() void {
    @memset(video.framebuffer[0..video.framebuffer_size], 0);
    cursor_x = 0;
    cursor_y = 0;
    current_font = &fonts.laggy8x8;
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
    }
    // TODO '\t'
    else {
        if (c != ' ') {
            put_font_char(current_font, c, cursor_x, cursor_y);
            cursor_x += current_font.char_width;
        } else {
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
    // TODO
}

fn put_font_char(f: *const FontData, c: u21, sx: usize, sy: usize) void {
    var i = video.pixels_per_scan_line * sy + sx;

    const cd = get_char_data(f, c);

    var j: usize = 0;
    for (0..f.char_height) |_| {
        for (0..f.char_width) |_| {
            video.framebuffer[i] = if (cd[j]) 0xffffffff else 0;
            i += 1;
            j += 1;
        }

        i += video.pixels_per_scan_line - f.char_width;
    }
}

fn get_char_data(f: *const FontData, c: u21) []const bool {
    const char_size = f.char_width * f.char_height;

    for (f.chars) |*e| {
        if (e.cp == c) return f.glyph_data[e.offset .. e.offset + char_size];

        // TODO implement this so lookup is faster
        // TODO or even better, use a hash table or whatever
        // if (e.cp > c) break;
    }

    // unknown char is always stored first
    return f.glyph_data[0..char_size];
}

pub const CharEntry = extern struct {
    cp: u32,
    offset: u32,

    pub fn lessThan(_: void, a: CharEntry, b: CharEntry) bool {
        return a.cp < b.cp;
    }
};

pub const FontData = struct {
    char_width: u16,
    char_height: u16,
    space_width: u16,
    chars: []const CharEntry,
    glyph_data: []const bool,
};
