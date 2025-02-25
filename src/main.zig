const builtin = @import("builtin");
const std = @import("std");

const kernel = @import("kernel.zig");

pub const os = @import("env/os.zig");

// TODO figure out how to swap this automatically depending on builtin.zig_version.major
// version 12+
pub const std_options = .{ .log_level = .debug, .logFn = kernel.kernel_log_fn };
// before that
// pub const std_options = struct {
//     pub const log_level = .debug;
//     pub const logFn = kernel_log_fn;
// };

// Define root.panic to override the std implementation
pub const panic = kernel.panic;

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

export fn kernel_main() callconv(.c) void {
    kernel.initialize();
}
