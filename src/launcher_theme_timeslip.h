/*
 * The launcher's look for Timeslip (recompose src/launcher/launcher_theme.h,
 * launcher_hero.inc): the hero layout -- the picked game's key art across the
 * window, its logo and a menu across the bottom -- in the logo's blue and
 * silver; each game's own colour and pictures are in src/launcher_games.c.
 *
 * The pictures are fetched when the game is installed (tools/fetch_art.py:
 * the key art and clear logos from the LaunchBox Games Database) and made
 * from the player's own disc (tools/make_disc_art.py, mac/make_art.sh: a
 * logo, and Future Perfect's controller button pictures), into the
 * launcher's art folder
 * (%LOCALAPPDATA%\xboxrecomp\art\<id>, ~/Library/Application
 * Support/xboxrecomp/art/<id> or ~/.local/share/...). Nothing of the game's
 * is in this repository. The two addresses below are the launcher's own
 * fetch (RECOMP_LAUNCHER_FETCH_ART=1), for a launcher started without an
 * install. Without the pictures the window writes the game's name.
 */
#ifndef TIMESLIP_LAUNCHER_THEME_H
#define TIMESLIP_LAUNCHER_THEME_H

#define THEME_FLAT_PANELS 1              /* the showcase's flat rows and panels */

#define THEME_ACCENT_RGB      0x78B3FF   /* the logo's blue */
#define THEME_ACCENT_DIM_RGB  0x38599E
#define THEME_HILITE_RGB      0xDCEBFF
#define THEME_BAR_DARKEN_RGB  0x203048
#define THEME_TRACK_RGB       0x0A1220
#define THEME_SLAB_RGB        0x040812   /* ink: near-black blue */
#define THEME_SLAB_LIT_RGB    0x10203C
#define THEME_INK_RGB         0x040812
#define THEME_INK_SHADOW_RGB  0x020409   /* under large text: the ink, not black */
#define THEME_BG_RGB          0x040812
#define THEME_GLOW_RGB        0x1E3C78
#define THEME_TEXT_RGB        0xEBF0FA   /* its silver */
#define THEME_TEXT_DIM_RGB    0x99ABC7

#define THEME_SC_NAME      "TIMESPLITTERS 2"
#define THEME_SC_SUBTITLE  "TIMESLIP"
#define THEME_SC_PLACE     "1990  \xc2\xb7  SIBERIA  \xc2\xb7  OBLASK DAM"
#define THEME_SC_CARD0_ART "card_metal"   /* the hub, its portal open */
#define THEME_SC_CARD1_ART "card_vulkan"  /* Siberia's base */

#define THEME_ART_BACKDROP_URL \
    "https://images.launchbox-app.com/08a8c4cd-39e0-434a-8597-74b1010fcfe7.jpg"
#define THEME_ART_LOGO_URL \
    "https://images.launchbox-app.com/075f4b11-0225-4c27-abf5-028a815d99b8.png"

#endif /* TIMESLIP_LAUNCHER_THEME_H */
