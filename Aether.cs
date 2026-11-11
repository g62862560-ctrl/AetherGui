using System.Diagnostics;
using System.IO.Compression;
using System.Net;
using System.Net.Sockets;
using System.Security.Cryptography;
using System.Text;

namespace AetherGui;

// How one protocol has done on this device: connects that worked, tries that failed, speed and recency (LastOk: epoch seconds, 0 = never).
record ProtocolStat(int Ok = 0, int Fail = 0, long TotalMs = 0, long LastOk = 0)
{
    public int Tries => Ok + Fail;
    public long AvgMs => Ok == 0 ? 0 : TotalMs / Ok;

    // Good works for you, Bad mostly fails, Maybe has too few tries, New was never tried.
    public string Verdict => Tries == 0 ? "new"
        : Ok == 0 && Fail >= 2 ? "bad"
        : Tries < 3 ? "maybe"
        : Ok / (double)Tries >= 0.6 ? "good" : "bad";
}

record Preset(string Name, string Args, int StartupSecs = Aether.FastSecs, string HttpFlag = "--http-proxy", bool AutoByDefault = false)
{
    public bool ManualOnly => StartupSecs > Aether.FastSecs && !AutoByDefault;
    public string Label => ManualOnly ? Name + " (manual)" : Name;
}

// Everything about aether.exe itself: where it lives, downloading it, starting it, and testing its tunnel.
static class Aether
{
    public const string DefaultTestUrl = "http://www.gstatic.com/generate_204";
    // Offered in Core settings; the user may also type any http(s) URL.
    public static readonly string[] TestUrlSuggestions =
    [
        DefaultTestUrl,
        "http://cp.cloudflare.com/generate_204",
        "https://www.google.com/generate_204",
        "https://www.cloudflare.com/cdn-cgi/trace",
        "http://www.msftconnecttest.com/connecttest.txt",
    ];
    public const int GoodPingMs = 300, SlowPingMs = 800; // ping colors: below good green, below slow amber, else red
    private const int ConnectTimeoutMs = 10_000; // after the proxy is up, the internet test must pass within this
    // The core's own listeners; users and the system proxy use the mixed ProxyPort in front of them.
    public const int SocksPort = 1818;           // SOCKS5, also used for the delay test
    public const int CoreHttpPort = 1823;        // HTTP CONNECT
    private const int InnerPort = 1822;          // base listener when tor/psiphon serves the SOCKS exit
    private const int TorDefault = 1820, PsiphonDefault = 1821; // the core's own --tor-bind/--psiphon-bind defaults, used by the reverse modes
    public const int DefaultProxyPort = 1819;    // what the system proxy used before ports were mixed
    private const string PortsKey = @"Software\AetherGui";

    // Read from the registry on every use, so the --watchdog copy always matches what the GUI last set.
    public static int ProxyPort
    {
        get
        {
            using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(PortsKey);
            return key?.GetValue("ProxyPort") is int p && ValidPort(p) is null ? p : DefaultProxyPort;
        }
        set
        {
            using var key = Microsoft.Win32.Registry.CurrentUser.CreateSubKey(PortsKey);
            key.SetValue("ProxyPort", value);
        }
    }

    public static string TestUrl
    {
        get
        {
            using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(PortsKey);
            return key?.GetValue("TestUrl") is string u && ValidTestUrl(u) is null ? u : DefaultTestUrl;
        }
        set
        {
            using var key = Microsoft.Win32.Registry.CurrentUser.CreateSubKey(PortsKey);
            key.SetValue("TestUrl", value);
        }
    }

    public static bool RealDelayTest
    {
        get
        {
            using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(PortsKey);
            return key?.GetValue("RealDelayTest") is not 0;
        }
        set
        {
            using var key = Microsoft.Win32.Registry.CurrentUser.CreateSubKey(PortsKey);
            key.SetValue("RealDelayTest", value ? 1 : 0);
        }
    }

