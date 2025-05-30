const std = @import("std");
const log = std.log.scoped(.mouse);

const MOUSE_BUTTON_COUNT = 5;

pub const MouseUpdate = struct {
    buttons: [MOUSE_BUTTON_COUNT]bool,
    dx: i8,
    dy: i8,
    dv: i8,
    dh: i8,
};

pub const MouseState = struct {
    buttons: [MOUSE_BUTTON_COUNT]bool,
    x: usize,
    y: usize,
    x_minimum: usize,
    y_minimum: usize,
    x_maximum: usize,
    y_maximum: usize,

    // changes this frame
    button_down: [MOUSE_BUTTON_COUNT]bool,
    button_up: [MOUSE_BUTTON_COUNT]bool,
    horizontal_wheel: i8,
    vertical_wheel: i8,
};

pub var state: *MouseState = undefined;

pub fn initialize(allocator: std.mem.Allocator, width: usize, height: usize) !void {
    log.debug("initializing", .{});
    defer log.debug("done", .{});

    state = try allocator.create(MouseState);
    inline for (0..MOUSE_BUTTON_COUNT) |i| {
        state.buttons[i] = false;
        state.button_down[i] = false;
        state.button_up[i] = true;
    }
    state.x = width / 2;
    state.y = height / 2;
    state.x_minimum = 0;
    state.x_maximum = width - 1;
    state.y_minimum = 0;
    state.y_maximum = height - 1;
}

pub fn update(data: MouseUpdate) void {
    inline for (0..MOUSE_BUTTON_COUNT) |i| {
        const old = state.buttons[i];
        const new = data.buttons[i];

        state.buttons[i] = new;
        state.button_down[i] = !old and new;
        state.button_up[i] = old and !new;
    }

    state.x = update_position(state.x, state.x_minimum, state.x_maximum, data.dx);
    state.y = update_position(state.y, state.y_minimum, state.y_maximum, data.dy);
    state.vertical_wheel = data.dv;
    state.horizontal_wheel = data.dh;

    log.debug("update: [{s}{s}{s}{s}{s}] x={d} y={d} dv={d} dh={d}", .{
        if (state.buttons[0]) "1" else "_",
        if (state.buttons[1]) "2" else "_",
        if (state.buttons[2]) "3" else "_",
        if (state.buttons[3]) "4" else "_",
        if (state.buttons[4]) "5" else "_",
        state.x,
        state.y,
        state.vertical_wheel,
        state.horizontal_wheel,
    });
}

fn update_position(old: usize, min: usize, max: usize, delta: i8) usize {
    if (delta == 0) return old;

    var result: struct { usize, u1 } = undefined;
    if (delta < 0) {
        const cast: usize = @intCast(-delta);
        result = @subWithOverflow(old, cast);
    } else {
        const cast: usize = @intCast(delta);
        result = @addWithOverflow(old, cast);
    }

    return @min(@max(result[0], min), max);
}
