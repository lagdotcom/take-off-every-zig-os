const std = @import("std");
const log = std.log.scoped(.mf2_keyboard);

const interrupts = @import("../../interrupts.zig");
const kb = @import("../../keyboard.zig");
const pic = @import("../../pic.zig");
const ps2 = @import("../../ps2.zig");

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

const State = struct { interpret: *const fn (byte: u8) State };
const s_normal = State{ .interpret = state_normal };
const s_e0 = State{ .interpret = state_e0 };
const s_f0 = State{ .interpret = state_f0 };
const s_e0_f0 = State{ .interpret = state_e0_f0 };

const Driver = struct { aux: bool, state: State };
var driver: Driver = .{ .aux = false, .state = s_normal };

fn on_byte(b: u8) void {
    driver.state = driver.state.interpret(b);
}

fn key_on(key: kb.Key) void {
    log.debug("ON: {s}", .{@tagName(key)});
    kb.on(key);
    // TODO fire key event
}

fn key_off(key: kb.Key) void {
    log.debug("OFF: {s}", .{@tagName(key)});
    kb.off(key);
}

fn key_on_off(key: kb.Key) void {
    key_on(key);
    key_off(key);
}

fn state_normal(b: u8) State {
    if (b == 0xe0) return s_e0;
    if (b == 0xf0) return s_f0;

    switch (b) {
        0x0e => key_on(.tilde),
        0x16 => key_on(.@"1"),
        0x1e => key_on(.@"2"),
        0x26 => key_on(.@"3"),
        0x25 => key_on(.@"4"),
        0x2e => key_on(.@"5"),
        0x36 => key_on(.@"6"),
        0x3d => key_on(.@"7"),
        0x3e => key_on(.@"8"),
        0x46 => key_on(.@"9"),
        0x45 => key_on(.@"0"),
        0x4e => key_on(.minus),
        0x55 => key_on(.equals),
        0x66 => key_on(.backspace),
        0x0d => key_on(.tab),
        0x15 => key_on(.q),
        0x1d => key_on(.w),
        0x24 => key_on(.e),
        0x2d => key_on(.r),
        0x2c => key_on(.t),
        0x35 => key_on(.y),
        0x3c => key_on(.u),
        0x43 => key_on(.i),
        0x44 => key_on(.o),
        0x4d => key_on(.p),
        0x54 => key_on(.left_square_bracket),
        0x5b => key_on(.right_square_bracket),
        0x5d => key_on(.pipe),
        0x58 => key_on(.caps_lock),
        0x1c => key_on(.a),
        0x1b => key_on(.s),
        0x23 => key_on(.d),
        0x2b => key_on(.f),
        0x34 => key_on(.g),
        0x33 => key_on(.h),
        0x3b => key_on(.j),
        0x42 => key_on(.k),
        0x4b => key_on(.l),
        0x4c => key_on(.semicolon),
        0x52 => key_on(.double_quote),
        0x5a => key_on(.left_enter),
        0x12 => key_on(.left_shift),
        0x61 => key_on(.macro),
        0x1a => key_on(.z),
        0x22 => key_on(.x),
        0x21 => key_on(.c),
        0x2a => key_on(.v),
        0x32 => key_on(.b),
        0x31 => key_on(.n),
        0x3a => key_on(.m),
        0x41 => key_on(.comma),
        0x49 => key_on(.period),
        0x4a => key_on(.slash),
        0x59 => key_on(.right_shift),
        0x14 => key_on(.left_ctrl),
        0x11 => key_on(.left_alt),
        0x29 => key_on(.space),
        0x77 => key_on(.num_lock),
        0x6c => key_on(.num_pad_7),
        0x6b => key_on(.num_pad_4),
        0x69 => key_on(.num_pad_1),
        0x75 => key_on(.num_pad_8),
        0x73 => key_on(.num_pad_5),
        0x72 => key_on(.num_pad_2),
        0x70 => key_on(.num_pad_0),
        0x7c => key_on(.num_pad_multiply),
        0x7d => key_on(.num_pad_9),
        0x74 => key_on(.num_pad_6),
        0x7a => key_on(.num_pad_3),
        0x71 => key_on(.num_pad_delete),
        0x7b => key_on(.num_pad_minus),
        0x79 => key_on(.num_pad_plus),
        0x76 => key_on(.escape),
        0x05 => key_on(.f1),
        0x06 => key_on(.f2),
        0x04 => key_on(.f3),
        0x0c => key_on(.f4),
        0x03 => key_on(.f5),
        0x0b => key_on(.f6),
        0x83 => key_on(.f7),
        0x0a => key_on(.f8),
        0x01 => key_on(.f9),
        0x09 => key_on(.f10),
        0x78 => key_on(.f11),
        0x07 => key_on(.f12),
        0x7e => key_on(.scroll_lock),

        else => log.warn("unexpected {x}", .{b}),
    }
    return s_normal;
}

fn state_e0(b: u8) State {
    if (b == 0xf0) return s_e0_f0;
    switch (b) {
        0x11 => key_on(.right_alt),
        0x14 => key_on(.right_ctrl),
        0x4a => key_on(.num_pad_divide),
        0x5a => key_on(.enter),

        0x70 => key_on(.insert),
        0x71 => key_on(.delete),
        0x6b => key_on(.left_arrow),
        0x6c => key_on(.home),
        0x69 => key_on(.end),
        0x75 => key_on(.up_arrow),
        0x72 => key_on(.down_arrow),
        0x7d => key_on(.page_up),
        0x7a => key_on(.page_down),
        0x74 => key_on(.right_arrow),

        else => log.warn("unexpected e0 {x}", .{b}),
    }
    return s_normal;
}

