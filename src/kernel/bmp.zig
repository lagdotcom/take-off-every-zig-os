const std = @import("std");
const log = std.log.scoped(.bmp);

const tools = @import("tools.zig");
const video = @import("video.zig");

pub const CompressionMethod = enum(u32) {
    None = 0,
    RLE8,
    RLE4,
    BitFields,
    JPEG,
    PNG,
    AlphaBitFields,

    CMYK = 11,
    CMYK_RLE8,
    CMYK_RLE4,
};

pub const Header = extern struct {
    magic: [2]u8,
    file_size: u32 align(1),
    reserved: u32 align(1),
    data_offset: u32 align(1),
    header_size: u32 align(1),
    width: i32 align(1),
    height: i32 align(1),
    planes: u16 align(1),
    bits_per_pixel: u16 align(1),
    compression: CompressionMethod align(1),
    data_size: u32 align(1),
    horizontal_pixels_per_metre: i32 align(1),
    vertical_pixels_per_metre: i32 align(1),
    colours_in_palette: u32 align(1),
    important_colours: u32 align(1),
};

pub const BMP = struct {
    header: *const Header,
    pixels: []const u8,

    pub fn init(raw: []const u8) !BMP {
        const header: *const Header = @alignCast(@ptrCast(raw[0..@sizeOf(Header)]));
        if (!std.mem.eql(u8, "BM", &header.magic)) return error.NotABitmap;

        // TODO
        if (header.bits_per_pixel != 24) return error.UnsupportedBitsPerPixel;
        if (header.compression != .None) return error.UnsupportedCompression;

        return BMP{
            .header = header,
            .pixels = raw[header.data_offset .. header.data_offset + header.data_size],
        };
    }

    pub fn display(self: *const BMP, sx: usize, sy: usize) !void {
        var stream = std.io.fixedBufferStream(self.pixels);
        var in = stream.reader();

        const width: usize = @intCast(self.header.width);
        const height: usize = @intCast(self.header.height);

        var index = video.get_index(sx, sy + height - 1);
        const stride = video.vga.pixels_per_scan_line + width;

        for (0..height) |_| {
            // TODO replace this with a memcpy
            for (0..width) |_| {
                const b = try in.readByte();
                const g = try in.readByte();
                const r = try in.readByte();

                video.plot(index, video.rgb(r, g, b));
                index += 1;
            }

            index -= stride;
        }
    }
};
