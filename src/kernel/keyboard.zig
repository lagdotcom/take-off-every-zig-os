const std = @import("std");
const log = std.log.scoped(.keyboard);

const console = @import("console.zig");
const video = @import("video.zig");

pub const Key = enum(u8) {
    tilde = 1,
    @"1",
    @"2",
    @"3",
    @"4",
    @"5",
    @"6",
    @"7",
    @"8",
    @"9",
    @"0",
    minus,
    equals,
    backspace = 15,
    tab,
    q,
    w,
    e,
    r,
    t,
    y,
    u,
    i,
    o,
    p,
    left_square_bracket,
    right_square_bracket,
    pipe,

    caps_lock,
    a,
    s,
    d,
    f,
    g,
    h,
    j,
    k,
    l,
    semicolon,
    double_quote,

    left_enter,
    left_shift,
    macro,
    z,
    x,
    c,
    v,
    b,
    n,
    m,
    comma,
    period,
    slash,
    right_shift,

    left_ctrl,
    left_alt,
    space,
    right_alt,
    right_ctrl = 64,

    insert = 75,
    delete,
    left_arrow = 79,
    home,
    end,
    up_arrow = 83,
    down_arrow,
    page_up,
    page_down,
    right_arrow = 89,

    num_lock = 90,
    num_pad_7,
    num_pad_4,
    num_pad_1,
    num_pad_8,
    num_pad_5,
    num_pad_2,
    num_pad_0,
    num_pad_multiply,
    num_pad_9,
    num_pad_6,
    num_pad_3,
    num_pad_delete,
    num_pad_minus,
    num_pad_plus,
    num_pad_divide,

    enter = 108,
    escape = 110,

    f1 = 112,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,

    print_screen = 124,
    scroll_lock,
    pause,

    COUNT,
};

const Meta = struct {
    left_shift: bool,
    left_ctrl: bool,
    left_alt: bool,
    right_shift: bool,
    right_ctrl: bool,
    right_alt: bool,
    caps_lock: bool,
    num_lock: bool,
};

const KeyPressEvent = struct {
    key: Key,
    meta: Meta,
    printed_value: ?[]const u8,
};

var key_states: []bool = undefined;
var caps_lock_state: bool = undefined;
var num_lock_state: bool = undefined;

const BUFFER_SIZE = 256;
var key_press_buffer: []KeyPressEvent = undefined;
var key_press_read_index: usize = 0;
var key_press_write_index: usize = 0;

pub fn is_pressed(key: Key) bool {
    return key_states[@intFromEnum(key)];
}

pub fn is_keypress_waiting() bool {
    return key_press_read_index != key_press_write_index;
}

pub fn get_key_press() KeyPressEvent {
    while (!is_keypress_waiting()) {}

    const e = key_press_buffer[key_press_read_index];
    key_press_read_index = (key_press_read_index + 1) % key_press_buffer.len;
    return e;
}

