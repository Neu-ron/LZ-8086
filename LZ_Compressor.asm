data segment 
    INDICATOR equ 0 ;COMES BEFORE A LONE CHAR (0 IS AN ACCEPTED INDICATOR)
    namelimit equ 24 
    size db ?  
    EF dw 0
    dupindex db ?            
    message db "Enter file name:", 10, 13, "$"
    newline db 10, 13, "$"
    showsize db "Original size (in bytes): ", 10, 13, "$"
    showdata db "Original data:", 10, 13, "$"
    showdictionary db "Dictionary:", 10, 13, "$"
    showcompressed db "Compressed:", 10, 13, "$"
    shownewsize db "Compressed size (in bytes):", 10, 13, "$"
    final_message db "Compressed successfully!", 10, 13, "$"
    file_name db namelimit dup(?), 0
    newfile_name db namelimit dup(?), 3 dup(?), 0  
    extension db ".LZC", 0
    file_handle dw ?
    compressed_file_handle dw ?
    LAST DW 0 
    buffer_len dw 0
    buffer_offset dw ?
    buffer_size dw ?
    extension_name db namelimit dup(?)
        original_extension db namelimit dup(?)
    extension_extension db ".X10TION", 0
    extension_handle dw ?
    extension_size dw ?
    compressed_size dw ?
    index db 0 
    max_index db 0
    notworthit db "Not compressed.", 10, 13, "$" 
    tocompress dw ?
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;;;;;;;;;;;; dynamic allocation ;;;;;;;;;;;;;;;;;
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    ;; used for variables with no pre known length ;;
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    pointer dw 2 ;points to the first open space of the dynamically allocated memory
    file_data db ?
    buffer db ?
ends

stack segment
    dw   128  dup(0)
ends

code segment 
    
proc GetSize
    pusha 
    xor cx, cx 
    xor dx, dx
    mov bx, file_handle
    mov al, 2
    mov ah, 42h
    int 21h
    mov size, al
    xor al, al
    mov ah, 42h
    mov bx, file_handle
    int 21h
    popa 
    ret  
endp Getsize

proc GetFileName
     pusha
     xor ax, ax
     mov dx, offset message
     mov ah, 9h
     int 21h
     mov dx, offset newline
     int 21h
     xor ax, ax 
     xor cx, cx
     lea bx, file_name  
     again:
     cmp cx, namelimit
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
    mov [file_handle], ax
    popa
    ret
endp OpenFile  

proc OpenToWrite
    mov bp, sp 
    pusha   
    xor ax, ax
    xor dx, dx
    mov al, 1 ; al = 1 => write only
    mov ah, 3Dh
    mov dx, [bp+4] ;mov dx, offset {whatever_file_name}
    int 21h                    
    mov bx, [bp+2]
    mov [bx], ax
    popa
    ret 2
endp OpenToWrite

proc WriteToFile
; Write data to file
    pusha 
    xor ax, ax
    mov ah, 40h
    mov bx, [compressed_file_handle] 
    mov dx, offset ToCompress
    mov cx, 2 
    int 21h
    popa
    ret 
endp WriteToFile 

proc WriteToExtensionFile
    pusha
    xor ax, ax
    mov bx, [extension_handle] 
    mov cx, extension_size
    mov dx, offset original_extension 
    mov ah, 40h
    int 21h
    popa
    ret 
endp WriteToExtensionFile

proc ReadFile
    pusha  
    xor ax, ax 
    xor cx, cx
    mov ah, 3Fh
    mov bx, [file_handle]
    mov cl, size
    mov dx, offset file_data ; pointer + 1 = offset file_data
    int 21h
    xor dx, dx
    mov dl, size
    add pointer, dx
    popa
    ret
endp ReadFile  

proc CloseFile
    mov bp, sp 
    pusha
    xor ax, ax
    mov ah, 3Eh
    mov bx, [bp + 2] ;push a file handle
    int 21h
    popa
    ret 2
endp CloseFile

proc GoToIndex ;returns the address of the index in BX
    MOV BP, SP
    PUSH AX 
    PUSH CX
    PUSH DI
    MOV DI, BUFFER_OFFSET
    MOV AX, [BP+2] ;push index
    MOV CX, BUFFER_LEN
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

