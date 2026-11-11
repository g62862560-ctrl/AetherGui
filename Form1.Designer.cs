namespace AetherGui;

// Normal Windows look: system colors, themed controls, Segoe UI, white log, status bar.
static class Palette
{
    public static readonly Color Background = SystemColors.Control; // the normal Windows window color
    public static readonly Color LogBackground = Color.White;
    public static readonly Color MutedText = ColorTranslator.FromHtml("#404040");
    public static readonly Color Accent = ColorTranslator.FromHtml("#000080");
    public static readonly Color AccentPressed = ColorTranslator.FromHtml("#800080");
    public static readonly Color Connected = ColorTranslator.FromHtml("#008000");
    public static readonly Color Connecting = ColorTranslator.FromHtml("#806000");
    public static readonly Color Disconnected = ColorTranslator.FromHtml("#800000");
}

partial class Form1
{
    private Button btnConnect = null!;
    private Button btnNextProtocol = null!;
    private NumericUpDown numTrySeconds = null!;
    private ToolStripMenuItem btnInfo = null!;
    private ToolStripMenuItem btnCoreSettings = null!;
    private ToolStripMenuItem btnCoreInput = null!;
    private ToolStripMenuItem btnUpdates = null!;
    private Label lblStatus = null!;
    private ToolStripStatusLabel lblDelay = null!;
    private Button btnReset = null!;
    private Label lblScan = null!;
    private ComboBox cboScan = null!;
    private RichTextBox txtMiniLog = null!;
    private ToolStripMenuItem chkStartup = null!;
    private CheckBox chkSysProxy = null!;
    private CheckBox chkShowLog = null!;
    private ToolStripMenuItem chkPsiphon = null!;
    private ProgressBar prgConnecting = null!;
    private TableLayoutPanel shell = null!;

    // Normal themed Windows button; the primary one is bold.
    private static Button ClassicButton(string text, bool primary = false)
    {
        var button = new Button
        {
            Text = text,
            AutoSize = true, MinimumSize = new Size(90, 23), Margin = new Padding(0, 0, 6, 6)
        };
        if (primary) button.Font = new Font("Segoe UI", 9F, FontStyle.Bold);
        return button;
    }

    // Same-size action button: a symbol over a short caption, filling its column.
    private static Button ActionButton(string glyph, string caption, string accessibleName) => new()
    {
        Text = glyph + "\n" + caption, AccessibleName = accessibleName, Dock = DockStyle.Fill,
        MinimumSize = new Size(0, 56), Margin = new Padding(3), UseVisualStyleBackColor = true
    };

    // Gray panel with an etched 3D frame, named so tests can find it.
    private static Panel Card(string name)
    {
        var card = new Panel { Name = name, Dock = DockStyle.Fill, BackColor = Palette.Background, Padding = new Padding(8) };
        card.Paint += (_, e) => ControlPaint.DrawBorder3D(e.Graphics, card.ClientRectangle, Border3DStyle.Etched);
        card.Resize += (_, _) => card.Invalidate();
        return card;
    }

