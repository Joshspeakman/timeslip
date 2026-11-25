# PC-native features: what is there and what is next

Josh's brief (23 November 2026): everything a PC game is expected to have --
frame rate and resolution settings, quitting whenever you like, modern mouse
and keyboard controls with Call of Duty as the baseline, and the best
renderer on each system at the highest frame rate, losing none of the
graphics or effects.

Most of the work is the toolkit's (Recompose): menus, settings, input and
renderers serve every title. TS2's part is its facts: where it turns the
camera, its control layouts, its defaults.

## Already there

| | Where | How |
| --- | --- | --- |
| Internal resolution 1-8x of 640x480 | Toolkit | `resolution_scale`, launcher Video tab |
| Widescreen, camera widened (Hor+) | Both | `widescreen`; TS2 lays out every screen for 16:9 |
| Texture filtering | Toolkit | `anisotropy` 1-16 |
| Borderless fullscreen, variable refresh | Toolkit | Alt+Enter, `fullscreen`, `vrr` |
| Frame cap | Toolkit | `frame_cap` adaptive / 60 / 30 / uncapped; F10 cycles it. Uncapped makes TS2 run fast: its logic steps once a frame |
| Above 60 frames a second on screen | Both | `frame_interp` 2-4: in-between frames drawn while the game runs at 60 |
| Frame counter, captures | Toolkit | F9, F11 |
| Rebindable keyboard and pads | Toolkit | `input_bindings.json`, launcher Input tab; mouse buttons are sources too |
| Mouse look | Toolkit | `mouse_look`: the mouse pushes controller 1's right stick (raw input, pointer clipped to the window) |
| Quitting | Toolkit | closing the window, Alt+F4, or the in-game menu's Quit to desktop |
| **In-game menu** (Nov 2026) | Toolkit | Esc: pauses (holds the title and its sound; online the game goes on), Resume, Quit to desktop, and display, frame-rate and mouse settings, saved to the settings file; some apply at once, the rest at the next start, with Restart now. Dear ImGui through the RHI, so the same on every renderer |
| Renderers | Toolkit | Windows: Direct3D 11 (default), Vulkan. Linux: Vulkan. macOS: Metal (`mac-local`/`metal`), MoltenVK |

## Missing, in the order it will be done

1. ~~An in-game menu~~ **Done** (Recompose 2bb2629): see the table above.
   Left: a controller can't open it yet (keyboard only), controls are not
   rebindable from it (the launcher's Input tab does that), and it is
   checked on Windows only so far.
2. ~~Call of Duty-style keyboard and mouse defaults~~ **Done** (Recompose
   770c186, `src/title_defaults.c`): over TS2's own "Default" control
   configuration, W A S D, mouse look on, left button fire, right button
   aim, G or middle button alternate fire, R reload, F/E/Space use, C or
   Ctrl crouch, wheel/Q/arrows for weapons, Z/X or the side buttons to zoom,
   Enter or Tab to pause; the README's Controls table. The launcher shows
   the same defaults. To check by hand: whether TS2's aim (right stick
   press) is a toggle or held, and whether that suits the right button.
3. ~~Mouse look that is a mouse, not a stick~~ **Done** (Recompose
   f578cf6; TS2 `ts2_mouse_look`): the mouse turns the player's yaw and pitch
   (degrees, at player context +0x148 / +0x14C) by an angle each frame, after
   the game reads the sticks (sub_00148160), with no ramp, dead zone or top
   speed; 0.11 degrees a count at the default sensitivity, invert in the
   menu; the game's own +-40 degree pitch limit kept. Online, each machine's
   mouse is latched with its controller (lockstep protocol 4), checked the
   same on both machines and in replay. Left: aim mode (the right button)
   with the mouse, aim assist, a separate sensitivity while aiming, and
   feel by hand.
