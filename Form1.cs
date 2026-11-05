using System.Diagnostics;
using System.Text.RegularExpressions;
using Microsoft.Win32;

namespace AetherGui;

public partial class Form1 : Form
{
    private const int StartupDelayMs = 1000; // pause before the automatic connect on startup
    private const string SettingsKey = @"Software\AetherGui";

    private Process? _process;
    private CancellationTokenSource? _cts;
    private CancellationTokenSource? _attemptCts;
    private bool _nextRequested;
    private CoreOptions _coreOptions = new();
    private readonly int[] _protocolIndexes = [-1, .. Aether.MenuPresetIndexes];
    private static readonly string[] ScanModes = ["turbo", "balanced"]; // saved as an index into this
    private Dictionary<int, int> _connectMs = []; // preset index -> ms its last connect took, -1 = failed; orders Auto

    public Form1()
    {
        InitializeComponent();
        cboProtocol.Items.Add("Auto (order in Core settings)");
        cboProtocol.Items.AddRange(Aether.MenuPresetIndexes.Select(i => (object)Aether.Presets[i].Label).ToArray());
        cboScan.Items.AddRange(["Fast: first server that answers", "Balanced: tries a few, keeps the fastest"]);
        using (var key = Registry.CurrentUser.OpenSubKey(SettingsKey))
        {
            chkStartup.Checked = key?.GetValue("AutoConnect") is 1;
            chkSysProxy.Checked = key?.GetValue("SetSystemProxy") is 1;
            chkPsiphon.Checked = key?.GetValue("RunPsiphon") is not 0; // on unless turned off, as before this option
            chkShowLog.Checked = key?.GetValue("ShowActivity") is not 0; // on unless turned off
            var saved = key?.GetValue("Protocol") is int i && i >= 0 && i <= Aether.Presets.Length ? i : 0;
            cboProtocol.SelectedIndex = Array.IndexOf(_protocolIndexes, saved - 1);
            cboScan.SelectedIndex = key?.GetValue("Scan") is 1 ? 1 : 0;
            numTrySeconds.Value = key?.GetValue("TrySeconds") is int seconds && seconds >= numTrySeconds.Minimum && seconds <= numTrySeconds.Maximum
                ? seconds : Aether.FastSecs;
            _connectMs = Aether.ParseConnectMs(key?.GetValue("ConnectMs") as string);
        }
        try { _coreOptions = CoreOptions.Load(); }
        catch { chkStartup.Checked = false; Log("Could not load core settings. Review settings before connecting."); }
        cboProtocol.SelectedIndexChanged += (_, _) => SaveSetting("Protocol", _protocolIndexes[cboProtocol.SelectedIndex] + 1);
        cboScan.SelectedIndexChanged += (_, _) => SaveSetting("Scan", cboScan.SelectedIndex);
        numTrySeconds.ValueChanged += (_, _) => SaveSetting("TrySeconds", (int)numTrySeconds.Value);
        chkStartup.CheckedChanged += (_, _) => SaveSetting("AutoConnect", chkStartup.Checked);
        if (chkShowLog.Checked) ShowLog(true); // starts hidden
        chkShowLog.CheckedChanged += (_, _) =>
        {
            SaveSetting("ShowActivity", chkShowLog.Checked);
            ShowLog(chkShowLog.Checked);
        };
        chkSysProxy.CheckedChanged += (_, _) =>
        {
            SaveSetting("SetSystemProxy", chkSysProxy.Checked);
            if (!chkSysProxy.Checked) SystemProxy.Disable();
            else if (_process is { HasExited: false } && lblStatus.Text.Contains("Connected:")) SystemProxy.Enable();
        };
        chkPsiphon.CheckedChanged += (_, _) =>
        {
            SaveSetting("RunPsiphon", chkPsiphon.Checked);
            if (chkPsiphon.Checked) return;
            Psiphon.Kill();
            SystemProxy.Disable(); // the proxy Psiphon set is dead now
            if (chkSysProxy.Checked && _process is { HasExited: false } && lblStatus.Text.Contains("Connected:")) SystemProxy.Enable();
        };
        Shown += async (_, _) =>
        {
            _ = CheckUpdatesAsync(interactive: false);
            if (!chkStartup.Checked) return;
            Log($"Auto-connecting in {StartupDelayMs / 1000}s...");
            await Task.Delay(StartupDelayMs);
            if (chkStartup.Checked && _cts == null && btnConnect.Enabled) btnConnect_Click(null, EventArgs.Empty); // not while a core update installs
        };
        _buttonTimer.Tick += (_, _) => btnConnect.BackColor = LightColorAt(_buttonClock.Elapsed.TotalSeconds / 4);
        FormClosing += (_, _) => { _buttonTimer.Dispose(); _cts?.Cancel(); KillProcess(); Psiphon.Kill(); SystemProxy.Disable(); };
    }

