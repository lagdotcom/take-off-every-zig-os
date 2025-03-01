const common = @import("common.zig");

const USBInterfaceCommand = packed struct {
    io_space_access_enable: bool,
    memory_access_enable: bool = false,
    bus_master_enable: bool,
    special_cycle_enable: bool = false,
    postable_memory_write_enable: bool = false,
    reserved_5: u4 = 0,
    fast_back_to_back_enable: bool = false,
    reserved_10: u6 = 0,
};

const USBInterfaceStatus = packed struct {
    reserved_0: u7 = 0,
    fast_back_to_back: bool = true,
    perr_response: bool = false,
    devsel_timing_status: u2 = 1,
    signalled_target_abort_status: bool,
    received_target_abort_status: bool,
    master_abort_status: bool,
    signalled_serr_status: bool = false,
    detected_parity_error: bool = false,
};

const USBIOSpaceBaseAddress = packed struct {
    resource_type_indicator: bool = true,
    reserved_1: u4 = 0,
    base_address: u11, // treat first two bytes as address, mask off first bit
    reserved_16: u16 = 0,
};

const USBReleaseNumber = enum(u8) {
    pre_release_1_0 = 0,
    release_1_0 = 2,
};

const USBMiscellaneousStatus = packed struct {
    usb_clock_selection: enum(u1) { @"48_mhz" = 0, @"24_mhz" = 1 },
    reserved: u15,
};

const USBLegacySupport = packed struct {
    trap_smi_on_60h_read_enable: bool,
    trap_smi_on_60h_write_enable: bool,
    trap_smi_on_64h_read_enable: bool,
    trap_smi_on_64h_write_enable: bool,
    trap_smi_on_irq_enable: bool,
    a20gate_pass_through_enable: bool,
    pass_through_status: bool,
    smi_at_end_of_pass_through_enable: bool,
    trap_by_60h_read_status: bool,
    trap_by_60h_write_status: bool,
    trap_by_64h_read_status: bool,
    trap_by_64h_write_status: bool,
    usb_irq_status: bool,
    usb_pirq_enable: bool,
    reserved: u1,
    end_of_a20gate_pass_through_status: bool,
};

// PIIX3 only
const USBInterfaceConfig = extern struct {
    vendor_id: u16, // 8086
    device_id: u16, // 7020
    command: USBInterfaceCommand,
    status: USBInterfaceStatus,
    revision_id: u8,
    class_code: [3]u8, // 00 03 0c
    reserved_0c: u8,
    latency_timer: common.MasterLatencyTimer,
    header_type: u8, // 00
    reserved_0f: [17]u8,
    io_space_base_address: USBIOSpaceBaseAddress,
    reserved_24: [24]u8,
    interrupt_line: u8, // ignored
    interrupt_pin: u8, // hard wired to PIRQD#
    reserved_3e: [34]u8,
    serial_bus_release_number: USBReleaseNumber,
    reserved_61: [9]u8,
    miscellaneous_status: USBMiscellaneousStatus,
    reserved_6c: [83]u8,
    legacy_support: USBLegacySupport,
    // reserved_c2: [62]u8,
};
