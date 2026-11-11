namespace AetherGui;

sealed class CoreSettingsForm : Form
{
    public CoreOptions Options { get; private set; }
    private readonly TextBox _arguments = Editor();
    private readonly TextBox _environment = Editor();
    private readonly NumericUpDown _timeout = new() { Minimum = 30, Maximum = 3600, Width = 120 };
    private readonly NumericUpDown _port = new() { Minimum = 1024, Maximum = 65535, Width = 100, Value = Aether.ProxyPort, AccessibleName = "Proxy port (HTTP and SOCKS5)" };
    private readonly ComboBox _testUrl = new() { DropDownStyle = ComboBoxStyle.DropDown, Width = 420, Text = Aether.TestUrl, AccessibleName = "Delay test URL" };
    private readonly CheckBox _realDelayTest = new() { Text = "Verify connection and measure delay with a real web request", AutoSize = true, Checked = Aether.RealDelayTest, AccessibleName = "Real delay test" };
    private readonly IReadOnlyDictionary<int, int> _connectMs;
    private readonly IReadOnlyDictionary<int, ProtocolStat> _stats;
    // Drawn by hand so each row can show how the protocol did next to its name.
    private readonly CheckedListBox _order = new() { Dock = DockStyle.Fill, CheckOnClick = true, IntegralHeight = false, DisplayMember = nameof(Preset.Label), AccessibleName = "Auto protocol order", AllowDrop = true, DrawMode = DrawMode.OwnerDrawFixed };
    private readonly int[] _menuOrder;
    private int[] _checkedOrder = [];
    public int[] MenuOrder { get; private set; } = [];
    private int _dragIndex = -1;
    private Point _dragStart;
    private readonly CancellationTokenSource _helpCancellation = new(TimeSpan.FromSeconds(10));

    private static TextBox Editor() => new()
    {
        Multiline = true, AcceptsReturn = true, ScrollBars = ScrollBars.Both,
        WordWrap = false, Dock = DockStyle.Fill, Font = new Font("Courier New", 9F)
    };

