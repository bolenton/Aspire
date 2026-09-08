# Lantern Visual Overhaul — from voxel bootstrap to a readable 3D world

This is the canonical spec for the Option A visual overhaul: **stay on
RealityKit, replace the content**. The engine is not the ceiling — the blocky
look was the zero-asset bootstrap. This pass replaces procedural boxes with
smooth procedural meshes plus real 3D models (USDZ), staged so every piece
ships independently and falls back gracefully. (Option B — a Unity/Godot
port — stays on the shelf unless this pass fails her playtest.)

Written like `PolishPlan.md`: independent agents can each execute one
workstream. Read "Ground rules" and your workstream fully first; respect the
file-conflict table at the end.

## Why this pass exists

Her verdict after the polish pass: still can't reliably tell the trees from
the rivers from her character. Root causes, traced:

| # | Problem | Root cause |
|---|---------|-----------|
| 1 | Trees ≈ rivers ≈ character | Everything shares one construction language: axis-aligned emissive boxes. Color is the only distinguishing channel, and similar hues collide |
| 2 | Water unrecognizable | The river is a static glowing slab (`ribbon` shape). **Motion — the strongest cue many low-vision players have — is unused** |
| 3 | Unrelated things look identical | 9 procedural shapes serve 23 entities: the singing crystal renders as a *door*, the bell tower as a *tree*, the mice choir as a *mound* |
| 4 | Blocky/pixelated overall | Terrain, scatter, characters are all voxel boxes — a content choice, not a RealityKit limit |

**North star: readability beats realism.** The wins are distinct silhouettes,
consistent color coding, motion, and depth cues — not photorealism. Art
direction: stylized, bold, high-saturation (*Wind Waker*, not *Unreal demo*).

## Ground rules (every agent)

- **Build system**: iOS 18.0 target, XcodeGen. New source files under `App/`
  (including `.metal`) require `xcodegen generate` before `xcodebuild`. Build
  check: `xcodegen generate && xcodebuild -project Lantern.xcodeproj -scheme
  Lantern -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' build`
- **Assets ship without regen**: `Assets/` is an xcodegen **folder reference**
  (`project.yml`) — dropping `foo.usdz` into `Assets/Art/Models/` lands it in
  the bundle on the next build. Only new *source* files need `xcodegen generate`.
- **Design pillars are sacred** (unchanged): offline-first, audio-first
  (visuals confirm what ears already said), no punishment, deterministic rules.
- **Graceful degradation is the architecture**: every real asset is an upgrade
  over a procedural fallback that never goes away (`WorldBuilder.loadArtModel`
  already implements this for entities). A missing/broken USDZ must never break
  a scene — it just renders the old shape.
- **High-contrast contract is inviolable**: `highContrastYellow` ignores ALL
  art assets and renders procedural silhouettes in forced `#FFE000` on
  near-black (`WorldBuilder.build` already guards this). Every workstream
  keeps that branch working; V4 regression-checks it.
- **Determinism**: each scene must look identical launch-to-launch and
  device-to-device (seeded from scene id). Matching *today's* exact layout is
  NOT required — that constraint belonged to the batching refactor. New
  procedural painters/scatter must draw all randomness from
  `SeededRandom(seed:)` with a stable call order.
- **Zero new persisted fields this pass** — no `CalibrationProfile` /
  `PlayerVault` changes, so the save-file-wipe risk class is structurally
  absent. (If a workstream is tempted to add a toggle: don't. Fallbacks are
  automatic, not settings.)
- **Movement contract**: the game assumes a flat, obstacle-free playable area
  (autopilot walks straight lines; pose has no y). Nothing this pass builds
  may create geometry she can walk into inside the reachable square
  (|x|, |z| ≤ 41).
- **Asset ledger discipline** (`ASSETS.md`): no binary enters the repo without
  a ledger row (source, author, license, prompt if AI-generated). License
  PDFs/receipts go in `Assets/Licenses/` (create it). CC0 preferred sources
  already whitelisted: Quaternius, Kenney, poly.pizza.
- **`Docs/ArtPipeline.md` remains the per-asset contract** (1 unit = 1 m,
  pivot at ground-center, face −Z, GLB → Reality Converter → USDZ, authored
  emissive). This doc adds the *scope and order*; that doc governs each file.

