const std = @import("std");
const log = std.log.scoped(.PIIX_IDE);

const ata = @import("../../../ata.zig");
const common = @import("common.zig");
const interrupts = @import("../../../interrupts.zig");
const pci = @import("../../../pci.zig");
const pic = @import("../../../pic.zig");
const tools = @import("../../../tools.zig");
const x86 = @import("../../../../arch/x86.zig");

const Command = packed struct {
    io_space_access_enable: bool,
    memory_access_enable: bool = true,
    bus_master_enable: bool,
    special_cycle_enable: bool = false,
    postable_memory_write_enable: bool = false,
    reserved_5: u4 = 0,
    fast_back_to_back_enable: bool = false,
    reserved_10: u6 = 0,
};

const Status = packed struct {
    reserved_0: u7 = 0,
    fast_back_to_back: bool = true,
    perr_response: bool = false,
    devsel_timing_status: u2 = 1,
    signalled_target_abort_status: bool,
    received_target_abort_status: bool,
    master_abort_status: bool,
    signalled_serr_status: bool = false,
    detected_parity_error: bool = false,
};

const BusMasterInterfaceBaseAddress = packed struct {
    resource_type_indicator: bool = true, // IO space address
    reserved_1: u1,
    reserved_2: u2 = 0,
    base_address: u12, // treat first two bytes as address, mask off first bit
    reserved_16: u16 = 0,
};

const RecoveryTime = enum(u2) { @"4" = 0, @"3", @"2", @"1" };
const IORDYSamplePoint = enum(u2) { @"5" = 0, @"4", @"3", @"2" };

const TimingModes = packed struct {
    fast_timing_bank_drive_select_0: bool,
    iordy_sample_point_enable_drive_select_0: bool,
    prefetch_and_posting_enable_0: bool,
    dma_timing_enable_only_0: bool,
    fast_timing_bank_drive_select_1: bool,
    iordy_sample_point_enable_drive_select_1: bool,
    prefetch_and_posting_enable_1: bool,
    dma_timing_enable_only_1: bool,
    recovery_time: RecoveryTime,
    reserved: u2,
    iordy_sample_point: IORDYSamplePoint,
    secondary_ide_timing_register_enable: bool,
    ide_decode_enable: bool,
};

const SecondaryTimingModes = packed struct {
    primary_drive_1_recovery_time: RecoveryTime,
    primary_drive_1_iordy_sample_point: IORDYSamplePoint,
    secondary_drive_1_recovery_time: RecoveryTime,
    secondary_drive_1_iordy_sample_point: IORDYSamplePoint,
};

const Config = extern struct {
    vendor_id: u16, // 8086
    device_id: u16, // 1230/7010
    command: Command,
    status: Status,
    revision_id: u8,
    class_code: [3]u8, // 80 01 01
    reserved_0c: u8,
    master_latency_timer: common.MasterLatencyTimer,
    header_type: u8, // 00
    reserved_0f: [17]u8,
    bus_master_interface_base_address: BusMasterInterfaceBaseAddress,
    reserved_24: [28]u8,
    timing_modes: [2]TimingModes,
    secondary_timing_modes: SecondaryTimingModes, // PIIX3 only
    // reserved_45: [187]u8,
};

const RegisterAccess = union(enum) {
    memory: struct { primary: usize, secondary: usize },
    port: struct { primary: u16, secondary: u16 },
};

const BusMasterMode = enum(u1) { read = 0, write };

const BusMasterCommand = packed struct {
    start: bool,
    reserved_1: u2,
    mode: BusMasterMode,
    reserved_4: u4,
};

const BusMasterStatus = packed struct {
    active: bool = false,
    dma_error: bool = false,
    interrupt: bool = false, // primary=IRQ14, secondary=IRQ15
    reserved_3: u2 = 0,
    drive_0_dma_capable: bool = false,
    drive_1_dma_capable: bool = false,
    reserved_7: u1 = 0,
};

// const BusMasterChannel = packed struct {
//     command: BusMasterCommand,
//     reserved_1: u8,
//     status: BusMasterStatus,
//     reserved_2: u8,
//     descriptor_table: [*]PhysicalRegionDescriptor,
// };

// const BusMaster = struct {
//     primary: BusMasterChannel,
//     secondary: BusMasterChannel,
// };

const PhysicalRegionDescriptor = struct {
    base: u32, // first bit ignored
    size: u16, // first bit ignored, if no bits set then size = 64KiB
    reserved: u7,
    end_of_table: bool,
};

pub var allocator: std.mem.Allocator = undefined;

