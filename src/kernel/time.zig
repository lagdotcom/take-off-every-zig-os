const std = @import("std");

pub const DateTime = struct {
    year: i32,
    month: u4,
    day: u5,
    hour: u5,
    minute: u6,
    second: u6,
    millisecond: u10,

    pub fn format_ymd(self: DateTime, buffer: []u8) ![]u8 {
        return std.fmt.bufPrint(buffer, "{d:0>5}-{d:0>2}-{d:0>2}", .{ self.year, self.month, self.day });
    }
};