    private static readonly Bitmap PsiphonIcon = new(typeof(Form1).Assembly.GetManifestResourceStream("psiphon.png")!);

    // Psiphon presets get Psiphon's logo; every item is indented the same so the names line up.
    private void DrawProtocolItem(object? sender, DrawItemEventArgs e)
    {
        e.DrawBackground();
        if (e.Index < 0) return;
        var text = cboProtocol.GetItemText(cboProtocol.Items[e.Index]) ?? "";
        int size = e.Bounds.Height - 2, x = e.Bounds.X + 2;
        if (text.Contains("Psiphon")) e.Graphics.DrawImage(PsiphonIcon, x, e.Bounds.Y + 1, size, size);
        var textBounds = Rectangle.FromLTRB(x + size + 4, e.Bounds.Top, e.Bounds.Right, e.Bounds.Bottom);
        TextRenderer.DrawText(e.Graphics, text, e.Font, textBounds, e.ForeColor, TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.EndEllipsis);
        e.DrawFocusRectangle();
    }

    // The window grows to make room for the log and shrinks back when it is hidden.
    private void ShowLog(bool show)
    {
        int Px(int v) => IsHandleCreated ? LogicalToDeviceUnits(v) : v; // before the handle, Dpi autoscale scales these later
        var change = show ? Px(157) : -Px(157); // 400 <-> 557; the log also fills spare room, so never shrink by its height
        txtMiniLog.Visible = show;
        MinimumSize = new Size(MinimumSize.Width, MinimumSize.Height + (show ? Px(50) : -Px(50)));
        Height += change;
    }

    private static void SaveSetting(string name, bool value) => SaveSetting(name, value ? 1 : 0);

    private static void SaveSetting(string name, object value)
    {
        using var key = Registry.CurrentUser.CreateSubKey(SettingsKey);
        key.SetValue(name, value);
    }

    private async void btnConnect_Click(object? sender, EventArgs e)
    {
        if (_cts != null) { _cts.Cancel(); return; }
        _cts = new CancellationTokenSource();
        StartWatchdog();
        btnConnect.Text = "Disconnect";
        btnConnect.AccessibleName = "Disconnect";
        btnCoreSettings.Enabled = cboProtocol.Enabled = cboScan.Enabled = numTrySeconds.Enabled = btnUpdates.Enabled = false;
        btnNextProtocol.Enabled = true;
        btnCoreInput.Enabled = true;
        await RunAsync(_cts.Token);
        _cts.Dispose();
        _cts = null;
        if (IsDisposed) return;
        btnCoreSettings.Enabled = cboProtocol.Enabled = cboScan.Enabled = numTrySeconds.Enabled = btnUpdates.Enabled = true;
        btnNextProtocol.Enabled = false;
        btnCoreInput.Enabled = false;
        btnConnect.Text = "Connect securely";
        btnConnect.AccessibleName = "Connect securely";
    }

    private void btnNextProtocol_Click(object? sender, EventArgs e)
    {
        if (_cts is null) return;
        _nextRequested = true;
        _attemptCts?.Cancel();
    }

