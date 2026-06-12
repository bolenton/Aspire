# Asset License Ledger

Every asset that ships in Lantern is listed here with its source and license.
This is mandatory: the app ships publicly (free, Kids category) and the repo
is intended to be open-sourced, so provenance must be airtight.

| Asset | Type | Source | Author | License | Notes |
|---|---|---|---|---|---|
| Assets/Audio/*.wav (all 41 files) | audio | `Tools/generate_placeholder_audio.py` | this project (procedurally synthesized) | original work, CC0 | Placeholder pass — replace file-by-file per Assets/Audio/MANIFEST.md |
| Assets/Art/{ember,petal,clover}.png | image | _pending — provided by project owner_ | _fill in (note AI generator if used)_ | _fill in_ | Companion portraits; see Assets/Art/README.md |
| Assets/music/song1.mp3, song2.mp3 | music | composed for Lantern by the project owner | project owner | original work | song1 = title screen (after welcome); song2 unassigned |

## Rules

1. **No asset enters the repo without a row in this table.** CI/PR review
   should reject binary additions that aren't ledgered.
2. Allowed licenses: CC0, CC-BY (with attribution row filled in), royalty-free
   store licenses that permit redistribution in a free app (keep the receipt /
   license PDF in `Assets/Licenses/`), and original work (mark "original,
   by <name>").
3. CC-BY attributions must also be mirrored into the in-app credits screen.
4. Avoid: BBC Sound Effects archive (non-commercial terms), YouTube rips,
   "free" packs without stated licenses.

## Preferred sources

- **Audio**: Sonniss GDC archives (royalty-free, pro quality), Freesound
  (filter CC0 first), Zapsplat (with attribution), original GarageBand
  compositions for music.
- **3D**: commissioned characters (contracts in `Assets/Licenses/`),
  Sketchfab Store / TurboSquid standard licenses, Quaternius & Kenney &
  poly.pizza (CC0) for placeholders.
