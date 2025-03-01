const PCIBridgeCommand = packed struct {
    io_space_access_enable: bool = true,
    memory_access_enable: bool = true,
    bus_master_enable: bool = true,
    special_cycle_enable: bool,
    postable_memory_write_enable: bool = false,
    reserved_5: u3 = 0,
    serr_enable: bool, // PIIX3 only
    fast_back_to_back_enable: bool = false,
    reserved_10: u6 = 0,
};

const PCIBridgeStatus = packed struct {
    reserved_0: u7 = 0,
    fast_back_to_back: bool,
    perr_response: bool = false,
    devsel_timing_status: u2 = 1,
    signalled_target_abort_status: bool,
    received_target_abort_status: bool,
    master_abort_status: bool,
    signalled_serr_status: bool, // PIIX3 only
    detected_parity_error: bool = false,
};

const PCIIORecoveryTimer = packed struct {
    @"16_bit_io_recovery_times": enum(u2) {
        @"4" = 0,
        @"1",
        @"2",
        @"3",
    },
    @"16_bit_io_recovery_enable": bool,
    @"8_bit_io_recovery_times": enum(u3) {
        @"8" = 0,
        @"1",
        @"2",
        @"3",
        @"4",
        @"5",
        @"6",
        @"7",
    },
    @"8_bit_io_recovery_enable": bool,
    dma_reserved_page_register_aliasing_control: bool,
};

const PCIXBusChipSelect = packed struct {
    rtc_address_location_enable: bool,
    keyboard_controller_address_location_enable: bool,
    bioscs_write_protect_enable: bool,
    reserved_3: u1 = 0,
    @"irq12/m_mouse_function_enable": bool,
    coprocessor_error_function_enable: bool,
    lower_bios_enable: bool,
    extended_bios_enable: bool,
    apic_chip_select: bool, // PIIX3 only
    reserved_9: u7 = 0,
};

const PCIPIRQRouteControl = packed struct {
    interrupt_routing: enum(u4) { irq3 = 3, irq4, irq5, irq6, irq7, irq9 = 9, irq10, irq11, irq12, irq14 = 14, irq15 },
    reserved: u3 = 0,
    routing_enable: bool,
};

const PCITopOfMemory = packed struct {
    reserved: u1 = 0,
    @"ISA/DMA 512-640-Kbyte Region Forwarding Enable": bool,
    @"A,B Segment Forwarding Enable": bool, // PIIX3 only
    @"ISA/DMA Lower BIOS Forwarding Enable": bool,
    top_of_memory: enum(u4) { @"1", @"2", @"3", @"4", @"5", @"6", @"7", @"8", @"9", @"10", @"11", @"12", @"13", @"14", @"15", @"16" },
};

const PCIMiscellaneousStatus = packed struct {
    isa_clock_divisor: bool,
    @"Internal ISA DMA or External DMA Mode Status": bool, // PIIX only
    reserved_2: u1,
    reserved_3: u1,
    usb_enable: bool, // PIIX3 only
    reserved_5: u1,
    extsmi_mode_enable: bool, // PIIX3 only
    nb_retry_enable: bool, // PIIX3 only
    reserved_8: u7,
    serr_generation_due_to_delayed_transaction: bool, // PIIX3 only
};

const PCIMotherboardIRQRouteControl = packed struct {
    interrupt_routing: enum(u4) { irq3 = 3, irq4, irq5, irq6, irq7, irq9 = 9, irq10, irq11, irq12, irq14 = 14, irq15 },
    reserved: u1 = 0,
    irq0_enable: bool, // PIIX3 only
    mirq_irq_sharing_enable: bool,
    routing_enable: bool,
};

const PCIMotherboardDMAControl = packed struct {
    channel_routing: enum(u3) { @"0" = 0, @"1", @"2", @"3", disabled, @"5", @"6", @"7" },
    disable_motherboard_channel: bool, // PIIX only
    reserved: u3 = 0,
    type_f_and_dma_buffer_enable: bool,
};

const PCIProgrammableChipSelectControl = packed struct {
    address_mask: enum(u2) { @"4_bytes" = 0, @"8_bytes_contiguous", disabled, @"16_bytes_contiguous" },
    address: u14, // treat entire field as address, mask lower bytes according to address_mask
};

