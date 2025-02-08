const console = @import("console.zig");
const keyboard = @import("keyboard.zig");
const pci = @import("pci.zig");
const utils = @import("utils.zig");

const ALIGN = 1 << 0;
const MEMINFO = 1 << 1;
const MAGIC = 0x1BADB002;
const FLAGS = ALIGN | MEMINFO;

const MultibootHeader = packed struct {
    magic: i32 = MAGIC,
    flags: i32,
    checksum: i32,
    padding: u32 = 0,
};

export var multiboot align(4) linksection(".multiboot") = MultibootHeader{
    .flags = FLAGS,
    .checksum = -(MAGIC + FLAGS),
};

export var stack_bytes: [16 * 1024]u8 align(16) linksection(".bss") = undefined;
const stack_bytes_slice = stack_bytes[0..];

export fn _start() callconv(.Naked) noreturn {
    asm volatile (
        \\ movl %[stack_top], %esp
        \\ movl %esp, %ebp
        \\ call kernel_main
        :
        : [stack_top] "{ecx}" (@intFromPtr(&stack_bytes_slice) + @sizeOf(@TypeOf(stack_bytes_slice))),
    );
    while (true) {}
}

fn show_pci_device_info(bus: u8, slot: u5, function: u3) void {
    if (pci.get_device_header(bus, slot, function)) |h| {
        console.printf("Vendor/Device ID: {x:0>4}:{x:0>4} ({s})\n", .{ h.vendor_id, h.device_id, pci.get_vendor_name(h.vendor_id) });
        console.printf("Class: {x}:{x}\n", .{ h.class_code, h.subclass });
        console.printf("Command: {b:0>16}\nStatus: {b:0>16}\n", .{ h.command, h.status });
        console.printf("Revision ID: {x}\nProg IF: {x}\n", .{ h.revision_id, h.prog_if });
        console.printf("Cache Line Size: {x}\nLatency Timer: {x}\n", .{ h.cache_line_size, h.latency_timer });
        console.printf("Header Type: {x}\nBIST: {x}\n", .{ h.header_type, h.bist });

        if (h.general) |g| {
            console.printf("BAR: {x} {x} {x} {x} {x} {x}\n", .{ g.base_address_registers[0], g.base_address_registers[1], g.base_address_registers[2], g.base_address_registers[3], g.base_address_registers[4], g.base_address_registers[5] });
            console.printf("CardBus CIS Pointer: {x}\n", .{g.card_bus_cis_pointer});
            console.printf("Subsystem Vendor ID: {x}\nSubsystem ID: {x}\n", .{ g.subsystem_vendor_id, g.subsystem_id });
            console.printf("Expansion ROM Base Address: {x}\n", .{g.expansion_rom_base_address});
            console.printf("Capabilities Pointer: {x}\n", .{g.capabilities_pointer});
            console.printf("Interrupt Line: {x} / Pin: {x}\n", .{ g.interrupt_line, g.interrupt_pin });
            console.printf("Min Grant: {x}\nMax Latency: {x}\n", .{ g.min_grant, g.max_latency });
        }
    }
}

fn show_pci_brief(bus: usize, slot: usize, function: usize, h: pci.DeviceHeader) void {
    console.printf("At {d}:{d}:{d} - {x:0>4}:{x:0>4} ({s}) - {s}\n", .{ bus, slot, function, h.vendor_id, h.device_id, pci.get_vendor_name(h.vendor_id), pci.get_device_class(h.class_code, h.subclass) });
}

fn check_pci_function(bus: u8, slot: u5, function: u3) void {
    if (pci.get_device_header(bus, slot, function)) |h| {
        show_pci_brief(@intCast(bus), @intCast(slot), @intCast(function), h);

        if (h.pci_to_pci_bridge) |p| {
            enumerate_pci_bus(p.secondary_bus_number);
        }
    }
}

fn check_pci_device(bus: u8, slot: u5) void {
    if (pci.get_device_header(bus, slot, 0)) |h| {
        show_pci_brief(@intCast(bus), @intCast(slot), 0, h);

        if ((h.header_type & 0x80) != 0) {
            for (1..8) |function| {
                check_pci_function(bus, slot, @intCast(function));
            }
        }
    }
}

fn enumerate_pci_bus(bus: u8) void {
    for (0..32) |slot| {
        check_pci_device(bus, @intCast(slot));
    }
}

fn enumerate_pci_buses() void {
    for (0..256) |bus| {
        enumerate_pci_bus(@intCast(bus));
    }
}

fn brute_force_pci_devices() void {
    for (0..256) |bus| {
        for (0..32) |slot| {
            for (0..8) |function| {
                if (pci.get_device_header(@intCast(bus), @intCast(slot), @intCast(function))) |h| {
                    show_pci_brief(bus, slot, function, h);
                }
            }
        }
    }
}

export fn kernel_main() callconv(.C) void {
    console.initialize();
    console.puts("Hello Zig Kernel!\n\n");

    enumerate_pci_buses();
}