    // null when usable, otherwise why not.
    public static string? ValidTestUrl(string text) =>
        Uri.TryCreate(text.Trim(), UriKind.Absolute, out var u) && u.Scheme is "http" or "https" && u.Host.Length > 0
            ? null : "Delay test URL must be a full http:// or https:// URL.";

    // null when usable, otherwise why not.
    public static string? ValidPort(int port) =>
        port is < 1024 or > 65535 ? "Port must be 1024-65535."
        : port is SocksPort or >= TorDefault and <= CoreHttpPort ? $"Ports {SocksPort} and {TorDefault}-{CoreHttpPort} are used internally." : null;

    private static readonly string Dir = AppContext.BaseDirectory; // aether.exe lives beside this exe
    private static readonly string Exe = Path.Combine(Dir, "aether.exe");

    private const string Warp = " --turbo -4 --quick-reconnect";
    public const int FastSecs = 30; // default Auto attempt budget; slow Psiphon routes can also be included

    // The protocol menu aether itself offers. Tor/Psiphon bootstrap slowly (tor tries 75s plainly, then bridges;
    // psiphon waits up to 180s), so they get longer startup budgets. Four Psiphon routes are in Auto by request.
    // The "alone" modes don't serve --http-proxy, so they expose their own HTTP proxy flag on the same port.
    public static readonly Preset[] Presets =
    {
        new("MASQUE", "--masque" + Warp),
        new("WireGuard", "--wg" + Warp),
        new("WARP-in-WARP (gool)", "--gool-classic" + Warp), // v2.3 renamed the classic carrier
        new("MASQUE-in-MASQUE", "--mim" + Warp),
        new("Tor alone", "--tor-only", 300, "--tor-http"),
        new("Tor + WARP", "--tor-reverse" + Warp, 300),         // warp reached via tor, exit via warp
        new("Psiphon alone", "--psiphon-only", 240, "--psiphon-http"),
        new("Psiphon + WARP", "--psiphon-reverse" + Warp, 240), // warp reached via psiphon, exit via warp
        // Append: existing registry protocol indexes must remain stable.
        new("MASQUE HTTP/2", "--masque --h2" + Warp),
        new("MASQUE HTTP/2 + fragmentation", "--masque --h2 --fragment" + Warp),
        new("MASQUE-in-MASQUE HTTP/2", "--mim --h2" + Warp),
        new("MASQUE → Tor", "--masque --tor" + Warp, 300, "--tor-http"),
        new("MASQUE HTTP/2 → Tor", "--masque --h2 --tor" + Warp, 300, "--tor-http"),
        new("WireGuard → Tor", "--wg --tor" + Warp, 300, "--tor-http"),
        new("WARP-in-WARP → Tor", "--gool-classic --tor" + Warp, 300, "--tor-http"),
        new("MASQUE-in-MASQUE → Tor", "--mim --tor" + Warp, 300, "--tor-http"),
        new("MASQUE → Psiphon", "--masque --psiphon" + Warp, 240, "--psiphon-http"),
        new("MASQUE HTTP/2 → Psiphon", "--masque --h2 --psiphon" + Warp, 240, "--psiphon-http", true),
        new("WireGuard → Psiphon", "--wg --psiphon" + Warp, 240, "--psiphon-http", true),
        new("WARP-in-WARP → Psiphon", "--gool-classic --psiphon" + Warp, 240, "--psiphon-http", true),
        new("MASQUE-in-MASQUE → Psiphon", "--mim --psiphon" + Warp, 240, "--psiphon-http", true),
        new("WireGuard-in-MASQUE (gool)", "--gool" + Warp),
        new("WireGuard-in-MASQUE HTTP/2", "--gool --h2" + Warp),
    };

    // Preferred Psiphon routes stay at the top of the main protocol list and fresh Auto order.
    private static readonly string[] PreferredAutoPresets =
    [
        "MASQUE HTTP/2 → Psiphon",
        "MASQUE-in-MASQUE → Psiphon",
        "WARP-in-WARP → Psiphon",
    ];

