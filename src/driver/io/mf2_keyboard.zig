const std = @import("std");
const log = std.log.scoped(.mf2_keyboard);

const kernel = @import("../../kernel.zig");

const Command = enum(u8) {
    set_reset_mode_indicators = 0xed,
    echo = 0xee,
    select_alternate_code_set = 0xf0,
    read_keyboard_id = 0xf2,
    set_typematic_rate = 0xf3,
    enable = 0xf4,
    default_disable = 0xf5,
    set_default = 0xf6,
    set_all_keys_typematic = 0xf7,
    set_all_keys_make_break = 0xf8,
    set_all_keys_make = 0xf9,
    set_all_keys_typematic_make_break = 0xfa,
    set_key_typematic = 0xfb,
    set_key_make_break = 0xfc,
    set_key_make = 0xfd,
    resend = 0xfe,
    reset = 0xff,
};

const Response = enum(u8) {
    set23_error = 0,
    bat_completion = 0xaa,
    bat_failure = 0xac,
    echo = 0xee,
    ack = 0xfa,
    resend = 0xfe,
    set1_error = 0xff,
};

const Key = enum(u8) {
    tilde = 1,
    _1,
    _2,
    _3,
    _4,
    _5,
    _6,
    _7,
    _8,
    _9,
    _0,
    minus,
    plus,
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
    colon,
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
    left_angle_bracket,
    right_angle_bracket,
    slash,
    right_shift,

    left_control,
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

const State = struct { interpret: *const fn (self: *MF2Keyboard, byte: u8) State };
const s_normal = State{ .interpret = MF2Keyboard.state_normal };
const s_e0 = State{ .interpret = MF2Keyboard.state_e0 };
const s_f0 = State{ .interpret = MF2Keyboard.state_f0 };
const s_e0_f0 = State{ .interpret = MF2Keyboard.state_e0_f0 };

const MF2Keyboard = struct {
    aux: bool,
    states: []bool,
    state: State,

    pub fn init(allocator: std.mem.Allocator, is_aux: bool) !MF2Keyboard {
        const states = try allocator.alloc(bool, @intFromEnum(Key.COUNT));

        // TODO set up interrupt handler

        return .{ .states = states, .aux = is_aux, .state = s_normal };
    }

    fn on_byte(self: *MF2Keyboard, b: u8) void {
        self.state = self.state.interpret(self, b);
    }

    fn key_on(self: *MF2Keyboard, key: Key) void {
        self.states[@intFromEnum(key)] = true;
        // TODO fire key event
    }

    fn key_off(self: *MF2Keyboard, key: Key) void {
        self.states[@intFromEnum(key)] = false;
        // TODO fire key event
    }

    fn key_on_off(self: *MF2Keyboard, key: Key) void {
        self.key_on(key);
        self.key_off(key);
    }

    fn state_normal(self: *MF2Keyboard, b: u8) State {
        if (b == 0xe0) return s_e0;
        if (b == 0xf0) return s_f0;

        switch (b) {
            0x0e => self.key_on(.tilde),
            0x16 => self.key_on(._1),
            0x1e => self.key_on(._2),
            0x26 => self.key_on(._3),
            0x25 => self.key_on(._4),
            0x2e => self.key_on(._5),
            0x36 => self.key_on(._6),
            0x3d => self.key_on(._7),
            0x3e => self.key_on(._8),
            0x46 => self.key_on(._9),
            0x45 => self.key_on(._0),
            0x4e => self.key_on(.minus),
            0x55 => self.key_on(.plus),
            0x66 => self.key_on(.backspace),
            0x0d => self.key_on(.tab),
            0x15 => self.key_on(.q),
            0x1d => self.key_on(.w),
            0x24 => self.key_on(.e),
            0x2d => self.key_on(.r),
            0x2c => self.key_on(.t),
            0x35 => self.key_on(.y),
            0x3c => self.key_on(.u),
            0x43 => self.key_on(.i),
            0x44 => self.key_on(.o),
            0x4d => self.key_on(.p),
            0x54 => self.key_on(.left_square_bracket),
            0x5b => self.key_on(.right_square_bracket),
            0x5d => self.key_on(.pipe),
            0x58 => self.key_on(.caps_lock),
            0x1c => self.key_on(.a),
            0x1b => self.key_on(.s),
            0x23 => self.key_on(.d),
            0x2b => self.key_on(.f),
            0x34 => self.key_on(.g),
            0x33 => self.key_on(.h),
            0x3b => self.key_on(.j),
            0x42 => self.key_on(.k),
            0x4b => self.key_on(.l),
            0x4c => self.key_on(.colon),
            0x52 => self.key_on(.double_quote),
            0x5a => self.key_on(.left_enter),
            0x12 => self.key_on(.left_shift),
            0x61 => self.key_on(.macro),
            0x1a => self.key_on(.z),
            0x22 => self.key_on(.x),
            0x21 => self.key_on(.c),
            0x2a => self.key_on(.v),
            0x32 => self.key_on(.b),
            0x31 => self.key_on(.n),
            0x3a => self.key_on(.m),
            0x41 => self.key_on(.left_angle_bracket),
            0x49 => self.key_on(.right_angle_bracket),
            0x4a => self.key_on(.slash),
            0x59 => self.key_on(.right_shift),
            0x14 => self.key_on(.left_control),
            0x11 => self.key_on(.left_alt),
            0x29 => self.key_on(.space),
            0x77 => self.key_on(.num_lock),
            0x6c => self.key_on(.num_pad_7),
            0x6b => self.key_on(.num_pad_4),
            0x69 => self.key_on(.num_pad_1),
            0x75 => self.key_on(.num_pad_8),
            0x73 => self.key_on(.num_pad_5),
            0x72 => self.key_on(.num_pad_2),
            0x70 => self.key_on(.num_pad_0),
            0x7c => self.key_on(.num_pad_multiply),
            0x7d => self.key_on(.num_pad_9),
            0x74 => self.key_on(.num_pad_6),
            0x7a => self.key_on(.num_pad_3),
            0x71 => self.key_on(.num_pad_delete),
            0x7b => self.key_on(.num_pad_minus),
            0x79 => self.key_on(.num_pad_plus),
            0x76 => self.key_on(.escape),
            0x05 => self.key_on(.f1),
            0x06 => self.key_on(.f2),
            0x04 => self.key_on(.f3),
            0x0c => self.key_on(.f4),
            0x03 => self.key_on(.f5),
            0x0b => self.key_on(.f6),
            0x83 => self.key_on(.f7),
            0x0a => self.key_on(.f8),
            0x01 => self.key_on(.f9),
            0x09 => self.key_on(.f10),
            0x78 => self.key_on(.f11),
            0x07 => self.key_on(.f12),
            0x7e => self.key_on(.scroll_lock),

            else => log.warn("unexpected {x}", .{b}),
        }
        return s_normal;
    }

    fn state_e0(self: *MF2Keyboard, b: u8) State {
        if (b == 0xf0) return s_e0_f0;
        switch (b) {
            0x11 => self.key_on(.right_alt),
            0x14 => self.key_on(.right_ctrl),
            0x5a => self.key_on(.enter),

            0x70 => self.key_on(.insert),
            0x71 => self.key_on(.delete),
            0x6b => self.key_on(.left_arrow),
            0x6c => self.key_on(.home),
            0x69 => self.key_on(.end),
            0x75 => self.key_on(.up_arrow),
            0x72 => self.key_on(.down_arrow),
            0x7d => self.key_on(.page_up),
            0x7a => self.key_on(.page_down),
            0x74 => self.key_on(.right_arrow),

            else => log.warn("unexpected e0 {x}", .{b}),
        }
        return s_normal;
    }

    fn state_f0(self: *MF2Keyboard, b: u8) State {
        switch (b) {
            0x0e => self.key_off(.tilde),
            0x16 => self.key_off(._1),

            else => log.warn("unexpected f0 {x}", .{b}),
        }
        return s_normal;
    }

    fn state_e0_f0(self: *MF2Keyboard, b: u8) State {
        switch (b) {
            0x11 => self.key_off(.right_alt),
            0x14 => self.key_off(.right_ctrl),
            0x5a => self.key_off(.enter),

            0x70 => self.key_off(.insert),
            0x71 => self.key_off(.delete),
            0x6b => self.key_off(.left_arrow),
            0x6c => self.key_off(.home),
            0x69 => self.key_off(.end),
            0x75 => self.key_off(.up_arrow),
            0x72 => self.key_off(.down_arrow),
            0x7d => self.key_off(.page_up),
            0x7a => self.key_off(.page_down),
            0x74 => self.key_off(.right_arrow),

            else => log.warn("unexpected e0 f0 {x}", .{b}),
        }
        return s_normal;
    }

    // TODO support for pause, print screen, see https://doc.lagout.org/science/0_Computer%20Science/0_Computer%20History/old-hardware/national/_appNotes/AN-0734.pdf
};

var driver: MF2Keyboard = undefined;

pub fn initialize(is_aux: bool) void {
    log.debug("initializing on {s}", .{if (is_aux) "aux" else "main"});

    driver = MF2Keyboard.init(kernel.allocator, is_aux) catch unreachable;
}
