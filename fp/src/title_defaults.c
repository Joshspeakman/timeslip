/*
 * title_defaults.c -- TimeSplitters: Future Perfect's own defaults, where the
 * toolkit's do not suit a first-person shooter played on a PC
 * (recomp_config.h, recomp_title_defaults_install). Built into the game
 * (src/main.c installs them first thing) and into the launcher
 * (recomp_add_launcher DEFAULTS), so both show and use the same.
 *
 * The keyboard and the mouse, laid out the way modern PC shooters are, over
 * what the game's own "Default" control layout does with each Xbox control
 * (Settings > Controls, read off the game, 25 Nov 2026):
 *
 *   right trigger      Fire                       left mouse button, H
 *   left trigger       Throw grenade              G
 *   right stick press  Aim                        right mouse button, left Shift
 *   left stick press   Crouch                     C, left Ctrl
 *   A                  Activate                   F, E, Space
 *   X                  Manual reload              R
 *   B                  Melee attack               V (and Backspace, Back in menus)
 *   Y                  (nothing in play; menus)   Y
 *   left stick         Run, side step             W A S D
 *   right stick        Look, turn                 the mouse (mouse_look); I J K L
 *   D-pad up           Toggle weapon mode;        middle mouse button, Z,
 *                      while aiming, zoom in      mouse side button, Up
 *   D-pad down         Change grenades;           X, the other side button,
 *                      while aiming, zoom out     Down
 *   D-pad left/right   Change weapon              Q, Left/Right
 *   the wheel          Change weapon; aiming a    (src/recomp_manual.c,
 *                      weapon that zooms, zoom    fp_wheel_filter)
 *   Start              Pause (objectives)         Enter, P
 *   Back               SCORES / OPTIONS           Tab
 *   White, Black       (the Xbox's two extra      T, B
 *                      buttons)
 *   (none)             A weapon by its place      1 to 9 (src/recomp_manual.c,
 *                                                 fp_weapon_change)
 *
 * Every Xbox control has a key, so nothing any menu or mode asks for is out
 * of reach: Back opens the SCORES / OPTIONS screen in a match (found by
 * pressing it in an Arcade match, 26 Nov 2026; Tab, as PC shooters show the
 * scores), the right stick moves what reads it outside the look step
 * (MapMaker's camera, anything the mouse does not turn), and the right
 * trigger and the aim have keys for the menus, where the mouse's buttons
 * work the menu instead (below).
 *
 * In the game's own menus -- the front end and its submenus, the pause and
 * SCORES screens, results -- the pointer is shown and the mouse works the
 * menu: left button A, right button B, the wheel up and down; the first
 * frame of play takes it back for mouse look (src/recomp_manual.c,
 * fp_menu_mouse_frame, as TimeSplitters 2's).
 *
 * The mouse turns the player directly, as an angle (native mouse look,
 * src/recomp_manual.c, fp_look_step, as TimeSplitters 2's): the game's own
 * Inverse Look (on in a new profile) is for the stick and does not turn the
 * mouse over, so pushed forward it looks up; mouse_invert (the launcher's
 * Controls, the Esc menu) is the mouse's own.
 *
 * In the menus W A S D and the arrows move, Enter, Space or F choose (Start
 * chooses too) and Backspace goes back; the menus' X and Y (Player Progress,
 * Refresh, Options, Delete) are R and Y. Esc is the PC menu (the toolkit's),
 * never the game's. A bindings file still wins for any control it names.
 */
#include <stddef.h>

const char *const recomp_title_bindings[] = {
    "lstick_up",    "key:W",
    "lstick_down",  "key:S",
    "lstick_left",  "key:A",
    "lstick_right", "key:D",
    "rstick_up",    "key:I",
    "rstick_down",  "key:K",
    "rstick_left",  "key:J",
    "rstick_right", "key:L",
    "rtrigger",     "mouse:left key:H",
    "ltrigger",     "key:G",
    "rthumb",       "mouse:right key:LSHIFT",
    "lthumb",       "key:C key:LCTRL",
    "a",            "key:F key:E key:SPACE",
    "x",            "key:R",
    "b",            "key:V key:BACK",
    "y",            "key:Y",
    "white",        "key:T",
    "black",        "key:B",
    "start",        "key:RETURN key:P",
    "back",         "key:TAB",
    "dpad_left",    "key:LEFT",
    "dpad_right",   "key:Q key:RIGHT",
    "dpad_up",      "mouse:middle key:Z mouse:x2 key:UP",
    "dpad_down",    "key:X mouse:x1 key:DOWN",
    NULL
};

/* Mouse look on: the mouse is how a PC shooter turns. It turns the player
 * as an angle (src/recomp_manual.c, fp_look_step), so the game's Inverse
 * Look -- on in a new profile, for the stick -- does not turn it over:
 * pushed forward it looks up. Vulkan on Windows (Josh, 25 Nov 2026),
 * Direct3D 11 a choice in the launcher and the Esc menu's Display; a Mac
 * draws with Metal whatever this says, Linux with Vulkan anyway. */
const char *const recomp_title_settings[] = {
    "mouse_look", "1",
    "renderer", "vulkan",
    "widescreen", "1",      /* Josh, 27 Nov 2026: 16:9 by default, as the Mac's launcher */
    NULL
};