var status = pci.DriverStatus.stopped;
fn get_status() pci.DriverStatus {
    return status;
}

var bus_master_base_port: ?u16 = null;

fn irq_handler(ctx: *interrupts.CpuState) usize {
    log.debug("got interrupt", .{});
    const base = bus_master_base_port.?;

    // When an interrupt arrives (after the transfer is complete), respond by resetting the Start/Stop bit.
    write_bus_master_command(base, .{ .start = false, .mode = .read, .reserved_1 = 0, .reserved_4 = 0 });

    // Clear interrupt bit.
    clear_bus_master_status_bits(base, .{ .interrupt = true });

    // Read the controller and drive status to determine if the transfer completed successfully.
    report_bus_master_status(base, "during interrupt");

    ata.primary.report_status();

    return @intFromPtr(ctx);
}

fn read_bus_master_status(base: u16) BusMasterStatus {
    return @bitCast(x86.inb(base + 2));
}
fn clear_bus_master_status_bits(base: u16, value: BusMasterStatus) void {
    x86.outb(base + 2, @bitCast(value));
}
fn report_bus_master_status(base: u16, comptime prefix: []const u8) void {
    const value = read_bus_master_status(base);
    log.debug("bus master status (" ++ prefix ++ "):{s}{s}{s}{s}{s}", .{
        if (value.active) " active" else "",
        if (value.dma_error) " error" else "",
        if (value.interrupt) " interrupt" else "",
        if (value.drive_0_dma_capable) " d0" else "",
        if (value.drive_1_dma_capable) " d1" else "",
    });
}

fn write_bus_master_command(base: u16, value: BusMasterCommand) void {
    x86.outb(base, @bitCast(value));
    log.debug("bus master command <= {any}", .{value});
}

fn write_bus_master_prd_address(base: u16, value: [*]PhysicalRegionDescriptor) void {
    x86.outl(base + 4, @intFromPtr(value));
    log.debug("bus master PRD table <= {x}", .{@intFromPtr(value)});
}

pub const piix3 = pci.DeviceID{ .vendor_id = 0x8086, .device_id = 0x7010 };
pub const piix3_driver = pci.PCIDriver{ .attach = attach_piix3, .get_status = get_status };

const prd_sector_size = 0x10000;
var sector_read_buffer: [prd_sector_size]u8 align(std.mem.page_size) = undefined;
var prd_table: [1]PhysicalRegionDescriptor align(std.mem.page_size) = undefined;
var cfg: Config = undefined;
var bus_number: pci.PCIBus = 0;
var device_number: pci.PCISlot = 0;
var function_number: pci.PCIFunction = 0;

pub fn attach_piix3(bus: pci.PCIBus, slot: pci.PCISlot, function: pci.PCIFunction) void {
    status = .starting;
    log.debug("PIIX3 attaching to {d}:{d}:{d}", .{ bus, slot, function });
    defer log.debug("done", .{});

    bus_number = bus;
    device_number = slot;
    function_number = function;

    pci.config_read_struct(Config, bus, slot, function, &cfg);

    if (cfg.class_code[0] & 0x80 == 0x80) {
        const raw: u32 = @bitCast(cfg.bus_master_interface_base_address);
        const raw_16: u16 = @truncate(raw);
        bus_master_base_port = raw_16 & 0xfff0;

        log.debug("bus master support @{x}", .{raw & 0xfffffff0});
    }

    // turn on IO Space Enable so we can use legacy IDE
    // if (!cfg.command.io_space_access_enable or cfg.command.bus_master_enable) {
    //     cfg.command.bus_master_enable = false;
    //     cfg.command.io_space_access_enable = true;

    //     const raw_ptr: *u32 = @ptrCast(&cfg.command);

    //     pci.config_write_long(.{
    //         .bus_number = bus,
    //         .device_number = slot,
    //         .function_number = function,
    //         .register_offset = @offsetOf(Config, "command"),
    //     }, raw_ptr.*);

    //     log.debug("enabled io_space_access, disabled bus_master", .{});
    // }

    // turn on IDE Decode for primary drive so we can use ATA for now?
    // if (!cfg.timing_modes[0].ide_decode_enable) {
    //     cfg.timing_modes[0].ide_decode_enable = true;

    //     const raw_ptr: *u32 = @ptrCast(&cfg.timing_modes);

    //     pci.config_write_long(.{
    //         .bus_number = bus,
    //         .device_number = slot,
    //         .function_number = function,
    //         .register_offset = @offsetOf(Config, "timing_modes"),
    //     }, raw_ptr.*);

    //     log.debug("enabled ide_decode", .{});
    // }

    // test_bmdma_transfer(true, 1);
    // test_pio_transfer(false, 0);
    // test_pio_transfer(false, 1);
    // test_pio_transfer(true, 0);
    test_pio_transfer(true, 1);
}

