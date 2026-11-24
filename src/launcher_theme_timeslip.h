/*
 * The launcher's look for Timeslip (recompose src/launcher/launcher_theme.h):
 * a deep teal and an orange, after TimeSplitters 2's key art.
 *
 * By default the launcher shows Timeslip's own mark (art/logo-launcher.png,
 * compiled in) over its own background in these colours. A backdrop of the
 * game's comes only from the player: an art/ folder beside the launcher, or
 * the art cache (recompose src/launcher/launcher_art.c), which Timeslip's
 * mac/make_art.sh fills from the player's own copy of the game. The two
 * addresses below -- the LaunchBox Games Database's copies of the GameCube
 * release's fanart and the Xbox release's clear logo -- are fetched only if
 * the player asks (RECOMP_LAUNCHER_FETCH_ART=1): they are the publisher's
 * art, and nothing here downloads it unasked.
 */
#ifndef TIMESLIP_LAUNCHER_THEME_H
#define TIMESLIP_LAUNCHER_THEME_H

#define THEME_ACCENT_RGB      0xF39A2C   /* the art's orange */
#define THEME_ACCENT_DIM_RGB  0x7A4A14
#define THEME_HILITE_RGB      0xFFE4BC
#define THEME_BAR_DARKEN_RGB  0x3A2408
#define THEME_TRACK_RGB       0x0E1A1E
#define THEME_SLAB_RGB        0x07141A   /* panels: near-black teal */
#define THEME_SLAB_LIT_RGB    0x163A44
#define THEME_BG_RGB          0x08141A
#define THEME_GLOW_RGB        0x1E6A78   /* the art's teal, at the glow's heart */
#define THEME_TEXT_RGB        0xEEF4F6
#define THEME_TEXT_DIM_RGB    0x8FA6AF

#define THEME_ART_BACKDROP_URL \
    "https://images.launchbox-app.com/08a8c4cd-39e0-434a-8597-74b1010fcfe7.jpg"
#define THEME_ART_LOGO_URL \
    "https://images.launchbox-app.com/075f4b11-0225-4c27-abf5-028a815d99b8.png"

#endif /* TIMESLIP_LAUNCHER_THEME_H */
