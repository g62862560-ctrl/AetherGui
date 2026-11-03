namespace AetherGui;

sealed class CoreSettingsForm : Form
{
    public CoreOptions Options { get; private set; }
    private readonly TextBox _arguments = Editor();
    private readonly TextBox _environment = Editor();
    private readonly NumericUpDown _timeout = new() { Minimum = 30, Maximum = 3600, Width = 120 };
    private readonly NumericUpDown _port = new() { Minimum = 1024, Maximum = 65535, Width = 100, Value = Aether.ProxyPort, AccessibleName = "Proxy port (HTTP and SOCKS5)" };
    private readonly ComboBox _testUrl = new() { DropDownStyle = ComboBoxStyle.DropDown, Width = 420, Text = Aether.TestUrl, AccessibleName = "Delay test URL" };
    private readonly IReadOnlyDictionary<int, int> _connectMs;
    private readonly CheckedListBox _order = new() { Dock = DockStyle.Fill, CheckOnClick = true, IntegralHeight = false, DisplayMember = nameof(Preset.Label), AccessibleName = "Auto protocol order" };
    private readonly CancellationTokenSource _helpCancellation = new(TimeSpan.FromSeconds(10));

    private static TextBox Editor() => new()
    {
        Multiline = true, AcceptsReturn = true, ScrollBars = ScrollBars.Both,
        WordWrap = false, Dock = DockStyle.Fill, Font = new Font("Courier New", 9F)
    };

