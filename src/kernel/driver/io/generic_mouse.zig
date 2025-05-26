const std = @import("std");
const log = std.log.scoped(.generic_mouse);

const interrupts = @import("../../interrupts.zig");
const pic = @import("../../pic.zig");
const pit = @import("../../pit.zig");
const ps2 = @import("../../ps2.zig");

const Command = enum(u8) {
    reset = 0xff,
    resend = 0xfe,
    set_defaults = 0xf6,
    disable_packet_streaming = 0xf5,
    enable_packet_streaming = 0xf4,
    set_sample_rate = 0xf3,
    get_mouse_id = 0xf2,
    request_single_packet = 0xeb,
    status_request = 0xe9,
    set_resolution = 0xe8,
};

const Status = packed struct {
    right: bool,
    middle: bool,
    left: bool,
    reserved_3: u1,
    scaling: enum(u1) { linear = 0, non_linear },
    enable: bool,
    mode: enum(u1) { stream = 0, remote },
    reserved_7: u1,
};

const Resolution = enum(u8) {
    _1 = 0,
    _2,
    _4,
    _8,
};

const PacketByte1 = packed struct {
    left: bool,
    right: bool,
    middle: bool,
    reserved_3: bool,
    x_is_negative: bool,
    y_is_negative: bool,
    x_overflow: bool,
    y_overflow: bool,
};

const PacketByte4 = packed struct {
    wheel: enum(u4) {
        none = 0,
        vertical_up,
        horizontal_right,
        _3,
        _4,
        _5,
        _6,
        _7,
        _8,
        _9,
        _a,
        _b,
        _c,
        _d,
        horizontal_left = 14,
        vertical_down = 15,
    } = .none,
    btn4: bool = false,
    btn5: bool = false,
    reserved: u2 = 0,
};

const Packet = struct {
    b1: PacketByte1,
    delta_x: i8,
    delta_y: i8,
    delta_z: i8 = 0,
    b4: PacketByte4 = .{},
};

pub const id = ps2.DeviceID{ 0x00, 0xff };
pub const ps2_driver = ps2.PS2Driver{ .attach = attach };

pub fn initialize() !void {
    try ps2.add_driver(id, &ps2_driver);
}

var aux: bool = undefined;
var packet_size: enum(u2) { three, four_simple, four_complex } = undefined;
var mouse_id: u8 = undefined;

fn attach(_: std.mem.Allocator, is_aux: bool) void {
    log.debug("initializing on {s}", .{if (is_aux) "aux" else "main"});

    aux = is_aux;
    packet_size = .three;
    send_command(.reset);

    while (true) {
        const sent = ps2.maybe_get_data();
        if (sent) |value| {
            log.debug("after reset: {x}", .{value});
            if (value == 0xaa) break;
        } else {
            log.warn("did not get 0xaa after reset, abandoning", .{});
            return;
        }
    }

    // this should always be 0
    mouse_id = ps2.get_data();

    activate_scroll_wheel();
    if (packet_size == .four_simple) activate_more_buttons();

    report_status();

    send_command_expect_ack(.enable_packet_streaming);
    interrupts.set_irq_handler(.mouse, mouse_irq_handler, "generic_mouse_irq_handler");
    // interrupts.set_irq_handler(.mouse, debug_handler, "generic_mouse_debug_handler");
    pic.clear_mask(.mouse);

    // pit.enable(30, mouse_pit_handler, "generic_mouse_pit_handler");
}

fn activate_scroll_wheel() void {
    set_sample_rate(200);
    set_sample_rate(100);
    set_sample_rate(80);

    get_mouse_id();
    if (mouse_id == 3) {
        log.debug("successfully activated mouse wheel", .{});
        packet_size = .four_simple;
    }
}

fn activate_more_buttons() void {
    set_sample_rate(200);
    set_sample_rate(200);
    set_sample_rate(80);

    get_mouse_id();
    if (mouse_id == 4) {
        log.debug("successfully activated buttons 4/5", .{});
        packet_size = .four_complex;
    }
}

