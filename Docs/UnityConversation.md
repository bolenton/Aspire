# Ember conversation in the Unity client

The Unity client can use Apple's on-device language model for short, friendly conversations. It also includes authored stories, a joke, reassurance and local navigation commands, which work without that model. Speech recognition already requests on-device processing; raw audio and conversation transcripts are not saved by Lantern or sent to a backend.

## Player experience

Tap Ember or the microphone, then speak. The existing microphone gets a clear activity ring while listening, thinking or speaking. Tap it again while listening or thinking to cancel. Touch movement, pause, a new request, an activity change, and backgrounding invalidate pending answers. A model answer cannot move the player, unlock an object, or complete an activity.

Examples: “Tell me a story,” “Tell me a joke,” “Take me to the tree,” “Where is the river bell?” and “Stop.” Familiar names such as tree, home, river, bridge, garden and star resolve through aliases on the authored entities. Unknown explicit destinations do not start movement. Nearby guidance says to tap the object; there is no obsolete large action-button instruction.

Pause → Comfort settings → Ember's voice and conversation shows device availability, a built-in-only option, sample story/joke actions, and Forget this conversation. The choice is saved; old saves default to using the on-device model when available. No account, API key or service subscription is needed.

## Boundaries

- `Lantern.Core/Companion/CompanionCommands` owns deterministic commands and route checks. Generated text has no action capability.
- `CompanionConversation` owns cancellation and the eight-second fallback deadline, including providers that ignore cancellation.
- `CompanionSmallTalk` provides authored fallback responses. These are not presented as model-generated replies.
- `ConversationPrompt` sends current scene, quest, hint and up to six available nearby entities, plus at most four recent exchanges kept in memory. It does not receive the save vault, child-name setting, avatar or journals.
- `AppleConversation` implements the provider behind Unity's native bridge, owns the short conversation window, and discards expired callbacks. History clears on a changed activity, backgrounding, explicit Forget, or switching conversation mode.
- `LanternConversation.swift` creates a fresh Foundation Models session with the current context. Apple's default guardrails stay enabled. Output is short and intended for speech. The instructions guide style and grounding; they are not a guarantee that every generated sentence will be appropriate or factually correct.
- `VoiceIndicator` owns the small visual status ring and spoken control labels. `AdventureController` continues to coordinate navigation and activity interaction.

Apple Intelligence hardware, iOS/iPadOS 26+, an enabled Apple Intelligence setting, supported language/region, and a downloaded model are required for generation. Unavailable models, rejected generations, and timeouts use authored responses. The editor uses authored responses. There is no remote provider or Docker backend in this phase; `IConversationProvider` remains the extension point for a later self-hosted service.

## Verification

Core checks cover familiar/unknown/locked destinations, commands bypassing the model, generated text having no action, timeout fallback even with an uncooperative provider, omission of locked places, saved preferences, and discarding a reply superseded by Stop.

Development builds accept `LANTERN_VERIFY_CONVERSATION=1` with `LANTERN_START_ADVENTURE=1`. This sends an authored test question through the actual controller/provider, reports model availability and latency, then cancels a follow-up. Only this opt-in check logs its authored test reply. It does not exercise microphone recognition and must not be described as a physical voice test.

On the actual iPad Pro 11-inch (4th generation), build 8 reported model availability, generated a firefly-story reply in 5.97 seconds, and passed cancellation of a follow-up. All 20 core checks and the final 13-activity native playthrough passed. The existing normal save was preserved. Evidence is in `.artifacts/unity/ipad-conversation-build8.log` and `.artifacts/unity/ipad-playthrough-build8.log`.

Physical acceptance still includes microphone permission, a spoken conversation, VoiceOver control announcements, interruptions, and the child's comfort with voice/timing. A successful generated test reply is not a comprehensive model-content evaluation.

## Apple references

[Generating content with Foundation Models](https://developer.apple.com/documentation/foundationmodels/generating-content-and-performing-tasks-with-foundation-models) and [generation options](https://developer.apple.com/documentation/foundationmodels/generationoptions). API signatures were also checked against the installed Xcode 26.6 iOS SDK and the native bridge was type-checked with the iOS 18 deployment target.
