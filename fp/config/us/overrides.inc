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
 * 0x007BEDC0, 0x1F54 apart; sub_00069720 returns a slot's controls).
 *
 * Native mouse look: the look state's yaw is +0x100 and pitch +0x104, in
 * degrees (found by dumping the state through a turn and a look: 349.6 to
 * 87.4 and back, 10.3 to -12.9 and back); the pitch is held within
 * +-[0x007B0C80] (0x0025DCCB). Its controller: the stick reads
 * (sub_000CF200 -> sub_00042970) take the state's id (+0) through the table
 * at 0x006B93C0 to a pad, or the id itself while [0x0076B0FC] is set.
 *
 * The wheel's zoom (fp_zoom_state): the player's camera while it is stepped
 * is [0x007B0CC0], and +0x388 is the angle the zoom is going to -- the angle
 * at rest, or while aiming a weapon that zooms its aim angle and below
 * (logged through an aim in an Arcade match: 55 at rest; the scoped pistol
 * 30.25, then 29.25, 24.25, 23.25 as the d-pad zoomed). */
static const FpLook k_fp_look = {
    0x007B0C7Cu, 0x1500u, 0x100u, 0x104u, 0x007B0C80u, 0x006B93C0u, 0x0076B0FCu,
    0x007B0CC0u, 0x388u
};
extern void sub_0025D520_gen(void);
void sub_0025D520(void) { fp_look_step(sub_0025D520_gen, &k_fp_look); }

/* control_step is sub_000D5C70 (fp_control_step), called from the player
 * update sub_000D5EB0 for the player being controlled, whatever its control
 * mode: it dispatches on the look state's mode word ([0x007B0C7C] +0x114):
 * 2..16 through the table at 0x000D5E84/0x000D5E98 (2 sub_00258F50, 4
 * sub_000D4100, 8 sub_000D4610, 16 sub_000D55F0), 0x20, 0x800 and above
 * apart. On foot the look step runs as well; the other modes read the right
 * stick themselves (sub_000CCAB0, sub_000D0E30, sub_000D2470, sub_0022B1A0:
 * found by the Mac session, logging every right-stick read). The mouse moves
 * the right stick while a player is controlled but not on foot
 * (fp_menu_mouse_frame). */
extern void sub_000D5C70_gen(void);
void sub_000D5C70(void) { fp_control_step(sub_000D5C70_gen); }

/* MapMaker's editor is sub_00306460 (fp_editor_step), which reads both of
 * pad 0's right-stick axes every frame the editor is up (0x003073F6,
 * 0x00307405: the grid's view; found by the Mac session in a MapMaker
 * session). MapMaker's screens draw a cursor of their own, moved by the
 * left stick, A choosing under it: there the mouse moves that stick and its
 * buttons are A and B (fp_menu_mouse_frame). */
extern void sub_00306460_gen(void);
void sub_00306460(void) { fp_editor_step(sub_00306460_gen); }

/* base_fov is sub_000CB3B0(player) (fp_base_fov): fld [0x004785CC] (55.0,
 * the game's vertical field of view), or [0x00478900] while player+0x254
 * is 0 and +0x258 is 1; called by the look step and the camera and culling
 * code. Found from the projection a gameplay frame uploads (y scale 1.92 =
 * cot 27.5 degrees). */
extern void sub_000CB3B0_gen(void);
void sub_000CB3B0(void) { fp_base_fov(sub_000CB3B0_gen, 0x004785CCu); }

/* player_reset is sub_000CC720(player, mode) and player_place sub_000CBD10
 * (player, ...): each has base_fov's test inlined (fp_player_fov) and writes
 * the player's camera angle itself -- +0x384..+0x390 in reset (55 when mode
 * is 0, else 55 or 45 as base_fov would), +0x388 in place (55 or 45). */
extern void sub_000CC720_gen(void);
void sub_000CC720(void) { fp_player_fov(sub_000CC720_gen, 0x384u, 4u); }
extern void sub_000CBD10_gen(void);
void sub_000CBD10(void) { fp_player_fov(sub_000CBD10_gen, 0x388u, 1u); }

/* object_draw is sub_000A2740(object) (fp_object_draw), which draws every
 * object (from sub_000867F0, sub_000A2900, sub_00344400). Its layer, +0x34:
 * the world's 1..0xC8 (0x000A27B4); 0xCA + a player that player's
 * first-person layer, the hands and the weapon (sub_00115F10 and
 * sub_0008CE30 take 0xCA off it to index the players' 0x1584-byte records
 * at [0x007B0C48]); the sky 0xCF, the backdrops 0xD5 (found by the Mac
 * session, 25 Nov). The current camera is [0x007B0CC0], the angle it shows
 * at +0x384 (eased toward +0x388, where sub_00259DF0 puts base_fov's answer,
 * 0x00259E27), its base at +0x390 (aiming is 0.55 of it), its
 * viewport at +0x224 as viewport_rect (sub_00055D90(vp, x0, y0, x1, y1))
 * lays it out: x0 +0, x1 +4, y0 +0x14, y1 +0x18, inclusive screen pixels.
 *
 * effect_draw is sub_00111FC0(effect) (fp_effect_draw), called for each
 * effect by the effects' pass sub_00112120 (the list at [0x0073BD54], next at
 * +0xF4), which puts the camera-space view (0x007A5900) in place for an
 * effect with bit 0x10 of +4 set and the camera's own (+0x208) for the rest:
 * the first-person muzzle flash is one (flags 0x00011011, at about (0.26,
 * -0.09, -0.75) in front of the camera; another player's view of the same
 * shot is a world-space one at the gun of the player's body, +0x88). */