    // Auto: try the default presets, fastest past connect first; one that times out or drops is not retried until all others were tried.
    // A chosen preset (including the slow manual-only ones) is retried unless Next protocol is pressed.
    private async Task RunAsync(CancellationToken ct)
    {
        var untried = new List<Preset>();
        var chosen = _protocolIndexes[cboProtocol.SelectedIndex]; // -1 = Auto; read once, a new pick applies on the next Connect
        var scan = ScanModes[cboScan.SelectedIndex];
        var trySeconds = (int)numTrySeconds.Value;
        try
        {
            SetStatus("Downloading aether...", Palette.Connecting);
            if (!await Aether.EnsureInstalledAsync(Log, ct)) return;
            try { _ = MixedProxy.Start(Aether.ProxyPort, ct); }
            catch (System.Net.Sockets.SocketException) { Log($"Port {Aether.ProxyPort} is in use. Pick another in Core settings."); return; }
            while (true)
            {
                if (untried.Count == 0) untried.AddRange(chosen < 0 ? Aether.AutoOrder(_connectMs, Aether.SavedOrder) : [Aether.Presets[chosen]]);
                var p = untried[0];
                untried.RemoveAt(0);
                using var attempt = CancellationTokenSource.CreateLinkedTokenSource(ct);
                _attemptCts = attempt;
                try
                {
                    if (_nextRequested) attempt.Cancel();
                    var startupSeconds = _coreOptions.IsConfigured ? _coreOptions.StartupSeconds : chosen < 0 ? trySeconds : p.StartupSecs;
                    await ConnectAndMonitorAsync(p, scan, startupSeconds, attempt.Token);
                    await Task.Delay(1000, attempt.Token);
                }
                catch (OperationCanceledException) when (!ct.IsCancellationRequested)
                {
                    KillProcess();
                    if (chosen >= 0) chosen = Aether.NextPresetIndex(Array.IndexOf(Aether.Presets, p));
                    Log($"Next protocol: {(chosen < 0 ? "Auto order" : Aether.Presets[chosen].Name)}.");
                }
                finally
                {
                    _attemptCts = null;
                    _nextRequested = false;
                }
            }
        }
        catch (OperationCanceledException) { }
        finally
        {
            _attemptCts = null;
            _nextRequested = false;
            KillProcess();
            SetStatus("Disconnected", Palette.Disconnected);
            lblDelay.Text = "Delay: -";
            lblDelay.ForeColor = SystemColors.ControlText;
        }
    }

    // Returns when the preset fails to connect within the timeout, or after a connected session drops.
    private async Task ConnectAndMonitorAsync(Preset p, string scan, int startupSeconds, CancellationToken ct)
    {
        ct.ThrowIfCancellationRequested();
        Log($"Trying {p.Name}...");
        SetStatus($"Connecting: {p.Name}", Palette.Connecting);
        var proc = _process = Aether.Start(p, Log, _coreOptions, scan);
        if (proc is null) return;

        var took = Stopwatch.StartNew();
        var ms = await Aether.WaitConnectedAsync(proc, startupSeconds, ct);
        _connectMs[Array.IndexOf(Aether.Presets, p)] = ms is null ? -1 : (int)took.ElapsedMilliseconds;
        SaveSetting("ConnectMs", Aether.FormatConnectMs(_connectMs));
        var order = Aether.AutoOrder(_connectMs, Aether.SavedOrder).Select(x => Array.IndexOf(Aether.Presets, x)).ToArray();
        Aether.SavedOrder = Aether.Rerank(order, _connectMs, Array.IndexOf(Aether.Presets, p));
        if (ms is null)
        {
            Log(proc.HasExited ? $"{p.Name}: process exited." : $"{p.Name}: no internet, switching.");
            KillProcess();
            return;
        }

        if (chkSysProxy.Checked) SystemProxy.Enable();
        SetStatus($"Connected: {p.Name}", Palette.Connected);
        Log($"Connected via {p.Name} in {took.Elapsed.TotalSeconds:0.0}s, delay {ms} ms.");
        // The core's own psiphon modes already run Psiphon; a second one on top only slows it down.
        if (chkPsiphon.Checked && !p.Args.Contains("psiphon")) _ = StartPsiphonAsync(ct); // a download must not hold up the connection monitor below
        for (int fails = 0; fails < 2;)
        {
            lblDelay.Text = ms is null ? "Delay: timeout" : $"Delay: {ms} ms";
            lblDelay.ForeColor = PingColor(ms);
            await Task.Delay(5000, ct);
            if (proc.HasExited) break;
            ms = await Aether.PingAsync(ct);
            fails = ms is null ? fails + 1 : 0;
        }
        Log($"{p.Name}: connection lost, switching.");
        KillProcess();
    }

