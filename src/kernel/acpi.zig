const std = @import("std");
const log = std.log.scoped(.acpi);

const acpi = @import("../common/acpi.zig");
const console = @import("console.zig");
const shell = @import("shell.zig");

pub var tables = acpi.ACPITables{};

fn add_entry(t: *shell.Table, e: *acpi.DescriptionHeader) !void {
    try t.add_string(&e.signature);
    try t.add_number(e.revision, 10);
    try t.add_string(&e.oem_id);
    try t.add_string(&e.oem_table_id);
    try t.add_number(e.oem_revision, 10);

    try t.end_row();
}

fn shell_acpi(sh: *shell.Context, _: []const u8) !void {
    var t = try sh.table();
    defer t.deinit();

    try t.add_heading(.{ .name = "Type" });
    try t.add_heading(.{ .name = "Revision" });
    try t.add_heading(.{ .name = "OEM ID" });
    try t.add_heading(.{ .name = "OEM Table ID" });
    try t.add_heading(.{ .name = "OEM Revision" });

    if (tables.madt) |e| try add_entry(&t, &e.header);
    if (tables.bert) |e| try add_entry(&t, &e.header);
    if (tables.bgrt) |e| try add_entry(&t, &e.header);
    if (tables.fadt) |e| try add_entry(&t, &e.header);
    if (tables.hpet) |e| try add_entry(&t, &e.header);
    if (tables.waet) |e| try add_entry(&t, &e.header);

    t.print();
}

inline fn printf_address(name: []const u8, address: *acpi.GenericAddressStructure) void {
    console.printf_nl("{s}: {s} {x} - o{d} w{d} {s}", .{
        name,
        @tagName(address.address_space_id),
        address.address,
        address.register_bit_offset,
        address.register_bit_width,
        @tagName(address.access_size),
    });
}

fn shell_acpi_madt(_: *shell.Context, _: []const u8) !void {
    if (tables.madt) |e| {
        console.printf_nl("local_interrupt_controller_address: {x}", .{e.local_interrupt_controller_address});
        console.printf_nl("flags:{s}", .{
            if (e.flags.pc_at_compatible) " PC-AT-compatible" else "",
        });

        const end = @intFromPtr(e) + e.header.length;
        var icc = @intFromPtr(e) + @sizeOf(acpi.MultipleAPICDescriptionTable);
        while (icc < end) {
            const p: *u8 = @ptrFromInt(icc);
            switch (p.*) {
                0 => {
                    const data: *align(1) acpi.ProcessorLocalAPIC = @ptrFromInt(icc);
                    icc += data.length;

                    console.printf_nl("Processor Local APIC> uid={d} id={d} flags={s}{s}", .{
                        data.acpi_processor_uid,
                        data.apic_id,
                        if (data.flags.enabled) "enabled " else "",
                        if (data.flags.online_capable) "online_capable " else "",
                    });
                },
                1 => {
                    const data: *align(1) acpi.IOAPIC = @ptrFromInt(icc);
                    icc += data.length;

                    console.printf_nl("I/O APIC> id={d} addr={x} gsi_base={x}", .{
                        data.io_apic_id,
                        data.io_apic_address,
                        data.global_system_interrupt_base,
                    });
                },
                2 => {
                    const data: *align(1) acpi.InterruptSourceOverride = @ptrFromInt(icc);
                    icc += data.length;

                    console.printf_nl("Interrupt Source Override> bus={d} irq={d} gsi={d} polarity={s} trigger_mode={s}", .{
                        data.bus,
                        data.source,
                        data.global_system_interrupt,
                        @tagName(data.flags.polarity),
                        @tagName(data.flags.trigger_mode),
                    });
                },
                4 => {
                    const data: *align(1) acpi.LocalAPICNMI = @ptrFromInt(icc);
                    icc += data.length;

                    console.printf_nl("Local APIC NMI> uid={d} polarity={s} trigger_mode={s} LINT#={d}", .{
                        data.acpi_processor_uid,
                        @tagName(data.flags.polarity),
                        @tagName(data.flags.trigger_mode),
                        data.local_apic_lintn,
                    });
                },
                else => {
                    console.printf_nl("!! unknown type {d}, breaking", .{p.*});
                    return;
                },
            }
        }
    } else return error.RecordNotFound;
}