proc Compress
    pusha        
    XOR CX, CX
    XOR DX, DX
    XOR AX, AX 
    MOV AX, POINTER         
    MOV DI, AX
    MOV BUFFER_OFFSET, DI
    MOV SI, OFFSET FILE_DATA
    MOV CL, size 
    CMP CL, 0 
    JZ ENDING
    ; PUTTING THE FIRST CHAR INTO THE DICTIONARY
    XOR AX, AX
    MOV AL, [SI] 
    MOV [DI], 1  
    MOV [DI+1], 1
    MOV [DI+2], AL        
    MOV AH, INDICATOR
    MOV TOCOMPRESS, AX 
    ADD COMPRESSED_SIZE, 2 
    CALL WRITETOFILE
    INC SI 
    INC BUFFER_LEN
    DEC CX ;CX
    ADD DI, 2 
    MOV LAST, DI ; LAST = LAST PLACE IN THE BUFFER
    SUB DI, 2
    ADD POINTER, 3 
    ADD BUFFER_SIZE, 3
    CMP CX, 0
    JZ ENDING
    CONT:    
    PUSH CX
    MOV DI, BUFFER_OFFSET 
    INC DI
    MOV CX, BUFFER_LEN     
    LP1:
    PUSH CX
    XOR CX, CX
    XOR AX, AX
    MOV DL, [DI-1]
    MOV INDEX, DL
    XOR DX, DX
    MOV CL, [DI] ;length of the current string (from the buffer)
    ;SCANNING THE FILE DATA AND COMPARING TO THE BUFFER
    LP2:     
    INC DI 
    MOV AL, [SI]
    CMP [DI], AL 
    JNZ NOT_THIS ;SAME => CONTINUE LENGTHENING THE STRING, DIFFERENT => REACHED THE END OF THE STRING, ADD TO BUFFER 
    INC DX ;COUNTS THE STRING LENGTH 
    INC SI
    LOOP LP2
    JMP INDICATE
    NOT_THIS:
    DEC CX
    ADD DI, CX 
    JMP SKIP
    INDICATE:
    MOV EF, DX ;EF = longeset sequence length        
    MOV AL, INDEX 
    MOV DUPINDEX, AL
    MOV MAX_INDEX, AL 
    SKIP:
    POP CX 
    ADD DI, 2
    SUB SI, DX 
    LOOP LP1
    MOV DX, EF
    INC DX 
    newString:
    POP CX
    CMP CX, DX
    JAE GREAT
    OH_NO:
    MOV DX, CX
    CMP DX, EF
    JZ SubNoNew
    GREAT: 
    MOV DI, LAST ;LAST
    INC DI  
    INC BUFFER_LEN
    MOV AX, BUFFER_LEN 
    CMP AX, INDICATOR
    JNZ DONT_ADD
    INC AX      
    DONT_ADD:
    MOV [DI], AX
    INC DI  
    PUSH CX
    ADD BUFFER_SIZE, 2
    MOV CX, DX 
    MOV [DI], DX ; LENGTH OF THE STRING, COMES BEFORE THE STRING IN THE BUFFER, LIKE THIS => [INDEX],[LEN],S,T,R,I,N,G  
    LP3:           
    INC DI 
    MOV AL, [SI]
    MOV [DI], AL
    INC SI 
    INC BUFFER_SIZE                                                                     
    LOOP LP3 
    ADD LAST, DX ;LAST
    ADD LAST, 2 ;LAST 
    XOR AX, AX
    MOV AH, MAX_INDEX
    CMP AH, 0
    JNZ SKIPTHISTHING
    MOV AH, INDICATOR  
    SKIPTHISTHING:
    MOV AL, [SI-1]
    MOV TOCOMPRESS, AX
    CALL WRITETOFILE
    ADD COMPRESSED_SIZE, 2 
    NoNew:
    POP CX 
    SubNoNew:
    SUB CX, DX 
    CMP DX, EF
    JZ NOT_ADDED
    MOV DUPINDEX, 0
    ADD DX, 2
    ADD POINTER, DX 
    XOR DX, DX
    NOT_ADDED: 
    MOV EF, 0 
    MOV MAX_INDEX, 0
    CMP CX, 0
    JNZ CONT
    CMP DUPINDEX, 0
    JZ ENDING
    mov ah, 40h
    mov bx, [compressed_file_handle] 
    mov dx, offset DUPINDEX
    mov cx, 1 
    int 21h
    INC COMPRESSED_SIZE
    ENDING:
    popa
    ret 
