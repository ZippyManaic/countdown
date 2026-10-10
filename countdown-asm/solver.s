# Solve a Countdown numbers round using the same algorithm and tie-breaks as the Rust version
#
# unsigned solve(unsigned target, const unsigned *pool, unsigned n, char *out)
#
# Each subset of the pool is a bitmask whose reachable values are kept sorted in one arena
# Each 16-byte entry holds value, operator (0 for a pool number), the operands' subset masks, larger operand and smaller operand

    .intel_syntax noprefix

    .set ARENA_CAP, 1 << 23
    .set TMP_CAP, 1 << 22
    .set INSERTION_MAX, 48
    .set RANK_MIN, 16

    .set E_VALUE, 0
    .set E_OP, 4
    .set E_LMASK, 5
    .set E_SMASK, 6
    .set E_LARGER, 8
    .set E_SMALLER, 12

    # Place the operator and mask templates for each half of a split after the right half's bounds on the stack
    .set T_LEFT_LARGER, 16
    .set T_RIGHT_LARGER, 48
    .set T_ADD, 0
    .set T_SUB, 8
    .set T_MUL, 16
    .set T_DIV, 24

    .set OP_ADD, 43
    .set OP_SUB, 45
    .set OP_MUL, 42
    .set OP_DIV, 47

    .bss
    .balign 64
arena:      .space 16 * ARENA_CAP
tmp:        .space 16 * TMP_CAP
# Hold one bit per value which covers the largest product any dealt pool can reach
seen:       .space 1 << 24
hist:       .space 4 * 1024
# Hold the count of values below each bitset word for ranking
rank:       .space 4 * (1 << 21)
mask_off:   .space 4 * 64
mask_len:   .space 4 * 64
g_res:      .space 16
g_whole:    .space 16
g_pval:     .space 4 * 8
g_pop:      .space 8
g_target:   .space 4
g_n:        .space 4
g_full:     .space 4
g_top:      .space 4
g_wd:       .space 4
    .balign 8
g_pool:     .space 8
g_out:      .space 8

    .section .rodata
    .balign 8
one:        .double 1.0

    .text

# Load the arena pointer and value count for the subset in \mask into \base and \len
.macro RANGE mask, base, len32, len64, scratch
    lea \scratch, [rip + mask_off]
    mov \len32, dword ptr [\scratch + \mask * 4]
    lea \base, [rip + arena]
    shl \len64, 4
    add \base, \len64
    lea \scratch, [rip + mask_len]
    mov \len32, dword ptr [\scratch + \mask * 4]
.endm

# Append the value in eax to the arena at rdi advancing past it only if the bitset at rsi shows it is new
.macro EMIT slot
    mov ecx, eax
    shr ecx, 6
    mov rdx, qword ptr [rsi + rcx * 8]
    bts rdx, rax
    mov qword ptr [rsi + rcx * 8], rdx
    # Turn the old bit into an advance of 0 or 16 so duplicates cost no mispredicted branch
    sbb r11, r11
    mov rdx, qword ptr [rsp + \slot]
    or rdx, rax
    mov qword ptr [rdi], rdx
    mov qword ptr [rdi + 8], r10
    and r11, -16
    lea rdi, [rdi + r11 + 16]
.endm

# Keep the value in eax as the whole pool's best if it is closer to the target or equally close and lower
.macro CHECK slot
    test eax, eax
    jz 9f
    mov ecx, eax
    sub ecx, dword ptr [rip + g_target]
    jae 7f
    neg ecx
7:  cmp ecx, dword ptr [rip + g_wd]
    ja 9f
    jb 8f
    cmp eax, dword ptr [rip + g_whole]
    jae 9f
8:  mov dword ptr [rip + g_wd], ecx
    mov rdx, qword ptr [rsp + \slot]
    or rdx, rax
    mov qword ptr [rip + g_whole], rdx
    mov qword ptr [rip + g_whole + 8], r10
9:
.endm

