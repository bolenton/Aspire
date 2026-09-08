namespace Lantern.Core.Gameplay
{
    public enum TravelPace { Gentle, Comfortable, Brisk }

    /// <summary>Shared speeds for walking, guidance and companion following.</summary>
    public static class TravelSettings
    {
        public static float WalkSpeed(TravelPace pace) => pace switch
        {
            TravelPace.Gentle => 1.85f,
            TravelPace.Brisk => 3.5f,
            _ => 2.8f
        };
        public static float GuideSpeed(TravelPace pace) => WalkSpeed(pace) * 1.15f;
    }
}
