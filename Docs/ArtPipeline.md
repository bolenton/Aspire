# Art pipeline — from prompt (or artist) to the glowing world

The engine never requires art. Every interactable renders today as a
procedural silhouette (`WorldBuilder.shape()`); a real 3D model is strictly
an upgrade that slots in over it, exactly like premium voices slot in over
AVSpeech. This document is the contract for that slot.

## The slot

`VisualSpec` (StoryEngine) carries an optional `assetName`:

```json
"visual": { "shape": "tree", "colorHex": "#FFD24A", "scale": 1.4,
            "glow": 1.2, "assetName": "old_oak" }
```

At build time `WorldBuilder` tries
`Assets/Art/Models/<assetName>.usdz` first and falls back to the
procedural `shape` on any failure — missing file, bad USDZ, load error.
Rules:

- **The `shape` key stays the semantic identity.** Content must always
  name a shape that reads on its own; `assetName` is presentation only.
- **High-contrast mode ignores assets** and always renders the procedural
  silhouette in forced `#FFE000`. That mode's promise is shape-only
  recognition; textured art would break it.
- Markers, halos, blob shadows, and the quest beacon attach around the
  model exactly as they do around procedural shapes.

## Producing models

Text-to-3D services (Meshy, Tripo3D, Rodin) or a commissioned artist →
GLB → Apple Reality Converter (or `usdzconvert`) → USDZ in
`Assets/Art/Models/`.

Conventions every model must follow:

- **≤ 15k triangles, ≤ 2048² textures.** The whole scene budget assumes
  cheap meshes; LOD is not implemented (revisit past ~150k visible tris).
- **1 unit = 1 meter.** `VisualSpec.scale` multiplies the model as-is.
- **Pivot at ground-center, facing −Z** (RealityKit forward). The marker
  floats at the model's visual bounds top, so a sunken pivot puts the
  chip in the ground.
- **Authored emissive map** matching the game's glow language — objects
  should carry their own light the way the procedural shapes do, or they
  will read as dark holes among the glowing primitives (and the bloom
  pass will ignore them).

## Companions

Meshy/Tripo auto-rig → USDZ with skeletal clips (idle / hop / flap),
played via `availableAnimations`. The procedural voxel critter remains
the fallback. (Companion models are not yet wired — the critter path in
`WorldBuilder.build` runs first; wiring `assetName` for companions is a
follow-up once rigged models exist.)

## Licensing — the ledger discipline

Record every asset in `ASSETS.md`: tool (or artist), tier/contract,
prompt, date. Paid tiers of the text-to-3D services grant commercial use
of outputs; AI-generated geometry is likely uncopyrightable on its own
(US Copyright Office guidance), so the ledger is the protection — it
proves provenance and terms for everything that ships. Nothing lands in
`Assets/Art/Models/` without a ledger row.
