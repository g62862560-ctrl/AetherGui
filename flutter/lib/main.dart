import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'aether.dart';
import 'auto_order_page.dart';
import 'core_options.dart';
import 'core_settings_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Aether.init();
  runApp(
    MaterialApp(
      title: 'Aether VPN',
      debugShowCheckedModeBanner: false,
      theme: Palette.theme,
      home: const HomePage(),
    ),
  );
}

// One place for every color, and the dark theme built from them.
abstract final class Palette {
  static const background = Color(0xFF121212);
  static const surface = Color(0xFF1E1E1E);
  static const accent = Color(0xFFB585FF); // neon purple
  static const secondaryText = Color(0xFF9E9E9E);
  static const connected = Color(0xFF4ADE80); // neon green
  static const connecting = Color(0xFFFBBF24);
  static const disconnected = Color(0xFFF87171); // muted coral

  static final theme = ThemeData(
    brightness: Brightness.dark,
    scaffoldBackgroundColor: background,
    colorScheme: ColorScheme.fromSeed(
      seedColor: accent,
      brightness: Brightness.dark,
    ).copyWith(primary: accent, surface: background),
    appBarTheme: const AppBarTheme(
      backgroundColor: background,
      surfaceTintColor: Colors.transparent,
    ),
    cardTheme: CardThemeData(
      color: surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.zero,
      subtitleTextStyle: TextStyle(color: secondaryText, fontSize: 13),
    ),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  static const maxSteps = 8; // lines kept in the connection report on Home
  static const startupDelayMs =
      1000; // pause before the automatic connect on startup
  static const red = Palette.disconnected,
      orange = Palette.connecting,
      seaGreen = Palette.connected;

  AetherProcess? _process;
  Cancel? _ct;
  bool _autoConnect = false;
  CoreOptions _coreOptions = const CoreOptions();
  int _preset = -1; // index into Aether.presets, -1 = Auto (rotate through all)
  String _scan = 'turbo'; // AETHER_SCAN: turbo or balanced
  bool _vpn = true; // full-device VPN (tun); false = only serve the local proxy
  bool _showActivity = true;
  String _status = 'Disconnected';
  Color _statusColor = red;
  String _delay = ''; // e.g. '24 ms', shown in the button while connected
  String? _route; // preset being tried or used right now
  String? _error; // latest failure, shown on Home until connected or dismissed
  int? _busyPort, _freePort; // occupied port behind _error, and a free one to offer
  final _changes = ValueNotifier(0); // tells an open Settings page to rebuild
  final _lines = <(String, Color?)>[];
  final _steps = <(String, Color?)>[]; // this connect's report on Home; no color = in progress
  final _scroll = ScrollController();
  final _httpPortText = TextEditingController(),
      _socksPortText = TextEditingController();
  // preset index -> ms its last connect took, -1 = failed; orders Auto
  var _connectMs = <int, int>{};
  // Auto's order as preset indexes, kept current after each connect and editable; empty = speed ranking
  var _order = <int>[];

  File get _settings => File('${Aether.dir}/settings.txt');

  @override
  void initState() {
    super.initState();
    try {
      final s = _settings.readAsStringSync();
      _autoConnect = s.contains('AutoConnect=1');
      final i =
          int.tryParse(
            RegExp(r'Preset=(-?\d+)').firstMatch(s)?.group(1) ?? '',
          ) ??
          -1;
      _preset = i >= -1 && i < Aether.presets.length ? i : -1;
      if (s.contains('Scan=balanced')) _scan = 'balanced';
      _vpn = !s.contains('Mode=proxy');
      _showActivity = !s.contains('ShowActivity=0');
      final http = RegExp(r'HttpPort=(\d+)').firstMatch(s)?.group(1) ?? '';
      final socks = RegExp(r'SocksPort=(\d+)').firstMatch(s)?.group(1) ?? '';
      if (Aether.portError(http, int.tryParse(socks) ?? 0) == null &&
          Aether.portError(socks, int.parse(http)) == null) {
        Aether.httpPort = int.parse(http);
        Aether.socksPort = int.parse(socks);
      }
      _connectMs = Aether.parseConnectMs(
        RegExp(r'ConnectMs=(.*)').firstMatch(s)?.group(1),
      );
      _order = Aether.parseOrder(
        RegExp(r'AutoOrder=(.*)').firstMatch(s)?.group(1),
      );
    } catch (_) {}
    try {
      _coreOptions = CoreOptions.load(Aether.dir);
    } catch (_) {
      _autoConnect = false;
      _logError(
        'Could not load core settings. Review settings before connecting.',
      );
    }
    // Fix the shuffled ties once, so the order shown in Settings does not jump on every rebuild.
    if (_order.isEmpty) _order = _autoIndexes();
    _httpPortText.text = '${Aether.httpPort}';
    _socksPortText.text = '${Aether.socksPort}';
    _checkUpdates(interactive: false);
    if (_autoConnect) {
      _log('Auto-connecting in ${startupDelayMs ~/ 1000}s...');
      Future.delayed(const Duration(milliseconds: startupDelayMs), () {
        if (mounted && _autoConnect && _ct == null) _connect();
      });
    }
  }

  @override
  void dispose() {
    _ct?.cancel();
    _killProcess();
    _scroll.dispose();
    _httpPortText.dispose();
    _socksPortText.dispose();
    _changes.dispose();
    super.dispose();
  }

  Future<void> _connect() async {
    if (_ct != null) return _ct!.cancel();
    final ct = _ct = Cancel();
    setState(() {
      _clearError();
      _steps.clear();
    });
    await _run(ct);
    _ct = null;
    if (mounted) setState(() {});
  }

  void _saveSettings() => _settings.writeAsStringSync(
    'AutoConnect=${_autoConnect ? 1 : 0}\nPreset=$_preset\nScan=$_scan\n'
    'Mode=${_vpn ? 'vpn' : 'proxy'}\n'
    'ShowActivity=${_showActivity ? 1 : 0}\n'
    'HttpPort=${Aether.httpPort}\nSocksPort=${Aether.socksPort}\n'
    'ConnectMs=${Aether.formatConnectMs(_connectMs)}\n'
    'AutoOrder=${_order.join(',')}\n',
  );

  List<int> _autoIndexes([List<int>? saved]) => [
    for (final p in Aether.autoOrder(_connectMs, saved))
      Aether.presets.indexOf(p),
  ];

  // Auto: try the fast presets, fastest past connect first; one that times out or drops is not retried until all others were tried.
  // A chosen preset (including the slow manual-only ones) is simply retried.
  Future<void> _run(Cancel ct) async {
    final untried = <Preset>[];
    try {
      if (!File(Aether.exe).existsSync())
        return _logError(
          'aether binary missing: run fetch_aether.sh and rebuild.',
        );
      // Started now, while the app is in front: Android refuses to start services from the background.
      if (!_vpn) await Aether.keepAlive();
      while (true) {
        if (untried.isEmpty) {
          untried.addAll(
            _preset < 0
                ? Aether.autoOrder(_connectMs, _order)
                : [Aether.presets[_preset]],
          );
        }
        await _connectAndMonitor(untried.removeAt(0), ct);
        await ct.delay(1000);
      }
    } on Cancelled {
      // user pressed Disconnect, or a port conflict stopped the rotation
      if (_busyPort == null) _addStep('Stopped.', orange);
    } catch (e) {
      _logError('Connection failed: $e');
      _addStep('Connection failed.', red);
    } finally {
      Aether.vpnStop();
      _killProcess();
      _setStatus('Disconnected', red);
      _setDelay('');
      _route = null;
    }
  }

  // Returns when the preset fails to connect within the timeout, or after a connected session drops.
  Future<void> _connectAndMonitor(Preset p, Cancel ct) async {
    _step('Trying ${p.name}...');
    _route = p.name;
    _setStatus('Connecting: ${p.name}', orange);
    var coreFailed = false, portConflict = false;
    void coreLog(String line) {
      final error = Aether.coreError(line);
      _log(line, error == null ? null : red);
      // A working session can log passing errors; those stay in the activity log.
      if (error == null || _statusColor == seaGreen) return;
      coreFailed = true;
      final port = Aether.busyPort(error);
      if (port != null &&
          (port == Aether.socksPort || port == Aether.httpPort)) {
        portConflict = true;
        _portInUse(port, ct);
      } else if (mounted) {
        setState(() => _error = '${p.name}: $error');
        _addStep('${p.name}: core reported an error.', red);
      }
    }

    final proc = _process = await Aether.start(p, coreLog, _coreOptions, _scan);
    if (proc == null) {
      if (mounted) {
        setState(
          () => _error =
              '${p.name}: core start failed. Check bundled binaries and core settings.',
        );
      }
      _addStep('${p.name}: core start failed.', red);
      return;
    }
    _step('Core started, waiting for local proxy...');

    final took = Stopwatch()..start();
    int? ms = await Aether.waitConnected(
      proc,
      _coreOptions.isConfigured ? _coreOptions.startupSeconds : p.startupSecs,
      ct,
      _step,
    );
    if (portConflict) return _killProcess(); // says nothing about this preset
    _connectMs[Aether.presets.indexOf(p)] = ms == null
        ? -1
        : took.elapsedMilliseconds;
    _order = Aether.rerank(
      _autoIndexes(_order),
      _connectMs,
      Aether.presets.indexOf(p),
    );
    _saveSettings();
    if (ms == null) {
      final failure = proc.exited
          ? '${p.name}: process exited.'
          : '${p.name}: no internet, switching.';
      // Keep the core's own message: it says why, this line only says what happened.
      coreFailed ? _log(failure) : _logError(failure);
      _addStep(failure, red);
      _killProcess();
      return;
    }

    _setStatus('Connected: ${p.name}', seaGreen);
    if (mounted) setState(() => _error = null);
    _step(
      'Connected via ${p.name} in ${(took.elapsedMilliseconds / 1000).toStringAsFixed(1)}s, delay $ms ms.',
      seaGreen,
    );
    if (!_vpn) {
      _step(
        'Proxy only: HTTP 127.0.0.1:${Aether.httpPort}, SOCKS5 127.0.0.1:${Aether.socksPort}.',
        seaGreen,
      );
    } else if (await Aether.vpnStart()) {
      _step('VPN on: all apps go through aether.', seaGreen);
    } else {
      _logError('VPN permission denied: proxy only.');
      _addStep('VPN permission denied: proxy only.', red);
    }
    for (var fails = 0; fails < 2;) {
      _setDelay(ms == null ? 'timeout' : '$ms ms');
      await ct.delay(5000);
      if (proc.exited) break;
      ms = await Aether.ping(ct);
      fails = ms == null ? fails + 1 : 0;
    }
    _logError('${p.name}: connection lost, switching.');
    _addStep('${p.name}: connection lost, switching.', red);
    _killProcess();
  }

  // Every preset needs this port, so rotating on cannot help: stop and let the user choose.
  Future<void> _portInUse(int port, Cancel ct) async {
    final other = port == Aether.socksPort
        ? Aether.httpPort
        : Aether.socksPort;
    _logError('Port $port is in use by another app. Close it or pick a new port.');
    _addStep('Port $port is in use.', red);
    if (mounted) setState(() => _busyPort = port);
    ct.cancel();
    final free = await Aether.freePort(port, other);
    if (mounted && _busyPort == port) setState(() => _freePort = free);
  }

  void _usePort(int busy, int port) {
    if (busy == Aether.socksPort) {
      Aether.socksPort = port;
      _socksPortText.text = '$port';
    } else {
      Aether.httpPort = port;
      _httpPortText.text = '$port';
    }
    _saveSettings();
    _connect();
  }

  Future<void> _enterPort(int busy) async {
    final other = busy == Aether.socksPort
        ? Aether.httpPort
        : Aether.socksPort;
    final input = TextEditingController(text: _freePort?.toString() ?? '');
    final port = await showDialog<int>(
      context: context,
      builder: (context) {
        String? error;
        return StatefulBuilder(
          builder: (context, setDialog) {
            Future<void> submit() async {
              final problem = Aether.portError(input.text, other);
              final port = int.tryParse(input.text);
              final taken =
                  problem == null && !await Aether.portFree(port!);
              if (!context.mounted) return;
              if (problem == null && !taken) {
                Navigator.pop(context, port);
              } else {
                setDialog(() => error = problem ?? 'Port $port is in use');
              }
            }

            return AlertDialog(
              title: const Text('Choose a port'),
              content: TextField(
                controller: input,
                autofocus: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Port',
                  errorText: error,
                ),
                onSubmitted: (_) => submit(),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: submit,
                  child: const Text('Use and connect'),
                ),
              ],
            );
          },
        );
      },
    );
    // Let the closing dialog finish before disposing its controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    input.dispose();
    if (mounted && port != null && _ct == null) _usePort(busy, port);
  }

  void _killProcess() {
    _process?.p.kill(ProcessSignal.sigkill);
    _process = null;
  }

  Future<void> _showCoreSettings() async {
    final options = await Navigator.push<CoreOptions>(
      context,
      MaterialPageRoute(
        builder: (_) => CoreSettingsPage(options: _coreOptions),
      ),
    );
    if (mounted && options != null) setState(() => _coreOptions = options);
  }

  Future<void> _showAutoOrder() async {
    final order = await Navigator.push<List<int>>(
      context,
      MaterialPageRoute(
        builder: (_) => AutoOrderPage(
          order: _autoIndexes(_order),
          ranking: _autoIndexes(),
        ),
      ),
    );
    if (!mounted || order == null) return;
    setState(() => _order = order);
    _saveSettings();
  }

  Future<void> _sendCoreInput() async {
    final proc = _process;
    if (proc == null || proc.exited) return;
    final input = TextEditingController();
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Core input'),
        content: TextField(
          controller: input,
          autofocus: true,
          obscureText: true,
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
            labelText: 'Code or prompt response',
          ),
          onSubmitted: (value) => Navigator.pop(context, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, input.text),
            child: const Text('Send'),
          ),
        ],
      ),
    );
    // Let the closing dialog finish before disposing its controller.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    input.dispose();
    if (!mounted || value == null || value.isEmpty) return;
    if (_process != proc || proc.exited) {
      _log('Core changed while input was open. Input was not sent.');
      return;
    }
    try {
      proc.p.stdin.writeln(value);
      await proc.p.stdin.flush();
      _log('Input sent to core.');
    } catch (_) {
      _log('Could not send input to core.');
    }
  }

  // A new release is offered in a dialog, at startup too, so it is seen with the log hidden;
  // only the button also reports "up to date" and failures.
  Future<void> _checkUpdates({required bool interactive}) async {
    void tell(String msg) {
      _log(msg);
      if (interactive && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      }
    }

    if (interactive) _log('Checking for updates...');
    try {
      final have = await Aether.appVersion();
      final latest = await Aether.latestGuiRelease();
      final mine = Aether.parseVersion(have),
          theirs = Aether.parseVersion(latest?.$1);
      if (!mounted) return;
      if (latest == null ||
          mine == null ||
          theirs == null ||
          !Aether.isNewer(theirs, mine)) {
        if (interactive) tell('Up to date: Aether $have.');
        return;
      }
      _log('Aether ${latest.$1} is available (you have $have).', Colors.blue);
      if (!latest.$2.startsWith('https://github.com/')) return;
      final open = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Update available'),
          content: Text(
            'Aether ${latest.$1} is available (you have $have). Open the download page?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Later'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Open'),
            ),
          ],
        ),
      );
      if (open == true) await Aether.openUrl(latest.$2);
    } catch (e) {
      if (interactive) tell('Update check failed: $e');
    }
  }

  void _showProxyInfo() {
    if (!_showActivity) {
      setState(() => _showActivity = true); // the info is written to the log
      _saveSettings();
    }
    const head = Colors.blue, info = null, tip = Colors.orange;
    final secrets = Directory(Aether.dir)
        .listSync()
        .where((f) => RegExp(r'[/\\]aether[^/\\]*\.toml$').hasMatch(f.path))
        .length;
    _log('=== Proxy info ===', head);
    _log(
      'HTTP 127.0.0.1:${Aether.httpPort} | SOCKS5 127.0.0.1:${Aether.socksPort}',
      info,
    );
    _log(
      'aether: ${_process != null && !_process!.exited ? 'running' : 'stopped'} | $_status | delay $_delay',
      info,
    );
    _log('Presets: ${Aether.presets.map((p) => p.name).join(', ')}', info);
    _log(
      'Cleanup: Disconnect, or Android stops aether together with the app.',
      info,
    );
    _log(
      'Credits: aether by CluvexStudio (github.com/CluvexStudio) | VPN via hev-socks5-tunnel (heiher)',
      info,
    );
    _log('=== Recommendations ===', head);
    _log(
      '1. Allow the VPN prompt: it routes browsers/most apps through aether on any network.',
      tip,
    );
    _log(
      '2. $secrets aether*.toml file(s) in app storage hold private keys/tokens: rotate keys if the device is shared.',
      tip,
    );
    _log(
      '3. Auto rotates the fast protocols (30s each), or your own order from Settings > Auto order. Tor/Psiphon help on strict networks.',
      tip,
    );
  }

  void _setStatus(String text, Color color) {
    if (mounted)
      setState(() {
        _status = text;
        _statusColor = color;
      });
  }

  void _setDelay(String text) {
    if (mounted) setState(() => _delay = text);
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _changes.value++;
  }

  void _log(String msg, [Color? color]) {
    if (!mounted) return;
    final t = DateTime.now().toIso8601String().substring(11, 19);
    setState(() => _lines.add(('[$t] $msg', color)));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  void _step(String text, [Color? color]) {
    _log(text, color);
    _addStep(text, color);
  }

  void _addStep(String text, Color? color) {
    if (!mounted) return;
    setState(() {
      _steps.add((text, color));
      // Auto can rotate for a long time; the full history stays in the activity log.
      if (_steps.length > maxSteps) _steps.removeAt(0);
    });
  }

  void _clearError() {
    _error = null;
    _busyPort = null;
    _freePort = null;
  }

  void _logError(String msg) {
    _log(msg, red);
    if (mounted) setState(() => _error = msg);
  }

  void _openSettings() => Navigator.push(
    context,
    MaterialPageRoute(
      builder: (_) => ListenableBuilder(
        listenable: _changes,
        builder: (context, _) => _settingsPage(context),
      ),
    ),
  );

  // ---------- Home ----------

  @override
  Widget build(BuildContext context) {
    final busy = _ct != null;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 72,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Aether', style: TextStyle(fontWeight: FontWeight.w700)),
            Text(
              'Private Network Client',
              style: TextStyle(fontSize: 12, color: Palette.secondaryText),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: _openSettings,
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const SizedBox(height: 16),
                  _powerButton(busy),
                  const SizedBox(height: 24),
                  _routeLine(busy),
                  const SizedBox(height: 32),
                  if (_error != null) ...[
                    _errorCard(_error!, busy),
                    const SizedBox(height: 16),
                  ],
                  if (_steps.isNotEmpty) ...[
                    _stepsCard(busy),
                    const SizedBox(height: 16),
                  ],
                  if (!_vpn) ...[_proxyCard(), const SizedBox(height: 16)],
                  _quickSettings(),
                  const SizedBox(height: 16),
                  _statusBanner(busy),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // On/off switch: red when off, amber with a spinner while connecting, green when on.
  // Color is never the only signal: each state also has its own icon and text.
  Widget _powerButton(bool busy) {
    final connected = _statusColor == seaGreen;
    final connecting = busy && !connected;
    final color = _statusColor;
    final (icon, label, detail) = connected
        ? (Icons.shield_rounded, 'Connected', _delay)
        : connecting
        ? (Icons.sync_rounded, 'Connecting...', 'Tap to cancel')
        : (Icons.power_settings_new_rounded, 'Tap to Connect', '');
    return Card(
      child: SwitchListTile(
        value: busy,
        onChanged: (_) => _connect(),
        activeThumbColor: color,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        secondary: connecting
            ? SizedBox.square(
                dimension: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: color,
                  value: MediaQuery.disableAnimationsOf(context) ? 1 : null,
                ),
              )
            : Icon(icon, size: 28, color: color),
        title: Text(
          label,
          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        subtitle: detail.isEmpty ? null : Text(detail),
      ),
    );
  }

  // Which route is used: the one running now, else the saved choice. Change opens Settings.
  Widget _routeLine(bool busy) {
    final route =
        _route ??
        (_preset < 0 ? 'Auto - fastest route' : Aether.presets[_preset].name);
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const Icon(Icons.bolt_rounded, size: 20, color: Palette.accent),
        const SizedBox(width: 8),
        Flexible(child: Text(route, overflow: TextOverflow.ellipsis)),
        TextButton(
          onPressed: busy ? null : _openSettings,
          child: const Text('Change'),
        ),
      ],
    );
  }

  // Proxy mode: nothing is routed for the user, so show where to point apps, ready to copy.
  Widget _proxyCard() {
    Widget row(String name, int port, String hint) => ListTile(
      leading: const Icon(Icons.lan_outlined),
      title: Text('$name  127.0.0.1:$port'),
      subtitle: Text(hint),
      trailing: IconButton(
        tooltip: 'Copy $name address',
        icon: const Icon(Icons.copy_rounded, size: 20),
        onPressed: () {
          Clipboard.setData(ClipboardData(text: '127.0.0.1:$port'));
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Copied 127.0.0.1:$port')));
        },
      ),
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Proxy address',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Only apps set to this proxy use Aether. Wi-Fi: long-press your network > '
              'Modify > Proxy: Manual > host 127.0.0.1, port ${Aether.httpPort}.',
              style: const TextStyle(
                color: Palette.secondaryText,
                fontSize: 13,
              ),
            ),
            row('HTTP', Aether.httpPort, 'Wi-Fi proxy, browsers'),
            row('SOCKS5', Aether.socksPort, 'Telegram and apps with SOCKS'),
          ],
        ),
      ),
    );
  }

  Widget _quickSettings() => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Quick Settings',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            secondary: const Icon(Icons.bolt_outlined),
            title: const Text('Auto-Connect on Startup'),
            value: _autoConnect,
            onChanged: (v) {
              setState(() => _autoConnect = v);
              _saveSettings();
            },
          ),
          // Android, not the app, can block traffic while the VPN is down, so this opens its setting.
          const ListTile(
            leading: Icon(Icons.block_rounded),
            title: Text('Kill Switch'),
            subtitle: Text(
              'Turn on "Always-on VPN" and "Block connections without VPN"',
            ),
            trailing: Icon(Icons.open_in_new_rounded, size: 20),
            onTap: Aether.vpnSettings,
          ),
        ],
      ),
    ),
  );

  // What the current connect is doing, step by step, so a slow route does not look stuck.
  Widget _stepsCard(bool busy) => Card(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Connection steps',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Clear steps',
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: busy ? null : () => setState(_steps.clear),
              ),
            ],
          ),
          for (final (i, (text, color)) in _steps.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 8, right: 12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox.square(
                    dimension: 20,
                    child: _stepIcon(color, busy && i == _steps.length - 1),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(text)),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  // Color is never the only signal: running, done and failed each have their own icon.
  Widget _stepIcon(Color? color, bool current) {
    if (color == null) {
      return current
          ? CircularProgressIndicator(
              strokeWidth: 2,
              color: orange,
              value: MediaQuery.disableAnimationsOf(context) ? 1 : null,
            )
          : const Icon(Icons.check_rounded, size: 20, color: seaGreen);
    }
    return color == red
        ? const Icon(Icons.close_rounded, size: 20, color: red)
        : color == orange
        ? const Icon(Icons.stop_rounded, size: 20, color: orange)
        : const Icon(Icons.check_rounded, size: 20, color: seaGreen);
  }

  // The latest failure, in the core's own words: selectable and copyable for reporting.
  // A port conflict also offers the fix: a free port, or one typed by hand.
  Widget _errorCard(String error, bool busy) => Semantics(
    liveRegion: true,
    child: Container(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 8),
      decoration: BoxDecoration(
        color: red.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: red.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(Icons.error_outline_rounded, color: red),
              const SizedBox(width: 12),
              Expanded(child: SelectableText(error)),
              IconButton(
                tooltip: 'Copy error',
                icon: const Icon(Icons.copy_rounded, size: 20),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: error));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Error copied')),
                  );
                },
              ),
              IconButton(
                tooltip: 'Dismiss error',
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () => setState(_clearError),
              ),
            ],
          ),
          if (_busyPort != null && !busy)
            Padding(
              padding: const EdgeInsets.fromLTRB(0, 4, 12, 8),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.end,
                children: [
                  OutlinedButton(
                    onPressed: () => _enterPort(_busyPort!),
                    child: const Text('Enter port'),
                  ),
                  if (_freePort != null)
                    FilledButton(
                      onPressed: () => _usePort(_busyPort!, _freePort!),
                      child: Text('Use port $_freePort'),
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  Widget _statusBanner(bool busy) {
    final connected = _statusColor == seaGreen;
    final (icon, text, color) = connected
        ? (Icons.check_circle_rounded, 'Your connection is secure', seaGreen)
        : busy
        ? (Icons.sync_rounded, 'Connecting...', orange)
        : (Icons.error_outline_rounded, 'You are not protected', red);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }

  // ---------- Settings: everything technical lives here ----------

  // Saved only while valid; an invalid entry shows why and keeps the last good port.
  Widget _portField(
    String label,
    TextEditingController text,
    int Function() other,
    void Function(int) set,
    bool busy,
  ) => TextField(
    controller: text,
    enabled: !busy,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(
      labelText: label,
      errorText: Aether.portError(text.text, other()),
    ),
    onChanged: (v) {
      if (Aether.portError(v, other()) == null) {
        set(int.parse(v));
        _saveSettings();
      }
      setState(() {});
    },
  );

  Widget _settingsPage(BuildContext context) {
    final busy = _ct != null;
    // A white line above each section title separates the sections.
    Widget section(String title) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(color: Colors.white, height: 1),
          const SizedBox(height: 16),
          Text(
            title,
            style: const TextStyle(
              color: Palette.accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        children: [
          section('Connection'),
          DropdownMenu<int>(
            label: const Text('Protocol'),
            leadingIcon: const Icon(Icons.vpn_lock_outlined),
            expandedInsets: EdgeInsets.zero,
            enabled: !busy, // pick before connecting; Disconnect to change
            initialSelection: _preset,
            dropdownMenuEntries: [
              const DropdownMenuEntry(
                value: -1,
                label: 'Auto (order below)',
              ),
              // Keep persisted values stable while displaying fast presets first.
              for (final manualOnly in [false, true])
                for (final (i, p) in Aether.presets.indexed)
                  if (p.manualOnly == manualOnly)
                    DropdownMenuEntry(
                      value: i,
                      label: p.label,
                      leadingIcon: p.name.contains('Psiphon')
                          ? Image.asset('assets/psiphon.png', width: 20)
                          : const SizedBox(width: 20), // keeps names lined up
                    ),
            ],
            onSelected: (v) {
              setState(() => _preset = v ?? -1);
              _saveSettings();
            },
          ),
          ListTile(
            leading: const Icon(Icons.low_priority_rounded),
            title: const Text('Auto order'),
            subtitle: Text(
              Aether.autoOrder(_connectMs, _order)
                  .take(3)
                  .map((p) => p.name)
                  .join(' > '),
              overflow: TextOverflow.ellipsis,
            ),
            enabled: !busy,
            onTap: _showAutoOrder,
          ),
          const SizedBox(height: 16),
          const Text('Server search'),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                value: 'turbo',
                label: Text('Fast'),
                tooltip: 'First server that answers',
              ),
              ButtonSegment(
                value: 'balanced',
                label: Text('Balanced'),
                tooltip: 'Tries a few servers, keeps the fastest',
              ),
            ],
            selected: {_scan},
            onSelectionChanged: busy
                ? null
                : (v) {
                    setState(() => _scan = v.first);
                    _saveSettings();
                  },
          ),
          const SizedBox(height: 16),
          const Text('Mode'),
          const SizedBox(height: 8),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: true,
                label: Text('VPN (all apps)'),
                tooltip: 'Full-device tunnel: every app goes through aether',
              ),
              ButtonSegment(
                value: false,
                label: Text('Proxy only'),
                tooltip: 'No VPN: only apps set to the local proxy use aether',
              ),
            ],
            selected: {_vpn},
            onSelectionChanged: busy
                ? null
                : (v) {
                    setState(() => _vpn = v.first);
                    _saveSettings();
                  },
          ),
          if (!_vpn) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _portField(
                    'HTTP port',
                    _httpPortText,
                    () => Aether.socksPort,
                    (p) => Aether.httpPort = p,
                    busy,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: _portField(
                    'SOCKS5 port',
                    _socksPortText,
                    () => Aether.httpPort,
                    (p) => Aether.socksPort = p,
                    busy,
                  ),
                ),
              ],
            ),
          ],
          section('Advanced'),
          ListTile(
            leading: const Icon(Icons.tune_rounded),
            title: const Text('Core settings'),
            enabled: !busy,
            onTap: _showCoreSettings,
          ),
          ListTile(
            leading: const Icon(Icons.keyboard_outlined),
            title: const Text('Core input'),
            subtitle: const Text('Send a sign-in code the core asks for'),
            enabled: busy,
            onTap: _sendCoreInput,
          ),
          ListTile(
            leading: const Icon(Icons.info_outline_rounded),
            title: const Text('Proxy info'),
            onTap: _showProxyInfo,
          ),
          ListTile(
            leading: const Icon(Icons.system_update_outlined),
            title: const Text('Check for updates'),
            onTap: () => _checkUpdates(interactive: true),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            secondary: const Icon(Icons.receipt_long_outlined),
            title: const Text('Show activity log'),
            value: _showActivity,
            onChanged: (value) {
              setState(() => _showActivity = value);
              _saveSettings();
            },
          ),
          if (_showActivity) ...[
            section('Activity'),
            Card(
              clipBehavior: Clip.antiAlias,
              child: SizedBox(
                height: 320,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: IconButton(
                        tooltip: 'Clear activity',
                        onPressed: _lines.isEmpty
                            ? null
                            : () => setState(_lines.clear),
                        icon: const Icon(Icons.delete_outline_rounded),
                      ),
                    ),
                    Expanded(
                      child: SelectionArea(
                        child: ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          itemCount: _lines.isEmpty ? 1 : _lines.length,
                          itemBuilder: (_, i) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text(
                              _lines.isEmpty
                                  ? 'Waiting for logs...'
                                  : _lines[i].$1,
                              style: TextStyle(
                                color: _lines.isEmpty
                                    ? Palette.secondaryText
                                    : _lines[i].$2 ?? Palette.secondaryText,
                                fontFamily: 'monospace',
                                fontSize: 12,
                                height: 1.45,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
