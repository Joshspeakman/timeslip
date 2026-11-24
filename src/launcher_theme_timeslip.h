/*
 * The launcher's look for Timeslip (recompose src/launcher/launcher_theme.h):
 * colours taken from TimeSplitters 2's own key art -- a deep teal, and the
 * orange of its stripe and the gun's muzzle -- and where that art is fetched
 * from.
 *
 * The pictures are not in this repository or its releases. The launcher
 * fetches them once into the player's art cache (recompose
 * src/launcher/launcher_art.c) from the LaunchBox Games Database's image
 * host: the GameCube release's fanart background (the Xbox release has none
 * there, and the art is the same game's) and the Xbox release's clear logo.
 * Offline, or until they arrive, the launcher draws its own background in
 * these colours and writes the game's name instead.
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
