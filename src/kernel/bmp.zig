const std = @import("std");
const log = std.log.scoped(.bmp);

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

    // everything after this is part of header_size above, this is just one version
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

const BufferReader = std.io.FixedBufferStream([]const u8).Reader;

pub const BMP = struct {
    header: *const Header,
    palette: []const u8,
    pixels: []const u8,

    pub fn init(raw: []const u8) !BMP {
        const header: *const Header = @alignCast(@ptrCast(raw[0..@sizeOf(Header)]));
        if (!std.mem.eql(u8, "BM", &header.magic)) return error.NotABitmap;

        const palette_start = @as(usize, header.data_offset) - header.colours_in_palette * 4;
        const palette_size = header.colours_in_palette * 4;

        return BMP{
            .header = header,
            .palette = raw[palette_start .. palette_start + palette_size],
            .pixels = raw[header.data_offset .. header.data_offset + header.data_size],
        };
    }

    pub fn display(self: *const BMP, sx: usize, sy: usize) !void {
        var stream = std.io.fixedBufferStream(self.pixels);
        var in = stream.reader();
        const width: usize = @intCast(self.header.width);
        const height: usize = @intCast(self.header.height);
        var plotter = OutputPlotter.init(sx, sy, width, height);

        return switch (self.header.bits_per_pixel) {
            24 => switch (self.header.compression) {
                .None => self.display_rgb24_uncompressed(&in, &plotter),
                else => error.UnsupportedCompression,
            },
            8 => switch (self.header.compression) {
                .RLE8 => self.display_rle8(&in, &plotter),
                else => error.UnsupportedCompression,
            },
            else => error.UnsupportedBitsPerPixel,
        };
    }

    fn display_rgb24_uncompressed(_: *const BMP, in: *BufferReader, plotter: *OutputPlotter) !void {
        // const stride = video.vga.pixels_per_scan_line + plotter.width;

        for (0..plotter.height) |_| {
            // TODO replace this with a memcpy
            for (0..plotter.width) |_| {
                const b = try in.readByte();
                const g = try in.readByte();
                const r = try in.readByte();

                plotter.plot(r, g, b);
            }

            plotter.end_line();
            while (in.context.pos % 4 != 0) _ = try in.readByte();
        }
    }

    fn display_rle8(self: *const BMP, in: *BufferReader, plotter: *OutputPlotter) !void {
        while (in.context.pos < self.header.data_size) {
            // log.debug("@{d},{d} pos={d}", .{ plotter.ox, plotter.oy, in.context.pos });
            const cmd = in.readByte() catch |err| switch (err) {
                error.EndOfStream => return,
                else => return err,
            };

            if (cmd == 0) {
                const arg = try in.readByte();
                switch (arg) {
                    0 => {
                        plotter.end_line();
                        // log.debug("00 00 | end line", .{});
                    },
                    1 => {
                        // log.debug("00 01 | end image", .{});
                        return;
                    },
                    2 => {
                        const dx = try in.readByte();
                        const dy = try in.readByte();
                        plotter.jump(dx, dy);
                        // log.debug("00 02 {x:2} {x:2} | jump", .{ dx, dy });
                    },
                    else => {
                        // log.debug("00 {x:2} | verbatim data", .{arg});
                        for (0..arg) |_| {
                            const pixel = try in.readByte();
                            self.display_palette_pixel(pixel, plotter);
                        }

                        // zero padded
                        if (in.context.pos % 2 != 0) _ = try in.readByte();
                    },
                }
                continue;
            }

            const pixel = try in.readByte();
            // log.debug("{x:2} {x:2} | rle", .{ cmd, pixel });
            for (0..cmd) |_| self.display_palette_pixel(pixel, plotter);
        }
    }

    fn display_palette_pixel(self: *const BMP, index: u8, plotter: *OutputPlotter) void {
        const raw_index = @as(usize, index) * 4;
        const b = self.palette[raw_index];
        const g = self.palette[raw_index + 1];
        const r = self.palette[raw_index + 2];
        plotter.plot(r, g, b);
    }
};

const OutputPlotter = struct {
    sx: usize,
    sy: usize,
    ox: usize,
    oy: usize,
    width: usize,
    height: usize,
    index: usize,

    pub fn init(sx: usize, sy: usize, width: usize, height: usize) OutputPlotter {
        return OutputPlotter{
            .sx = sx,
            .sy = sy,
            .ox = 0,
            .oy = 0,
            .width = width,
            .height = height,
            .index = video.get_index(sx, sy + height - 1),
        };
    }

    pub fn plot(self: *OutputPlotter, r: u8, g: u8, b: u8) void {
        video.plot(self.index, video.rgb(r, g, b));
        self.index += 1;
        self.ox += 1;
    }

    pub fn end_line(self: *OutputPlotter) void {
        self.ox = 0;
        self.oy += 1;
        self.update_index();
    }

    pub fn jump(self: *OutputPlotter, dx: usize, dy: usize) void {
        self.ox += dx;
        self.oy += dy;
        self.update_index();
    }

    fn update_index(self: *OutputPlotter) void {
        self.index = video.get_index(self.sx + self.ox, self.sy + self.height - 1 - self.oy);
    }
};
