const std = @import("std");
const log = std.log.scoped(.ata);

const console = @import("console.zig");
const shell = @import("shell.zig");
const x86 = @import("../arch/x86.zig");

pub const Error = packed struct {
    address_mark_not_found: bool,
    track_zero_not_found: bool,
    aborted_command: bool,
    media_change_request: bool,
    id_not_found: bool,
    media_changed: bool,
    uncorrectable_data_error: bool,
    bad_block_detected: bool,
};

const AddressMode = enum(u1) { chs = 0, lba };

pub const DriveNumber = u1;

const DriveHead = packed struct {
    lba_hi2: u4 = 0,
    drive_number: DriveNumber,
    reserved_5: u1 = 1,
    address_mode: AddressMode = .chs,
    reserved_7: u1 = 1,
};

pub const Status = packed struct {
    err: bool,
    index: bool = 0,
    corrected_data: bool = 0,
    data_request: bool,
    drive_seek_complete: bool,
    drive_write_fault: bool,
    drive_ready: bool,
    busy: bool,
};

const command_offsets = struct {
    const rw_data = 0;
    const r_err = 1;
    const w_features = 1;
    const rw_sector_count = 2;
    const rw_sector_number = 3;
    const rw_lba_lo = 3;
    const rw_cylinder_lo = 4;
    const rw_lba_mid = 4;
    const rw_cylinder_hi = 5;
    const rw_lba_hi = 5;
    const rw_drive_head = 6;
    const r_status = 7;
    const w_command = 7;
};

pub const DeviceControl = packed struct {
    reserved_0: u1 = 0,
    interrupts_disabled: bool = false,
    software_reset: bool = false,
    reserved_3: u4 = 1,
    read_high_order_byte: bool = false,
};

pub const DriveAddress = packed struct {
    select_drive_0: bool,
    select_drive_1: bool,
    head: u4,
    write_gate: bool,
    reserved: u1,
};

const control_offsets = struct {
    const r_alternate_status = 0;
    const w_device_control = 0;
    const r_drive_address = 1;
};

const Command = enum(u8) {
    nop = 0,
    read_sectors = 0x20, // IBM PC/AT to present
    read_sectors_no_retry,
    read_sectors_ext = 0x24, // ATA-6 to present
    write_sectors = 0x30, // IBM PC/AT to present
    write_sectors_no_retry,
    write_long = 0x32,
    write_long_no_retry,
    write_verify = 0x3c,
    read_verify_sectors = 0x40,
    read_verify_sectors_no_retry,
    format_track = 0x50,
    execute_drive_diagnostic = 0x90,
    initialize_drive_parameters = 0x91,
    packet = 0xa0, // ATA-3 to ACS-3
    identify_packet_device = 0xa1, // ATA-3 to ACS-3
    write_multiple = 0xc5,
    set_multiple_mode = 0xc6,
    read_dma = 0xc8, // ATA-1 to present
    read_dma_no_retry,
    write_dma = 0xca,
    write_dma_no_return,
    acknowledge_media_change = 0xdb,
    boot_post_boot = 0xdc,
    boot_pre_boot = 0xdd,
    door_lock = 0xde,
    door_unlock = 0xdf,
    read_buffer = 0xe4,
    write_buffer = 0xe8,
    write_same = 0xe9,
    identify = 0xec, // ATA-1 to present
    set_features = 0xef,
};

const DeviceType = enum {
    patapi,
    satapi,
    pata,
    sata,
    unknown,
};

const GeneralConfiguration = packed struct {
    reserved_0: u1,
    hard_sectored: bool,
    soft_sectored: bool,
    not_mfm_encoded: bool,
    head_switch_time_over_15usec: bool,
    spindle_motor_control_option_implemented: bool,
    fixed_device: bool,
    removable_media: bool,
    disk_transfer_rate_5mbps_or_less: bool,
    disk_transfer_rate_10mbps_or_less: bool,
    disk_transfer_rate_over_10mbps: bool,
    rotational_speed_tolerance_over_0_5_percent: bool,
    data_strobe_offset_option_available: bool,
    track_offset_option_available: bool,
    format_speed_tolerance_gap_required: bool,
    non_magnetic: bool,
};

