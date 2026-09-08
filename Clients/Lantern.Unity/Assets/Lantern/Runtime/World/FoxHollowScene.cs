using System.Collections.Generic;
using System.Threading.Tasks;
using Lantern.Core.Content;
using Lantern.Core.Gameplay;
using Lantern.Unity.Presentation;
using Unity.AI.Navigation;
using UnityEngine;
using UnityEngine.AI;
using UnityEngine.Rendering.Universal;

namespace Lantern.Unity.World
{
    // Story anchors and collision stay independent of the authored artwork.
    public sealed class FoxHollowScene : MonoBehaviour
    {
        public readonly Dictionary<string, Transform> Anchors = new Dictionary<string, Transform>();
        public PlayerMotor Player { get; private set; }
        public WorldPalette Palette { get; private set; }
        private Transform environment;
        private CompanionFollower companionFollower;
        private Transform companionArtwork;
        private DestinationMarker destination;
        private LandmarkMotion gardenFlower;
        private MeadowRewards rewards;
        private CharacterMotion emberMotion;
        private OrchardLife orchardLife;

        public async Task BuildAsync(SceneDefinition definition, GameProgress progress, CompanionDefinition companion, WorldPalette palette)
        {
            Palette = palette;
            gameObject.AddComponent<MeadowLighting>().Initialize();
            environment = new GameObject("Meadow landscape").transform;
            environment.SetParent(transform, false);
            await environment.gameObject.AddComponent<AuthoredModel>().LoadAsync("Meadow");
            if (this == null) return;
            gameObject.AddComponent<MeadowSurfaces>().Initialize(environment);
            var orchard=new GameObject("Lantern Orchard");orchard.transform.SetParent(transform,false);
            await orchard.AddComponent<AuthoredModel>().LoadAsync("Orchard");
            foreach(var renderer in orchard.GetComponentsInChildren<Renderer>())palette.Track(renderer.gameObject,SurfaceRole.Scenery);
            foreach (var renderer in environment.GetComponentsInChildren<Renderer>())
            {
                var role = renderer.name.StartsWith("Path") ? SurfaceRole.Path :
                    renderer.name.StartsWith("Oak") || renderer.name.StartsWith("Lantern") ? SurfaceRole.Landmark :
                    renderer.name.StartsWith("Water") ? SurfaceRole.Water : SurfaceRole.Scenery;
                palette.Track(renderer.gameObject, role);
            }
            var collision = new GameObject("Meadow navigation");
            collision.transform.SetParent(transform,false);
            collision.AddComponent<MeadowNavigation>().Build();
            foreach (var entity in definition.Entities)
            {
                if (!progress.IsPerceivable(entity, companion)) continue;
                var anchor = new GameObject(entity.Id).transform;
                anchor.SetParent(transform, false);
                anchor.position = Coordinates.Authored(entity.Position);
                if (entity.Id == "old_oak") anchor.position = new Vector3(0,0,13.8f);
                if (entity.Id == "glowing_acorn") anchor.position = new Vector3(2.1f,0,13.5f);
                Anchors.Add(entity.Id, anchor);
                if (entity.Id == "glowing_acorn") await CreateLandmarkAsync(anchor,"Acorn",1.2f,true);
                if (entity.Id == "river_bell") await CreateLandmarkAsync(anchor,"RiverBell",1,false);
                if (entity.Id == "lantern_flower") gardenFlower = await CreateLandmarkAsync(anchor,"LanternFlower",1,false);
                if (entity.Id == "garden_star") await CreateLandmarkAsync(anchor,"GardenStar",1.3f,true);
                if(entity.Id=="orchard_gate")await CreateLandmarkAsync(anchor,"OrchardGate",1,false);
                if(entity.Id=="moon_harp")await CreateLandmarkAsync(anchor,"MoonHarp",1,false);
                if(entity.Id=="moon_seed")await CreateLandmarkAsync(anchor,"MoonSeed",1.4f,true);
                if(entity.Id=="lantern_nest")await CreateLandmarkAsync(anchor,"LanternNest",1,false);
                if(entity.Id=="luma")
                {
                    await CreateLandmarkAsync(anchor,"Luma",1.35f,false);
                    var model=anchor.GetComponentInChildren<AuthoredModel>();model.transform.localRotation=Quaternion.identity;
                    model.gameObject.AddComponent<CharacterMotion>().Initialize(anchor);
                }
            }
            await CreatePlayerAsync();
            if(Anchors.TryGetValue("luma",out var owl))owl.gameObject.AddComponent<WoodlandFriend>().Explorer=Player.transform;
            var fox = new GameObject("Ember artwork");
            fox.transform.SetParent(Anchors[StoryPack.CompanionPlaceholder], false);
            fox.transform.localRotation = Quaternion.Euler(0,180,0);
            fox.transform.localScale = Vector3.one * 1.15f;
            await fox.AddComponent<AuthoredModel>().LoadAsync("Ember");
            if (this == null) return;
            companionArtwork = fox.transform;
            companionFollower = Anchors[StoryPack.CompanionPlaceholder].gameObject.AddComponent<CompanionFollower>();
            companionFollower.Initialize(Player.transform);
            emberMotion=fox.AddComponent<CharacterMotion>();emberMotion.Initialize(companionFollower.transform);
            palette.Track(fox, SurfaceRole.Companion);
            RefreshCompanion(progress);
            destination = new GameObject("Current destination").AddComponent<DestinationMarker>();
            destination.Initialize();
            rewards=gameObject.AddComponent<MeadowRewards>();rewards.Initialize();
            orchardLife=gameObject.AddComponent<OrchardLife>();orchardLife.Initialize();
#if UNITY_EDITOR || DEVELOPMENT_BUILD
            gameObject.AddComponent<DevelopmentCapture>();
            gameObject.AddComponent<DevelopmentFrameSample>();
#endif
        }

