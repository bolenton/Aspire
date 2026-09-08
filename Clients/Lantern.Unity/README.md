# Lantern Unity port

Lantern Meadow replaces the first prototype artwork and its permanent button bar. **Touch anywhere and drag to walk; release to stop. Tap a character or destination to interact.** Pause, voice and guided travel use three small icon controls. A visible joystick and captions are optional in Comfort settings. The default walk speed is 2.8 m/s and guided speed is 3.22 m/s; Gentle, Comfortable and Brisk options are saved in Travel pace. The adventure now continues across the bridge to the lantern garden and back home, with 13 activities and free exploration afterward. Songs use marked touch chimes over the world. The meadow has newly authored characters and scenery, a newly licensed score, field recordings and recorded foley. It is not a finished replacement for the Swift app. See [the implementation status](../../Docs/UnityPortStatus.md) and [engine assessment](../../Docs/EnginePortAssessment.md).


Ember now supports on-device conversation using Apple Foundation Models on eligible devices, with authored stories, jokes and reassurance when the model is unavailable. Navigation commands always resolve locally. Tap the microphone or Ember to talk; tap again while listening/thinking to cancel. The microphone has a quiet activity ring, and conversation choices live under Comfort settings. See [the conversation architecture and device requirements](../../Docs/UnityConversation.md).

## Open and build

1. Complete the license agreement and license activation in Unity Hub.
2. Install **Unity 6000.3.23f1, Apple Silicon**, with **iOS Build Support**. Allow space for the editor, iOS module, imports, and Xcode build output. Do not put the Unity editor directly on ExFAT.
3. Add this directory as a project in Hub. The checked-in settings select **Input System Package** under **Player → Other Settings → Active Input Handling**. If Unity prompts to enable the backend, allow the Editor to restart. The editor initialization prepares the URP assets, copies the story contracts, and creates `Assets/Lantern/Scenes/FoxHollow.unity`. If needed, use **Lantern → Prepare Fox Hollow**.
4. Open FoxHollow and press Play. Focus the Game view to receive input. The Editor supports mouse drag, world taps and WASD; native speech and PHASE are for iOS. Space or Escape stops movement. Use **Assets → Refresh** after external script edits if the Editor has not recompiled. **Lantern → Diagnostics → Check visible button targets** reports which UI object receives a hit at each visible button's center.
5. Use **Lantern → Build iOS Xcode project**, or run from the repository root:

```bash
bash scripts/unity-build.sh
```

For a non-default editor location, set `LANTERN_UNITY_EDITOR` to the editor executable. Set `LANTERN_BUILD_PATH` to move the exported Xcode project. The build log is `.artifacts/unity/editor-build.log`.

### Current Mac storage setup

Unity 6000.3.23f1 and iOS Build Support are installed under `/Applications/Unity/Hub/Editor` and registered in Hub. Account sign-in and license activation are complete.

The external drive became unavailable during the meadow work. The current ignored `Library` symlink uses `.artifacts/unity-library`, and the native export/build use `.artifacts/unity/iOS` and `.artifacts/unity/DerivedData`. To return to the existing external cache after reconnecting that drive, first quit Unity and mount its APFS image:

```bash
hdiutil attach /Volumes/Untitled/LanternDevelopment/UnityWorkspace.sparsebundle
```

With that volume mounted, the Library symlink can be repointed to `/Volumes/LanternDevelopment/Caches/Aspire/UnityLibrary`. Export the Xcode project from the repository root using:

```bash
LANTERN_BUILD_PATH=/Volumes/LanternDevelopment/Builds/Lantern/iOS bash scripts/unity-build.sh
```

Keep Xcode DerivedData on this volume too. This storage layout is local to this Mac; other checkouts can use a normal `Library` directory. The sparse image has an 80 GB capacity and occupies space as it fills.

### iOS application identity

The prototype bundle ID is `com.bolenton.Lantern.UnitySlice`. It can be installed alongside the original app. The exporter enables automatic signing without selecting or changing an account, team, certificate, or profile. The original Lantern Xcode project uses team `M899BRL953`; pass that existing team when building this separate prototype on this Mac:

```bash
xcodebuild \
  -project /Volumes/LanternDevelopment/Builds/Lantern/iOS/Unity-iPhone.xcodeproj \
  -scheme Unity-iPhone -configuration Debug -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath /Volumes/LanternDevelopment/Builds/Lantern/DerivedData \
  -allowProvisioningUpdates DEVELOPMENT_TEAM=M899BRL953 build
```

