/*
 * launcher_games.c -- the Timeslip launcher's games (recompose
 * src/launcher/launcher_games.h): one launcher for TimeSplitters 2 and
 * TimeSplitters: Future Perfect, built into both installs (recomp_add_launcher
 * GAMES, in this repository's CMakeLists.txt and fp/CMakeLists.txt), so
 * either one opens on both games.
 *
 * Each game is found where it is installed -- beside the launcher, or in the
 * other game's install folder beside this one (tools\install_windows.ps1:
 * Programs\Timeslip and Programs\Timeslip Future Perfect) -- or in the build
 * tree, from either build folder. Its card's picture is the player's own,
 * made from their disc into that game's art folder (tools/make_disc_art.py:
 * card_vulkan, Siberia's base and 2401's canyon); nothing of the games is in
 * this repository.
 *
 * Each game's own defaults are its title_defaults.c, the same files the games
 * are built with, taken in here under names of their own.
 */
#include "launcher_games.h"

#define recomp_title_bindings ts2_title_bindings
#define recomp_title_settings ts2_title_settings
#include "title_defaults.c"
#undef recomp_title_bindings
#undef recomp_title_settings

#define recomp_title_bindings fp_title_bindings
#define recomp_title_settings fp_title_settings
#include "../fp/src/title_defaults.c"
#undef recomp_title_bindings
#undef recomp_title_settings

static const char *const ts2_dirs[] = {
    ".", "../Timeslip", "../../../build/Release", NULL
};
static const char *const fp_dirs[] = {
    ".", "../Timeslip Future Perfect", "../../fp/build/Release", NULL
};

const LauncherGame launcher_games[] = {
    { "ts2", 0x4553000Au, "timeslip", "default.xbe", "../../game", ts2_dirs,
      "TIMESPLITTERS 2", "TIMESPLITTERS 2",
      "Story \xc2\xb7 Arcade \xc2\xb7 Challenge \xc2\xb7 online co-op",
      "1990  \xc2\xb7  SIBERIA  \xc2\xb7  OBLASK DAM", "card_vulkan",
      2,    /* its camera widened (src/recomp_manual.c, Hor+) */
      ts2_title_bindings, ts2_title_settings },
    { "fp", 0x45410066u, "timeslip_fp", "default.xbe", "../../game", fp_dirs,
      "TIMESPLITTERS FUTURE PERFECT", "FUTURE PERFECT",
      "Story \xc2\xb7 Arcade \xc2\xb7 Challenge \xc2\xb7 MapMaker \xc2\xb7 online co-op",
      "2401  \xc2\xb7  TIME TO SPLIT", "card_vulkan",
      1,    /* its own 16:9 mode (fp/CMakeLists.txt recomp_title_widescreen NATIVE) */
      fp_title_bindings, fp_title_settings },
};
const int launcher_game_count = (int)(sizeof launcher_games / sizeof launcher_games[0]);
