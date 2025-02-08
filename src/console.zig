const fmt = @import("std").fmt;
const Writer = @import("std").io.Writer;

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

var row: u16 = 0;
var column: u16 = 0;
var colour = vga_entry_colour(ConsoleColour.LightGray, ConsoleColour.Black);
var buffer = @as([*]volatile u16, @ptrFromInt(0xB8000));

inline fn vga_entry_colour(fg: ConsoleColour, bg: ConsoleColour) u8 {
    return @intFromEnum(fg) | (@intFromEnum(bg) << 4);
}

inline fn vga_entry(uc: u8, new_colour: u8) u16 {
    const c: u16 = new_colour;

    return uc | (c << 8);
}

pub fn initialize() void {
    clear();
}

pub fn set_colour(new_colour: u8) void {
    colour = new_colour;
}

pub fn clear() void {
    @memset(buffer[0..VGA_SIZE], vga_entry(' ', colour));

    row = 0;
    column = 0;
    move_hardware_cursor();
}

pub fn new_line() void {
    column = 0;
    row += 1;
    if (row == VGA_HEIGHT) scroll_down();
}

fn put_char_at(c: u8, new_colour: u8, x: usize, y: usize) void {
    const index = y * VGA_WIDTH + x;
    buffer[index] = vga_entry(c, new_colour);
}

pub fn putc(c: u8) void {
    put_char_at(c, colour, column, row);
    column += 1;
    if (column == VGA_WIDTH) new_line();
}

pub fn puts(data: []const u8) void {
    for (data) |c| {
        if (c == '\n') {
            new_line();
        } else {
            putc(c);
        }
    }

    move_hardware_cursor();
}

pub const printf_writer = Writer(void, error{}, printf_callback){ .context = {} };

fn printf_callback(_: void, string: []const u8) error{}!usize {
    puts(string);
    return string.len;
}

pub fn printf(comptime format: []const u8, args: anytype) void {
    fmt.format(printf_writer, format, args) catch unreachable;
}

fn move_hardware_cursor() void {
    const position = row * 80 + column;
    utils.outb(0x3D4, 0x0F);
    utils.outb(0x3D5, @truncate(position));
    utils.outb(0x3D4, 0x0E);
    utils.outb(0x3D5, @truncate(position >> 8));
}

fn scroll_down() void {
    const first = VGA_WIDTH;
    const last = VGA_SIZE - VGA_WIDTH;

    @memcpy(buffer[0..last], buffer[first..VGA_SIZE]);
    @memset(buffer[last..VGA_SIZE], vga_entry(' ', colour));

    row -= 1;
    move_hardware_cursor();
}

pub fn goto(x: u16, y: u16) void {
    column = x;
    row = y;
    move_hardware_cursor();
}