## Verified integration facts (planning-time — trust, with noted hedges)

- **The entity art slot is live**: `WorldBuilder.loadArtModel`
  (`App/World/WorldBuilder.swift:127`) loads
  `Assets/Art/Models/<assetName>.usdz`, scales by `spec.scale`, computes the
  marker height from `visualBounds` (floor 0.5 m), falls back to `shape()` on
  any failure, and is skipped entirely in high contrast. Markers, halos, blob
  shadows, quest beacon all attach around whatever body renders.
- **Existing animations survive assets**: `WorldView.tick` spins the `"body"`
  child for `.item` kinds (fine for a USDZ acorn), bobs `"body"` for the
  companion, flaps `"wing"`-named children (procedural butterfly only).
- **`VisualSpec.shape` is a free string** — no engine whitelist; unknown
  shapes hit `WorldBuilder.shape()`'s `default:` cube. Adding `"water"` is
  safe; `ContentValidationTests` must stay green after pack edits.
- **Content Codable**: optional fields on pack/roster models decode missing
  keys as nil (synthesized Codable). These are bundled content files, not save
  data — no migration risk.
- **`MeshDescriptor` custom meshes** are proven in-repo (`VoxelWorld.TileMesh`)
  — positions + normals + triangles → `MeshResource.generate(from:)`. UVs go
  in `descriptor.textureCoordinates`. Procedural `TextureResource` from
  `UIGraphicsImageRenderer` is proven in-repo (`VoxelWorld.skyDome`).
- **`MeshResource.generateCone/generateCylinder`** exist at our iOS 18 target.
  Hedge: if a signature surprises, build the same solids with a small
  `MeshDescriptor` lathe helper — same pattern as `TileMesh`.
- **`CustomMaterial`** (iOS 15+): Metal surface shader from the app's default
  `MTLLibrary`; the shader reads `params.uniforms().time()` for animation.
  **Behavior in nonAR ARView is not documented either way** (same status bloom
  had) → the water workstream's first hour verifies it on device; a designed
  no-shader fallback exists below. Never let water dead-end the pass.
- **`PhysicallyBasedMaterial.emissiveColor` accepts a texture** — the glow
  floor pass (V2) can reuse a model's base-color texture as its emissive map.

## The entity inventory (what actually needs to read)

From `StoryPacks/ForestJourney/pack.json` — 23 entities, 3 companions, 1 avatar:

| Scene | Entity | Kind | Today renders as | Priority |
|---|---|---|---|---|
| fox_hollow | river, hidden_stream | landmark | glowing slab (`ribbon`) | **V1 water** |
| echo_chamber | underground_river | landmark | glowing slab (`ribbon`) | **V1 water** |
| fox_hollow | old_oak | character | procedural oak | P1 |
| lantern_courtyard | lantern_keeper (Wick) | character | floating cube (!) | P1 |
| echo_chamber | singing_crystal | character | **door** (!) | P1 |
| echo_chamber | crystal_guardian (Boulder) | character | mound (!) | P1 |
| lantern_courtyard | mice_choir | character | mound (!) | P1 |
| lantern_courtyard | bell_tower | character | tree (!) | P1 |
| fox_hollow | glowing_acorn | item | cube | P2 |
| echo_chamber | moonstone, glow_mushrooms, high_geode | item | cube/mound/nest | P2 |
| fox_hollow | buried_treat, high_nest | item | mound/nest | P2 |
| lantern_courtyard | biscuit_stall | item | mound | P2 |
| fox_hollow | castle_gate, cave_mouth, broken_bridge | portal/landmark | door/arch | P3 |
| echo_chamber | forest_door | portal | arch | P3 |
| lantern_courtyard | courtyard_gate, lantern_east/west, flag_garland | portal/landmark | door/cube/ribbon | P3 |
| roster | ember (fox), clover (bunny), petal (butterfly) | companion | voxel critter | V3 |
| — | player avatar | — | voxel figure from AvatarSpec | V3 |

---

# WS-V1 — Smooth world foundation (pure code, zero external assets)

