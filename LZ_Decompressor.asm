data segment
    INDICATOR equ 237
    namelimit equ 24
    file_handle dw ?
    decompressed_size dw ?
    size dw ?
    dictionary_size dw ? 
    dictionary_offset dw ?
    decom_file_handle dw ?
    file_name db namelimit dup(?)
    name2 db namelimit dup(?)
    ex_ex db ".X10TION", 0
    original_extension db namelimit dup(?), 0
    extension_handle dw ? 
    extension_size dw ?
    extension_name db namelimit dup(?), 8 dup(?) 
    message db "Enter file name", 10, 13, "$"
    decomp_msg db "Decompressed:", 10, 13, "$"
    newline db 10, 13, "$"
    dictionary_len dw ?
    index_address dw ? 
    dupindex db ?
    length db 1
    ;dynamic:       
    pointer dw 2
    file_data db ?
    dictionary db ?  
ends

stack segment
    dw   128  dup(0)
ends

code segment     

proc decompress
    pusha 
    mov di, pointer
    mov si, pointer
    sub si, size
    mov cx, size
    mov ax, [si] 
    mov index_address, di
    mov [di], 1
    inc di
    mov [di], 1
    inc di
    mov [di], al
    call WriteToFile
    inc di
    sub cx, 2 
    inc decompressed_size
    inc dictionary_len
    add dictionary_size, 3
    add si, 2
    DECOMPRESSING:
    mov length, 1
    inc dictionary_len
    mov ax, dictionary_len
    mov [di], ax
    mov index_address, di
    inc di
    inc dictionary_size
    mov ax, [si] 
    cmp ah, indicator
    JZ NOT_INDEX  
    IS_INDEX:
    xor al, al
    mov al, ah
    xor ah, ah 
    push ax
    call GoToIndex
    inc bx
    mov al, [bx] 
    mov length, al
    inc length
    mov al, length
    mov [di], al
    inc di
    inc dictionary_size 
    xor ax, ax
    push cx
    xor cx, cx
    mov cl, [bx] 
    FINALE:     
    inc bx
    mov al, [bx]
    mov [di], al
    inc di 
    inc decompressed_size
    inc dictionary_size 
    loop Finale
    pop cx
    JMP DONT_LEN
    NOT_INDEX:
    mov al, length
    mov [di], al 
    inc di      
    DONT_LEN:
    mov ax, [si]
    mov [di], al 
    add si, 2
    inc di
    inc decompressed_size
    inc dictionary_size
    call writetofile
    sub cx, 2
    cmp cx, 1
    JZ HERE
    cmp cx, 0
    JNZ DECOMPRESSING
    JMP DINGDING
    HERE:
    mov ax, [si]
    mov dupindex, ah
    xor ah, ah
    push ax   
    call GoToIndex
    mov index_address, bx 
    mov al, [bx+1]
    mov length, al 
    call writetofile 
    xor ah, ah
    add decompressed_size, ax
    DINGDING:
    popa 
    ret 
endp decompress

proc OpenExtension
    pusha
    xor ax, ax
    mov al, 0 ; al = 0 => read only
    mov ah, 3Dh
    lea dx, extension_name
    int 21h
    mov [extension_handle], ax 
    popa
    ret
endp OpenExtension

proc ReadExtension
    pusha
    xor ax, ax
    mov ah, 3Fh
    mov bx, extension_handle
    mov cx, extension_size
    mov dx, offset original_extension
    int 21h    
    popa
    ret
endp ReadExtension

proc OpenToWrite
    mov bp, sp 
    pusha   
    xor ax, ax
    xor dx, dx
    mov al, 1 ; al = 1 => write only
    mov ah, 3Dh
    mov dx, offset name2 ;mov dx, offset newfile_name
    int 21h
    mov [decom_file_handle], ax
    popa
    ret 
endp OpenToWrite

proc WriteToFile
; Write message to file
    pusha 
    xor ax, ax
    mov ah, 40h
    mov bx, [decom_file_handle] 
    mov dx, index_address
    add dx, 2
    xor cx, cx
    mov cl, length
    int 21h
    popa
    ret 
endp WriteToFile 

proc GetSize
    pusha 
    mov bx, file_handle
    mov al, 2
    mov ah, 42h
    int 21h 
    xor ah, ah
    mov size, ax 
    popa 
    ret  
endp Getsize

proc ReadFile
    pusha  
    xor ax, ax 
    mov ah, 3Fh
    mov bx, [file_handle]
    mov cx, size
    mov dx, offset file_data ; pointer + 1 = offset file_data
    int 21h
    mov dx, size
    add pointer, dx
    mov ax, pointer
    mov dictionary_offset, ax 
    popa
    ret
endp ReadFile

proc CloseFile
    mov bp, sp 
    pusha
    xor ax, ax
    mov ah, 3Eh
    mov si, [bp + 2] ;push a file handle
    mov bx, si ;was mov bx, [si]
    int 21h
    popa
    ret 2
endp CloseFile

