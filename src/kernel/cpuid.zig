const std = @import("std");
const log = std.log.scoped(.cpuid);

const cache_tlb = @import("cpuid/cache_tlb.zig");
const console = @import("console.zig");
const shell = @import("shell.zig");
const tools = @import("tools.zig");
const x86 = @import("../arch/x86.zig");

fn get_cpuid(req: x86.CPUIDRequest) x86.CPUIDResults {
    const res = x86.cpuid(req);

    log.debug("{s}: a={x} b={x} c={x} d={x}", .{ @tagName(req), res.a, res.b, res.c, res.d });

    return res;
}

fn get_cpuid_2(req: x86.CPUIDRequest, c: u32) x86.CPUIDResults {
    const res = x86.cpuid_2(req, c);

    log.debug("{s} c={x}: a={x} b={x} c={x} d={x}", .{ @tagName(req), c, res.a, res.b, res.c, res.d });

    return res;
}

fn vendor_string_3(destination: *[12]u8, res: x86.CPUIDResults) void {
    destination[0] = @intCast(res.b & 0xff);
    destination[1] = @intCast((res.b & 0xff00) >> 8);
    destination[2] = @intCast((res.b & 0xff0000) >> 16);
    destination[3] = @intCast((res.b & 0xff000000) >> 24);
    destination[4] = @intCast(res.d & 0xff);
    destination[5] = @intCast((res.d & 0xff00) >> 8);
    destination[6] = @intCast((res.d & 0xff0000) >> 16);
    destination[7] = @intCast((res.d & 0xff000000) >> 24);
    destination[8] = @intCast(res.c & 0xff);
    destination[9] = @intCast((res.c & 0xff00) >> 8);
    destination[10] = @intCast((res.c & 0xff0000) >> 16);
    destination[11] = @intCast((res.c & 0xff000000) >> 24);
}

fn vendor_string_4(destination: *[16]u8, res: x86.CPUIDResults) void {
    destination[0] = @intCast(res.a & 0xff);
    destination[1] = @intCast((res.a & 0xff00) >> 8);
    destination[2] = @intCast((res.a & 0xff0000) >> 16);
    destination[3] = @intCast((res.a & 0xff000000) >> 24);
    destination[4] = @intCast(res.b & 0xff);
    destination[5] = @intCast((res.b & 0xff00) >> 8);
    destination[6] = @intCast((res.b & 0xff0000) >> 16);
    destination[7] = @intCast((res.b & 0xff000000) >> 24);
    destination[8] = @intCast(res.c & 0xff);
    destination[9] = @intCast((res.c & 0xff00) >> 8);
    destination[10] = @intCast((res.c & 0xff0000) >> 16);
    destination[11] = @intCast((res.c & 0xff000000) >> 24);
    destination[12] = @intCast(res.d & 0xff);
    destination[13] = @intCast((res.d & 0xff00) >> 8);
    destination[14] = @intCast((res.d & 0xff0000) >> 16);
    destination[15] = @intCast((res.d & 0xff000000) >> 24);
}

const EAXType = enum(u2) {
    primary,
    overdrive,
    secondary,
    reserved,
};

const EAXFeatures = packed struct {
    stepping: u4,
    model: u4,
    family: u4,
    type: EAXType,
    unused_14: u2,
    model_extended: u4,
    family_extended: u8,
    unused_28: u4,
};

const EBXFeatures = packed struct {
    brand_index: u8,
    clflush_line_size: u8,
    maximum_addressable_processor_id: u8,
    local_apic_id: u8,
};

const ECXFeatures = packed struct {
    sse3: bool,
    pclmul: bool,
    dtes64: bool,
    monitor: bool,
    ds_cpl: bool,
    vmx: bool,
    smx: bool,
    est: bool,
    tm2: bool,
    ssse3: bool,
    cnxt_id: bool,
    sdbg: bool,
    fma: bool,
    cx16: bool,
    xtpr: bool,
    pdcm: bool,
    unused_16: bool,
    pcid: bool,
    dca: bool,
    sse4_1: bool,
    sse4_2: bool,
    x2apic: bool,
    movbe: bool,
    popcnt: bool,
    tsc: bool,
    aes_ni: bool,
    xsave: bool,
    osxsave: bool,
    avx: bool,
    f16c: bool,
    rdrand: bool,
    hypervisor: bool,
};

