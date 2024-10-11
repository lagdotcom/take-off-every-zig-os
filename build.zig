const std = @import("std");

pub fn build(b: *std.Build) void {
    // Standard optimization options allow the person running `zig build` to select
    // between Debug, ReleaseSafe, ReleaseFast, and ReleaseSmall. Here we do not
    // set a preferred release mode, allowing the user to decide how to optimize.
    const optimize = b.standardOptimizeOption(.{});

    const target = b.resolveTargetQuery(.{ .cpu_arch = .x86, .os_tag = .freestanding });

    const os = b.addExecutable(.{
        .name = "os.elf",
        .root_source_file = b.path("src/main.zig"),
        .optimize = optimize,
        .target = target,
    });
    os.setLinkerScriptPath(b.path("linker.ld"));
    b.installArtifact(os);

    const run_cmd = b.addSystemCommand(&.{
        "qemu-system-i386",
        "-kernel",
        "zig-out/bin/os.elf",
        "-display",
        "gtk,zoom-to-fit=on",
    });
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the os");
    run_step.dependOn(&run_cmd.step);
}
