const std = @import("std");
const log = std.log.scoped(.acpi);

const kernel = @import("kernel.zig");

pub const RSDP_v1 = extern struct {
    signature: [8]u8,
    checksum: u8,
    oem_id: [6]u8,
    revision: u8,
    rsdt_address: u32,
};

pub const RSDP_v2 = extern struct {
    v1: RSDP_v1,
    length: u32,
    xsdt_address: u64,
    extended_checksum: u8,
    reserved: [3]u8,
};

pub const DescriptionHeader = extern struct {
    signature: [4]u8,
    length: u32,
    revision: u8,
    checksum: u8,
    oem_id: [6]u8,
    oem_table_id: [8]u8,
    oem_revision: u32,
    creator_id: [4]u8,
    creator_revision: u32,
};

pub const rsdt_signature = "RSDT";

pub const RSDT = struct {
    header: *DescriptionHeader,
    entries: []u32,
};

pub fn read_rsdt(pointer: usize) !RSDT {
    const header: *DescriptionHeader = @ptrFromInt(pointer);

    if (!std.mem.eql(u8, &header.signature, "RSD PTR ")) return error.InvalidSignature;
    if (header.revision != 1) return error.InvalidRevision;

    const entry_count: usize = (header.length - @sizeOf(DescriptionHeader)) / @sizeOf(u32);
    const u32_pointer = @as([*]u32, @ptrFromInt(pointer + @sizeOf(DescriptionHeader)));
    const entries = u32_pointer[0..entry_count];

    // TODO checksum

    return .{ .header = header, .entries = entries };
}

pub const XSDT = struct {
    header: *DescriptionHeader,
    entries: []u64,
};

pub fn read_xsdt(pointer: usize) !XSDT {
    const header: *DescriptionHeader = @ptrFromInt(pointer);

    if (!std.mem.eql(u8, &header.signature, "XSDT")) return error.InvalidSignature;
    if (header.revision != 1) return error.InvalidRevision;

    const entry_count: usize = (header.length - @sizeOf(DescriptionHeader)) / @sizeOf(u64);
    const u64_pointer = @as([*]u64, @ptrFromInt(pointer + @sizeOf(DescriptionHeader)));
    const entries = u64_pointer[0..entry_count];

    // TODO checksum

    return .{ .header = header, .entries = entries };
}

const AddressSpace = enum(u8) {
    system_memory = 0,
    system_io,
    pci_configuration,
    embedded_controller,
    smbus,
    system_cmos,
    pci_bar_target,
    ipmi,
    gpio,
    generic_serial_bus,
    platform_communications_channel,
    functional_fixed_hardware = 0x7f,
    _,
};

const AccessSize = enum(u8) {
    undefined = 0,
    byte,
    word,
    dword,
    qword,
    _,
};

pub const GenericAddressStructure = extern struct {
    address_space_id: AddressSpace,
    register_bit_width: u8,
    register_bit_offset: u8,
    access_size: AccessSize,
    address: u64,
};

const MADTFlags = packed struct {
    pc_at_compatible: bool,
    reserved: u31,
};

pub const MultipleAPICDescriptionTable = extern struct {
    header: DescriptionHeader,
    local_interrupt_controller_address: u32,
    flags: MADTFlags,
    // TODO
    // interrupt_controller_structure: []InterruptControllerStructure,
};

pub const BootErrorRecordTable = extern struct {
    header: DescriptionHeader,
    boot_error_region_length: u32,
    boot_error_region: u64,
};

const OrientationOffset = enum(u2) {
    none = 0,
    _90_degrees = 1,
    _190_degrees = 2,
    _270_degrees = 3,
};

const BGRTStatus = packed struct {
    displayed: bool,
    orientation_offset: OrientationOffset,
    reserved: u5,
};

pub const BootGraphicsResourceTable = extern struct {
    header: DescriptionHeader,
    version: u16,
    status: BGRTStatus,
    image_type: enum(u8) { bitmap = 0, _ },
    image_address: u64,
    image_offset_x: u32,
    image_offset_y: u32,
};

const PreferredPMProfile = enum(u8) {
    unspecified = 0,
    desktop,
    mobile,
    workstation,
    enterprise_server,
    soho_server,
    appliance_pc,
    performance_server,
    tablet,
    _,
};

const FACPIntelBootArchitectureFlags = packed struct {
    legacy_devices: bool,
    has_8042: bool,
    vga_not_present: bool,
    msi_not_supported: bool,
    pcie_aspm_controls: bool,
    cmos_rtc_not_present: bool,
    reserved: u10,
};

const FACPARMBootArchitectureFlags = packed struct {
    pcsi_compliant: bool,
    psci_use_hvc: bool,
    reserved: u14,
};

