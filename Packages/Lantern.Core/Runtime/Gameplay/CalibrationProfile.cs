#nullable enable
namespace Lantern.Core.Gameplay
{
    public enum ContrastTheme { LightOnDark, DarkOnLight, HighContrastYellow }
    public enum HintAggressiveness { Gentle, Standard, Eager }

    public sealed class CalibrationProfile
    {
        public string ChildName { get; set; } = "";
        public bool ShowMovementControl { get; set; }
        public bool ShowCaptions { get; set; }
        public bool UseFamilyServer { get; set; } = true;
        public bool OnDeviceConversation { get; set; } = true;
        public TravelPace TravelPace { get; set; } = TravelPace.Comfortable;
        public double TextScale { get; set; } = 2;
        public ContrastTheme ContrastTheme { get; set; }
        public double SpeechRate { get; set; } = 1;
        public double SpeechPitch { get; set; } = 1;
        public HintAggressiveness HintAggressiveness { get; set; } = HintAggressiveness.Standard;
        public double WorldVolume { get; set; } = 1;
        public double NarrationVolume { get; set; } = 1;
        public double MusicVolume { get; set; } = 0.8;
        public bool TapToTalkEnabled { get; set; } = true;
    }
}
