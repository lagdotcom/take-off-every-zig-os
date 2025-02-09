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

fn show_vendor() void {
    const result = utils.cpuid(.get_vendor_id_string);
    const vendor = vendor_string_3(result);
    console.printf("CPUID: {s} ({d}fn)", .{ vendor, result.a });

    const extended_result = utils.cpuid(.intel_extended);
    if (extended_result.a > 0x80000000) {
        const brand0 = vendor_string_4(utils.cpuid(.intel_brand_string));
        const brand1 = vendor_string_4(utils.cpuid(.intel_brand_string_more));
        const brand2 = vendor_string_4(utils.cpuid(.intel_brand_string_end));

        console.printf(" [{s}{s}{s}]", .{ brand0, brand1, brand2 });
    }

    console.new_line();
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

fn guess_cpu(a: EAXFeatures) []const u8 {
    return switch (a.family) {
        3 => "80386",
        4 => switch (a.model) {
            1 => "80486DX",
            2 => "80486SX",
            3 => "80486DX2",
            4 => "80486SL",
            8 => "80486DX4",
            else => "80486",
        },
        5 => switch (a.model) {
            1 => "P5/P54/P54CQS",
            2 => "P54CS",
            4 => "P55C",
            7, 8 => "P55C (Mobile)",
            9 => "X1000/D1000",
            else => "P5/Lakemont",
        },
        6 => switch (a.model) {
            7 => "Katmai",
            8 => "Coppermine/T",
            9 => "Banias",
            0xB => "Tualatin",
            0xD => "Dothan",
            else => "Unknown",
        },
        else => "Unknown",
    };
}

fn show_features() void {
    const features_result = utils.cpuid(.get_features);

    const a: EAXFeatures = @bitCast(features_result.a);
    const family: u8 = if (a.family == 15) a.family + a.family_extended else a.family;
    const model: u8 = if (a.family == 6 or a.family == 15) a.model | (@as(u8, a.model_extended) << 4) else a.model;
    console.printf("f{d} m{d} s{d} -- {s}\n", .{ family, model, a.stepping, guess_cpu(a) });

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
    show_vendor();
    show_features();
}
