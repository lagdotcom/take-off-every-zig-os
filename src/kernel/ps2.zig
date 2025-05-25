const std = @import("std");
const log = std.log.scoped(.ps2);

const acpi = @import("../common/acpi.zig");
const console = @import("console.zig");
const drivers = @import("driver/ps2.zig");
const x86 = @import("../arch/x86.zig");

pub const LEDState = packed struct {
    scroll_lock: bool,
    number_lock: bool,
    caps_lock: bool,
    unused: u5,
};

pub const StatusRegister = packed struct {
    /// is data ready to be read?
    output_full: bool,

    /// is input buffer full?
    input_full: bool,

    /// was self-test successful?
    system_flag: bool,

    /// last write was a command
    data_for_controller: bool,

    keyboard_unlocked: bool,
    aux_full: bool,
    timeout_error: bool,
    parity_error: bool,
};

const ConfigByte = packed struct {
    main_interrupt_enabled: bool,
    aux_interrupt_enabled: bool,
    system_flag: bool,
    ignore_keyboard_lock: bool,
    main_disabled: bool,
    aux_disabled: bool,
    translate: bool,
    unused: bool,
};

const PS2_DATA_PORT: u16 = 0x60;
const PS2_STATUS_PORT: u16 = 0x64;
const PS2_COMMAND_PORT: u16 = 0x64;

const ControllerCommand = enum(u8) {
    read_controller_configuration = 0x20,
    write_controller_configuration = 0x60,

    disable_aux = 0xa7,
    enable_aux = 0xa8,
    interface_test_aux = 0xa9,
    self_test = 0xaa,
    interface_test = 0xab,
    diagnostic_dump = 0xac,
    disable_main = 0xad,
    enable_main = 0xae,

    read_input = 0xc0,
    read_output = 0xd0,
    write_output = 0xd1,

    write_main_output = 0xd2,
    write_aux_output = 0xd3,
    write_aux_input = 0xd4,

    read_test_results = 0xe0,
    system_reset = 0xfe,
};

const DeviceCommand = enum(u8) {
    set_leds = 0xed,
    echo = 0xee,
    scan_code_set = 0xf0,
    identify = 0xf2,
    typematic = 0xf3,
    enable_scanning = 0xf4,
    disable_scanning = 0xf5,
    set_default_parameters = 0xf6,
    // resend_last_byte = 0xfe,
    reset = 0xff,

    // these only work in scan code set 3
    set_all_typematic_only = 0xf7,
    set_all_make_release = 0xf8,
    set_all_make_only = 0xf9,
    set_all_keys_typematic_make_release = 0xfa,
    set_key_typematic_only = 0xfb,
    set_key_make_release = 0xfc,
    set_key_make_only = 0xfd,
};

const Reply = enum(u8) {
    err = 0,
    self_test_passed = 0xaa,
    echo = 0xee,
    ack = 0xfa,
    self_test_failed = 0xfc,
    self_test_failed_2 = 0xfd,
    resend = 0xfe,
    err_2 = 0xff,
};

fn debug_status(status: StatusRegister) void {
    log.debug("status:{s}{s}{s}{s}{s}{s}{s}{s}", .{
        if (status.output_full) " output_full" else "",
        if (status.input_full) " input_full" else "",
        if (status.system_flag) " system_flag" else "",
        if (status.data_for_controller) " data_for_controller" else "",
        if (status.keyboard_unlocked) " keyboard_unlocked" else "",
        if (status.aux_full) " aux_full" else "",
        if (status.timeout_error) " timeout_error" else "",
        if (status.parity_error) " parity_error" else "",
    });
}

fn get_status() StatusRegister {
    const status: StatusRegister = @bitCast(x86.inb(PS2_STATUS_PORT));
    // debug_status(status);
    return status;
}

