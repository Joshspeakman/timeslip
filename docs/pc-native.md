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