# Store the four operator templates for the masks in ecx shifted into the entry's upper half at \base
.macro TEMPLATES base
    lea eax, [rcx + OP_ADD]
    shl rax, 32
    mov qword ptr [rsp + \base + T_ADD], rax
    lea eax, [rcx + OP_SUB]
    shl rax, 32
    mov qword ptr [rsp + \base + T_SUB], rax
    lea eax, [rcx + OP_MUL]
    shl rax, 32
    mov qword ptr [rsp + \base + T_MUL], rax
    lea eax, [rcx + OP_DIV]
    shl rax, 32
    mov qword ptr [rsp + \base + T_DIV], rax
.endm

# Emit every legal result of x in r8d and y in r9d where x is at least y using reciprocal \inv of y to test division
.macro OPS emit, inv, part
    # Pack both operands once per pair for the entry's second half
    mov r10, r9
    shl r10, 32
    or r10, r8
    lea eax, [r8 + r9]
    \emit \part+T_ADD
    # Skip a zero result since every intermediate value must be a positive integer
    cmp r8d, r9d
    je 3f
    mov eax, r8d
    sub eax, r9d
    \emit \part+T_SUB
    # Skip multiplying and dividing by one as they never produce a new value
3:  cmp r9d, 1
    je 4f
    mov eax, r8d
    imul eax, r9d
    \emit \part+T_MUL
    # Round x times 1/y and multiply back which is exact for values below 2^27 and avoids a slow div
    cvtsi2sd xmm0, r8d
    mulsd xmm0, \inv
    cvtsd2si eax, xmm0
    mov ecx, eax
    imul ecx, r9d
    # Emit zero for an inexact division since bit 0 stays set so it is dropped without a branch
    xor edx, edx
    cmp ecx, r8d
    cmovne eax, edx
    \emit \part+T_DIV
4:
.endm

# Pass every legal combination of each left value in ebx with each right value in r13d to \emit
.macro PAIRS emit
    # Build each half's operator and mask templates once per split
    mov ecx, ebx
    shl ecx, 8
    mov edx, r13d
    shl edx, 16
    or ecx, edx
    TEMPLATES T_LEFT_LARGER
    mov ecx, r13d
    shl ecx, 8
    mov edx, ebx
    shl edx, 16
    or ecx, edx
    TEMPLATES T_RIGHT_LARGER
    RANGE rbx, r14, ecx, rcx, rax
    shl rcx, 4
    lea r15, [r14 + rcx]
    # Copy the right values next to their reciprocals so each divisor is inverted once per split
    RANGE r13, rax, ecx, rcx, rdx
    lea rdx, [rip + tmp]
    mov qword ptr [rsp], rdx
    movsd xmm2, qword ptr [rip + one]
.Lpr\@:
    test ecx, ecx
    jz .Lprd\@
    mov r8d, dword ptr [rax]
    mov dword ptr [rdx], r8d
    cvtsi2sd xmm0, r8d
    movapd xmm1, xmm2
    divsd xmm1, xmm0
    movsd qword ptr [rdx + 8], xmm1
    add rax, 16
    add rdx, 16
    dec ecx
    jmp .Lpr\@
.Lprd\@:
    mov qword ptr [rsp + 8], rdx
.Lpa\@:
    cmp r14, r15
    jae .Lpend\@
    mov rbp, qword ptr [rsp]
    mov r8d, dword ptr [r14]
    # Pair with right values up to a first where a is the larger and ties go to the left as combine does
.Lp1\@:
    cmp rbp, qword ptr [rsp + 8]
    jae .Lpan\@
    mov r9d, dword ptr [rbp]
    cmp r9d, r8d
    ja .Lp2s\@
    movsd xmm1, qword ptr [rbp + 8]
    OPS \emit, xmm1, T_LEFT_LARGER
    add rbp, 16
    jmp .Lp1\@
    # Pair with the remaining larger right values where a is the smaller so its reciprocal is fixed