const EDXFeatures = packed struct {
    fpu: bool,
    vme: bool,
    de: bool,
    pse: bool,
    tsc: bool,
    msr: bool,
    pae: bool,
    mce: bool,
    cx8: bool,
    apic: bool,
    _10: bool,
    sep: bool,
    mtrr: bool,
    pge: bool,
    mca: bool,
    cmov: bool,
    pat: bool,
    pse_36: bool,
    psn: bool,
    clfsh: bool,
    nx: bool, // technically reserved on everything except Itanium
    ds: bool,
    acpi: bool,
    mmx: bool,
    fxsr: bool,
    sse: bool,
    sse2: bool,
    ss: bool,
    htt: bool,
    tm: bool,
    ia64: bool,
    pbe: bool,
};

const Manufacturer = enum {
    Intel,
    AMD,
    Cyrix,
    Centaur,
    NexGen,
    Transmeta,
    Rise,
    UMC,
    SiS,
    NSC,
    Other,
};

fn guess_manufacturer(vendor: [12]u8) Manufacturer {
    if (std.mem.eql(u8, &vendor, "GenuineIntel")) return .Intel;
    if (std.mem.eql(u8, &vendor, "AuthenticAMD")) return .AMD;
    if (std.mem.eql(u8, &vendor, "CyrixInstead")) return .Cyrix;
    if (std.mem.eql(u8, &vendor, "CentaurHauls")) return .Centaur;
    if (std.mem.eql(u8, &vendor, "NexGenDriven")) return .NexGen;
    if (std.mem.eql(u8, &vendor, "GenuineTMx86")) return .Transmeta;
    if (std.mem.eql(u8, &vendor, "RiseRiseRise")) return .Rise;
    if (std.mem.eql(u8, &vendor, "UMC UMC UMC ")) return .UMC;
    if (std.mem.eql(u8, &vendor, "SiS SiS SiS ")) return .SiS;
    if (std.mem.eql(u8, &vendor, "Geode by NSC")) return .NSC;
    return .Other;
}