fn test_bmdma_transfer(secondary_bus: bool, drive_number: u1) void {
    const bus = if (secondary_bus) ata.secondary else ata.primary;
    const irq: interrupts.IRQ = if (secondary_bus) .secondary_ata else .primary_ata;

    const ata_device = bus.detect_device_type(drive_number);
    log.debug("{s} ata bus drive {d}, ata type: {s}", .{ bus.name, drive_number, @tagName(ata_device) });

    // const PCI_INTERRUPT_LINE = 0x3C;
    // const cfg_raw: [*]u8 = @ptrCast(&cfg);
    // const ide_irq = cfg_raw[PCI_INTERRUPT_LINE];
    // if (ide_irq != 14) {
    //     log.debug("pci interrupt line = {d}, changing to 14", .{ide_irq});
    //     cfg_raw[PCI_INTERRUPT_LINE] = 14;

    //     pci.config_write_byte(.{
    //         .bus_number = bus_number,
    //         .device_number = device_number,
    //         .function_number = function_number,
    //         .register_offset = PCI_INTERRUPT_LINE,
    //     }, 14);
    // }

    // pci.config_read_struct(Config, bus, slot, function, &cfg);
    // log.debug("Config:", .{});
    // inline for (std.meta.fields(Config)) |f| log.debug("  .{s} = {any}", .{ f.name, @field(cfg, f.name) });

    if (bus_master_base_port) |base| {
        // TODO turn on bus master support on Config if necessary

        report_bus_master_status(base, "start");

        // TODO The data buffers cannot cross a 64K boundary, and must be contiguous in physical memory.
        // const buf = allocator.alignedAlloc(u8, std.mem.page_size, sector_size) catch unreachable;

        // Prepare a PRDT in system memory.
        // TODO The PRDT must be uint32_t aligned, contiguous in physical memory, and cannot cross a 64K boundary.
        // const prd_table = allocator.alignedAlloc(PhysicalRegionDescriptor, std.mem.page_size, 1) catch unreachable;
        prd_table[0].base = @intFromPtr(&sector_read_buffer);
        prd_table[0].size = if (sector_read_buffer.len == prd_sector_size) 0 else @intCast(sector_read_buffer.len);
        prd_table[0].end_of_table = true;

        // Send the physical PRDT address to the Bus Master PRDT Register.
        write_bus_master_prd_address(base, &prd_table);
        report_bus_master_status(base, "after prd write");

        // Set the direction of the data transfer by setting the Read/Write bit in the Bus Master Command Register.
        var cmd: BusMasterCommand = .{ .start = false, .mode = .read, .reserved_1 = 0, .reserved_4 = 0 };
        write_bus_master_command(base, cmd);
        report_bus_master_status(base, "after mode set");

        // Clear the Error and Interrupt bit in the Bus Master Status Register.
        clear_bus_master_status_bits(base, .{ .dma_error = true, .interrupt = true });
        report_bus_master_status(base, "after clear");

        // (set up for IRQ handling)
        interrupts.set_irq_handler(irq, irq_handler, "piix3_ide_irq_handler");
        pic.clear_mask(irq);

        // Select the drive.
        // Send the LBA and sector count to their respective ports.
        // Send the DMA transfer command to the ATA controller.
        bus.set_lba28(0, drive_number, 1);
        bus.dma_read();

        // Set the Start/Stop bit on the Bus Master Command Register.
        cmd.start = true;
        write_bus_master_command(base, cmd);
        report_bus_master_status(base, "after command");

        bus.report_status();
    }

    // log.debug("Config:", .{});
    // inline for (std.meta.fields(Config)) |f|
    //     log.debug("  .{s} = {any}", .{ f.name, @field(cfg, f.name) });

    // const primary_ata = ata.ATABus.init(PRIMARY_COMMAND_BLOCK_OFFSET, PRIMARY_CONTROL_BLOCK_OFFSET);
    // primary_ata.soft_reset();
    // primary_ata.report_status();

    // {
    //     // try to identify primary drive
    //     x86.outb(PRIMARY_COMMAND_BLOCK_OFFSET + 6, 0xa0); // primary drive

    //     // read status FIFTEEN TIMES lol
    //     var ide_status: u8 = 0;
    //     for (0..15) |_| ide_status = x86.inb(PRIMARY_COMMAND_BLOCK_OFFSET + 7);

    //     // reset old values
    //     x86.outb(PRIMARY_COMMAND_BLOCK_OFFSET + 2, 0); // sector count
    //     x86.outb(PRIMARY_COMMAND_BLOCK_OFFSET + 3, 0); // LBA lo
    //     x86.outb(PRIMARY_COMMAND_BLOCK_OFFSET + 4, 0); // LBA mid
    //     x86.outb(PRIMARY_COMMAND_BLOCK_OFFSET + 5, 0); // LBA hi

    //     x86.outb(PRIMARY_COMMAND_BLOCK_OFFSET + 7, 0xec); // IDENTIFY

    //     const result = x86.inb(PRIMARY_COMMAND_BLOCK_OFFSET + 7);
    //     log.debug("IDENTIFY got {x}", .{result});

    //     if (result != 0) {
    //         while ((x86.inb(PRIMARY_COMMAND_BLOCK_OFFSET + 7) & 0x80) != 0) {}
    //     }
    // }
}