.Lp2s\@:
    mov r9d, r8d
    cvtsi2sd xmm0, r9d
    movapd xmm3, xmm2
    divsd xmm3, xmm0
.Lp2\@:
    cmp rbp, qword ptr [rsp + 8]
    jae .Lpan\@
    mov r8d, dword ptr [rbp]
    OPS \emit, xmm3, T_RIGHT_LARGER
    add rbp, 16
    jmp .Lp2\@
.Lpan\@:
    add r14, 16
    jmp .Lpa\@
.Lpend\@:
.endm

# Return in rax a pointer to the entry with value edx among esi sorted entries at rdi or zero if absent
lookup:
    test esi, esi
    jz 3f
    # Halve the range with a conditional move so unpredictable comparisons cost no mispredicted branches
1:  cmp esi, 1
    jbe 2f
    mov ecx, esi
    shr ecx, 1
    mov r8d, ecx
    shl r8, 4
    lea r9, [rdi + r8]
    cmp dword ptr [r9], edx
    cmovbe rdi, r9
    sub esi, ecx
    jmp 1b
2:  cmp dword ptr [rdi], edx
    jne 3f
    mov rax, rdi
    ret
3:  xor eax, eax
    ret

# Fill g_pval and g_pop with every number that combines with edi to make esi and return the count in eax
gen_partners:
    xor r8d, r8d
    lea r9, [rip + g_pval]
    lea r10, [rip + g_pop]
    cmp esi, edi
    jbe 1f
    mov eax, esi
    sub eax, edi
    mov dword ptr [r9 + r8 * 4], eax
    mov byte ptr [r10 + r8], OP_ADD
    inc r8d
1:  cmp edi, esi
    jbe 1f
    mov eax, edi
    sub eax, esi
    mov dword ptr [r9 + r8 * 4], eax
    mov byte ptr [r10 + r8], OP_SUB
    inc r8d
1:  lea eax, [rdi + rsi]
    mov dword ptr [r9 + r8 * 4], eax
    mov byte ptr [r10 + r8], OP_SUB
    inc r8d
    mov eax, esi
    xor edx, edx
    div edi
    test edx, edx
    jnz 1f
    cmp edi, 1
    je 1f
    cmp eax, 1
    je 1f
    mov dword ptr [r9 + r8 * 4], eax
    mov byte ptr [r10 + r8], OP_MUL
    inc r8d
1:  mov eax, edi
    xor edx, edx
    div esi
    test edx, edx
    jnz 1f
    cmp eax, 1
    je 1f
    mov dword ptr [r9 + r8 * 4], eax
    mov byte ptr [r10 + r8], OP_DIV
    inc r8d
1:  cmp edi, 1
    je 1f
    mov eax, edi
    mul esi
    test edx, edx
    jnz 1f
    mov dword ptr [r9 + r8 * 4], eax
    mov byte ptr [r10 + r8], OP_DIV
    inc r8d
1:  mov eax, r8d
    ret

# Return 1 in eax and fill g_res if the target can be made from subset edi without building its values
find_exact:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 72
    # Keep left and right bases at 0 and 8, lengths at 16 and 20, best at 24, its partner at 28, operator at 32
    mov r12d, edi
    lea ebx, [rdi - 1]
    and ebx, edi
.Lfe_split:
    test ebx, ebx
    jz .Lfe_none
    mov r13d, r12d
    xor r13d, ebx
    # Visit splits in the same order as building so the same origin wins
    cmp ebx, r13d
    jae .Lfe_next
    RANGE rbx, rax, ecx, rcx, rdx
    mov qword ptr [rsp], rax
    mov dword ptr [rsp + 16], ecx
    RANGE r13, rax, ecx, rcx, rdx
    mov qword ptr [rsp + 8], rax
    mov dword ptr [rsp + 20], ecx
    cmp dword ptr [rsp + 16], ecx
    ja .Lfe_right_small

    # Take the first left value with any partner on the right and keep its smallest partner
    mov r14, qword ptr [rsp]
    mov r15d, dword ptr [rsp + 16]