    private static int PreferredPriority(string name)
    {
        var i = Array.IndexOf(PreferredAutoPresets, name);
        return i < 0 ? PreferredAutoPresets.Length : i;
    }

    // Display order is separate from persisted preset indexes.
    public static readonly int[] MenuPresetIndexes = Enumerable.Range(0, Presets.Length)
        .OrderBy(i => Presets[i].ManualOnly)
        .ThenBy(i => Presets[i].ManualOnly ? 0 : PreferredPriority(Presets[i].Name))
        .ThenBy(i => i)
        .ToArray();

    public static int NextPresetIndex(int current)
    {
        var position = Array.IndexOf(MenuPresetIndexes, current);
        return MenuPresetIndexes[(position + 1) % MenuPresetIndexes.Length];
    }

    public static readonly Preset[] AutoPresets = Presets.Where(p => !p.ManualOnly).ToArray();

    // The saved Auto order as preset indexes, kept up to date by Rerank and editable by the user;
    // empty = not saved yet, rank by past connects. Saved as "3,0,8".
    public static int[] SavedOrder
    {
        get
        {
            using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(PortsKey);
            return ParseOrder(key?.GetValue("AutoOrder") as string);
        }
        set
        {
            using var key = Microsoft.Win32.Registry.CurrentUser.CreateSubKey(PortsKey);
            key.SetValue("AutoOrder", string.Join(",", value));
        }
    }

    // Unknown, malformed and repeated indexes are dropped.
    public static int[] ParseOrder(string? text) => (text ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries)
        .Select(s => int.TryParse(s, out var i) ? i : -1).Where(i => i >= 0 && i < Presets.Length).Distinct().ToArray();

    // A saved order is used as is. Otherwise the preferred Psiphon routes come first, then from past connects
    // (preset index -> ms to connect, -1 = failed last time): fastest first, then WireGuard on a fresh run,
    // then never tried, then failed; other ties shuffled (OrderBy is stable).
    public static List<Preset> AutoOrder(IReadOnlyDictionary<int, int> connectMs, int[]? saved = null) => saved is { Length: > 0 }
        ? saved.Select(i => Presets[i]).ToList()
        : AutoPresets
        .OrderBy(_ => Random.Shared.Next())
        .OrderBy(p => PreferredPriority(p.Name) < PreferredAutoPresets.Length ? 0 : 1)
        .ThenBy(p => PreferredPriority(p.Name))
        .ThenBy(p => SpeedKey(connectMs, Array.IndexOf(Presets, p)))
        .ThenBy(p => p.Name == "WireGuard" && !connectMs.ContainsKey(Array.IndexOf(Presets, p)) ? 0 : 1)
        .ToList();

    private static int SpeedKey(IReadOnlyDictionary<int, int> connectMs, int i) =>
        connectMs.TryGetValue(i, out var ms) ? (ms < 0 ? int.MaxValue : ms) : FastSecs * 1000;

    // After a connect attempt only the tested preset moves: before the first one that was slower (to the end if it failed).
    // Everything else keeps its place, so the user's own moves survive.
    public static int[] Rerank(int[] order, IReadOnlyDictionary<int, int> connectMs, int tested)
    {
        if (!order.Contains(tested)) return order;
        var rest = order.Where(i => i != tested).ToList();
        var key = SpeedKey(connectMs, tested);
        var at = rest.FindIndex(i => SpeedKey(connectMs, i) > key);
        rest.Insert(at < 0 ? rest.Count : at, tested);
        return rest.ToArray();
    }

    // Saved as "0:4200,8:-1"; unknown or malformed entries are dropped.
    public static Dictionary<int, int> ParseConnectMs(string? text) =>
        (text ?? "").Split(',', StringSplitOptions.RemoveEmptyEntries)
            .Select(e => e.Split(':'))
            .Where(kv => kv.Length == 2 && int.TryParse(kv[0], out var i) && i >= 0 && i < Presets.Length && int.TryParse(kv[1], out _))
            .GroupBy(kv => int.Parse(kv[0]))
            .ToDictionary(g => g.Key, g => int.Parse(g.Last()[1]));

