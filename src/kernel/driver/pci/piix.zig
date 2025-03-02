// Device Driver for 82371FB (PIIX) AND 82371SB (PIIX3)
// 8086:122E    PIIX    (PCI to ISA Bridge)
// 8086:1230    PIIX    (IDE Interface)
// 8086:7000    PIIX3   (PCI to ISA Bridge)
// 8086:7010    PIIX3   (IDE Interface)
// 8086:7020    PIIX3   (USB Interface)

const registry = @import("../../pci.zig");
const ide = @import("piix/ide.zig");

pub fn initialize() void {
    registry.add_driver(ide.piix3, &ide.piix3_driver);
}