fn debug_configuration(ccb: ConfigByte, prefix: []const u8) void {
    log.debug("{s} config:{s}{s}{s}{s}{s}{s}{s}", .{
        prefix,
        if (ccb.main_interrupt_enabled) " main_interrupt_enabled" else "",
        if (ccb.aux_interrupt_enabled) " aux_interrupt_enabled" else "",
        if (ccb.system_flag) " system_flag" else "",
        if (ccb.ignore_keyboard_lock) " ignore_keyboard_lock" else "",
        if (ccb.main_disabled) " main_disabled" else "",
        if (ccb.aux_disabled) " aux_disabled" else "",
        if (ccb.translate) " translate" else "",
    });
}

pub fn get_controller_configuration() ConfigByte {
    send_command(.read_controller_configuration);
    const ccb: ConfigByte = @bitCast(get_data());
    debug_configuration(ccb, "get");
    return ccb;
}

pub fn set_controller_configuration(ccb: ConfigByte) void {
    send_command(.write_controller_configuration);
    send_data(@bitCast(ccb));
    debug_configuration(ccb, "set");
}

const io_timeout_attempts = 10;

pub fn send_command(cmd: ControllerCommand) void {
    log.debug("send_command: {s}", .{@tagName(cmd)});

    x86.io_wait();
    for (0..io_timeout_attempts) |_| {
        if (!get_status().input_full)
            return x86.outb(PS2_COMMAND_PORT, @intFromEnum(cmd));
    }

    log.warn("timeout on send_command: {s}", .{@tagName(cmd)});
}

pub fn send_device_command(cmd: DeviceCommand) void {
    log.debug("send_device_command: {s}", .{@tagName(cmd)});

    x86.io_wait();
    for (0..io_timeout_attempts) |_| {
        if (!get_status().input_full)
            return x86.outb(PS2_DATA_PORT, @intFromEnum(cmd));
    }

    log.debug("timeout on send_device_command: {s}", .{@tagName(cmd)});
}

pub fn send_data(byte: u8) void {
    log.debug("send_data: {d}/{x}", .{ byte, byte });

    x86.io_wait();
    for (0..io_timeout_attempts) |_| {
        if (!get_status().input_full)
            return x86.outb(PS2_DATA_PORT, byte);
    }

    log.warn("timeout on send_data: {d}/{x}", .{ byte, byte });
}

pub fn get_data() u8 {
    x86.io_wait();
    for (0..io_timeout_attempts) |_| {
        if (get_status().output_full) {
            x86.io_wait();
            const value = x86.inb(PS2_DATA_PORT);
            log.debug("get_reply_byte: {d}/{x}", .{ value, value });
            return value;
        }
    }

    log.warn("timeout on get_reply_byte()", .{});
    return 0;
}

pub fn maybe_get_data() ?u8 {
    for (0..io_timeout_attempts) |_| {
        if (get_status().output_full) {
            x86.io_wait();
            return x86.inb(PS2_DATA_PORT);
        }
    }

    return null;
}

pub fn get_reply() Reply {
    return @enumFromInt(get_data());
}

fn send_command_and_response(cmd: ControllerCommand) Reply {
    send_command(cmd);
    var reply = get_reply();
    if (reply != .resend) return reply;

    for (0..3) |_| {
        reply = get_reply();
        if (reply != .resend) return reply;
    }

    return .resend;
}

pub fn set_leds(scroll_lock: bool, number_lock: bool, caps_lock: bool) void {
    send_command(.set_leds);
    send_data(@bitCast(LEDState{ .scroll_lock = scroll_lock, .number_lock = number_lock, .caps_lock = caps_lock, .unused = 0 }));
}

fn has_8042_controller(maybe_fadt: ?*acpi.FixedACPIDescriptionTable) bool {
    if (maybe_fadt) |fadt| {
        if (fadt.header.revision < 2) {
            // FADT v1.x reserved IAPC_BOOT_ARCH. There's an 8042.
            return true;
        }

        // Believe whatever the FADT says.
        return fadt.ia_pc_boot_arch.has_8042;
    }

    // No ACPI support? There's an 8042.
    return true;
}

pub const DeviceID = [2]u8;

