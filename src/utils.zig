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

pub inline fn cli() void {
    asm volatile ("cli");
}

pub inline fn io_wait() void {
    outb(0x80, 0);
}

pub const CPUIDRequest = enum(u32) {
    get_vendor_id_string,
    get_features,
    get_tlb,
    get_serial,

    intel_extended = 0x80000000,
    intel_features,
    intel_brand_string,
    intel_brand_string_more,
    intel_brand_string_end,
};

pub const CPUIDResults = struct {
    a: u32,
    b: u32,
    c: u32,
    d: u32,
};

pub inline fn cpuid(code: CPUIDRequest) CPUIDResults {
    var a: u32 = undefined;
    var b: u32 = undefined;
    var c: u32 = undefined;
    var d: u32 = undefined;

    asm volatile ("cpuid"
        : [a] "={eax}" (a),
          [b] "={ebx}" (b),
          [c] "={ecx}" (c),
          [d] "={edx}" (d),
        : [code] "{eax}" (code),
        : "ebx", "ecx"
    );

    return .{ .a = a, .b = b, .c = c, .d = d };
}
