# Deal Countdown rounds in the standard, cats and nasty-cats modes and read the mode from the command line

    .intel_syntax noprefix

    .set SYS_GETRANDOM, 318
    .set RANDOM_WORDS, 32

    .section .rodata
    .balign 16
# Give each mode four large cards with nasty-cats using the cards of the 2010 specials
large_decks: .long 25, 50, 75, 100, 25, 50, 75, 100, 12, 37, 62, 87
s_standard: .asciz "standard"
s_cats:     .asciz "cats"
s_nasty:    .asciz "nasty"

    .bss
    .balign 8
random:     .space 8 * RANDOM_WORDS
rand_next:  .space 4

    .text

# Return in eax a random number below edi refilling the random buffer from the kernel when it runs out
rand_below:
    mov ecx, dword ptr [rip + rand_next]
    test ecx, ecx
    jnz 1f
    push rdi
    mov eax, SYS_GETRANDOM
    lea rdi, [rip + random]
    mov esi, 8 * RANDOM_WORDS
    xor edx, edx
    syscall
    pop rdi
    mov ecx, RANDOM_WORDS
1:  dec ecx
    mov dword ptr [rip + rand_next], ecx
    lea rax, [rip + random]
    mov rax, qword ptr [rax + rcx * 8]
    # Accept the tiny modulo bias since 64 random bits dwarf any range used here
    mov ecx, edi
    xor edx, edx
    div rcx
    mov eax, edx
    ret

# Shuffle esi numbers at rdi in place with Fisher-Yates
shuffle:
    push rbx
    push r12
    push r13
    mov r12, rdi
    lea ebx, [rsi - 1]
1:  test ebx, ebx
    jz 2f
    lea edi, [rbx + 1]
    call rand_below
    mov ecx, dword ptr [r12 + rbx * 4]
    mov edx, dword ptr [r12 + rax * 4]
    mov dword ptr [r12 + rbx * 4], edx
    mov dword ptr [r12 + rax * 4], ecx
    dec ebx
    jmp 1b
2:  pop r13
    pop r12
    pop rbx
    ret

# Return in eax 1 when the zero-terminated strings at rdi and rsi are equal and 0 otherwise
str_eq:
1:  mov al, byte ptr [rdi]
    cmp al, byte ptr [rsi]
    jne 2f
    test al, al
    jz 3f
    inc rdi
    inc rsi
    jmp 1b
2:  xor eax, eax
    ret
3:  mov eax, 1
    ret

# Return in rax the four large cards of mode edi
    .globl large_numbers
large_numbers:
    mov eax, edi
    shl eax, 4
    lea rcx, [rip + large_decks]
    add rax, rcx
    ret

# Deal into the six numbers at rdx for mode edi with esi large numbers or a random count when esi is -1 and return the target in eax
    .globl deal_round
deal_round:
    push rbx
    push r12
    push r13
    push r14
    push r15
    # Keep the twenty small cards at rsp and the four large ones at rsp + 80 so nothing outlives the call
    sub rsp, 96
    mov r13d, edi
    mov r12d, esi
    mov r14, rdx
    mov edi, 900
    call rand_below
    lea r15d, [rax + 100]
    cmp r12d, -1
    jne 2f
    test r13d, r13d
    jnz 1f
    mov edi, 2
    call rand_below
    lea r12d, [rax + 1]
    jmp 2f
1:  mov edi, 5
    call rand_below
    mov r12d, eax

    # Hold two cards of each small number to match the game's deck
2:  xor ecx, ecx
3:  mov eax, ecx
    xor edx, edx
    mov r8d, 10
    div r8d
    inc edx
    mov dword ptr [rsp + rcx * 4], edx
    inc ecx
    cmp ecx, 20
    jb 3b
    mov rdi, rsp
    mov esi, 20
    call shuffle
    # Shuffle a copy since each large number appears only once in the game
    lea rsi, [rip + large_decks]
    mov eax, r13d
    shl eax, 4
    movdqu xmm0, xmmword ptr [rsi + rax]
    movdqu xmmword ptr [rsp + 80], xmm0
    lea rdi, [rsp + 80]
    mov esi, 4
    call shuffle

    mov rdi, r14
    mov rsi, rsp
    mov ecx, 6
    sub ecx, r12d
    rep movsd
    lea rsi, [rsp + 80]
    mov ecx, r12d
    rep movsd
    mov eax, r15d
    add rsp, 96
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Read edi arguments at rsi into the mode at rdx and fixed count at rcx (-1 for random) and return 0 in eax or -1 when they are invalid
    .globl parse_args
parse_args:
    push rbx
    push r12
    push r13
    push r14
    push r15
    mov ebx, edi
    mov r12, rsi
    mov r13, rdx
    mov r14, rcx
    mov dword ptr [r13], 0
    mov dword ptr [r14], -1
    cmp ebx, 2
    ja 9f
    test ebx, ebx
    jz 8f
    xor r15d, r15d
    mov rdi, qword ptr [r12]
    lea rsi, [rip + s_standard]
    call str_eq
    test eax, eax
    jnz 1f
    inc r15d
    mov rdi, qword ptr [r12]
    lea rsi, [rip + s_cats]
    call str_eq
    test eax, eax
    jnz 1f
    inc r15d
    mov rdi, qword ptr [r12]
    lea rsi, [rip + s_nasty]
    call str_eq
    test eax, eax
    jz 9f
1:  mov dword ptr [r13], r15d
    cmp ebx, 1
    je 8f
    # Accept only a single digit so that signs, spaces and trailing text are rejected
    mov rsi, qword ptr [r12 + 8]
    movzx eax, byte ptr [rsi]
    sub eax, '0'
    cmp eax, 9
    ja 9f
    cmp byte ptr [rsi + 1], 0
    jne 9f
    test r15d, r15d
    jnz 2f
    # Allow only one or two large numbers in standard mode
    lea ecx, [rax - 1]
    cmp ecx, 1
    ja 9f
    jmp 3f
2:  cmp eax, 4
    ja 9f
3:  mov dword ptr [r14], eax
8:  xor eax, eax
    jmp 0f
9:  mov eax, -1
0:  pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

    .section .note.GNU-stack, "", @progbits