const DeviceCapabilities = packed struct {
    current_long_physical_sector_alignment: u2,
    reserved_a: u6,
    dma_supported: bool,
    lba_supported: bool,
    can_disable_iordy: bool,
    iordy_supported: bool,
    reserved_b: u1,
    standby_timer_support: bool,
    reserved_c: u2,
    reserved_d: u16,
};

const Supported = packed struct {
    multi_sector_setting_valid: bool,
    reserved: u3,
    sanitize_feature_supported: bool,
    crypto_scramble_ext_command_supported: bool,
    overwrite_ext_command_supported: bool,
    block_erase_ext_command_supported: bool,
};

const AdditionalSupported = packed struct {
    ZonedCapabilities: u2,
    NonVolatileWriteCache: bool,
    ExtendedUserAddressableSectorsSupported: bool,
    DeviceEncryptsAllUserData: bool,
    ReadZeroAfterTrimSupported: bool,
    Optional28BitCommandsSupported: bool,
    IEEE1667: bool,
    DownloadMicrocodeDmaSupported: bool,
    SetMaxSetPasswordUnlockDmaSupported: bool,
    WriteBufferDmaSupported: bool,
    ReadBufferDmaSupported: bool,
    DeviceConfigIdentifySetDmaSupported: bool,
    LPSAERCSupported: bool,
    DeterministicReadAfterTrimSupported: bool,
    CFastSpecSupported: bool,
};

const TrustedComputing = packed struct {
    feature_supported: bool,
    reserved: u15,
};

const DMAFlags = packed struct {
    pio: bool,
    dma: bool,
    prefer_interrupt: bool,
    unknown: u5,
};

const TranslationFieldsValidity = packed struct {
    words_54_58_valid: bool,
    words_64_70_value: bool,
    reserved: u6,
};

pub const DeviceIdentification = extern struct {
    general_configuration: GeneralConfiguration,
    cylinder_count: u16,
    reserved_2: u16,
    head_count: u16,
    unformatted_bytes_per_track: u16,
    unformatted_bytes_per_sector: u16,
    sectors_per_track: u16,
    vendor_7: [3]u16,
    serial_number: [20]u8,
    buffer_type: u16,
    buffer_size_in_sectors: u16,
    ecc_byte_count: u16,
    firmware_revision: [8]u8,
    model_number: [40]u8,
    maximum_block_transfer: u8, // max number of sectors passable to READ/WRITE MULTIPLE
    vendor_47: u8,
    trusted_computing: TrustedComputing align(1),
    capabilities: DeviceCapabilities align(1),
    vendor_51: u8,
    pio_data_transfer_cycle_timing_mode: u8,
    vendor_52: u8,
    dma_data_transfer_cycle_timing_mode: u8,
    translation_fields_valid: TranslationFieldsValidity,
    free_fall_control_sensitivity: u8,
    current_cylinder_count: u16 align(1),
    current_head_count: u16 align(1),
    current_sectors_per_track: u16 align(1),
    current_capacity_in_sectors: u32 align(1),
    current_maximum_block_transfer: u8,
    supported: Supported,
    use_addressable_sector_count: u32 align(1),
    single_word_dma_support: DMAFlags,
    single_word_dma_active: DMAFlags,
    multi_word_dma_support: DMAFlags,
    multi_word_dma_active: DMAFlags,
    advanced_pio_modes: u8,
    reserved_64: u8,
    minimum_mw_dma_xfer_cycle_time: u16 align(1),
    recommended_mw_dma_xfer_cycle_time: u16,
    minimum_pio_xfer_cycle_time: u16,
    minimum_pio_xfer_cycle_time_iordy: u16,
    additional_supported: AdditionalSupported,
    reserved_h: [5]u16,
    queue_depth: u16,
    serial_ata_capabilities: u32,
    serial_ata_features_supported: u16,
    serial_ata_features_enabled: u16,
    major_revision: u16,
    minor_revision: u16,
    command_set_support: [3]u16,
    command_set_active: [3]u16,
    ultra_dma_support: u8,
    ultra_dma_active: u8,
    normal_security_erase_unit: u16,
    enhanced_security_erase_unit: u16,
    current_apm_level: u8,
    reserved_i: u8,
    master_password_id: u16,
    hardware_reset_result: u16,
    current_acoustic_value: u8,
    recommended_acoustic_value: u8,
    stream_min_request_size: u16,
    streaming_transfer_time_dma: u16,
    streaming_access_latency_dma_pio: u16,
    streaming_perf_granularity: u32,
    max_48bit_lba: [2]u32,
    streaming_transfer_time: u16,
    dsm_cap: u16,
    physical_logical_sector_size: u16,
    inter_seek_delay: u16,
    world_wide_name: [4]u16,
    reserved_j: [4]u16,
    reserved_k: u16,
    words_per_logical_sector: [2]u16,
    command_set_support_ext: u16,
    command_set_active_ext: u16,
    reserved_l: [6]u16,
    msn_support: u16,
    security_status: u16,
    reserved_m: [31]u16,
    cfa_power_model: u16,
    reserved_n: [7]u16,
    nominal_form_factor: u16,
    data_set_management_feature: u16,
    additional_product_id: [4]u16,
    reserved_o: [2]u16,
    current_media_serial_number: [30]u16,
    sct_command_transport: u16,
    reserved_p: [2]u16,
    block_alignment: u16,
    write_verify_sector_count_mode_3_only: [2]u16,
    write_verify_sector_count_mode_2_only: [2]u16,
    nv_cache_capabilities: u16,
    nv_cache_size_lsw: u16,
    nv_cache_size_msw: u16,
    nominal_media_rotation_rate: u16,
    reserved_q: u16,
    nv_cache_options: u16,
    write_read_verify_sector_count_mode: u16,
    reserved_r: u16,
    transport_major_version: packed struct { major_version: u12, transport_type: u4 },
    transport_minor_version: u16,
    reserved_s: [6]u16,
    extended_number_of_user_addressable_sectors: [2]u32,
    min_blocks_per_download_microcode_mode_03: u16,
    max_blocks_per_download_microcode_mode_03: u16,
    reserved_t: [19]u16,
    signature: u8,
    checksum: u8,
};