    private bool _psiphonStarting;

    // Opens psiphon3.exe from beside this exe once per connection, downloading it first if missing; skipped if already running.
    private async Task StartPsiphonAsync(CancellationToken ct)
    {
        if (_psiphonStarting || Process.GetProcessesByName("psiphon3").Length > 0) return;
        _psiphonStarting = true;
        try
        {
            if (!await Psiphon.EnsureDownloadedAsync(Log, ct) || ct.IsCancellationRequested) return;
        }
        catch (OperationCanceledException) { return; }
        finally { _psiphonStarting = false; }
        var exe = Psiphon.Exe;
        // Psiphon reads its Upstream Proxy setting from here at startup: point it at our HTTP port.
        using (var key = Registry.CurrentUser.CreateSubKey(@"Software\Psiphon3"))
        {
            key.SetValue("SSHParentProxyHost", "127.0.0.1");
            key.SetValue("SSHParentProxyPort", Aether.ProxyPort);
            key.SetValue("SSHParentProxySkip", 0);
        }
        try { Process.Start(new ProcessStartInfo(exe) { UseShellExecute = true, WorkingDirectory = AppContext.BaseDirectory }); }
        catch (Exception ex) { Log($"psiphon3: {ex.Message}"); }
    }

    private bool _watchdogStarted;

    // If this GUI crashes or is killed, the watchdogs stop aether and clear the system proxy (two independent layers).
    private void StartWatchdog()
    {
        if (_watchdogStarted) return;
        _watchdogStarted = true;
        Process.Start(new ProcessStartInfo(Environment.ProcessPath!, $"--watchdog {Environment.ProcessId}") { CreateNoWindow = true, UseShellExecute = false });
        SystemProxy.StartIndependentGuard(Environment.ProcessId);
    }

    private void KillProcess()
    {
        SystemProxy.Disable(); // never leave the system pointing at a dead proxy
        try { if (_process is { HasExited: false }) { _process.Kill(true); _process.WaitForExit(2000); } } catch { }
        _process?.Dispose();
        _process = null;
    }

    private void ShowCoreSettings()
    {
        if (_cts != null) return;
        using var dialog = new CoreSettingsForm(_coreOptions, _connectMs);
        if (dialog.ShowDialog(this) == DialogResult.OK) _coreOptions = dialog.Options;
    }