fn get_printable_key(key: Key, meta: Meta) ?[]const u8 {
    const shift = meta.left_shift or meta.right_shift;
    const uppercase = if (shift) !meta.caps_lock else meta.caps_lock;
    const alt_gr = meta.right_alt;

    return switch (key) {
        .tilde => if (shift) "¬" else if (alt_gr) "¦" else "`",
        .@"1" => if (shift) "!" else "1",
        .@"2" => if (shift) "\"" else "2",
        .@"3" => if (shift) "£" else "3",
        .@"4" => if (shift) "$" else if (alt_gr) "€" else "4",
        .@"5" => if (shift) "%" else "5",
        .@"6" => if (shift) "^" else "6",
        .@"7" => if (shift) "&" else "7",
        .@"8" => if (shift) "*" else "8",
        .@"9" => if (shift) "(" else "9",
        .@"0" => if (shift) ")" else "0",
        .minus => if (shift) "_" else "-",
        .equals => if (shift) "+" else "=",

        .tab => "\t",
        .q => if (uppercase) "Q" else "q",
        .w => if (uppercase) "W" else "w",
        .e => switch (uppercase) {
            true => if (alt_gr) "É" else "E",
            false => if (alt_gr) "é" else "e",
        },
        .r => if (uppercase) "R" else "r",
        .t => if (uppercase) "T" else "t",
        .y => switch (uppercase) {
            true => if (alt_gr) "Ý" else "Y",
            false => if (alt_gr) "ý" else "y",
        },
        .u => switch (uppercase) {
            true => if (alt_gr) "Ú" else "U",
            false => if (alt_gr) "ú" else "u",
        },
        .i => switch (uppercase) {
            true => if (alt_gr) "Í" else "I",
            false => if (alt_gr) "í" else "i",
        },
        .o => switch (uppercase) {
            true => if (alt_gr) "Ó" else "O",
            false => if (alt_gr) "ó" else "o",
        },
        .p => if (uppercase) "P" else "p",
        .left_square_bracket => if (shift) "{" else "[",
        .right_square_bracket => if (shift) "}" else "]",

        .a => switch (uppercase) {
            true => if (alt_gr) "Á" else "A",
            false => if (alt_gr) "á" else "a",
        },
        .s => if (uppercase) "S" else "s",
        .d => if (uppercase) "D" else "d",
        .f => if (uppercase) "F" else "f",
        .g => if (uppercase) "G" else "g",
        .h => if (uppercase) "H" else "h",
        .j => if (uppercase) "J" else "j",
        .k => if (uppercase) "K" else "k",
        .l => if (uppercase) "L" else "l",
        .semicolon => if (shift) ":" else ";",
        .double_quote => if (shift) "@" else "\"",
        .pipe => if (shift) "~" else "#",
        .left_enter => "\n",

        .macro => if (shift) "|" else "\\",
        .z => if (uppercase) "Z" else "z",
        .x => if (uppercase) "X" else "x",
        .c => if (uppercase) "C" else "c",
        .v => if (uppercase) "V" else "v",
        .b => if (uppercase) "B" else "b",
        .n => if (uppercase) "N" else "n",
        .m => if (uppercase) "M" else "m",
        .comma => if (shift) "<" else ",",
        .period => if (shift) ">" else ".",
        .slash => if (shift) "?" else "/",

        .space => " ",

        .num_pad_0 => if (meta.num_lock) "0" else null,
        .num_pad_1 => if (meta.num_lock) "1" else null,
        .num_pad_2 => if (meta.num_lock) "2" else null,
        .num_pad_3 => if (meta.num_lock) "3" else null,
        .num_pad_4 => if (meta.num_lock) "4" else null,
        .num_pad_5 => if (meta.num_lock) "5" else null,
        .num_pad_6 => if (meta.num_lock) "6" else null,
        .num_pad_7 => if (meta.num_lock) "7" else null,
        .num_pad_8 => if (meta.num_lock) "8" else null,
        .num_pad_9 => if (meta.num_lock) "9" else null,
        .num_pad_minus => "-",
        .num_pad_multiply => "*",
        .num_pad_plus => "+",
        .num_pad_divide => "/",
        .num_pad_delete => if (meta.num_lock) "." else null,
        .enter => "\n",

        else => null,
    };
}

pub fn on(key: Key) void {
    key_states[@intFromEnum(key)] = true;

    if (key == .caps_lock) {
        caps_lock_state = !caps_lock_state;
    } else if (key == .num_lock) {
        num_lock_state = !num_lock_state;
    }

    const meta: Meta = .{
        .left_alt = is_pressed(.left_alt),
        .left_ctrl = is_pressed(.left_ctrl),
        .left_shift = is_pressed(.left_shift),
        .right_alt = is_pressed(.right_alt),
        .right_ctrl = is_pressed(.right_ctrl),
        .right_shift = is_pressed(.right_shift),
        .caps_lock = caps_lock_state,
        .num_lock = num_lock_state,
    };

    const printed_value = get_printable_key(key, meta);

    // TODO check if buffer is full
    key_press_buffer[key_press_write_index] = .{
        .key = key,
        .meta = meta,
        .printed_value = printed_value,
    };
    key_press_write_index = (key_press_write_index + 1) % key_press_buffer.len;
}

pub fn off(key: Key) void {
    key_states[@intFromEnum(key)] = false;
    // TODO add to buffer
}

pub fn initialize(allocator: std.mem.Allocator) !void {
    log.debug("initializing", .{});
    defer log.debug("done", .{});

    key_states = try allocator.alloc(bool, @intFromEnum(Key.COUNT));
    key_press_buffer = try allocator.alloc(KeyPressEvent, BUFFER_SIZE);
    key_press_read_index = 0;
    key_press_write_index = 0;

    // TODO read from keyboard leds?
    caps_lock_state = false;
    num_lock_state = false;
}

pub fn echo_mode(vid: *video.VideoInfo) void {
    console.puts("entering echo mode\n");

    while (true) {
        const e = get_key_press();
        if (e.printed_value) |print| console.putc(print);

        switch (e.key) {
            .f1 => console.set_foreground_colour(vid.rgb(255, 255, 255)),
            .f2 => console.set_foreground_colour(vid.rgb(255, 0, 0)),
            .f3 => console.set_foreground_colour(vid.rgb(0, 255, 0)),
            .f4 => console.set_foreground_colour(vid.rgb(0, 0, 255)),
            .f5 => console.set_foreground_colour(vid.rgb(255, 255, 0)),
            .f6 => console.set_foreground_colour(vid.rgb(255, 0, 255)),
            .f7 => console.set_foreground_colour(vid.rgb(0, 255, 255)),
            else => {},
        }
    }
}
