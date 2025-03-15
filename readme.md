# Take Off Every Zig

It's an operating system! Well, in theory. For now, it's a toy kernel that does nothing.

## Prerequisites

- [zigup](https://github.com/marler8997/zigup) or [Zig](https://ziglang.org) 0.13.0
- [qemu](https://www.qemu.org)

## Getting Started

- Download `bios32.bin` from https://github.com/BlankOn/ovmf-blobs and save it into the root directory.
- Run `zigup run 0.13.0 build qemu -Dboot=uefi -Dserial=stdio`
  - or `zig build qemu -Dboot=uefi -Dserial=stdio` if you're not using zigup

## TODO

- like everything, this is barely a kernel
- add PDB reading so the kernel can give a proper stack trace
  - preprocess with https://github.com/moyix/pdbparse ?
  - or does my EFI file contain a .debug section?