**Goal**: kill the Minecraft look without waiting on any asset: smooth
terrain, smooth scatter, a sky that breathes, and — the single biggest
complaint fix — **water that moves and shimmers**. Everything procedural,
everything seeded, everything shippable this week.

### 1. Terrain v2 (`App/World/VoxelWorld.swift`)

Replace the tiled-box floor with one smooth ground mesh per scene:

- Heightfield grid, ~1.5 m vertex spacing, spanning ±66 m. Height function:
  **0 everywhere in the reachable square (|x|, |z| ≤ 41)** — she can never
  clip a slope — rising beyond it into smooth rolling ridge hills that reuse
  today's noise character (`sin/cos` mix from `tileHeight`), amplitude ~3–5 m.
  Normals via central differences; planar UVs.
- **Painted ground texture** per biome (this replaces per-tile color
  variation): `UIGraphicsImageRenderer` 1024², drawn from
  `SeededRandom(seed: sceneID + "|ground")` — biome base color, soft mottle
  blobs in the existing `groundColors` palette, gentle radial darkening toward
  the rim. Castle additionally gets a faint flagstone grid; cave gets sparse
  speckle. Material: PBM, roughness 1.0, `emissiveIntensity =
  biome.groundEmissive` (the "floor stays dim" rule is load-bearing — the
  interactables must own the bright end).
- Keep the dark base plane beneath; keep the sky dome. Delete the tile
  buckets path (`TileMesh` may survive as the mesh-accumulator helper).
- High contrast: flat near-black ground, **no texture** — the contract is a
  black void; only the ridge silhouette may remain at 0.10 gray.

### 2. Scatter v2 (same file)

Same counts, same `ringSpot` placement discipline, smooth construction:

- Scatter trees: `generateCylinder` trunk + 2–3 stacked `generateCone` /
  squashed-sphere canopies, per-tree canopy color from the existing
  `leafGreens` draw. Deliberately still distinct from the hero `old_oak`.
- Cave: stalagmites = stacked tapering cones; crystals = tilted slender cones,
  emissive 2.2 (they're the cave's sparkle — keep them loud).
- Castle: walls stay chunky (they read correctly), but merlons get corner
  radius and towers get cone caps.
- Flowers: small sphere on a thin cylinder stem.
- High contrast: all scatter stays the 0.12-gray silhouette treatment.

### 3. Water (`WorldBuilder.swift`, `VoxelWorld.swift`, new `App/World/WorldShaders.metal`, `WorldView.swift`)

New shape `"water"` + content change: `river`, `hidden_stream`,
`underground_river` switch `"ribbon"` → `"water"` in `pack.json` (`ribbon`
survives for `flag_garland`).

- Geometry: flat plane `2.6 × 7.4` (× `spec.scale`) at y = 0.02, plus a
  slightly larger dark under-plane at y = 0.005 — the "banks" that ground it.
  No depression, no collision: the visual sits on the walkable plane.
- **Animated material** — `CustomMaterial` surface shader `water_surface` in
  `WorldShaders.metal`: two scrolling sine-ripple layers perturbing the
  normal + a brightness sparkle term, tinted from `spec.colorHex`
  (blue-teal), opacity ~0.85, driven by `params.uniforms().time()`.
  **Hour one: verify CustomMaterial renders in nonAR on device** (print-once
  + eyeball). If `time()` misbehaves, fall back to writing a phase into the
  material's `custom` parameter each frame from `WorldView.tick`.
- **No-shader fallback** (if CustomMaterial fails outright in nonAR): PBM
  translucent blue plane + tick-driven shimmer (gentle brightness/scale
  pulse) + 3 drifting firefly-style sparkle quads clamped to the water
  rectangle. Water must *move* one way or another.
- `WorldBuilder.shape()` gains a `"water"` case for the procedural/HC path: a
  flat slab like today's ribbon (HC keeps forced-yellow slab semantics
  automatically).
- Markers/halos unchanged — the river is a landmark and keeps its star chip.

### 4. Sky & light polish (`WorldView.swift`, `VoxelWorld.swift`)

- Dome stays; strengthen the horizon band subtly per biome.
- Add one dim fill `DirectionalLight` opposing the key light (~15% intensity,
  no shadow) so smooth curved surfaces shade with depth instead of flat
  cardboard. Key light + cast shadows unchanged.

