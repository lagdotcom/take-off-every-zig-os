const builtin = @import("builtin");
const std = @import("std");

fn path(b: *std.Build, sub_path: []const u8) std.Build.LazyPath {
    if (@hasDecl(std.Build, "path")) return b.path(sub_path);

    return .{ .path = sub_path };
}

var allocator: std.mem.Allocator = undefined;

const src_dir = "src/";
const bootloader_dir = src_dir ++ "bootloader/";
const fonts_dir = src_dir ++ "fonts/";
const zig_out_bin_dir = "zig-out/bin/";

const fat_imgen = "fat_imgen";
const bootloader_src = bootloader_dir ++ "bootloader.asm";
const bootloader_image = zig_out_bin_dir ++ "bootloader.bin";
const bootloader2_src = bootloader_dir ++ "stage2.asm";
const bootloader2_image = zig_out_bin_dir ++ "stage2.bin";
const disk_image = zig_out_bin_dir ++ "disk.bin";
const main_zig = src_dir ++ "main.zig";
const os_elf = zig_out_bin_dir ++ "os.elf";

fn build_disk_image(step: *std.Build.Step, node: std.Progress.Node) !void {
    node.setEstimatedTotalItems(6);

    try step.evalChildProcess(&.{ fat_imgen, "-c", "-F", "-f", disk_image });
    node.setCompletedItems(1);

    try step.evalChildProcess(&.{ "fasm", bootloader_src, bootloader_image });
    node.setCompletedItems(2);

    try step.evalChildProcess(&.{ "fasm", bootloader2_src, bootloader2_image });
    node.setCompletedItems(3);

    try step.evalChildProcess(&.{ fat_imgen, "-m", "-f", disk_image, "-s", bootloader_image });
    node.setCompletedItems(4);

    try step.evalChildProcess(&.{ fat_imgen, "-m", "-f", disk_image, "-i", bootloader2_image });
    node.setCompletedItems(5);

    try step.evalChildProcess(&.{ fat_imgen, "-m", "-f", disk_image, "-i", os_elf });
    node.setCompletedItems(6);
}

fn convert_font_txt(step: *std.Build.Step, node: std.Progress.Node) !void {
    var argv = std.ArrayList([]const u8).init(allocator);
    try argv.append("zig"); // TODO does this work with zigup build?
    try argv.append("run");
    try argv.append("tools/convert_font_txt.zig");
    try argv.append("--");

    const dir = try std.fs.cwd().openDir(fonts_dir, .{ .iterate = true });
    var iter = dir.iterate();

    while (try iter.next()) |e| {
        if (std.mem.eql(u8, std.fs.path.extension(e.name), ".txt")) try argv.append(try std.fs.path.join(allocator, &.{ fonts_dir, e.name }));
    }

    _ = try step.evalZigProcess(try argv.toOwnedSlice(), node);
}

const BootType = enum {
    floppy,
    uefi,
    direct,
};

pub fn build(b: *std.Build) void {
    allocator = b.allocator;

    var convert_font_txt_step = b.step("convert font files", "convert fonts/*.txt into .fon files");
    convert_font_txt_step.makeFn = convert_font_txt;

    var compile_assets = b.step("compile assets", "compile all assets");
    compile_assets.dependOn(convert_font_txt_step);

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const is_64 = b.option(bool, "64", "compile for x86_64") orelse false;

    const efi_name = if (is_64) "BOOTX64" else "BOOTIA32";
    const efi_arch: std.Target.Cpu.Arch = if (is_64) .x86_64 else .x86;
    const qemu_system_cmd = if (is_64) "qemu-system-x86_64" else "qemu-system-i386";
    const bios_arg = if (is_64) "bios64.bin" else "bios32.bin";

    var disabled_features = std.Target.Cpu.Feature.Set.empty;
    var enabled_features = std.Target.Cpu.Feature.Set.empty;

    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.mmx));
    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.sse));
    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.sse2));
    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.avx));
    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.avx2));
    enabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.soft_float));

    const kernel_target_query = .{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .none,
        .ofmt = .elf,
        .cpu_features_add = enabled_features,
        .cpu_features_sub = disabled_features,
    };
    const kernel_target = if (@hasDecl(std.Build, "resolveTargetQuery")) b.resolveTargetQuery(kernel_target_query) else kernel_target_query;

    const kernel_details = .{
        .name = "os.elf",
        .root_source_file = path(b, main_zig),
        .optimize = optimize,
        .target = kernel_target,
        .single_threaded = true,
    };
    if (@hasDecl(std.Build.ExecutableOptions, "code_model")) kernel_details.code_model = .kernel;

    const kernel_exe = b.addExecutable(kernel_details);
    kernel_exe.setLinkerScriptPath(path(b, "linker.ld"));
    kernel_exe.step.dependOn(compile_assets);

    const efi = b.addExecutable(.{
        .name = efi_name,
        .root_source_file = b.path("src/efi_main.zig"),
        .optimize = optimize,
        .target = b.resolveTargetQuery(.{
            .cpu_arch = efi_arch,
            .os_tag = .uefi,
            .abi = .msvc,
        }),
    });
    efi.step.dependOn(compile_assets);

    const efi_artifact = b.addInstallArtifact(efi, .{
        .dest_dir = .{
            .override = .{ .custom = "efi/boot" },
        },
    });

    const boot_type = b.option(BootType, "boot", "choose boot type") orelse .direct;

    const install_step = b.getInstallStep();

    var disk_image_step = b.step("build disk image", "make FAT12 floppy disk image");
    disk_image_step.makeFn = build_disk_image;

    const qemu_cmd = b.addSystemCommand(&.{
        qemu_system_cmd,
        "-display",
        "gtk,zoom-to-fit=on",
        "-D",
        "./qemu-debug.log",
        "-no-reboot",
    });
    qemu_cmd.step.dependOn(install_step);

    switch (boot_type) {
        .uefi => {
            install_step.dependOn(&efi_artifact.step);
            qemu_cmd.addArg("-bios");
            qemu_cmd.addArg(bios_arg);
            qemu_cmd.addArg("-hdd");
            qemu_cmd.addArg("fat:rw:zig-out");
        },
        .floppy => {
            install_step.dependOn(disk_image_step);
            qemu_cmd.addArg("-drive");
            qemu_cmd.addArg("if=floppy,format=raw,media=disk,file=" ++ disk_image);
        },
        .direct => {
            b.installArtifact(kernel_exe);
            qemu_cmd.addArg("-kernel");
            qemu_cmd.addArg(os_elf);
        },
    }

    const cpu_option = b.option([]const u8, "cpu", "qemu cpu option");
    if (cpu_option) |cpu| {
        qemu_cmd.addArg("-cpu");
        qemu_cmd.addArg(cpu);
    }

    const machine_option = b.option([]const u8, "machine", "qemu machine option");
    if (machine_option) |mach| {
        qemu_cmd.addArg("-machine");
        qemu_cmd.addArg(mach);
    }

    const serial_option = b.option([]const u8, "serial", "qemu serial option");
    if (serial_option) |log| {
        qemu_cmd.addArg("-serial");
        qemu_cmd.addArg(log);
    }

    const qemu_step = b.step("qemu", "Run on qemu");
    qemu_step.dependOn(&qemu_cmd.step);

    // const bochs_cmd = b.addSystemCommand(&.{
    //     "bochs",
    //     "-q",
    //     "-f",
    //     "bochsrc.txt",
    // });
    // bochs_cmd.step.dependOn(disk_image_step);

    // const bochs_step = b.step("bochs", "Run on bochs");
    // bochs_step.dependOn(&bochs_cmd.step);
}