fn guess_cpu(mfc: Manufacturer, a: EAXFeatures) []const u8 {
    return switch (mfc) {
        .Intel => switch (a.family) {
            3 => "386",
            4 => switch (a.model) {
                0 => "486DX-25/33",
                1 => "486DX-50",
                2 => "486SX",
                3 => "486DX/2",
                4 => "486SL",
                5 => "486SX/2",
                7 => "486DX/2-WB",
                8 => "486DX/4",
                9 => "486DX/4-WB",
                else => "Unknown 486",
            },
            5 => switch (a.model) {
                0 => "Pentium 60/66 A-step",
                1 => "Pentium 60/66",
                2 => "Pentium 75 - 200",
                3 => "OverDrive PODP5V83",
                4 => "Pentium MMX",
                7 => "Mobile Pentium 75 - 200",
                8 => "Mobile Pentium MMX",
                9 => "X1000/D1000",
                else => "Unknown Pentium",
            },
            6 => switch (a.model_extended) {
                0 => switch (a.model) {
                    0 => "Pentium Pro A-step",
                    1 => "Pentium Pro",
                    3 => "PII Klamath",
                    5 => "PII Deschutes / Celeron Covington / Mobile PII Dixon",
                    6 => "Mobile PII / Celeron Mendocino",
                    7 => "PIII Katmai",
                    8 => "PIII Coppermine/T",
                    9 => "Mobile Pentium III",
                    0xA => "PIII (0.18µm)",
                    0xB => "PIII (0.13µm)",
                    0xD => "Dothan",
                    0xE => "Yonah",
                    0xF => "Merom",
                    else => "Unknown PII/III",
                },
                1 => switch (a.model) {
                    5 => "Tolapai",
                    6 => "Merom L",
                    7 => "Penryn/Wolfdale/Yorkfield",
                    0xE => "Clarksfield",
                    0xF => "Auburndale/Havendale",
                    else => "Unknown P6.1",
                },
                2 => switch (a.model) {
                    5 => "Arrandale/Clarkdale",
                    0xA => "Sandy Bridge M/H/Celeron",
                    else => "Unknown P6.2",
                },
                3 => switch (a.model) {
                    0xA => "Ivy Bridge M/H/Gladden",
                    0xC => "Haswell S",
                    0xD => "Broadwell U/Y/S",
                    else => "Unknown P6.3",
                },
                4 => switch (a.model) {
                    5 => "Haswell ULT",
                    6 => "Haswell GT3E",
                    7 => "Broadwell H/C/W",
                    0xE => "Skylake Y/U",
                    else => "Unknown P6.4",
                },
                5 => switch (a.model) {
                    0xE => "Skylake DT/H/S",
                    else => "Unknown P6.5",
                },
                6 => switch (a.model) {
                    6 => "Cannon Lake U",
                    else => "Unknown P6.6",
                },
                7 => switch (a.model) {
                    0xE => "Ice Lake Y/U",
                    else => "Unknown P6.7",
                },
                8 => switch (a.model) {
                    0xC => "Tiger Lake U",
                    0xD => "Tiger Lake H",
                    0xE => "Kaby/Coffee/Whiskey/Amber/Comet Lake Y/U",
                    else => "Unknown P6.8",
                },
                9 => switch (a.model) {
                    7 => "Gracemont E/S",
                    0xA => "Golden Cove P",
                    0xE => "Kaby/Coffee Lake DT/H/S/X/E",
                    else => "Unknown P6.9",
                },
                0xA => switch (a.model) {
                    5 => "Comet Lake S/H",
                    7 => "Cypress Cove S",
                    else => "Unknown P6.10",
                },
                0xB => switch (a.model) {
                    7 => "Enhanced Gracemont E/S",
                    0xA => "Raptor Cove P",
                    else => "Unknown P6.11",
                },
                else => "Unknown P6",
            },
            7 => "Itanium",
            15 => switch (a.family_extended) {
                0 => switch (a.model) {
                    0, 1 => "Pentium IV (0.18µm)",
                    2 => "Pentium IV (0.13µm)",
                    3 => "Pentium IV (0.09µm)",
                    else => "Unknown Pentium IV",
                },
                1 => "Itanium 2",
                else => "Unknown Intel.x",
            },
            else => "Unknown Intel",
        },

        .AMD => switch (a.family) {
            4 => switch (a.model) {
                3 => "486DX/2",
                7 => "486DX/2-WB",
                8 => "486DX/4",
                9 => "486DX/4-WB",
                14 => "Am5x86-WT",
                15 => "Am5x86-WB",
                else => "Unknown K4",
            },
            5 => switch (a.model) {
                0 => "K5/SSA5",
                1, 2, 3 => "K5",
                6, 7 => "K6",
                8 => "K6-2",
                9 => "K6-3",
                13 => "K6-2+/K6-III+",
                else => "Unknown K5/6",
            },
            6 => switch (a.model) {
                0, 1 => "Athlon (25µm)",
                2 => "Athlon (18µm)",
                3 => "Duron",
                4 => "Athlon (Thunderbird)",
                6 => "Athlon (Palamino)",
                7 => "Duron (Morgan)",
                8 => "Athlon (Thoroughbred)",
                10 => "Athlon (Barton)",
                else => "Unknown Athlon/Duron",
            },
            15 => switch (a.family_extended) {
                0 => switch (a.model) {
                    4 => "Athlon 64",
                    5 => "Athlon 64FX/Opteron",
                    else => "Unknown Athlon 64",
                },
                else => "Unknown AMD.x",
            },
            else => "Unknown AMD",
        },

        else => "Unknown",
    };
}

const CPUFeaturesInfo = struct {
    a: EAXFeatures,
    d: EDXFeatures,
    c: ECXFeatures,
    family: u8,
    model: u8,
    cpu: []const u8,
};

const ExtendedEDXFeatures = packed struct {
    fpu: bool,
    vme: bool,
    de: bool,
    pse: bool,
    tsc: bool,
    msr: bool,
    pae: bool,
    mce: bool,
    cx8: bool,
    apic: bool,
    syscall_k6: bool,
    syscall: bool,
    mtrr: bool,
    pge: bool,
    mca: bool,
    cmov: bool,
    pat: bool,
    pse_36: bool,
    _18: bool,
    ecc: bool,
    nx: bool,
    _21: bool,
    mmxext: bool,
    mmx: bool,
    fxsr: bool,
    fxsr_opt: bool,
    pdpe1gb: bool,
    rdtscp: bool,
    _28: bool,
    lm: bool,
    @"3dnowext": bool,
    @"3dnow": bool,
};