### Acceptance (on device)

River visibly moves and reads as *water* from spawn distance; ground has no
grid seams; rim hills are smooth; scatter trees read as trees at 20 m; 60 fps
holds with bloom on; high-contrast screenshots semantically identical to
today (black world, yellow entities, white markers); two consecutive
launches of the same scene are pixel-identical.

---

# WS-V2 — Entity art fleet (USDZ into the live slot)

**Goal**: every P1/P2 entity gets a real model. The slot exists; this
workstream is briefs → assets → conversion → `assetName` rows → device check.

### 1. Code prep (small, `WorldBuilder.swift` — do first)

- **Glow-floor pass** `applyGlowLanguage(to model: ModelEntity)` called from
  `loadArtModel`: for each `PhysicallyBasedMaterial` whose
  `emissiveIntensity < 0.3`, set `emissiveColor` to the material's base-color
  texture (or tint when untextured) at intensity ~0.8. Authored emissive wins;
  unauthored assets stop reading as dark holes among the glowing primitives,
  and bloom picks them up.
- **Sanity clamp**: after applying `spec.scale`, if the model's visual-bounds
  height is > 6 m or < 0.2 m (wrong-unit export), uniformly rescale into a
  sane band and log once. A giant biscuit must degrade to a weird biscuit,
  not a wall.

### 2. Asset production (human-in-the-loop — dad's task, agents write briefs)

- **Source order**: (1) CC0 packs today — Quaternius / Kenney / poly.pizza
  (already whitelisted; Quaternius has stylized trees, rocks, chests, doors,
  rigged animals); (2) text-to-3D (Meshy / Tripo3D, paid tier for commercial
  terms) for the hero characters no pack will have — Wick the lantern keeper,
  Boulder the guardian, singing crystal, mice choir; (3) commissioned artist
  later if wanted.
- Every model: GLB → **Reality Converter** → USDZ → `Assets/Art/Models/` +
  ledger row + license file. Conventions per `ArtPipeline.md`; tri budgets:
  characters ≤ 15k, props ≤ 8k, items ≤ 5k, **total visible ≤ 150k**.
