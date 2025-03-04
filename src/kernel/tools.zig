const std = @import("std");
const log = std.log.scoped(.tools);

pub const log_function = fn (comptime format: []const u8, args: anytype) void;

var hex_dump_buffer: [48]u8 = undefined;
var char_dump_buffer: [16]u8 = undefined;

pub fn hex_dump(logger: log_function, data: []const u8) void {
    defer log.debug("hex_dump({d} bytes) done", .{data.len});
    var i: usize = 0;

    var hex_dump_stream = std.io.fixedBufferStream(hex_dump_buffer[0..hex_dump_buffer.len]);
    var hex_dump_writer = hex_dump_stream.writer();
    var char_dump_stream = std.io.fixedBufferStream(char_dump_buffer[0..char_dump_buffer.len]);
    var char_dump_writer = char_dump_stream.writer();

    logger("            0  1  2  3  4  5  6  7  8  9  a  b  c  d  e  f", .{});

    while (i < data.len) {
        var j = i;
        hex_dump_stream.reset();
        char_dump_stream.reset();

        for (0..16) |_| {
            if (j >= data.len) break;
            const b = data[j];

            std.fmt.formatInt(b, 16, .lower, .{ .fill = '0', .width = 2 }, hex_dump_writer) catch unreachable;
            hex_dump_writer.writeByte(' ') catch unreachable;
            char_dump_writer.writeByte(if (b >= 32 and b < 128) b else '.') catch unreachable;

            j += 1;
        }

        logger("{x:0>8} | {s:<48}| {s}", .{ i, hex_dump_stream.getWritten(), char_dump_stream.getWritten() });
        i = j;
    }
}

pub fn struct_dump(comptime T: type, logger: log_function, data: *const T) void {
    logger("{s} (size={d})", .{ @typeName(T), @sizeOf(T) });
    inline for (std.meta.fields(T)) |f|
        logger("  {d:4} | .{s} = {any}", .{ @offsetOf(T, f.name), f.name, @field(data, f.name) });
}

pub fn split_by_something(value: []const u8, separators: []const u8) [2][]const u8 {
    const si = std.mem.indexOfAny(u8, value, separators);
    const first_word = if (si) |i| value[0..i] else value;
    const rest_of_line = if (si) |i| value[i + 1 ..] else value[0..0];

    return .{ first_word, rest_of_line };
}

pub fn split_by_whitespace(value: []const u8) [2][]const u8 {
    return split_by_something(value, " \r\n\t");
}

pub fn split_by_path(value: []const u8) [2][]const u8 {
    return split_by_something(value, "/\\");
}

const size_prefix_list = " KMGTPEZY";
pub fn nice_size(buffer: []u8, size: u64) ![]u8 {
    var multiple = size;
    for (size_prefix_list) |prefix| {
        if (multiple < 1000) return std.fmt.bufPrint(buffer, "{d:4}{c}B", .{ multiple, prefix });
        multiple /= 1024;
    }

    return std.fmt.bufPrint(buffer, "TooBig", .{});
}