pub const ATAPIDeviceType = packed struct {
    reserved_1: u8,
    type: enum(u2) { hdd = 0, tape, cd_dvd, optical },
    reserved_2: u5,
    atapi: bool,
};

pub const ATAPIMajorVersion = enum(u16) {
    ATAPI_4 = 0x1e,
};

pub const sector_size: usize = 512;

pub const Bus = struct {
    name: []const u8,
    is_secondary: bool,
    command: u16,
    control: u16,

    pub fn init(is_secondary: bool, command_base: u16, control_base: u16) Bus {
        return .{
            .name = if (is_secondary) "secondary" else "primary",
            .is_secondary = is_secondary,
            .command = command_base,
            .control = control_base,
        };
    }

    fn write_device_control(self: *const Bus, value: DeviceControl) void {
        x86.outb(self.control + control_offsets.w_device_control, @bitCast(value));
    }

    // reading this register clears pending interrupts
    pub fn get_status(self: *const Bus) Status {
        return @bitCast(x86.inb(self.command + command_offsets.r_status));
    }

    pub fn get_alt_status(self: *const Bus) Status {
        return @bitCast(x86.inb(self.control + control_offsets.r_alternate_status));
    }

    pub fn get_data_word(self: *const Bus) u16 {
        return x86.inw(self.command + command_offsets.rw_data);
    }

    pub fn report_status(self: *const Bus) void {
        const status = self.get_alt_status();
        log.debug("status:{s}{s}{s}{s}{s}{s}{s}{s}", .{
            if (status.err) " ERR" else "",
            if (status.index) " IDX" else "",
            if (status.corrected_data) " CORR" else "",
            if (status.data_request) " DRQ" else "",
            if (status.drive_seek_complete) " DSC" else "",
            if (status.drive_write_fault) " DWF" else "",
            if (status.drive_ready) " RDY" else "",
            if (status.busy) " BSY" else "",
        });
    }

    pub fn wait_for_ready(self: *const Bus) void {
        log.debug("wait for ready", .{});
        while (self.get_alt_status().busy) {}
    }

    pub fn io_wait(self: *const Bus) void {
        inline for (0..8) |_| _ = self.get_alt_status();
    }

    pub fn soft_reset(self: *const Bus) void {
        self.write_device_control(.{ .software_reset = true });
        x86.io_wait();

        self.write_device_control(.{ .software_reset = false });
        x86.io_wait();
        x86.io_wait();
        x86.io_wait();
        x86.io_wait();
        x86.io_wait();
        x86.io_wait();
    }

    pub fn detect_device_type(self: *const Bus, drive_number: DriveNumber) DeviceType {
        self.select_device(.{ .drive_number = drive_number });

        const cl: u8 = x86.inb(self.command + 4);
        const ch: u8 = x86.inb(self.command + 5);

        if (cl == 0x14 and ch == 0xeb) return .patapi;
        if (cl == 0x69 and ch == 0x96) return .satapi;
        if (cl == 0 and ch == 0) return .pata;
        if (cl == 0x3c and ch == 0xc3) return .sata;
        return .unknown;
    }

    pub fn identify(self: *const Bus, drive_number: DriveNumber, data: *DeviceIdentification) bool {
        self.select_device(.{ .drive_number = drive_number });
        self.send_command(.identify);

        if (x86.inb(self.command + command_offsets.r_status) == 0) {
            log.debug("status=0 after identify", .{});
            return false;
        }

        self.wait_for_ready();

        if (self.get_alt_status().err) {
            const err = x86.inb(self.command + command_offsets.r_err);
            log.debug("ERR={d} after identify", .{err});
            return false;
        }

        if (!self.get_alt_status().data_request) {
            log.debug("no DRQ after identify, o well", .{});
            return false;
        }

        // read ID data
        const raw: [*]u16 = @ptrCast(data);
        for (0..256) |i| raw[i] = self.get_data_word();

        return true;
    }

    pub fn identify_packet_device(self: *const Bus, drive_number: DriveNumber, buffer: *[256]u16) bool {
        self.select_device(.{ .drive_number = drive_number });
        self.send_command(.identify_packet_device);

        self.wait_for_ready();

        if (self.get_alt_status().err) {
            const err = x86.inb(self.command + command_offsets.r_err);
            log.debug("ERR={d} after identify packet device", .{err});
            return false;
        }

        for (buffer) |*word| word.* = self.get_data_word();
        return true;
    }

    fn send_command(self: *const Bus, cmd: Command) void {
        log.debug("ata@{x}: {s}", .{ self.command, @tagName(cmd) });
        x86.outb(self.command + command_offsets.w_command, @intFromEnum(cmd));
    }

    fn select_device(self: *const Bus, dh: DriveHead) void {
        x86.outb(self.command + command_offsets.rw_drive_head, @bitCast(dh));
        self.io_wait();
    }

    pub fn set_lba28(self: *const Bus, lba: u28, drive_number: DriveNumber, sector_count: u8) void {
        const addr_00_07: u8 = @intCast((lba >> 0) & 0xff);
        const addr_08_15: u8 = @intCast((lba >> 8) & 0xff);
        const addr_16_23: u8 = @intCast((lba >> 16) & 0xff);
        const addr_24_27: u4 = @intCast((lba >> 24) & 0xf);

        self.select_device(.{ .drive_number = drive_number, .lba_hi2 = addr_24_27, .address_mode = .lba });
        x86.outb(self.command + command_offsets.rw_sector_count, sector_count);
        x86.outb(self.command + command_offsets.rw_lba_lo, addr_00_07);
        x86.outb(self.command + command_offsets.rw_lba_mid, addr_08_15);
        x86.outb(self.command + command_offsets.rw_lba_hi, addr_16_23);
    }

    pub fn read_final_lba(self: *const Bus) u28 {
        const dh: DriveHead = @bitCast(x86.inb(self.command + command_offsets.rw_drive_head));
        const addr_24_27 = dh.lba_hi2;
        const addr_16_23 = x86.inb(self.command + command_offsets.rw_lba_hi);
        const addr_08_15 = x86.inb(self.command + command_offsets.rw_lba_mid);
        const addr_00_07 = x86.inb(self.command + command_offsets.rw_lba_lo);

        return (@as(u28, addr_24_27) << 24) |
            (@as(u28, addr_16_23) << 16) |
            (@as(u28, addr_08_15) << 8) |
            (@as(u28, addr_00_07) << 0);
    }

    pub fn dma_read(self: *const Bus) void {
        x86.outb(self.command + command_offsets.w_features, 1);
        self.send_command(.read_dma);
    }

    pub fn pio_read(self: *const Bus) void {
        self.send_command(.read_sectors);
    }

    pub fn pio_atapi_read(self: *const Bus, lba: u32, drive_number: DriveNumber, sector_count: u32, buffer: [*]u16) bool {
        const command_bytes: []const u8 = &.{
            0xa8,
            0,
            @truncate(lba >> 24),
            @truncate(lba >> 16),
            @truncate(lba >> 8),
            @truncate(lba),
            @truncate(sector_count >> 24),
            @truncate(sector_count >> 16),
            @truncate(sector_count >> 8),
            @truncate(sector_count),
            0,
            0,
        };
        const raw_words: [*]const u16 = @alignCast(@ptrCast(command_bytes.ptr));
        const command_words: []const u16 = raw_words[0..6];

        log.debug("sending ata args", .{});
        const ata_lba: u16 = 2048;
        self.select_device(.{ .drive_number = drive_number });
        x86.outb(self.command + command_offsets.w_features, 0);
        x86.outb(self.command + command_offsets.rw_lba_mid, ata_lba & 0xff);
        x86.outb(self.command + command_offsets.rw_lba_hi, (ata_lba >> 8) & 0xff);

        self.send_command(.packet);
        self.io_wait();

        log.debug("waiting for RDY", .{});
        while (true) {
            self.report_status();
            const status = self.get_alt_status();
            if (status.err) return false;
            if (!status.busy and status.data_request) break;

            self.io_wait();
        }

        log.debug("sending atapi packet", .{});
        for (command_words) |w| x86.outw(self.command + command_offsets.rw_data, w);

        for (0..sector_count) |s| {
            log.debug("waiting for sector {d}", .{s});
            while (true) {
                self.report_status();
                const status = self.get_alt_status();
                if (status.err) return false;
                if (!status.busy and status.data_request) break;
            }

            log.debug("reading sector {d}", .{s});

            const size_hi = x86.inb(self.command + command_offsets.rw_lba_hi);
            const size_lo = x86.inb(self.command + command_offsets.rw_lba_mid);

            const size: u16 = (@as(u16, size_hi) << 8) | size_lo;

            var index = s * 0x400;
            for (0..size / 2) |_| {
                buffer[index] = x86.inw(self.command + command_offsets.rw_data);
                index += 1;
            }
        }

        log.debug("done", .{});
        return true;
    }
};