const ExtendedECXFeatures = packed struct {
    lahf_lm: bool,
    cmp_legacy: bool,
    svm: bool,
    extapic: bool,
    cr8_legacy: bool,
    abm_lzcnt: bool,
    sse4a: bool,
    misalignsse: bool,
    @"3dnowprefetch": bool,
    osvw: bool,
    ibs: bool,
    xop: bool,
    skinit: bool,
    wdt: bool,
    _14: bool,
    lwp: bool,
    fma4: bool,
    tce: bool,
    _18: bool,
    nodeid_msr: bool,
    _20: bool,
    tbm: bool,
    topoext: bool,
    perfctr_core: bool,
    perfctr_nb: bool,
    StreamPerfMon: bool,
    dbx: bool,
    perftsc: bool,
    pcx_l2i: bool,
    monitorx: bool,
    addr_mask_ext: bool,
    _31: bool,
};

const ExtendedFeaturesInfo = struct { d: ExtendedEDXFeatures, c: ExtendedECXFeatures };

const CacheEAX = packed struct {
    type: enum(u5) { none, data, instruction, unified },
    level: u3,
    self_initializing: bool,
    fully_associative: bool,
    wbinvd_cache_invalidation_execution_scope: bool,
    cache_inclusiveness: bool,
    reserved: u2,
    maximum_processor_ids: u12,
    maximum_core_ids: u6,
};

const CacheEBX = packed struct {
    line_size: u12,
    partitions: u10,
    associativity: u10,
};

const CacheEDX = packed struct {
    wbinvd_cache_invalidation_execution_scope: bool,
    cache_inclusiveness: bool,
    complex_indexing: bool,
    reserved: u29,
};

const CacheHierarchyEntry = struct { a: CacheEAX, b: CacheEBX, c: u32, d: CacheEDX };

const MonitorFeatures = struct {
    smallest: u16,
    largest: u16,
    c0: u4 = 0,
    c1: u4 = 0,
    c2: u4 = 0,
    c3: u4 = 0,
    c4: u4 = 0,
    c5: u4 = 0,
    c6: u4 = 0,
    c7: u4 = 0,
    emx: bool = false,
    ibe: bool = false,
    monitorless_mwait: bool = false,
};

const TPMEAX = packed struct {
    dts: bool,
    intel_turbo_boost: bool,
    arat: bool,
    _3: bool,
    pln: bool,
    ecmd: bool,
    ptm: bool,
    hwp: bool,
    hwp_notification: bool,
    hwp_activity_window: bool,
    hwp_energy_performance_preference: bool,
    hwp_package_level_request: bool,
    _12: bool,
    hdc: bool,
    intel_turbo_boost_max_3: bool,
    hwp_capabilities_interrupt: bool,
    hwp_peci_override: bool,
    flexible_hwp: bool,
    fast_access_mode: bool,
    hw_feedback: bool,
    hwp_request_ignored: bool,
    _21: bool,
    hwp_control_msr: bool,
    intel_thread_director: bool,
    thermal_interrupt_bit25: bool,
    _25: bool,
    _26: bool,
    _27: bool,
    _28: bool,
    _29: bool,
    _30: bool,
    _31: bool,
};

const TPMEBX = packed struct {
    thermal_interrupt_thresholds: u4,
    reserved: u28,
};

const TPMECX = packed struct {
    effective_frequency_interface: bool,
    acnt2_capability: bool,
    reserved_2: bool,
    performance_energy_bias: bool,
    reserved_4: u4,
    intel_thread_director_classes: u8,
    reserved_16: u16,
};

const TPMEDX = packed struct {
    performance_capability_reporting: bool,
    efficiency_capability_reporting: bool,
    reserved_2: u6,
    hardware_feedback_interface_size: u4,
    reserved_12: u4,
    logical_processor_row: u16,
};

const TPMFeatures = struct { a: TPMEAX, b: TPMEBX, c: TPMECX, d: TPMEDX };

