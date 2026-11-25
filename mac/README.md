# TimeSplitters 2 for the Mac: the app

`TimeSplitters 2.app`: a launch window in the style of the other native Mac ports, then the recompiled game.

- **Renderer**: **Metal**, the toolkit's native Metal renderer (`recompose/src/d3d/rhi_metal.m`). The Mac draws with
  Metal only: no Vulkan or MoltenVK in the app, and an old settings file's `renderer = vulkan` means Metal.
  Double-click the card to play.
- **Graphics Options**: window or full screen, resolution 1x–4x, 16:9 or 4:3, texture filtering, frame rate,
  frame interpolation, FPS counter.
- **Controls**: Keyboard & Mouse (WASD, mouse look, fire and secondary fire on the mouse buttons; a controller still
  works beside it) or Controller (the toolkit's own mapping), with a key guide.
- **Play Together**: System Link (host or join) and online co-op (host or join, for a game whose build has it), the
  host's address, whether to open the router (UPnP) when hosting, and this Mac's own address to give the other player.
- **Saves**, **Updates**: the newest GitHub release (pre-releases included), fetched and rebuilt from your copy
  (`mac/update.sh`; `tools/update_windows.ps1` is the Windows one, with the same rules).

## Make it

```sh
VULKAN_SDK=~/VulkanSDK/1.4.357.1/macOS ~/.venvs/recomp/bin/python scripts/build.py   # README: "Build it yourself"
mac/make_art.sh     # the launcher's art, from your own disc (about 3 minutes; once)
mac/install.sh      # builds /Applications/TimeSplitters 2.app
```

The disc's files go in `~/Games/TimeSplitters2Native/game` (`default.xbe`, `data/`, `music/`); the game saves there too
(`game/UDATA`). `install.sh --app <path> --data <dir>` puts either somewhere else. It refuses to replace an app at that
path that isn't this one, and won't run while the game is open.

Nothing from the game is in this folder: `make_art.sh` takes the title screen's logo textures and frames the game
draws, from your copy, into `<data>/art`. The app holds the game's recompiled code: for your own Mac, never share it.

## Development

`TS2_LAUNCHER_SHOT=<png>` renders the window to an image (`TS2_LAUNCHER_PANEL=0|1`,
`TS2_LAUNCHER_HOVER=<code>`); `TS2_DATA_PATH=<dir>` uses a test copy of the game folder (the game saves into it);
`TS2_LAUNCHER_PLAY=1` presses Play without showing the window. Every other `RECOMP_*` variable passes through to the game.
