# Future Perfect's lockstep recordings

As TimeSplitters 2's (`tests/lockstep/` at the repository's root): each
frame's controllers, with a hash of the game's state every 60 frames,
recorded on one machine. A replay on any other build must reach the same
hash at every checkpoint.

| File | Release | What it plays | Frames |
| --- | --- | --- | --- |
| `coop-2401-us.trace` | USA | A fresh game: 2 PLAYER, both make a profile (player 2 by START), Story Co-op, 2401 Time To Split on Normal, the briefing and the intro, then both players walking, turning, strafing and firing | 13,730 |
| `arcade-vietnam-us.trace` | USA | A fresh game: 2 PLAYER, both profiles, Arcade, Arcade, Deathmatch, Vietnam, the recommended weapons and six bots, GO!, both pick Cortez; then both players walking, turning, strafing and firing among the bots -- hits, deaths, respawns, pickups, ranks from 1st= to 7th -- with a pause and a resume at 160 s | 14,329 |

Both recorded 26 November 2026 on Windows (Vulkan) with `RECOMP_LOCKSTEP=1`
and `RECOMP_INPUT_SEQ_PAD=1`; controller 2 by `RECOMP_INPUT_SEQ_P2`. Reduced
with `py -3 -m tools.lockstep compact` (from `recompose/`).

- Co-op: controller 1
  `20000:down,21000:a,26000:a,32000:a,38000:a,62000:a,68000:a,74000:a,80000:a,86000:a,92000:a`,
  controller 2 `42000:start,46000:a,50000:a,54000:a`; then from 112 s every
  6 s for 17 rounds controller 1
  `<t>:lstick_up:3500,<t+800>:rt:1800,<t+3600>:rstick_left:450,<t+4200>:lstick_left:1200`
  and controller 2, 1.5 s later,
  `<u>:lstick_up:3000,<u+500>:rt:1500,<u+3300>:rstick_right:400,<u+4000>:lstick_right:1000`
  (every third turn and every second strafe the other way).
- Arcade: controller 1
  `20000:down,21000:a,26000:a,32000:a,38000:a,61000:down,63000:a,68000:a,73000:a,78000:a,83000:a,88000:a`,
  controller 2 `42000:start,46000:a,50000:a,54000:a,88500:a`; then the same
  rounds from 105 s for 20 rounds, less those starting from 158 s to 169 s,
  and controller 1 `160000:start,165000:a` (pause, resume).

Replay one from a copy of the game folder with no `UDATA` and an empty save
folder, muted:

```bash
RECOMP_GAME_DIR=<game copy without UDATA> RECOMP_SAVE_DIR=<empty folder> \
RECOMP_MUTE=1 RECOMP_WINDOW_BACKGROUND=1 \
RECOMP_LOCKSTEP_REPLAY=fp/tests/lockstep/arcade-vietnam-us.trace \
fp/build/Release/timeslip_fp 2> replay.log
grep LOCKSTEP replay.log | tail -1
```

The last line says how many of the recording's ticks differed: 0, or the
first that did. Both were recorded at Future Perfect's defaults and replay
the same only at them: mouse look on (`mouse_look = 1`, the title's default;
with it Auto Lookahead is set aside, so a replay with it off plays another
game -- the Mac's first replays with an older settings file differed from
tick 6,890), the game's own field of view (`fov = 0`), widescreen off. A
recording keeps no settings, so a replay at other ones just differs; an
online session checks them and refuses.

Several copies replaying one recording at once find what depends on the
host's timing fastest. The Arcade one found the fifth GPU fence time the game
keeps in `.data` (`config/us/overrides.inc`): one copy in four or more drifted
in one page from its first fight on, with the game itself the same.
