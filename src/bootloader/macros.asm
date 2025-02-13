macro show_hex op,bits
{
  repeat bits/4
    d = '0' + op shr (bits-%*4) and 0Fh
    if d > '9'
      d = d + 'A'-'9'-1
    end if
    display d
  end repeat
}

macro show_hex_var name,op,bits
{
  display name
  display '='
  show_hex op,bits
  display 13,10
}

; set dl and es:bx before calling this
macro disk_read_sectors_into_memory sector,heads,sectors_per_track,sectors
{
  bios_sector = 1 + (sector mod sectors_per_track)
  bios_head = (sector / sectors_per_track) mod heads
  bios_track = (sector / sectors_per_track) / heads

  t_lo = bios_track and 0ffh
  t_hi = (bios_track and 300h) shr 8

  ; AL = sector count
  mov ax,(2 shl 8) or sectors

  ; CH = cylinder[0..8], CL = cylinder[9,10] + sector
  mov cx,(bios_sector or (t_hi shl 6) shl 8) or t_lo

  ; DH = head number, DL = drive number
  mov dh,bios_head
  int 13h             ; Int 13/AH=02h - DISK - READ SECTOR(S) INTO MEMORY
  ; CF set on error
}

macro scan_file buffer,file_name
{
  clc
  mov si,buffer
.loop:
  mov al,[si]
  test al,al
  je .notfound
  push si
  mov cx,11
  mov di,file_name
  ; do the comparison
  repe cmpsb
  pop si
  je .exit
  add si,32
  jmp short .loop
.notfound:
  stc
.exit:
}
