#nullable enable
using System;
using System.IO;
using Lantern.Core.Content;

namespace Lantern.Core.Persistence
{
    public sealed class VaultStore
    {
        private readonly string path;
        private bool canWrite;
        public VaultStore(string path) => this.path = path;
        public PlayerVault Load()
        {
            canWrite = false;
            if (!File.Exists(path)) { canWrite = true; return new PlayerVault(); }
            // A parse/validation failure is surfaced. Never overwrite unreadable progress.
            var vault = Parse(File.ReadAllText(path));
            canWrite = true;
            return vault;
        }
        public static PlayerVault Parse(string json)
        {
            var vault = StoryJson.Read<PlayerVault>(json);
            if (vault.SchemaVersion != 1 || vault.Calibration == null || vault.Slots == null || vault.SharedJournal == null)
                throw new InvalidDataException("This save version cannot be read. The original file has been preserved.");
            foreach (var slot in vault.Slots)
                if (slot.Progress == null || slot.Journal == null || slot.Difficulty == null || string.IsNullOrEmpty(slot.Progress.CurrentSceneID))
                    throw new InvalidDataException("An adventure is incomplete in this save. The original file has been preserved.");
            return vault;
        }
        public void Save(PlayerVault vault)
        {
            if (!canWrite) throw new InvalidOperationException("Load the save successfully before writing.");
            var json = StoryJson.Write(vault);
            Parse(json);
            Directory.CreateDirectory(Path.GetDirectoryName(Path.GetFullPath(path))!);
            var temporary = path + ".tmp";
            File.WriteAllText(temporary, json);
            if (File.Exists(path)) File.Replace(temporary, path, path + ".backup");
            else File.Move(temporary, path);
        }
    }
}
