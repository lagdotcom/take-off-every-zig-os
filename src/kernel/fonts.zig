const std = @import("std");

const console = @import("console.zig");

const FONHeader = extern struct {
    magic: [8]u8,
    char_width: u16,
    char_height: u16,
    space_width: u16,
    entry_count: u16,
};

fn read_fon(raw: []const u8) console.FontData {
    const h: *const FONHeader = @ptrCast(@alignCast(raw[0..@sizeOf(FONHeader)]));
    if (!std.mem.eql(u8, &h.magic, "TOEZFONm")) @compileError("font missing magic number");

    const entries_offset: usize = @sizeOf(FONHeader);
    const entries_size: usize = @as(usize, h.entry_count) * @sizeOf(console.CharEntry);

    const chars: []console.CharEntry = @as([*]console.CharEntry, @constCast(@alignCast(@ptrCast(raw[entries_offset .. entries_offset + entries_size]))))[0..h.entry_count];

    const data_offset = entries_offset + entries_size;
    const data_size = (h.entry_count + 1) * h.char_width * h.char_height;
    const glyph_data: []const bool = @as([*]const bool, @ptrCast(raw[data_offset..]))[0..data_size];

    return .{
        .char_width = h.char_width,
        .char_height = h.char_height,
        .space_width = h.space_width,
        .chars = chars,
        .glyph_data = glyph_data,
    };
}

pub const laggy_8x8 = read_fon(@embedFile("../fonts/laggy8x8.fon"));
pub const zero_wing_8x8 = read_fon(@embedFile("../fonts/zerowing8x8.fon"));
