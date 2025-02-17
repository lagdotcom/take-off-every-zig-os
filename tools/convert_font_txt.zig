const std = @import("std");

fn read_usize_line(r: std.fs.File.Reader) !usize {
    var value: usize = 0;
    var first = true;

    while (true) {
        const c = try r.readByte();
        if (c == '\n') {
            if (first) return error.Empty;
            return value;
        }

        if (!std.ascii.isDigit(c)) return error.NotDigit;

        first = false;
        value *= 10;

        value += (c - '0');
    }
}

fn read_char_data(allocator: std.mem.Allocator, r: std.fs.File.Reader, w: usize, h: usize) ![]bool {
    const bits = try allocator.alloc(bool, w * h);
    @memset(bits, false);

    var row: usize = 0;
    var col: usize = 0;

    while (true) {
        const c = try r.readByte();
        if (c == '\n') {
            if (row >= h) return error.TooManyRows;

            row += 1;
            col = 0;
        } else if (c == '~') {
            return bits;
        } else {
            if (col >= w) return error.RowTooLong;

            bits[row * w + col] = c != ' ';
            col += 1;
        }
    }
}

const GlyphData = struct {
    cp: u32,
    bits: []bool,
};

fn get_next_glyph(allocator: std.mem.Allocator, r: std.fs.File.Reader, w: usize, h: usize) !?GlyphData {
    var cp_storage: [4]u8 = undefined;
    var i: usize = 0;

    const end = try r.context.getEndPos();
    while (true) {
        const pos = try r.context.getPos();
        if (pos >= end) return null;

        const c = try r.readByte();

        if (c == '\n') {
            if (i == 0) continue;

            const cp = try std.unicode.utf8Decode(cp_storage[0..i]);
            const bits = try read_char_data(allocator, r, w, h);
            return .{ .cp = cp, .bits = bits };
        }

        cp_storage[i] = c;
        i += 1;
    }
}

const CharEntry = extern struct { cp: u32, offset: u32 };

fn process_font_txt(allocator: std.mem.Allocator, path: []u8) !void {
    // std.log.debug("reading: {s}", .{path});
    const f = try std.fs.cwd().openFile(path, .{ .mode = .read_only });
    errdefer f.close();

    const r = f.reader();

    const char_width = try read_usize_line(r);
    const char_height = try read_usize_line(r);
    const space_width = try read_usize_line(r);
    const unknown_char = try read_char_data(allocator, r, char_width, char_height);

    var out_filename = try allocator.dupe(u8, path);
    defer allocator.free(out_filename);
    out_filename[out_filename.len - 3] = 'f';
    out_filename[out_filename.len - 2] = 'o';
    out_filename[out_filename.len - 1] = 'n';

    var entries = std.ArrayList(CharEntry).init(allocator);
    var glyph_bits = try std.mem.concat(allocator, bool, &.{unknown_char});

    while (try get_next_glyph(allocator, r, char_width, char_height)) |g| {
        try entries.append(.{ .cp = g.cp, .offset = @intCast(glyph_bits.len) });
        glyph_bits = try std.mem.concat(allocator, bool, &.{ glyph_bits, g.bits });
    }

    std.sort.insertion(CharEntry, entries.items, {}, struct {
        fn lessThan(_: void, a: CharEntry, b: CharEntry) bool {
            if (a.cp == b.cp) std.debug.panic("font has duplicate codepoint: {d}", .{a.cp});
            return a.cp < b.cp;
        }
    }.lessThan);

    f.close();

    // std.log.debug("writing: {s}, {d} glyphs", .{ out_filename, entries.items.len });
    const o = try std.fs.cwd().createFile(out_filename, .{});
    defer o.close();

    const ow = o.writer();
    _ = try ow.write("TOEZFONm");
    try ow.writeInt(u16, @intCast(char_width), .little);
    try ow.writeInt(u16, @intCast(char_height), .little);
    try ow.writeInt(u16, @intCast(space_width), .little);

    try ow.writeInt(u16, @intCast(entries.items.len), .little);

    for (entries.items) |e| {
        try ow.writeInt(u32, e.cp, .little);
        try ow.writeInt(u32, e.offset, .little);
    }

    _ = try ow.write(@ptrCast(glyph_bits));
}

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

    for (args[1..]) |arg|
        try process_font_txt(allocator, arg);
}