// TODO for later
const EAXFeatures0 = packed struct {
    fsgsbase: bool,
    ia32_tsc_adjust_msr: bool,
    sgx: bool,
    bmi1: bool,
    hle: bool,
    avx2: bool,
    @"fdp-excptn-only": bool,
    smep: bool,
    bmi2: bool,
    erms: bool,
    invpcid: bool,
    rtm: bool,
    @"rdt-m/pqm": bool,
    x87_cs_ds_deprecated: bool,
    mpx: bool,
    @"rdt-a/pqe": bool,
    avx512_f: bool,
    avx512_dq: bool,
    rdseed: bool,
    adx: bool,
    smap: bool,
    avx512_ifma: bool,
    pcommit: bool,
    clflushopt: bool,
    clwb: bool,
    pt: bool,
    avx512_pf: bool,
    avx512_er: bool,
    avx512_cd: bool,
    sha: bool,
    avx512_bw: bool,
    avx512_vl: bool,
};

const CPUInfo = struct {
    allocator: std.mem.Allocator,

    highest_function: u32,
    manufacturer_id: [12]u8,
    manufacturer: Manufacturer,
    info: ?CPUFeaturesInfo,
    cache_info: ?cache_tlb.Info,
    cache_hierarchy: ?[]CacheHierarchyEntry,
    monitor_features: ?MonitorFeatures,
    tpm_features: ?TPMFeatures,

    extended_highest_function: u32,
    extended_manufacturer_id: [12]u8,
    extended_info: ?ExtendedFeaturesInfo,
    brand: ?[]u8,

    fn create(allocator: std.mem.Allocator) !*CPUInfo {
        const info = try allocator.create(CPUInfo);
        info.allocator = allocator;
        return info;
    }

    fn destroy(self: *CPUInfo) void {
        if (self.brand) |buffer| self.allocator.free(buffer);
        if (self.cache_hierarchy) |mem| self.allocator.free(mem);
        self.allocator.destroy(self);
    }

    fn supports(self: *CPUInfo, req: x86.CPUIDRequest) bool {
        return self.highest_function >= @intFromEnum(req);
    }

    fn supports_extended(self: *CPUInfo, req: x86.CPUIDRequest) bool {
        return self.extended_highest_function >= @intFromEnum(req);
    }
};

pub fn initialize() !void {
    try shell.add_command(.{
        .name = "cpuid",
        .summary = "Get CPU information",
        .exec = shell_cpuid_command,
    });
}