fn identify_device(id: DeviceID) []const u8 {
    return switch (id[0]) {
        0xff => "Ancient AT keyboard",
        0x00 => "Standard PS/2 mouse",
        0x03 => "Mouse with scroll wheel",
        0x04 => "5-button mouse",
        0xAB => switch (id[1]) {
            0x83 => "MF2 keyboard",
            0xC1 => "MF2 keyboard",
            0x84 => "ThinkPad/Spacesaver keyboard",
            0x85 => "NCD N-97/122-Key Host Connected keyboard",
            0x86 => "122-Key keyboard",
            0x90 => "Japanese 'G' keyboard",
            0x91 => "Japanese 'P' keyboard",
            0x92 => "Japanese 'A' keyboard",
            else => "Unknown keyboard",
        },
        0xAC => switch (id[1]) {
            0xA1 => "NCD Sun layout keyboard",
            else => "Unknown keyboard",
        },
        else => "Unknown device",
    };
}

fn self_test() bool {
    for (0..4) |i| {
        send_command(.self_test);
        const rep = get_data();
        if (rep != 0x55) {
            log.warn("self test #{d}: {x}, expected 55", .{ i, rep });
            continue;
        }

        return true;
    }

    return false;
}

pub const PS2Driver = struct {
    attach: *const fn (allocator: std.mem.Allocator, is_aux: bool) void,
};
const PS2DriverMap = std.AutoHashMap(DeviceID, *const PS2Driver);
pub var ps2_driver_map: PS2DriverMap = undefined;

pub fn add_driver(id: DeviceID, driver: *const PS2Driver) !void {
    try ps2_driver_map.put(id, driver);
}

fn start_driver(allocator: std.mem.Allocator, id: DeviceID, is_aux: bool) !void {
    if (ps2_driver_map.get(id)) |driver| {
        log.debug("attempting to start driver for {x:0>2}{x:0>2}", .{ id[0], id[1] });
        driver.attach(allocator, is_aux);
    } else log.warn("no driver found for {x:0>2}{x:0>2} ({s})", .{ id[0], id[1], identify_device(id) });
}

