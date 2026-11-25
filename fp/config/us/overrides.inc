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

/* -- online co-op: the frame clock and the vblank count -------------------
 *
 * frame_clock is sub_001538C0 (fp_frame_clock), called once a frame from the
 * game loops sub_0003D370 and sub_0003D440. It loops on vblank_count,
 * sub_00022030 (which returns the word at 0x00563918, incremented by the
 * vblank callback sub_00022020 that 0x0002406C installs with
 * D3DDevice_SetVerticalBlankCallback), until at least one vblank has passed
 * since the last frame; stores the vblanks elapsed at 0x004E7940 clamped to
 * 1..3 and as a float at 0x004E7948. The other reader of vblank_count is the
 * thread sub_00156CB0. The state hashed for lockstep is .data, 0x004B82C0
 * for 0x333594 bytes (the section table of this XBE), less the vblank
 * callback's own count and the GPU fence times the game keeps.
 *
 * The fence times: Direct3D's push-buffer time (the device, at
 * *0x003E3F58 = 0x003E3F60, +0x2C, outside .data) rises with every fence
 * from the first frame the title draws, and the boot's logos and movies draw
 * before frame_clock first runs, on the host's clock: a frame more or less
 * there (about 5 fences a frame) and every fence after differs by as much.
 * D3DDevice_SetRenderTarget (sub_003D3800) stamps the target it leaves with
 * that time (a resource's Lock, +8), and the game keeps two such resources in
 * .data, its copies of the two frame buffers' headers (0x00563120 and
 * 0x00563154, 0x34 apart, copied from GetBackBuffer's at 0x00023C71); and its
 * two-part geometry ring (0x0054F128, 0x14 apart, flipped by sub_00018DE0)
 * keeps the D3DDevice_InsertFence it waits on before reusing a part, at +8.
 * The game hands those back only to Direct3D's waits, which the kernel's
 * fence mirror always finds done (recompose hle_d3d8.c, "The GPU time
 * fence"). Found by replaying one recording on several copies at once: in
 * about one replay in two everything else was the same at every frame, and
 * these four words differed by 4 from frame 3 on.
 *
 * It is not only the boot: started from one value at the session's first
 * frame (tried, 26 Nov), two copies' times still came apart by 4 in an
 * Arcade match, because Direct3D also fences as its push buffer fills and
 * wraps, which goes as fast as the host's GPU thread empties it. A fence
 * time is the host's timing, so every word in .data that keeps one is left
 * out: the four above, and a fifth an Arcade match stamps from its first
 * fight (0x006654E8's Lock, at 0x006654F0), found the same way with a
 * recording of two players and six bots. A word still missing here shows
 * as a report that the machines differ, not as a game that does.
 */
static const FpStateRegion k_fp_state[] = {
    { 0x004B82C0u, 0x00333594u, ".data" },
    /* Not game state: the vblank callback's count (the game reads the tick
     * instead, through vblank_count). */
    { 0x00563918u, 4u, 0 },
    /* Not game state: GPU fence times (above). */
    { 0x00563128u, 4u, 0 },             /* the frame buffers' Locks */
    { 0x0056315Cu, 4u, 0 },
    { 0x0054F130u, 4u, 0 },             /* the geometry ring's fences */
    { 0x0054F144u, 4u, 0 },
    { 0x006654F0u, 4u, 0 },             /* an Arcade resource's Lock */
    { 0, 0, 0 }
};
extern void sub_001538C0_gen(void);
void sub_001538C0(void) { fp_frame_clock(sub_001538C0_gen, k_fp_state); }
extern void sub_00022030_gen(void);
void sub_00022030(void) { fp_vblank_count(sub_00022030_gen); }

/* look_step is sub_0025D520 (fp_look_step), called from the player update
 * sub_000D5EB0: for the player whose look state [0x007B0C7C] points at, it
 * turns the right stick into the look angles (+0x100, +0x104) and, while
 * +0x108 says there is no look input and bit 3 of byte 2 of the profile's
 * controls ([state +0x1500]) is set, levels the pitch (+0x104) by a share a
 * frame (0x0025DB95): Auto Lookahead. The controls' address and that bit
 * are the same ones the Controls screen changes (the profile slots at
 * 0x007BEDC0, 0x1F54 apart; sub_00069720 returns a slot's controls). */
extern void sub_0025D520_gen(void);
void sub_0025D520(void) { fp_look_step(sub_0025D520_gen, 0x007B0C7Cu, 0x1500u); }

/* loading_screen_start is sub_00156D80 (fp_loading_screen_start), called
 * from the game loop sub_0003D440 at 0x0003D56A: unless the screen is one
 * that has none, it clears the "stopped" flag at 0x004E7A94 (1 in the XBE)
 * and tail-jumps to sub_00156D10, which starts the loading screen's thread
 * sub_00156CB0. Its stops: sub_00156840 (from 0x0003D607), which while
 * 0x004E7A94 is 0 spins until the thread's fade at 0x00749848 reaches 1.0,
 * and sub_00155550, which while 0x0074A9AC is set waits for the thread's
 * end. */
extern void sub_00156D80_gen(void);
void sub_00156D80(void) { fp_loading_screen_start(sub_00156D80_gen); }

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