const FACPFeatureFlags = packed struct {
    wbinvd: bool,
    wbinvd_flush: bool,
    proc_c1: bool,
    p_lvl2_up: bool,
    pwr_button: bool,
    slp_button: bool,
    fix_rtc: bool,
    rtc_s4: bool,
    tmr_val_ext: bool,
    dck_cap: bool,
    reset_reg_sup: bool,
    sealed_case: bool,
    headless: bool,
    cpu_sw_slp: bool,
    pci_exp_wak: bool,
    use_platform_clock: bool,
    s4_rtc_sts_valid: bool,
    remote_power_on_capable: bool,
    force_apic_cluster_model: bool,
    force_apic_physical_destination_mode: bool,
    hw_reduced_acpi: bool,
    low_power_s0_idle_capable: bool,
    reserved: u10,
};

pub const FixedACPIDescriptionTable = extern struct {
    header: DescriptionHeader,
    firmware_ctrl: u32,
    dsdt: u32,
    int_model: u8,
    preferred_pm_profile: PreferredPMProfile,
    sci_interrupt: u16,
    smi_cmd: u32,
    acpi_enable: u8,
    acpi_disable: u8,
    s4bios_req: u8,
    pstate_cnt: u8,
    pm1a_evt_blk: u32,
    pm1b_evt_blk: u32,
    pm1a_cnt_blk: u32,
    pm1b_cnt_blk: u32,
    pm2_cnt_blk: u32,
    pm_tmr_blk: u32,
    gpe0_blk: u32,
    gpe1_blk: u32,
    pm1_evt_len: u8,
    pm1_cnt_len: u8,
    pm2_cnt_len: u8,
    pm_tmr_len: u8,
    gpe0_blk_len: u8,
    gpe1_blk_len: u8,
    gpe1_base: u8,
    cst_cnt: u8,
    p_lvl2_lat: u16,
    p_lvl3_lat: u16,
    flush_size: u16,
    flush_stride: u16,
    duty_offset: u8,
    duty_width: u8,
    day_alrm: u8,
    mon_alrm: u8,
    century: u8,
    ia_pc_boot_arch: FACPIntelBootArchitectureFlags align(1),
    reserved_2: u8 align(1),
    flags: FACPFeatureFlags align(1),
    reset_reg: GenericAddressStructure align(1),
    reset_value: u8 align(1),
    arm_boot_arch: FACPARMBootArchitectureFlags align(1),
    fadt_minor_version: packed struct { minor: u4, errata: u4 } align(1),
    x_firmware_ctrl: u64 align(1),
    x_dsdt: u64,
    x_pm1a_evt_blk: GenericAddressStructure,
    x_pm1b_evt_blk: GenericAddressStructure,
    x_pm1a_cnt_blk: GenericAddressStructure,
    x_pm1b_cnt_blk: GenericAddressStructure,
    x_pm2_cnt_blk: GenericAddressStructure,
    x_pm_tmr_blk: GenericAddressStructure,
    x_gpe0_blk: GenericAddressStructure,
    x_gpe1_blk: GenericAddressStructure,
    sleep_control_reg: GenericAddressStructure,
    sleep_status_reg: GenericAddressStructure,
    hypervisor_vendor_identity: [8]u8,
};

pub const ACPITable = union(enum) {
    madt: *MultipleAPICDescriptionTable,
    bert: *BootErrorRecordTable,
    bgrt: *BootGraphicsResourceTable,
    fadt: *FixedACPIDescriptionTable,
    unknown: *DescriptionHeader,
};

fn read_acpi_table(ptr: usize) ACPITable {
    const header: *DescriptionHeader = @ptrFromInt(ptr);

    if (std.mem.eql(u8, &header.signature, "APIC")) {
        return .{ .madt = @ptrFromInt(ptr) };
    } else if (std.mem.eql(u8, &header.signature, "BERT")) {
        return .{ .bert = @ptrFromInt(ptr) };
    } else if (std.mem.eql(u8, &header.signature, "BGRT")) {
        return .{ .bgrt = @ptrFromInt(ptr) };
    } else if (std.mem.eql(u8, &header.signature, "FACP")) {
        return .{ .fadt = @ptrFromInt(ptr) };
    }

    return .{ .unknown = header };
}

pub fn read_acpi_tables(pointers: []usize) ![]ACPITable {
    const tables: []ACPITable = try kernel.allocator.alloc(ACPITable, pointers.len);

    for (pointers, 0..) |ptr, i| tables[i] = read_acpi_table(ptr);

    return tables;
}

const FACSFeatureFlags = extern struct {
    s4bios_req: bool,
    _64bit_wake: bool,
    reserved: u30,
};

const FACSOSPMFeatureFlags = extern struct {
    _64bit_wake: bool,
    reserved: u31,
};

pub const FirmwareACPIControlStructure = extern struct {
    signature: [4]u8,
    length: u32,
    hardware_signature: u32,
    firmware_waking_vector: u32,
    global_lock: u32,
    flags: FACSFeatureFlags,
    x_firmware_waking_vector: u64,
    version: u8,
    reserved: [3]u8,
    ospm_flags: FACSOSPMFeatureFlags,
    reserved_2: [24]u8,
};
