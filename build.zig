const builtin = @import("builtin");
const std = @import("std");

fn path(b: *std.Build, sub_path: []const u8) std.Build.LazyPath {
    if (@hasDecl(std.Build, "path")) return b.path(sub_path);

    return .{ .path = sub_path };
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
        .root_source_file = path(b, "src/main.zig"),
        .optimize = optimize,
        .target = exe_target,
        .single_threaded = true,
    };
    if (@hasDecl(std.Build.ExecutableOptions, "code_model")) exe_details.code_model = .kernel;

    const os = b.addExecutable(exe_details);
    os.setLinkerScriptPath(path(b, "linker.ld"));
    b.installArtifact(os);

    const qemu_cmd = b.addSystemCommand(&.{
        "qemu-system-i386",
        // "-cpu",
        // "486",
        "-serial",
        "stdio",
        // "file:qemu-serial.log",
        "-kernel",
        "zig-out/bin/os.elf",
        "-display",
        "gtk",
        "-D",
        "./qemu-debug.log",
        // "-monitor",
        // "stdio",
    });
    qemu_cmd.step.dependOn(b.getInstallStep());

    const qemu_step = b.step("qemu", "Run on qemu");
    qemu_step.dependOn(&qemu_cmd.step);

    const bochs_cmd = b.addSystemCommand(&.{
        "bochs",
        "-q",
        "-f",
        "bochsrc.txt",
    });
    bochs_cmd.step.dependOn(b.getInstallStep());

    const bochs_step = b.step("bochs", "Run on bochs");
    bochs_step.dependOn(&bochs_cmd.step);
}
