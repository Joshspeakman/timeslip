# TimeSplitters 2 for the Mac: the app

`TimeSplitters 2.app`: a launch window in the style of the other native Mac ports, then the recompiled game.

- **Renderer**: a card each for **Metal** (the toolkit's native Metal renderer, `xboxrecomp/src/d3d/rhi_metal.m`) and
  **Vulkan** (through MoltenVK, upstream's path). Double-click a card to play with it.
- **Graphics Options**: window or full screen, resolution 1x–4x, 16:9 or 4:3, texture filtering, frame rate,
  frame interpolation, FPS counter.
- **Controls**: Keyboard & Mouse (WASD, mouse look, fire and secondary fire on the mouse buttons; a controller still
  works beside it) or Controller (the toolkit's own mapping), with a key guide.
- **Saves**, **Updates** (follows this branch on GitHub and rebuilds from your copy).

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

`TS2_LAUNCHER_SHOT=<png>` renders the window to an image (`TS2_LAUNCHER_PANEL=0|1`, `TS2_LAUNCHER_CARD=0|1`,
`TS2_LAUNCHER_HOVER=<code>`); `TS2_DATA_PATH=<dir>` uses a test copy of the game folder (the game saves into it);
`TS2_LAUNCHER_PLAY=1` presses Play without showing the window. Every other `RECOMP_*` variable passes through to the game.