4. **Resolution and frame rate the PC way** (toolkit): render at the
   window's own size ("native") or a chosen one, not only whole multiples of
   640x480; a frame-rate target that picks the interpolation for the
   display (120, 144, 165, 240) and a V-Sync switch.
5. **The fastest renderer on each system, nothing lost** (toolkit): the
   co-op recording replayed as a fixed benchmark on each renderer, frame
   times and pictures compared frame for frame; the default changes only
   for a measured win with the same pictures. Windows: Direct3D 11 against
   Vulkan. macOS: Metal against MoltenVK (on the Mac).

Each step is checked against the lockstep recording (`tests/lockstep`): it
must still replay the same at every frame, offline and online.

## The picture at higher resolutions (24 November 2026)

Josh's report: above 1x the game still looked low resolution, the world
showed seams you could see through (Arcade, Mexican Mission, along the outer
walls, whenever moving), and effects such as smoke and haze looked wrong.

**One cause for all three, fixed** (Recompose c5689c3, 291724e). TS2 ends
every frame with three full-screen passes that blend a copy of the frame
back over it: a soften and motion blur, one console pixel wide. The copy went
into a render-target texture the size the game asked for, 640x480, while
the frame itself was rendered 5 times larger. So every frame was overlaid
three times with a 640x480 point sample of itself:

- the whole picture veiled at console resolution: "still looks low-res";
- every edge against a bright background stair-stepped and partly
  transparent, shifting as the camera moved. This is very likely the
  "seams you can see through" along the walls: it matches where and when
  Josh saw them (walls against the sky, moving, scaled only), and nothing
  else that looks like a seam was found. Inferred, not confirmed by him;
- sparks, fire and smoke with serrated, blocky outlines.

Render targets, depth surfaces and depth textures the game creates are now
made at the scene's own scale, and the copies fill them one to one.
`RECOMP_RT_SCALE=0` puts the old sizes back for comparison.

Measured on replays (`RECOMP_PRESENT_DUMP_TICKS`, the same frame on both
sides), at Josh's settings (5x, widescreen, 16x filtering, interpolation 3):

| Check | Result |
| --- | --- |
| Scaling off against the build before | identical, pixel for pixel |
| Sharpness at 5x (edge measure) | 11-17% higher on every frame, interpolated frames too; same brightness |
| Wall edges against the sky while turning | the stair-stepped see-through band gone |
| Sparks, fire, bullet trails (Arcade, Mexican Mission) | clean outlines where they were serrated |
| The handheld's map (a corner of the screen copied into it) | continuous lines where they broke into dots |
| Split screen, each player's own screen, Vulkan | the same improvement; Vulkan within driver rounding of Direct3D 11 |
| Frame rate, uncapped at 5x | no change: about 200 fps (Direct3D 11) and 290 (Vulkan) either way on an RTX 3080 Ti |
| Co-op recording at 5x | the same as the recording at every frame |

What TS2 draws that depends on the resolution, and where each stands:

