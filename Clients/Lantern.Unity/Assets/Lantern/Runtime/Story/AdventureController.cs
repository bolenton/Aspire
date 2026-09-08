using System;
using System.Collections.Generic;
using System.Linq;
using System.Threading;
using Lantern.Core.Companion;
using Lantern.Core.Content;
using Lantern.Core.Gameplay;
using Lantern.Core.Persistence;
using Lantern.Unity.Audio;
using Lantern.Unity.Companion;
using Lantern.Unity.Platform;
using Lantern.Unity.Presentation;
using Lantern.Unity.World;
using UnityEngine;
using UnityEngine.InputSystem;

namespace Lantern.Unity.Story
{
    public sealed class AdventureController : MonoBehaviour
    {
        private StoryPack pack;
        private SaveSlot slot;
        private CompanionDefinition companion;
        private FoxHollowScene world;
        private AdventureHud hud;
        private CompanionVoice voice;
        private CompanionConnection server;
        private bool conversationOpen;
        private float listenAgainAt, nextWorldUpdate;
        private WorldSoundscape sounds;
        private SongInstrument instrument;
        private Func<bool> save;
        private CompanionConversation conversation;
        private bool thinking;
        private int conversationRevision;
        private readonly CancellationTokenSource lifetime = new CancellationTokenSource();
        private string lastWords = "";
        public string LastWords => lastWords;
        public bool IsThinking => thinking;
        private long revision;
        private float stepStarted;
        private int hintsUsed;
        private SongActivity songActivity;
        private bool keyboardMoving;
        private SceneDefinition Scene => pack.Scene(slot.Progress.CurrentSceneID);
        private QuestStep CurrentStep => slot.Progress.CurrentStep(pack);

