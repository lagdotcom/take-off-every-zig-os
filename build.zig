const builtin = @import("builtin");
const std = @import("std");

fn path(b: *std.Build, sub_path: []const u8) std.Build.LazyPath {
    if (@hasDecl(std.Build, "path")) return b.path(sub_path);

    return .{ .path = sub_path };
}

const bootloader_src = "src/bootloader/bootloader.asm";
const bootloader_image = "zig-out/bin/bootloader.bin";
const disk_image = "zig-out/bin/disk.bin";
const main_src = "src/main.zig";

fn build_disk_image(step: *std.Build.Step, node: std.Progress.Node) anyerror!void {
    node.setEstimatedTotalItems(4);

    try step.evalChildProcess(&.{ "fat_imgen", "-c", "-F", "-f", disk_image });
    node.setCompletedItems(1);

    try step.evalChildProcess(&.{ "fasm", bootloader_src, bootloader_image });
    node.setCompletedItems(2);

    try step.evalChildProcess(&.{ "fat_imgen", "-m", "-f", disk_image, "-s", bootloader_image });
    node.setCompletedItems(3);

    try step.evalChildProcess(&.{ "fat_imgen", "-m", "-f", disk_image, "-i", "zig-out/bin/os.elf" });
    node.setCompletedItems(4);
}

pub fn build(b: *std.Build) void {
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    var disabled_features = std.Target.Cpu.Feature.Set.empty;
    var enabled_features = std.Target.Cpu.Feature.Set.empty;

    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.mmx));
    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.sse));
    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.sse2));
    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.avx));
    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.avx2));
    enabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.soft_float));

    const exe_target_query = .{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .none,
        .ofmt = .elf,
        .cpu_features_add = enabled_features,
        .cpu_features_sub = disabled_features,
    };
    const exe_target = if (@hasDecl(std.Build, "resolveTargetQuery")) b.resolveTargetQuery(exe_target_query) else exe_target_query;

    const exe_details = .{
        .name = "os.elf",
        .root_source_file = path(b, main_src),
        .optimize = optimize,
        .target = exe_target,
        .single_threaded = true,
    };
    if (@hasDecl(std.Build.ExecutableOptions, "code_model")) exe_details.code_model = .kernel;

    const os = b.addExecutable(exe_details);
    os.setLinkerScriptPath(path(b, "linker.ld"));
    b.installArtifact(os);

    var disk_image_step = b.step("build disk image", "make FAT12 floppy disk image");
    disk_image_step.makeFn = build_disk_image;
    disk_image_step.dependOn(b.getInstallStep());

    const qemu_cmd = b.addSystemCommand(&.{
        "qemu-system-i386",
        "-drive",
        "if=floppy,format=raw,media=disk,file=" ++ disk_image,
        "-display",
        "gtk",
        "-D",
        "./qemu-debug.log",
        "-no-reboot",
    });
    qemu_cmd.step.dependOn(disk_image_step);

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

    const serial_option = b.option([]const u8, "serial", "qemu serial log filename");
    if (serial_option) |log| {
        const serial_log_file = std.fmt.allocPrint(b.allocator, "file:{s}", .{log}) catch unreachable;
        defer b.allocator.free(serial_log_file);
        qemu_cmd.addArg("-serial");
        qemu_cmd.addArg(serial_log_file);
    }

    const qemu_step = b.step("qemu", "Run on qemu");
    qemu_step.dependOn(&qemu_cmd.step);

    const bochs_cmd = b.addSystemCommand(&.{
        "bochs",
        "-q",
        "-f",
        "bochsrc.txt",
    });
    bochs_cmd.step.dependOn(disk_image_step);

    const bochs_step = b.step("bochs", "Run on bochs");
    bochs_step.dependOn(&bochs_cmd.step);
}