.Lfe_l_loop:
    test r15d, r15d
    jz .Lfe_next
    mov edi, dword ptr [r14]
    mov dword ptr [rsp + 36], edi
    mov esi, dword ptr [rip + g_target]
    call gen_partners
    mov dword ptr [rsp + 40], eax
    mov dword ptr [rsp + 24], -1
    xor ebp, ebp
.Lfe_l_p:
    cmp ebp, dword ptr [rsp + 40]
    jae .Lfe_l_pdone
    lea rax, [rip + g_pval]
    mov edx, dword ptr [rax + rbp * 4]
    cmp edx, dword ptr [rsp + 24]
    jae .Lfe_l_pnext
    mov dword ptr [rsp + 44], edx
    mov rdi, qword ptr [rsp + 8]
    mov esi, dword ptr [rsp + 20]
    call lookup
    test rax, rax
    jz .Lfe_l_pnext
    mov edx, dword ptr [rsp + 44]
    mov dword ptr [rsp + 24], edx
    lea rax, [rip + g_pop]
    movzx eax, byte ptr [rax + rbp]
    mov byte ptr [rsp + 32], al
.Lfe_l_pnext:
    inc ebp
    jmp .Lfe_l_p
.Lfe_l_pdone:
    cmp dword ptr [rsp + 24], -1
    jne .Lfe_l_found
    add r14, 16
    dec r15d
    jmp .Lfe_l_loop
.Lfe_l_found:
    mov edi, dword ptr [rsp + 36]
    mov esi, dword ptr [rsp + 24]
    jmp .Lfe_emit

    # Loop over the smaller right half and keep the smallest left value any of its partners match
.Lfe_right_small:
    mov dword ptr [rsp + 24], -1
    mov r14, qword ptr [rsp + 8]
    mov r15d, dword ptr [rsp + 20]
.Lfe_r_loop:
    test r15d, r15d
    jz .Lfe_r_done
    mov edi, dword ptr [r14]
    mov dword ptr [rsp + 36], edi
    mov esi, dword ptr [rip + g_target]
    call gen_partners
    mov dword ptr [rsp + 40], eax
    xor ebp, ebp
.Lfe_r_p:
    cmp ebp, dword ptr [rsp + 40]
    jae .Lfe_r_pdone
    lea rax, [rip + g_pval]
    mov edx, dword ptr [rax + rbp * 4]
    cmp edx, dword ptr [rsp + 24]
    jae .Lfe_r_pnext
    mov dword ptr [rsp + 44], edx
    mov rdi, qword ptr [rsp]
    mov esi, dword ptr [rsp + 16]
    call lookup
    test rax, rax
    jz .Lfe_r_pnext
    mov edx, dword ptr [rsp + 44]
    mov dword ptr [rsp + 24], edx
    mov edx, dword ptr [rsp + 36]
    mov dword ptr [rsp + 28], edx
    lea rax, [rip + g_pop]
    movzx eax, byte ptr [rax + rbp]
    mov byte ptr [rsp + 32], al
.Lfe_r_pnext:
    inc ebp
    jmp .Lfe_r_p
.Lfe_r_pdone:
    add r14, 16
    dec r15d
    jmp .Lfe_r_loop
.Lfe_r_done:
    cmp dword ptr [rsp + 24], -1
    je .Lfe_next
    mov edi, dword ptr [rsp + 24]
    mov esi, dword ptr [rsp + 28]

    # Record the match with edi from the left half and esi from the right putting the larger first
.Lfe_emit:
    lea rax, [rip + g_res]
    mov edx, dword ptr [rip + g_target]
    mov dword ptr [rax + E_VALUE], edx
    movzx edx, byte ptr [rsp + 32]
    mov byte ptr [rax + E_OP], dl
    cmp edi, esi
    jb 1f
    mov dword ptr [rax + E_LARGER], edi
    mov dword ptr [rax + E_SMALLER], esi
    mov byte ptr [rax + E_LMASK], bl
    mov byte ptr [rax + E_SMASK], r13b
    jmp 2f