pub fn initialize(allocator: std.mem.Allocator, maybe_fadt: ?*acpi.FixedACPIDescriptionTable) !void {
    log.debug("initializing", .{});
    defer log.debug("done", .{});

    // Step 2: Determine if the PS/2 Controller Exists
    if (!has_8042_controller(maybe_fadt)) {
        log.warn("No 8042 present, not sure how to continue.", .{});
        return;
    }

    // ok, fine, let's initialize things
    ps2_driver_map = PS2DriverMap.init(allocator);
    try drivers.initialize();

    // Step 3: Disable Devices
    send_command(.disable_main);
    send_command(.disable_aux);

    // Step 4: Flush The Output Buffer
    _ = x86.inb(PS2_DATA_PORT);

    // Step 5: Set the Controller Configuration Byte
    {
        var ccb = get_controller_configuration();
        ccb.main_interrupt_enabled = false;
        ccb.aux_interrupt_enabled = false;
        ccb.translate = false;
        ccb.main_disabled = false;

        set_controller_configuration(ccb);
    }

    // Step 6: Perform Controller Self Test
    if (!self_test()) return;

    // Step 7: Determine If There Are 2 Channels
    var has_aux = false;
    {
        send_command(.enable_aux);

        var ccb = get_controller_configuration();
        if (!ccb.aux_disabled) {
            has_aux = true;
            log.info("found 2 channels", .{});

            send_command(.disable_aux);
            ccb = get_controller_configuration();

            ccb.aux_interrupt_enabled = false;
            ccb.aux_disabled = false;
            set_controller_configuration(ccb);
        }
    }

    // Step 8: Perform Interface Tests
    var main_ok = false;
    var aux_ok = false;
    {
        send_command(.interface_test);
        const reply = get_data();
        if (reply != 0) {
            log.debug("interface test: {x}, expected 0", .{reply});
        } else main_ok = true;

        if (has_aux) {
            send_command(.interface_test_aux);
            const reply_aux = get_data();
            if (reply_aux != 0) {
                log.debug("interface test aux: {x}, expected 0", .{reply_aux});
            } else aux_ok = true;
        }
    }

    if (!main_ok and !aux_ok) {
        log.info("no working devices to enable", .{});
        return;
    }

    // try an echo
    {
        send_device_command(.echo);
        const reply = get_data();
        if (reply == 0xee) {
            log.debug("echo ok", .{});
        } else {
            log.debug("echo: got {x}, expected ee", .{reply});
        }
    }

    // Step 9: Enable Devices
    {
        var ccb = get_controller_configuration();

        if (main_ok) {
            send_command(.enable_main);
            ccb.main_interrupt_enabled = true;
        }
        if (aux_ok) {
            send_command(.enable_aux);
            ccb.aux_interrupt_enabled = true;
        }

        set_controller_configuration(ccb);
    }

    // Step 10: Reset Devices
    var main_device_id: DeviceID = .{ 0xff, 0xff };
    if (main_ok) {
        send_device_command(.reset);

        const response_1 = get_reply();
        if (response_1 != .ack) {
            log.warn("main reset: got {s}, expected ack", .{@tagName(response_1)});
        } else {
            const response_2 = get_reply();
            if (response_2 != .self_test_passed) {
                log.warn("main reset: got {s}, expected self_test_passed", .{@tagName(response_2)});
            } else {
                if (maybe_get_data()) |b| {
                    main_device_id[0] = b;
                    if (maybe_get_data()) |b2| main_device_id[1] = b2;
                }
            }
        }
    }

    var aux_device_id: DeviceID = .{ 0xff, 0xff };
    if (aux_ok) {
        send_command(.write_aux_input);
        send_device_command(.reset);

        const response_1 = get_reply();
        if (response_1 != .ack) {
            log.warn("aux reset: got {s}, expected ack", .{@tagName(response_1)});
        } else {
            const response_2 = get_reply();
            if (response_2 != .self_test_passed) {
                log.warn("aux reset: got {s}, expected self_test_passed", .{@tagName(response_2)});
            } else {
                if (maybe_get_data()) |b| {
                    aux_device_id[0] = b;
                    if (maybe_get_data()) |b2| aux_device_id[1] = b2;
                }
            }
        }
    }

    // get device IDs if we didn't already
    if (main_device_id[0] == 0xff and main_device_id[1] == 0xff) {
        send_device_command(.disable_scanning);

        const response_1 = get_reply();
        if (response_1 != .ack) {
            log.warn("get id: got {s}, expected ack", .{@tagName(response_1)});
        } else {
            send_device_command(.identify);

            const response_2 = get_reply();
            if (response_2 != .ack) {
                log.warn("get id: got {s}, expected ack", .{@tagName(response_2)});
            } else {
                if (maybe_get_data()) |b| main_device_id[0] = b;
                if (maybe_get_data()) |b| main_device_id[1] = b;

                // send_device_command(.enable_scanning);
            }
        }
    }
    if (aux_ok and aux_device_id[0] == 0xff and aux_device_id[1] == 0xff) {
        send_command(.write_aux_input);
        send_device_command(.disable_scanning);

        const response_1 = get_reply();
        if (response_1 != .ack) {
            log.warn("get aux id: got {s}, expected ack", .{@tagName(response_1)});
        } else {
            send_command(.write_aux_input);
            send_device_command(.identify);

            const response_2 = get_reply();
            if (response_2 != .ack) {
                log.warn("get aux id: got {s}, expected ack", .{@tagName(response_2)});
            } else {
                if (maybe_get_data()) |b| aux_device_id[0] = b;
                if (maybe_get_data()) |b| aux_device_id[1] = b;

                // send_command(.write_aux_input);
                // send_device_command(.enable_scanning);
            }
        }
    }

    try start_driver(allocator, main_device_id, false);
    try start_driver(allocator, aux_device_id, true);

    // // get current scan code set
    // {
    //     send_device_command(.scan_code_set);
    //     send_data(0);

    //     const reply = get_reply();
    //     if (reply != .ack) {
    //         log.debug("get current scan code set: got {s}, expected ack", .{@tagName(reply)});
    //     } else {
    //         const set = get_reply_byte();
    //         log.debug("get current scan code set: set {d}", .{set});
    //     }
    // }
}