fn send_command(cmd: Command) void {
    if (aux) ps2.send_command(.write_aux_input);
    ps2.send_data(@intFromEnum(cmd));
}

fn send_command_expect_ack(cmd: Command) void {
    send_command(cmd);
    const reply = ps2.get_reply();
    if (reply != .ack) log.debug("expected {s} => ack, got {s}", .{ @tagName(cmd), @tagName(reply) });
}

fn send_data_expect_ack(data: u8) void {
    if (aux) ps2.send_command(.write_aux_input);
    ps2.send_data(data);
    const reply = ps2.get_reply();
    if (reply != .ack) log.debug("expected ack, got {s}", .{@tagName(reply)});
}

fn set_sample_rate(rate: u8) void {
    send_command_expect_ack(.set_sample_rate);
    send_data_expect_ack(rate);
}

fn get_mouse_id() void {
    send_command_expect_ack(.get_mouse_id);
    mouse_id = ps2.get_data();
}

fn mouse_irq_handler(ctx: *interrupts.CpuState) usize {
    if (ps2.get_status().output_full) {
        const p = read_mouse_packet();
        debug_mouse_packet(p);
    }

    return @intFromPtr(ctx);
}

fn debug_handler(ctx: *interrupts.CpuState) usize {
    log.debug("irq", .{});
    while (ps2.get_status().output_full) {
        const byte = ps2.get_data();
        log.debug("byte: {x}", .{byte});
    }

    return @intFromPtr(ctx);
}

fn mouse_pit_handler(ctx: *interrupts.CpuState) usize {
    send_command_expect_ack(.request_single_packet);
    const p = read_mouse_packet();
    if (p.delta_x != 0 or p.delta_y != 0 or p.delta_z != 0 or p.b4.wheel != .none) debug_mouse_packet(p);

    return @intFromPtr(ctx);
}

fn read_mouse_packet() Packet {
    const b1: PacketByte1 = @bitCast(ps2.get_data());
    const delta_x: i8 = @bitCast(ps2.get_data());
    const delta_y: i8 = @bitCast(ps2.get_data());

    return switch (packet_size) {
        .three => .{
            .b1 = b1,
            .delta_x = delta_x,
            .delta_y = delta_y,
        },
        .four_simple => .{
            .b1 = b1,
            .delta_x = delta_x,
            .delta_y = delta_y,
            .delta_z = @bitCast(ps2.get_data()),
        },
        .four_complex => .{
            .b1 = b1,
            .delta_x = delta_x,
            .delta_y = delta_y,
            .b4 = @bitCast(ps2.get_data()),
        },
    };
}

fn debug_mouse_packet(p: Packet) void {
    log.debug("{s}{s}{s}{s}{s} {s}{s}{s}{s} x:{d:3} y:{d:3} z:{d:3} wheel:{s}", .{
        if (p.b1.left) "L" else " ",
        if (p.b1.right) "R" else " ",
        if (p.b1.middle) "M" else " ",
        if (p.b4.btn4) "4" else " ",
        if (p.b4.btn5) "5" else " ",

        if (p.b1.x_is_negative) "XNE" else "   ",
        if (p.b1.y_is_negative) "YNE" else "   ",
        if (p.b1.x_overflow) "XOV" else "   ",
        if (p.b1.y_overflow) "YOV" else "   ",

        p.delta_x,
        p.delta_y,
        p.delta_z,
        @tagName(p.b4.wheel),
    });
}

fn report_status() void {
    send_command_expect_ack(.status_request);

    const status: Status = @bitCast(ps2.get_data());
    const resolution = ps2.get_data();
    const sample_rate = ps2.get_data();

    log.debug("status: {s}{s}{s} scaling={s} reporting={s} mode={s} / res={d} rate={d}", .{
        if (status.left) "L" else " ",
        if (status.middle) "M" else " ",
        if (status.right) "R" else " ",
        if (status.scaling == .linear) "1:1" else "2:1",
        if (status.enable) "enabled" else "disabled",
        @tagName(status.mode),
        resolution,
        sample_rate,
    });
}
