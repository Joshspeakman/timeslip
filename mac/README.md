# Timeslip for the Mac: the app

`Timeslip.app`: one launch window for both games, TimeSplitters 2 and TimeSplitters: Future Perfect, in the style of the
other native Mac ports; then the recompiled game you picked, in the same process.

- **Choose your game**: a card for each, with its own art from your disc. A game whose build or disc files are missing
  shows as Not Installed. The tiles below show and change the chosen game's settings; Play (or a double-click on its
  card) starts it, and the launcher opens on the game you picked last.
- **Graphics Options**: window or full screen, resolution 1x–4x, 16:9 or 4:3, texture filtering, post-processing,
  frame rate, frame interpolation, FPS counter. **Advanced**: the renderer, **Metal** (the default: the toolkit's own
  Metal renderer, `recompose/src/d3d/rhi_metal.m`) or **Vulkan through MoltenVK**, from the next start. A MoltenVK that
  cannot start gives way to Metal, and an old settings file's `renderer = vulkan` stays Metal (only `moltenvk` picks it).
- **Controls**: Keyboard & Mouse (mouse look) or Controller, mouse speed, the crosshair, and the game's own keys.
- **Play Together**: System Link (host or join) and online co-op (host or join), the host's address, whether to open
  the router (UPnP) when hosting, and this Mac's own address to give the other player.
- **Saves**, **Updates**: the newest GitHub release (pre-releases included), fetched and both games rebuilt from your
  copies (`mac/update.sh`; `tools/update_windows.ps1` is the Windows one, with the same rules).

Graphics, the renderer and the mouse are kept in each game's settings file,
`~/Library/Application Support/xboxrecomp/titles/<title id>.conf` (`4553000A` TimeSplitters 2, `45410066` Future
Perfect), the one its in-game menu (Esc) changes too, so a change made in either place is what the other shows. The
launcher writes only those lines and keeps the rest. The key bindings are the game's own unless
`titles/<title id>.input.json` (or the shared `input_bindings.json`) names others; the game last picked is in
`launcher_game.txt` beside them, which the Windows launcher uses too. System Link and co-op are chosen for each start.

## Make it

```sh
VULKAN_SDK=~/VulkanSDK/1.4.357.1/macOS ~/.venvs/recomp/bin/python scripts/build.py      # README: "Build it yourself"
VULKAN_SDK=~/VulkanSDK/1.4.357.1/macOS ~/.venvs/recomp/bin/python fp/scripts/build.py   # fp/README.md
mac/make_art.sh     # TimeSplitters 2's launcher art, from your own disc (about 3 minutes; once)
mac/install.sh      # builds /Applications/Timeslip.app with both games
```

TimeSplitters 2's disc files go in `~/Games/TimeSplitters2Native/game` (`default.xbe`, `data/`, `music/`), Future
Perfect's in `~/Games/TimeSplittersFPNative/game`; each game saves there too (`game/UDATA`), and its launcher art is in
`art/` beside it. `install.sh --data-ts2 <dir> --data-fp <dir>` puts them somewhere else; `--app <path>` the app.
`install.sh --title ts2` or `--title fp` builds one game alone, as `TimeSplitters 2.app` or `TimeSplitters Future
Perfect.app`, the apps there were before. It refuses to replace an app at that path that isn't this one, and won't run
while the game is open. The app's launcher is `Contents/MacOS/Timeslip Launcher`, beside `timeslip` and `timeslip_fp`
(a Mac's disk does not tell `Timeslip` from `timeslip`).

Nothing from the games is in this folder: `make_art.sh` takes the title screen's logo textures and frames the game
draws, from your copy, into `<data>/art`. The app holds the games' recompiled code: for your own Mac, never share it.

## Development

`TS2_LAUNCHER_SHOT=<png>` renders the window to an image (`TS2_LAUNCHER_GAME=ts2|fp` picks the game,
`TS2_LAUNCHER_PANEL=0-3` opens Graphics Options, Controls, Play Together or Advanced, `TS2_LAUNCHER_ROWFOCUS=-1`
focuses a panel's title-bar button, `TS2_LAUNCHER_HOVER=<code>` lights an item); `TS2_LAUNCHER_PLAY=1` presses Play
without showing the window. For a test that leaves your own settings alone: `TS2_CONF_DIR=<dir>` (the settings files,
and `launcher_game.txt` in its parent), `TS2_LAUNCHER_PREFS=<prefix>` (the launcher's own settings domains),
`TS2_DATA_PATH_TS2` / `TS2_DATA_PATH_FP=<dir>` (a test copy of a game folder: the game saves into it). Every other
`RECOMP_*` variable passes through to the game.
