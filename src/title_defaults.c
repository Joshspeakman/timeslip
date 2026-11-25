/*
 * title_defaults.c -- TimeSplitters 2's own defaults, where the toolkit's
 * do not suit a first-person shooter played on a PC (recomp_config.h,
 * recomp_title_defaults_install). Built into the game (src/main.c installs
 * them first thing) and into the launcher (recomp_add_launcher DEFAULTS),
 * so both show and use the same.
 *
 * The keyboard and the mouse, laid out the way modern PC shooters are --
 * Call of Duty is the model -- over what TS2's own "Default" control
 * configuration does with each Xbox control (Options > Player Options >
 * Controls):
 *
 *   right trigger      Fire                 left mouse button
 *   left trigger       Alternate fire       G, middle mouse button
 *   right stick press  Aim                  right mouse button
 *   left stick press   Crouch               C, left Ctrl
 *   A                  Activate             F, E, Space
 *   Y                  Manual reload        R
 *   left stick         Run, side step       W A S D
 *   right stick        Look, turn           the mouse (mouse_look)
 *   D-pad left/right   Swap weapon          Q, arrows (and the wheel, below)
 *   D-pad up/down      Zoom in/out          Z / X, mouse side buttons, arrows
 *   Start              Pause (objectives)   Enter, Tab
 *   B                  Back, in menus       Backspace
 *
 * The mouse wheel swaps weapons, or with a weapon that zooms zooms in and
 * out (while aiming, as the d-pad does), and 1 to 9 pick a weapon: both in
 * src/recomp_manual.c (ts2_wheel_filter, ts2_weapon_keys), since what they
 * do depends on the weapon in hand.
 *
 * In the menus W A S D and the arrows move, Enter, Space or F choose (Start
 * chooses too) and Backspace goes back. Esc is the PC menu (the toolkit's),
 * never the game's. A bindings file still wins for any control it names.
 */
#include <stddef.h>

const char *const recomp_title_bindings[] = {
    "lstick_up",    "key:W",
    "lstick_down",  "key:S",
    "lstick_left",  "key:A",
    "lstick_right", "key:D",
    "rtrigger",     "mouse:left",
    "ltrigger",     "key:G mouse:middle",
    "rthumb",       "mouse:right",
    "lthumb",       "key:C key:LCTRL",
    "a",            "key:F key:E key:SPACE",
    "y",            "key:R",
    "b",            "key:BACK",
    "start",        "key:RETURN key:TAB",
    "dpad_left",    "key:LEFT",
    "dpad_right",   "key:Q key:RIGHT",
    "dpad_up",      "key:Z mouse:x2 key:UP",
    "dpad_down",    "key:X mouse:x1 key:DOWN",
    NULL
};

/* Mouse look on: the mouse is how a PC shooter turns. */
const char *const recomp_title_settings[] = {
    "mouse_look", "1",
    NULL
};