    public CoreSettingsForm(CoreOptions options, IReadOnlyDictionary<int, int>? connectMs = null, int[]? menuOrder = null, IReadOnlyDictionary<int, ProtocolStat>? stats = null)
    {
        Options = options;
        _stats = stats ?? new Dictionary<int, ProtocolStat>();
        _connectMs = connectMs ?? new Dictionary<int, int>();
        _checkedOrder = Aether.SavedOrder is { Length: > 0 } saved
            ? saved : Aether.AutoOrder(_connectMs).Select(p => Array.IndexOf(Aether.Presets, p)).ToArray();
        _menuOrder = menuOrder is { Length: > 0 } order ? order : Aether.MenuPresetIndexes;
        MenuOrder = _menuOrder;
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
        _realDelayTest.CheckedChanged += (_, _) => _testUrl.Enabled = _realDelayTest.Checked;
        _testUrl.Enabled = _realDelayTest.Checked;
        Add(_realDelayTest);
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
            _port.Value = Aether.DefaultProxyPort; _realDelayTest.Checked = true; _testUrl.Text = Aether.DefaultTestUrl; ResetOrder();
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
        FillOrder(_menuOrder);
        _order.ItemHeight = Font.Height + 8;
        _order.DrawItem += DrawOrderItem;
        _order.MouseDown += OrderMouseDown;
        _order.MouseMove += OrderMouseMove;
        _order.DragEnter += (_, e) => e.Effect = e.Data?.GetDataPresent(typeof(int)) == true ? DragDropEffects.Move : DragDropEffects.None;
        _order.DragOver += (_, e) => e.Effect = e.Data?.GetDataPresent(typeof(int)) == true ? DragDropEffects.Move : DragDropEffects.None;
        _order.DragDrop += OrderDragDrop;
        var resetOrder = new Button { Text = "Reset order", AutoSize = true, AccessibleName = "Reset Auto order to the speed ranking" };
        resetOrder.Click += (_, _) => ResetOrder();
        var note = new Label { AutoSize = true, Dock = DockStyle.Fill, Text =
            "Auto tries the checked protocols from the top. After each try the app moves that protocol by its speed " +
            "(to the bottom if it failed); your own moves stay otherwise. Drag a protocol to reorder. " +
            "Reset order restores the speed ranking (only this list); then Save. " +
            "Each row shows how the protocol did on this device: successful connects, failures, average connect time and when it last worked." };

        var layout = new TableLayoutPanel { Dock = DockStyle.Fill, ColumnCount = 2, RowCount = 2 };
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
        layout.ColumnStyles.Add(new ColumnStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        layout.RowStyles.Add(new RowStyle(SizeType.Percent, 100));
        layout.Controls.Add(note, 0, 0); layout.SetColumnSpan(note, 2);
        layout.Controls.Add(_order, 0, 1); layout.Controls.Add(resetOrder, 1, 1);
        return layout;
    }

    internal static string Ago(long epochSeconds)
    {
        var s = DateTimeOffset.UtcNow.ToUnixTimeSeconds() - epochSeconds;
        return s < 3600 ? $"{Math.Max(1, s / 60)}m ago" : s < 86400 ? $"{s / 3600}h ago" : $"{s / 86400}d ago";
    }

    // Name, then the verdict (the answer) in color, then the numbers behind it.
    private void DrawOrderItem(object? sender, DrawItemEventArgs e)
    {
        e.DrawBackground();
        if (e.Index < 0) return;
        var preset = (Preset)_order.Items[e.Index];
        var st = _stats.GetValueOrDefault(Array.IndexOf(Aether.Presets, preset)) ?? new ProtocolStat();
        var state = _order.GetItemChecked(e.Index) ? System.Windows.Forms.VisualStyles.CheckBoxState.CheckedNormal : System.Windows.Forms.VisualStyles.CheckBoxState.UncheckedNormal;
        var glyph = CheckBoxRenderer.GetGlyphSize(e.Graphics, state);
        CheckBoxRenderer.DrawCheckBox(e.Graphics, new Point(e.Bounds.X + 2, e.Bounds.Y + (e.Bounds.Height - glyph.Height) / 2), state);
        var selected = (e.State & DrawItemState.Selected) != 0;
        var (verdict, color) = st.Verdict switch
        {
            "good" => ("Works for you", Palette.Connected),
            "bad" => ("Often fails", Palette.Disconnected),
            "maybe" => ("Too few tries", Palette.Connecting),
            _ => ("Not tried yet", Palette.MutedText)
        };
        var details = st.Tries == 0 ? "" : $"{st.Ok} ok · {st.Fail} failed"
            + (st.Ok > 0 ? $" · avg {st.AvgMs / 1000.0:0.0}s" : "") + (st.LastOk > 0 ? $" · last ok {Ago(st.LastOk)}" : "");
        const TextFormatFlags flags = TextFormatFlags.VerticalCenter | TextFormatFlags.Left | TextFormatFlags.EndEllipsis | TextFormatFlags.NoPrefix;
        int x = e.Bounds.X + glyph.Width + 8, nameWidth = Math.Max(140, e.Bounds.Width * 2 / 5), verdictWidth = TextRenderer.MeasureText("Too few tries ", e.Font).Width;
        TextRenderer.DrawText(e.Graphics, preset.Label, e.Font, new Rectangle(x, e.Bounds.Y, nameWidth, e.Bounds.Height), e.ForeColor, flags);
        TextRenderer.DrawText(e.Graphics, verdict, e.Font, new Rectangle(x + nameWidth, e.Bounds.Y, verdictWidth, e.Bounds.Height), selected ? e.ForeColor : color, flags);
        TextRenderer.DrawText(e.Graphics, details, e.Font, Rectangle.FromLTRB(x + nameWidth + verdictWidth, e.Bounds.Top, e.Bounds.Right, e.Bounds.Bottom), selected ? e.ForeColor : Palette.MutedText, flags);
        e.DrawFocusRectangle();
    }

    private void OrderMouseDown(object? sender, MouseEventArgs e)
    {
        _dragIndex = _order.IndexFromPoint(e.Location);
        _dragStart = e.Location;
    }

    private void OrderMouseMove(object? sender, MouseEventArgs e)
    {
        if (e.Button != MouseButtons.Left || _dragIndex < 0 ||
            (Math.Abs(e.X - _dragStart.X) < 5 && Math.Abs(e.Y - _dragStart.Y) < 5)) return;
        var index = _dragIndex;
        _dragIndex = -1;
        if (index < _order.Items.Count) _order.DoDragDrop(index, DragDropEffects.Move);
    }

    private void OrderDragDrop(object? sender, DragEventArgs e)
    {
        if (e.Data?.GetData(typeof(int)) is not int from) return;
        var to = _order.IndexFromPoint(_order.PointToClient(new Point(e.X, e.Y)));
        if (to < 0) to = _order.Items.Count - 1;
        if (to == from) return;
        var item = _order.Items[from];
        var on = _order.GetItemChecked(from);
        _order.Items.RemoveAt(from);
        _order.Items.Insert(to, item);
        _order.SetItemChecked(to, on);
        _order.SelectedIndex = to;
    }

    private void ResetOrder()
    {
        _checkedOrder = Aether.AutoOrder(_connectMs).Select(p => Array.IndexOf(Aether.Presets, p)).ToArray();
        FillOrder([.. _checkedOrder, .. Aether.MenuPresetIndexes.Except(_checkedOrder)]);
    }

    private void FillOrder(int[] fullOrder)
    {
        var checkedSet = _checkedOrder.ToHashSet();
        _order.Items.Clear();
        foreach (var i in fullOrder)
            if (i >= 0 && i < Aether.Presets.Length && !_order.Items.Cast<Preset>().Any(p => p == Aether.Presets[i]))
                _order.Items.Add(Aether.Presets[i], checkedSet.Contains(i));
        foreach (var i in Aether.MenuPresetIndexes.Except(fullOrder))
            _order.Items.Add(Aether.Presets[i], checkedSet.Contains(i));
    }

    private void SaveOptions()
    {
        var port = (int)_port.Value;
        if (Aether.ValidPort(port) is string error) { MessageBox.Show(this, error, Text); return; }
        if (_realDelayTest.Checked && Aether.ValidTestUrl(_testUrl.Text) is string urlError) { MessageBox.Show(this, urlError, Text); return; }
        var order = _order.CheckedItems.Cast<Preset>().Select(p => Array.IndexOf(Aether.Presets, p)).ToArray();
        if (order.Length == 0) { MessageBox.Show(this, "Check at least one protocol for Auto.", Text); return; }
        MenuOrder = _order.Items.Cast<Preset>().Select(p => Array.IndexOf(Aether.Presets, p)).ToArray();
        _checkedOrder = order;
        try
        {
            var options = CoreOptions.Parse(_arguments.Text, _environment.Text, (int)_timeout.Value);
            options.Save(); Aether.ProxyPort = port; Aether.RealDelayTest = _realDelayTest.Checked; Aether.TestUrl = _testUrl.Text.Trim(); Aether.SavedOrder = order; Options = options; DialogResult = DialogResult.OK; Close();
        }
        catch (Exception ex) when (ex is System.Text.Json.JsonException or FormatException)
        { MessageBox.Show(this, "Invalid JSON/settings. Use string arrays and string environment values; do not override managed protocols or ports.", Text); }
        catch { MessageBox.Show(this, "Could not save settings to LocalAppData.", Text); }
    }
}
