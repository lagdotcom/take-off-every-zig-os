const std = @import("std");

pub fn build(b: *std.Build) void {
    var disabled_features = std.Target.Cpu.Feature.Set.empty;
    var enabled_features = std.Target.Cpu.Feature.Set.empty;

    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.mmx));
    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.sse));
    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.sse2));
    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.avx));
    disabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.avx2));
    enabled_features.addFeature(@intFromEnum(std.Target.x86.Feature.soft_float));

    const target = b.resolveTargetQuery(.{
        .cpu_arch = .x86,
        .os_tag = .freestanding,
        .abi = .none,
        .cpu_features_sub = disabled_features,
        .cpu_features_add = enabled_features,
    });

    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const os = b.addExecutable(.{
        .name = "os.elf",
        .root_source_file = b.path("src/main.zig"),
        .optimize = optimize,
        .target = target,
        .code_model = .kernel,
    });
    os.setLinkerScriptPath(b.path("linker.ld"));
    b.installArtifact(os);

    const run_cmd = b.addSystemCommand(&.{
        "qemu-system-i386",
        "-serial",
        "stdio",
        "-kernel",
        "zig-out/bin/os.elf",
        "-display",
        "gtk",
        // "-D",
        // "./qemu-debug.log",
        // "-monitor",
        // "stdio",
    });
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the os");
    run_step.dependOn(&run_cmd.step);
}
