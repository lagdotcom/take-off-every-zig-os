const mf2 = @import("io/mf2_keyboard.zig");

pub fn initialize() !void {
    try mf2.initialize();
}