proc GoToIndex ;returns the address of the index in BX
    MOV BP, SP
    PUSH AX 
    PUSH CX
    PUSH DI
    MOV DI, POINTER 
    MOV AX, [BP+2] ;push index
    MOV CX, size
    L3:
    CMP AL, [DI]
    JZ DONE
    INC DI
    PUSH CX 
    XOR CX, CX
    MOV CL, [DI]
    L2: ;RUNNING UNTIL THE END OF THE STRING TO GET TO THE NEXT INDEX
    INC DI
    LOOP L2
    INC DI
    POP CX
    LOOP L3
    DONE:
    MOV BX, DI
    POP DI
    POP CX
    POP AX
    ret 2
endp GoToIndex

proc GetFileName
     pusha
     xor ax, ax
     mov dx, offset message
     mov ah, 9h
     int 21h
     mov dx, offset newline
     int 21h
     xor cx, cx
     lea bx, file_name  
     again:
     cmp cx, NAMELIMIT
     jz sof 
     mov ah, 1
     int 21h 
     cmp al, 0Dh
     jz sof
     mov [bx], al
     inc bx
     inc cx 
     jmp again
     sof:
     popa
     ret
endp GetFileName

proc OpenFile 
    pusha
    xor ax, ax
    mov al, 0 ; al = 0 => read only
    mov ah, 3Dh
    lea dx, file_name
    int 21h
    mov file_handle, ax
    popa
    ret
endp OpenFile 

proc opendecompressed
    pusha
    xor ax, ax
    mov al, 0 ; al = 0 => read only
    mov ah, 3Dh
    lea dx, name2
    int 21h
    mov decom_file_handle, ax
    popa
    ret
endp opendecompressed

proc ReadDecompressed
    pusha  
    xor ax, ax
    mov al, 2 
    mov ah, 3Fh
    mov bx, [decom_file_handle]
    mov cx, decompressed_size
    mov dx, pointer
    int 21h
    popa
    ret
endp ReadDecompressed 

start:
; set segment registers:    
    mov ax, data
    mov ds, ax
    
    ;//1 
    add pointer, offset pointer
    
    ;//2
    call getfilename
    
    ;//3
    call openfile
    
    ;//4
    call getsize
    
    ;//5
    mov ax, file_handle
    push ax
    call closefile 
    
    ;//6
    call openfile
    
    ;//7 
    call ReadFile
    
    ;//8
    mov ax, file_handle
    push ax
    call closefile 
    
    ;//9
    ;get extension name:
    xor ax, ax
    mov si, offset file_name
    mov di, offset extension_name
    nameof:      
    mov al, [si]
    cmp al, "."
    jz we
    mov [di], al
    inc di
    inc si
    jmp nameof
    we:
    mov si, offset ex_ex 
    writeextension2.0:
    mov al, [si]
    cmp al, 0
    jz bye2.0
    mov [di], al
    inc di
    inc si
    jmp writeextension2.0 
    
    bye2.0: 
    call openextension
    
    ;//10      
    ;get extension file size
    mov bx, extension_handle
    mov al, 2
    mov ah, 42h
    int 21h 
    xor ah, ah
    mov extension_size, ax
    
    ;//11
    mov ax, extension_handle
    push ax
    call closefile 
    
    ;//12
    call openextension
    
    ;//13
    call readextension
    
    ;//14
    mov ax, extension_handle
    push ax
    call closefile  
    
    ;//15
    ;//creating a file for decompressed data:
    xor ax, ax
    mov bx, offset name2
    mov si, offset file_name
    newname:      
    mov al, [si]
    cmp al, "."
    jz we2
    mov [bx], al
    inc bx
    inc si
    jmp newname
    we2:
    mov si, offset original_extension
    writeextension2:
    mov al, [si]
    cmp al, 0
    jz bye2
    mov [bx], al
    inc bx
    inc si
    jmp writeextension2
    bye2:
    ;create new file:
    xor cx, cx 
    mov dx, offset name2 
    mov al, 2 ;read & write
    mov ah, 3Ch 
    int 21h
    mov [decom_file_handle], ax
    
    ;//15 
    call opentowrite
    
    ;//16
    call decompress
    
    ;//17
    mov ax, decom_file_handle 
    push ax
    call closefile
    
    mov ax, dictionary_size
    add pointer, ax
    
    
    ;//18a
    ;printing the decompressed data
        
    call opendecompressed
    
    ;//18b
    call readdecompressed
    
    ;//18c
    mov ax, decom_file_handle
    push ax
    call closefile
    
    ;//18d
    xor ax, ax
    mov ah, 9 
    mov dx, offset newline
    int 21h               
    int 21h
    
    mov dx, offset decomp_msg
    int 21h                  
    mov dx, offset newline
    int 21h
    
    ;print decompressed data
    mov bx, pointer
    mov cx, decompressed_size
    mov ah, 2        
    LP1:
    mov dl, [bx]
    int 21h
    inc bx
    loop LP1 
    
    ;//19
    mov ax, decom_file_handle
    push ax
    call closefile
    
    ;//20    
    ;delete compressed
    mov ah, 41h
    mov bx, file_handle
    mov dx, offset file_name
    int 21h
    ;delete extension file
    mov ah, 41h
    mov bx, extension_handle
    mov dx, offset extension_name
    int 21h
    
    ;//21
    mov ax, 4c00h ; exit to operating system.
    int 21h    
ends

end start ; set entry point and stop the assembler.
