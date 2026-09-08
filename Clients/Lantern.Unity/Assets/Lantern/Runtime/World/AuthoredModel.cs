using System;
using System.IO;
using System.Threading.Tasks;
using GLTFast;
using GLTFast.Logging;
using UnityEngine;

namespace Lantern.Unity.World
{
    /// <summary>Owns the imported meshes and materials for one authored asset.</summary>
    public sealed class AuthoredModel : MonoBehaviour
    {
        private GltfImport importer;

        public async Task LoadAsync(string asset)
        {
            importer = new GltfImport(logger: new ConsoleLogger());
            var path = Path.Combine(Application.streamingAssetsPath, "Meadow", asset + ".glb");
            if (!await importer.Load(new Uri(path).AbsoluteUri))
                throw new InvalidDataException($"The {asset} artwork could not be loaded.");
            if (this == null) return;
            if (!await importer.InstantiateMainSceneAsync(transform))
                throw new InvalidDataException($"The {asset} scene could not be created.");
        }

        private void OnDestroy() => importer?.Dispose();
    }
}