1:  mov dword ptr [rax + E_LARGER], esi
    mov dword ptr [rax + E_SMALLER], edi
    mov byte ptr [rax + E_LMASK], r13b
    mov byte ptr [rax + E_SMASK], bl
2:  mov eax, 1
    jmp .Lfe_ret
.Lfe_next:
    lea ebx, [rbx - 1]
    and ebx, r12d
    jmp .Lfe_split
.Lfe_none:
    xor eax, eax
.Lfe_ret:
    add rsp, 72
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

# Sort esi entries at rdi by value using insertion sort for short runs and radix sort otherwise
sort_entries:
    cmp esi, 1
    jbe 9f
    cmp esi, INSERTION_MAX
    jae radix_sort
    mov ecx, 1
1:  cmp ecx, esi
    jae 9f
    mov eax, ecx
    shl rax, 4
    lea r8, [rdi + rax]
    movdqu xmm0, xmmword ptr [r8]
    movd edx, xmm0
2:  cmp r8, rdi
    jbe 3f
    cmp dword ptr [r8 - 16], edx
    jbe 3f
    movdqu xmm1, xmmword ptr [r8 - 16]
    movdqu xmmword ptr [r8], xmm1
    sub r8, 16
    jmp 2b
3:  movdqu xmmword ptr [r8], xmm0
    inc ecx
    jmp 1b
9:  ret

# Sort by bytes counting every digit in one pass and skipping any digit shared by all values
radix_sort:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    mov r12, rdi
    mov rbp, rdi
    mov r13d, esi
    lea r14, [rip + tmp]
    lea r11, [rip + hist]
    mov rdi, r11
    xor eax, eax
    mov ecx, 1024
    rep stosd
    mov rax, r12
    mov r8d, r13d
1:  mov edx, dword ptr [rax]
    movzx ecx, dl
    inc dword ptr [r11 + rcx * 4]
    movzx ecx, dh
    inc dword ptr [r11 + rcx * 4 + 1024]
    shr edx, 16
    movzx ecx, dl
    inc dword ptr [r11 + rcx * 4 + 2048]
    movzx ecx, dh
    inc dword ptr [r11 + rcx * 4 + 3072]
    add rax, 16
    dec r8d
    jnz 1b
    xor ebx, ebx
.Lr_pass:
    # Skip this digit when one bucket holds every value
    mov eax, dword ptr [r12]
    mov ecx, ebx
    shl ecx, 3
    shr eax, cl
    movzx eax, al
    mov r15, rbx
    shl r15, 10
    add r15, r11
    cmp dword ptr [r15 + rax * 4], r13d
    je .Lr_next
    xor eax, eax
    xor r8d, r8d
2:  mov edx, dword ptr [r15 + r8 * 4]
    mov dword ptr [r15 + r8 * 4], eax
    add eax, edx
    inc r8d
    cmp r8d, 256
    jb 2b
    mov rax, r12
    mov r8d, r13d
3:  movdqu xmm0, xmmword ptr [rax]
    movd edx, xmm0
    shr edx, cl
    movzx edx, dl
    mov r9d, dword ptr [r15 + rdx * 4]
    lea r10d, [r9 + 1]
    mov dword ptr [r15 + rdx * 4], r10d
    shl r9, 4
    movdqu xmmword ptr [r14 + r9], xmm0
    add rax, 16
    dec r8d
    jnz 3b
    xchg r12, r14
.Lr_next:
    inc ebx
    cmp ebx, 4
    jb .Lr_pass
    # Copy back when an odd number of passes left the result in the temporary buffer
    cmp r12, rbp
    je 6f
    mov rsi, r12
    mov rdi, rbp
    mov ecx, r13d
    shl rcx, 4
    rep movsb
6:  pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

