# Audio Cue Manifest

Every sound the current chapters reference, with production status.
Status: **missing** → **placeholder** (shippable for playtests) → **final**.

All current files are **placeholder**: procedurally synthesized originals
from `Tools/generate_placeholder_audio.py` (mono 16-bit WAV, 32 kHz,
loop-crossfaded). Regenerate any of them by editing that script and
re-running it. To replace one with a curated/recorded sound: drop in a mono
file with the same name (CAF/WAV — `Tools/normalize_audio.sh` converts and
loudness-normalizes), flip its status to **final**, and add its row to
`ASSETS.md`. Spatial sources MUST be mono — PHASE positions them in 3D;
stereo files break localization.

## Scene: Fox Hollow (ForestJourney)

| File | Status | Description | Search terms for final pass |
|---|---|---|---|
| wind_leaves_loop.wav | placeholder | Gentle wind through leaves, seamless loop | "wind leaves rustle loop" |
| crickets_loop.wav | placeholder | Soft night crickets, seamless loop | "crickets ambience loop" |
| companion_call.wav | placeholder | Friendly two-note call, gap for looping | per-companion variants later |
| river_loop.wav | placeholder | Medium river flow, seamless loop | "river stream flowing loop" |
| oak_creak_loop.wav | placeholder | Slow deep wood creaks, sparse loop | "tree creak wood groan" |
| acorn_chime_loop.wav | placeholder | Tiny silver bell chime, gentle loop | "small bell chime twinkle" |
| bridge_creak_loop.wav | placeholder | Old wood bridge creaking over water | "wooden bridge creak" |
| chicks_quiet_loop.wav | placeholder | Very quiet sleepy bird chirps | "baby birds nest quiet" |
| stream_quiet_loop.wav | placeholder | Tiny underground water trickle | "water trickle quiet" |

## Scene: Echo Chamber (Crystal Caves)

| File | Status | Description | Search terms for final pass |
|---|---|---|---|
| waterfall_loop.wav | placeholder | Waterfall doorway, seamless loop | "waterfall medium loop" |
| cave_hum_loop.wav | placeholder | Deep cave drone, breathing loop | "cave ambience drone" |
| cave_drips_loop.wav | placeholder | Echoing water drips, sparse loop | "cave water drips echo" |
| crystal_chime_loop.wav | placeholder | Ringing crystal song, sparse bells | "glass bell crystal ring" |
| guardian_snore_loop.wav | placeholder | Boulder's deep sleepy rumble | "giant snore rumble" |
| moonstone_shimmer_loop.wav | placeholder | Soft silvery shimmer, very quiet | "magic shimmer twinkle soft" |

## Scene: Lantern Courtyard (City of Lanterns)

| File | Status | Description | Search terms for final pass |
|---|---|---|---|
| castle_wind_loop.wav | placeholder | Open wind over castle walls | "wind castle walls open" |
| banners_flap_loop.wav | placeholder | Cloth banners flapping, sparse | "flag cloth flap wind" |
| bell_tower_loop.wav | placeholder | Deep sleepy bell strikes | "church bell distant slow" |
| lantern_hum_loop.wav | placeholder | Warm lantern flame hum | "lamp hum warm flicker" |
| mice_choir_loop.wav | placeholder | Tiny three-part squeaky singing | original recording, honestly |

## Companions (roster)

| File | Status | Description |
|---|---|---|
| ember_greeting.wav | placeholder | Bright fox yip-yip |
| ember_celebrate.wav | placeholder | Excited ascending yips |
| ember_sniffing.wav | placeholder | Rhythmic sniffs |
| ember_padding.wav | placeholder | Soft paw-step trot loop |
| ember_hum.wav | placeholder | Curious little hum |
| petal_greeting.wav | placeholder | Sparkly chimes + wing flutter |
| petal_celebrate.wav | placeholder | Ascending chime run |
| petal_flutter_up.wav | placeholder | Wings fluttering upward |
| petal_wings.wav | placeholder | Gentle wingbeat loop |
| petal_chime.wav | placeholder | Dreamy soft chime |
| clover_greeting.wav | placeholder | Shy snuffles + tiny squeak |
| clover_thump.wav | placeholder | Happy double foot thump |
| clover_ear_wiggle.wav | placeholder | Quick soft rustles |
| clover_hops.wav | placeholder | Soft hop pairs loop |
| clover_soft_hum.wav | placeholder | Tiny gentle hum |

## UI / feedback

| File | Status | Description |
|---|---|---|
| earcon_listen_start.wav | placeholder | Tap-to-talk: ears open (rising) |
| earcon_listen_stop.wav | placeholder | Tap-to-talk: done (falling) |
| earcon_freeze.wav | placeholder | Freeze-and-explain soft gong |
| celebrate_step.wav | placeholder | Quest step sparkle |
| celebrate_quest.wav | placeholder | Warm quest-complete fanfare |
| note_do.wav … note_ti.wav | placeholder | Solfège tones C4–B4, warm harmonics (7 files) |

## Movement & controls

Footsteps come in a/b alternates per surface — one repeated hit at walking
cadence sounds like a machine gun. Biome mapping: forest→grass, cave→cave,
castle→stone, default grass.

| File | Status | Description | Search terms for final pass |
|---|---|---|---|
| footstep_grass.wav | placeholder | Soft grass footstep, filtered noise burst (a) | "footstep grass single soft" |
| footstep_grass_b.wav | placeholder | Soft grass footstep, alternate (b) | "footstep grass single soft" |
| footstep_stone.wav | placeholder | Flagstone footstep, crisp tap (a) | "footstep stone single" |
| footstep_stone_b.wav | placeholder | Flagstone footstep, alternate (b) | "footstep stone single" |
| footstep_cave.wav | placeholder | Stone footstep with cave echo tail (a) | "footstep cave echo single" |
| footstep_cave_b.wav | placeholder | Stone footstep with cave echo tail, alternate (b) | "footstep cave echo single" |
| earcon_stick_engage.wav | placeholder | Touch stick engaged under the thumb (soft pop) | original |
| earcon_turn_tick.wav | placeholder | Heading crossed a 45° sector (tiny tick) | original |
| earcon_boundary.wav | placeholder | Soft dull thump at the world's edge | "soft thud muffled" |
| earcon_autopilot_start.wav | placeholder | Companion leads the way (rising triad) | original |
| earcon_autopilot_stop.wav | placeholder | Autopilot stopped (gentle falling pair) | original |
