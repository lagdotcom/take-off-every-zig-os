const console = @import("./console.zig");

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
        \\ movl %[stk], %esp
        \\ movl %esp, %ebp
        \\ call kmain
        :
        : [stk] "{ecx}" (@intFromPtr(&stack_bytes_slice) + @sizeOf(@TypeOf(stack_bytes_slice))),
    );
    while (true) {}
}

export fn kmain() void {
    console.initialize();
    console.puts("Hello Zig Kernel!");
}
