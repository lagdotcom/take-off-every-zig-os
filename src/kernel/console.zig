const std = @import("std");
const log = std.log.scoped(.console);

const fonts = @import("fonts.zig");
const video = @import("video.zig");

pub var cursor_x: usize = 0;
pub var cursor_y: usize = 0;
var current_font: *const FontData = undefined;
var fg_colour: u32 = 0xffffffff;
var bg_colour: u32 = 0;

pub fn initialize() void {
    log.debug("initializing", .{});
    defer log.debug("done", .{});

    clear();
}

pub fn clear() void {
    video.vga.fill(0);

    cursor_x = 0;
    cursor_y = 0;
    set_font(&fonts.zero_wing);
}

pub fn set_font(font: *const FontData) void {
    current_font = font;
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

fn put_char_or_space(c: u21) bool {
    if (c > ' ') {
        put_font_char(c);
        return true;
    } else {
        video.vga.fill_rectangle(cursor_x, cursor_y, current_font.space_width, current_font.char_height, bg_colour);
        return false;
    }
}

pub fn putc(c: u21) void {
    if (c == '\n') {
        new_line();
    } else if (c == '\r') {
        cursor_x = 0;
    } else if (c == '\t') {
        const tab_size = current_font.char_width * 4;
        const offset = tab_size - (cursor_x % tab_size);
        const ex = @min(cursor_x + offset, video.vga.horizontal);

        if (ex > cursor_x)
            video.vga.fill_rectangle(cursor_x, cursor_y, ex - cursor_x, current_font.char_height, bg_colour);

        if (ex >= video.vga.horizontal) {
            new_line();
        } else {
            cursor_x = ex;
        }
    } else {
        cursor_x += if (put_char_or_space(c)) current_font.char_width else current_font.space_width;
        if (cursor_x >= video.vga.horizontal) new_line();
    }
}

pub fn replace_last_char(s: []const u8, move: bool) void {
    var new_x = cursor_x;
    var new_y = cursor_y;

    if (cursor_x == 0) {
        if (cursor_y == 0) {
            // lol now what
            return;
        }

        new_y -= current_font.char_height;
        new_x = video.vga.horizontal - current_font.char_width;
    } else {
        new_x -= current_font.char_width;
    }

    cursor_x = new_x;
    cursor_y = new_y;

    puts(s);

    if (move) {
        cursor_x = new_x;
        cursor_y = new_y;
    }
}

pub fn new_line() void {
    cursor_x = 0;
    cursor_y += current_font.char_height;
    if (cursor_y >= video.vga.vertical) scroll_down();
}

pub const printf_writer = std.io.Writer(void, error{}, printf_callback){ .context = {} };

fn printf_callback(_: void, string: []const u8) error{}!usize {
    puts(string);
    return string.len;
}

pub fn printf(comptime format: []const u8, args: anytype) void {
    std.fmt.format(printf_writer, format, args) catch return;
}

pub fn printf_nl(comptime format: []const u8, args: anytype) void {
    std.fmt.format(printf_writer, format, args) catch return;
    new_line();
}

fn scroll_down() void {
    const row_size = video.vga.pixels_per_scan_line * current_font.char_height;
    const stop_copying_at = video.vga.pixels_per_scan_line * (video.vga.vertical - current_font.char_height);

    var offset: usize = 0;
    while (offset < stop_copying_at) {
        @memcpy(
            video.vga.framebuffer[offset .. offset + row_size],
            video.vga.framebuffer[offset + row_size .. offset + row_size + row_size],
        );

        offset += row_size;
    }

    @memset(video.vga.framebuffer[stop_copying_at..video.vga.framebuffer_size], 0);

    cursor_y -= current_font.char_height;
}

fn put_font_char(c: u21) void {
    var i = video.vga.get_index(cursor_x, cursor_y);
    const stride = video.vga.pixels_per_scan_line - current_font.char_width;

    const cd = get_char_data(current_font, c);

    var j: usize = 0;
    for (0..current_font.char_height) |_| {
        for (0..current_font.char_width) |_| {
            video.vga.plot(i, if (cd[j]) fg_colour else bg_colour);
            i += 1;
            j += 1;
        }

        i += stride;
    }
}

const Fallback = struct { cp: u21, alternatives: []const u21 };

const fallback_table: []const Fallback = &.{
    .{ .cp = 'a', .alternatives = &.{'A'} },
    .{ .cp = 'b', .alternatives = &.{'B'} },
    .{ .cp = 'c', .alternatives = &.{'C'} },
    .{ .cp = 'd', .alternatives = &.{'D'} },
    .{ .cp = 'e', .alternatives = &.{'E'} },
    .{ .cp = 'f', .alternatives = &.{'F'} },
    .{ .cp = 'g', .alternatives = &.{'G'} },
    .{ .cp = 'h', .alternatives = &.{'H'} },
    .{ .cp = 'i', .alternatives = &.{'I'} },
    .{ .cp = 'j', .alternatives = &.{'J'} },
    .{ .cp = 'k', .alternatives = &.{'K'} },
    .{ .cp = 'l', .alternatives = &.{'L'} },
    .{ .cp = 'm', .alternatives = &.{'M'} },
    .{ .cp = 'n', .alternatives = &.{'N'} },
    .{ .cp = 'o', .alternatives = &.{'O'} },
    .{ .cp = 'p', .alternatives = &.{'P'} },
    .{ .cp = 'q', .alternatives = &.{'Q'} },
    .{ .cp = 'r', .alternatives = &.{'R'} },
    .{ .cp = 's', .alternatives = &.{'S'} },
    .{ .cp = 't', .alternatives = &.{'T'} },
    .{ .cp = 'u', .alternatives = &.{'U'} },
    .{ .cp = 'v', .alternatives = &.{'V'} },
    .{ .cp = 'w', .alternatives = &.{'W'} },
    .{ .cp = 'x', .alternatives = &.{'X'} },
    .{ .cp = 'y', .alternatives = &.{'Y'} },
    .{ .cp = 'z', .alternatives = &.{'Z'} },
    .{ .cp = '‼', .alternatives = &.{'!'} },
};

fn get_char_fallbacks(cp: u21) ?[]const u21 {
    for (fallback_table) |fb| {
        if (fb.cp == cp) return fb.alternatives;
    }
    return null;
}

fn get_individual_char_data(f: *const FontData, cp: u21) ?[]const bool {
    const char_size = f.char_width * f.char_height;

    for (f.chars) |*e| {
        if (e.cp == cp) return f.glyph_data[e.offset .. e.offset + char_size];

        // TODO make this into a hash table or whatever later
        if (e.cp > cp) break;
    }

    return null;
}

fn get_char_data(f: *const FontData, cp: u21) []const bool {
    if (get_individual_char_data(f, cp)) |data| return data;

    // try fallbacks?
    if (get_char_fallbacks(cp)) |fb_list| {
        for (fb_list) |fb| {
            if (get_individual_char_data(f, fb)) |data| return data;
        }
    }

    // unknown char is always stored first
    const char_size = f.char_width * f.char_height;
    return f.glyph_data[0..char_size];
}

pub const FontData = struct {
    name: []const u8,
    char_width: u16,
    char_height: u16,
    space_width: u16,
    chars: []const fonts.FONEntry,
    glyph_data: []const bool,
};