fn shell_acpi_fadt(_: *shell.Context, _: []const u8) !void {
    if (tables.fadt) |e| {
        console.printf_nl("firmware_ctrl: {x}", .{e.firmware_ctrl});
        console.printf_nl("dsdt: {x}", .{e.dsdt});
        console.printf_nl("int_model: {d}", .{e.int_model});
        console.printf_nl("preferred_pm_profile: {s}", .{@tagName(e.preferred_pm_profile)});
        console.printf_nl("sci_interrupt: {d}", .{e.sci_interrupt});
        console.printf_nl("smi_cmd: {x}", .{e.smi_cmd});
        console.printf_nl("acpi_enable: {d}", .{e.acpi_enable});
        console.printf_nl("acpi_disable: {d}", .{e.acpi_disable});
        console.printf_nl("s4bios_req: {d}", .{e.s4bios_req});
        console.printf_nl("pstate_cnt: {d}", .{e.pstate_cnt});
        console.printf_nl("pm1a_evt_blk: {x} len {d}", .{ e.pm1a_evt_blk, e.pm1_evt_len });
        console.printf_nl("pm1b_evt_blk: {x} len {d}", .{ e.pm1b_evt_blk, e.pm1_evt_len });
        console.printf_nl("pm1a_cnt_blk: {x} len {d}", .{ e.pm1a_cnt_blk, e.pm1_cnt_len });
        console.printf_nl("pm1b_cnt_blk: {x} len {d}", .{ e.pm1b_cnt_blk, e.pm1_cnt_len });
        console.printf_nl("pm2_cnt_blk: {x} len {d}", .{ e.pm2_cnt_blk, e.pm2_cnt_len });
        console.printf_nl("pm_tmr_blk: {x} len {d}", .{ e.pm_tmr_blk, e.pm_tmr_len });
        console.printf_nl("gpe0_blk: {x} len {d}", .{ e.gpe0_blk, e.gpe0_blk_len });
        console.printf_nl("gpe1_blk: {x} len {d}", .{ e.gpe1_blk, e.gpe1_blk_len });
        console.printf_nl("gpe1_base: {d}", .{e.gpe1_base});
        console.printf_nl("cst_cnt: {d}", .{e.cst_cnt});
        console.printf_nl("p_lvl2_lat: {d}", .{e.p_lvl2_lat});
        console.printf_nl("p_lvl3_lat: {d}", .{e.p_lvl3_lat});
        console.printf_nl("flush_size: {d}", .{e.flush_size});
        console.printf_nl("flush_stride: {d}", .{e.flush_stride});
        console.printf_nl("duty_offset: {d}", .{e.duty_offset});
        console.printf_nl("duty_width: {d}", .{e.duty_width});
        console.printf_nl("day_alrm: {d}", .{e.day_alrm});
        console.printf_nl("mon_alrm: {d}", .{e.mon_alrm});
        console.printf_nl("century: {d}", .{e.century});
        console.printf_nl("ia_pc_boot_arch:{s}{s}{s}{s}{s}{s}", .{
            if (e.ia_pc_boot_arch.legacy_devices) " legacy_devices" else "",
            if (e.ia_pc_boot_arch.has_8042) " has_8042" else "",
            if (e.ia_pc_boot_arch.vga_not_present) " vga_not_present" else "",
            if (e.ia_pc_boot_arch.msi_not_supported) " msi_not_supported" else "",
            if (e.ia_pc_boot_arch.pcie_aspm_controls) " pcie_aspm_controls" else "",
            if (e.ia_pc_boot_arch.cmos_rtc_not_present) " cmos_rtc_not_present" else "",
        });
        console.printf_nl("flags:{s}{s}{s}{s}{s}{s}{s}{s}{s}{s}{s}{s}{s}{s}{s}{s}{s}{s}{s}{s}{s}{s} {s}", .{
            if (e.flags.wbinvd) " wbinvd" else "",
            if (e.flags.wbinvd_flush) " wbinvd_flush" else "",
            if (e.flags.proc_c1) " proc_c1" else "",
            if (e.flags.p_lvl2_up) " p_lvl2_up" else "",
            if (e.flags.pwr_button) " pwr_button" else "",
            if (e.flags.slp_button) " slp_button" else "",
            if (e.flags.fix_rtc) " fix_rtc" else "",
            if (e.flags.rtc_s4) " rtc_s4" else "",
            if (e.flags.tmr_val_ext) " tmr_val_ext" else "",
            if (e.flags.dck_cap) " dck_cap" else "",
            if (e.flags.reset_reg_sup) " reset_reg_sup" else "",
            if (e.flags.sealed_case) " sealed_case" else "",
            if (e.flags.headless) " headless" else "",
            if (e.flags.cpu_sw_slp) " cpu_sw_slp" else "",
            if (e.flags.pci_exp_wak) " pci_exp_wak" else "",
            if (e.flags.use_platform_clock) " use_platform_clock" else "",
            if (e.flags.s4_rtc_sts_valid) " s4_rtc_sts_valid" else "",
            if (e.flags.remote_power_on_capable) " remote_power_on_capable" else "",
            if (e.flags.force_apic_cluster_model) " force_apic_cluster_model" else "",
            if (e.flags.force_apic_physical_destination_mode) " force_apic_physical_destination_mode" else "",
            if (e.flags.hw_reduced_acpi) " hw_reduced_acpi" else "",
            if (e.flags.low_power_s0_idle_capable) " low_power_s0_idle_capable" else "",
            @tagName(e.flags.persistent_cpu_caches),
        });

        if (e.header.length <= @offsetOf(acpi.FixedACPIDescriptionTable, "reset_reg")) return;
        printf_address("reset_reg", &e.reset_reg);

        if (e.header.length <= @offsetOf(acpi.FixedACPIDescriptionTable, "reset_value")) return;
        console.printf_nl("reset_value: {d}", .{e.reset_value});

        if (e.header.length <= @offsetOf(acpi.FixedACPIDescriptionTable, "arm_boot_arch")) return;
        console.printf_nl("arm_boot_arch:{s}{s}", .{
            if (e.arm_boot_arch.pcsi_compliant) " pcsi_compliant" else "",
            if (e.arm_boot_arch.psci_use_hvc) " psci_use_hvc" else "",
        });

        if (e.header.length <= @offsetOf(acpi.FixedACPIDescriptionTable, "fadt_minor_version")) return;
        console.printf_nl("fadt_minor_version: {d} e{d}", .{ e.fadt_minor_version.minor, e.fadt_minor_version.errata });

        if (e.header.length <= @offsetOf(acpi.FixedACPIDescriptionTable, "x_firmware_ctrl")) return;
        console.printf_nl("x_firmware_ctrl: {x}", .{e.x_firmware_ctrl});

        if (e.header.length <= @offsetOf(acpi.FixedACPIDescriptionTable, "x_dsdt")) return;
        console.printf_nl("x_dsdt: {x}", .{e.x_dsdt});

        if (e.header.length <= @offsetOf(acpi.FixedACPIDescriptionTable, "x_pm1a_evt_blk")) return;
        printf_address("x_pm1a_evt_blk", &e.x_pm1a_evt_blk);
        printf_address("x_pm1b_evt_blk", &e.x_pm1b_evt_blk);
        printf_address("x_pm1a_cnt_blk", &e.x_pm1a_cnt_blk);
        printf_address("x_pm1b_cnt_blk", &e.x_pm1b_cnt_blk);
        printf_address("x_pm2_cnt_blk", &e.x_pm2_cnt_blk);
        printf_address("x_pm_tmr_blk", &e.x_pm_tmr_blk);
        printf_address("x_gpe0_blk", &e.x_gpe0_blk);
        printf_address("x_gpe1_blk", &e.x_gpe1_blk);
        printf_address("sleep_control_reg", &e.sleep_control_reg);
        printf_address("sleep_status_reg", &e.sleep_status_reg);
        console.printf_nl("hypervisor_vendor_identity: {s}", .{e.hypervisor_vendor_identity});
    } else return error.RecordNotFound;
}

