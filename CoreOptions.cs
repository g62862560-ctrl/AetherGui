using System.Text.Json;

namespace AetherGui;

sealed class CoreOptions
{
    public string[] Arguments { get; set; } = [];
    public Dictionary<string, string> EnvironmentVariables { get; set; } = new();
    public int StartupSeconds { get; set; } = 300;
    public string PsiphonRegion { get; set; } = "";
    public bool IsConfigured => Arguments.Length != 0 || EnvironmentVariables.Count != 0 || PsiphonRegion.Length != 0;
    public bool HasPsiphonRegionOverride => Arguments.Any(a => a == "--psiphon-region" || a.StartsWith("--psiphon-region=", StringComparison.Ordinal))
        || EnvironmentVariables.Keys.Any(k => k.Equals("AETHER_PSIPHON_REGION", StringComparison.OrdinalIgnoreCase));

    public static string NormalizePsiphonRegion(string? region)
    {
        var code = (region ?? "").Trim().ToUpperInvariant();
        if (!Psiphon.Countries.Any(c => c.Code == code)) throw new FormatException("Unknown Psiphon country. Choose Automatic or a listed country.");
        return code;
    }
    private static readonly JsonSerializerOptions Json = new() { WriteIndented = true };
    private static readonly string FilePath = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "AetherGui", "core-options.json");
    private static readonly HashSet<string> ManagedFlags = new(StringComparer.Ordinal)
    {
        "--bind", "--http-proxy", "--tor-bind", "--tor-http", "--psiphon-bind", "--psiphon-http",
        "--masque", "--wg", "--wireguard", "--warp", "--gool", "--wiw", "--mim", "--masque-in-masque",
        "--gool-classic", "--protocol", "--tor", "--tor-only", "--tor-reverse", "--psiphon", "--psiphon-only", "--psiphon-reverse",
        "--help", "help", "--version", "--register"
    };
    private static readonly HashSet<string> ManagedEnvironment = new(StringComparer.OrdinalIgnoreCase)
    {
        "AETHER_SOCKS", "AETHER_HTTP_PROXY", "AETHER_TOR_BIND", "AETHER_TOR_HTTP",
        "AETHER_PSIPHON_BIND", "AETHER_PSIPHON_HTTP", "AETHER_PROTOCOL", "AETHER_TOR", "AETHER_PSIPHON"
    };

    public string ArgumentsJson => JsonSerializer.Serialize(Arguments, Json);
    public string EnvironmentJson => JsonSerializer.Serialize(EnvironmentVariables, Json);

    public static CoreOptions Parse(string arguments, string environment, int seconds, string? psiphonRegion = null)
    {
        var args = JsonSerializer.Deserialize<string[]>(arguments) ?? throw new FormatException("Arguments must be a JSON array of strings.");
        var env = JsonSerializer.Deserialize<Dictionary<string, string>>(environment) ?? throw new FormatException("Environment must be a JSON object of strings.");
        if (seconds is < 30 or > 3600) throw new FormatException("Startup timeout must be 30–3600 seconds.");
        foreach (var arg in args)
            if (arg is null || arg.Contains('\0') || ManagedFlags.Contains(arg.Split('=')[0]))
                throw new FormatException("Arguments contain an app-managed option or invalid value.");
        var normalized = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var (key, value) in env)
        {
            if ((!key.StartsWith("AETHER_", StringComparison.Ordinal) && key != "RUST_LOG") ||
                ManagedEnvironment.Contains(key) || key.Contains('=') || key.Contains('\0') || value is null || value.Contains('\0') ||
                !normalized.TryAdd(key, value))
                throw new FormatException("Environment contains an app-managed key or invalid value.");
        }
        return new CoreOptions { Arguments = args, EnvironmentVariables = normalized, StartupSeconds = seconds, PsiphonRegion = NormalizePsiphonRegion(psiphonRegion) };
    }

    public static CoreOptions Load() => Load(FilePath);

    internal static CoreOptions Load(string path)
    {
        if (!File.Exists(path)) return new();
        var data = JsonSerializer.Deserialize<CoreOptions>(File.ReadAllText(path)) ?? throw new FormatException("Invalid settings.");
        return Parse(data.ArgumentsJson, data.EnvironmentJson, data.StartupSeconds, data.PsiphonRegion);
    }

    public void Save() => Save(FilePath);

    internal void Save(string path)
    {
        var validated = Parse(ArgumentsJson, EnvironmentJson, StartupSeconds, PsiphonRegion);
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temp = path + ".tmp";
        File.WriteAllText(temp, JsonSerializer.Serialize(new { Arguments, EnvironmentVariables, StartupSeconds, validated.PsiphonRegion }, Json));
        File.Move(temp, path, true);
    }
}
