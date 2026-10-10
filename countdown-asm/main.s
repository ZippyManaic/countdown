# Generate a Countdown numbers round and work out whether it can be solved without the C library

    .intel_syntax noprefix

    .set SYS_WRITE, 1
    .set SYS_EXIT_GROUP, 231
    .set SYS_GETRANDOM, 318
    .set RANDOM_WORDS, 32

    .section .rodata
s_target:   .asciz "Target: "
s_pool:     .asciz "\nPool:   "
s_solved:   .asciz "Solved: "
s_closest:  .asciz "No exact solution, closest is "
s_equals:   .asciz " = "
s_open:     .asciz " ("
s_away:     .asciz " away)"
large_deck: .long 25, 50, 75, 100

    .bss
    .balign 8
random:     .space 8 * RANDOM_WORDS
rand_next:  .space 4
target:     .space 4
small:      .space 4 * 20
large:      .space 4 * 4
pool:       .space 4 * 6
expr:       .space 256
out:        .space 1024

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

# Copy the zero-terminated string at rsi to rdi and return the end in rax
put_str:
1:  mov al, byte ptr [rsi]
    test al, al
    jz 2f
    mov byte ptr [rdi], al
    inc rsi
    inc rdi
    jmp 1b
2:  mov rax, rdi
    ret

    .globl _start
_start:
    mov edi, 900
    call rand_below
    add eax, 100
    mov dword ptr [rip + target], eax
    mov edi, 2
    call rand_below
    lea r12d, [rax + 1]

    # Hold two cards of each small number to match the game's deck
    lea rdi, [rip + small]
    xor ecx, ecx
1:  mov eax, ecx
    xor edx, edx
    mov r8d, 10
    div r8d
    inc edx
    mov dword ptr [rdi + rcx * 4], edx
    inc ecx
    cmp ecx, 20
    jb 1b
    mov esi, 20
    call shuffle
    # Shuffle a copy since each large number appears only once in the game
    lea rsi, [rip + large_deck]
    lea rdi, [rip + large]
    movdqu xmm0, xmmword ptr [rsi]
    movdqu xmmword ptr [rdi], xmm0
    mov esi, 4
    call shuffle

    lea rdi, [rip + pool]
    lea rsi, [rip + small]
    mov ecx, 6
    sub ecx, r12d
    rep movsd
    lea rsi, [rip + large]
    mov ecx, r12d
    rep movsd

    lea rdi, [rip + out]
    lea rsi, [rip + s_target]
    call put_str
    mov rsi, rax
    mov edi, dword ptr [rip + target]
    call fmt_uint
    mov rdi, rax
    lea rsi, [rip + s_pool]
    call put_str
    xor ebx, ebx
    lea r13, [rip + pool]
2:  mov rsi, rax
    mov edi, dword ptr [r13 + rbx * 4]
    call fmt_uint
    inc ebx
    cmp ebx, 6
    je 3f
    mov byte ptr [rax], ' '
    inc rax
    jmp 2b
3:  mov byte ptr [rax], 10
    inc rax
    mov r14, rax

    mov edi, dword ptr [rip + target]
    lea rsi, [rip + pool]
    mov edx, 6
    lea rcx, [rip + expr]
    call solve
    mov r15d, eax

    mov rdi, r14
    lea rsi, [rip + s_solved]
    cmp r15d, dword ptr [rip + target]
    je 4f
    lea rsi, [rip + s_closest]
4:  call put_str
    mov rdi, rax
    lea rsi, [rip + expr]
    call put_str
    mov rdi, rax
    lea rsi, [rip + s_equals]
    call put_str
    mov rsi, rax
    mov edi, r15d
    call fmt_uint
    xor ebx, ebx
    cmp r15d, dword ptr [rip + target]
    je 6f
    mov rdi, rax
    lea rsi, [rip + s_open]
    call put_str
    mov rsi, rax
    mov edi, r15d
    sub edi, dword ptr [rip + target]
    jae 5f
    neg edi
5:  call fmt_uint
    mov rdi, rax
    lea rsi, [rip + s_away]
    call put_str
    mov ebx, 1
6:  mov byte ptr [rax], 10
    inc rax

    lea rsi, [rip + out]
    mov rdx, rax
    sub rdx, rsi
    mov edi, 1
    mov eax, SYS_WRITE
    syscall
    mov edi, ebx
    mov eax, SYS_EXIT_GROUP
    syscall

    .section .note.GNU-stack, "", @progbits
