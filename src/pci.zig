const std = @import("std");
const log = std.log.scoped(.pci);

const console = @import("console.zig");
const utils = @import("utils.zig");

const CONFIG_ADDRESS = 0xcf8;
const CONFIG_DATA = 0xcfc;

pub const PCIBus = u8;
pub const PCISlot = u5;
pub const PCIFunction = u3;

pub const ConfigAddress = packed struct {
    register_offset: u8,
    function_number: PCIFunction,
    device_number: PCISlot,
    bus_number: PCIBus,
    reserved: u7,
    enable_bit: bool,
};

pub fn read_config_address() ConfigAddress {
    return @bitCast(utils.inl(CONFIG_ADDRESS));
}

pub fn config_read_long(addr: ConfigAddress) u32 {
    utils.outl(CONFIG_ADDRESS, @bitCast(addr));
    return utils.inl(CONFIG_DATA);
}

pub fn get_device_config(bus: PCIBus, slot: PCISlot, function: PCIFunction, offset: u8) u32 {
    return config_read_long(ConfigAddress{
        .register_offset = offset,
        .function_number = function,
        .device_number = slot,
        .bus_number = bus,
        .reserved = 0,
        .enable_bit = true,
    });
}

pub const DeviceID = struct {
    vendor_id: u16,
    device_id: u16,
};

pub fn get_device_id(bus: PCIBus, slot: PCISlot) ?DeviceID {
    const long0 = get_device_config(bus, slot, 0);
    const vendor_id: u16 = @intCast(long0 & 0xffff);
    if (vendor_id == 0xffff) {
        return null;
    }

    const device_id: u16 = @intCast(long0 >> 16);
    return DeviceID{ .vendor_id = vendor_id, .device_id = device_id };
}

pub const DeviceHeader = struct {
    vendor_id: u16,
    device_id: u16,
    command: u16,
    status: u16,
    revision_id: u8,
    prog_if: u8,
    subclass: u8,
    class_code: u8,
    cache_line_size: u8,
    latency_timer: u8,
    header_type: u8,
    bist: u8,
    general: ?GeneralDeviceHeader,
    pci_to_pci_bridge: ?PCIToPCIBridgeHeader,
};

pub const GeneralDeviceHeader = struct {
    base_address_registers: [6]u32,
    card_bus_cis_pointer: u32,
    subsystem_vendor_id: u16,
    subsystem_id: u16,
    expansion_rom_base_address: u32,
    capabilities_pointer: u8,
    reserved_a: [3]u8,
    reserved_b: u32,
    interrupt_line: u8,
    interrupt_pin: u8,
    min_grant: u8,
    max_latency: u8,
};

pub const PCIToPCIBridgeHeader = struct {
    base_address_registers: [2]u32,
    primary_bus_number: u8,
    secondary_bus_number: u8,
    subordinate_bus_number: u8,
    secondary_latency_timer: u8,
    io_base: u8,
    io_limit: u8,
    secondary_status: u16,
    memory_base: u16,
    memory_limit: u16,
    prefetchable_memory_base: u16,
    prefetchable_memory_limit: u16,
    prefetchable_base_upper_32_bits: u32,
    prefetchable_limit_upper_32_bits: u32,
    io_base_upper_16_bits: u16,
    io_limit_upper_16_bits: u16,
    capabilities_pointer: u8,
    reserved: [3]u8,
    expansion_rom_base_address: u32,
    interrupt_line: u8,
    interrupt_pin: u8,
    bridge_control: u16,
};

pub fn get_device_header(bus: PCIBus, slot: PCISlot, function: PCIFunction) ?DeviceHeader {
    const long0 = get_device_config(bus, slot, function, 0);

    const vendor_id: u16 = @intCast(long0 & 0xffff);
    if (vendor_id == 0xffff) {
        return null;
    }

    const device_id: u16 = @intCast(long0 >> 16);

    const word2 = get_device_config(bus, slot, function, 4);
    const command: u16 = @intCast(word2 & 0xffff);
    const status: u16 = @intCast(word2 >> 16);

    const long3 = get_device_config(bus, slot, function, 8);
    const revision_id: u8 = @intCast(long3 & 0xff);
    const prog_if: u8 = @intCast((long3 >> 8) & 0xff);
    const subclass: u8 = @intCast((long3 >> 16) & 0xff);
    const class_code: u8 = @intCast(long3 >> 24);

    const long4 = get_device_config(bus, slot, function, 12);
    const cache_line_size: u8 = @intCast(long4 & 0xff);
    const latency_timer: u8 = @intCast((long4 >> 8) & 0xff);
    const header_type: u8 = @intCast((long4 >> 16) & 0xff);
    const bist: u8 = @intCast(long4 >> 24);

    return DeviceHeader{
        .vendor_id = vendor_id,
        .device_id = device_id,
        .command = command,
        .status = status,
        .revision_id = revision_id,
        .prog_if = prog_if,
        .subclass = subclass,
        .class_code = class_code,
        .cache_line_size = cache_line_size,
        .latency_timer = latency_timer,
        .header_type = header_type,
        .bist = bist,
        .general = if ((header_type & 0x7F) == 0) get_general_device_header(bus, slot, function) else null,
        .pci_to_pci_bridge = if ((header_type & 0x7F) == 1) get_pci_to_pci_bridge_header(bus, slot, function) else null,
    };
}

