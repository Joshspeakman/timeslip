# Future Perfect's lockstep recordings

As TimeSplitters 2's (`tests/lockstep/` at the repository's root): each
frame's controllers, with a hash of the game's state every 60 frames,
recorded on one machine. A replay on any other build must reach the same
hash at every checkpoint.

| File | Release | What it plays | Frames |
| --- | --- | --- | --- |
| `coop-2401-us.trace` | USA | A fresh game: 2 PLAYER, both make a profile (player 2 by START), Story Co-op, 2401 Time To Split on Normal, the briefing and the intro, then both players walking, turning, strafing and firing | 13,770 |

Recorded 25 November 2026 on Windows (Vulkan) with `RECOMP_LOCKSTEP=1`,
`RECOMP_INPUT_SEQ_PAD=1`, controller 1 by `RECOMP_INPUT_SEQ`
`20000:down,21000:a,26000:a,32000:a,38000:a,62000:a,68000:a,74000:a,80000:a,86000:a,92000:a`
and controller 2 by `RECOMP_INPUT_SEQ_P2` `42000:start,46000:a,50000:a,54000:a`,
then from 112 s every 6 s for 17 rounds controller 1
`<t>:lstick_up:3500,<t+800>:rt:1800,<t+3600>:rstick_left:450,<t+4200>:lstick_left:1200`
and controller 2, 1.5 s later, `<u>:lstick_up:3000,<u+500>:rt:1500,<u+3300>:rstick_right:400,<u+4000>:lstick_right:1000`
(the turns and strafes alternate sides). Reduced with
`py -3 -m tools.lockstep compact` (from `recompose/`).

Replay it from a copy of the game folder with no `UDATA` and an empty save
folder, muted:

```bash
RECOMP_GAME_DIR=<game copy without UDATA> RECOMP_SAVE_DIR=<empty folder> \
RECOMP_MUTE=1 RECOMP_WINDOW_BACKGROUND=1 \
RECOMP_LOCKSTEP_REPLAY=fp/tests/lockstep/coop-2401-us.trace \
fp/build/Release/timeslip_fp 2> replay.log
grep LOCKSTEP replay.log | tail -1
```

The last line says how many of the recording's ticks differed: 0, or the
first that did. A replay at other settings than the defaults (widescreen,
the field of view) differs early on.
