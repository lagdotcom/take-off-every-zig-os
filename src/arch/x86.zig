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