    public static string FormatConnectMs(IReadOnlyDictionary<int, int> connectMs) =>
        string.Join(",", connectMs.Select(kv => $"{kv.Key}:{kv.Value}"));

    // Saved as "0:5:2:21000:1762850000;..." = preset:ok:fail:totalOkMs:lastOkEpochSeconds; bad entries are dropped.
    public static Dictionary<int, ProtocolStat> ParseStats(string? text) =>
        System.Text.RegularExpressions.Regex.Matches(text ?? "", @"(\d+):(\d+):(\d+):(\d+):(\d+)")
            .Where(m => int.Parse(m.Groups[1].Value) < Presets.Length)
            .GroupBy(m => int.Parse(m.Groups[1].Value))
            .ToDictionary(g => g.Key, g =>
            {
                var m = g.Last();
                return new ProtocolStat(int.Parse(m.Groups[2].Value), int.Parse(m.Groups[3].Value),
                    long.Parse(m.Groups[4].Value), long.Parse(m.Groups[5].Value));
            });

    public static string FormatStats(IReadOnlyDictionary<int, ProtocolStat> stats) =>
        string.Join(";", stats.Select(kv => $"{kv.Key}:{kv.Value.Ok}:{kv.Value.Fail}:{kv.Value.TotalMs}:{kv.Value.LastOk}"));

    // A real request through aether's SOCKS5 proxy measures the real delay.
    private static readonly HttpClient Http = new(new SocketsHttpHandler { Proxy = new WebProxy($"socks5://127.0.0.1:{SocksPort}") })
    { Timeout = TimeSpan.FromSeconds(3) };

    public const string GuiRepo = "g62862560-ctrl/AetherGui";
    private const string CoreRepo = "CluvexStudio/Aether";

    private static HttpClient GitHub(TimeSpan timeout)
    {
        var http = new HttpClient { Timeout = timeout };
        http.DefaultRequestHeaders.UserAgent.ParseAdd("AetherGui");
        return http;
    }

    // null when the repo has no published release yet (GitHub answers 404).
    private static async Task<System.Text.Json.JsonDocument?> LatestReleaseAsync(HttpClient http, string repo, CancellationToken ct)
    {
        using var response = await http.GetAsync($"https://api.github.com/repos/{repo}/releases/latest", ct);
        if (response.StatusCode == HttpStatusCode.NotFound) return null;
        response.EnsureSuccessStatusCode();
        return System.Text.Json.JsonDocument.Parse(await response.Content.ReadAsStringAsync(ct));
    }

    // "v2.4.0", "aether 2.4.0" or "1.0.0.0" -> 2.4.0; always three parts so 1.0.0 equals 1.0.0.0.
    public static Version? ParseVersion(string? text) =>
        Version.TryParse(text?.Trim().Split(' ').Last().TrimStart('v'), out var v) ? new Version(v.Major, v.Minor, Math.Max(v.Build, 0)) : null;

    public static Version AppVersion => ParseVersion(typeof(Aether).Assembly.GetName().Version?.ToString())!;

    public static async Task<Version?> InstalledCoreVersionAsync(CancellationToken ct)
    {
        if (!File.Exists(Exe)) return null;
        using var p = Process.Start(new ProcessStartInfo(Exe, "--version") { UseShellExecute = false, CreateNoWindow = true, RedirectStandardOutput = true })!;
        return ParseVersion(await p.StandardOutput.ReadToEndAsync(ct));
    }

    public record Updates(Version? Core, Version? LatestCore, Version? LatestGui, string? GuiPage)
    {
        public bool CoreNewer => LatestCore is not null && (Core is null || LatestCore > Core);
        public bool GuiNewer => LatestGui is not null && LatestGui > AppVersion;
    }

