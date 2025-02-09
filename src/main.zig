const builtin = @import("builtin");
const std = @import("std");
const log = std.log.scoped(.kmain);

const console = @import("console.zig");
const cpuid = @import("cpuid.zig");
const gdt = @import("gdt.zig");
const keyboard = @import("keyboard.zig");
const kernel_log = @import("log.zig");
const pci = @import("pci.zig");
const serial = @import("serial.zig");
const utils = @import("utils.zig");

pub const os = @import("os.zig");

pub fn kernel_log_fn(
    comptime level: std.log.Level,
    comptime scope: @TypeOf(.EnumLiteral),
    comptime format: []const u8,
    args: anytype,
) void {
    kernel_log.write(level, "(" ++ @tagName(scope) ++ "): " ++ format, args);
}

// TODO figure out how to swap this automatically depending on builtin.zig_version.major
// version 12+
pub const std_options = .{
    .log_level = .debug,
    .logFn = kernel_log_fn,
};
// before that
// pub const std_options = struct {
//     pub const log_level = .debug;
//     pub const logFn = kernel_log_fn;
// };

// Define root.panic to override the std implementation
pub fn panic(msg: []const u8, error_return_trace: ?*std.builtin.StackTrace, ret_addr: ?usize) noreturn {
    @setCold(true);

    _ = error_return_trace;
    _ = ret_addr;
    kernel_log_fn(.err, .kernel, "!panic! {s}", .{msg});

    while (true) {}
}

const ALIGN = 1 << 0;
const MEMINFO = 1 << 1;
const MAGIC = 0x1BADB002;
const FLAGS = ALIGN | MEMINFO;

const MultibootHeader = packed struct {
    magic: i32 = MAGIC,
    flags: i32,
    checksum: i32,
    padding: u32 = 0,
};

export var multiboot align(4) linksection(".multiboot") = MultibootHeader{
    .flags = FLAGS,
    .checksum = -(MAGIC + FLAGS),
};

export var stack_bytes: [16 * 1024]u8 align(16) linksection(".bss") = undefined;
const stack_bytes_slice = stack_bytes[0..];

export fn _start() callconv(.Naked) noreturn {
    asm volatile (
        \\ movl %[stack_top], %esp
        \\ movl %esp, %ebp
        \\ call kernel_main
        :
        : [stack_top] "{ecx}" (@intFromPtr(&stack_bytes_slice) + @sizeOf(@TypeOf(stack_bytes_slice))),
    );
    while (true) {}
}

export fn kernel_main() callconv(.C) void {
    const com1 = serial.initialize(serial.COM1) catch unreachable;
    kernel_log.initialize(com1);

    gdt.initialize();

    console.initialize();
    console.puts("Hello Zig Kernel!\n\n");

    cpuid.initialize();

    keyboard.report_status();
    keyboard.set_leds(true, true, true);

    pci.enumerate_buses();
}