fn shell_acpi_hpet(_: *shell.Context, _: []const u8) !void {
    if (tables.hpet) |e| {
        console.printf_nl("hardware_rev_id: {d}", .{e.hardware_rev_id});
        console.printf_nl("comparator_count: {d}", .{e.comparator_count});
        console.printf_nl("counter_size: {d}", .{e.counter_size});
        console.printf_nl("legacy_replacement: {d}", .{e.legacy_replacement});
        console.printf_nl("pci_vendor_id: {x}", .{e.pci_vendor_id});
        printf_address("address", &e.address);
        console.printf_nl("hpet_number: {d}", .{e.hpet_number});
        console.printf_nl("minimum_tick: {d}", .{e.minimum_tick});
        console.printf_nl("page_protection: {d}", .{e.page_protection});
    } else return error.RecordNotFound;
}

fn shell_acpi_waet(_: *shell.Context, _: []const u8) !void {
    if (tables.waet) |e| {
        console.printf_nl("flags:{s}{s}", .{
            if (e.flags.rtc_good) " RTC good" else "",
            if (e.flags.acpi_pm_timer_good) " ACPI PM timer good" else "",
        });
    } else return error.RecordNotFound;
}

pub fn initialize(pointers: []const usize) !void {
    log.debug("initializing", .{});
    defer log.debug("done", .{});

    tables = acpi.read_acpi_tables(pointers);

    try shell.add_command(.{
        .name = "acpi",
        .summary = "Get information on ACPI tables",
        .exec = shell_acpi,
        .sub_commands = &.{ .{
            .name = "madt",
            .summary = "Multiple APIC Description info",
            .exec = shell_acpi_madt,
        }, .{
            .name = "fadt",
            .summary = "Fixed ACPI Description info",
            .exec = shell_acpi_fadt,
        }, .{
            .name = "hpet",
            .summary = "High Precision Event Timer info",
            .exec = shell_acpi_hpet,
        }, .{
            .name = "waet",
            .summary = "Windows ACPI Emulated Devices info",
            .exec = shell_acpi_waet,
        } },
    });
}
