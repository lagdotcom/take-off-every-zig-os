include 'constants.asm'

boot_signature_org = bootloader_org + bpb_bytes_per_sector - 2
boot_signature = 0aa55h

bpb_bytes_per_sector          = 512
bpb_sectors_per_cluster       = 1
bpb_reserved_sectors          = 1
bpb_fat_count                 = 2
bpb_root_directory_entries    = 224
bpb_total_sectors             = 2880
bpb_sectors_per_fat           = 9
bpb_sectors_per_track         = 18
bpb_head_count                = 2

use16
org bootloader_org
  ; BIOS Parameter Block
  jmp short bootloader_start  ; jump over the rest of the header
  nop

  oem_identifier            db "TOEZigOS"
  bytes_per_sector          dw bpb_bytes_per_sector
  sectors_per_cluster       db bpb_sectors_per_cluster
  reserved_sectors          dw bpb_reserved_sectors
  fat_count                 db bpb_fat_count
  root_directory_entries    dw bpb_root_directory_entries
  total_sectors             dw bpb_total_sectors
  media_descriptor_type     db 0f0h  ; 3.5" floppy, 1.44mb
  sectors_per_fat           dw bpb_sectors_per_fat
  sectors_per_track         dw bpb_sectors_per_track
  head_count                dw bpb_head_count
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
  mov [drive_number], dl              ; save the actual drive number

  ; clear all sectors
  mov ax,cs
  mov ds,ax
  mov es,ax
  mov ss,ax

  ; set up stack below 7c00
  mov sp,bootloader_org
  sti

  ; drive number is still in dl
  xor ah,ah
  int 013h                            ; Int 13/AH=00h - DISK - RESET DISK SYSTEM
  jc disk_error                       ; CF set on error

include 'macros.asm'

; where's the FAT root directory?
root_dir_sectors = ((bpb_root_directory_entries * 32) + bpb_bytes_per_sector - 1) / bpb_bytes_per_sector
first_data_sector = bpb_reserved_sectors + (bpb_fat_count * bpb_sectors_per_fat) + root_dir_sectors
first_root_dir_sector = first_data_sector - root_dir_sectors

  mov bx,500h
  disk_read_sectors_into_memory first_root_dir_sector,bpb_head_count,bpb_sectors_per_track,root_dir_sectors
  jc disk_error

scan_file 500h,stage2_file_name
  jc fnf_error
; ds:si now points to the matching file entry

; ok here's my basic plan

; 1. read in two sectors of the fat / the whole fat?
  mov bx,700h
  disk_read_sectors_into_memory bpb_reserved_sectors,bpb_head_count,bpb_sectors_per_track,2 ; bpb_sectors_per_fat

; 2. set bx to @bootloader_stage2_org
  mov bx,bootloader_stage2_org

; 3. calculate the starting cluster
  mov ax,[si + 26]                    ; DirEntry.cluster_lo
  mov [current_cluster],ax

; 4. read the cluster contents to bx, advance bx
.cluster_loop:
  mov ax,[current_cluster]
  dec ax
  dec ax
  mov dx,bpb_sectors_per_cluster
  mul dx
  add ax,first_data_sector
  ; ; TODO CALC_SECTOR lol

  ; disk_read_sectors_into_memory CALC_SECTOR,bpb_head_count,bpb_sectors_per_track
  add bx,512

; 5. read the next cluster value from fat
  mov cx,ax
  shl ax,1
  add ax,cx
  add ax,700h
  ; TODO

; 6. if the cluster value is 0ff7h, die horribly
  ; TODO

; 7. if cluster value is < 0xff7, jump to 4
  ; TODO

; 8. jump to @bootloader_stage2_org
  ; jmp bootloader_stage2_org

  lea si,[not_implemented_msg]
  jmp show_error_msg

disk_error:
  lea si,[disk_error_msg]
  jmp show_error_msg

fnf_error:
  lea si,[fnf_error_msg]
  jmp show_error_msg

show_error_msg:
  mov ah,0eh
  xor bx,bx                           ; BH = page number, BL = foreground colour
.loop:
  lodsb                               ; AL = character to write
  cmp al,0
  je infinite_loop
  int 010h                            ; Int 10/AH=0Eh - VIDEO - TELETYPE OUTPUT
  jmp short .loop

infinite_loop:
  cli
  hlt
  jmp short infinite_loop

not_implemented_msg         db "not finished yet!",0
disk_error_msg              db "disk error",0
fnf_error_msg               db "file not found",0
stage2_file_name            db "STAGE2  BIN"

align 16
current_cluster             dw 0

; make sure we fit in the boot sector!
assert($<=boot_signature_org)
rb boot_signature_org-$
  dw boot_signature
