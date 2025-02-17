# Take Off Every Zig

It's an operating system! Well, in theory. For now, it's a toy kernel that does nothing.

## Prerequisites

- [zigup](https://github.com/marler8997/zigup) or [Zig](https://ziglang.org) 0.13.0
- [qemu](https://www.qemu.org)

## Getting Started

- Download `bios32.bin` from https://github.com/BlankOn/ovmf-blobs and save it into the root directory.
- Run `zigup run 0.13.0 build qemu -Dboot=uefi -Dserial=stdio`
  - or `zig build qemu -Dboot=uefi -Dserial=stdio` if you're not using zigup