    public static async Task<Updates> CheckUpdatesAsync(CancellationToken ct)
    {
        using var http = GitHub(TimeSpan.FromSeconds(15));
        using var core = await LatestReleaseAsync(http, CoreRepo, ct);
        using var gui = await LatestReleaseAsync(http, GuiRepo, ct);
        return new Updates(await InstalledCoreVersionAsync(ct),
            ParseVersion(core?.RootElement.GetProperty("tag_name").GetString()),
            ParseVersion(gui?.RootElement.GetProperty("tag_name").GetString()),
            gui?.RootElement.GetProperty("html_url").GetString());
    }

    public static Task<bool> EnsureInstalledAsync(Action<string> log, CancellationToken ct) =>
        File.Exists(Exe) ? Task.FromResult(true) : InstallCoreAsync("aether.exe not found, downloading the latest release from GitHub...", log, ct);

    // Downloads the latest Windows release from GitHub and verifies its SHA-256; also used to update in place.
    // The whole archive is kept: pt/ holds the tor bridge transports and psiphon, which aether looks for beside itself.
    public static async Task<bool> InstallCoreAsync(string reason, Action<string> log, CancellationToken ct)
    {
        try
        {
            log(reason);
            using var http = GitHub(TimeSpan.FromMinutes(5));
            using var release = await LatestReleaseAsync(http, CoreRepo, ct) ?? throw new Exception("no release published");
            string? Asset(string name) => release.RootElement.GetProperty("assets").EnumerateArray()
                .FirstOrDefault(a => a.GetProperty("name").GetString() == name)
                .TryGetProperty("browser_download_url", out var u) ? u.GetString() : null;

            var zipUrl = Asset("aether-windows-x86_64.zip") ?? throw new Exception("no Windows asset in the latest release");
            var zip = await http.GetByteArrayAsync(zipUrl, ct);
            if (Asset("aether-windows-x86_64.zip.sha256") is { } shaUrl)
            {
                var expected = (await http.GetStringAsync(shaUrl, ct)).Split((char[]?)null, StringSplitOptions.RemoveEmptyEntries)[0];
                if (!Convert.ToHexString(SHA256.HashData(zip)).Equals(expected, StringComparison.OrdinalIgnoreCase))
                    throw new Exception("SHA-256 mismatch, download discarded");
            }
            using var archive = new ZipArchive(new MemoryStream(zip));
            if (archive.GetEntry("aether.exe") is null) throw new Exception("aether.exe not in the archive");
            archive.ExtractToDirectory(Dir, true);
            log($"Downloaded {release.RootElement.GetProperty("tag_name").GetString()}.");
            return true;
        }
        catch (Exception ex) when (ex is not OperationCanceledException)
        {
            log($"Download failed: {ex.Message}");
            return false;
        }
    }

    public static ProcessStartInfo CreateStartInfo(Preset p, CoreOptions options, string scan = "turbo")
    {
        var args = p.Args.Split(' ', StringSplitOptions.RemoveEmptyEntries)
            .Where(a => a is not ("--turbo" or "-4" or "--quick-reconnect")).ToList();
        bool tor = args.Contains("--tor"), psiphon = args.Contains("--psiphon");
        args.AddRange(options.Arguments);
        args.AddRange(["--bind", $"127.0.0.1:{(tor || psiphon ? InnerPort : SocksPort)}"]);
        if (tor) args.AddRange(["--tor-bind", $"127.0.0.1:{SocksPort}"]);
        if (psiphon) args.AddRange(["--psiphon-bind", $"127.0.0.1:{SocksPort}"]);
        args.AddRange([p.HttpFlag, $"127.0.0.1:{CoreHttpPort}"]);
        var info = new ProcessStartInfo(Exe)
        {
            WorkingDirectory = Dir, UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8,
            StandardInputEncoding = new UTF8Encoding(false)
        };
        foreach (var arg in args) info.ArgumentList.Add(arg);
        info.Environment["AETHER_SCAN"] = scan;
        info.Environment["AETHER_IP"] = "v4"; // the core accepts v4, v6 or both
        info.Environment["AETHER_QUICK_RECONNECT"] = "1";
        foreach (var (key, value) in options.EnvironmentVariables) info.Environment[key] = value;
        return info;
    }