# Build the sorted reachable values of subset edi keeping only the first way found to make each
build:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 104
    mov r12d, edi
    mov eax, dword ptr [rip + g_top]
    shl rax, 4
    lea rdi, [rip + arena]
    add rdi, rax
    mov qword ptr [rsp + 80], rdi
    mov dword ptr [rsp + 88], 0
    lea rsi, [rip + seen]
    # Mark zero as seen so sentinel results never become entries
    or qword ptr [rsi], 1
    lea ebx, [r12 - 1]
    and ebx, r12d
.Lb_split:
    test ebx, ebx
    jz .Lb_done
    mov r13d, r12d
    xor r13d, ebx
    # Visit each split once rather than once per ordering
    cmp ebx, r13d
    jae .Lb_next
    # Raise the largest value to this split's sum or product of its two largest values
    RANGE rbx, rax, ecx, rcx, rdx
    shl rcx, 4
    mov r8d, dword ptr [rax + rcx - 16]
    RANGE r13, rax, ecx, rcx, rdx
    shl rcx, 4
    mov r9d, dword ptr [rax + rcx - 16]
    lea eax, [r8 + r9]
    imul r8d, r9d
    cmp r8d, eax
    cmova eax, r8d
    cmp eax, dword ptr [rsp + 88]
    jbe 1f
    mov dword ptr [rsp + 88], eax
1:  PAIRS EMIT
.Lb_next:
    lea ebx, [rbx - 1]
    and ebx, r12d
    jmp .Lb_split
.Lb_done:
    and qword ptr [rsi], -2
    mov r15, rdi
    sub r15, qword ptr [rsp + 80]
    shr r15, 4
    cmp r15d, RANK_MIN
    jae .Lb_rank
    # Clear only the words this subset touched so the bitset is ready for the next one
    mov rax, qword ptr [rsp + 80]
1:  cmp rax, rdi
    jae 2f
    mov edx, dword ptr [rax]
    shr edx, 6
    mov qword ptr [rsi + rdx * 8], 0
    add rax, 16
    jmp 1b
2:  mov rdi, qword ptr [rsp + 80]
    mov esi, r15d
    call sort_entries
    jmp .Lb_record

    # Sort by rank in the bitset since its words up to the largest value number fewer than the values
.Lb_rank:
    mov ecx, dword ptr [rsp + 88]
    shr ecx, 6
    mov r14d, ecx
    # Record how many values lie below each word
    lea r8, [rip + rank]
    xor edx, edx
    xor eax, eax
2:  mov dword ptr [r8 + rax * 4], edx
    popcnt r9, qword ptr [rsi + rax * 8]
    add edx, r9d
    inc eax
    cmp eax, r14d
    jbe 2b
    # Place each entry at its word's rank plus the set bits below it in that word
    lea r9, [rip + tmp]
    mov rax, qword ptr [rsp + 80]
3:  movdqu xmm0, xmmword ptr [rax]
    movd edx, xmm0
    mov ecx, edx
    and ecx, 63
    shr edx, 6
    mov r10, qword ptr [rsi + rdx * 8]
    bzhi r10, r10, rcx
    popcnt r10, r10
    add r10d, dword ptr [r8 + rdx * 4]
    shl r10, 4
    movdqu xmmword ptr [r9 + r10], xmm0
    add rax, 16
    cmp rax, rdi
    jb 3b
    mov rdi, rsi
    lea ecx, [r14 + 1]
    xor eax, eax
    rep stosq
    lea rsi, [rip + tmp]
    mov rdi, qword ptr [rsp + 80]
    mov rcx, r15
    shl rcx, 4
    rep movsb
.Lb_record:
    mov edx, dword ptr [rip + g_top]
    lea rax, [rip + mask_off]
    mov dword ptr [rax + r12 * 4], edx
    lea rax, [rip + mask_len]
    mov dword ptr [rax + r12 * 4], r15d
    add edx, r15d
    mov dword ptr [rip + g_top], edx
    add rsp, 104
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