    private void InitializeComponent()
    {
        Font = new Font("Segoe UI", 9F);
        var bold = new Font("Segoe UI", 9F, FontStyle.Bold);

        // Three same-size buttons in one row; the caption sits inside, under a symbol.
        btnConnect = ActionButton("⏻", "Connect", "Connect securely");
        btnConnect.Font = new Font("Segoe UI", 9F, FontStyle.Bold); // the primary one is bold
        btnConnect.Click += btnConnect_Click;
        btnReset = ActionButton("↻", "Reset", "Reset order and connect");
        btnReset.AccessibleDescription = "Forget the learned speeds and order, then connect with Auto";
        btnReset.Click += btnReset_Click;
        btnNextProtocol = ActionButton("⏭", "Next", "Next protocol");
        btnNextProtocol.Enabled = false;
        btnNextProtocol.AccessibleDescription = "Stop the current protocol attempt and try the next one";
        btnNextProtocol.Click += btnNextProtocol_Click;
        var actionRow = new TableLayoutPanel { Dock = DockStyle.Top, AutoSize = true, ColumnCount = 3, RowCount = 1, Margin = new Padding(0, 6, 0, 6) };
        for (var i = 0; i < 3; i++) actionRow.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100f / 3)); // equal width at any window size
        actionRow.Controls.Add(btnConnect, 0, 0);
        actionRow.Controls.Add(btnReset, 1, 0);
        actionRow.Controls.Add(btnNextProtocol, 2, 0);
        numTrySeconds = new NumericUpDown
        {
            Minimum = 5, Maximum = 3600, Width = 60, Margin = new Padding(0, 0, 0, 6),
            AccessibleName = "Auto protocol try seconds",
            AccessibleDescription = "Seconds Auto waits for each protocol before trying the next one"
        };

        // Rarely used actions and options live in a classic menu bar so the window shows only what connecting needs.
        btnInfo = new ToolStripMenuItem("&Proxy info") { AccessibleDescription = "Write proxy ports and security recommendations to the activity log" };
        btnInfo.Click += (_, _) => ShowProxyInfo();
        btnCoreSettings = new ToolStripMenuItem("Core &settings...");
        btnCoreSettings.Click += (_, _) => ShowCoreSettings();
        btnCoreInput = new ToolStripMenuItem("Core &input...") { Enabled = false };
        btnCoreInput.Click += async (_, _) => await SendCoreInputAsync();
        btnUpdates = new ToolStripMenuItem("Check for &updates...") { AccessibleDescription = "Check for a new AetherGui release and a newer core" };
        btnUpdates.Click += async (_, _) => await CheckUpdatesAsync(interactive: true);

        lblStatus = new Label { Text = "●  Disconnected", ForeColor = Palette.Disconnected, AutoSize = true, Font = new Font("Segoe UI", 10F, FontStyle.Bold), Margin = new Padding(0, 0, 0, 0), AccessibleName = "Connection status: Disconnected" };
        // Status bar along the bottom, with a sunken pane; no sizing grip since the size is locked.
        lblDelay = new ToolStripStatusLabel("Delay: -") { Spring = false, TextAlign = ContentAlignment.MiddleLeft, BorderSides = ToolStripStatusLabelBorderSides.All, BorderStyle = Border3DStyle.SunkenOuter };
        var statusBar = new StatusStrip { RenderMode = ToolStripRenderMode.System, BackColor = Palette.Background, SizingGrip = false };
        statusBar.Items.Add(lblDelay);
        statusBar.Items.Add(new ToolStripStatusLabel($"AetherGui {Aether.AppVersion}") { Spring = true, TextAlign = ContentAlignment.MiddleRight });
        // Tall enough to show the classic chunky blocks.
        prgConnecting = new ProgressBar
        {
            Style = SystemInformation.UIEffectsEnabled ? ProgressBarStyle.Marquee : ProgressBarStyle.Continuous,
            Value = 100, MarqueeAnimationSpeed = 30, Dock = DockStyle.Top, Height = 14, Visible = false,
            Margin = new Padding(0, 4, 0, 0)
        };

        lblScan = new Label { Text = "Server search", Font = bold, AutoSize = true, Margin = new Padding(0, 6, 0, 2) };
        cboScan = new ComboBox { DropDownStyle = ComboBoxStyle.DropDownList, Dock = DockStyle.Top, DropDownWidth = 360, Margin = new Padding(0, 0, 0, 4), AccessibleName = "Server search mode" };

        chkSysProxy = new CheckBox { Text = "Set Windows system proxy", AutoSize = true, Margin = new Padding(0, 8, 0, 0) };
        chkStartup = new ToolStripMenuItem("&Connect on startup") { CheckOnClick = true };
        chkPsiphon = new ToolStripMenuItem("Open &Psiphon after connecting") { CheckOnClick = true };

        var menu = new MenuStrip { RenderMode = ToolStripRenderMode.System, BackColor = Palette.Background, Dock = DockStyle.Top };
        menu.Items.AddRange([
            new ToolStripMenuItem("&Options", null, chkStartup, chkPsiphon),
            new ToolStripMenuItem("&Tools", null, btnCoreSettings, btnCoreInput, btnInfo),
            new ToolStripMenuItem("&Help", null, btnUpdates)]);

        var status = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Top, WrapContents = true, Margin = Padding.Empty };
        status.Controls.Add(lblStatus);

        var tryRow = new FlowLayoutPanel { AutoSize = true, Dock = DockStyle.Top, WrapContents = true, Margin = Padding.Empty };
        tryRow.Controls.Add(new Label { Text = "Auto try (seconds)", AutoSize = true, Margin = new Padding(0, 5, 4, 0) });
        tryRow.Controls.Add(numTrySeconds);

        var controlLayout = new TableLayoutPanel { Dock = DockStyle.Top, AutoSize = true, ColumnCount = 1, RowCount = 8, Margin = Padding.Empty };
        controlLayout.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100)); // fit the panel, never the content
        for (var i = 0; i < 8; i++) controlLayout.RowStyles.Add(new RowStyle(SizeType.AutoSize));
        // The buttons sit right under the status so they stay in view; the rest scrolls if large text needs more room.
        controlLayout.Controls.Add(status, 0, 0);
        controlLayout.Controls.Add(prgConnecting, 0, 1);
        controlLayout.Controls.Add(actionRow, 0, 2);
        controlLayout.Controls.Add(tryRow, 0, 3);
        controlLayout.Controls.Add(lblScan, 0, 4);
        controlLayout.Controls.Add(cboScan, 0, 5);
        controlLayout.Controls.Add(chkSysProxy, 0, 6);
        chkShowLog = new CheckBox { Text = "Show latest activity", AutoSize = true, Margin = new Padding(0, 4, 0, 2) };
        controlLayout.Controls.Add(chkShowLog, 0, 7);

        // Small sunken log of the latest lines that fills the space left under the controls.
        txtMiniLog = new RichTextBox
        {
            Dock = DockStyle.Fill, ReadOnly = true, BorderStyle = BorderStyle.Fixed3D, BackColor = Palette.LogBackground,
            Font = new Font("Courier New", 8.25F), ScrollBars = RichTextBoxScrollBars.Vertical, MinimumSize = new Size(0, 40),
            TabStop = false, AccessibleName = "Latest activity", Visible = false // hidden until Show latest activity is ticked
        };

        var controlScroll = new Panel { Dock = DockStyle.Fill, AutoScroll = true, Margin = Padding.Empty }; // scrollbar only when needed
        // Docked controls lay out last-added first: the controls take the top, the mini log fills the rest.
        controlScroll.Controls.Add(txtMiniLog);
        controlScroll.Controls.Add(controlLayout);

        var connectionCard = Card("connectionPanel");
        connectionCard.Controls.Add(controlScroll);

        shell = new TableLayoutPanel { Dock = DockStyle.Fill, Padding = new Padding(8), ColumnCount = 1, RowCount = 1, BackColor = Palette.Background };
        shell.Controls.Add(connectionCard, 0, 0);

        Text = "Aether — Private network client";
        AutoScaleMode = AutoScaleMode.Dpi;
        BackColor = Palette.Background;
        Size = new Size(420, 600);
        FormBorderStyle = FormBorderStyle.FixedSingle; // size is locked; only Show latest activity changes the height
        MaximizeBox = false;
        MinimumSize = new Size(380, 420); // sized for the hidden log; ShowLog grows it
        StartPosition = FormStartPosition.CenterScreen;
        KeyPreview = true;
        // Docked controls lay out last-added first: the menu takes the top, then the shell fills the rest.
        Controls.Add(shell);
        Controls.Add(statusBar);
        Controls.Add(menu);
        MainMenuStrip = menu;
    }
}