    // Updates are offered in a dialog, at startup too, so they are seen with the log hidden; only the
    // menu check also reports "up to date" and failures. The core is replaced only while disconnected,
    // since a running aether.exe cannot be overwritten.
    private async Task CheckUpdatesAsync(bool interactive)
    {
        if (interactive) Log("Checking for updates...");
        Aether.Updates u;
        try { u = await Aether.CheckUpdatesAsync(CancellationToken.None); }
        catch (Exception ex)
        {
            if (!interactive || IsDisposed) return;
            Log($"Update check failed: {ex.Message}");
            MessageBox.Show(this, $"Could not check for updates.\n\n{ex.Message}", "Check for updates", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        if (IsDisposed) return;

        if (u.GuiNewer)
        {
            Log($"AetherGui {u.LatestGui} is available (you have {Aether.AppVersion}).", Color.Blue);
            if (u.GuiPage?.StartsWith("https://github.com/") == true && MessageBox.Show(this, $"AetherGui {u.LatestGui} is available (you have {Aether.AppVersion}). Open the download page?", "Update available",
                    MessageBoxButtons.YesNo, MessageBoxIcon.Information) == DialogResult.Yes)
                Process.Start(new ProcessStartInfo(u.GuiPage!) { UseShellExecute = true });
        }
        if (u.CoreNewer)
        {
            Log($"Core {u.LatestCore} is available (you have {u.Core?.ToString() ?? "none"}).", Color.Blue);
            if (_cts != null) { if (interactive) MessageBox.Show(this, $"Core {u.LatestCore} is available. Disconnect first, then check for updates again.", "Update available"); }
            else if (MessageBox.Show(this, $"Update the core to {u.LatestCore}?", "Update available",
                         MessageBoxButtons.YesNo, MessageBoxIcon.Information) == DialogResult.Yes)
            {
                if (_cts != null) { Log("Disconnect first to update the core."); return; } // auto-connect may have started while asking
                btnConnect.Enabled = btnUpdates.Enabled = false;
                if (await Aether.InstallCoreAsync($"Updating the core to {u.LatestCore}...", Log, CancellationToken.None))
                    Log($"Core is now {await Aether.InstalledCoreVersionAsync(CancellationToken.None)}.");
                btnConnect.Enabled = btnUpdates.Enabled = true;
            }
        }
        if (interactive && !u.GuiNewer && !u.CoreNewer)
        {
            var upToDate = $"Up to date: AetherGui {Aether.AppVersion}, core {u.Core?.ToString() ?? "not installed"}.";
            Log(upToDate);
            MessageBox.Show(this, upToDate, "Check for updates", MessageBoxButtons.OK, MessageBoxIcon.Information);
        }
    }

    private async Task SendCoreInputAsync()
    {
        var proc = _process;
        if (proc is null || proc.HasExited) { Log("Core is not running yet."); return; }
        using var dialog = new Form
        {
            Text = "Core input", ClientSize = new Size(440, 140), MinimumSize = new Size(360, 180),
            StartPosition = FormStartPosition.CenterParent, AutoScaleMode = AutoScaleMode.Dpi,
            Font = Font, BackColor = Palette.Background
        };
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(12), RowCount = 3, ColumnCount = 1 };
        layout.Controls.Add(new Label { Text = "Code or prompt response (not logged)", AutoSize = true });
        var input = new TextBox { UseSystemPasswordChar = true, Dock = DockStyle.Top };
        layout.Controls.Add(input);
        var send = new Button { Text = "Send", DialogResult = DialogResult.OK, AutoSize = true };
        layout.Controls.Add(send); dialog.Controls.Add(layout); dialog.AcceptButton = send;
        if (dialog.ShowDialog(this) != DialogResult.OK || input.Text.Length == 0) return;
        if (_process != proc) { Log("Core changed; input was not sent."); return; }
        try
        {
            if (proc.HasExited) { Log("Core exited; input was not sent."); return; }
            await proc.StandardInput.WriteLineAsync(input.Text);
            await proc.StandardInput.FlushAsync();
            Log("Input sent to core.");
        }
        catch { Log("Could not send input to core."); }
    }

    private void ShowProxyInfo()
    {
        chkShowLog.Checked = true; // the info is written to the log
        var secrets = Directory.GetFiles(AppContext.BaseDirectory, "aether*.toml").Length;
        var head = Color.Blue; Color? info = null; var tip = Color.DarkOrange;
        Log("=== Proxy info ===", head);
        Log($"System proxy: {SystemProxy.Status()}", info);
        Log($"Proxy {Aether.ProxyPort} (HTTP + SOCKS5, system proxy) | core: SOCKS5 {Aether.SocksPort}, HTTP {Aether.CoreHttpPort}", info);
        Log($"aether.exe: {(_process is { HasExited: false } ? "running" : "stopped")} | {lblStatus.Text.TrimStart('●', ' ')} | {lblDelay.Text}", info);
        Log("Presets: " + string.Join(", ", Aether.Presets.Select(p => p.Name)), info);
        Log("Cleanup: form close, --watchdog copy, hidden PowerShell guard, reset on startup.", info);
        Log("=== Recommendations ===", head);
        Log($"1. {secrets} aether*.toml file(s) beside the exe hold private keys/tokens: keep this folder private, rotate keys if shared.", tip);
        Log("2. Enable 'Set system proxy' only when needed; anything with its own proxy settings can bypass it.", tip);
        Log($"3. Auto rotates the default protocols ({(int)numTrySeconds.Value}s each), or your own order from Core settings > Auto order. Psiphon may need a longer try time.", tip);
    }

    private void SetStatus(string text, Color color)
    {
        lblStatus.Text = "\u25CF " + text;
        lblStatus.AccessibleName = "Connection status: " + text;
        lblStatus.ForeColor = color;
        prgConnecting.Visible = color == Palette.Connecting;
        AnimateConnectButton(color == Palette.Connecting);
    }

    // Light colors the Connect button drifts through while connecting, same as the Android app; t runs 0..1.
    internal static readonly Color[] LightColors =
        [ColorTranslator.FromHtml("#FDE68A"), ColorTranslator.FromHtml("#FBCFE8"), ColorTranslator.FromHtml("#DDD6FE"),
         ColorTranslator.FromHtml("#BAE6FD"), ColorTranslator.FromHtml("#BBF7D0")];
    internal static Color LightColorAt(double t)
    {
        double x = (t - Math.Floor(t)) * LightColors.Length, f = x - Math.Floor(x);
        Color a = LightColors[(int)x % LightColors.Length], b = LightColors[((int)x + 1) % LightColors.Length];
        int Mix(int from, int to) => (int)Math.Round(from + (to - from) * f);
        return Color.FromArgb(Mix(a.R, b.R), Mix(a.G, b.G), Mix(a.B, b.B));
    }

    private readonly System.Windows.Forms.Timer _buttonTimer = new() { Interval = 50 };
    private readonly Stopwatch _buttonClock = new();

    // Only the fill color changes; size and shape stay. Holds one color when Windows animations are off.
    private void AnimateConnectButton(bool on)
    {
        if (on == _buttonClock.IsRunning) return; // already in that state
        if (!on)
        {
            _buttonTimer.Stop(); _buttonClock.Reset();
            btnConnect.UseVisualStyleBackColor = true; // back to the normal Windows button
            return;
        }
        _buttonClock.Restart();
        btnConnect.BackColor = LightColors[0];
        if (SystemInformation.UIEffectsEnabled) _buttonTimer.Start();
    }

    private void Log(string msg) => Log(msg, null);

    private void Log(string msg, Color? color)
    {
        if (IsDisposed || Disposing) return;
        if (InvokeRequired)
        {
            try { BeginInvoke(() => Log(msg, color)); } catch (InvalidOperationException) { }
            return;
        }
        color ??= LogColor(msg);
        txtMiniLog.SelectionStart = txtMiniLog.TextLength;
        txtMiniLog.SelectionColor = color.Value;
        txtMiniLog.AppendText($"{DateTime.Now:HH:mm} {msg}{Environment.NewLine}");
        txtMiniLog.SelectionColor = txtMiniLog.ForeColor;
        txtMiniLog.ScrollToCaret();
        if (txtMiniLog.Lines.Length > 60) // only the latest lines: drop the oldest half
        {
            txtMiniLog.ReadOnly = false;
            txtMiniLog.Select(0, txtMiniLog.GetFirstCharIndexFromLine(30));
            txtMiniLog.SelectedText = "";
            txtMiniLog.ReadOnly = true;
            txtMiniLog.SelectionStart = txtMiniLog.TextLength;
            txtMiniLog.ScrollToCaret();
        }
    }

    // Green when fast, amber when slow, red when very slow or timed out.
    internal static Color PingColor(int? ms) =>
        ms is null || ms >= Aether.SlowPingMs ? Palette.Disconnected
        : ms < Aether.GoodPingMs ? Palette.Connected : Palette.Connecting;

    // Lines without their own color get one from what they say, in the classic palette.
    internal static Color LogColor(string msg) =>
        Regex.IsMatch(msg, @"\b(error|fail(ed|ure)?|could not|cannot|timeout|timed out|denied|refused)\b", RegexOptions.IgnoreCase) ? Palette.Disconnected
        : Regex.IsMatch(msg, @"\b(warn(ing)?|retry(ing)?|switching|reconnect(ing)?|slow)\b", RegexOptions.IgnoreCase) ? Palette.Connecting
        : Regex.IsMatch(msg, @"\b(connected|ready|success(ful)?|ok|started|listening)\b", RegexOptions.IgnoreCase) ? Palette.Connected
        : Color.Black;
}