        public void Initialize(StoryPack story, SaveSlot adventure, CompanionDefinition friend, FoxHollowScene scene, AdventureHud presentation, CompanionVoice speech, WorldSoundscape audio, SongInstrument songs, Func<bool> saveAdventure, IConversationProvider provider, CompanionConnection connection)
        {
            pack = story; slot = adventure; companion = friend; world = scene; hud = presentation;
            voice = speech; sounds = audio; instrument = songs; save = saveAdventure;
            server = connection;
            conversation = new CompanionConversation(provider, TimeSpan.FromSeconds(40));
            songActivity = new SongActivity(instrument,hud,voice,Say);
            instrument.NotePlayed += hud.HighlightNote;
            hud.Stop += Stop;
            hud.Guide += Guide;
            hud.Interact += Interact;
            hud.Repeat += () => Say(lastWords);
            hud.Talk += Talk;
            hud.Step += (forward, turn) => world.Player.Step(forward, turn);
            hud.Movement += Move;
            hud.MovementReleased += world.Player.Stop;
            hud.WorldTapped += TapWorld;
            voice.Recognized += Ask;
            voice.Partial += OnPartial;
            voice.Failed += message => { conversationOpen=false; world.Player.Stop(); hud.Say(message); };
            voice.BusyChanged += sounds.Duck;
            voice.BusyChanged += busy => { RefreshVoiceState(); if(!busy)listenAgainAt=Time.time+.4f; };
            world.Player.Arrived += () => { Say("We're here. Take your time."); CheckReach(); };
            world.Player.RouteFailed += () => Say("I couldn't finish that path. We've stopped safely. Let's try another way.");
            stepStarted = Time.time;
            RefreshWorld();
            hud.ShowAdventure(ActionLabel());
            if (CurrentStep == null) CompleteAdventure();
            else if(slot.Progress.CompletedStepIDs.Count>0) Say("Welcome back. "+CurrentStep.Intro.Resolve(companion.Id));
            else Say("Welcome to the meadow. Touch anywhere and slide your finger to walk. Lift your finger to stop. Tap Ember to say hello. We can take our time.");
        }
        public void Stop()
        {
            conversationOpen=false;
            world.Player.Stop(); voice.Stop(); instrument.Stop(); conversation?.Cancel();
            conversationRevision++; thinking = false; RefreshVoiceState();
        }
        private void Talk()
        {
            var cancel = conversationOpen;
            Stop(); hud.ShowAdventure(ActionLabel());
            if (cancel) return;
            conversationOpen=true;
            hud.Say("I'm listening. Ask for help, a story, or a chat.");
            voice.Listen();
        }
        private void Move(Vector3 direction)
        {
            if (thinking || voice.IsListening) Stop();
            world.Player.MoveWorld(direction);
        }
        private void RefreshVoiceState() => hud.SetVoiceState(voice.IsListening ? VoiceState.Listening : voice.Audible ? VoiceState.Speaking : thinking || voice.Processing ? VoiceState.Thinking : VoiceState.Idle);
        public void Say(string words) { PublishWorld(); lastWords = words; hud.Say(words); voice.Speak(words); }
        private void OnPartial(string words)
        {
            if (CompanionConversation.LocalCommand(words, new WorldObservation())?.Action == CompanionAction.Stop)
            { Stop(); hud.Say("Stopped. We can take our time."); }
        }
        private async void Ask(string words) => await AskAsync(words);
        public async System.Threading.Tasks.Task AskAsync(string words)
        {
            var continueTalking=conversationOpen;
            Stop();
            conversationOpen=continueTalking;
            PublishWorld();
            var request = ++conversationRevision;
            var observed = Observe();
            thinking = true; RefreshVoiceState();
            try
            {
                var reply = await conversation.ReplyAsync(words, companion, observed, lifetime.Token);
                if (this == null || observed.Revision != revision || request != conversationRevision) return;
                if (reply.Action == CompanionAction.Stop) Stop();
                else if (reply.Action == CompanionAction.GuideToTarget) GuideTo(reply.TargetID);
                else if (reply.Action == CompanionAction.Interact) { Interact(); return; }
                thinking = false;
                Say(reply.Text);
            }
            catch (OperationCanceledException) { }
            catch (Exception error) { Debug.LogException(error); Say("I'm here. Tap the compass and I will guide us."); }
            finally { if (this != null && request == conversationRevision) { thinking = false; RefreshVoiceState(); } }
        }
        public WorldObservation Observe()
        {
            var observation = new WorldObservation
            {
                Revision = revision, SceneName = Scene.Name,
                PlayerPosition = Coordinates.Snapshot(world.Player.transform.position), BodyYawDegrees = world.Player.Yaw,
                Quest = pack.Quest(slot.Progress.ActiveQuestID)?.SpokenSummary.Resolve(companion.Id) ?? "We can explore together.",
                Hint = CurrentStep == null ? "The meadow is full of light. We can keep exploring together." : slot.Difficulty.Hint(CurrentStep, companion.Id), TargetID = CurrentStep?.TargetEntityID
            };
            foreach (var entity in Scene.Entities)
            {
                if (!world.Anchors.TryGetValue(entity.Id, out var anchor) || slot.Progress.Inventory.Contains(entity.Id)) continue;
                var observed = world.Player.Observe(entity.Id, entity.Id == StoryPack.CompanionPlaceholder ? companion.Name : entity.Name, anchor.position);
                observed.Available = slot.Progress.IsAvailable(entity);
                observed.Aliases = entity.VoiceAliases;
                observed.LockedExplanation = entity.LockedExplanation?.Resolve(companion.Id);
                var distance = Vector3.Distance(world.Player.transform.position, anchor.position);
                var hearingRange = (entity.Sound?.FarRadius ?? 0) * companion.HearingMultiplier;
                observed.InAwarenessRange = distance <= Math.Max(8, hearingRange);
                observed.SoundDescription = observed.Available && distance <= hearingRange ? entity.Sound?.SpokenDescription ?? "" : "";
                observation.Entities.Add(observed);
            }
            return observation;
        }
        private void Guide()
        {
            Stop();
            hintsUsed++;
            var observed = Observe();
            if (observed.Target == null) { Say("We can rest here together."); return; }
            if (GuideTo(observed.TargetID)) Say("I'll guide us. You can stop at any time.");
            else Say(Guidance.DescribeRoute(observed, observed.Target));
        }
        private bool GuideTo(string id)
        {
            var entity = Scene.Entities.FirstOrDefault(e => e.Id == id);
            return entity != null && slot.Progress.IsAvailable(entity) && world.Anchors.TryGetValue(id, out var anchor) && world.Player.Guide(anchor.position);
        }
        private void Update()
        {
            if (world == null) return;
            if(Time.time>=nextWorldUpdate){nextWorldUpdate=Time.time+2;PublishWorld();}
            if(conversationOpen && hud.IsAdventure && !thinking && !voice.IsListening && !voice.IsSpeaking && Time.time>=listenAgainAt)
            {listenAgainAt=Time.time+1;voice.Listen();}
            RefreshVoiceState();
            world.SetCompanionExpression(voice.IsListening,(thinking||voice.Processing)&&!voice.Audible,voice.SpeechLevel,voice.Audible);
            sounds.Pose(world.Player.transform.position, world.Player.Yaw);
            if (!hud.IsAdventure || voice.IsListening) return;
            var keyboard = Keyboard.current;
            if (keyboard != null)
            {
                if (keyboard.escapeKey.wasPressedThisFrame || keyboard.spaceKey.wasPressedThisFrame) Stop();
                else
                {
                    var input = new Vector2((keyboard.dKey.isPressed ? 1 : 0) - (keyboard.aKey.isPressed ? 1 : 0), (keyboard.wKey.isPressed ? 1 : 0) - (keyboard.sKey.isPressed ? 1 : 0));
                    if (input.sqrMagnitude > 0) { if (thinking) Stop(); world.Player.Move(input); }
                    else if (keyboardMoving) world.Player.Stop();
                    keyboardMoving = input.sqrMagnitude > 0;
                }
            }
            CheckReach();
        }
        private void TapWorld(Vector2 position)
        {
            if (!hud.IsAdventure) return;
            var closest = WorldInteraction.Resolve(position,Camera.main,world.Anchors);
            if (closest != null && closest == CurrentStep?.TargetEntityID) Interact();
            else if (closest == StoryPack.CompanionPlaceholder)
            { Talk(); }
            else if(closest != null) ExploreLandmark(closest);
        }
        private void ExploreLandmark(string id)
        {
            Stop();
            var entity=Scene.Entities.FirstOrDefault(e=>e.Id==id);
            if(entity==null)return;
            if(!slot.Progress.IsAvailable(entity)) { Say(entity.LockedExplanation?.Resolve(companion.Id) ?? "This light is resting.");return; }
            if(!IsNear(id)) { GuideTo(id);Say("Let us visit the "+entity.Name+".");return; }
            Stop();
            if(CurrentStep==null && (id=="river_bell" || id=="lantern_flower" || id=="old_oak" || id=="moon_harp"))
            {
                var song=id=="river_bell" ? "river_song" : id=="lantern_flower" ? "garden_song" : id=="moon_harp" ? "starlight_song" : "oak_song";
                songActivity.Begin(pack.Song(song),slot.Difficulty.Support.Challenge,
                    ()=> {hud.ShowAdventure(ActionLabel());Say("Lovely! We can play again whenever you like.");},
                    ()=> {Stop();hud.ShowAdventure(ActionLabel());});
                return;
            }
            if(id=="river_bell") { instrument.Play(SolfegeNote.Do);Say("The river bell sings to the water. The stone bridge leads to our lantern garden."); }
            else if(id=="lantern_flower") Say(slot.Progress.Flags.Contains("garden_awake") ? "Our lantern flower is awake. Look at that warm little light." : "A whole garden is dreaming inside this flower.");
            else if(id=="old_oak") Say("The old oak is our friend. Its golden windows always welcome us home.");
            else Say(entity.Description.Length>0 ? entity.Description : "Here is the "+entity.Name+". We can take our time.");
        }
        private void CheckReach()
        {
            var step = CurrentStep;
            if (step?.Goal == QuestGoal.Reach && IsNear(step.TargetEntityID)) CompleteStep(QuestGoal.Reach);
        }
        private bool IsNear(string id) => world.Anchors.TryGetValue(id, out var anchor) && Vector3.Distance(world.Player.transform.position, anchor.position) <= 3;
        private string ActionLabel() => CurrentStep?.Goal switch
        { QuestGoal.Talk => "Say hello", QuestGoal.Song => "Sing together", QuestGoal.Collect => "Collect light", _ => "Explore" };
        private void Interact()
        {
            var step = CurrentStep;
            if (step == null) { CompleteAdventure(); return; }
            if (!IsNear(step.TargetEntityID)) { Guide(); return; }
            Stop();
            var entity = Scene.Entities.Single(e => e.Id == step.TargetEntityID);
            if (!slot.Progress.IsAvailable(entity)) { Say(entity.LockedExplanation?.Resolve(companion.Id) ?? "That is still resting."); return; }
            if (step.Goal == QuestGoal.Talk) ShowDialogue(entity.DialogueID);
            else if (step.Goal == QuestGoal.Song) BeginSong(step);
            else CompleteStep(step.Goal);
        }
        private void ShowDialogue(string id)
        {
            var dialogue = pack.Dialogue(id);
            if (dialogue == null) { Say("We can talk again soon."); return; }
            var choices = dialogue.Choices.Where(c => c.RequiresCompanion == null || c.RequiresCompanion == companion.Id)
                .Select(choice => (choice.Text.Resolve(companion.Id), (Action)(() =>
                {
                    if (choice.MemoryKey != null) slot.Journal.Events.Add(new MemoryEvent { Kind = MemoryKind.Choice, Key = choice.MemoryKey, Value = choice.MemoryValue ?? "", SpokenRecap = choice.Text.Resolve(companion.Id), CompanionID = companion.Id });
                    if (choice.NextDialogueID == null) CompleteStep(QuestGoal.Talk); else ShowDialogue(choice.NextDialogueID);
                }))).ToList();
            if (choices.Count == 0) choices.Add(("Continue", () => CompleteStep(QuestGoal.Talk)));
            choices.Add(("Take a break", () => { Stop(); save(); hud.ShowAdventure(ActionLabel()); }));
            hud.ShowChoices(dialogue.Line.Resolve(companion.Id), choices);
            Say(dialogue.Line.Resolve(companion.Id));
        }
        private void BeginSong(QuestStep step) => songActivity.Begin(pack.Song(step.SongSpellID),slot.Difficulty.Support.Challenge,
            () => CompleteStep(QuestGoal.Song), () => { Stop();hud.ShowAdventure(ActionLabel()); });

