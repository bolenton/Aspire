# Lantern meadow asset ledger

The meadow replaces the old model, procedural scenery and audio set. The old Swift client is untouched. Newly acquired audio is stored in `Clients/Lantern.Unity/Assets/StreamingAssets/Meadow`; no legacy audio folder or sample Fox model is staged into the Unity client.

| Asset | Source | License / changes |
| --- | --- | --- |
| Explorer.glb, Ember.glb, Meadow.glb, Acorn.glb, RiverBell.glb, LanternFlower.glb, GardenStar.glb | Original Lantern Blender authoring in `scripts/art/` | Project source; exported meshes with named character pivots and PBR material parameters. Procedural pose animation, not a motion-capture rig. |
| LanternMeadow.png | OpenAI image generation for Lantern | New title illustration. Used only as menu artwork, never presented as an in-engine screenshot. |
| MeadowScore.mp3 | [Childhood by Scott Buckley](https://www.scottbuckley.com.au/library/childhood/) | [CC BY 4.0](https://creativecommons.org/licenses/by/4.0/). Loudness normalization, short fade-in, MP3 encoding. |
| Birds.wav, River.wav | [Park ambiences by Thimras](https://opengameart.org/content/park-ambiences) | CC0. Edited into crossfaded loops, leveled; river is mono for positioning. |
| Footstep0–3.wav, Bell.wav, Acorn.wav, Oak.wav | [Impact Sounds by Kenney](https://kenney.nl/assets/impact-sounds) | CC0. Grass and bell recordings; low-pass filtering, level adjustment, padding/resampling. Song notes pitch the recorded bell, replacing the synthesized tone generator. |

Required credit, included in the app's credits and bundled `Meadow/Credits/AssetCredits.txt`:

> 'Childhood' by Scott Buckley - released under CC-BY 4.0. www.scottbuckley.com.au

The expansion adds an original brass river bell, sunflower gateway, lantern flower, wishing star, seating and planting borders. `scripts/art/garden.py` owns these new shapes. The world shader adds restrained surface variation, a slow leaf breeze and water ripples; it preserves the character materials. Modifier evaluation happens before material batching so a stem cannot cause the entire grass field to be subdivided.

The model sources are deterministic. Run Blender 4.5 LTS with `--background --python scripts/art/build_assets.py -- all`. Meshes go into the Unity StreamingAssets meadow folder; Blender source scenes and preview renders go into ignored `.artifacts/art`. These preview renders are different from actual Unity screenshots under `.artifacts/unity`.

The title image is saved at `Clients/Lantern.Unity/Assets/Lantern/Art/Resources/LanternMeadow.png`. Prompt:

> Use case: stylized-concept. Asset type: illustrated title-screen background for Lantern, a premium 3D adventure for a visually impaired 9-year-old. Create a polished 16:9 landscape game key-art image of a welcoming storybook meadow in warm late-afternoon light. A broad gently curving pale sandstone path leads from the foreground to an enormous beautiful ancient oak with a small inviting round door, warm golden window light and hanging lanterns. Crafted tree bark, layered leafy canopies, a little arched stone bridge over a turquoise stream, large ivory and coral flowers along the edges, rolling hills and distant blue-green woodland. The middle path is clear and uncluttered. The tree has elegant organic structure, not a stack of balls. Highly art-directed stylized 3D animation feature quality, tactile materials, soft contact shadows, atmospheric depth, beautiful restrained highlights, clear readable silhouettes. Keep the left third darker and quiet for separately rendered menu text, with the main oak in the right half. No text, no logos, no UI, no people, no watermark. Lush and magical without visual noise or harsh glare. This is an illustrated title asset, not a gameplay screenshot.

A production quality target is not a certification: the scene still needs evaluation by the intended player, device frame-time measurements and further art direction. The original meshes and title illustration should not be described as commercially produced AAA assets.
