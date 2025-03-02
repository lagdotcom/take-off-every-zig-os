const piix = @import("pci/piix.zig");

pub fn initialize() !void {
    try piix.initialize();
}