fn state_f0(b: u8) State {
    switch (b) {
        0x0e => key_off(.tilde),
        0x16 => key_off(.@"1"),
        0x1e => key_off(.@"2"),
        0x26 => key_off(.@"3"),
        0x25 => key_off(.@"4"),
        0x2e => key_off(.@"5"),
        0x36 => key_off(.@"6"),
        0x3d => key_off(.@"7"),
        0x3e => key_off(.@"8"),
        0x46 => key_off(.@"9"),
        0x45 => key_off(.@"0"),
        0x4e => key_off(.minus),
        0x55 => key_off(.equals),
        0x66 => key_off(.backspace),
        0x0d => key_off(.tab),
        0x15 => key_off(.q),
        0x1d => key_off(.w),
        0x24 => key_off(.e),
        0x2d => key_off(.r),
        0x2c => key_off(.t),
        0x35 => key_off(.y),
        0x3c => key_off(.u),
        0x43 => key_off(.i),
        0x44 => key_off(.o),
        0x4d => key_off(.p),
        0x54 => key_off(.left_square_bracket),
        0x5b => key_off(.right_square_bracket),
        0x5d => key_off(.pipe),
        0x58 => key_off(.caps_lock),
        0x1c => key_off(.a),
        0x1b => key_off(.s),
        0x23 => key_off(.d),
        0x2b => key_off(.f),
        0x34 => key_off(.g),
        0x33 => key_off(.h),
        0x3b => key_off(.j),
        0x42 => key_off(.k),
        0x4b => key_off(.l),
        0x4c => key_off(.semicolon),
        0x52 => key_off(.double_quote),
        0x5a => key_off(.left_enter),
        0x12 => key_off(.left_shift),
        0x61 => key_off(.macro),
        0x1a => key_off(.z),
        0x22 => key_off(.x),
        0x21 => key_off(.c),
        0x2a => key_off(.v),
        0x32 => key_off(.b),
        0x31 => key_off(.n),
        0x3a => key_off(.m),
        0x41 => key_off(.comma),
        0x49 => key_off(.period),
        0x4a => key_off(.slash),
        0x59 => key_off(.right_shift),
        0x14 => key_off(.left_ctrl),
        0x11 => key_off(.left_alt),
        0x29 => key_off(.space),
        0x77 => key_off(.num_lock),
        0x6c => key_off(.num_pad_7),
        0x6b => key_off(.num_pad_4),
        0x69 => key_off(.num_pad_1),
        0x75 => key_off(.num_pad_8),
        0x73 => key_off(.num_pad_5),
        0x72 => key_off(.num_pad_2),
        0x70 => key_off(.num_pad_0),
        0x7c => key_off(.num_pad_multiply),
        0x7d => key_off(.num_pad_9),
        0x74 => key_off(.num_pad_6),
        0x7a => key_off(.num_pad_3),
        0x71 => key_off(.num_pad_delete),
        0x7b => key_off(.num_pad_minus),
        0x79 => key_off(.num_pad_plus),
        0x76 => key_off(.escape),
        0x05 => key_off(.f1),
        0x06 => key_off(.f2),
        0x04 => key_off(.f3),
        0x0c => key_off(.f4),
        0x03 => key_off(.f5),
        0x0b => key_off(.f6),
        0x83 => key_off(.f7),
        0x0a => key_off(.f8),
        0x01 => key_off(.f9),
        0x09 => key_off(.f10),
        0x78 => key_off(.f11),
        0x07 => key_off(.f12),
        0x7e => key_off(.scroll_lock),

        else => log.warn("unexpected f0 {x}", .{b}),
    }
    return s_normal;
}

fn state_e0_f0(b: u8) State {
    switch (b) {
        0x11 => key_off(.right_alt),
        0x14 => key_off(.right_ctrl),
        0x4a => key_off(.num_pad_divide),
        0x5a => key_off(.enter),

        0x70 => key_off(.insert),
        0x71 => key_off(.delete),
        0x6b => key_off(.left_arrow),
        0x6c => key_off(.home),
        0x69 => key_off(.end),
        0x75 => key_off(.up_arrow),
        0x72 => key_off(.down_arrow),
        0x7d => key_off(.page_up),
        0x7a => key_off(.page_down),
        0x74 => key_off(.right_arrow),

        else => log.warn("unexpected e0 f0 {x}", .{b}),
    }
    return s_normal;
}

// TODO support for pause, print screen, see https://doc.lagout.org/science/0_Computer%20Science/0_Computer%20History/old-hardware/national/_appNotes/AN-0734.pdf

fn kb_irq_handler(ctx: *interrupts.CpuState) usize {
    const byte = ps2.get_data();

    // log.debug("keyboard IRQ: {x}", .{byte});
    on_byte(byte);

    return @intFromPtr(ctx);
}

pub fn initialize(is_aux: bool) void {
    log.debug("initializing on {s}", .{if (is_aux) "aux" else "main"});

    driver.aux = is_aux;
    driver.state = s_normal;

    // clear any remaining data in the port
    _ = ps2.maybe_get_data();

    interrupts.set_irq_handler(.keyboard, kb_irq_handler);
    pic.clear_mask(1);

    var ccb = ps2.get_controller_configuration();
    if (is_aux) {
        ccb.aux_disabled = false;
        ccb.aux_interrupt_enabled = true;
    } else {
        ccb.main_disabled = false;
        ccb.main_interrupt_enabled = true;
    }
    ps2.set_controller_configuration(ccb);
}
