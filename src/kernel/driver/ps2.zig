const mf2 = @import("io/mf2_keyboard.zig");
const mouse = @import("io/generic_mouse.zig");

pub fn initialize() !void {
    try mf2.initialize();
    try mouse.initialize();
}
