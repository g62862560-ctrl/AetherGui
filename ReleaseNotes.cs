namespace AetherGui;

static class ReleaseNotes
{
    public static string ForVersion(Version version)
    {
        using var reader = new StreamReader(typeof(ReleaseNotes).Assembly.GetManifestResourceStream("release_notes.txt")!);
        var lines = new List<string>();
        var matching = false;
        while (reader.ReadLine() is { } line)
        {
            if (line.StartsWith("## ", StringComparison.Ordinal))
            {
                if (matching) break;
                matching = line == $"## {version}";
            }
            else if (matching) lines.Add(line);
        }
        return string.Join(Environment.NewLine, lines).Trim();
    }

    public static bool ShouldShow(Version current, string? lastSeen, bool hadSettings) =>
        Aether.ParseVersion(lastSeen) is { } previous ? current > previous : hadSettings;
}
