const std = @import("std");

const log_function = fn (comptime format: []const u8, args: anytype) void;

var hex_dump_buffer: [48]u8 = undefined;
var char_dump_buffer: [16]u8 = undefined;

pub fn hex_dump(logger: log_function, data: []const u8) void {
    var i: usize = 0;

    while (i < data.len) {
        var hi: usize = 0;
        var ci: usize = 0;

        for (0..16) |_| {
            if (i >= data.len) break;
            const b = data[i];

            hi += std.fmt.formatIntBuf(hex_dump_buffer[hi .. hi + 3], b, 16, .lower, .{ .fill = '0', .width = 2 });
            hex_dump_buffer[hi] = ' ';
            hi += 1;

            char_dump_buffer[ci] = if (b >= 32 and b < 128) b else '.';
            ci += 1;

            i += 1;
        }

        logger("{x:0>8} | {s:<48}| {s}", .{ i, hex_dump_buffer[0..hi], char_dump_buffer[0..ci] });
    }
}

pub fn struct_dump(comptime T: type, logger: log_function, data: *T) void {
    logger("{s} (size={d})", .{ @typeName(T), @sizeOf(T) });
    inline for (std.meta.fields(T)) |f|
        logger("  {d:4} | .{s} = {any}", .{ @offsetOf(T, f.name), f.name, @field(data, f.name) });
}
