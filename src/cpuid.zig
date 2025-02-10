const std = @import("std");

const console = @import("console.zig");
const utils = @import("utils.zig");

pub fn vendor_string_3(res: utils.CPUIDResults) [12]u8 {
    return .{
        @intCast(res.b & 0xff),
        @intCast((res.b & 0xff00) >> 8),
        @intCast((res.b & 0xff0000) >> 16),
        @intCast((res.b & 0xff000000) >> 24),
        @intCast(res.d & 0xff),
        @intCast((res.d & 0xff00) >> 8),
        @intCast((res.d & 0xff0000) >> 16),
        @intCast((res.d & 0xff000000) >> 24),
        @intCast(res.c & 0xff),
        @intCast((res.c & 0xff00) >> 8),
        @intCast((res.c & 0xff0000) >> 16),
        @intCast((res.c & 0xff000000) >> 24),
    };
}

pub fn vendor_string_4(res: utils.CPUIDResults) [16]u8 {
    return .{
        @intCast(res.a & 0xff),
        @intCast((res.a & 0xff00) >> 8),
        @intCast((res.a & 0xff0000) >> 16),
        @intCast((res.a & 0xff000000) >> 24),
        @intCast(res.b & 0xff),
        @intCast((res.b & 0xff00) >> 8),
        @intCast((res.b & 0xff0000) >> 16),
        @intCast((res.b & 0xff000000) >> 24),
        @intCast(res.c & 0xff),
        @intCast((res.c & 0xff00) >> 8),
        @intCast((res.c & 0xff0000) >> 16),
        @intCast((res.c & 0xff000000) >> 24),
        @intCast(res.d & 0xff),
        @intCast((res.d & 0xff00) >> 8),
        @intCast((res.d & 0xff0000) >> 16),
        @intCast((res.d & 0xff000000) >> 24),
    };
}

fn show_vendor() Manufacturer {
    const result = utils.cpuid(.get_vendor_id_string);
    const vendor = vendor_string_3(result);
    console.printf("CPUID: {s} ({d}fn)", .{ vendor, result.a });

    const extended_result = utils.cpuid(.intel_extended);
    if (extended_result.a >= @intFromEnum(utils.CPUIDRequest.intel_brand_string_end)) {
        const brand0 = vendor_string_4(utils.cpuid(.intel_brand_string));
        const brand1 = vendor_string_4(utils.cpuid(.intel_brand_string_more));
        const brand2 = vendor_string_4(utils.cpuid(.intel_brand_string_end));

        console.printf(" [{s}{s}{s}]", .{ brand0, brand1, brand2 });
    }

    console.new_line();
    return guess_manufacturer(vendor);
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
    reserved_10: bool,
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

fn show_features(mfc: Manufacturer) void {
    const features_result = utils.cpuid(.get_features);

    const a: EAXFeatures = @bitCast(features_result.a);
    const family: u8 = if (a.family == 15) a.family + a.family_extended else a.family;
    const model: u8 = if (a.family == 6 or a.family == 15) a.model | (@as(u8, a.model_extended) << 4) else a.model;
    console.printf("f{d} m{d} s{d} -- {s}\n", .{ family, model, a.stepping, guess_cpu(mfc, a) });

    console.printf("Features:", .{});

    const d: EDXFeatures = @bitCast(features_result.d);
    if (d.fpu) console.puts(" fpu");
    if (d.vme) console.puts(" vme");
    if (d.de) console.puts(" de");
    if (d.pse) console.puts(" pse");
    if (d.tsc) console.puts(" tsc");
    if (d.msr) console.puts(" msr");
    if (d.pae) console.puts(" pae");
    if (d.mce) console.puts(" mce");
    if (d.cx8) console.puts(" cx8");
    if (d.apic) console.puts(" apic");
    if (d.sep) console.puts(" sep");
    if (d.mtrr) console.puts(" mtrr");
    if (d.pge) console.puts(" pge");
    if (d.mca) console.puts(" mca");
    if (d.cmov) console.puts(" cmov");
    if (d.pat) console.puts(" pat");
    if (d.pse_36) console.puts(" pse-36");
    if (d.psn) console.puts(" psn");
    if (d.clfsh) console.puts(" clflush");
    if (d.ds) console.puts(" ds");
    if (d.acpi) console.puts(" acpi");
    if (d.mmx) console.puts(" mmx");
    if (d.fxsr) console.puts(" fxsr");
    if (d.sse) console.puts(" sse");
    if (d.sse2) console.puts(" sse2");
    if (d.ss) console.puts(" ss");
    if (d.htt) console.puts(" htt");
    if (d.tm) console.puts(" tm");
    if (d.ia64) console.puts(" ia64");
    if (d.pbe) console.puts(" pbe");

    const c: ECXFeatures = @bitCast(features_result.c);
    if (c.sse3) console.puts(" sse3");
    if (c.pclmul) console.puts(" pclmul");
    if (c.dtes64) console.puts(" dtes64");
    if (c.monitor) console.puts(" monitor");
    if (c.ds_cpl) console.puts(" ds-cpl");
    if (c.vmx) console.puts(" vmx");
    if (c.smx) console.puts(" smx");
    if (c.est) console.puts(" est");
    if (c.tm2) console.puts(" tm2");
    if (c.ssse3) console.puts(" ssse3");
    if (c.cnxt_id) console.puts(" cnxt-id");
    if (c.sdbg) console.puts(" sdbg");
    if (c.fma) console.puts(" fma");
    if (c.cx16) console.puts(" cx16");
    if (c.xtpr) console.puts(" xtpr");
    if (c.pdcm) console.puts(" pdcm");
    if (c.pcid) console.puts(" pcid");
    if (c.dca) console.puts(" dca");
    if (c.sse4_1) console.puts(" sse4.1");
    if (c.sse4_2) console.puts(" sse4.2");
    if (c.x2apic) console.puts(" x2apic");
    if (c.movbe) console.puts(" movbe");
    if (c.popcnt) console.puts(" popcnt");
    if (c.tsc) console.puts(" tsc-deadline");
    if (c.aes_ni) console.puts(" aes-ni");
    if (c.xsave) console.puts(" xsave");
    if (c.osxsave) console.puts(" osxsave");
    if (c.avx) console.puts(" avx");
    if (c.f16c) console.puts(" f16c");
    if (c.rdrand) console.puts(" rdrand");
    if (c.hypervisor) console.puts(" hypervisor");

    console.new_line();
}

pub fn initialize() void {
    const mfc = show_vendor();
    show_features(mfc);
}