const PRIMARY_COMMAND_BLOCK_OFFSET = 0x1f0;
const PRIMARY_CONTROL_BLOCK_OFFSET = 0x3f6; // spec says 3f4 but first two bytes are reserved anyway
pub const primary = Bus.init(false, PRIMARY_COMMAND_BLOCK_OFFSET, PRIMARY_CONTROL_BLOCK_OFFSET);

const SECONDARY_COMMAND_BLOCK_OFFSET = 0x170;
const SECONDARY_CONTROL_BLOCK_OFFSET = 0x376;
pub const secondary = Bus.init(true, SECONDARY_COMMAND_BLOCK_OFFSET, SECONDARY_CONTROL_BLOCK_OFFSET);

fn shell_ata(_: std.mem.Allocator, _: []const u8) !void {
    ata_shell_report_status(&primary);
    ata_shell_report_status(&secondary);
}

fn ata_shell_report_status(bus: *const Bus) void {
    const status = bus.get_alt_status();
    console.printf("{s:>9} ata bus @{x}/{x}:{s}{s}{s}{s}{s}{s}{s}{s}\n", .{
        bus.name,
        bus.command,
        bus.control,
        if (status.err) " ERR" else "",
        if (status.index) " IDX" else "",
        if (status.corrected_data) " CORR" else "",
        if (status.data_request) " DRQ" else "",
        if (status.drive_seek_complete) " SRV" else "",
        if (status.drive_write_fault) " DF" else "",
        if (status.drive_ready) " RDY" else "",
        if (status.busy) " BSY" else "",
    });
}

pub fn initialize() !void {
    log.debug("initializing", .{});
    defer log.debug("done", .{});

    try shell.add_command(.{
        .name = "ata",
        .summary = "Get ATA device status.",
        .exec = shell_ata,
    });
}
