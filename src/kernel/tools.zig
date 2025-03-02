const std = @import("std");

pub const log_function = fn (comptime format: []const u8, args: anytype) void;

var hex_dump_buffer: [48]u8 = undefined;
var char_dump_buffer: [16]u8 = undefined;

pub fn hex_dump(logger: log_function, data: []const u8) void {
    var i: usize = 0;

    logger("            0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f", .{});

    while (i < data.len) {
        var hi: usize = 0;
        var ci: usize = 0;

        var j = i;

        for (0..16) |_| {
            if (j >= data.len) break;
            const b = data[j];

            hi += std.fmt.formatIntBuf(hex_dump_buffer[hi .. hi + 3], b, 16, .lower, .{ .fill = '0', .width = 2 });
            hex_dump_buffer[hi] = ' ';
            hi += 1;

            char_dump_buffer[ci] = if (b >= 32 and b < 128) b else '.';
            ci += 1;

            j += 1;
        }

        logger("{x:0>8} | {s:<48}| {s}", .{ i, hex_dump_buffer[0..hi], char_dump_buffer[0..ci] });
        i = j;
    }
}

pub fn struct_dump(comptime T: type, logger: log_function, data: *const T) void {
    logger("{s} (size={d})", .{ @typeName(T), @sizeOf(T) });
    inline for (std.meta.fields(T)) |f|
        logger("  {d:4} | .{s} = {any}", .{ @offsetOf(T, f.name), f.name, @field(data, f.name) });
}

pub fn split_by_space(cmd_line: []const u8) [2][]const u8 {
    const si = std.mem.indexOfAny(u8, cmd_line, " \r\n\t");
    const first_word = if (si) |i| cmd_line[0..i] else cmd_line;
    const rest_of_line = if (si) |i| cmd_line[i + 1 ..] else cmd_line[0..0];

    return .{ first_word, rest_of_line };
}

const size_prefix_list = " KMGTPEZY";
pub fn nice_size(buffer: []u8, size: u64) ![]u8 {
    var multiple = size;
    for (size_prefix_list) |prefix| {
        if (multiple < 1000) return std.fmt.bufPrint(buffer, "{d:4}{c}B", .{ multiple, prefix });
        multiple /= 1024;
    }
    unreachable;
}