fn get_cpu_information(allocator: std.mem.Allocator) !*CPUInfo {
    const cpu = try CPUInfo.create(allocator);
    errdefer cpu.destroy();

    {
        const res = get_cpuid(.highest_function_parameter_and_mfc_id);
        cpu.highest_function = res.a;

        vendor_string_3(&cpu.manufacturer_id, res);
        cpu.manufacturer = guess_manufacturer(cpu.manufacturer_id);
    }

    if (cpu.supports(.processor_info_and_feature_bits)) {
        const res = get_cpuid(.processor_info_and_feature_bits);

        const a: EAXFeatures = @bitCast(res.a);
        const family: u8 = if (a.family == 15) a.family + a.family_extended else a.family;
        const model: u8 = if (a.family == 6 or a.family == 15) a.model | (@as(u8, a.model_extended) << 4) else a.model;

        cpu.info = .{
            .a = a,
            .d = @bitCast(res.d),
            .c = @bitCast(res.c),
            .family = family,
            .model = model,
            .cpu = guess_cpu(cpu.manufacturer, a),
        };
    }

    if (cpu.supports(.cache_and_tlb_descriptor_information)) {
        const res = get_cpuid(.cache_and_tlb_descriptor_information);
        cpu.cache_info = try cache_tlb.get_info(allocator, res);
    }

    if (cpu.supports(.cache_hierarchy_and_topology)) {
        var list = std.ArrayList(CacheHierarchyEntry).init(allocator);
        errdefer list.deinit();

        for (0..0xff) |c| {
            const res = get_cpuid_2(.cache_hierarchy_and_topology, c);

            const a: CacheEAX = @bitCast(res.a);
            if (a.type == .none) break;

            try list.append(.{
                .a = a,
                .b = @bitCast(res.b),
                .c = res.c,
                .d = @bitCast(res.d),
            });
        }

        cpu.cache_hierarchy = try list.toOwnedSlice();
    }

    if (cpu.supports(.monitor_mwait_features)) {
        const res = get_cpuid(.monitor_mwait_features);
        var f: MonitorFeatures = .{
            .smallest = @intCast(res.a & 0xffff),
            .largest = @intCast(res.b & 0xffff),
        };

        if (res.c & 0x1 > 0) {
            f.emx = true;
            f.ibe = res.c & 0x2 > 0;
            f.monitorless_mwait = res.c & 0x8 > 0;
            f.c0 = @intCast((res.d >> 0) & 0xf);
            f.c1 = @intCast((res.d >> 4) & 0xf);
            f.c2 = @intCast((res.d >> 8) & 0xf);
            f.c3 = @intCast((res.d >> 12) & 0xf);
            f.c4 = @intCast((res.d >> 16) & 0xf);
            f.c5 = @intCast((res.d >> 20) & 0xf);
            f.c6 = @intCast((res.d >> 24) & 0xf);
            f.c7 = @intCast((res.d >> 28) & 0xf);
        }

        cpu.monitor_features = f;
    }

    if (cpu.supports(.thermal_and_power_management)) {
        const res = get_cpuid(.thermal_and_power_management);
        cpu.tpm_features = .{
            .a = @bitCast(res.a),
            .b = @bitCast(res.b),
            .c = @bitCast(res.c),
            .d = @bitCast(res.d),
        };
    }

    {
        const res = get_cpuid(.extended_highest_function_parameter);
        cpu.extended_highest_function = res.a;

        vendor_string_3(&cpu.extended_manufacturer_id, res);
    }

    if (cpu.supports_extended(.extended_features)) {
        const res = get_cpuid(.extended_features);
        cpu.extended_info = .{ .c = @bitCast(res.c), .d = @bitCast(res.d) };
    }

    if (cpu.supports_extended(.extended_brand_string_end)) {
        var buffer = try allocator.alloc(u8, 48);

        vendor_string_4(buffer[0..16], get_cpuid(.extended_brand_string));
        vendor_string_4(buffer[16..32], get_cpuid(.extended_brand_string_more));
        vendor_string_4(buffer[32..48], get_cpuid(.extended_brand_string_end));

        cpu.brand = buffer;
    }

    return cpu;
}