endp Compress

proc PrintDictionary
    pusha
    mov bx, buffer_offset
    mov cx, buffer_len
    print_index:
    ;push cx 
    xor ax, ax
    xor dx, dx
    mov al, [bx]
    push ax
    call printdecimal
    push cx
    mov ah, 2
    ;printing " = " : 
    mov dl, " "
    int 21h
    mov dl, "="
    int 21h
    mov dl, " "
    int 21h 
    ;end of printing
    ;printing the string 
    xor dx, dx
    xor ax, ax
    xor cx, cx
    mov ah, 2
    inc bx
    mov cl, [bx]
    print_string:
    inc bx
    mov dl, [bx]
    int 21h
    loop print_string 
    pop cx
    cmp cx, 1
    jz goodbye
    inc bx
    mov ah, 9
    mov dx, offset newline 
    int 21h
    int 21h
    goodbye:
    loop print_index
    popa
    ret     
endp PrintDictionary

proc PrintDecimal
    mov bp, sp
    pusha 
    mov ax, [bp+2]
    xor cx, cx
    xor dx, dx
    p1:
    cmp ax, 0
    je printIt
    mov bx, 10
    div bx
    push dx
    inc cx
    xor dx, dx
    jmp p1
    printIt:
    cmp cx, 0
    je exit
    pop dx
    add dx, 48
    mov ah, 2
    int 21h
    dec cx
    jmp printIt
    exit:
    popa
    ret 2
endp PrintDecimal

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

proc OpenCompressed 
    pusha
    xor ax, ax
    mov al, 0 ; al = 0 => read only
    mov ah, 3Dh
    lea dx, newfile_name
    int 21h
    mov [compressed_file_handle], ax
    popa
    ret  
endp OpenCompressed

proc ReadCompressed
    pusha  
    xor ax, ax 
    mov ah, 3Fh
    mov bx, [compressed_file_handle]
    mov cx, compressed_size
    mov dx, pointer
    int 21h
    popa
    ret
endp ReadCompressed 