pub fn get_device_type(header_type: u8) []const u8 {
    return switch (header_type) {
        0x00 => "General",
        0x01 => "PCI-to-PCI Bridge",
        0x02 => "PCI-to-CardBus Bridge",
        0x80 => "General (multi-function)",
        0x81 => "PCI-to-PCI Bridge (multi-function)",
        0x82 => "PCI-to-CardBus Bridge (multi-function)",
        else => "Unknown",
    };
}

pub fn get_device_class(class_code: u8, subclass: u8) []const u8 {
    return switch (class_code) {
        0x00 => switch (subclass) {
            0x00 => "Non-VGA-Compatible Unclassified Device",
            else => "VGA-Compatible Unclassified Device",
        },
        0x01 => switch (subclass) {
            0x00 => "SCSI Bus Controller",
            0x01 => "IDE Controller",
            0x02 => "Floppy Disk Controller",
            0x03 => "IPI Bus Controller",
            0x04 => "RAID Controller",
            0x05 => "ATA Controller",
            0x06 => "SATA Controller",
            0x07 => "Serial Attached SCSI Controller",
            0x08 => "Non-Volatile Memory Controller",
            else => "Unclassified Mass Storage Controller",
        },
        0x02 => switch (subclass) {
            0x00 => "Ethernet Controller",
            0x01 => "Token Ring Controller",
            0x02 => "FDDI Controller",
            0x03 => "ATM Controller",
            0x04 => "ISDN Controller",
            0x05 => "WorldFip Controller",
            0x06 => "PICMG 2.14 Multi Computing Controller",
            0x07 => "Infiniband Controller",
            0x08 => "Fabric Controller",
            else => "Unclassified Network Controller",
        },
        0x03 => switch (subclass) {
            0x00 => "VGA-Compatible Controller",
            0x01 => "XGA Controller",
            0x02 => "3D Controller",
            else => "Unclassified Display Controller",
        },
        0x04 => switch (subclass) {
            0x00 => "Multimedia Video Controller",
            0x01 => "Multimedia Audio Controller",
            0x02 => "Computer Telephony Device",
            0x03 => "Audio Device",
            else => "Unclassified Multimedia Controller",
        },
        0x05 => switch (subclass) {
            0x00 => "RAM Controller",
            0x01 => "Flash Controller",
            else => "Unclassified Memory Controller",
        },
        0x06 => switch (subclass) {
            0x00 => "Host Bridge",
            0x01 => "ISA Bridge",
            0x02 => "EISA Bridge",
            0x03 => "MCA Bridge",
            0x04 => "PCI-to-PCI Bridge",
            0x05 => "PCMCIA Bridge",
            0x06 => "NuBus Bridge",
            0x07 => "CardBus Bridge",
            0x08 => "RACEway Bridge",
            0x09 => "PCI-to-PCI Bridge",
            0x0a => "InfiniBand-to-PCI Host Bridge",
            else => "Unclassified Bridge Device",
        },
        0x07 => switch (subclass) {
            0x00 => "Serial Controller",
            0x01 => "Parallel Controller",
            0x02 => "Multiport Serial Controller",
            0x03 => "Modem",
            0x04 => "IEEE 488.1/2 (GPIB) Controller",
            0x05 => "Smart Card Controller",
            else => "Unclassified Communication Controller",
        },
        0x08 => switch (subclass) {
            0x00 => "PIC",
            0x01 => "DMA Controller",
            0x02 => "Timer",
            0x03 => "RTC Controller",
            0x04 => "PCI Hot-Plug Controller",
            0x05 => "SD Host Controller",
            0x06 => "IOMMU",
            else => "Unclassified System Peripheral",
        },
        0x09 => switch (subclass) {
            0x00 => "Keyboard Controller",
            0x01 => "Digitizer Pen",
            0x02 => "Mouse Controller",
            0x03 => "Scanner Controller",
            0x04 => "Gameport Controller",
            else => "Unclassified Input Device Controller",
        },
        0x0a => switch (subclass) {
            0x00 => "Generic Docking Station",
            0x01 => "Display Station",
            0x02 => "VR Headset",
            else => "Unclassified Docking Station",
        },
        0x0b => switch (subclass) {
            0x00 => "386",
            0x01 => "486",
            0x02 => "Pentium",
            0x03 => "Pentium Pro",
            0x10 => "Alpha",
            0x20 => "PowerPC",
            0x30 => "MIPS",
            0x40 => "Co-Processor",
            else => "Unclassified Processor",
        },
        0x0c => switch (subclass) {
            0x00 => "FireWire (IEEE 1394) Controller",
            0x01 => "ACCESS Bus Controller",
            0x02 => "SSA",
            0x03 => "USB Controller",
            0x04 => "Fibre Channel",
            0x05 => "SMBus Controller",
            0x06 => "InfiniBand Controller",
            0x07 => "IPMI Interface",
            0x08 => "SERCOS Interface (IEC 61491)",
            0x09 => "CANbus Controller",
            else => "Unclassified Serial Bus Controller",
        },
        0x0d => switch (subclass) {
            0x00 => "iRDA Compatible Controller",
            0x01 => "Consumer IR Controller",
            0x10 => "RF Controller",
            0x11 => "Bluetooth Controller",
            0x12 => "Broadband Controller",
            0x20 => "Ethernet Controller (802.1a)",
            0x21 => "Ethernet Controller (802.1b)",
            else => "Unclassified Wireless Controller",
        },
        0x0e => switch (subclass) {
            0x00 => "I20",
            else => "Unclassified Intelligent Controller",
        },
        0x0f => switch (subclass) {
            0x00 => "Satellite TV Controller",
            0x01 => "Satellite Audio Controller",
            0x02 => "Satellite Voice Controller",
            0x03 => "Satellite Data Controller",
            else => "Unclassified Satellite Controller",
        },
        0x10 => switch (subclass) {
            0x00 => "Encryption Controller",
            0x01 => "Tokenizer",
            0x10 => "SAS Controller",
            0x11 => "SD Controller",
            0x12 => "MMC Controller",
            0x13 => "Memory Stick Controller",
            0x20 => "InfiniBand Controller",
            0x80 => "SATA Controller",
            0x81 => "SAS Controller",
            0x82 => "SSD Controller",
            else => "Unclassified Encryption Controller",
        },
        0x11 => switch (subclass) {
            0x00 => "DPIO Modules",
            0x01 => "Performance Counters",
            0x10 => "Communication Synchronizer",
            0x20 => "Signal Processing Management",
            else => "Unclassified Signal Processing Controller",
        },
        0x12 => "Processing Accelerator",
        0x13 => "Non-Essential Instrumentation",
        0x40 => "Co-Processor",
        else => "Unclassified",
    };
}