    // Both listeners use the selected exit, including forward Tor/Psiphon modes.
    public static Process? Start(Preset p, Action<string> log, CoreOptions options, string scan = "turbo")
    {
        try
        {
            var proc = new Process { StartInfo = CreateStartInfo(p, options, scan) };
            try { proc.Start(); }
            catch { proc.Dispose(); throw; }
            _ = PumpOutputAsync(proc.StandardOutput, log);
            _ = PumpOutputAsync(proc.StandardError, log);
            return proc;
        }
        catch { log("Core start failed. Check the executable and core settings."); return null; }
    }

    private static async Task PumpOutputAsync(StreamReader reader, Action<string> log)
    {
        try
        {
            var buffer = new char[2048];
            int count;
            // Unlike ReadLine, this displays prompts that have no trailing newline.
            while ((count = await reader.ReadAsync(buffer)) > 0)
                foreach (var line in new string(buffer, 0, count).Split(['\r', '\n'], StringSplitOptions.RemoveEmptyEntries))
                    log(line);
        }
        catch (Exception ex) when (ex is IOException or ObjectDisposedException) { }
    }

    public static async Task<string> ReadHelpAsync(CancellationToken ct)
    {
        using var proc = new Process { StartInfo = new ProcessStartInfo(Exe, "--help")
        {
            WorkingDirectory = Dir, UseShellExecute = false, CreateNoWindow = true,
            RedirectStandardOutput = true, RedirectStandardError = true,
            StandardOutputEncoding = Encoding.UTF8, StandardErrorEncoding = Encoding.UTF8
        } };
        proc.Start();
        try
        {
            var stdout = proc.StandardOutput.ReadToEndAsync(ct);
            var stderr = proc.StandardError.ReadToEndAsync(ct);
            await proc.WaitForExitAsync(ct);
            return await stdout + Environment.NewLine + await stderr;
        }
        finally { if (!proc.HasExited) proc.Kill(true); }
    }

    // Waits for the proxy and, unless disabled, a passing internet test. Gives up once the startup budget is spent
    // and the proxy has been up for ConnectTimeoutMs without passing (tor opens its port long before it can carry traffic).
    public static async Task<(bool Connected, int? DelayMs)> WaitConnectedAsync(
        Process proc, int startupSecs, CancellationToken ct, bool realDelayTest = true)
    {
        var sw = Stopwatch.StartNew();
        long? upAt = null;
        while (!proc.HasExited)
        {
            if (upAt is null && await PortOpenAsync(ct))
            {
                upAt = sw.ElapsedMilliseconds;
                if (!realDelayTest) return (true, null);
            }
            if (upAt is not null && await PingAsync(ct) is int ms) return (true, ms);
            var t = sw.ElapsedMilliseconds;
            if (t > startupSecs * 1000 && (upAt is null || t - upAt > ConnectTimeoutMs)) return (false, null);
            await Task.Delay(500, ct);
        }
        return (false, null);
    }

    private static async Task<bool> PortOpenAsync(CancellationToken ct)
    {
        try { using var c = new TcpClient(); await c.ConnectAsync("127.0.0.1", SocksPort, ct); return true; }
        catch (Exception) when (!ct.IsCancellationRequested) { return false; }
    }

    public static async Task<int?> PingAsync(CancellationToken ct)
    {
        var sw = Stopwatch.StartNew();
        try
        {
            using var req = new HttpRequestMessage(HttpMethod.Get, TestUrl);
            req.Headers.ConnectionClose = true;
            using var res = await Http.SendAsync(req, ct);
            // Any success counts, since user URLs may answer 200 rather than 204.
            return (int)res.StatusCode < 400 ? (int)sw.ElapsedMilliseconds : null;
        }
        catch (Exception) when (!ct.IsCancellationRequested) { return null; }
    }
}
