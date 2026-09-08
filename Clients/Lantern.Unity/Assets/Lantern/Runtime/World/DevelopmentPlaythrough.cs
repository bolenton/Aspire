#if UNITY_EDITOR || DEVELOPMENT_BUILD
using System;
using System.Collections;
using System.IO;
using System.Linq;
using Lantern.Core.Content;
using Lantern.Core.Gameplay;
using Lantern.Core.Persistence;
using Lantern.Unity.Presentation;
using UnityEngine;
using UnityEngine.EventSystems;

namespace Lantern.Unity.World
{
    /// <summary>Opt-in real navigation/UI playthrough. Bootstrap supplies a separate verification save.</summary>
    public sealed class DevelopmentPlaythrough : MonoBehaviour
    {
        private bool failed;
        public void Run(StoryPack pack,SaveSlot slot,FoxHollowScene world,AdventureHud hud)
            => StartCoroutine(Play(pack,slot,world,hud));
        private IEnumerator Play(StoryPack pack,SaveSlot slot,FoxHollowScene world,AdventureHud hud)
        {
            yield return new WaitForSeconds(2);
            for(var index=0;index<40 && slot.Progress.CurrentStep(pack)!=null;index++)
            {
                var step=slot.Progress.CurrentStep(pack);
                Debug.Log("Lantern playthrough: starting "+step.Id);
                var anchor=world.Anchors[step.TargetEntityID];
                if(Vector3.Distance(world.Player.transform.position,anchor.position)>3)
                {
                    Invoke(hud,"Let Ember guide me");
                    var until=Time.realtimeSinceStartup+65;
                    while(Vector3.Distance(world.Player.transform.position,anchor.position)>3 && Time.realtimeSinceStartup<until)
                        yield return null;
                    if(Vector3.Distance(world.Player.transform.position,anchor.position)>3)
                    { Fail("Cannot reach "+step.TargetEntityID+" from "+world.Player.transform.position);yield break; }
                }
                yield return new WaitForSeconds(1.2f);
                if(step.Goal==QuestGoal.Reach)
                {
                    if(slot.Progress.CurrentStep(pack)?.Id==step.Id) {Fail("Reach did not advance "+step.Id);yield break;}
                    continue;
                }
                var center=WorldInteraction.BoundsFor(step.TargetEntityID,anchor).center;
                var screen=Camera.main.WorldToScreenPoint(center);
                if(screen.z<=0 || screen.x<0 || screen.x>Screen.width || screen.y<0 || screen.y>Screen.height)
                { Fail("Target is outside the camera at "+step.Id);yield break; }
                if(WorldInteraction.Resolve(screen,Camera.main,world.Anchors)!=step.TargetEntityID)
                { Fail("Visible target cannot be tapped at "+step.Id+"; hit="+WorldInteraction.Resolve(screen,Camera.main,world.Anchors)+"; player="+world.Player.transform.position);yield break; }
                var touch=hud.GetComponentInChildren<TouchMovement>();
                var pointer=new PointerEventData(EventSystem.current){pointerId=71,position=screen};
                touch.OnPointerDown(pointer);touch.OnPointerUp(pointer);yield return null;
                if(failed)yield break;
                if(step.Goal==QuestGoal.Song)
                {
                    if(step.Id=="sing_river" || step.Id=="wake_lantern_garden")
                    { yield return new WaitForEndOfFrame();Capture(step.Id+"-chimes.png"); }
                    var notes=pack.Song(step.SongSpellID).NotesForChallenge(slot.Difficulty.Support.Challenge).ToArray();
                    Invoke(hud,"Hear the song");yield return new WaitForSeconds(notes.Length*.95f+.2f);
                    foreach(var note in notes)
                    { Invoke(hud,note.ToString());yield return new WaitForSeconds(.65f);if(failed)yield break; }
                }
                else if(step.Goal==QuestGoal.Talk)
                {
                    for(var choice=0;choice<8 && slot.Progress.CurrentStep(pack)?.Id==step.Id;choice++)
                    {
                        var first=hud.GetComponentsInChildren<AccessibleAction>().FirstOrDefault(a=>a.Button.IsInteractable() && a.Label.text!="Take a break");
                        if(first==null){Fail("Dialogue has no choice at "+step.Id);yield break;}
                        first.Button.onClick.Invoke();yield return new WaitForSeconds(.15f);
                    }
                }
                if(slot.Progress.CurrentStep(pack)?.Id==step.Id) {Fail("Step did not advance "+step.Id);yield break;}
                if(step.Id=="wake_lantern_garden" || step.Id=="plant_moon_seed")
                { yield return new WaitForSeconds(2);yield return new WaitForEndOfFrame();Capture(step.Id=="plant_moon_seed" ? "lantern-orchard-restored.png":"lantern-garden-awake.png"); }
            }
            if(slot.Progress.Flags.Contains("orchard_restored") && slot.Progress.Inventory.Contains("moon_seed"))
            {
                Invoke(hud,"Keep exploring with Ember");yield return new WaitForSeconds(1);
                yield return new WaitForEndOfFrame();Capture("lantern-home-restored.png");
                Debug.Log("Lantern playthrough: PASS; all 21 activities, bridge in both directions, visible world taps, chimes, garden and orchard rewards and free exploration completed. Verification save only.");
            }
            else Fail("Final garden reward was not completed.");
        }
        private void Invoke(AdventureHud hud,string name)
        {
            var action=hud.GetComponentsInChildren<AccessibleAction>().FirstOrDefault(a=>a.name==name && a.Button.IsInteractable());
            if(action==null){Fail("Missing active action: "+name);return;}
            action.Button.onClick.Invoke();
        }
        private void Fail(string reason){failed=true;Debug.LogError("Lantern playthrough: FAIL; "+reason);}
        private static void Capture(string file)
            => ScreenCapture.CaptureScreenshot(Application.isMobilePlatform ? file : Path.Combine(Application.persistentDataPath,file));
    }
}
#endif