pub fn get_general_device_header(bus: PCIBus, slot: PCISlot, function: PCIFunction) GeneralDeviceHeader {
    const bar0 = get_device_config(bus, slot, function, 0x10);
    const bar1 = get_device_config(bus, slot, function, 0x14);
    const bar2 = get_device_config(bus, slot, function, 0x18);
    const bar3 = get_device_config(bus, slot, function, 0x1C);
    const bar4 = get_device_config(bus, slot, function, 0x20);
    const bar5 = get_device_config(bus, slot, function, 0x24);

    const card_bus_cis_pointer = get_device_config(bus, slot, function, 0x28);

    const word2c = get_device_config(bus, slot, function, 0x2a);
    const subsystem_vendor_id: u16 = @intCast(word2c & 0xffff);
    const subsystem_id: u16 = @intCast(word2c >> 16);

    const expansion_rom_base_address = get_device_config(bus, slot, function, 0x30);

    const word34 = get_device_config(bus, slot, function, 0x34);
    const capabilities_pointer: u8 = @intCast(word34 & 0xff);
    const reserved0: u8 = @intCast((word34 >> 8) & 0xff);
    const reserved1: u8 = @intCast((word34 >> 8) & 0xff);
    const reserved2: u8 = @intCast((word34 >> 8) & 0xff);

    const reserved_b = get_device_config(bus, slot, function, 0x38);

    const word3d = get_device_config(bus, slot, function, 0x3c);
    const interrupt_line: u8 = @intCast(word3d & 0xff);
    const interrupt_pin: u8 = @intCast((word3d >> 8) & 0xff);
    const min_grant: u8 = @intCast((word3d >> 16) & 0xff);
    const max_latency: u8 = @intCast(word3d >> 24);

    return GeneralDeviceHeader{
        .base_address_registers = .{ bar0, bar1, bar2, bar3, bar4, bar5 },
        .card_bus_cis_pointer = card_bus_cis_pointer,
        .subsystem_vendor_id = subsystem_vendor_id,
        .subsystem_id = subsystem_id,
        .expansion_rom_base_address = expansion_rom_base_address,
        .capabilities_pointer = capabilities_pointer,
        .reserved_a = .{ reserved0, reserved1, reserved2 },
        .reserved_b = reserved_b,
        .interrupt_line = interrupt_line,
        .interrupt_pin = interrupt_pin,
        .min_grant = min_grant,
        .max_latency = max_latency,
    };
}

