const fmt = @import("std").fmt;
const Writer = @import("std").io.Writer;

const console = @import("console.zig");
const utils = @import("utils.zig");

pub const LEDState = packed struct {
    scroll_lock: bool,
    number_lock: bool,
    caps_lock: bool,
    unused: u5,
};

pub const StatusRegister = packed struct {
    output_full: bool,
    input_full: bool,
    system_flag: bool,
    data_for_controller: bool,
    unused_4: bool,
    unused_5: bool,
    timeout_error: bool,
    parity_error: bool,

    const Self = @This();
    pub fn as_u8(self: Self) u8 {
        return @bitCast(self);
    }
};

const PS2_DATA_PORT: u16 = 0x60;
const PS2_COMMAND_PORT: u16 = 0x64;

pub fn report_status() void {
    const status: StatusRegister = @bitCast(utils.inb(PS2_COMMAND_PORT));

    console.printf("Keyboard Status Register:", .{});
    if (status.output_full) console.printf(" output_full", .{});
    if (status.input_full) console.printf(" input_full", .{});
    if (status.system_flag) console.printf(" system_flag", .{});
    if (status.data_for_controller) console.printf(" data_for_controller", .{});
    if (status.unused_4) console.printf(" unused_4", .{});
    if (status.unused_5) console.printf(" unused_5", .{});
    if (status.timeout_error) console.printf(" timeout_error", .{});
    if (status.parity_error) console.printf(" parity_error", .{});
    console.new_line();
}

pub fn set_leds(scroll_lock: bool, number_lock: bool, caps_lock: bool) void {
    utils.outb(PS2_COMMAND_PORT, 0xED);
    utils.outb(PS2_DATA_PORT, @bitCast(LEDState{ .scroll_lock = scroll_lock, .number_lock = number_lock, .caps_lock = caps_lock, .unused = 0 }));
}
