# Multiplayer: System Link for TimeSplitters 2

Status (13 October 2026): System Link works on Windows, between copies of
this build on one PC, on a LAN and over the internet. Since 23 November 2026
it works on macOS and Linux too, and between them: a Mac and a Windows PC on
one LAN, and a Windows PC and Linux (x86-64, in WSL on the same PC), each
held a Deathmatch (the USA release; see "Between systems" below). Split-screen
multiplayer works on all of them.

TimeSplitters 2 has System Link (LAN play between consoles) and no Xbox Live,
so there is no online service to replace. The toolkit emulates the console's
network card and carries its Ethernet frames between copies, and the game's
own network code runs unchanged on top. How the card, the sessions and the
crypto work is toolkit material, in
`xboxrecomp/docs/technical/system-link.md`. This file keeps what is specific
to TS2.

## Playing

The README's System Link section covers it for players: one copy hosts a
session from the launcher's System Link tab (or `RECOMP_SYSLINK=host`), the
others join it (`RECOMP_SYSLINK=join RECOMP_SYSLINK_HOST=<address>`), and then
everyone uses the game's own Arcade > System Link menu.

Two copies on one PC, each with its own save folder so each has its own
Ethernet address:

```text
copy A: RECOMP_SAVE_DIR=<a> RECOMP_SYSLINK=host RECOMP_SYSLINK_UPNP=0
copy B: RECOMP_SAVE_DIR=<b> RECOMP_SYSLINK=join RECOMP_SYSLINK_HOST=127.0.0.1
```

TS2 keeps its profiles under `UDATA` in the game folder, which
`RECOMP_SAVE_DIR` does not cover. Run scripted copies from copies of the game
folder without `UDATA`.

## How TS2's network code runs

The game links Microsoft's network library (XNet) into its own executable, in
the `XNET` section (VA `0x0020B0E0` in PAL, `0x0020ACC0` in USA, 37,836
bytes). It does not start the stack at boot: nothing touches the network card
until Join Game, or the hosting path, starts XNet. That is also when the
game first asks for the console's Ethernet address.

The PAL driver is five functions at `0x0020F578` to `0x0020FD1E`. Its
interrupt routine (`0x0020F742`) connects on bus level 4. The register-level
trace of what it does is in the toolkit's doc ("What XNet does, measured").

To find a game, XNet broadcasts UDP from port 3074 to port 3074, from IP
0.0.0.1. There is no DHCP on System Link.

## What TS2 needed

One seed. Selecting System Link makes an indirect call to `0x0009D530`
(PAL), which discovery had not found. The skipped call returned 0, the game
took its error path and crashed writing through `0xFFCFFFF0`. The seed is in
`config/pal/seeds.json` and in the toolkit's `config/seeds/4553000A.json`.

Everything else was toolkit work that every title gets: the network card,
a unique Ethernet address per save folder, a kernel fix that had moved the
card's interrupt to vector 0, and real Diffie-Hellman and triple DES in place
of the stubs.

## Measured

Two PAL copies on one PC, Deathmatch, 150 seconds in the level:

| Run | Joined | Match | Frames (host out / in) |
| --- | --- | --- | --- |
| No added delay | yes | held to the end | 1654 / 1506 |
| 100 ms added each way | yes | held to the end | 1336 / 1233 |
| 50 ms each way, 5% loss | yes | held to the end | 1324 / 1157, 130 dropped in all |

In a match TS2 sends about 11 frames a second each way. The largest frame
seen during the join was 298 bytes. Match traffic has not been measured for
frame size.

## Between systems (23 November 2026)

The USA release, `netplay` b7aa63c (toolkit bbcbb1c), PC hosting:

| Host | Joiner | Match |
| --- | --- | --- |
| Windows 11 (zig build, Direct3D 11) | Mac, M1 Pro, Metal, over the LAN | held the 5 minutes run: 3,636 frames out, 3,327 in, none dropped; both in the lobby, then "1st=" with the other on radar to the end |
| Windows 11 | Mac, the same, both players walking, turning and firing (netplay edb2854) | held to the end: 3,037 frames out, 2,786 in, none dropped, 8-12 ms round trip; each saw the other's dot move on the radar and its own view move |
| Windows 11 | Linux (WSL Ubuntu 26.04, clang, Vulkan on llvmpipe) | held to the end of the run, about 1,280 frames each way, the joiner walking and firing |
| Linux (WSL, llvmpipe held to 4 threads) | Windows 11 | held to the end of the run, about 800 frames each way |

A Linux host in WSL drawing on llvmpipe with every core starved its own
System Link thread, so its welcome came seconds late and Join Game found
nothing; `LP_NUM_THREADS=4` fixed that, and so does any real GPU. The
toolkit now also holds a joiner's first frames until it is welcomed (xboxrecomp
`src/kernel/xbox_net_udp.c`), so a slow welcome no longer loses the search.