static const FpViewModel k_fp_view_model = {
    0x007B0CC0u, 0x384u, 0x390u, 0x224u, 0x0u, 0x4u, 0x14u, 0x18u, 0x34u, 0xCAu, 0xCEu, 4u, 0x10u
};
extern void sub_000A2740_gen(void);
void sub_000A2740(void) { fp_object_draw(sub_000A2740_gen, &k_fp_view_model); }
extern void sub_00111FC0_gen(void);
void sub_00111FC0(void) { fp_effect_draw(sub_00111FC0_gen, &k_fp_view_model); }

/* weapon_change is sub_001BF140 (fp_weapon_change), called from the player's
 * weapon update sub_001C4400 (0x001C4593) each frame the player may change
 * weapon: for the player whose look state [0x007B0C7C] points at, it reads
 * the d-pad (the masks at +0x3C/+0x38, next and last weapon; +0x44/+0x40,
 * the weapon's next and last mode) and changes the player's weapons (look
 * state +0x14 -> character, +0x7C -> weapons; the player's number at +8,
 * the slot held at +0x94). Next weapon (0x001BF164): the sound
 * sub_00238510(0x3E, player, 1.0f), select sub_001BA130(weapons,
 * sub_001BAAF0(weapons, 1, 1)), the HUD's panel sub_00142820(). The order
 * the d-pad steps through is the 70 slots at 0x004FC888, from the second
 * for a human (sub_001BAAF0's wrap: [weapons +8] < [0x00790950], the human
 * players); a slot is 0x3C bytes in the table at 0x004FA128, its category
 * at +0x38. Found by watching the slot through d-pad changes in an Arcade
 * match (pistols 10, fists 1: their slots; pistols, the other mode and a
 * pair are slots 8, 9, 10, all category 4). */
extern void sub_001BAA70(void), sub_001BA410(void), sub_001BA130(void);
extern void sub_00238510(void), sub_00142820(void);
static const FpWeaponKeys k_fp_weapon_keys = {
    0x007B0C7Cu, 0x14u, 0x7Cu, 0x006B93C0u, 0x0076B0FCu, 0x00790950u,
    0x004FC888u, 70u, 1u, 0x004FA128u, 0x3Cu, 0x38u, 0x94u, 8u,
    sub_001BAA70, sub_001BA410, sub_001BA130, sub_00238510, sub_00142820
};
extern void sub_001BF140_gen(void);
void sub_001BF140(void) { fp_weapon_change(sub_001BF140_gen, &k_fp_weapon_keys); }

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

/* viewport_rect is sub_00055D90(vp, x0, y0, x1, y1) (online co-op's whole
 * screens, fp_viewport_rect). The game's current-viewport word is
 * 0x007E71C8 (sub_00055D80 sets it); sub_00056050(x0, y0, x1, y1) lays the
 * current one out through viewport_rect (its call returns to 0x00056070).
 * Logged in a two-player Story level (RECOMP_FP_VPLOG): the cameras'
 * viewports (camera + 0x224; the cameras at [0x007B0CE4], 0xFFC apart) are
 * laid out when the level is set up by the camera layout switch
 * (sub_0025A570, on the number of players, sub_001CDAE0): 0x0025A62C one
 * player, the whole screen less a pixel ([0x004E8CF0]-1, [0x004E8CF4]-1);
 * 0x0025A67A player 1, the top half, 0,0-639,239; 0x0025A65D player 2, the
 * bottom, 0,240-639,479. In the intro, 0x000CB1BE lays player 1's camera out
 * whole and both watch it. Every frame each player's pass lays that
 * player's HUD viewport out from the current one, its camera's
 * (sub_002F2FF0, returning to 0x002F30EA), the look state [0x007B0C7C]
 * being that player's. The scissor (sub_0001A010) and the projection are
 * made from the current viewport. */
static const FpViews k_fp_views = {
    0x007E71C8u, 0x00056070u, 0x002F30EAu, { 0x0025A67Au, 0x0025A65Du }, 0x000CB1BEu,
    0x004E8CF0u, 0x004E8CF4u, 0x007B0C7Cu, 0x006B93C0u, 0x0076B0FCu
};
extern void sub_00055D90_gen(void);
void sub_00055D90(void) { fp_viewport_rect(sub_00055D90_gen, &k_fp_views); }

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
