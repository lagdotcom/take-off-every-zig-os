const std = @import("std");
const log = std.log.scoped(.pci);

const console = @import("console.zig");
const drivers = @import("driver/pci.zig");
const shell = @import("shell.zig");
const video = @import("video.zig");
const x86 = @import("../arch/x86.zig");

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
    reserved: u7 = 0,
    enable_bit: bool = true,
};

pub fn read_config_address() ConfigAddress {
    return @bitCast(x86.inl(CONFIG_ADDRESS));
}

pub fn config_read_long(addr: ConfigAddress) u32 {
    x86.outl(CONFIG_ADDRESS, @bitCast(addr));
    return x86.inl(CONFIG_DATA);
}

pub fn config_write_byte(addr: ConfigAddress, value: u8) void {
    x86.outl(CONFIG_ADDRESS, @bitCast(addr));
    x86.outb(CONFIG_DATA, value);
}

pub fn config_write_long(addr: ConfigAddress, value: u32) void {
    x86.outl(CONFIG_ADDRESS, @bitCast(addr));
    x86.outl(CONFIG_DATA, value);
}

pub fn get_device_config(bus: PCIBus, slot: PCISlot, function: PCIFunction, offset: u8) u32 {
    return config_read_long(.{
        .register_offset = offset,
        .function_number = function,
        .device_number = slot,
        .bus_number = bus,
    });
}

