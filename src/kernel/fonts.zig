const std = @import("std");

const console = @import("console.zig");
const shell = @import("shell.zig");

pub const fon_header_magic = "TOEZFONm";

pub const FONHeader = extern struct {
    magic: [8]u8,
    char_width: u16,
    char_height: u16,
    space_width: u16,
    entry_count: u16,
};

pub const FONEntry = extern struct {
    cp: u32,
    offset: u32,

    pub fn less_than(_: void, a: FONEntry, b: FONEntry) bool {
        return a.cp < b.cp;
    }
};

fn read_fon(comptime font_name: []const u8) console.FontData {
    const file_name = "../fonts/" ++ font_name ++ ".fon";
    const raw = @embedFile(file_name);

    const h: *const FONHeader = @alignCast(@ptrCast(raw[0..@sizeOf(FONHeader)]));
    if (!std.mem.eql(u8, &h.magic, fon_header_magic)) @compileError("font missing magic number");

    const entries_offset: usize = @sizeOf(FONHeader);
    const entries_size: usize = @as(usize, h.entry_count) * @sizeOf(FONEntry);

    const chars: []FONEntry = @as([*]FONEntry, @constCast(@alignCast(@ptrCast(raw[entries_offset .. entries_offset + entries_size]))))[0..h.entry_count];

    const data_offset = entries_offset + entries_size;
    const data_size = (h.entry_count + 1) * h.char_width * h.char_height;
    const glyph_data: []const bool = @as([*]const bool, @ptrCast(raw[data_offset..]))[0..data_size];

    return .{
        .name = font_name,
        .char_width = h.char_width,
        .char_height = h.char_height,
        .space_width = h.space_width,
        .chars = chars,
        .glyph_data = glyph_data,
    };
}

pub const laggy = read_fon("laggy");
pub const zero_wing = read_fon("zero_wing");

const FontList = std.ArrayList(console.FontData);
var fonts: FontList = undefined;

pub fn initialize(allocator: std.mem.Allocator) !void {
    fonts = FontList.init(allocator);
    try fonts.append(laggy);
    try fonts.append(zero_wing);

    try shell.add_command(.{
        .name = "font",
        .summary = "list available fonts or change font",
        .exec = shell_font,
    });
}

fn shell_font(sh: *shell.Context, args: []const u8) !void {
    if (args.len == 0) {
        var t = try sh.table();
        try t.add_heading(.{ .name = "Name" });
        try t.add_heading(.{ .name = "Size" });
        try t.add_heading(.{ .name = "Glyphs" });

        for (fonts.items) |*font| {
            try t.add_string(font.name);
            try t.add_fmt("{d}x{d}", .{ font.char_width, font.char_height });
            try t.add_number(font.chars.len, 10);
            try t.end_row();
        }
        t.print();
        return;
    }

    for (fonts.items) |*font| {
        if (std.mem.eql(u8, args, font.name)) {
            console.set_font(font);
            console.printf("Changed font to {s}\n", .{font.name});
            return;
        }
    }

    console.printf("No such font: {s}", .{args});
}
