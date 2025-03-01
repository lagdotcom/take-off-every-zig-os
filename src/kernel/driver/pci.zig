const std = @import("std");

const piix = @import("pci/piix.zig");

pub fn initialize(allocator: std.mem.Allocator) void {
    piix.initialize(allocator);
}