# Find the whole pool's closest value into g_whole and g_wd checking results as they are made
whole_scan:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 88
    mov dword ptr [rip + g_wd], -1
    lea rax, [rip + g_whole]
    mov dword ptr [rax + E_VALUE], -1
    mov r12d, dword ptr [rip + g_full]
    lea ebx, [r12 - 1]
    and ebx, r12d
.Lw_split:
    test ebx, ebx
    jz .Lw_done
    mov r13d, r12d
    xor r13d, ebx
    cmp ebx, r13d
    jae .Lw_next
    PAIRS CHECK
.Lw_next:
    lea ebx, [rbx - 1]
    and ebx, r12d
    jmp .Lw_split
.Lw_done:
    add rsp, 88
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

# Return in rax the closest stored entry ranked by distance then numbers used and its distance in edx
partial_min:
    push rbx
    push r12
    push r13
    push r14
    push r15
    xor r12, r12
    mov r13d, -1
    mov r14d, 99
    mov ebx, 1
.Lp_mask:
    cmp ebx, dword ptr [rip + g_full]
    ja .Lp_done
    RANGE rbx, rax, ecx, rcx, rdx
    test ecx, ecx
    jz .Lp_next
    popcnt r15d, ebx
.Lp_e:
    mov r8d, dword ptr [rax]
    sub r8d, dword ptr [rip + g_target]
    jae 1f
    neg r8d
1:  cmp r8d, r13d
    jb 2f
    ja 3f
    cmp r15d, r14d
    jae 3f
2:  mov r12, rax
    mov r13d, r8d
    mov r14d, r15d
3:  add rax, 16
    dec ecx
    jnz .Lp_e
.Lp_next:
    inc ebx
    jmp .Lp_mask
.Lp_done:
    mov rax, r12
    mov edx, r13d
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    ret

# Write edi in decimal at rsi and return the end pointer in rax
    .globl fmt_uint
fmt_uint:
    mov eax, edi
    lea r8, [rsp - 16]
    mov r9, r8
    mov ecx, 10
1:  xor edx, edx
    div ecx
    add dl, '0'
    dec r8
    mov byte ptr [r8], dl
    test eax, eax
    jnz 1b
2:  cmp r8, r9
    jae 3f
    mov al, byte ptr [r8]
    mov byte ptr [rsi], al
    inc r8
    inc rsi
    jmp 2b
3:  mov rax, rsi
    ret

# Write the expression for entry rdi at rsi wrapping it in brackets when edx is set and return the end in rax
render:
    push rbx
    push r12
    push r13
    mov rbx, rdi
    mov r12, rsi
    mov r13d, edx
    cmp byte ptr [rbx + E_OP], 0
    jne 1f
    mov edi, dword ptr [rbx + E_VALUE]
    mov rsi, r12
    call fmt_uint
    jmp 9f
1:  test r13d, r13d
    jz 2f
    mov byte ptr [r12], '('
    inc r12
2:  movzx ecx, byte ptr [rbx + E_LMASK]
    RANGE rcx, rdi, esi, rsi, rax
    mov edx, dword ptr [rbx + E_LARGER]
    call lookup
    mov rdi, rax
    mov rsi, r12
    mov edx, 1
    call render
    mov r12, rax
    mov byte ptr [r12], ' '
    mov al, byte ptr [rbx + E_OP]
    mov byte ptr [r12 + 1], al
    mov byte ptr [r12 + 2], ' '
    add r12, 3
    movzx ecx, byte ptr [rbx + E_SMASK]
    RANGE rcx, rdi, esi, rsi, rax
    mov edx, dword ptr [rbx + E_SMALLER]
    call lookup
    mov rdi, rax
    mov rsi, r12
    mov edx, 1
    call render
    mov r12, rax
    test r13d, r13d
    jz 3f
    mov byte ptr [r12], ')'
    inc r12
3:  mov rax, r12
9:  pop r13
    pop r12
    pop rbx
    ret

    .globl solve