pub fn config_read_struct(comptime T: type, bus: PCIBus, slot: PCISlot, function: PCIFunction, obj: *T) void {
    std.debug.assert(@mod(@sizeOf(T), @sizeOf(u32)) == 0);
    std.debug.assert(@sizeOf(T) <= std.math.maxInt(u8));
    const raw_pointer: [*]u32 = @ptrCast(obj);

    var u32_offset: u8 = 0;
    while (u32_offset < @divExact(@sizeOf(T), @sizeOf(u32))) {
        raw_pointer[u32_offset] = config_read_long(.{
            .register_offset = u32_offset << 2,
            .function_number = function,
            .device_number = slot,
            .bus_number = bus,
        });
        u32_offset += 1;
    }
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

pub const PCICommand = packed struct {
    io_space: bool,
    memory_space: bool,
    bus_master: bool,
    special_cycles: bool,
    memory_write_and_invalidate: bool,
    vga_palette_snoop: bool,
    parity_error_response: bool,
    zero: bool,
    serr_enable: bool,
    fast_back_to_back_enable: bool,
    interrupt_disable: bool,
    reserved: u5,
};

pub const DEVSELTiming = enum(u2) {
    fast = 0,
    medium = 1,
    slow = 2,
};

pub const PCIStatus = packed struct {
    reserved: u3,
    interrupt_status: bool,
    new_capabilities_list: bool,
    @"66mhz_capable": bool,
    user_definable_features: bool,
    fast_back_to_back_capable: bool,
    master_data_parity: bool,
    devsel_timing: DEVSELTiming,
    signalled_target_abort: bool,
    received_target_abort: bool,
    received_master_abort: bool,
    signalled_system_error: bool,
    detected_parity_error: bool,
};

pub const PCIHeaderType = enum(u7) {
    standard = 0,
    pci_to_pci_bridge,
    card_bus_bridge,
};

pub const PCIHeaderTypeByte = packed struct {
    type: PCIHeaderType,
    multi_function: bool,
};

pub const PCIBuiltInSelfTest = packed struct {
    completion_code: u4,
    reserved: u2,
    start: bool,
    capable: bool,
};

pub const DeviceHeader = struct {
    vendor_id: u16,
    device_id: u16,
    command: PCICommand,
    status: PCIStatus,
    revision_id: u8,
    programming_interface: u8,
    subclass: u8,
    class_code: u8,
    cache_line_size: u8,
    latency_timer: u8,
    header_type: PCIHeaderTypeByte,
    built_in_self_test: PCIBuiltInSelfTest,
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

fn device_exists(bus: PCIBus, slot: PCISlot, function: PCIFunction) bool {
    const long0 = get_device_config(bus, slot, function, 0);

    const vendor_id: u16 = @intCast(long0 & 0xffff);
    return vendor_id != 0xffff;
}

pub fn get_device_header(header: *DeviceHeader, bus: PCIBus, slot: PCISlot, function: PCIFunction) void {
    const long0 = get_device_config(bus, slot, function, 0);

    const vendor_id: u16 = @intCast(long0 & 0xffff);
    const device_id: u16 = @intCast(long0 >> 16);

    const long2 = get_device_config(bus, slot, function, 4);
    const command: u16 = @intCast(long2 & 0xffff);
    const status: u16 = @intCast(long2 >> 16);

    const long3 = get_device_config(bus, slot, function, 8);
    const revision_id: u8 = @intCast(long3 & 0xff);
    const programming_interface: u8 = @intCast((long3 >> 8) & 0xff);
    const subclass: u8 = @intCast((long3 >> 16) & 0xff);
    const class_code: u8 = @intCast(long3 >> 24);

    const long4 = get_device_config(bus, slot, function, 12);
    const cache_line_size: u8 = @intCast(long4 & 0xff);
    const latency_timer: u8 = @intCast((long4 >> 8) & 0xff);
    const header_type_byte: u8 = @intCast((long4 >> 16) & 0xff);
    const built_in_self_test: u8 = @intCast(long4 >> 24);

    const header_type: PCIHeaderTypeByte = @bitCast(header_type_byte);

    header.vendor_id = vendor_id;
    header.device_id = device_id;
    header.command = @bitCast(command);
    header.status = @bitCast(status);
    header.revision_id = revision_id;
    header.programming_interface = programming_interface;
    header.subclass = subclass;
    header.class_code = class_code;
    header.cache_line_size = cache_line_size;
    header.latency_timer = latency_timer;
    header.header_type = header_type;
    header.built_in_self_test = @bitCast(built_in_self_test);
    header.general = if (header_type.type == .standard) get_general_device_header(bus, slot, function) else null;
    header.pci_to_pci_bridge = if (header_type.type == .pci_to_pci_bridge) get_pci_to_pci_bridge_header(bus, slot, function) else null;
}

pub fn get_device_type(header_type: PCIHeaderTypeByte) []const u8 {
    return switch (header_type.multi_function) {
        false => switch (header_type.type) {
            .standard => "General",
            .pci_to_pci_bridge => "PCI-to-PCI Bridge",
            .card_bus_bridge => "PCI-to-CardBus Bridge",
        },
        true => switch (header_type.type) {
            .standard => "General (multi-function)",
            .pci_to_pci_bridge => "PCI-to-PCI Bridge (multi-function)",
            .card_bus_bridge => "PCI-to-CardBus Bridge (multi-function)",
        },
    };
}

pub fn get_device_class(class_code: u8, subclass: u8, interface: u8) []const u8 {
    return switch (class_code) {
        0x00 => switch (subclass) {
            0x00 => "Non-VGA-Compatible Unclassified Device",
            else => "VGA-Compatible Unclassified Device",
        },
        0x01 => switch (subclass) {
            0x00 => "SCSI Bus Controller",
            0x01 => switch (interface) {
                0x00 => "IDE Controller, ISA compatibility mode-only",
                0x05 => "IDE Controller, PCI native mode-only",
                0x0A => "IDE Controller, ISA compatibility mode, supports PCI native",
                0x0F => "IDE Controller, PCI native mode, supports ISA compatibility",
                0x80 => "IDE Controller, ISA Compatibility mode-only, supports bus mastering",
                0x85 => "IDE Controller, PCI native mode-only, supports bus mastering",
                0x8A => "IDE Controller, ISA compatibility mode, supports PCI native, supports bus mastering",
                0x8F => "IDE Controller, PCI native mode, supports ISA compatibility, supports bus mastering",
                else => "IDE Controller",
            },
            0x02 => "Floppy Disk Controller",
            0x03 => "IPI Bus Controller",
            0x04 => "RAID Controller",
            0x05 => switch (interface) {
                0x20 => "ATA Controller, Single DMA",
                0x30 => "ATA Controller, Chained DMA",
                else => "ATA Controller",
            },
            0x06 => switch (interface) {
                0x00 => "SATA Controller, Vendor-Specific",
                0x01 => "SATA Controller, AHCI 1.0",
                0x02 => "SATA Controller, Serial Storage Bus",
                else => "SATA Controller",
            },
            0x07 => switch (interface) {
                0x00 => "Serial Attached SCSI Controller, SAS",
                0x01 => "Serial Attached SCSI Controller, Serial Storage Bus",
                else => "Serial Attached SCSI Controller",
            },
            0x08 => switch (interface) {
                0x01 => "Non-Volatile Memory Controller, NVMHCI",
                0x02 => "Non-Volatile Memory Controller, NVM Express",
                else => "Non-Volatile Memory Controller",
            },
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
            0x00 => switch (interface) {
                0x00 => "VGA Controller",
                0x01 => "8514-Compatible VGA Controller",
                else => "VGA-Compatible Controller",
            },
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
            0x04 => switch (interface) {
                0x00 => "PCI-to-PCI Bridge, Normal Decode",
                0x01 => "PCI-to-PCI Bridge, Subtractive Decode",
                else => "PCI-to-PCI Bridge",
            },
            0x05 => "PCMCIA Bridge",
            0x06 => "NuBus Bridge",
            0x07 => "CardBus Bridge",
            0x08 => switch (interface) {
                0x00 => "RACEway Bridge, Transparent Mode",
                0x01 => "RACEway Bridge, Endpoint Mode",
                else => "RACEway Bridge",
            },
            0x09 => switch (interface) {
                0x40 => "PCI-to-PCI Bridge, Semi-Transparent, Primary bus toward host CPU",
                0x80 => "PCI-to-PCI Bridge, Semi-Transparent, Secondary bus toward host CPU",
                else => "PCI-to-PCI Bridge",
            },
            0x0a => "InfiniBand-to-PCI Host Bridge",
            else => "Unclassified Bridge Device",
        },
        0x07 => switch (subclass) {
            0x00 => switch (interface) {
                0x00 => "Serial Controller, 8250-Compatible",
                0x01 => "Serial Controller, 16450-Compatible",
                0x02 => "Serial Controller, 16550-Compatible",
                0x03 => "Serial Controller, 16650-Compatible",
                0x04 => "Serial Controller, 16750-Compatible",
                0x05 => "Serial Controller, 16850-Compatible",
                0x06 => "Serial Controller, 16950-Compatible",
                else => "Serial Controller",
            },
            0x01 => switch (interface) {
                0x00 => "Parallel Controller, Standard Parallel Port",
                0x01 => "Parallel Controller, Bi-Directional Parallel Port",
                0x02 => "Parallel Controller, ECP 1.x Compliant Parallel Port",
                0x03 => "IEEE 1284 Controller",
                0xfe => "IEEE 1284 Target Device",
                else => "Parallel Controller",
            },
            0x02 => "Multiport Serial Controller",
            0x03 => switch (interface) {
                0x00 => "Generic Modem",
                0x01 => "Modem, Hayes 16450-Compatible",
                0x02 => "Modem, Hayes 16550-Compatible",
                0x03 => "Modem, Hayes 16650-Compatible",
                0x04 => "Modem, Hayes 16750-Compatible",
                else => "Modem",
            },
            0x04 => "IEEE 488.1/2 (GPIB) Controller",
            0x05 => "Smart Card Controller",
            else => "Unclassified Communication Controller",
        },
        0x08 => switch (subclass) {
            0x00 => switch (interface) {
                0x00 => "PIC, Generic 8259-Compatible",
                0x01 => "PIC, ISA-Compatible",
                0x02 => "PIC, EISA-Compatible",
                0x10 => "I/O APIC Interrupt Controller",
                0x20 => "I/O(x) APIC Interrupt Controller",
                else => "PIC",
            },
            0x01 => switch (interface) {
                0x00 => "DMA Controller, Generic 8237-Compatible",
                0x01 => "DMA Controller, ISA-Compatible",
                0x02 => "DMA Controller, EISA-Compatible",
                else => "DMA Controller",
            },
            0x02 => switch (interface) {
                0x00 => "Timer, Generic 8254-Compatible",
                0x01 => "Timer, ISA-Compatible",
                0x02 => "Timer, EISA-Compatible",
                0x03 => "Timer, HPET",
                else => "Timer",
            },
            0x03 => switch (interface) {
                0x00 => "RTC Controller, Generic",
                0x01 => "RTC Controller, ISA-Compatible",
                else => "RTC Controller",
            },
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
            0x04 => switch (interface) {
                0x00 => "Gameport Controller, Generic",
                0x10 => "Gameport Controller, Extended",
                else => "Gameport Controller",
            },
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
            0x00 => switch (interface) {
                0x00 => "FireWire (IEEE 1394) Controller, Generic",
                0x10 => "FireWire (IEEE 1394) Controller, OHCI",
                else => "FireWire (IEEE 1394) Controller",
            },
            0x01 => "ACCESS Bus Controller",
            0x02 => "SSA",
            0x03 => switch (interface) {
                0x00 => "USB Controller, UHCI",
                0x10 => "USB Controller, OHCI",
                0x20 => "USB Controller, EHCI (USB2)",
                0x30 => "USB Controller, XHCI (USB3)",
                0x80 => "USB Controller, Unspecified",
                0xfe => "USB Device",
                else => "USB Controller",
            },
            0x04 => "Fibre Channel",
            0x05 => "SMBus Controller",
            0x06 => "InfiniBand Controller",
            0x07 => switch (interface) {
                0x00 => "IPMI Interface, SMIC",
                0x01 => "IPMI Interface, Keyboard Controller Style",
                0x02 => "IPMI Interface, Block Transfer",
                else => "IPMI Interface",
            },
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

const MemorySpaceBARType = enum(u2) {
    base_32 = 0,
    reserved_16 = 1,
    base_64 = 2,
};

const MemorySpaceBAR = packed struct {
    zero: u1,
    type: MemorySpaceBARType,
    prefetchable: bool,
    base: u28,
};

const IOSpaceBAR = packed struct {
    one: u1,
    reserved: u1,
    base: u30,
};

pub const BaseAddressRegister = union(enum) {
    memory: struct {
        base: u32,
        type: MemorySpaceBARType,
        prefetchable: bool,
    },
    io: struct { base: u32 },
};

fn parse_bar(bar: u32) BaseAddressRegister {
    if ((bar & 0x01) == 0) {
        const memory: MemorySpaceBAR = @bitCast(bar);
        const raw = bar & 0xfffffff0;

        const base: u32 = switch (memory.type) {
            .base_32, .base_64 => raw,
            .reserved_16 => raw & 0x0000ffff,
        };

        return .{ .memory = .{
            .type = memory.type,
            .prefetchable = memory.prefetchable,
            .base = base,
        } };
    }

    return .{ .io = .{ .base = bar & 0xfffffffc } };
}

fn show_bar_info(index: usize, bar: u32) void {
    switch (parse_bar(bar)) {
        .memory => |mem| log.debug("BAR[{d}]: memory {x} {s} {s}", .{ index, mem.base, @tagName(mem.type), if (mem.prefetchable) "prefetchable" else "" }),
        .io => |io| log.debug("BAR[{d}]: io {x}", .{ index, io.base }),
    }
}

fn show_full_device_info(bus: usize, slot: usize, function: usize, h: DeviceHeader) void {
    log.debug("Location: {d}:{d}:{d}", .{ bus, slot, function });
    log.debug("Vendor/Device ID: {x:0>4}:{x:0>4} ({s})", .{ h.vendor_id, h.device_id, get_vendor_name(h.vendor_id) });
    log.debug("Class: {x}:{x}:{x} r{d} ({s})", .{ h.class_code, h.subclass, h.programming_interface, h.revision_id, get_device_class(h.class_code, h.subclass, h.programming_interface) });
    log.debug("Command: {any}", .{h.command});
    log.debug("Status: {any}", .{h.status});
    log.debug("Cache Line Size: {x} -- Latency Timer: {x}", .{ h.cache_line_size, h.latency_timer });
    log.debug("BIST: {any}", .{h.built_in_self_test});

    if (h.general) |g| {
        inline for (g.base_address_registers, 0..) |bar, i|
            if (bar > 0) show_bar_info(i, bar);

        log.debug("CardBus CIS Pointer: {x}", .{g.card_bus_cis_pointer});
        log.debug("Subsystem Vendor ID: {x} -- Subsystem ID: {x}", .{ g.subsystem_vendor_id, g.subsystem_id });
        log.debug("Expansion ROM Base Address: {x}", .{g.expansion_rom_base_address});
        log.debug("Capabilities Pointer: {x}", .{g.capabilities_pointer});
        log.debug("Interrupt Line: {x} / Pin: {x}", .{ g.interrupt_line, g.interrupt_pin });
        log.debug("Min Grant: {x} -- Max Latency: {x}", .{ g.min_grant, g.max_latency });
    }

    if (h.pci_to_pci_bridge) |b| {
        inline for (b.base_address_registers, 0..) |bar, i|
            if (bar > 0) show_bar_info(i, bar);

        log.debug("BAR: {x} {x}", .{ b.base_address_registers[0], b.base_address_registers[1] });
        log.debug("Primary Bus: {d} -- Secondary Bus: {d} / Latency: {d} -- Subordinate Bus: {d}", .{ b.primary_bus_number, b.secondary_bus_number, b.secondary_latency_timer, b.subordinate_bus_number });
        log.debug("Secondary Status: {d}", .{b.secondary_status});
        log.debug("I/O Base: {x}{x:0>2}, Limit: {x}{x:0>2}", .{ b.io_base_upper_16_bits, b.io_base, b.io_limit_upper_16_bits, b.io_limit });
        log.debug("Memory Base: {x}, Limit: {x}", .{ b.memory_base, b.memory_limit });
        log.debug("Prefetchable Memory Base: {x}{x:0>4}, Limit: {x}{x:0>4}", .{ b.prefetchable_base_upper_32_bits, b.prefetchable_memory_base, b.prefetchable_limit_upper_32_bits, b.prefetchable_memory_limit });
        log.debug("Capability Pointer: {d}", .{b.capabilities_pointer});
        log.debug("Expansion ROM Base Address: {x}", .{b.expansion_rom_base_address});
        log.debug("Interrupt Line: {x} / Pin: {x}", .{ b.interrupt_line, b.interrupt_pin });
        log.debug("Bridge Control: {d}", .{b.bridge_control});
    }
}

const AddDeviceError = std.mem.Allocator.Error;

fn add_device(bus: PCIBus, slot: PCISlot, function: PCIFunction) AddDeviceError!*const DeviceHeader {
    const header = try pci_devices.allocator.create(DeviceHeader);
    get_device_header(header, bus, slot, function);

    try pci_devices.append(.{
        .bus = bus,
        .slot = slot,
        .function = function,
        .id = .{ .vendor_id = header.vendor_id, .device_id = header.device_id },
        .header = header,
    });

    return header;
}

fn check_function(bus: PCIBus, slot: PCISlot, function: PCIFunction) AddDeviceError!void {
    if (device_exists(bus, slot, function)) {
        const h = try add_device(bus, slot, function);

        if (h.pci_to_pci_bridge) |p|
            try enumerate_bus(p.secondary_bus_number);
    }
}

fn check_device(bus: PCIBus, slot: PCISlot) AddDeviceError!void {
    if (device_exists(bus, slot, 0)) {
        const h = try add_device(bus, slot, 0);

        if (h.header_type.multi_function) {
            for (1..8) |function|
                try check_function(bus, slot, @intCast(function));
        }
    }
}

fn enumerate_bus(bus: PCIBus) AddDeviceError!void {
    for (0..32) |slot|
        try check_device(bus, @intCast(slot));
}

fn enumerate_buses() AddDeviceError!void {
    for (0..256) |bus|
        try enumerate_bus(@intCast(bus));
}

fn brute_force_devices() AddDeviceError!void {
    for (0..256) |bus| {
        for (0..32) |slot| {
            for (0..8) |function| {
                if (device_exists(@intCast(bus), @intCast(slot), @intCast(function)))
                    _ = try add_device(bus, slot, function);
            }
        }
    }
}

fn shell_pci_list(sh: *shell.Context, _: []const u8) !void {
    var t = try sh.table();
    defer t.deinit();

    try t.add_heading(.{ .name = "Loc." });
    try t.add_heading(.{ .name = "VnID:DvID" });
    try t.add_heading(.{ .name = "Vendor" });
    try t.add_heading(.{ .name = "Type" });

    for (pci_devices.items) |dev| {
        const h = dev.header;

        try t.add_fmt("{d}:{d}:{d}", .{ dev.bus, dev.slot, dev.function });
        try t.add_fmt("{x:0>4}:{x:0>4}", .{ h.vendor_id, h.device_id });
        try t.add_string(get_vendor_name(h.vendor_id));
        try t.add_string(get_device_class(h.class_code, h.subclass, h.programming_interface));

        try t.end_row();
    }
    t.print();
}

pub const DriverStatus = enum(u8) {
    stopped,
    starting,
    running,
};

pub const PCIDriver = struct {
    attach: *const fn (allocator: std.mem.Allocator, device: *const PCIDevice) void,
    get_status: *const fn () DriverStatus,
};
const PCIDriverMap = std.AutoHashMap(DeviceID, *const PCIDriver);
pub var pci_driver_map: PCIDriverMap = undefined;

pub const PCIDevice = struct {
    bus: PCIBus,
    slot: PCISlot,
    function: PCIFunction,
    id: DeviceID,
    header: *const DeviceHeader,
};
const PCIDeviceList = std.ArrayList(PCIDevice);
pub var pci_devices: PCIDeviceList = undefined;

pub fn initialize(allocator: std.mem.Allocator) !void {
    log.debug("initializing", .{});
    defer log.debug("done", .{});

    try shell.add_command(.{
        .name = "pci",
        .summary = "Get information on PCI devices",
        .sub_commands = &.{.{
            .name = "list",
            .summary = "List available PCI devices",
            .exec = shell_pci_list,
        }},
    });

    pci_driver_map = PCIDriverMap.init(allocator);
    try drivers.initialize();

    pci_devices = PCIDeviceList.init(allocator);
    try enumerate_buses();

    for (pci_devices.items) |*dev| start_driver(allocator, dev);
}

pub fn add_driver(id: DeviceID, driver: *const PCIDriver) !void {
    try pci_driver_map.put(id, driver);
}

fn start_driver(allocator: std.mem.Allocator, device: *const PCIDevice) void {
    if (pci_driver_map.get(device.id)) |driver| {
        if (driver.get_status() == .stopped) {
            log.debug("attempting to start driver for {x}:{x}", .{ device.id.vendor_id, device.id.device_id });
            driver.attach(allocator, device);
        }
    } else log.warn("no driver found for {x}:{x}", .{ device.id.vendor_id, device.id.device_id });
}
