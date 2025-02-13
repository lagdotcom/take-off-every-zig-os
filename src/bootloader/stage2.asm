include 'constants.asm'

use16
org bootloader_stage2_org
bootloader_2nd_stage:

  call check_a20
  jc a20_activated

a20_bios_method:

  mov     ax,2403h
  int     15h                         ; Int 15/AX=2403h - SYSTEM - later PS/2s - QUERY A20 GATE SUPPORT
  jc      a20_ns                      ; CF set on error
  cmp     ah,0                        ; AH = status (non-zero bad)
  jnz     a20_ns

  mov     ax,2402h
  int     15h                         ; Int 15/AX=2402h - SYSTEM - later PS/2s - GET A20 GATE STATUS
  jc      a20_failed                  ; CF set on error
  cmp     ah,0                        ; AH = status (non-zero bad)
  jnz     a20_failed

  cmp     al,1                        ; 0h=disabled, 01=enabled
  jz      a20_activated

  mov     ax,2401h
  int     15h                         ; Int 15/AX=2401h - SYSTEM - later PS/2s - ENABLE A20 GATE
  jc      a20_failed                  ; CF set on error
  cmp     ah,0                        ; AH = status (non-zero bad)
  jnz     a20_failed

  jmp a20_activated

a20_failed:
  ; TODO try another A20 method
  lea si,[failed_msg]
  jmp show_error_msg

a20_ns:
  ; TODO try another A20 method
  lea si,[not_supported_msg]
  jmp show_error_msg

a20_activated:
  ; TODO continue with booting
  lea si,[activated_msg]
  jmp show_error_msg

; check if A20 is enabled, return value in cf
check_a20:
    pusha

    xor ax, ax ; ax = 0
    mov es, ax

    not ax ; ax = 0xFFFF
    mov ds, ax

    mov di, 0500h
    mov si, 0510h

    mov al, byte [es:di]
    push ax

    mov al, byte [ds:si]
    push ax

    mov byte [es:di], 0
    mov byte [ds:si], 0FFh

    cmp byte [es:di], 0FFh

    pop ax
    mov byte [ds:si], al

    pop ax
    mov byte [es:di], al

    clc
    je .exit

    stc

.exit:
    popa
    ret

show_error_msg:
  mov ah,0eh
  xor bx,bx                           ; BH = page number, BL = foreground colour
.loop:
  lodsb                               ; AL = character to write
  cmp al,0
  je infinite_loop
  int 010h                            ; Int 10/AH=0Eh - VIDEO - TELETYPE OUTPUT
  jmp short .loop

infinite_loop: jmp short infinite_loop

not_supported_msg           db "INT 15h not supported",0
failed_msg                  db "A20 failed",0
activated_msg               db "A20 activated",0
