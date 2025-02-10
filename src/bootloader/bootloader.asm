boot_location = 7c00h
boot_signature_location = boot_location + 1feh
boot_signature = 0aa55h
fat_segment = 0050h

use16
org boot_location
  ; BIOS Parameter Block
  jmp short bootloader_start  ; jump over the rest of the header
  nop

  oem_identifier            db "ZigOS   "
  bytes_per_sector          dw 512
  sectors_per_cluster       db 1
  reserved_sectors          dw 1
  fat_count                 db 2
  root_directory_entries    dw 224
  total_sectors             dw 2880
  media_descriptor_type     db 0f0h  ; 3.5" floppy, 1.44mb
  sectors_per_fat           dw 9
  sectors_per_track         dw 18
  head_count                dw 2
  hidden_sectors            dd 0
  large_sector_count        dd 0
  drive_number              db 0
                            db 0
  signature                 db 29h
  volume_id                 dd 0aa0925ffh
  volume_label              db "plz boot os"
  system_identifier         db "FAT12   "

; Boot Code
bootloader_start:
  ; our address might be 0:7Cxx or 7C00:00xx, let's fix that
  jmp far 0:start_boot

start_boot:
  cli
  mov [drive_number], dl             ; save the actual drive number

  ; clear all sectors
  mov ax,cs
  mov ds,ax
  mov es,ax
  mov ss,ax

  ; set up stack below 7c00
  mov sp,boot_location
  sti

  ; drive number is still in dl
  xor ah,ah
  int 013h
  jc disk_error

  lea si,[not_implemented_msg]
  jmp show_error_msg

disk_error:
  lea si,[disk_error_msg]
  jmp show_error_msg

show_error_msg:
  mov ah,0eh
  xor bx,bx
.loop:
  lodsb
  cmp al,0
  je infinite_loop
  int 010h
  jmp short .loop

infinite_loop: jmp short infinite_loop

not_implemented_msg         db "not finished yet!",0
disk_error_msg              db "disk error",0

; make sure we fit in the boot sector!
assert($<=boot_signature_location)
rb boot_signature_location-$
  dw boot_signature
