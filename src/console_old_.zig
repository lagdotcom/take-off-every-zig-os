const std = @import("std");
const log = std.log.scoped(.console);

const utils = @import("utils.zig");

const VGA_WIDTH = 80;
const VGA_HEIGHT = 25;
const VGA_SIZE = VGA_WIDTH * VGA_HEIGHT;

pub const ConsoleColour = enum(u8) {
    Black = 0,
    Blue = 1,
    Green = 2,
    Cyan = 3,
    Red = 4,
    Magenta = 5,
    Brown = 6,
    LightGray = 7,
    DarkGray = 8,
    LightBlue = 9,
    LightGreen = 10,
    LightCyan = 11,
    LightRed = 12,
    LightMagenta = 13,
    LightBrown = 14,
    White = 15,
};

const Terminal = struct {
    row: usize,
    column: usize,
    colour: u8,
    buffer: [*]volatile u16,
};

var term = Terminal{
    .row = 0,
    .column = 0,
    .colour = vga_entry_colour(ConsoleColour.LightGray, ConsoleColour.Black),
    .buffer = @as([*]volatile u16, @ptrFromInt(0xB8000)),
};

fn vga_entry_colour(fg: ConsoleColour, bg: ConsoleColour) u8 {
    return @intFromEnum(fg) | (@intFromEnum(bg) << 4);
}

fn vga_entry(uc: u8, colour: u8) u16 {
    const c: u16 = colour;
    return uc | (c << 8);
}

pub fn initialize() void {
    clear();
}

pub fn set_colour(colour: u8) void {
    term.colour = colour;
}

pub fn clear() void {
    log.debug("clearing console", .{});
    @memset(term.buffer[0..VGA_SIZE], vga_entry(' ', term.colour));

    term.row = 0;
    term.column = 0;
    move_hardware_cursor();
}

pub fn new_line() void {
    log.debug("new line, old row={d}", .{term.row});
    term.column = 0;
    term.row += 1;
    if (term.row >= VGA_HEIGHT) scroll_down();
}

fn put_char_at(c: u8, new_colour: u8, x: usize, y: usize) void {
    const index = y * VGA_WIDTH + x;
    term.buffer[index] = vga_entry(c, new_colour);
}

pub fn putc(c: u8) void {
    put_char_at(c, term.colour, term.column, term.row);
    term.column += 1;
    if (term.column == VGA_WIDTH) new_line();
}

pub fn puts(data: []const u8) void {
    for (data) |c| {
        if (c == '\n') {
            new_line();
        } else if (c == '\r') {
            term.column = 0;
        } else if (c == '\t') {
            while (term.column % 4 != 0) putc(' ');
        } else {
            putc(c);
        }
    }

    move_hardware_cursor();
}

pub const printf_writer = std.io.Writer(void, error{}, printf_callback){ .context = {} };

fn printf_callback(_: void, string: []const u8) error{}!usize {
    puts(string);
    return string.len;
}

pub fn printf(comptime format: []const u8, args: anytype) void {
    std.fmt.format(printf_writer, format, args) catch unreachable;
}

fn move_hardware_cursor() void {
    const position = term.row * 80 + term.column;
    // log.debug("updating hardware cursor to {x} ({d},{d})", .{ position, term.column, term.row });
    utils.outb(0x3D4, 0x0F);
    utils.outb(0x3D5, @truncate(position));
    utils.outb(0x3D4, 0x0E);
    utils.outb(0x3D5, @truncate(position >> 8));
}

fn vga_row_offset(y: usize) usize {
    return y * VGA_WIDTH;
}

fn scroll_down() void {
    for (1..VGA_HEIGHT) |y| {
        const a = vga_row_offset(y - 1);
        const b = vga_row_offset(y);
        const c = vga_row_offset(y + 1);
        @memcpy(term.buffer[a..b], term.buffer[b..c]);
    }

    log.debug("scrolling down; clearing last line", .{});
    @memset(term.buffer[vga_row_offset(VGA_HEIGHT - 1)..VGA_SIZE], vga_entry(' ', term.colour));

    term.row -= 1;
    move_hardware_cursor();
}

pub fn goto(x: u16, y: u16) void {
    term.column = x;
    term.row = y;
    move_hardware_cursor();
}
