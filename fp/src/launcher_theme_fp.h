/*
 * The launcher's look for TimeSplitters: Future Perfect in the Timeslip
 * collection (recompose src/launcher/launcher_theme.h, launcher_showcase.inc):
 * the showcase layout, in the same blue and silver as TimeSplitters 2's
 * (src/launcher_theme_timeslip.h), so the collection looks like one.
 *
 * The pictures are the player's own, made from their disc into the
 * launcher's art folder for this title (...\xboxrecomp\art\45410066):
 * backdrop, logo, glow, card_metal and card_vulkan. Nothing of the game's is
 * in this repository, and nothing is downloaded. Without the pictures the
 * window writes the game's name.
 */
#ifndef TIMESLIP_FP_LAUNCHER_THEME_H
#define TIMESLIP_FP_LAUNCHER_THEME_H

#define THEME_FLAT_PANELS 1              /* the showcase's flat rows and panels */

#define THEME_ACCENT_RGB      0x78B3FF
#define THEME_ACCENT_DIM_RGB  0x38599E
#define THEME_HILITE_RGB      0xDCEBFF
#define THEME_BAR_DARKEN_RGB  0x203048
#define THEME_TRACK_RGB       0x0A1220
#define THEME_SLAB_RGB        0x040812
#define THEME_SLAB_LIT_RGB    0x10203C
#define THEME_INK_RGB         0x040812
#define THEME_INK_SHADOW_RGB  0x020409
#define THEME_BG_RGB          0x040812
#define THEME_GLOW_RGB        0x1E3C78
#define THEME_TEXT_RGB        0xEBF0FA
#define THEME_TEXT_DIM_RGB    0x99ABC7

#define THEME_SC_NAME      "TIMESPLITTERS FUTURE PERFECT"
#define THEME_SC_SUBTITLE  "TIMESLIP"
#define THEME_SC_PLACE     "THE TIMESLIP COLLECTION"
#define THEME_SC_CARD0_ART "card_metal"
#define THEME_SC_CARD1_ART "card_vulkan"

#endif /* TIMESLIP_FP_LAUNCHER_THEME_H */