        private void CompleteStep(QuestGoal goal)
        {
            var step = CurrentStep;
            if (step == null) return;
            var completed = slot.Progress.Complete(pack, step.TargetEntityID, goal);
            if (completed == null) return;
            revision++; conversation.Cancel(); world.Player.Stop();
            slot.Difficulty.Record(new TelemetrySample { Kind = goal == QuestGoal.Song ? ActivityKind.Song : goal == QuestGoal.Talk ? ActivityKind.Dialogue : ActivityKind.Navigation, Succeeded = true, Duration = Time.time - stepStarted, HintsUsed = hintsUsed });
            stepStarted = Time.time; hintsUsed = 0;
            if(CurrentStep==null) slot.Progress.SelectNextQuest(pack);
            RefreshWorld();
            if (!save()) { Stop(); return; }
            if (CurrentStep == null) { CompleteAdventure(); return; }
            hud.ShowAdventure(ActionLabel());
            Say(completed.Celebration.Resolve(companion.Id) + " " + CurrentStep.Intro.Resolve(companion.Id));
        }
        private void PublishWorld()
        {
            if(server==null || world==null || slot==null)return;
            server.SetWorld(AdventureWorld.Build(pack,slot,Observe(),world.Player.transform.position.x < -14 ? "Lantern Orchard" : "Lantern Meadow",hud.IsAdventure ? "Exploring" : hud.PageTitle));
        }
        private void RefreshWorld()
        {
            world.RefreshProgress(slot.Progress,CurrentStep?.TargetEntityID);
            sounds.Refresh(Scene, slot.Progress, world.Anchors,CurrentStep?.TargetEntityID);
            PublishWorld();
        }
        private void CompleteAdventure()
        {
            Stop();
            var saved = save();
            var celebration = "You made a home for the light! The oak, garden and orchard are glowing. Luma and Ember are celebrating with you. " + (saved ? "Your adventure is saved." : "We could not save yet. Please keep Lantern open and ask a grown-up for help.");
            hud.ShowChoices(celebration, new List<(string, Action)> { ("Keep exploring with Ember", () => hud.ShowAdventure(ActionLabel())), ("Hear that again", () => Say(celebration)), ("Rest here", Stop) });
            Say(celebration);
        }
        private void OnApplicationPause(bool pause) { if (pause && world != null) { Stop(); save(); } }
        private void OnDestroy() { if(instrument!=null && hud!=null) instrument.NotePlayed -= hud.HighlightNote; lifetime.Cancel(); conversation?.Dispose(); lifetime.Dispose(); }
    }
}