fn shell_cpuid_command(sh: *shell.Context, _: []const u8) !void {
    const cpu = try get_cpu_information(sh.allocator);
    defer cpu.destroy();

    console.printf_nl("'{s}', '{s}', manufacturer guess: {s}", .{ cpu.manufacturer_id, cpu.extended_manufacturer_id, @tagName(cpu.manufacturer) });

    console.printf_nl("highest function supported: {x} ({s})", .{ cpu.highest_function, @tagName(@as(x86.CPUIDRequest, @enumFromInt(cpu.highest_function))) });

    if (cpu.info) |info| {
        console.puts("> features info:\n");
        console.printf("  family={d} model={d} stepping={d}, cpu guess: {s}\n", .{ info.family, info.model, info.a.stepping, info.cpu });

        console.puts("  supports:");
        inline for (std.meta.fields(EDXFeatures)) |f|
            if (@field(info.d, f.name)) console.puts(" " ++ f.name);
        inline for (std.meta.fields(ECXFeatures)) |f|
            if (@field(info.c, f.name)) console.puts(" " ++ f.name);
        console.new_line();
    }

    if (cpu.cache_info) |info| {
        console.puts("> cache info:\n");
        console.puts("  flags:");
        if (info.no_l3_cache) console.puts(" no L3 cache present");
        if (info.prefetch_128) console.puts(" 128-byte prefetch");
        if (info.prefetch_64) console.puts(" 64-byte prefetch");
        if (info.use_leaf_4) console.puts(" use leaf 4 instead");
        if (info.use_leaf_18) console.puts(" use leaf 18h instead");
        console.new_line();

        for (info.tlb) |e|
            console.printf_nl("  {s} TLB: {d}E, {s}, {d}A", .{ @tagName(e.type), e.entries, e.page_size, e.associativity });

        var size_buffer: [6]u8 = undefined;
        var line_size_buffer: [6]u8 = undefined;
        var sector_size_buffer: [6]u8 = undefined;
        for (info.cache) |e|
            console.printf_nl("  L{d} {s:11}: size={s}, {d:2}A, line={s}, sector={s}", .{ e.level, @tagName(e.type), try tools.nice_size(size_buffer[0..6], e.size), e.associativity, try tools.nice_size(line_size_buffer[0..6], e.line_size), try tools.nice_size(sector_size_buffer[0..6], e.sector_size) });
    }

    if (cpu.cache_hierarchy) |info| {
        console.printf_nl("> cache hierarchy: {d} entries", .{info.len});

        var size_buffer: [6]u8 = undefined;
        var line_size_buffer: [6]u8 = undefined;
        for (info) |e| {
            const line_size: u13 = e.b.line_size + 1;
            const partitions: u11 = e.b.partitions + 1;
            const associativity: u11 = e.b.associativity + 1;
            const max_p: u13 = e.a.maximum_processor_ids + 1;
            const max_c: u7 = e.a.maximum_core_ids + 1;
            const sets: u32 = if (e.a.fully_associative) 1 else (e.c + 1);
            const size: u64 = line_size * partitions * associativity * sets;

            console.printf_nl("  L{d} {s:11}: size={s}, {d:2}A, line={s}, part={d}, max_p={d}, max_c={d}", .{ e.a.level, @tagName(e.a.type), try tools.nice_size(size_buffer[0..6], size), associativity, try tools.nice_size(line_size_buffer[0..6], line_size), partitions, max_p, max_c });
        }
    }

    if (cpu.monitor_features) |info| {
        console.printf_nl("> MONITOR/MWAIT line sizes: {d}-{d}", .{ info.smallest, info.largest });
        if (info.emx) {
            console.puts("  features: emx");
            if (info.ibe) console.puts(" ibe");
            if (info.monitorless_mwait) console.puts(" monitorless-mwait");
            console.new_line();

            console.printf_nl("  MWAIT sub-states: {d}/{d}/{d}/{d}/{d}/{d}/{d}/{d}", .{ info.c0, info.c1, info.c2, info.c3, info.c4, info.c5, info.c6, info.c7 });
        }
    }

    if (cpu.tpm_features) |info| {
        console.puts("> Thermal and Power Management\n");

        console.puts("  features:");
        inline for (std.meta.fields(TPMEAX)) |f|
            if (@field(info.a, f.name)) console.puts(" " ++ f.name);
        if (info.c.effective_frequency_interface) console.puts(" effective_frequency_interface");
        if (info.c.acnt2_capability) console.puts(" acnt2_capability");
        if (info.c.performance_energy_bias) console.puts(" performance_energy_bias");
        if (info.d.performance_capability_reporting) console.puts(" performance_capability_reporting");
        if (info.d.efficiency_capability_reporting) console.puts(" efficiency_capability_reporting");
        console.new_line();

        const size: u64 = (@as(u64, info.d.hardware_feedback_interface_size) + 1) * 4096;
        var size_buffer: [6]u8 = undefined;
        console.printf_nl("  thermal interrupt thresholds={d}, intel thread director classes={d}, feedback size={s}, row={d}", .{ info.b.thermal_interrupt_thresholds, info.c.intel_thread_director_classes, try tools.nice_size(size_buffer[0..6], size), info.d.logical_processor_row });
    }

    console.printf_nl("\nhighest extended function supported: {x} ({s})", .{ cpu.extended_highest_function, @tagName(@as(x86.CPUIDRequest, @enumFromInt(cpu.extended_highest_function))) });

    if (cpu.extended_info) |info| {
        console.puts("> supports:");
        inline for (std.meta.fields(ExtendedEDXFeatures)) |f|
            if (@field(info.d, f.name)) console.puts(" " ++ f.name);
        inline for (std.meta.fields(ExtendedECXFeatures)) |f|
            if (@field(info.c, f.name)) console.puts(" " ++ f.name);
        console.new_line();
    }

    if (cpu.brand) |brand| {
        console.printf_nl("> brand: {s}", .{brand});
    }
}
