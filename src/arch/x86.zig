pub inline fn inb(port: u16) u8 {
    return asm volatile ("inb %[port], %[result]"
        : [result] "={al}" (-> u8),
        : [port] "N{dx}" (port),
    );
}

pub inline fn inw(port: u16) u16 {
    return asm volatile ("inw %[port], %[result]"
        : [result] "={ax}" (-> u16),
        : [port] "N{dx}" (port),
    );
}

pub inline fn inl(port: u16) u32 {
    return asm volatile ("inl %[port], %[result]"
        : [result] "={eax}" (-> u32),
        : [port] "N{dx}" (port),
    );
}

pub inline fn outb(port: u16, value: u8) void {
    asm volatile ("outb %[value], %[port]"
        :
        : [port] "N{dx}" (port),
          [value] "{al}" (value),
    );
}

pub inline fn outw(port: u16, value: u16) void {
    asm volatile ("outw %[value], %[port]"
        :
        : [port] "N{dx}" (port),
          [value] "{ax}" (value),
    );
}

pub inline fn outl(port: u16, value: u32) void {
    asm volatile ("outl %[value], %[port]"
        :
        : [port] "N{dx}" (port),
          [value] "{eax}" (value),
    );
}

var interrupts_enabled = false;

pub inline fn cli() void {
    asm volatile ("cli");
    interrupts_enabled = false;
}

pub inline fn sti() void {
    asm volatile ("sti");
    interrupts_enabled = true;
}

pub inline fn pause_interrupts() bool {
    const status = interrupts_enabled;
    if (interrupts_enabled) cli();
    return status;
}

pub inline fn resume_interrupts(status: bool) void {
    if (status) sti();
}

pub inline fn io_wait() void {
    outb(0x80, 0);
}

pub const CPUIDRequest = enum(u32) {
    highest_function_parameter_and_mfc_id,
    processor_info_and_feature_bits,
    cache_and_tlb_descriptor_information,
    serial_number,
    cache_hierarchy_and_topology,
    monitor_mwait_features,
    thermal_and_power_management,
    extended_features,
    _8,
    _9,
    _a,
    _b,
    _c,
    xsave_features,
    _e,
    _f,
    _10,
    _11,
    sgx_capabilities,
    _13,
    processor_trace,
    tsc_and_core_crystal_information,
    processor_and_bus_specification,
    soc_vendor_attribute_enumeration,
    _18,
    intel_key_locker_features,
    _1a,
    _1b,
    _1c,
    tile_information,
    tmul_information,
    _1f,
    _20,
    tdx_enumeration,
    _22,
    _23,
    avx10,

    xeon_phi_highest_function_parameter = 0x20000000,
    xeon_phi_feature_bits,

    hypervisor_highest_function_parameter_and_id = 0x40000000,

    extended_highest_function_parameter = 0x80000000,
    extended_processor_info_and_feature_bits,
    extended_brand_string,
    extended_brand_string_more,
    extended_brand_string_end,
    extended_l1_cache_and_tlb_identifiers,
    extended_l2_cache_features,
    extended_processor_power_management_and_ras_information,
    extended_virtual_and_physical_address_sizes,
    _x9,
    extended_svm_features,
    _xb,
    _xc,
    _xd,
    _xe,
    _xf,
    _x10,
    _x11,
    _x12,
    _x13,
    _x14,
    _x15,
    _x16,
    _x17,
    _x18,
    _x19,
    _x1a,
    _x1b,
    _x1c,
    _x1d,
    _x1e,
    extended_encrypted_memory_features,
    _x20,
    extended_feature_identification,
    amd_easter_egg = 0x8fffffff,

    centaur_highest_function_parameter = 0xc0000000,
    centaur_feature_information,
};

pub const CPUIDResults = struct {
    a: u32,
    b: u32,
    c: u32,
    d: u32,
};

pub inline fn cpuid(req: CPUIDRequest) CPUIDResults {
    var a: u32 = undefined;
    var b: u32 = undefined;
    var c: u32 = undefined;
    var d: u32 = undefined;

    asm volatile ("cpuid"
        : [a] "={eax}" (a),
          [b] "={ebx}" (b),
          [c] "={ecx}" (c),
          [d] "={edx}" (d),
        : [code] "{eax}" (req),
        : "ebx", "ecx", "edx"
    );

    return .{ .a = a, .b = b, .c = c, .d = d };
}

pub inline fn cpuid_2(req: CPUIDRequest, c_in: u32) CPUIDResults {
    var a: u32 = undefined;
    var b: u32 = undefined;
    var c: u32 = undefined;
    var d: u32 = undefined;

    asm volatile ("cpuid"
        : [a] "={eax}" (a),
          [b] "={ebx}" (b),
          [c] "={ecx}" (c),
          [d] "={edx}" (d),
        : [code] "{eax}" (req),
          [param] "{ecx}" (c_in),
        : "ebx", "ecx", "edx"
    );

    return .{ .a = a, .b = b, .c = c, .d = d };
}

pub const IDTDescriptor = packed struct {
    limit: u16,
    base: u32,
};

pub inline fn lidt(ptr: *IDTDescriptor) void {
    asm volatile ("lidt (%%eax)"
        :
        : [ptr] "{eax}" (ptr),
    );
}

pub const EFLAGS = packed struct {
    cf: bool,
    reserved_1: bool,
    pf: bool,
    reserved_3: bool,
    af: bool,
    reserved_5: bool,
    zf: bool,
    sf: bool,
    tf: bool,
    @"if": bool,
    df: bool,
    of: bool,
    iopl: u2,
    nt: bool,
    md: bool,

    rf: bool,
    vm: bool,
    ac: bool,
    vif: bool,
    vip: bool,
    id: bool,
    reserved_22: u8,
    aes: bool,
    ai: bool,
};