What it took, beyond the card:

- A second USA seed, `0x000D0DD0`, called on the joiner's match load (the
  first, `0x0009D4F0`, opens the menu; see "Not done" for the history).
- The x87 transcendentals from the toolkit's `src/math` instead of the host's
  libm (xboxrecomp `src/math/recomp_math.h`): glibc, Apple's libm and Windows'
  CRTs round some sin, cos, tan, atan2, log2 and exp2 results differently, and
  two systems playing each other must compute the same game. It turned out
  not to be what was dropping matches, and no match has been seen to drift
  without it: it is kept as a precaution.
- Nothing else in the game. What broke every first attempt was the test rig:
  the Windows copy's stderr was a PowerShell pipe, which stalled the game's
  logging and stretched its match load from about 3 s to 15 s, more than
  TS2's load handshake tolerates between consoles (loads about 12-14 s apart
  dropped, "Lost Server"; about 1.5 s apart held; the exact limit is not
  measured). The toolkit's `docs/technical/system-link.md` has the details;
  send a test copy's stderr straight to a file. The same limit would drop a
  player whose machine really loads that much slower than the others.

A match's load handshake, as seen on the card: at START the host sends one
211-byte frame; each side, once its level is loaded, sends 74-byte frames
and then one each of 82, 98, 157 and 266 bytes; then both send a 76-byte
frame about every 100 ms for the rest of the match.

## Online co-op (Story, `coop` branch)

System Link only ever covered Arcade, and Story co-op on the console is two
players split-screen on one machine. Online co-op runs that split-screen game
on both machines and sends only the controllers: each copy computes the same
game from the same pads, frame by frame (xboxrecomp
`docs/technical/lockstep.md`). The host is player 1 and the joiner player 2,
each with their own machine's controller 1.

### Playing

In the launcher's System Link tab, one player chooses **Host online co-op**
and the other **Join online co-op** with the host's address (the router is
opened on the host's side, as for System Link). Or without the launcher:

```text
host:  RECOMP_LOCKSTEP_NET=host                 (UDP 27620)
join:  RECOMP_LOCKSTEP_NET=join RECOMP_LOCKSTEP_PEER=<host's address>
```

