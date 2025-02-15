const std = @import("std");

const console = @import("console.zig");

fn read_fon(raw: []const u8) console.FontData {
    const char_width = std.mem.readInt(u16, raw[0..2], .little);
    const char_height = std.mem.readInt(u16, raw[2..4], .little);
    const space_width = std.mem.readInt(u16, raw[4..6], .little);
    const entry_count = std.mem.readInt(u16, raw[6..8], .little);

    const entries_offset: usize = 8;
    const entries_size: usize = @as(usize, entry_count) * 8;

    const chars: []console.CharEntry = @as([*]console.CharEntry, @constCast(@alignCast(@ptrCast(raw[entries_offset .. entries_offset + entries_size]))))[0..entry_count];

    // TODO make this work here or in parse_font_txt.zig
    // std.sort.insertion(console.CharEntry, chars, {}, console.CharEntry.lessThan);

    const data_offset = entries_offset + entries_size;
    const data_size = (entry_count + 1) * char_width * char_height;
    const glyph_data: []const bool = @as([*]const bool, @ptrCast(raw[data_offset..]))[0..data_size];

    return .{
        .char_width = char_width,
        .char_height = char_height,
        .space_width = space_width,
        .chars = chars,
        .glyph_data = glyph_data,
    };
}

pub const laggy8x8 = read_fon(@embedFile("fonts/laggy8x8.fon"));