Exporting an Xcode project is not the same as building, installing, or running the app. This command builds a development app for local device testing; it does not upload a release.

## Structure

- `Packages/Lantern.Core` at repository root is the engine-independent C# package: authored content, quest state, adaptive support, saves, and companion commands.
- `Assets/Lantern/Runtime/World` owns scene geometry, the animated fox, camera, navigation, and coordinate conversion.
- `Assets/Lantern/Runtime/Presentation` owns the HUD, contrast materials, safe-area layout, and screen-reader hierarchy.
- `Assets/Lantern/Runtime/Story` connects gameplay events to the core.
- `Assets/Lantern/Runtime/Audio` owns audio playback and the forgiving song instrument.
- `Assets/Lantern/Runtime/Platform` and `Assets/Plugins/iOS` contain the narrow native speech, on-device conversation, PHASE, and headphone-motion boundaries.
- `Assets/Lantern/Runtime/Composition` loads content and saves, then connects these components.
- `Assets/Lantern/Editor` prepares reproducible project assets and exports the iOS project.

The Unity adventure is authored in `Content/MeadowJourney/pack.json`; its original quest and save IDs remain compatible with the earlier meadow. Story JSON is staged from its source directories. `scripts/prepare-unity-content.py` copies only those contracts. New GLB models and sound files are in `Assets/StreamingAssets/Meadow`; the illustration is in `Assets/Lantern/Art/Resources`. No legacy WAVs, music, USDZs or sample Fox model are used. Rebuild art with Blender and `scripts/art/build_assets.py`; rebuild sound with `scripts/art/prepare_audio.py`. See the [asset ledger](../../Docs/UnityAssetLedger.md) for licenses and exact sources. Gameplay does not download assets.

## Dependencies

Unity URP 17.3.0 provides rendering. AI Navigation 2.0.14 provides the NavMesh used by both manual and assisted movement. Input System 1.17.0 and uGUI 2.0.0 provide input and UI. Unity glTFast 6.15.1 loads the new authored GLB models. Newtonsoft JSON 13.0.3 in the .NET build, and Unity's supported 3.2.2 package, preserve the original mixed string/object dialogue JSON.

The selected dependencies are pinned, and `packages-lock.json` was generated by the first successful Unity import. The initial build explicitly includes the runtime shaders to avoid a fox that works in the Editor but turns pink on device. After device verification, capture the used shader variants to reduce build size.

## Critical checks

Use the [device check](../../Docs/UnityDeviceCheck.md) for the physical quest, VoiceOver, speech, contrast, and headphone checks.

Development builds can exercise normal adventure startup directly, using the current save or creating a first slot when none exists:

```bash
xcrun devicectl device process launch --device 'Orange iPhone' \
  --terminate-existing --environment-variables '{"LANTERN_START_ADVENTURE":"1"}' \
  --console com.bolenton.Lantern.UnitySlice
```

Require `Lantern adventure ready: Fox Hollow.` in the device log and check for exceptions. This startup flag is excluded from non-development builds. Set `LANTERN_CAPTURE=1` to write an actual gameplay screenshot into the app Documents directory. `LANTERN_VERIFY_INPUT=1` additionally exercises drag, release and second-finger isolation, restores the starting pose, and records the result in the log. Set `LANTERN_VERIFY_EXPANSION=1` with automatic startup to run all 13 activities through real navigation and UI actions. This uses a fresh `verification-vault.json`, keeping `vault.json` and the player’s progress separate. It captures the river chimes, awakened garden and restored home. `LANTERN_CAPTURE=1` also logs a 20-second main-thread frame sample after warmup; this is not a GPU or sustained thermal benchmark. Set `LANTERN_VERIFY_CONVERSATION=1` in a separate run to exercise an authored test question through the native model and cancel a follow-up; the microphone itself is not exercised. These checks do not replace the intended player trying the controls. The linker entries retain required runtime component types.

```bash
dotnet test Tests/Lantern.Core.Tests/Lantern.Core.Tests.csproj
swift test --package-path Packages/StoryEngine
```

The C# test project is at repository root, not inside this client directory. It includes a synthetic save produced by the current Swift engine, with no real child data.

The port uses a separate app data container. Its save decoder can read the tested legacy format, but an on-device import/export flow between the two apps has **not** been implemented. Do not uninstall the original app to transfer saves.
