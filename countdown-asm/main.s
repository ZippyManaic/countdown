# Generate a Countdown numbers round and work out whether it can be solved without the C library

    .intel_syntax noprefix

    .set SYS_WRITE, 1
    .set SYS_EXIT_GROUP, 231

    .section .rodata
s_target:   .asciz "Target: "
s_pool:     .asciz "\nPool:   "
s_solved:   .asciz "Solved: "
s_closest:  .asciz "No exact solution, closest is "
s_equals:   .asciz " = "
s_open:     .asciz " ("
s_away:     .asciz " away)"
s_usage:    .ascii "usage: countdown [standard|cats|nasty] [LARGE]\n"
    .set USAGE_LENGTH, . - s_usage

    .bss
    .balign 8
target:     .space 4
pool:       .space 4 * 6
expr:       .space 256
out:        .space 1024

    .text

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
    # Read the mode and count into the stack from the arguments after the program name
    mov edi, dword ptr [rsp]
    dec edi
    lea rsi, [rsp + 16]
    sub rsp, 16
    mov rdx, rsp
    lea rcx, [rsp + 4]
    call parse_args
    test eax, eax
    jnz usage
    mov edi, dword ptr [rsp]
    mov esi, dword ptr [rsp + 4]
    lea rdx, [rip + pool]
    call deal_round
    mov dword ptr [rip + target], eax

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

# Print the usage line to stderr and exit with code 2
usage:
    mov edi, 2
    lea rsi, [rip + s_usage]
    mov edx, USAGE_LENGTH
    mov eax, SYS_WRITE
    syscall
    mov edi, 2
    mov eax, SYS_EXIT_GROUP
    syscall

    .section .note.GNU-stack, "", @progbits