var swap_buf: [64]u8 = undefined;
fn get_swapped(src: []const u8, len: usize) []u8 {
    var i: usize = 0;
    while (i < len) {
        swap_buf[i] = src[i + 1];
        swap_buf[i + 1] = src[i];
        i += 2;
    }

    return swap_buf[0..len];
}

fn test_pio_transfer(secondary_bus: bool, drive_number: u1) void {
    const bus = if (secondary_bus) ata.secondary else ata.primary;

    bus.soft_reset();
    const ata_device = bus.detect_device_type(drive_number);
    log.debug("{s} drive {d}, ata type: {s}", .{ bus.name, drive_number, @tagName(ata_device) });

    // if (ata_device == .patapi) {
    //     if (bus.pio_atapi_read(0, drive_number, 1, @ptrCast(&sector_read_buffer))) {
    //         log.debug("atapi read successful", .{});
    //     } else {
    //         log.debug("atapi read failed", .{});
    //     }
    // }

    var identity: ata.DeviceIdentification = undefined;

    switch (ata_device) {
        .patapi, .satapi => {
            log.debug("trying to get ATAPI id", .{});

            if (!bus.identify_packet_device(drive_number, @ptrCast(&identity))) {
                log.debug("{s} drive {d} identify failed", .{ bus.name, drive_number });
                return;
            }
        },
        else => {
            if (!bus.identify(drive_number, &identity)) {
                log.debug("{s} drive {d} not present, abandoning test transfer", .{ bus.name, drive_number });
                return;
            }
        },
    }

    tools.struct_dump(ata.DeviceIdentification, log.debug, &identity);

    switch (ata_device) {
        .patapi, .satapi => {
            const atapi_type: ata.ATAPIDeviceType = @bitCast(identity.general_configuration);
            log.debug("atapi_type: {any}", .{atapi_type});
        },
        else => {},
    }

    log.debug("serial_number: {s}", .{get_swapped(&identity.serial_number, 20)});
    log.debug("firmware_revision: {s}", .{get_swapped(&identity.firmware_revision, 8)});
    log.debug("model_number: {s}", .{get_swapped(&identity.model_number, 40)});

    const sector_count = 1;
    const lba = 0;
    std.debug.assert(@as(usize, ata.sector_size) * sector_count <= sector_read_buffer.len);

    switch (ata_device) {
        .patapi, .satapi => {
            const success = bus.pio_atapi_read(lba, drive_number, sector_count, @ptrCast(&sector_read_buffer));
            log.debug("ATAPI read: {any}", .{success});
            // TODO make this API similar to the other one?
        },
        else => {
            bus.set_lba28(lba, drive_number, sector_count);
            bus.pio_read();

            for (0..sector_count) |sector_index| {
                log.debug("waiting for RDY", .{});
                while (!bus.get_alt_status().data_request) {}
                bus.report_status();

                const buf_u16: [*]u16 = @ptrCast(&sector_read_buffer);

                for (0..ata.sector_size / 2) |i| {
                    const data = bus.get_data_word();
                    buf_u16[i] = data;
                }

                log.debug("read {d} bytes", .{ata.sector_size});
                bus.report_status();

                log.debug("sector {d}:", .{sector_index});
                tools.hex_dump(log.debug, sector_read_buffer[0..ata.sector_size]);

                log.debug("ending lba address = {d}", .{bus.read_final_lba()});
            }
        },
    }
}
