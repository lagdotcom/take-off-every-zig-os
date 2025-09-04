const std = @import("std");
const log = std.log.scoped(.hpet);

const acpi = @import("../common/acpi.zig");
const console = @import("console.zig");
const shell = @import("shell.zig");
const tools = @import("tools.zig");

const reg_offsets = struct {
    const GeneralCapabilitiesAndID = 0;
    const GeneralConfiguration = 0x10;
    const GeneralInterruptStatus = 0x20;
    const MainCounterValue = 0xf0;
    const Timer0ConfigurationAndCapability = 0x100;
    const Timer0ComparatorValue = 0x108;
    const Timer0FSBInterruptRoute = 0x110;
    const TimerBlockSize = 0x20;
};

var hpet: *acpi.HighPrecisionEventTimer = undefined;
var base_address: usize = 0;

const GeneralCapabilitiesAndID = packed struct {
    revision_id: u8,
    number_of_timers: u5,
    counter_size_64bit: bool,
    reserved: u1,
    legacy_replacement_route_capable: bool,
    vendor_id: u16,
    main_counter_tick_period: u32,
};

pub fn get_general_capabilities() GeneralCapabilitiesAndID {
    return @as(*GeneralCapabilitiesAndID, @ptrFromInt(base_address + reg_offsets.GeneralCapabilitiesAndID)).*;
}

const GeneralConfiguration = packed struct {
    enable: bool,
    supports_legacy_replacement: bool,
    reserved: u62,
};

pub fn get_general_configuration() GeneralConfiguration {
    return @as(*GeneralConfiguration, @ptrFromInt(base_address + reg_offsets.GeneralConfiguration)).*;
}

// each timer gets an enabled bit (top 32 are reserved)
pub fn get_general_interrupt_status() u64 {
    return @as(*u64, @ptrFromInt(base_address + reg_offsets.GeneralInterruptStatus)).*;
}

pub fn get_main_counter() u64 {
    return @as(*u64, @ptrFromInt(base_address + reg_offsets.MainCounterValue)).*;
}

const TimerConfig = packed struct {
    reserved_0: u1 = 0,
    interrupt_type: enum(u1) { edge = 0, level },
    interrupt_enable: bool,
    periodic: bool,
    supports_periodic: bool,
    supports_64bit: bool,
    set_accumulator: bool,
    reserved_7: u1 = 0,
    force_32bit: bool,
    io_apic_routing: u5,
    use_fsb_interrupt_mapping: bool,
    supports_fsb_interrupt_mapping: bool,
    reserved_16: u16,
    routing_capability: u32,
};

pub fn get_timer_config(index: usize) TimerConfig {
    return @as(*TimerConfig, @ptrFromInt(base_address + reg_offsets.Timer0ConfigurationAndCapability + index * reg_offsets.TimerBlockSize)).*;
}

pub fn get_timer_comparator(index: usize) u64 {
    return @as(*u64, @ptrFromInt(base_address + reg_offsets.Timer0ComparatorValue + index * reg_offsets.TimerBlockSize)).*;
}

pub fn get_timer_comparator_32(index: usize) u32 {
    return @as(*u32, @ptrFromInt(base_address + reg_offsets.Timer0ComparatorValue + index * reg_offsets.TimerBlockSize)).*;
}

fn shell_hpet(_: *shell.Context, _: []const u8) !void {
    console.printf_nl("HPET base address = {x}", .{base_address});

    // const raw: [*]const u8 = @ptrFromInt(base_address);
    // tools.hex_dump(console.printf_nl, raw[0..0x400]);

    const data = get_general_capabilities();
    tools.struct_dump(GeneralCapabilitiesAndID, console.printf_nl, &data);

    const config = get_general_configuration();
    tools.struct_dump(GeneralConfiguration, console.printf_nl, &config);

    for (0..data.number_of_timers + 1) |i| {
        const t0 = get_timer_config(i);
        tools.struct_dump(TimerConfig, console.printf_nl, &t0);
    }
}

pub fn initialize(acpi_entry: ?*acpi.HighPrecisionEventTimer) !void {
    log.debug("initializing", .{});
    defer log.debug("done", .{});

    if (acpi_entry) |e| {
        hpet = e;

        // TODO what if the address is a port?
        base_address = @intCast(e.address.address);

        try shell.add_command(.{
            .name = "hpet",
            .summary = "High Precision Event Timer info",
            .exec = shell_hpet,
        });
    }
}