- Per-entity briefs live in a new `Assets/Art/BRIEFS.md` (agent writes it
  from the inventory table above — one line of intent per entity, e.g.
  old_oak: "gnarled friendly oak, warm bark, a face suggested in the trunk,
  canopy distinct from scatter pines"; singing_crystal: "man-tall luminous
  crystal cluster, faceted, cool cyan"). Briefs are the interface between
  code agents and whoever generates/downloads art.

### 3. Slotting (as assets arrive, any order)

Add `"assetName"` to the entity's `visual` in `pack.json`. One entity per
commit is fine — each lands independently, fallback covers the rest.
Priority: P1 characters (the "someone to talk to" cues) → P2 items → P3
structures.

### Acceptance

Each landed P1 entity is nameable at ~15 m on device; no dark holes (glow
floor working); markers float correctly above each model; item spin looks
right on USDZ items; `ContentValidationTests` green; ledger complete.

---

# WS-V3 — Companions + player avatar

### a. Companion model slot (`StoryEngine` Companion model, `StoryPacks/Companions/roster.json`, `WorldBuilder.swift`, `WorldView.swift`)

- `Companion` gains optional `assetName: String?` (roster content, decodes
  missing as nil). Roster rows point at e.g. `companion_fox.usdz`.
- `WorldBuilder.build`'s companion branch: when not high-contrast, try the
  USDZ; play its first `availableAnimations` clip `.repeat`ed (rigged idle);
  fallback remains `VoxelWorld.critter`.
- `WorldView.tick` bob-guard: skip the procedural bob when the body has its
  own running animation (double-motion reads as glitch). Wing-flap targeting
  is name-based and simply won't match a USDZ — safe.
- Butterfly (petal) stays procedural until a genuinely good rigged asset
  exists; fox and bunny have strong CC0 candidates (Quaternius rigged
  animals).

### b. Avatar smooth pass (`VoxelWorld.playerAvatar` — after V1, same file)

Rounded toy-figure construction replacing the voxel blocks: sphere head,
high-corner-radius torso, cylinder limbs — **identical `AvatarSpec`
customization surface** (body type, skin tone, hair color + all five styles,
outfit color, boots, belt lantern, dark eyes). Her designed hero keeps her
design; only the geometry language smooths.

### c. Avatar USDZ (stretch — only after V2 proves the pipeline)

Rigged base model per body type with a **material-name tint convention**
(`skin` / `hair` / `outfit` named materials, tinted programmatically from
`AvatarPalette`) + hair-style attachment meshes. Do not attempt until a
rigged source of adequate quality exists; the smooth procedural figure is a
respectable end state.

### Acceptance

Companion reads as an animal with lifelike idle motion at 10 m; avatar keeps
her exact chosen colors and hair style; high contrast still renders the
procedural critter/figure; VoiceOver and gameplay untouched.

---

# WS-V4 — Cohesion + the real gate

- **Post-stack retune**: bloom threshold (0.85) was tuned for emissive
  primitives — textured models may need ~0.75; outline weight per support
  level re-checked against the new silhouettes; marker distance-scale
  re-checked against physically larger models.
- **Performance gate**: Xcode FPS gauge per scene on the target iPad, worst
  case first (lantern_courtyard has the most entities); Low Power Mode path
  still skips post effects.
- **High-contrast regression**: side-by-side screenshots of all three scenes
  vs today — must be semantically identical (assets ignored, yellow
  procedural silhouettes, black world, white markers).
- **Her playtest — the actual acceptance test** (dad runs, structured):
  1. At spawn in each scene, point at 5 things: "what's that?" — score
     named/unnamed, compare against the same test on the current build.
  2. Timed "find the ⟨quest target⟩" per scene.
  3. Free play; note every confusion moment verbatim.
  Findings become the punch list; iterate before calling the pass done.

---

# Sequencing

```
V1   smooth world (VoxelWorld, WorldBuilder, WorldView, WorldShaders.metal, pack.json water rows)
     → start immediately, no dependencies, pure code
V2.1 glow floor + scale clamp (WorldBuilder)              — after V1 merges
V2.2 BRIEFS.md + asset acquisition (human + agent)        — parallel with V1
V2.3 assetName slotting rows (pack.json + Assets/)        — as assets arrive
V3a  companion slot (StoryEngine, roster, WorldBuilder, WorldView) — after V2.1
V3b  avatar smooth pass (VoxelWorld)                      — after V1
V4   cohesion + gates + her playtest                      — last
```

File-conflict serialization (do NOT parallelize within a row):
- `App/World/VoxelWorld.swift`: V1 → V3b
- `App/World/WorldBuilder.swift`: V1 (water) → V2.1 → V3a
- `App/World/WorldView.swift`: V1 → V3a
- `StoryPacks/ForestJourney/pack.json`: V1 (water rows) → V2.3

# Verification (whole pass)

- Build after every workstream (command in Ground rules).
- `swift test --package-path Packages/StoryEngine` stays green (V3a touches
  the engine's Companion model — content Codable only).
- High-contrast screenshot diff after every workstream that touches
  `WorldBuilder`/`VoxelWorld`.
- On-device checklist = each workstream's Acceptance + the V4 playtest.

# Risk register

1. **CustomMaterial in nonAR undocumented** — hour-one device check, designed
   shimmer fallback; water can never dead-end (mirrors the bloom playbook).
2. **Asset quality variance** (CC0 mismatch, text-to-3D weirdness) —
   per-entity independence + briefs + human review before any ledger row;
   a rejected asset costs nothing (fallback holds).
3. **Dark-hole assets** — glow-floor pass; authored emissive preferred.
4. **Performance from real meshes** — tri budgets, staged landing, V4 FPS
   gate, Low Power path unchanged.
5. **Determinism drift** — all procedural painters seeded; launch-to-launch
   stability is the requirement (not sameness with today).
6. **Avatar customization parity** — smooth pass keeps the palette surface;
   USDZ avatar blocked on the tint-material convention.
7. **Scope creep toward realism** — V4's naming + find-time metrics are the
   definition of done, not screenshot beauty. Readability wins every tie.
