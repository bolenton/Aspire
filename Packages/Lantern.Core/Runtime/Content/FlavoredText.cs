#nullable enable
using System;
using System.Collections.Generic;
using Newtonsoft.Json;
using Newtonsoft.Json.Linq;

namespace Lantern.Core.Content
{
    [JsonConverter(typeof(FlavoredTextConverter))]
    public sealed class FlavoredText
    {
        public string Base { get; set; } = "";
        public Dictionary<string, string> ByCompanion { get; set; } = new Dictionary<string, string>();
        public string Resolve(string? companionId) => companionId != null && ByCompanion.TryGetValue(companionId, out var value) ? value : Base;
        public static implicit operator FlavoredText(string value) => new FlavoredText { Base = value };
    }

    internal sealed class FlavoredTextConverter : JsonConverter<FlavoredText>
    {
        public override FlavoredText ReadJson(JsonReader reader, Type objectType, FlavoredText? existingValue, bool hasExistingValue, JsonSerializer serializer)
        {
            if (reader.TokenType == JsonToken.String) return new FlavoredText { Base = (string?)reader.Value ?? "" };
            if (reader.TokenType != JsonToken.StartObject) throw new JsonSerializationException("Spoken text must be a string or a companion-text object.");
            var token = JObject.Load(reader);
            return new FlavoredText
            {
                Base = token.Value<string>("base") ?? throw new JsonSerializationException("Spoken text is missing its base line."),
                ByCompanion = token["byCompanion"]?.ToObject<Dictionary<string, string>>(serializer) ?? new Dictionary<string, string>()
            };
        }

        public override void WriteJson(JsonWriter writer, FlavoredText? value, JsonSerializer serializer)
        {
            if (value == null) { writer.WriteNull(); return; }
            if (value.ByCompanion.Count == 0) { writer.WriteValue(value.Base); return; }
            writer.WriteStartObject();
            writer.WritePropertyName("base"); writer.WriteValue(value.Base);
            writer.WritePropertyName("byCompanion"); serializer.Serialize(writer, value.ByCompanion);
            writer.WriteEndObject();
        }
    }
}
