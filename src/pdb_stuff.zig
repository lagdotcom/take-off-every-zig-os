const std = @import("std");

fn replace_slice(input: []const u8, needle: []const u8, replacement: []const u8, output_buffer: []u8) []u8 {
    const size = std.mem.replacementSize(u8, input, needle, replacement);
    _ = std.mem.replace(u8, input, needle, replacement, output_buffer);

    return output_buffer[0..size];
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();
    const stdout = std.io.getStdOut().writer();

    var pdb = try std.pdb.Pdb.init(allocator, "zig-out/efi/boot/BOOTIA32.pdb");
    try pdb.parseDbiStream();
    try pdb.parseInfoStream();

    const output = try allocator.alloc(u8, 500);
    defer allocator.free(output);

    for (0..pdb.modules.len) |i| {
        const res = pdb.getModule(i);
        if (res == error.InvalidDebugInfo) {
            const mod = pdb.modules[i];
            try stdout.print("{d:3}: {s} [{s}] InvalidDebugInfo", .{ i, mod.module_name, mod.obj_file_name });
            continue;
        }

        if (try res) |mod| {
            try stdout.print("{d:3}: {s} [{s}]\n", .{ i, mod.module_name, mod.obj_file_name });

            var addr_start: u64 = 0xffffffffffffffff;
            var addr_end: u64 = 0;

            // time for some symbol parsing
            var symbol_i: usize = 0;
            while (symbol_i != mod.symbols.len) {
                const prefix = @as(*align(1) std.pdb.RecordPrefix, @ptrCast(&mod.symbols[symbol_i]));
                if (prefix.RecordLen < 2)
                    continue;

                switch (prefix.RecordKind) {
                    .S_LPROC32, .S_GPROC32 => {
                        const sym = @as(*align(1) std.pdb.ProcSym, @ptrCast(&mod.symbols[symbol_i + @sizeOf(std.pdb.RecordPrefix)]));
                        const end = sym.CodeOffset + sym.CodeSize;

                        addr_start = @min(addr_start, sym.CodeOffset);
                        addr_end = @max(addr_end, end);

                        const name = std.mem.sliceTo(@as([*:0]u8, @ptrCast(&sym.Name[0])), 0);

                        const line = try pdb.getLineNumberInfo(mod, sym.CodeOffset);

                        const slice = replace_slice(line.file_name, "C:\\Apps\\zigup-windows-x86_64-v2024_05_05\\zig\\0.13.0\\files\\lib\\", "zig:", output);
                        const slice2 = replace_slice(slice, "D:\\zig-os\\src\\", "toez:", output);

                        try stdout.print("     {x:6}-{x:6}: {s:40} {s}:{d}\n", .{ sym.CodeOffset, end, name, slice2, line.line });
                    },
                    else => {},
                }

                symbol_i += prefix.RecordLen + @sizeOf(u16);
            }

            try stdout.print("     {x:6}-{x:6} all\n", .{ addr_start, addr_end });
        }
    }
}