pub fn get_vendor_name(vendor_id: u16) []const u8 {
    return switch (vendor_id) {
        0x8086 => "Intel",
        0x1234 => "qemu?",
        else => "Unknown",
    };
}

pub fn get_pci_to_pci_bridge_header(bus: PCIBus, slot: PCISlot, function: PCIFunction) PCIToPCIBridgeHeader {
    const bar0 = get_device_config(bus, slot, function, 0x10);
    const bar1 = get_device_config(bus, slot, function, 0x14);

    const word18 = get_device_config(bus, slot, function, 0x18);
    const primary_bus_number: u8 = @intCast(word18 & 0xff);
    const secondary_bus_number: u8 = @intCast((word18 >> 8) & 0xff);
    const subordinate_bus_number: u8 = @intCast((word18 >> 16) & 0xff);
    const secondary_latency_timer: u8 = @intCast(word18 >> 24);

    const word1c = get_device_config(bus, slot, function, 0x1C);
    const io_base: u8 = @intCast(word1c & 0xff);
    const io_limit: u8 = @intCast((word1c >> 8) & 0xff);
    const secondary_status: u16 = @intCast(word1c >> 16);

    const word20 = get_device_config(bus, slot, function, 0x20);
    const memory_base: u16 = @intCast(word20 & 0xffff);
    const memory_limit: u16 = @intCast(word20 >> 16);

    const word24 = get_device_config(bus, slot, function, 0x24);
    const prefetchable_memory_base: u16 = @intCast(word24 & 0xffff);
    const prefetchable_memory_limit: u16 = @intCast(word24 >> 16);

    const prefetchable_base_upper_32_bits = get_device_config(bus, slot, function, 0x28);
    const prefetchable_limit_upper_32_bits = get_device_config(bus, slot, function, 0x2C);

    const word30 = get_device_config(bus, slot, function, 0x30);
    const io_base_upper_16_bits: u16 = @intCast(word30 & 0xffff);
    const io_limit_upper_16_bits: u16 = @intCast(word30 >> 16);

    const word34 = get_device_config(bus, slot, function, 0x34);
    const capabilities_pointer: u8 = @intCast(word34 & 0xff);
    const reserved1: u8 = @intCast((word34 >> 8) & 0xff);
    const reserved2: u8 = @intCast((word34 >> 16) & 0xff);
    const reserved3: u8 = @intCast(word34 >> 24);

    const expansion_rom_base_address = get_device_config(bus, slot, function, 0x38);

    const word3c = get_device_config(bus, slot, function, 0x3C);
    const interrupt_line: u8 = @intCast(word3c & 0xff);
    const interrupt_pin: u8 = @intCast((word3c >> 8) & 0xff);
    const bridge_control: u16 = @intCast(word3c >> 16);

    return PCIToPCIBridgeHeader{
        .base_address_registers = .{ bar0, bar1 },
        .primary_bus_number = primary_bus_number,
        .secondary_bus_number = secondary_bus_number,
        .subordinate_bus_number = subordinate_bus_number,
        .secondary_latency_timer = secondary_latency_timer,
        .io_base = io_base,
        .io_limit = io_limit,
        .secondary_status = secondary_status,
        .memory_base = memory_base,
        .memory_limit = memory_limit,
        .prefetchable_memory_base = prefetchable_memory_base,
        .prefetchable_memory_limit = prefetchable_memory_limit,
        .prefetchable_base_upper_32_bits = prefetchable_base_upper_32_bits,
        .prefetchable_limit_upper_32_bits = prefetchable_limit_upper_32_bits,
        .io_base_upper_16_bits = io_base_upper_16_bits,
        .io_limit_upper_16_bits = io_limit_upper_16_bits,
        .capabilities_pointer = capabilities_pointer,
        .reserved = .{ reserved1, reserved2, reserved3 },
        .expansion_rom_base_address = expansion_rom_base_address,
        .interrupt_line = interrupt_line,
        .interrupt_pin = interrupt_pin,
        .bridge_control = bridge_control,
    };
}

