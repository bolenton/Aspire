using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using Lantern.Core.Content;
using Lantern.Core.Gameplay;
using Lantern.Core.Persistence;
using Lantern.Unity.Audio;
using Lantern.Unity.Companion;
using Lantern.Unity.Platform;
using Lantern.Unity.Presentation;
using Lantern.Unity.Story;
using Lantern.Unity.World;
using UnityEngine;
using UnityEngine.AI;

namespace Lantern.Unity.Composition
{
    public sealed class LanternBootstrap : MonoBehaviour
    {
        private PlayerVault vault;
        private SaveSlot slot;
        private VaultStore store;
        private StoryPack pack;
        private CompanionDefinition companion;
        private WorldPalette palette;
        private AdventureHud hud;
        private CompanionVoice voice;
        private CompanionConnection server;
        private AppleConversation conversation;
        private FoxHollowScene world;
        private AdventureController adventure;
        private Camera menuCamera;
        private bool starting;

        private void Start()
        {
            Application.targetFrameRate = 60;
            Screen.sleepTimeout = SleepTimeout.NeverSleep;
            palette = new WorldPalette();
            try
            {
                var saveName = "vault.json";
                var verifying = false;
#if UNITY_EDITOR || DEVELOPMENT_BUILD
                verifying = Environment.GetEnvironmentVariable("LANTERN_VERIFY_EXPANSION") == "1";
                if(verifying) saveName = "verification-vault.json";
#endif
                store = new VaultStore(Path.Combine(Application.persistentDataPath,saveName));
                var loaded = store.Load();
                vault = verifying ? new PlayerVault() : loaded;
                pack = StoryJson.Read<StoryPack>(File.ReadAllText(Path.Combine(Application.streamingAssetsPath, "StoryPacks/MeadowJourney/pack.json")));
                var roster = StoryJson.Read<CompanionRoster>(File.ReadAllText(Path.Combine(Application.streamingAssetsPath, "StoryPacks/Companions/roster.json")));
                StoryJson.Validate(pack, roster);
                companion = roster.Companions.Single(c => c.Id == "ember");
                palette.SetTheme(vault.Calibration.ContrastTheme);
                CreateHud();
                slot = vault.Slots.Where(s => s.StoryPackID == pack.Id && s.CompanionID == companion.Id && s.Progress.CurrentSceneID == "fox_hollow").OrderByDescending(s => s.LastPlayedAt).FirstOrDefault();
                var choices = new List<(string, Action)>();
                if (slot != null) choices.Add(("Continue with Ember", () => StartAdventure(false)));
                choices.Add(("Begin a new adventure", () => StartAdventure(true)));
                choices.Add(("Art credits", ShowCredits));
                hud.ShowTitle(choices);
#if UNITY_EDITOR || DEVELOPMENT_BUILD
                // Exercise device-only startup failures without requiring a manual menu tap.
                if (Environment.GetEnvironmentVariable("LANTERN_START_ADVENTURE") == "1")
                    StartAdventure(slot == null);
#endif
            }
            catch (Exception error)
            {
                Debug.LogException(error);
                vault = new PlayerVault(); CreateHud();
                hud.ShowChoices("Lantern could not open this adventure. Your saved file has been kept unchanged.", new List<(string, Action)> { ("Try again", () => UnityEngine.SceneManagement.SceneManager.LoadScene(0)) });
            }
        }
        private void CreateHud()
        {
            if (hud != null) return;
            menuCamera = new GameObject("Menu backdrop").AddComponent<Camera>();
            menuCamera.clearFlags = CameraClearFlags.SolidColor;
            menuCamera.backgroundColor = palette.Background;
            menuCamera.cullingMask = 0;
            menuCamera.depth = -100;
            hud = new GameObject("Lantern interface", typeof(RectTransform)).AddComponent<AdventureHud>();
            hud.Initialize(palette, vault.Calibration);
            var native = new GameObject("Speech").AddComponent<AppleSpeech>(); native.Initialize(vault.Calibration);
            server = new GameObject("Ember server connection").AddComponent<CompanionConnection>();
            voice = new GameObject("Ember voice").AddComponent<CompanionVoice>();voice.Initialize(native,server,vault.Calibration);
            server.SetEnabled(vault.Calibration.UseFamilyServer);server.Initialize();
            conversation = new GameObject("Conversation").AddComponent<AppleConversation>(); conversation.Initialize(vault.Calibration);
        }
        private async void StartAdventure(bool create)
        {
            if (starting) return;
            starting = true;
            try
            {
                if (create) slot = vault.CreateSlot(pack, companion);
                if (slot.Progress.CurrentStep(pack) == null) slot.Progress.SelectNextQuest(pack);
                hud.ShowChoices("Ember is getting ready…", Array.Empty<(string, Action)>());
                world = new GameObject("Fox Hollow").AddComponent<FoxHollowScene>();
                await world.BuildAsync(pack.Scene("fox_hollow"), slot.Progress, companion, palette);
                if (this == null) return;
                world.Player.SetPace(vault.Calibration.TravelPace);
                Destroy(menuCamera.gameObject);
                palette.SetTheme(vault.Calibration.ContrastTheme);
                if (slot.PlayerPosition.HasValue && NavMesh.SamplePosition(Coordinates.Runtime(slot.PlayerPosition.Value), out var location, 3, NavMesh.AllAreas))
                    world.Player.GetComponent<NavMeshAgent>().Warp(location.position);
                world.Player.transform.rotation = Quaternion.Euler(0, (float)slot.BodyYawDegrees, 0);
                Camera.main.GetComponent<CalmCamera>().Snap();
                var soundscape = gameObject.AddComponent<WorldSoundscape>();
                soundscape.Initialize(pack.Scene("fox_hollow"), (float)vault.Calibration.WorldVolume);
                await world.Player.gameObject.AddComponent<MeadowFootsteps>().InitializeAsync();
                var instrument = gameObject.AddComponent<SongInstrument>();
                await instrument.InitializeAsync();
                if (this == null) return;
                adventure = gameObject.AddComponent<AdventureController>();
                adventure.Initialize(pack, slot, companion, world, hud, voice, soundscape, instrument, Save, new ServerConversation(server,voice,conversation), server);
                hud.Settings += ShowSettings;
                Save();
                Debug.Log("Lantern adventure ready: Fox Hollow.");
#if UNITY_EDITOR || DEVELOPMENT_BUILD
                if(Environment.GetEnvironmentVariable("LANTERN_VERIFY_EXPANSION")=="1")
                    gameObject.AddComponent<DevelopmentPlaythrough>().Run(pack,slot,world,hud);
                if(Environment.GetEnvironmentVariable("LANTERN_VERIFY_CONVERSATION")=="1")
                    gameObject.AddComponent<DevelopmentConversation>().Run(adventure,conversation);
#endif
            }
            catch (Exception error)
            {
                Debug.LogException(error);
                world?.Player?.Stop();
                hud.ShowChoices("The adventure could not start. Your previous save is safe. Please check the build's content and audio files.", new List<(string, Action)> { ("Try again", () => UnityEngine.SceneManagement.SceneManager.LoadScene(0)) });
            }
        }
        private bool Save()
        {
            if (world == null || slot == null) return false;
            slot.PlayerPosition = Coordinates.Snapshot(world.Player.transform.position);
            slot.BodyYawDegrees = world.Player.Yaw;
            slot.LastPlayedAt = DateTime.UtcNow;
            try { store.Save(vault); return true; }
            catch (Exception error) { Debug.LogException(error); hud.Say("We couldn't save this time. Please keep Lantern open so a grown-up can help."); return false; }
        }
        private void ShowSettings()
        {
            adventure.Stop();
            void SetTheme(ContrastTheme theme)
            { vault.Calibration.ContrastTheme = theme; palette.SetTheme(theme); Save(); hud.RefreshTheme(); }
            hud.ShowChoices("Choose what feels comfortable", new List<(string, Action)>
            {
                ("Light on dark", () => SetTheme(ContrastTheme.LightOnDark)),
                ("Dark on light", () => SetTheme(ContrastTheme.DarkOnLight)),
                ("Yellow on black", () => SetTheme(ContrastTheme.HighContrastYellow)),
                ("Larger words", () => { vault.Calibration.TextScale = Math.Min(4, vault.Calibration.TextScale + .5); Save(); hud.RefreshTheme(); }),
                ("Smaller words", () => { vault.Calibration.TextScale = Math.Max(1, vault.Calibration.TextScale - .5); Save(); hud.RefreshTheme(); }),
                ("Travel pace: " + vault.Calibration.TravelPace, ShowTravelSettings),
                ("Ember's voice and conversation", ShowConversationSettings),
                (vault.Calibration.ShowMovementControl ? "Hide movement control" : "Show movement control", () => { vault.Calibration.ShowMovementControl = !vault.Calibration.ShowMovementControl; Save(); hud.ResumeAdventure(); }),
                (vault.Calibration.ShowCaptions ? "Hide captions" : "Show captions", () => { vault.Calibration.ShowCaptions = !vault.Calibration.ShowCaptions; Save(); hud.ResumeAdventure(); }),
                ("Center headphone sounds", SpatialAudioBridge.Recenter),
                ("Back to adventure", hud.ResumeAdventure)
            });
        }
        private void ShowTravelSettings()
        {
            void SetPace(TravelPace pace)
            { vault.Calibration.TravelPace = pace; world.Player.SetPace(pace); Save(); hud.ResumeAdventure(); }
            hud.ShowChoices("Choose our walking pace", new List<(string,Action)>
            {
                ("Gentle", () => SetPace(TravelPace.Gentle)),
                ("Comfortable", () => SetPace(TravelPace.Comfortable)),
                ("Brisk", () => SetPace(TravelPace.Brisk)),
                ("Back", ShowSettings)
            });
        }
        private void ShowConversationSettings()
        {
            hud.ShowChoices(server.Status + " " + (server.Connected ? "Whisper listens and Piper speaks on your family server. Recent conversation is remembered for this adventure." : conversation.Status), new List<(string,Action)>
            {
                (vault.Calibration.UseFamilyServer ? "Use on-device voice instead" : "Use family server voice", () => {adventure.Stop();vault.Calibration.UseFamilyServer=!vault.Calibration.UseFamilyServer;server.SetEnabled(vault.Calibration.UseFamilyServer);Save();ShowConversationSettings();}),
                (vault.Calibration.OnDeviceConversation ? "Use built-in conversation only" : "Enable on-device conversation", () =>
                {
                    adventure.Stop(); conversation.ForgetConversation();
                    vault.Calibration.OnDeviceConversation = !vault.Calibration.OnDeviceConversation;
                    Save(); ShowConversationSettings();
                }),
                ("Hear a little story", () => { hud.ResumeAdventure(); _ = adventure.AskAsync("Tell me a little story"); }),
                ("Hear a joke", () => { hud.ResumeAdventure(); _ = adventure.AskAsync("Tell me a joke"); }),
                ("Forget this conversation", () => { adventure.Stop(); conversation.ForgetConversation(); server.Forget(); ShowConversationSettings(); }),
                ("Back", ShowSettings)
            });
        }
        private void ShowCredits()
        {
            hud.ShowChoices("Original Lantern meadow, explorer and Ember artwork. Park field recordings: Thimras (CC0). Music: Childhood by Scott Buckley, released under CC-BY 4.0. www.scottbuckley.com.au. Foley: Kenney (CC0). Title illustration generated for Lantern. Full sources and credits are included with the project.",
                new List<(string, Action)> { ("Back", () => UnityEngine.SceneManagement.SceneManager.LoadScene(0)) });
        }
        private void OnApplicationQuit() { if (adventure != null) Save(); }
        private void OnDestroy() => palette?.Dispose();
    }
}
