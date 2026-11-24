# Lockstep recordings

Online co-op runs the whole game on every machine and sends only the
controllers, so every build on every system has to compute the same game
from the same pads (xboxrecomp `src/kernel/recomp_lockstep.h`). These files
are the check: controller input for each frame, with a hash of the game's
state every 60 frames, recorded on one machine. A replay on any other build
must reach the same hash at every checkpoint.

| File | Release | What it plays | Frames |
| --- | --- | --- | --- |
| `coop-siberia-us.trace` | USA | A fresh game: 2 Players, both create a profile, Story Co-op, Siberia, both players walking, turning and firing | 8,000 |

Replay one from a copy of the game folder with no `UDATA` (the recording
starts from a fresh profile) and an empty save folder, muted:

```bash
RECOMP_GAME_DIR=<game copy without UDATA> RECOMP_SAVE_DIR=<empty folder> \
RECOMP_MUTE=1 RECOMP_WINDOW_BACKGROUND=1 \
RECOMP_LOCKSTEP_REPLAY=tests/lockstep/coop-siberia-us.trace RECOMP_LOCKSTEP_END=8000 \
./split2_recomp 2> replay.log
grep LOCKSTEP replay.log | tail -2
```

The last line says `every tick was the same as the recording`, or names the
first tick that differs. To find out why, write a trace of the replay
(`RECOMP_LOCKSTEP_TRACE=<file>`, which hashes each 4 KB page every frame) on
both machines and compare them, then dump memory at the first differing
tick (`RECOMP_LOCKSTEP_DUMP=<tick>`):

```bash
py -3 -m tools.lockstep trace a.trace b.trace --base 0x002A01E0   # from xboxrecomp/
py -3 -m tools.lockstep dump a.trace.t<tick>.bin b.trace.t<tick>.bin
```

Checked (23 November 2026): Windows 11 (zig/clang, Direct3D 11 and Vulkan)
and Linux (WSL Ubuntu, clang, Vulkan on llvmpipe) replay it the same at every
frame.

Recorded with the menu script in `docs/multiplayer.md` ("Online co-op"),
then reduced with `py -3 -m tools.lockstep compact`.
