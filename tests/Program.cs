using System.Diagnostics;
using System.Net.Http;
using AetherGui;

static class Checks
{
    static void Check(bool condition, string name)
    {
        if (!condition) throw new Exception(name);
        Console.WriteLine("PASS: " + name);
    }

    sealed class TrackedContent : StringContent
    {
        public bool Disposed;
        public TrackedContent() : base("") { }
        protected override void Dispose(bool disposing)
        {
            Disposed = true;
            base.Dispose(disposing);
        }
    }

    sealed class CancelingProbeHandler(CancellationTokenSource cancellation) : HttpMessageHandler
    {
        public TrackedContent Content = new();
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            cancellation.Cancel();
            return Task.FromResult(new HttpResponseMessage(System.Net.HttpStatusCode.OK) { Content = Content });
        }
    }

    [STAThread]
    static void Main()
    {
        SecurityChecks.Run();
        Check(TunMode.PowerShell("Write-Output \"Ethernet adapter\"").Trim() == "Ethernet adapter",
            "TUN PowerShell preserves embedded double quotes");
        var alias = "Ethernet O'Brien $adapter";
        Check(TunMode.PowerShell("Write-Output " + TunMode.PsLiteral(alias)).Trim() == alias,
            "TUN interface names remain literal");
        bool queryFailed = false;
        try { TunMode.PowerShell("throw 'test failure'"); }
        catch (InvalidOperationException) { queryFailed = true; }
        Check(queryFailed, "TUN PowerShell failures are not treated as empty route lists");
        Check(!string.IsNullOrWhiteSpace(TunMode.PowerShell(
            "Get-NetRoute -AddressFamily IPv4 -PolicyStore ActiveStore -ErrorAction Stop | Select-Object -ExpandProperty DestinationPrefix")),
            "TUN route query reads the live Windows route table");
        using (var current = Process.GetCurrentProcess())
        {
            Check(ProcessOwnership.MatchesExecutable(current, current.MainModule!.FileName), "Watchdog accepts an exact executable path");
            Check(!ProcessOwnership.MatchesExecutable(current, Path.Combine(Path.GetTempPath(), "aether.exe")),
                "Watchdog rejects an unrelated executable path");
        }

        using (var invalidProcess = new Process())
        {
            var diagnostics = new List<string>();
            Check(!Aether.StopProcess(invalidProcess, diagnostics.Add), "Unconfirmed process exit blocks replacement");
            Check(diagnostics.Any(s => s.Contains("replacement blocked")), "Cleanup failure is diagnosed");
        }
        using (var child = Process.Start(new ProcessStartInfo("cmd.exe", "/c ping -n 30 127.0.0.1 > nul")
        { UseShellExecute = false, CreateNoWindow = true })!)
        {
            Check(Aether.StopProcess(child, _ => { }) && child.HasExited, "Core stop confirms exit before replacement");
            Check(Aether.StopProcess(child, _ => { }), "Already exited core cleanup is idempotent");
        }
        using (var cancel = new CancellationTokenSource())
        using (var handler = new CancelingProbeHandler(cancel))
        using (var client = new HttpClient(handler))
        {
            bool canceled = false;
            try { Aether.PingAsync(client, "http://localhost/probe", cancel.Token).GetAwaiter().GetResult(); }
            catch (OperationCanceledException) { canceled = true; }
            Check(canceled, "Cancellation wins over a late successful probe response");
            Check(handler.Content.Disposed, "Canceled probe response content is disposed");
        }

        var options = CoreOptions.Parse("[\"--tor-bridge\",\"obfs4 1.2.3.4:443 cert=abc iat-mode=0\"]",
            "{\"AETHER_SCAN\":\"balanced\"}", 600);
        Check(options.Arguments.Length == 2 && options.Arguments[1].Contains(" iat-mode=0"), "Arguments preserve spaces");
        Check(options.StartupSeconds == 600, "Advanced timeout");
        var countryOptions = CoreOptions.Parse(options.ArgumentsJson, options.EnvironmentJson, 600, " de ");
        Check(countryOptions.PsiphonRegion == "DE" && countryOptions.IsConfigured, "Country normalized and configured");
        Check(Psiphon.Countries.Select(c => c.Code).Distinct().Count() == Psiphon.Countries.Length
            && Psiphon.Countries.Single(c => c.Code == "DE").Label == "Germany (DE)", "Unique country codes and clean labels");
        foreach (var invalid in new[] { "ZZ", "DE,US", "--help", "D", "🇩🇪" })
        {
            bool rejected = false;
            try { CoreOptions.Parse("[]", "{}", 300, invalid); } catch (FormatException) { rejected = true; }
            Check(rejected, "Reject invalid country " + invalid);
        }
        var countryPath = Path.Combine(Path.GetTempPath(), "aether-country-" + Guid.NewGuid() + ".json");
        try
        {
            countryOptions.Save(countryPath);
            var loaded = CoreOptions.Load(countryPath);
            Check(loaded.PsiphonRegion == "DE" && loaded.Arguments.SequenceEqual(options.Arguments)
                && loaded.EnvironmentVariables["AETHER_SCAN"] == "balanced" && loaded.StartupSeconds == 600, "Country persistence preserves expert settings");
            File.WriteAllText(countryPath, "{\"Arguments\":[],\"EnvironmentVariables\":{},\"StartupSeconds\":300}");
            Check(CoreOptions.Load(countryPath).PsiphonRegion == "", "Legacy settings default to Automatic");
            new CoreOptions().Save(countryPath);
            Check(CoreOptions.Load(countryPath).PsiphonRegion == "", "Automatic persistence");
        }
        finally { File.Delete(countryPath); File.Delete(countryPath + ".tmp"); }
        Check(Aether.ParseExit("[+] masque-in-masque exit: 104.28.214.161, IR via FRA, 448ms to cloudflare, warp on")
            is { Ip: "104.28.214.161", CountryCode: "IR", Colo: "FRA", LatencyMs: 448, Warp: true }, "Exit line parsed with colo and warp");
        Check(Aether.ParseExit("[+] psiphon exit: 1.2.3.4, US, 250ms to cloudflare, warp off")
            is { CountryCode: "US", Colo: null, LatencyMs: 250, Warp: false }, "Psiphon exit parsed without colo or warp");
        Check(Aether.ParseExit("Listening on 127.0.0.1:1818") is null, "Non-exit lines are ignored");
        Check(Aether.CountryName("US") == "United States" && Aether.CountryName("DE") == "Germany"
            && Aether.CountryName("ZZ") == "ZZ", "Exit country names resolve, unknown codes pass through");
        Check(Aether.CountryFlag("ZZ") is null, "Unknown exit country has no flag image");
        _ = Aether.CountryFlag("DE"); // must not throw; the image is embedded in the app, not the test host
        foreach (var preset in Aether.Presets)
        {
            var args = Aether.CreateStartInfo(preset, countryOptions).ArgumentList.ToList();
            bool usesPsiphon = preset.Args.Split(' ').Any(a => a is "--psiphon" or "--psiphon-only" or "--psiphon-reverse");
            Check(args.Contains("--psiphon-region") == usesPsiphon, preset.Name + " country scope");
            if (usesPsiphon) Check(args[args.IndexOf("--psiphon-region") + 1] == "DE", preset.Name + " country value");
            Check(!Aether.CreateStartInfo(preset, new()).ArgumentList.Contains("--psiphon-region"), preset.Name + " Automatic adds no flag");
        }
        foreach (var json in new[] { "[\"--psiphon-region\",\"US\"]", "[\"--psiphon-region=US\"]" })
        {
            var expert = CoreOptions.Parse(json, "{}", 300, "DE");
            var args = Aether.CreateStartInfo(new Preset("test", "--psiphon-only"), expert).ArgumentList;
            Check(expert.HasPsiphonRegionOverride && !args.Contains("DE") && expert.Arguments.All(args.Contains), "Expert region flag preserved without conflict");
        }
        var envRegion = CoreOptions.Parse("[]", "{\"AETHER_PSIPHON_REGION\":\"US\"}", 300, "DE");
        var envInfo = Aether.CreateStartInfo(new Preset("test", "--psiphon-only"), envRegion);
        Check(!envInfo.ArgumentList.Contains("--psiphon-region") && envInfo.Environment["AETHER_PSIPHON_REGION"] == "US", "Expert region environment takes precedence");
        foreach (var value in new[] { "[\"--bind=0.0.0.0:80\"]", "[\"--tor\"]", "[null]", "[1]", "{}" })
        {
            bool rejected = false;
            try { CoreOptions.Parse(value, "{}", 300); }
            catch (Exception ex) when (ex is FormatException or System.Text.Json.JsonException) { rejected = true; }
            Check(rejected, "Reject invalid arguments " + value);
        }
        foreach (var value in new[] { "{\"AETHER_SOCKS\":\"x\"}", "{\"PATH\":\"x\"}", "{\"AETHER_IP\":null}" })
        {
            bool rejected = false;
            try { CoreOptions.Parse("[]", value, 300); }
            catch (FormatException) { rejected = true; }
            Check(rejected, "Reject invalid environment " + value);
        }
        foreach (var preset in Aether.Presets)
        {
            var info = Aether.CreateStartInfo(preset, options);
            var args = info.ArgumentList.ToList();
            string Value(string flag) => args[args.IndexOf(flag) + 1];
            bool tor = preset.Args.Split(' ').Contains("--tor"), psiphon = preset.Args.Split(' ').Contains("--psiphon");
            string socks = $"127.0.0.1:{Aether.SocksPort}";
            Check(Value("--bind") == (tor || psiphon ? "127.0.0.1:1822" : socks), preset.Name + " base listener");
            Check(Value(preset.HttpFlag) == $"127.0.0.1:{Aether.CoreHttpPort}", preset.Name + " HTTP exit");
            if (tor) Check(Value("--tor-bind") == socks, "Tor SOCKS exit");
            if (psiphon) Check(Value("--psiphon-bind") == socks, "Psiphon SOCKS exit");
            Check(info.Environment["AETHER_SCAN"] == "balanced" && !args.Contains("--turbo"), "Environment overrides defaults");
            Check(args.Contains(options.Arguments[1]) && !info.UseShellExecute, "No shell splitting");
        }
        Check(Aether.CreateStartInfo(Aether.Presets[0], new CoreOptions(), "balanced").Environment["AETHER_SCAN"] == "balanced", "Chosen scan mode reaches the core");
        Check(Aether.CreateStartInfo(Aether.Presets[0], new CoreOptions()).Environment["AETHER_SCAN"] == "turbo", "Fast scan is the default");
        {
            int Index(string name) => Array.FindIndex(Aether.Presets, p => p.Name == name);
            Check(Enumerable.Range(0, 20).All(_ => Aether.AutoOrder(new Dictionary<int, int>())[0].Name == "MASQUE HTTP/2 → Psiphon"),
                "Preferred Psiphon routes are first in the fresh default Auto order");
            Check(Aether.AutoOrder(new Dictionary<int, int> { [Index("WireGuard")] = -1 })[0].Name != "WireGuard",
                "Failed WireGuard does not keep default priority");
            var past = new Dictionary<int, int> { [Index("WireGuard")] = 9000, [Index("MASQUE")] = 3000, [Index("MASQUE-in-MASQUE")] = -1 };
            var preferred = new[] { "MASQUE HTTP/2 → Psiphon", "MASQUE-in-MASQUE → Psiphon", "WARP-in-WARP → Psiphon" };
            var order = Aether.AutoOrder(past).Select(p => p.Name).ToList();
            Check(order.Take(3).SequenceEqual(preferred)
                && order.IndexOf("MASQUE") < order.IndexOf("WireGuard")
                && Aether.AutoOrder(new Dictionary<int, int> { [Index("WireGuard")] = -1 }).Last().Name == "WireGuard"
                && order.Count == Aether.AutoPresets.Length, "Preferred routes first, then fastest, failed non-preferred last");
            var manual = Aether.ParseOrder($"{Index("Tor alone")},x,{Index("MASQUE")},{Index("Tor alone")},999,-1");
            Check(Aether.AutoOrder(past, manual).Select(p => p.Name).SequenceEqual(["Tor alone", "MASQUE"]), "Manual Auto order used as is, junk dropped");
            Check(Aether.AutoOrder(past, []).Count == Aether.AutoPresets.Length, "Empty manual order falls back to ranking");
            // User put WireGuard (9000 ms) first; a new 2000 ms MASQUE goes before it, a failed one to the end, the rest stay.
            int m = Index("MASQUE"), w = Index("WireGuard"), t = Index("Tor alone");
            int[] mine = [w, t, m];
            Check(Aether.Rerank(mine, new Dictionary<int, int>(past) { [m] = 2000 }, m).SequenceEqual([m, w, t]), "Faster tested protocol moves up");
            Check(Aether.Rerank(mine, new Dictionary<int, int>(past) { [w] = -1 }, w).SequenceEqual([t, m, w]), "Failed protocol moves to the end");
            Check(Aether.Rerank(mine, past, Index("WireGuard-in-MASQUE (gool)")) == mine, "Untested-in-order protocol changes nothing");
            var saved = Aether.ParseConnectMs(Aether.FormatConnectMs(past) + ",999:5,x:1,3");
            Check(saved.Count == 3 && saved[Index("MASQUE")] == 3000 && saved[Index("MASQUE-in-MASQUE")] == -1, "Connect times round-trip, junk dropped");
        }
        Check(Aether.ValidPort(10808) is null && Aether.ValidPort(80) is not null
            && new[] { 1818, 1820, 1821, 1822, 1823 }.All(p => Aether.ValidPort(p) is not null), "Custom port validated");
        {
            // Fake core listeners answer with their name; the mixed port must pick by the first byte.
            using var stop = new CancellationTokenSource(TimeSpan.FromSeconds(10));
            static System.Net.Sockets.TcpListener Fake(int port, string name, CancellationToken ct)
            {
                var l = new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, port); l.Start();
                _ = Task.Run(async () => { using var c = await l.AcceptTcpClientAsync(ct); await c.GetStream().ReadAsync(new byte[1], ct);
                    await c.GetStream().WriteAsync(System.Text.Encoding.ASCII.GetBytes(name), ct); await Task.Delay(500, ct); }, ct);
                return l;
            }
            static string Ask(int port, byte first)
            {
                using var c = new System.Net.Sockets.TcpClient("127.0.0.1", port);
                c.GetStream().Write([first]);
                var buf = new byte[5];
                return System.Text.Encoding.ASCII.GetString(buf, 0, c.GetStream().Read(buf));
            }
            var socks = Fake(Aether.SocksPort, "socks", stop.Token); var http = Fake(Aether.CoreHttpPort, "http", stop.Token);
            _ = MixedProxy.Start(18190, stop.Token);
            Check(Ask(18190, 5) == "socks" && Ask(18190, (byte)'C') == "http", "Mixed port routes SOCKS5 and HTTP");
            stop.Cancel(); socks.Stop(); http.Stop();
        }
        {
            var listener = new System.Net.Sockets.TcpListener(System.Net.IPAddress.Loopback, Aether.SocksPort);
            listener.Start();
            try
            {
                using var proc = System.Diagnostics.Process.GetCurrentProcess();
                using var stop = new CancellationTokenSource(TimeSpan.FromSeconds(2));
                var result = Aether.WaitConnectedAsync(proc, 1, stop.Token, realDelayTest: false).GetAwaiter().GetResult();
                Check(result.Connected && result.DelayMs is null, "Disabled real delay test only requires the local proxy");
            }
            finally { listener.Stop(); }
        }
        {
            var unsigned = Path.GetTempFileName();
            Check(!Psiphon.IsSignedByPsiphon(unsigned), "Unsigned psiphon3.exe rejected");
            File.Delete(unsigned);
            var real = Path.Combine(AppContext.BaseDirectory, @"..\..\..\..\publish\psiphon3.exe");
            if (File.Exists(real)) Check(Psiphon.IsSignedByPsiphon(real), "Real psiphon3.exe signature accepted");
            var tampered = Path.GetTempFileName();
            if (File.Exists(real)) { var b = File.ReadAllBytes(real); b[b.Length / 2] ^= 1; File.WriteAllBytes(tampered, b); }
            if (File.Exists(real)) Check(!Psiphon.IsSignedByPsiphon(tampered), "Tampered psiphon3.exe rejected");
            File.Delete(tampered);
        }
        Check(Aether.ParseVersion("v2.4.0") == new Version(2, 4, 0) && Aether.ParseVersion("aether 2.3.0\n") == new Version(2, 3, 0), "Release tag and core output parse");
        Check(Aether.ParseVersion("1.0.0.0") == Aether.ParseVersion("v1.0.0") && Aether.ParseVersion("nightly") is null, "Version compare ignores the fourth part");
        Check(new Aether.Updates(new Version(2, 3, 0), new Version(2, 4, 0), null, null).CoreNewer
            && !new Aether.Updates(new Version(2, 4, 0), new Version(2, 4, 0), Aether.AppVersion, null).CoreNewer
            && !new Aether.Updates(null, null, Aether.AppVersion, null).GuiNewer, "Only a newer release counts as an update");
        Check(Aether.Presets[4].Name == "Tor alone" && Aether.Presets[7].Name == "Psiphon + WARP", "Saved indexes stable");
        Check(Aether.AutoPresets.Any(p => p.Args.Contains("--h2")), "Auto HTTP/2 fallback");
        var requestedPsiphon = new[] { "MASQUE HTTP/2 → Psiphon", "WireGuard → Psiphon", "WARP-in-WARP → Psiphon", "MASQUE-in-MASQUE → Psiphon" };
        Check(Aether.AutoPresets.Length == 13 && requestedPsiphon.All(name => Aether.AutoPresets.Any(p => p.Name == name))
            && Aether.AutoPresets.All(p => p.Name != "MASQUE → Psiphon" && p.Name != "Psiphon alone"),
            "Fresh Auto includes only the four requested Psiphon routes");
        Check(Aether.MenuPresetIndexes.Order().SequenceEqual(Enumerable.Range(0, Aether.Presets.Length)), "Menu includes every stable preset index exactly once");
        Check(Aether.MenuPresetIndexes.Take(Aether.AutoPresets.Length).All(i => !Aether.Presets[i].ManualOnly), "Fast protocols appear first");
        Check(Aether.MenuPresetIndexes.Skip(Aether.AutoPresets.Length).All(i => Aether.Presets[i].ManualOnly), "Manual protocols appear last");
        Check(Aether.NextPresetIndex(Aether.MenuPresetIndexes[^1]) == Aether.MenuPresetIndexes[0]
            && Aether.MenuPresetIndexes.Zip(Aether.MenuPresetIndexes.Skip(1)).All(x => Aether.NextPresetIndex(x.First) == x.Second),
            "Next protocol follows menu order and wraps around");
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        var help = Aether.ReadHelpAsync(timeout.Token).GetAwaiter().GetResult();
        Check(help.Contains("--tor") && help.Contains("--psiphon"), "Real bundled core help executes");
        Check(help.Contains("--gool-classic"), "Bundled core supports v2.3 classic gool");
        Check(Aether.Presets[2].Args.Contains("--gool-classic"), "Saved gool keeps WireGuard-in-WireGuard semantics");
        Check(Aether.Presets[21].Args.Split(' ').Contains("--gool"), "New gool appended without shifting saved indexes");
        bool classicRejected = false;
        try { CoreOptions.Parse("[\"--gool-classic\"]", "{}", 300); }
        catch (FormatException) { classicRejected = true; }
        Check(classicRejected, "Classic gool cannot override selected protocol");
        var stats = Aether.ParseStats("0:5:2:21000:1762850000;1:0:3:0:0;999:1:1:1:1");
        Check(stats.Count == 2 && Aether.ParseStats(Aether.FormatStats(stats))[0].AvgMs == 4200
            && stats[0].Verdict == "good" && stats[1].Verdict == "bad" && new ProtocolStat().Verdict == "new" && new ProtocolStat(1).Verdict == "maybe",
            "Protocol stats round-trip and give a verdict");
        var parts = CoreSettingsForm.StatParts(stats[0]);
        Check(parts[0].Color == Palette.Connected && parts[1].Color == Palette.Disconnected && parts[2].Color == Palette.Connected && parts[3].Color == Palette.Connected,
            "Stat numbers carry meaning colors");
        Check(Aether.SortByStats([1, 2, 3, 0], new Dictionary<int, ProtocolStat> { [0] = new(5, 1, 9000), [1] = new(0, 3), [3] = new(1, 0, 4000) })
            .SequenceEqual([3, 0, 2, 1]), "Worked protocols lead, untried keep order, only-failed go last");
        ApplicationConfiguration.Initialize();
        // Larger text stands in for 125-200% display scaling: the left panel must grow with it, never slide under the log.
        static IEnumerable<Control> All(Control c) => c.Controls.Cast<Control>().SelectMany(x => All(x).Prepend(x));
        static Rectangle InForm(Control c) // bounds in form client coordinates, without needing a shown window
        {
            var r = c.Bounds;
            for (var p = c.Parent; p is not null and not Form; p = p.Parent) r.Offset(p.Location);
            return r;
        }
        foreach (var scale in new[] { 1f, 1.5f, 2f })
        {
            using var main = new Form1();
            main.Font = new Font(main.Font.FontFamily, 9f * scale);
            main.Size = main.MinimumSize;
            main.PerformLayout();
            var buttons = new[] { "Connect securely", "Reset order and connect", "Next protocol" }
                .Select(name => InForm(All(main).OfType<Button>().First(b => b.AccessibleName == name))).ToArray();
            var panel = InForm(main.Controls.Find("connectionPanel", true)[0]);
            Check(buttons.All(panel.Contains), $"Action buttons inside their panel at {scale:0.#}x text");
            Check(buttons.All(b => Math.Abs(b.Width - buttons[0].Width) <= 2 && b.Height == buttons[0].Height && b.Top == buttons[0].Top),
                $"Action buttons share one row, size and shape at {scale:0.#}x text ({string.Join(" | ", buttons)})");
        }
        {
            using var main = new Form1();
            var next = All(main).OfType<Button>().First(b => b.AccessibleName == "Next protocol");
            Check(All(main).OfType<ComboBox>().Any(c => c.AccessibleName == "Connection protocol"), "The protocol list is on the main window");
            Check(All(main).OfType<CheckBox>().Any(c => c.AccessibleName == "Full-device TUN mode"), "The full-device TUN toggle is on the main window");
            var seconds = All(main).OfType<NumericUpDown>().First(n => n.AccessibleName == "Auto protocol try seconds");
            var delay = All(main).OfType<CheckBox>().Single(c => c.Text == "Real delay test");
            Check(delay.Parent == seconds.Parent && delay.Left >= seconds.Right && delay.Checked == Aether.RealDelayTest,
                "Main delay toggle sits next to Auto try and reflects the saved preference");
            Check(!next.Enabled && seconds.Minimum == 5 && seconds.Maximum == 3600
                && seconds.Value >= seconds.Minimum && seconds.Value <= seconds.Maximum,
                "Next protocol starts disabled and Auto try seconds are editable");
        }
        {
            // After showing then hiding the log, every control fits while connecting, with no scrolling.
            using var main = new Form1();
            var toggle = All(main).OfType<CheckBox>().First(c => c.Text == "Show latest activity");
            toggle.Checked = true; main.PerformLayout();
            toggle.Checked = false;
            All(main).OfType<ProgressBar>().First().Visible = true;
            main.PerformLayout();
            var showLog = InForm(All(main).OfType<CheckBox>().First(c => c.Text == "Show latest activity"));
            Check(showLog.Bottom <= InForm(main.Controls.Find("connectionPanel", true)[0]).Bottom - 8, $"All controls fit while connecting ({showLog.Bottom} vs panel {InForm(main.Controls.Find("connectionPanel", true)[0]).Bottom})");
        }
        {
            using var main = new Form1();
            var cards = All(main).OfType<TableLayoutPanel>().Single(t => t.AccessibleName == "Connected protocol stats");
            Check(!cards.Visible && cards.Controls.Count == 4, "Four stat cards, hidden until connected");
            var dir = Environment.GetEnvironmentVariable("AETHER_SHOT_DIR");
            if (dir is not null)
            {
                cards.Visible = true;
                main.Show(); Application.DoEvents();
                using var shot = new Bitmap(main.Width, main.Height);
                main.DrawToBitmap(shot, new Rectangle(Point.Empty, main.Size));
                shot.Save(Path.Combine(dir, "main-cards.png"));
                main.Close();
            }
        }
        using (var exitForm = new Form1())
        {
            var showExit = typeof(Form1).GetMethod("ShowExit", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!;
            showExit.Invoke(exitForm, new object[] { new ExitInfo("104.28.214.161", "DE", "FRA", 448, true) });
            var fields = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
            var text = (Label)typeof(Form1).GetField("exitText", fields)!.GetValue(exitForm)!;
            var flag = (PictureBox)typeof(Form1).GetField("exitFlag", fields)!.GetValue(exitForm)!;
            var panel = (FlowLayoutPanel)typeof(Form1).GetField("exitPanel", fields)!.GetValue(exitForm)!;
            Check(text.Text == "" && !text.Visible, "Exit badge contains no IP or technical text");
            Check(panel.Parent is TableLayoutPanel header && header.GetColumn(panel) == 1
                && header.Controls.OfType<Label>().Any(label => label.AccessibleName == "Connection status: Disconnected"),
                "Exit flag is in the right-hand column of the connection status header");
            Check(flag.Image is not null && flag.AccessibleName == "Exit country: Germany"
                && panel.AccessibleName == "Exit country: Germany", "Exit badge uses flag with country-only accessibility");
        }
        Check(Aether.TorBootstrapProgress("[notice] Bootstrapped 43% (loading): Loading") == 43
            && Aether.TorBootstrapProgress("tor reaching the network: 15%") == 15
            && Aether.TorBootstrapProgress("[INFO aether::tor] tor reaching the network: 100%") == 100
            && Aether.TorBootstrapProgress("tor reaching the network: 101%") is null
            && Aether.TorBootstrapProgress("Bootstrapped 100% (done)") == 100
            && Aether.TorBootstrapProgress("Bootstrapped 0%") == 0
            && Aether.TorBootstrapProgress("Bootstrapped 101%") is null
            && Aether.TorBootstrapProgress("download 43%") is null, "Tor bootstrap percentages validated");
        Check(Form1.LogColor("Could not start the core") == Palette.Disconnected, "Errors are red in the log");
        Check(Form1.LogColor("Switching to WireGuard") == Palette.Connecting, "Route switches are amber in the log");
        Check(Form1.LogColor("Connected: MASQUE") == Palette.Connected, "Connections are green in the log");
        Check(Form1.LogColor("Disconnected") == Color.Black, "Disconnected is not mistaken for connected");
        Check(Form1.PingColor(120) == Palette.Connected && Form1.PingColor(500) == Palette.Connecting
            && Form1.PingColor(900) == Palette.Disconnected && Form1.PingColor(null) == Palette.Disconnected, "Ping colors follow the thresholds");
        Check(Form1.LightColorAt(0).ToArgb() == Form1.LightColors[0].ToArgb() && Form1.LightColorAt(0.2).ToArgb() == Form1.LightColors[1].ToArgb()
            && Form1.LightColorAt(1).ToArgb() == Form1.LightColors[0].ToArgb() && Form1.LightColorAt(0.1).ToArgb() != Form1.LightColors[0].ToArgb(),
            "Connecting colors start, step and wrap around smoothly");
        Check(Aether.ValidTestUrl("https://www.cloudflare.com/cdn-cgi/trace") is null && Aether.ValidTestUrl("ftp://x") is not null
            && Aether.ValidTestUrl("gstatic.com") is not null, "Delay test URL must be absolute http(s)");
        Check(!Aether.DefaultRealDelayTest && !Aether.ParseRealDelayTest(null) && !Aether.ParseRealDelayTest(0)
            && !Aether.ParseRealDelayTest("1") && Aether.ParseRealDelayTest(1), "Real delay test is disabled by default");
        {
            // The Auto order list must really draw the stats: a "good" protocol shows its green verdict.
            using var withStats = new CoreSettingsForm(new(), null, null, stats);
            var list = All(withStats).OfType<CoreSettingsForm.StatsListBox>().Single();
            ((TabControl)withStats.Controls[0]).SelectedIndex = 1;
            withStats.Show();
            Application.DoEvents();
            using var shot = new Bitmap(list.Width, list.Height);
            list.DrawToBitmap(shot, new Rectangle(Point.Empty, list.Size));
            var dir = Environment.GetEnvironmentVariable("AETHER_SHOT_DIR");
            if (dir is not null) shot.Save(Path.Combine(dir, "auto-order.png"));
            var green = 0;
            for (var x = 0; x < shot.Width; x++)
                for (var y = 0; y < shot.Height; y++)
                    if (shot.GetPixel(x, y).ToArgb() == Palette.Connected.ToArgb()) green++;
            withStats.Close();
            Check(green > 0, "Auto order list draws per-protocol stats");
        }
        using (var countryForm = new CoreSettingsForm(countryOptions))
        {
            var selector = All(countryForm).OfType<ComboBox>().Single(c => c.AccessibleName == "Psiphon server country");
            Check(selector.DropDownStyle == ComboBoxStyle.DropDownList && ((Psiphon.Country)selector.SelectedItem!).Code == "DE", "Country selector restores saved choice");
        }
        using var settings = new CoreSettingsForm(new());
        var delayUrl = All(settings).OfType<ComboBox>().Single(c => c.AccessibleName == "Delay test URL");
        Check(delayUrl.Enabled && !All(settings).OfType<CheckBox>().Any(c => c.AccessibleName == "Real delay test"),
            "Settings keeps the editable URL but not the delay toggle");
        var release = new Version(1, 0, 29);
        Check(ReleaseNotes.ForVersion(release).Contains("آزمایش تأخیر واقعی", StringComparison.Ordinal) && ReleaseNotes.ForVersion(new Version(1, 0, 0)).Length == 0,
            "Bundled notes match the installed version only");
        Check(ReleaseNotes.ShouldShow(release, "1.0.28", true) && ReleaseNotes.ShouldShow(release, null, true)
            && !ReleaseNotes.ShouldShow(release, null, false) && !ReleaseNotes.ShouldShow(release, "1.0.29", true)
            && !ReleaseNotes.ShouldShow(release, "1.0.30", true), "Notes appear on upgrades, not on fresh installs, repeat launches or downgrades");
        foreach (var size in new[] { new Size(520, 460), new Size(800, 650), new Size(1200, 800) })
        {
            settings.Size = size; settings.PerformLayout();
            Check(settings.Controls[0].Width > 0 && settings.Controls[0].Height > 0, "Settings layout " + size);
        }
        Console.WriteLine("All core checks passed. No tunnel or system proxy was started.");
    }
}