solve:
    push rbx
    push rbp
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov dword ptr [rip + g_target], edi
    mov qword ptr [rip + g_pool], rsi
    mov dword ptr [rip + g_n], edx
    mov qword ptr [rip + g_out], rcx
    mov ecx, edx
    mov eax, 1
    shl eax, cl
    dec eax
    mov dword ptr [rip + g_full], eax
    mov dword ptr [rip + g_top], 0
    # Forget subsets from the previous call so unbuilt ones read as empty
    lea rdi, [rip + mask_len]
    xor eax, eax
    mov ecx, 64
    rep stosd

    # Store each pool number as a one-number subset
    xor ebx, ebx
.Ls_leaf:
    cmp ebx, dword ptr [rip + g_n]
    jae .Ls_leafdone
    mov rsi, qword ptr [rip + g_pool]
    mov eax, dword ptr [rsi + rbx * 4]
    mov edx, dword ptr [rip + g_top]
    mov ecx, edx
    shl rcx, 4
    lea rdi, [rip + arena]
    add rdi, rcx
    mov dword ptr [rdi + E_VALUE], eax
    mov byte ptr [rdi + E_OP], 0
    mov ecx, ebx
    mov r8d, 1
    shl r8d, cl
    lea rcx, [rip + mask_off]
    mov dword ptr [rcx + r8 * 4], edx
    lea rcx, [rip + mask_len]
    mov dword ptr [rcx + r8 * 4], 1
    inc edx
    mov dword ptr [rip + g_top], edx
    inc ebx
    jmp .Ls_leaf
.Ls_leafdone:
    xor ebx, ebx
.Ls_lx:
    cmp ebx, dword ptr [rip + g_n]
    jae .Ls_sizes
    mov ecx, ebx
    mov r8d, 1
    shl r8d, cl
    RANGE r8, rax, ecx, rcx, rdx
    mov ecx, dword ptr [rax]
    cmp ecx, dword ptr [rip + g_target]
    jne 1f
    mov r12, rax
    jmp .Ls_render
1:  inc ebx
    jmp .Ls_lx

    # Work through subsets smallest first stopping at the first size that hits the target
.Ls_sizes:
    mov r13d, 2
.Ls_size:
    cmp r13d, dword ptr [rip + g_n]
    ja .Ls_unsolved
    mov ebx, 1
.Ls_fe:
    cmp ebx, dword ptr [rip + g_full]
    ja .Ls_fedone
    popcnt eax, ebx
    cmp eax, r13d
    jne 1f
    mov edi, ebx
    call find_exact
    test eax, eax
    jz 1f
    lea r12, [rip + g_res]
    jmp .Ls_render
1:  inc ebx
    jmp .Ls_fe
.Ls_fedone:
    # Skip building the whole pool's values since no larger subset is made from them
    cmp r13d, dword ptr [rip + g_n]
    je .Ls_unsolved
    mov ebx, 1
.Ls_b:
    cmp ebx, dword ptr [rip + g_full]
    ja .Ls_bdone
    popcnt eax, ebx
    cmp eax, r13d
    jne 1f
    mov edi, ebx
    call build
1:  inc ebx
    jmp .Ls_b
.Ls_bdone:
    inc r13d
    jmp .Ls_size

    # Fall back to the whole pool only when it gets strictly closer as it uses the most numbers
.Ls_unsolved:
    call partial_min
    mov r12, rax
    mov r14d, edx
    cmp dword ptr [rip + g_n], 1
    jbe .Ls_render
    call whole_scan
    mov eax, dword ptr [rip + g_wd]
    cmp eax, r14d
    jae .Ls_render
    lea r12, [rip + g_whole]

    # Render without outer brackets which matches stripping them from the bracketed form
.Ls_render:
    mov rdi, r12
    mov rsi, qword ptr [rip + g_out]
    xor edx, edx
    call render
    mov byte ptr [rax], 0
    mov eax, dword ptr [r12 + E_VALUE]
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbp
    pop rbx
    ret

    .section .note.GNU-stack, "", @progbits