        public void SetCompanionExpression(bool listening,bool thinking,float speech,bool speaking)
        {if(emberMotion!=null)emberMotion.SetExpression(listening,thinking,speech,speaking);}

        public void RefreshCompanion(GameProgress progress)
        {
            if (companionFollower == null) return;
            var follow = progress.CompletedStepIDs.Contains("say_hello");
            companionFollower.Following = follow;
            if (follow) companionArtwork.localRotation = Quaternion.identity;
        }

        public void RefreshProgress(GameProgress progress, string targetID)
        {
            RefreshCompanion(progress);
            foreach(var id in new[] { "glowing_acorn", "garden_star", "moon_seed" })
            {
                var unlocked=progress.Flags.Contains(id=="glowing_acorn" ? "oak_awake" : id=="garden_star" ? "garden_awake" : "orchard_awake");
                if(Anchors.TryGetValue(id,out var collectible)) collectible.gameObject.SetActive(unlocked && !progress.Inventory.Contains(id));
            }
            gardenFlower?.SetBloom(progress.Flags.Contains("garden_awake"));
            rewards.Refresh(progress);
            orchardLife?.Refresh(progress.Flags.Contains("orchard_awake"),progress.Flags.Contains("orchard_restored"));
            var target=targetID!=null && Anchors.TryGetValue(targetID,out var anchor) ? anchor : null;
            destination.Follow(target);
            companionFollower.SetInterest(target);
        }

        private async Task<LandmarkMotion> CreateLandmarkAsync(Transform anchor,string asset,float scale,bool collectible)
        {
            var artwork = new GameObject(asset+" artwork");
            artwork.transform.SetParent(anchor,false); artwork.transform.localScale=Vector3.one*scale;
            if(collectible)artwork.transform.localPosition=Vector3.up*.85f;
            await artwork.AddComponent<AuthoredModel>().LoadAsync(asset);
            if(this==null)return null;
            Palette.Track(artwork,collectible ? SurfaceRole.Collectible : SurfaceRole.Landmark);
            var motion=artwork.AddComponent<LandmarkMotion>();motion.Initialize(collectible);
            return motion;
        }

        private async Task CreatePlayerAsync()
        {
            var root = new GameObject("Player");
            root.transform.SetParent(transform, false);
            root.AddComponent<NavMeshAgent>();
            Player = root.AddComponent<PlayerMotor>();
            var model = new GameObject("Explorer artwork");
            model.transform.SetParent(root.transform, false);
            await model.AddComponent<AuthoredModel>().LoadAsync("Explorer");
            if (this == null) return;
            model.AddComponent<CharacterMotion>().Initialize(root.transform);
            Palette.Track(model, SurfaceRole.Player);
            var cameraRoot = new GameObject("Main Camera");
            cameraRoot.tag = "MainCamera";
            var camera = cameraRoot.AddComponent<Camera>();
            camera.fieldOfView = 44;
            camera.nearClipPlane = .15f;
            camera.farClipPlane = 160;
            camera.clearFlags = CameraClearFlags.Skybox;
            camera.allowHDR = true;
            camera.GetUniversalAdditionalCameraData().renderPostProcessing = true;
            var listener = new GameObject("Body audio listener", typeof(AudioListener));
            listener.transform.SetParent(root.transform, false);
            listener.transform.localPosition = Vector3.up * 1.6f;
            var follow = cameraRoot.AddComponent<CalmCamera>();
            follow.Target = root.transform;
            follow.Obstacles = new[]
            {
                new Bounds(new Vector3(0,3,17),new Vector3(3.8f,6,3.8f)),
                new Bounds(new Vector3(17,1.9f,6),new Vector3(.85f,3.8f,3.6f)),
                new Bounds(new Vector3(-14,2,8),new Vector3(1,4.2f,4.4f)),
                new Bounds(new Vector3(-19,2.8f,10),new Vector3(1.2f,5.6f,1.2f)),
                new Bounds(new Vector3(-28,2.8f,13),new Vector3(1.2f,5.6f,1.2f)),
                new Bounds(new Vector3(-36,2.8f,10),new Vector3(1.2f,5.6f,1.2f)),
                new Bounds(new Vector3(-38,2.8f,3),new Vector3(1.2f,5.6f,1.2f)),
                new Bounds(new Vector3(-37,2.8f,-9),new Vector3(1.2f,5.6f,1.2f)),
                new Bounds(new Vector3(-28,2.8f,-10),new Vector3(1.2f,5.6f,1.2f)),
                new Bounds(new Vector3(-21,2.8f,-7),new Vector3(1.2f,5.6f,1.2f))
            };
            follow.Snap();
        }

    }
}