start:
; set segment registers:
    mov ax, data
    mov ds, ax
    xor ax, ax
    
    ;//1
    add pointer, offset pointer 
    
    ;//2
    call Getfilename  
    
    ;//3
    call openfile
    
    ;//4
    call GetSize
    
    ;//5
    cmp size, 0
    jz DONT_COMRESS_FILE
    
    ;//6
    ;print: "Original size: {size}"

    ;intro
    mov ah, 9
    mov dx, offset newline
    int 21h
    mov dx, offset newline
    int 21h 
    mov dx, offset newline
    int 21h
    mov dx, offset showsize
    int 21h
    mov dx, offset newline
    int 21h
    
    ;printing size   
    mov ah, 2
    xor ax, ax
    mov al, size
    push ax
    call printdecimal
    
    mov ah, 9
    mov dx, offset newline
    int 21h
    mov dx, offset newline
    int 21h
    
    ;//7
    call ReadFile
    
    ;//8
    mov ax, file_handle  
    push ax
    call closefile  
    
    
    ;//9
    ;print file data
    
    ;intro
    mov ah, 9
    mov dx, offset newline
    int 21h
    mov dx, offset showdata
    int 21h
    mov dx, offset newline
    int 21h 
    
    ;printing data
    mov ah, 2
    xor cx, cx
    mov cl, size
    mov bx, offset file_data
    print1:
    mov dl, [bx]
    int 21h
    inc bx
    loop print1
    
    mov ah, 9
    mov dx, offset newline
    int 21h
    mov dx, offset newline
    int 21h
    
    ;//10
    ;creating the compressed file
    xor ax, ax
    mov bx, offset newfile_name
    mov si, offset file_name 
    newname:      
    mov al, [si]
    cmp al, "."
    jz we
    mov [bx], al
    inc bx
    inc si
    jmp newname
    we:
    mov si, offset extension 
    writeextension:
    mov al, [si]
    cmp al, 0
    jz create
    mov [bx], al
    inc bx
    inc si
    jmp writeextension 
    create:
    xor cx, cx 
    mov dx, offset newfile_name 
    mov al, 2 ;read & write
    mov ah, 3Ch 
    int 21h
    mov [compressed_file_handle], ax  
    
    ;//11
    mov ax, offset newfile_name
    push ax
    mov bx, offset compressed_file_handle
    push bx
    call opentowrite
    
    ;//12
    call Compress
    
    ;//13
    mov ax, compressed_file_handle
    push ax
    call closefile
                            
    ;//14                                           
    xor ax, ax
    mov al, size
    cmp compressed_size, ax
    JAE DELETE_COMPRESSED
        
    
    ;//15                        
    ;printing the dictionary 
    ;intro
    mov ah, 9
    mov dx, offset newline
    int 21h
    mov dx, offset showdictionary
    int 21h
    mov dx, offset newline
    int 21h 
    call PrintDictionary
    mov ah, 9
    mov dx, offset newline
    int 21h
    mov dx, offset newline
    int 21h
    
     
    ;print compressed data
    
    ;intro 
    mov dx, offset newline
    int 21h
    mov dx, offset showcompressed
    int 21h
    mov dx, offset newline
    int 21h 

    ;//16a
    call opencompressed
    
    ;//16b
    call readcompressed
    
    ;//16c
    push compressed_file_handle
    call closefile  
    pop compressed_file_handle
     
    ;//16d 
    ;printing the compressed data
    mov ah, 2
    mov cx, compressed_size
    cmp dupindex, 0
    jz just
    dec cx
    just: 
    mov bx, pointer ; pointer points to the first available spot, not the last taken one, so we need to decrease bx by 1 so it represents the address of the last item
    print2:
    mov ax, [bx]
    mov al, ah  
    xor ah, ah
    push ax 
    call printdecimal
    mov ax, [bx]
    mov ah, 2 
    mov dl, al  
    int 21h
    cmp cx, 1 
    jz dont_decrease
    dec cx        
    add bx, 2 
    dont_decrease:
    loop print2
    
    cmp dupindex, 0
    jz justskip2
    mov ax, [bx-1] 
    mov al, ah
    xor ah, ah
    push ax
    call printdecimal
    
    justskip2:
    mov ah, 9
    mov dx, offset newline
    int 21h
    mov dx, offset newline
    int 21h
    
    ;//17
    ;print new size
    mov dx, offset newline
    int 21h
    mov dx, offset shownewsize
    int 21h
    mov dx, offset newline
    int 21h 
    
    mov ax, compressed_size
    push ax
    call printdecimal
    
         
    ;//18
    ;create extension file
    xor ax, ax
    mov bx, offset extension_name
    mov si, offset file_name
    extensionname:      
    mov al, [si]
    cmp al, "."
    jz justbefore
    mov [bx], al
    inc bx
    inc si
    jmp extensionname
    justbefore:
    push bx
    mov bx, offset original_extension
    buildit:
    mov al, [si]
    cmp al, 0
    jz justbefore2
    mov [bx], al
    inc bx
    inc si
    inc extension_size
    jmp buildit
    
    justbefore2:
    pop bx
    mov si, offset extension_extension
    mov cx, 8 ;".x10tion" length
    org_exten:
    mov al, [si]
    mov [bx], al 
    inc si
    inc bx
    loop org_exten
     
    ;creating the file 
    xor cx, cx 
    mov dx, offset extension_name 
    mov al, 2 ;read & write
    mov ah, 3Ch 
    int 21h
    mov [extension_handle], ax
    
    ;//19
    mov ax, offset extension_name
    push ax
    mov bx, offset extension_handle
    push bx 
    call opentowrite
    
    ;//20
    call writetoextensionfile  
    
    
    ;decompression - seperate program     
    ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
    
    ;//21
    mov ah, 9
    mov dx, offset newline
    int 21h               
    int 21h
    int 21h
    mov dx, offset final_message
    int 21h
    
    ;//22
    ;delete original
    mov ah, 41h
    mov dx, offset file_name
    int 21h
    jmp theEnd
    
    ;//*
    DELETE_COMPRESSED: 
    mov ah, 41h
    mov dx, offset newfile_name
    int 21h
    
    ;//*    
    DONT_COMRESS_FILE:
    mov ah, 9
    mov dx, offset newline
    int 21h
    int 21h
    mov dx, offset notworthit
    int 21h
    
    ;//23
    theEnd:  
    mov ax, 04c00h
    int 21h
    
ends
end start ; set entry point and stop the assembler.