The joiner's game starts from the host's saves, handed over before it boots
(the joiner's own are not touched). Then, as on one console: **2 Players** at
the title screen, each player presses A to claim a controller and picks or
creates a profile, and **Story Co-op** in the main menu. Both copies must be
the same build (both repositories' commits, stamped at build time) with the
same Widescreen and front-end (`ts2_menus`) settings; a joiner that differs
is refused, told why, in the log beside the game.

Each player has the whole screen, as in GoldenEye's online co-op: the game
lays every player's view out as the whole screen, as in one-player play, on
both machines, and each machine draws only its own player's (`coop_view =
split` keeps the console's split screen instead; both players must choose the
same). Menus, cutscenes, loading screens and a level's fly-by, which both
players watch, are shown to both.
The window's title says what the session is doing: waiting for player 2,
playing with whom, the other player left, or the two games differ.

Each frame waits for both controllers. A press lands a few frames after it
is made, on both machines: the joiner measures the round trip as it joins
and picks the delay that covers it (3 frames, 50 ms, on a LAN; 9 at 100 ms
each way), unless `coop_delay` / `RECOMP_LOCKSTEP_DELAY` names one. A slow
machine slows the game for both.

### What it took in TS2

- Each player's whole screen: TS2 lays a player's view out with
  `sub_001B49C0(viewport, x0, y0, x1, y1)` from a handful of places (each
  player's own viewport every frame, the camera's through a level's opening
  and when the player takes control, the level's setup); called from those
  it is given the whole 640x480 frame, so the camera, the HUD and the aspect
  are one player's. The game points `0x00483F28` at a player's viewport for
  that player's pass, and the renderer leaves out every draw and clear made
  during the other player's (`xbox_D3D8SetDrawFilter`). Found by logging the
  layout calls and watching writes to player 2's viewport
  (`RECOMP_WATCH_WRITE`); `ts2_viewport_rect` in `src/recomp_manual.c`.
- One step per frame: TS2 steps by the vblanks elapsed (1 to 3), so its
  vblank count (USA `sub_001C8190`) answers the lockstep tick
  (`ts2_vblank_count` in `src/recomp_manual.c`), and its frame clock
  (`sub_001ADF80`) is the frame boundary.
- The state checked each 60 frames: `.data` (globals and the pools after
  them), less the vblank counter and the music streamer's own state
  (`config/us/overrides.inc`).
- Everything else is the toolkit's (clocks, sound, the music thread, GPU
  visibility tests, x87 NaNs, saves, the network): xboxrecomp
  `docs/technical/lockstep.md` lists what each difference was.

Two players reach Story Co-op from a fresh game by script (controller 2 by
`RECOMP_INPUT_SEQ_P2`): controller 1
`10000:down,12000:start,16000:a,22000:a,26000:start,30000:a,38000:a,46000:a,52000:a,58000:a,64000:a,70000:a,76000:a`
(2 Players, claim controller 1, a new profile, Story Co-op, through the
intro, Siberia on Normal) and controller 2 `18000:a,23000:a,27000:start,31000:a`
(claim controller 2, a new profile). `tests/lockstep/` has 8,000 frames of it,
both players moving and firing in Siberia, as a recording every build must
replay the same.

### Measured (23 November 2026)

| Check | Result |
| --- | --- |
| The recording replayed offline: Windows (Direct3D 11, Vulkan), Linux (WSL, clang), macOS (M1 Pro, Metal) | the same at every frame on all |
| Online, two copies on one PC | the same at every frame, both against the recording |
| Online, Windows host with a saved profile, Linux joiner (WSL) | the joiner booted from the host's saves (5 files, 23 KB); the two the same at every frame |
| Online, Windows host, Mac joiner, over the LAN | 8,000 frames, every 60-frame check the same, the host the same as the recording |
| Online, two copies, 50 ms more each way and 5% lost (`RECOMP_LOCKSTEP_SIM_DELAY_MS`, `_LOSS`) | the same at every frame; 6,000 frames in 102-105 s (100 s of frames) |
| The same, 100 ms each way and 10% lost | the same at every frame; 218 ms measured, 9 frames of delay, 6,000 frames in 103-106 s (at a fixed 4 frames: 139 s) |
| Each player's whole screen, online between two copies (the windows dumped by `RECOMP_PRESENT_DUMP`) | each machine its own player only, at the whole window with its own HUD, from the moment the player takes control; the fly-by, menus, pause, Game Over and status screens on both; the two the same at every frame over the recording and over 40,000 frames of random play (pause, hits, Mission Failed, quit to the title). The game's memory differs from a split-screen run from the level's setup on (the layout is in it), so a split-screen recording does not replay the same with it; offline, with no session, nothing changes (the recording the same at every frame) |

### Not done

- Played by people with controllers: every run so far was a recording or a
  script.
- Over the real internet (simulated only), and a Mac hosting (macOS asks the
  person at the Mac to let the game through its firewall the first time).
- More than two players; a desync is reported, not repaired.

## Not done or not checked

- A Mac hosting a PC (it needs macOS's firewall to allow the game's incoming
  connections, which asks the person at the Mac the first time), Linux
  hosting a Mac, and Linux on real hardware rather than WSL.
- More than two systems in one session, and Mac against Linux. On one Mac
  (23 November 2026, an M1 Pro, the USA
  release, `netplay` 51d36f3) the card works through the toolkit's POSIX path
  (the signal handler and the arm64 decoder; xboxrecomp
  `docs/technical/system-link.md`): two copies, host and join on 127.0.0.1
  with the scripts below, both on the Metal renderer, loaded the same
  Deathmatch on Mexican Mission at 60 fps; over the run the host sent 916
  frames and took 840, none refused or dropped. Mac to PC and Linux to PC
  are above ("Between systems").
- The USA release over the internet, and with added delay or loss. On one
  PC (23 November 2026) it works:
  selecting System Link made one unresolved indirect call, to `0x0009D4F0`
  (PAL's `0x0009D530`, 0x40 lower), which left a blank screen; with it seeded
  in `config/us/seeds.json`, two copies (one on Vulkan, one on Direct3D 11,
  built with zig and Ninja) hosted and joined a Deathmatch on Mexican Mission
  and held it to the end of the run, the joiner walking and firing, 10 to 11
  frames a second each way, none dropped. Host's script (fresh profile):
  `12000:start,16000:start,20000:start,24000:start,28000:a,34000:down,38000:a,42000:down,44000:down,47000:a`
  (Arcade, System Link), then `51000:a,55000:a,60000:a,65000:a,70000:a,75000:a`
  (Start Game, Deathmatch, the first map, GO, a character, the game's name)
  and `125000:start`; the joiner's the same to `47000:a`, then
  `51000:down,88000:a,94000:a,100000:a,106000:a,112000:a`.
- Playing against xemu or a real console. It needs the player's own
  `XboxLANKey` in `keys.ini`. Two recompiled builds agree on an all-zero key,
  which is why they play each other without one. Untested.
- XLink Kai.
- More than one player per copy (split screen over System Link). It
  multiplies traffic, and has not been tried.
- The intermittent `0xFFFFFFFF` exit (see `CLAUDE.md`) would end a session
  for everyone if it hit the host.