| Technique | Status |
| --- | --- |
| Copies of the frame (the soften and blur passes, the handheld's map) | scaled (above) |
| Render-target and depth textures | scaled |
| Interpolated frames | checked at full scene resolution while turning: no cracks |
| Line lists (the handheld's map) | one host pixel wide at any scale, so thinner as the scale rises. Left as it is |
| Point lists (50 untextured size-1 points a frame) | the same; nothing visible found that depends on them |
| Fog, decals, fire, sparks, smoke sprites | resolution-independent; compared 1x against 5x |

Not found: cracks between pieces of the level. Full-resolution scene dumps
(`RECOMP_PRESENT_DUMP_SCENE=1`) of Siberia and Mexican Mission, still and
turning, showed none. A long dark line from a pistol to where it hit, seen
while firing, is drawn the same at 1x and 5x, at 4:3 and 16:9, so it is the
game's own (a bullet trail, by its look) rather than anything of the port's.

`tests/lockstep/arcade-mexican-mission-us.trace` is the scene for this:
Arcade, Deathmatch on Mexican Mission with the recommended bots, walking
along the walls, turning and firing.

Checked on the Mac too (M1 Pro, Metal): both recordings the same at every
frame at 5x, the same pictures and brightness, and 0.55 ms more GPU time a
frame at 5x (2.41 to 2.96 ms), under a third of a 120 Hz frame.

## Widescreen without stretching (24 November 2026)

Josh's report: the world and the HUD looked stretched at 16:9 rather than
corrected. What was measured, at his settings (16:9, 2560x1440 screen):

- **The in-game camera is right.** The horizontal half-width the game keeps
  over the vertical one (`RECOMP_TS2_CAMLOG=1`) is 1.778 for the player's
  view in one-player play and in co-op's own-screen view, and 3.556 for
  each half of split screen, which is 16:9 for a half-height view. It has
  been widened in the game itself (so what is drawn and what is culled
  agree) since the USA release was added.
- **Every other projection was 4:3, fixed.** The game builds four more
  (`build_projection`'s other callers): the front end's two scene cameras,
  the character select's model and the projection decals are drawn with.
  Left at 4:3 they were stretched by 4/3 at 16:9. Sgt Cortez on the
  character select measured 26% wider by area than at 4:3, the same height;
  now the same as at 4:3. Bullet holes landed up to 4/3 too far from the
  middle of the screen, or not at all; now they are where the shots hit.
  Widened only in widescreen with the 16:9 front end, both of which an
  online session already makes the machines agree on.
- **The 2D: what the width guess got wrong, fixed.** Unplaced 2D is left to
  the renderer, which squeezes a narrow batch to 4:3 and spans a wide one.
  Comparing each frame with every unplaced site forced to the middle and
  forced to span found:
  - the row of bullets beside each ammo number once some were spent stayed
    beside the guns while the number went to the corner;
  - falling snow (Siberia) was squeezed toward the middle whenever few
    flakes were on screen, and spread out when many were;
  - the whole-screen tint while the player burns, a frame of which at 4:3
    put a seam down both old borders;
  - eight more sites of the code that projects sprites into the world,
    spanned in every frame seen, now pinned so a frame with few of them is
    not squeezed off the 3D.

  Everything else the two recordings draw unplaced (68 sites in Story
  co-op, 82 in Arcade) the guess put right: text and panels kept in
  proportion, haze and fades across the whole picture.

Online: two copies in one session with widescreen on, 6,000 frames of play
and firing, the same game on both at every frame. A machine on an older
build is refused at the handshake (the build id is both repositories'
commits), so a PC and a Mac on different builds cannot drift apart.

Left: the PAL release has neither the projection hook nor the new sites
(its addresses are not checked). Screens neither recording reaches
(Challenge, MapMaker, Options, the story's other levels and cutscenes) are
unsurveyed. `RECOMP_TS2_UI_SITES=1` now logs each site's first frame and
whether it is placed, so a replay of a recording that reaches a screen
lists what to look at.

## The corridor sweep (24 November 2026)

Josh's report: on Mexican Mission, moving the mouse quickly opened breaks in
the level through to the sky, the post-processing was still blurry, the gun
floated at a wider field of view, the plasma gun blinked the screen, and he
wanted a mouse cursor in the menus. A test that plays the game found each of
them: `RECOMP_TS2_SWEEP=<script>` (`src/recomp_manual.c`) runs an Arcade match
under lockstep from the player's spawn in the mission's cloister, turns the
player as a mouse does (5 to 60 degrees a frame), hands out the match's
weapons, fires each, keeps the player alive and in place, and logs every
frame; frame dumps by tick range (`RECOMP_PRESENT_DUMP_TICKS=a-b/n`, in-between
frames named `...i.bmp`) and input-script steps by tick (`t<tick>:button`) make
a run that slows down still line up. The recording replays the same at every
frame, so a setting that only changes the picture can be compared frame by
frame.

What it found, and what changed:

| | Found | Fixed |
| --- | --- | --- |
| Breaks to the sky on fast turns | Only in frame interpolation's in-between frames (the game's own frames were clean in every replay). TS2 draws what it sees through a doorway clipped to the doorway's rectangle on screen (about fifty scissors a frame) and culls to its newer camera; an in-between frame looks part of the way back, so it showed rooms clipped by the newer frame's rectangles, and rooms only the older camera saw were never drawn. Breaking in-between frames: 34 of 72 at 5 degrees a frame, 50 of 71 at 15 | Recompose `hle_d3d8_interp.c`: each scissor is carried along with the camera's turn (`d3d8_SetScissorWarp`), what the older frame drew and the newer left out is drawn into the in-between frame moved as the camera moved (and what only the newer one drew is moved back), every piece is blended by its motion relative to the frame before so the level's pieces move together, and a turn of up to 20 degrees a frame is interpolated (a flick faster than that shows the game's own frames: at 30 and 60 degrees a frame in-between frames lost the rooftops beyond the roof and a wedge under it, 20 of 62 and 11 of 54, so 70 was tried and dropped). After, on the harness's own recording (`tests/sweep`): 1 of 62 at 15 degrees a frame, none at 30 and 60, none while firing the fire rifle or weapon 13, 1 with the shotgun, 3 with the pistols (60 before); a thin sliver at the screen's edge on the frame a swing reverses remains. Widening the game's own culling was tried and dropped: what it culls feeds the game (a replay ended with a different rank) |
| Breaks to the sky while walking and turning (second round, from Fable's test and the Mac's walking run) | Josh still saw them. Away from the sweep's one spot they were common at every field of view: four units along the arcade, standing and turning 10 degrees a frame, 125 broken in-between frames (Fable's `factor0` recording), walking 104 and 114 (`walkA0`, `walkA100`), a real mouse 175 of about 1,000. Three causes: (1) the doorway scissors -- carried along with a turn, they cannot follow a walk (near doorways move more than far ones), and the sky TS2 draws flat through a doorway, with no depth test, was painted over the wall beside it where a carried rectangle came out too wide; (2) on a fast mouse turn toward a bare wall the two pistols, held still on the screen, outvoted the level for which motion is the camera's, so the camera was taken to stand still and what only the older frame drew was left where it had been; (3) turns of 15 to 20 degrees a frame still lost pieces at the screen's edge the camera was leaving (13% of in-between frames with a real mouse) | Recompose `xbox_D3D8SetScissorsOff`: TS2 is drawn without its scissors for a frame of play (a player updated) whose every player view is the whole frame and that draws no front-end scene (`ts2_present`, `ts2_viewport_rect`). Its frames are the same without them there, HUD and all (frame for frame over the corridor sweep, a dark room and Fable's arcade spot); a local split screen, the letterboxed end of a match and the menus keep theirs, since TS2 keeps a split screen's halves, the letterbox and its list boxes to their rectangles with a scissor (dropped, player 2's sky was drawn over player 1's half, and the Game Over screen's 3D streaks over the bars). Checked pixel for pixel against the scissors kept: both co-op recordings to their last frame (results screens included) and the menus. The camera's motion is voted by primitives weighed down by nearness to the eye, agreeing in turn and move, and a frame is held as a cut by the same weights (with a bare wall in view the pistols had outweighed a level that turned past the limit). Turns of up to 12 degrees a frame are interpolated (720 a second; faster flicks show the game's frames). After: 0 of 613 (`factor0`), 1 of 553 (`walkA0`), 5 of 583 (`walkA100`), 0 of 616 in the dark room, 0 of 320 in the Mac's walk at FOV 100, 15 of 831 with the real mouse (slivers at the edge the camera leaves, still open). Both co-op recordings replay the same at every frame, and their pictures are the same as with the scissors kept but for 12 results-screen frames (about 128 scattered pixels each, along the streaks' edges) |
| Hairlines of sky and sand along pillar and doorway edges, flickering as the view moves (Fable's test; Josh: "blinking lines on the ground") | In the game's own frames at 5x, none at 1x: the doorway rectangles are whole console pixels, and a wall's edge inside a pixel the rectangle leaves out shows what is behind | The same: in play, drawn without the rectangles. Fable's arcade spot: 69 of 400 frames had them, 13 after (where a doorway's rectangle spans the screen's width, kept as a letterbox would be) |
| The soften pass | A copy of the screen blended back over it at 25%, one console pixel down: five screen pixels at 5x, a ghost under every edge | Recompose `post_soften` (launcher Graphics, Esc menu): `sharp` (default) scales the shift to one screen pixel, `console` keeps it, `off` leaves it out |
| The gun at a wider field of view | The hands and weapon (`view_model`, US `sub_000AF8A0`, found by the guest stack of their draws) upload only their transforms (c64-c67) and draw with whatever projection c60-c63 hold, which at the console's one field of view was always the camera's; widened, they shrank toward the middle and the arms showed. A first fix rewrote uploads of c60-c67 carrying the widened projection, but those belong to the decal pass restoring the camera after itself, so the weapon was right only on frames where one came first (on the Mac at FOV 80, tick 4600 of the sweep: both pistols small and high) | `ts2_view_model`: the 60-degree projection (the camera's, x and y scaled by tan(fov/2) / tan(30)) is set in c60-c63 for the pass and the camera's after it, both through the game's own `D3DDevice_SetVertexShaderConstant4`, so they reach the push buffer in draw order and frame interpolation's recording. The muzzle flashes the pass draws come with it. A scope's narrower view is left alone. The filter is gone |
| Bullet holes sliding off the walls at a wider field of view | The pass that draws bullet holes, scorch marks and blood over the level (`sub_00058510`) builds its own projection each time, 60 degrees times the zoom (in radians, from 0x00058574), so at FOV 100 the holes sat where they would at 60 and slid as the view turned | `ts2_build_projection`: that call gets the chosen field of view too (a scope's narrower one stays) |
| The plasma blink | Not black: one frame washed white. The Plasma Autorifle's bolt glow, an additive sprite spawned at the camera, crossed the near plane and covered the view (draw 237 of the frame took the picture's mean from 82 to 138); the same with interpolation off | **Not fixed.** Recompose `reduce_flashes` (an additive glow reaching behind the near plane left out) took the plasma frames to brightness 71 to 88, but compared frame for frame with it off it also took out the shotgun's and fire rifle's smoke, light near the camera and a sight the fire rifle draws: it works out depth from the registers interpolation uses, which many effect programs do not. Off by default now (`RECOMP_REDUCE_FLASHES=1` for testing); a real fix needs the depth each program puts out |
| A mouse cursor in the menus | | Once no player has been updated for a quarter of a second (front end, pause, results), the pointer shows and the mouse works the menu: wheel to move, left to choose, right to go back (`hle_window_title_menu`); play takes the pointer back. Pointing at an item to highlight it is the next step |

Left: slivers at the screen's edge on fast real-mouse turns (15 of 831
in-between frames in Fable's mouse recording); the doorway scissors still on
in a local split screen (its hairlines and in-between breaks as before), and
where a doorway's rectangle spans the screen's width (taken for a letterbox:
13 of the 69 frames with hairlines at Fable's arcade spot keep them); the plasma bolt's glow starts
about 4% of the screen nearer the middle than the barrel at FOV 100 (the gun is
drawn at 60, the bolt with the world); Vulkan not run through the sweep yet;
the plasma grenades (alternate fire) untested; strafing frames cannot be
judged by the sky test; a scope's view at a wider field of view (no scoped
weapon in this match). Fable's recordings and scripts:
`I:\Development\scratch\ts2-sweep\fable-review` on the PC (not in the repo).
