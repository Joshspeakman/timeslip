/*
 * TimeSplitters: Future Perfect, USA (title 45410066, version 1; default.xbe
 * SHA-1 daf0bcc57b6e93a7ebf5498074c8a9e7dc90381e): the functions
 * fp/src/recomp_manual.c attaches to, by address, each found by what it does.
 */

/* -- the MMX memcpy at 0x000245C0 (from Recompose's titles/futureperfect) --
 *
 * sub_000245C0 is the title's MMX block copy: void *(void *dst, const void
 * *src, size_t n), cdecl, returning dst (five callers, among them
 * sub_0011A930). It enters two slides of string moves through computed jumps:
 *
 *   mov ecx, 8; sub ecx, edi; and ecx, 7; ... neg ecx; add ecx, 0x2460C; jmp ecx
 *       -> 0 to 7 movsb (0x00024604..0x0002460B) to align the destination
 *   shr ecx, 2; and ecx, 0xF; neg ecx; add ecx, 0x24784; jmp ecx
 *       -> 0 to 15 movsd (0x00024774..0x00024780) for the tail
 *
 * The lifter turns `jmp <reg>` into gotos only when the register was loaded
 * with `mov reg, imm`, and the disassembler ends the function at 0x00024772,
 * before the movsd slide. Lifted, the first jump resolves to nothing:
 * "[ICALL] unresolved jump target 0x0002460C" from 0x0011ACAC in the 2401
 * intro cutscene, and the title faulted at once on the data the copy never
 * wrote. It is the only `jmp <reg>` in the XBE whose target is computed by
 * `add reg, imm`. A copy has no behaviour beyond the bytes it moves, so this
 * does exactly what the original does; memmove, because overlap was never
 * defined. Delete it once the lifter follows computed jumps into slides.
 */
#define FP_GUEST(va) ((uint8_t *)((uintptr_t)(uint32_t)(va) + g_xbox_mem_offset))
#define FP_MEM32(va) (*(volatile uint32_t *)FP_GUEST(va))

void sub_000245C0(void)
{
    uint32_t dst = FP_MEM32(g_esp + 4u);
    uint32_t src = FP_MEM32(g_esp + 8u);
    uint32_t n   = FP_MEM32(g_esp + 12u);

    if (n && dst != src)
        memmove(FP_GUEST(dst), FP_GUEST(src), n);
    g_eax = dst;
    g_esp += 4u;            /* ret: the caller pops the arguments (cdecl) */
}