const PCIAPICBaseAddressRelocation = packed struct {
    y_base_address: u2,
    x_base_address: u4,
    a12_mask: bool,
    reserved: bool,
};

const PCIDeterministicLatencyControl = packed struct {
    delayed_transaction_enable: bool,
    passive_release_enable: bool,
    usb_passive_release_enable: bool,
    serr_generation_due_to_delayed_transaction_timeout_enable: bool,
    reserved: u4,
};

const PCISMIControl = packed struct {
    smi_gate: bool,
    stpclk_signal_enable: bool,
    stpclk_scaling_enable: bool,
    fast_off_timer_free: enum(u2) { minute = 0, disabled, pciclk, msec },
    reserved: u3,
};

const PCISMIEnable = packed struct {
    irq1_smi_enable: bool,
    irq3_smi_enable: bool,
    irq4_smi_enable: bool,
    irq8_smi_enable: bool,
    irq12_smi_enable: bool,
    fast_off_timer_smi_enable: bool,
    extsmi_smi_enable: bool,
    apmc_write_smi_enable: bool,
    legacy_usb_smi_enable: bool, // PIIX3 only
    reserved: u7,
};

const PCISystemEventEnable = packed struct {
    fast_off_irq0_enable: bool,
    fast_off_irq1_enable: bool,
    reserved_2: u1,
    fast_off_irq3_enable: bool,
    fast_off_irq4_enable: bool,
    fast_off_irq5_enable: bool,
    fast_off_irq6_enable: bool,
    fast_off_irq7_enable: bool,
    fast_off_irq8_enable: bool,
    fast_off_irq9_enable: bool,
    fast_off_irq10_enable: bool,
    fast_off_irq11_enable: bool,
    fast_off_irq12_enable: bool,
    fast_off_irq13_enable: bool,
    fast_off_irq14_enable: bool,
    fast_off_irq15_enable: bool,
    reserved_16: u12,
    fast_off_apic_enable: bool, // PIIX3 only
    fast_off_nmi_enable: bool,
    intr_enable: bool,
    fast_off_smi_enable: bool,
};

const PCISMIRequest = packed struct {
    irq1_request: bool,
    irq3_request: bool,
    irq4_request: bool,
    irq8_request: bool,
    irq12_request: bool,
    fast_off_time_expired_status: bool,
    extsmi_smi_status: bool,
    apm_smi_status: bool,
    legacy_usb_smi_status: bool, // PIIX3 only
    reserved: u7,
};

const PCIBridgeConfig = extern struct {
    vendor_id: u16, // 8086
    device_id: u16, // 122e/7000
    command: PCIBridgeCommand,
    status: PCIBridgeStatus,
    revision_id: u8,
    class_code: [3]u8, // 00 01 06
    reserved_0c: [2]u8,
    header_type: u8, // 80
    reserved_0f: [61]u8,
    isa_io_controller_recovery_timer: PCIIORecoveryTimer,
    reserved_4d: u8,
    x_bus_chip_select_enable: PCIXBusChipSelect,
    reserved_50: [16]u8,
    pci_irq_route_control: [4]PCIPIRQRouteControl,
    reserved_64: [4]u8,
    top_of_memory: PCITopOfMemory,
    miscellaneous_status: PCIMiscellaneousStatus,
    reserved_6c: [4]u8,
    motherboard_irq_route_control: [2]PCIMotherboardIRQRouteControl, // [1] is PIIX3 only
    reserved_72: [4]u8,
    motherboard_dma_control: [2]PCIMotherboardDMAControl,
    programmable_chip_select_control: PCIProgrammableChipSelectControl,
    reserved_7a: [6]u8,
    apic_base_address_relocation: PCIAPICBaseAddressRelocation, // PIIX3 only
    reserved_81: u8,
    deterministic_latency_control: PCIDeterministicLatencyControl, // PIIX3 only
    reserved_83: [29]u8,
    smi_control: PCISMIControl,
    reserved_a1: u8,
    smi_enable: PCISMIEnable,
    system_event_enable: PCISystemEventEnable,
    fast_off_time: u8,
    reserved_a9: u8,
    smi_request: PCISMIRequest,
    clock_scale_low_timer: u8,
    reserved_ad: u8,
    clock_scale_high_timer: u8,
    // reserved_af: [80]u8,
};