    public CoreSettingsForm(CoreOptions options, IReadOnlyDictionary<int, int>? connectMs = null)
    {
        Options = options;
        _connectMs = connectMs ?? new Dictionary<int, int>();
        Text = "Core settings";
        // Same normal Windows look as the main window.
        Font = new Font("Segoe UI", 9F);
        BackColor = Palette.Background;
        AutoScaleMode = AutoScaleMode.Dpi;
        ClientSize = new Size(800, 650);
        MinimumSize = new Size(520, 460);
        StartPosition = FormStartPosition.CenterParent;
        var tabs = new TabControl { Dock = DockStyle.Fill };
        var settings = new TabPage("Settings") { Padding = new Padding(12), BackColor = Palette.Background };
        var helpTab = new TabPage("Bundled core help") { BackColor = Palette.Background };
        var help = Editor(); help.ReadOnly = true; help.Text = "Loading...";
        helpTab.Controls.Add(help);
        var orderTab = new TabPage("Auto order") { Padding = new Padding(12), BackColor = Palette.Background };
        orderTab.Controls.Add(OrderLayout());
        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 1 };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        void Add(Control control, float percent = 0)
        {
            layout.RowStyles.Add(percent > 0 ? new RowStyle(SizeType.Percent, percent) : new RowStyle(SizeType.AutoSize));
            layout.Controls.Add(control, 0, layout.RowCount++);
        }
        // A white line between sections.
        void Separator() => Add(new Panel { Height = 1, Dock = DockStyle.Fill, BackColor = Color.White, Margin = new Padding(0, 6, 0, 6) });
        var warning = new Label { AutoSize = true, Dock = DockStyle.Fill, Text =
            "Expert options apply to every protocol. Use a manual protocol for protocol-specific flags. " +
            "Protocols are app-managed; set the port below, not as arguments. Settings are stored in LocalAppData, NOT encrypted. " +
            "Direct routes bypass the tunnel; Gateway/debug logs can expose browsing or secrets. " +
            "SO_MARK is not a Windows feature. File options require existing accessible files." };
        Add(warning);
        Separator();
        Add(new Label { Text = "Arguments (JSON array): [\"--scan\", \"balanced\", \"--stats\"]", AutoSize = true });
        _arguments.Text = options.ArgumentsJson;
        Add(_arguments, 55);
        Separator();
        Add(new Label { Text = "Environment (JSON object): {\"AETHER_ROUTE_SNIFF_MS\":\"600\"}", AutoSize = true });
        _environment.Text = options.EnvironmentJson;
        Add(_environment, 45);
        Separator();
        var timeRow = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill };
        timeRow.Controls.Add(new Label { Text = "Advanced startup timeout (seconds)", AutoSize = true });
        _timeout.Value = options.StartupSeconds; timeRow.Controls.Add(_timeout);
        Add(timeRow);
        var portRow = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill };
        portRow.Controls.AddRange([new Label { Text = "Proxy port (HTTP + SOCKS5)", AutoSize = true }, _port]);
        Add(portRow);
        _testUrl.Items.AddRange(Aether.TestUrlSuggestions); // editable: pick one or type your own
        var urlRow = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Fill };
        urlRow.Controls.AddRange([new Label { Text = "Delay test URL", AutoSize = true }, _testUrl]);
        Add(urlRow);
        // Under the tabs, so the one Save also saves the Auto order tab.
        var buttons = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Bottom, Padding = new Padding(6) };
        var save = new Button { Text = "Save", AutoSize = true, MinimumSize = new Size(75, 23), Font = new Font("Segoe UI", 9F, FontStyle.Bold) }; // bold like the main window's primary button
        var reset = new Button { Text = "Reset fields", AutoSize = true };
        var cancel = new Button { Text = "Cancel", AutoSize = true, DialogResult = DialogResult.Cancel };
        save.Click += (_, _) => SaveOptions();
        reset.Click += (_, _) =>
        {
            _arguments.Text = "[]"; _environment.Text = "{}"; _timeout.Value = 300;
            _port.Value = Aether.DefaultProxyPort; _testUrl.Text = Aether.DefaultTestUrl; FillOrder(null);
        };
        buttons.Controls.AddRange([save, reset, cancel]);
        settings.Controls.Add(layout); tabs.TabPages.AddRange([settings, orderTab, helpTab]); Controls.AddRange([tabs, buttons]);
        CancelButton = cancel;
        Shown += async (_, _) =>
        {
            try
            {
                var text = await Aether.ReadHelpAsync(_helpCancellation.Token);
                if (!IsDisposed) help.Text = text.Replace("\r\n", "\n").Replace("\n", Environment.NewLine);
            }
            catch { if (!IsDisposed) help.Text = "Could not read aether.exe --help. Check the core executable beside the GUI."; }
        };
        FormClosed += (_, _) => _helpCancellation.Cancel();
    }

    // Checked protocols are tried top to bottom, then the unchecked rest are skipped.
    // The app keeps this order current after each connect; the user may move or uncheck any of them.
    private TableLayoutPanel OrderLayout()
    {
        FillOrder(Aether.SavedOrder);
        var moves = new FlowLayoutPanel { FlowDirection = FlowDirection.TopDown, AutoSize = true };
        var resetOrder = new Button { Text = "Reset order", AutoSize = true, AccessibleName = "Reset Auto order to the speed ranking" };
        resetOrder.Click += (_, _) => FillOrder(null);
        moves.Controls.AddRange([MoveButton("Up", -1), MoveButton("Down", 1), resetOrder]);
        var note = new Label { AutoSize = true, Dock = DockStyle.Fill, Text =
            "Auto tries the checked protocols from the top. After each try the app moves that protocol by its speed " +
            "(to the bottom if it failed); your own moves stay otherwise. Up/Down move all checked protocols one step. " +
            "Reset order restores the speed ranking (only this list); then Save." };

        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 2 };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.Controls.Add(note, 0, 0); layout.SetColumnSpan(note, 2);
        layout.Controls.Add(_order, 0, 1); layout.Controls.Add(moves, 1, 1);
        return layout;
    }

    // saved null or empty = the speed ranking of the fast protocols.
    private void FillOrder(int[]? saved)
    {
        var first = Aether.AutoOrder(_connectMs, saved).Select(p => Array.IndexOf(Aether.Presets, p)).ToArray();
        _order.Items.Clear();
        foreach (var i in first) _order.Items.Add(Aether.Presets[i], true);
        foreach (var i in Aether.MenuPresetIndexes.Except(first)) _order.Items.Add(Aether.Presets[i], false);
    }

    private Button MoveButton(string text, int delta)
    {
        var button = new Button { Text = text, AutoSize = true, AccessibleName = $"Move checked protocols {text.ToLower()}" };
        button.Click += (_, _) => MoveChecked(_order, delta);
        return button;
    }

    // Every checked item steps one place up (-1) or down (+1) past an unchecked neighbour; checked ones keep their own order.
    public static void MoveChecked(CheckedListBox list, int delta)
    {
        int n = list.Items.Count;
        for (int k = 0; k < n; k++)
        {
            int i = delta < 0 ? k : n - 1 - k, j = i + delta;
            if (j < 0 || j >= n || !list.GetItemChecked(i) || list.GetItemChecked(j)) continue;
            var item = list.Items[i];
            list.Items.RemoveAt(i); list.Items.Insert(j, item);
            list.SetItemChecked(j, true);
        }
    }

    private void SaveOptions()
    {
        var port = (int)_port.Value;
        if (Aether.ValidPort(port) is string error) { MessageBox.Show(this, error, Text); return; }
        if (Aether.ValidTestUrl(_testUrl.Text) is string urlError) { MessageBox.Show(this, urlError, Text); return; }
        var order = _order.CheckedItems.Cast<Preset>().Select(p => Array.IndexOf(Aether.Presets, p)).ToArray();
        if (order.Length == 0) { MessageBox.Show(this, "Check at least one protocol for Auto.", Text); return; }
        try
        {
            var options = CoreOptions.Parse(_arguments.Text, _environment.Text, (int)_timeout.Value);
            options.Save(); Aether.ProxyPort = port; Aether.TestUrl = _testUrl.Text.Trim(); Aether.SavedOrder = order; Options = options; DialogResult = DialogResult.OK; Close();
        }
        catch (Exception ex) when (ex is System.Text.Json.JsonException or FormatException)
        { MessageBox.Show(this, "Invalid JSON/settings. Use string arrays and string environment values; do not override managed protocols or ports.", Text); }
        catch { MessageBox.Show(this, "Could not save settings to LocalAppData.", Text); }
    }
}