fn show_full_device_info(bus: usize, slot: usize, function: usize, h: DeviceHeader) void {
    log.debug("Location: {d}:{d}:{d}", .{ bus, slot, function });
    log.debug("Vendor/Device ID: {x:0>4}:{x:0>4} ({s})", .{ h.vendor_id, h.device_id, get_vendor_name(h.vendor_id) });
    log.debug("Class: {x}:{x} ({s})", .{ h.class_code, h.subclass, get_device_class(h.class_code, h.subclass) });
    log.debug("Command: {b:0>16} -- Status: {b:0>16}", .{ h.command, h.status });
    log.debug("Revision ID: {x} -- Prog IF: {x}", .{ h.revision_id, h.prog_if });
    log.debug("Cache Line Size: {x} -- Latency Timer: {x}", .{ h.cache_line_size, h.latency_timer });
    log.debug("Header Type: {x} -- BIST: {x}", .{ h.header_type, h.bist });

    if (h.general) |g| {
        log.debug("BAR: {x} {x} {x} {x} {x} {x}", .{ g.base_address_registers[0], g.base_address_registers[1], g.base_address_registers[2], g.base_address_registers[3], g.base_address_registers[4], g.base_address_registers[5] });
        log.debug("CardBus CIS Pointer: {x}", .{g.card_bus_cis_pointer});
        log.debug("Subsystem Vendor ID: {x} -- Subsystem ID: {x}", .{ g.subsystem_vendor_id, g.subsystem_id });
        log.debug("Expansion ROM Base Address: {x}", .{g.expansion_rom_base_address});
        log.debug("Capabilities Pointer: {x}", .{g.capabilities_pointer});
        log.debug("Interrupt Line: {x} / Pin: {x}", .{ g.interrupt_line, g.interrupt_pin });
        log.debug("Min Grant: {x} -- Max Latency: {x}", .{ g.min_grant, g.max_latency });
    }
}

fn show_brief_device_info(bus: usize, slot: usize, function: usize, h: DeviceHeader) void {
    console.printf("At {d}:{d}:{d} - {x:0>4}:{x:0>4} ({s}) - {s}\n", .{ bus, slot, function, h.vendor_id, h.device_id, get_vendor_name(h.vendor_id), get_device_class(h.class_code, h.subclass) });
}

fn show_device_info(bus: PCIBus, slot: PCISlot, function: PCIFunction, h: DeviceHeader) void {
    show_brief_device_info(bus, slot, function, h);
    show_full_device_info(bus, slot, function, h);
}

fn check_function(bus: PCIBus, slot: PCISlot, function: PCIFunction) void {
    if (get_device_header(bus, slot, function)) |h| {
        show_device_info(bus, slot, function, h);

        if (h.pci_to_pci_bridge) |p| {
            enumerate_bus(p.secondary_bus_number);
        }
    }
}

fn check_device(bus: PCIBus, slot: PCISlot) void {
    if (get_device_header(bus, slot, 0)) |h| {
        show_device_info(bus, slot, 0, h);

        if ((h.header_type & 0x80) != 0) {
            for (1..8) |function| {
                check_function(bus, slot, @intCast(function));
            }
        }
    }
}

fn enumerate_bus(bus: PCIBus) void {
    for (0..32) |slot| {
        check_device(bus, @intCast(slot));
    }
}

pub fn enumerate_buses() void {
    for (0..256) |bus| {
        enumerate_bus(@intCast(bus));
    }
}

pub fn brute_force_devices() void {
    for (0..256) |bus| {
        for (0..32) |slot| {
            for (0..8) |function| {
                if (get_device_header(@intCast(bus), @intCast(slot), @intCast(function))) |h| {
                    show_device_info(bus, slot, function, h);
                }
            }
        }
    }
}
