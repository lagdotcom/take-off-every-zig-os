const std = @import("std");

const serial = @import("serial.zig");

var port: serial.Port = undefined;

pub fn initialize(use_port: serial.Port) void {
    port = use_port;
    write(.debug, "logging initialized", .{});
}

const LogError = error{};
const log_writer = std.io.Writer(void, LogError, log_callback){ .context = {} };

fn log_callback(_: void, string: []const u8) LogError!usize {
    port.write(string);
    return string.len;
}

pub fn write(comptime level: std.log.Level, comptime format: []const u8, args: anytype) void {
    std.fmt.format(log_writer, "[" ++ @tagName(level) ++ "] " ++ format ++ "\n", args) catch {};
}
