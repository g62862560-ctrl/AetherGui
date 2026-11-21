import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'aether.dart';
import 'battery_guide.dart';
import 'auto_order_page.dart';
import 'protocol_order_sheet.dart';
import 'connection.dart';
import 'core_options.dart';
import 'core_settings_page.dart';
import 'diagnostics.dart';
import 'exit_info.dart';
import 'psiphon_countries.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Aether.init();
  runApp(
    MaterialApp(
      title: 'Aether VPN',
      debugShowCheckedModeBanner: false,
      theme: Palette.theme,
      // Keeps layouts intact when the system font size is very large.
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: MediaQuery.textScalerOf(
            context,
          ).clamp(maxScaleFactor: 1.3),
        ),
        child: child!,
      ),
      home: const HomePage(),
    ),
  );
}

// One place for every color, and the dark theme built from them.
abstract final class Palette {
  // Neutrals lean toward the accent's violet so gray surfaces feel part of the brand.
  static const background = Color(0xFF131119);
  static const surface = Color(0xFF1D1A26);
  static const accent = Color(0xFFB585FF); // neon purple
  static const secondaryText = Color(
    0xFFC3BED0,
  ); // ~9:1 on surface, readable in sunlight
  // Role colors for the secondary actions: Reset = accent (brand action), Next = sky (move on).
  static const resetBg = Color(0xFF3B2A63);
  static const nextBg = Color(0xFF1E3A4C);
  static const next = Color(0xFF7DD3FC);
  static const connected = Color(0xFF4ADE80); // neon green
  static const connecting = Color(0xFFFBBF24);
  static const disconnected = Color(0xFFF87171); // muted coral

  static final theme = ThemeData(
    brightness: Brightness.dark,
    visualDensity: VisualDensity.compact,
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
  static const maxSteps = 4; // lines kept in the connection report on Home
  static const startupDelayMs =
      1000; // pause before the automatic connect on startup
  static const red = Palette.disconnected,
      orange = Palette.connecting,
      seaGreen = Palette.connected;

  AetherProcess? _process;
  Cancel? _ct, _attempt;
  bool _nextRequested = false;
  bool _vpnStartedBySession = false;
  bool _autoConnect = false;
  CoreOptions _coreOptions = const CoreOptions();
  int _preset = -1; // index into Aether.presets, -1 = Auto (rotate through all)
  int _trySeconds = Aether.fastSecs;
  String _scan = 'turbo'; // AETHER_SCAN: turbo or balanced
  bool _vpn = true; // full-device VPN (tun); false = only serve the local proxy
  bool _showActivity = true;
  bool _realDelayTest = true;
  String _status = 'Disconnected';
  Color _statusColor = red;
  String _delay = ''; // e.g. '24 ms', shown beside the route while connected
  String? _appVersion;
  String? _route; // preset being tried or used right now
  ExitInfo? _exitInfo; // latest tunnel exit hop, shown while connected
  String? _error; // latest failure, shown on Home until connected or dismissed
  int? _busyPort,
      _freePort; // occupied port behind _error, and a free one to offer
  final _changes = ValueNotifier(0); // tells an open Settings page to rebuild
  final _connection = ConnectionController();
  final _diagnosticLog = DiagnosticLog();
  final _lines = <(String, Color?)>[];
  final _steps =
      <
        (String, Color?)
      >[]; // this connect's report on Home; no color = in progress
  final _scroll = ScrollController();
  final _httpPortText = TextEditingController(),
      _socksPortText = TextEditingController(),
      _testUrlText = TextEditingController(),
      _trySecondsText = TextEditingController();
  // preset index -> ms its last connect took, -1 = failed; orders Auto
  var _connectMs = <int, int>{};
  // Auto's order as preset indexes, kept current after each connect and editable; empty = speed ranking
  var _order = <int>[];
  // Display order of every protocol in the main list, editable by dragging.
  var _menuOrder = <int>[];
  // Per-protocol history (successful connects, failures, speed), shown in the Auto order list.
  var _stats = <int, ProtocolStat>{};
  ProtocolStat? get _connectedStat => _statusColor == seaGreen
      ? _stats[Aether.presets.indexWhere((p) => p.name == _route)]
      : null;

  File get _settings => File('${Aether.dir}/settings.txt');

  @override
  void initState() {
    super.initState();
    Aether.setVpnHandlers(onRevoked: _vpnRevoked, onState: _vpnStateChanged);
    try {
      final s = _settings.readAsStringSync();
      _autoConnect = s.contains('AutoConnect=1');
      final i =
          int.tryParse(
            RegExp(r'Preset=(-?\d+)').firstMatch(s)?.group(1) ?? '',
          ) ??
          -1;
      _preset = i >= -1 && i < Aether.presets.length ? i : -1;
      final seconds = int.tryParse(
        RegExp(r'TrySeconds=(\d+)').firstMatch(s)?.group(1) ?? '',
      );
      if (seconds != null && seconds >= 5 && seconds <= 3600)
        _trySeconds = seconds;
      if (s.contains('Scan=balanced')) _scan = 'balanced';
      _vpn = !s.contains('Mode=proxy');
      _showActivity = !s.contains('ShowActivity=0');
      _realDelayTest = !s.contains('RealDelayTest=0');
      final http = RegExp(r'HttpPort=(\d+)').firstMatch(s)?.group(1) ?? '';
      final socks = RegExp(r'SocksPort=(\d+)').firstMatch(s)?.group(1) ?? '';
      if (Aether.portError(http, int.tryParse(socks) ?? 0) == null &&
          Aether.portError(socks, int.parse(http)) == null) {
        Aether.httpPort = int.parse(http);
        Aether.socksPort = int.parse(socks);
      }
      final url = RegExp(r'TestUrl=(.*)').firstMatch(s)?.group(1)?.trim();
      if (url != null && Aether.testUrlError(url) == null) Aether.testUrl = url;
      _connectMs = Aether.parseConnectMs(
        RegExp(r'ConnectMs=(.*)').firstMatch(s)?.group(1),
      );
      _stats = Aether.parseStats(RegExp(r'Stats=(.*)').firstMatch(s)?.group(1));
      _order = s.contains('OrderVersion=3')
          ? Aether.parseOrder(RegExp(r'AutoOrder=(.*)').firstMatch(s)?.group(1))
          : [];
      _menuOrder = s.contains('OrderVersion=3')
          ? Aether.parseOrder(RegExp(r'MenuOrder=(.*)').firstMatch(s)?.group(1))
          : [];
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
    if (_menuOrder.length != Aether.presets.length ||
        _menuOrder.toSet().length != Aether.presets.length) {
      _menuOrder = [
        ..._order,
        ...Aether.menuPresetIndexes.where((i) => !_order.contains(i)),
      ];
    }
    _order = Aether.sortByStats(_order, _stats);
    _menuOrder = Aether.sortByStats(_menuOrder, _stats);
    _httpPortText.text = '${Aether.httpPort}';
    _socksPortText.text = '${Aether.socksPort}';
    _testUrlText.text = Aether.testUrl;
    _trySecondsText.text = '$_trySeconds';
    // A stale core implies its VPN may still own native state. The next serialized
    // connection performs acknowledged teardown before starting a replacement.
    Aether.killStale();
    _saveSettings(); // persist the one-time Auto-order migration and defaults
    _checkUpdates(interactive: false);
    _loadVersion();
    if (_autoConnect) {
      _log('Auto-connecting in ${startupDelayMs ~/ 1000}s...');
      Future.delayed(const Duration(milliseconds: startupDelayMs), () {
        if (mounted && _autoConnect && _ct == null) _connect();
      });
    }
  }

  @override
  void dispose() {
    Aether.setVpnHandlers();
    _ct?.cancel();
    _killProcess();
    _scroll.dispose();
    _httpPortText.dispose();
    _socksPortText.dispose();
    _testUrlText.dispose();
    _trySecondsText.dispose();
    _changes.dispose();
    _connection.dispose();
    super.dispose();
  }

  Future<void> _vpnRevoked() async {
    if (!mounted) return;
    _connection.transition(
      ConnectionPhase.recovering,
      message: 'VPN permission or ownership was revoked.',
      reconnectAvailable: true,
    );
    _logError(
      'Another VPN took over. Aether stopped, or VPN permission was revoked. '
      'Disable the other VPN, then reconnect.',
    );
    _addStep('VPN access was revoked; Aether stopped.', red);
    _ct?.cancel();
    // onRevoke already stopped native tun2socks and closed the TUN.
    _vpnStartedBySession = false;
    await _killProcessAndWait();
    if (!mounted) return;
    setState(() {
      _status = 'VPN access lost';
      _statusColor = red;
      _delay = '';
      _route = null;
      _exitInfo = null;
    });
  }

  Future<void> _vpnStateChanged(NativeVpnState state) async {
    if (!mounted) return;
    switch (state.state) {
      case 'starting':
        _connection.transition(ConnectionPhase.startingVpn, clearMessage: true);
      case 'connected':
        _connection.transition(
          ConnectionPhase.connected,
          clearMessage: true,
          reconnectAvailable: false,
        );
      case 'stopping':
        _connection.transition(ConnectionPhase.stopping);
      case 'disconnected':
        if (state.reason == 'revoked' && _vpn) {
          await _vpnRevoked();
        } else {
          _connection.transition(
            ConnectionPhase.disconnected,
            clearMessage: state.reason == 'requested',
            reconnectAvailable: false,
          );
        }
      case 'error':
        final message = state.error ?? 'The Android VPN could not start.';
        _connection.transition(
          ConnectionPhase.error,
          message: message,
          reconnectAvailable: true,
        );
        _logError(message);
        _ct?.cancel();
      default:
        _log('Ignored unknown VPN state: ${state.state}.');
    }
  }

  Future<void> _connect() async {
    if (_ct != null) {
      _connection.transition(ConnectionPhase.stopping);
      _ct!.cancel();
      return;
    }
    return _connection.serialize(() async {
      if (_ct != null) return;
      final ct = _ct = Cancel();
      _connection.transition(
        ConnectionPhase.preparing,
        clearMessage: true,
        reconnectAvailable: false,
      );
      setState(() {
        _clearError();
        _steps.clear();
        _exitInfo = null;
      });
      try {
        await _run(ct);
      } finally {
        _ct = null;
      }
      _connection.transition(ConnectionPhase.disconnected);
      if (mounted) setState(() {});
    });
  }

  void _saveSettings() => _settings.writeAsStringSync(
    'AutoConnect=${_autoConnect ? 1 : 0}\nPreset=$_preset\nScan=$_scan\n'
    'Mode=${_vpn ? 'vpn' : 'proxy'}\n'
    'ShowActivity=${_showActivity ? 1 : 0}\n'
    'HttpPort=${Aether.httpPort}\nSocksPort=${Aether.socksPort}\n'
    'TestUrl=${Aether.testUrl}\n'
    'RealDelayTest=${_realDelayTest ? 1 : 0}\n'
    'ConnectMs=${Aether.formatConnectMs(_connectMs)}\n'
    'AutoOrder=${_order.join(',')}\n'
    'MenuOrder=${_menuOrder.join(',')}\n'
    'Stats=${Aether.formatStats(_stats)}\n'
    'OrderVersion=3\n'
    'TrySeconds=$_trySeconds\n',
  );

  List<int> _autoIndexes([List<int>? saved]) => [
    for (final p in Aether.autoOrder(_connectMs, saved))
      Aether.presets.indexOf(p),
  ];

  void _nextProtocol() {
    if (_ct == null) return;
    _nextRequested = true;
    _attempt?.cancel();
  }

  // Auto: try the default presets, fastest past connect first; one that times out or drops is not retried until all others were tried.
  // A chosen preset is retried unless Next protocol is pressed.
  Future<bool> _stopAttempt({Cancel? ct}) async {
    _connection.transition(ConnectionPhase.stopping);
    _log(
      'Lifecycle: stopping attempt; core=${_process?.p.pid}, vpnOwned=$_vpnStartedBySession.',
    );
    if (_vpn &&
        (_vpnStartedBySession ||
            _process != null ||
            await Aether.vpnActive())) {
      final stopped = await Aether.vpnStop();
      final active = await Aether.vpnActive();
      if (!stopped || active) {
        _logError(
          'VPN teardown did not complete; retry blocked to avoid reusing stale native state.',
        );
        // Do not leave the core and its protocol helpers alive after a failed
        // native stop. The next explicit connect will reconcile native state.
        await _killProcessAndWait();
        return false;
      }
      _vpnStartedBySession = false;
    }
    await _killProcessAndWait();
    ct?.check();
    return true;
  }

  Future<void> _run(Cancel ct) async {
    final untried = <Preset>[];
    var chosen = _preset;
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
            chosen < 0
                ? Aether.autoOrder(_connectMs, _order)
                : [Aether.presets[chosen]],
          );
        }
        final p = untried.removeAt(0);
        if (!await _stopAttempt(ct: ct)) {
          _connection.transition(
            ConnectionPhase.error,
            message: 'The previous VPN session could not be released.',
            reconnectAvailable: true,
          );
          return;
        }
        final attempt = _attempt = Cancel(ct);
        try {
          if (_nextRequested) attempt.cancel();
          await _connectAndMonitor(
            p,
            _trySeconds, // the user's limit, for a picked protocol too
            attempt,
          );
          await attempt.delay(1000);
        } on Cancelled {
          if (ct.isCancelled) rethrow;
          if (!await _stopAttempt(ct: ct)) return;
          if (chosen >= 0)
            chosen = Aether.nextPresetIndex(Aether.presets.indexOf(p));
          _step(
            'Next protocol: ${chosen < 0 ? 'Auto order' : Aether.presets[chosen].name}.',
            orange,
          );
        } finally {
          _attempt = null;
          _nextRequested = false;
        }
      }
    } on Cancelled {
      // user pressed Disconnect, or a port conflict stopped the rotation
      if (_busyPort == null) _addStep('Stopped.', orange);
    } catch (e) {
      _logError('Connection failed: $e');
      _addStep('Connection failed.', red);
    } finally {
      _attempt = null;
      _nextRequested = false;
      await _stopAttempt();
      _setStatus('Disconnected', red);
      _setDelay('');
      _route = null;
      _exitInfo = null;
    }
  }

  // Returns when the preset fails to connect within the timeout, or after a connected session drops.
  Future<void> _connectAndMonitor(
    Preset p,
    int startupSeconds,
    Cancel ct,
  ) async {
    ct.check();
    _exitInfo = null;
    _step('Trying ${p.name}...');
    _route = p.name;
    _setStatus('Connecting: ${p.name}', orange);
    var coreFailed = false, portConflict = false;
    void coreLog(String line) {
      final progress = Aether.torBootstrapProgress(line);
      if (!ct.isCancelled &&
          mounted &&
          _statusColor == orange &&
          progress != null &&
          progress != _torProgress) {
        setState(() => _torProgress = progress);
        _step('Tor bootstrap: $progress%');
      }
      final error = Aether.coreError(line);
      _log(line, error == null ? null : red);
      // A working session can log passing errors; those stay in the activity log.
      if (error == null || _statusColor == seaGreen) return;
      coreFailed = true;
      final port = Aether.busyPort(error);
      if (port != null &&
          (port == Aether.socksPort || port == Aether.httpPort)) {
        portConflict = true;
        _portInUse(port, _ct!);
      } else if (mounted) {
        setState(() => _error = '${p.name}: $error');
        _addStep('${p.name}: core reported an error.', red);
      }
    }

    _connection.transition(ConnectionPhase.preparing);
    // Let an old aether process release its ports before starting a new one.
    Aether.killStale();
    var portsFree = false;
    for (var i = 0; i < 25; i++) {
      ct.check();
      portsFree =
          await Aether.portFree(Aether.socksPort) &&
          await Aether.portFree(Aether.httpPort);
      if (portsFree) break;
      await ct.delay(200);
    }
    if (!portsFree) {
      _logError('Previous core still owns a proxy port; retry blocked.');
      _addStep('Previous core did not release its proxy ports.', red);
      return;
    }

    ct.check();
    _connection.transition(ConnectionPhase.startingCore);
    final proc = _process = await Aether.start(
      p,
      coreLog,
      _coreOptions,
      _scan,
      _onExit,
    );
    ct.check();
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
    _connection.transition(ConnectionPhase.waitingForProxy);

    // Never establish the VPN before the owned local proxy is accepting.
    var proxyReady = false;
    var vpnStarted = false;
    for (var i = 0; i < 25; i++) {
      ct.check();
      if (await Aether.portOpen()) {
        proxyReady = true;
        break;
      }
      await ct.delay(200);
    }
    ct.check();
    if (_vpn && proxyReady) {
      _connection.transition(ConnectionPhase.startingVpn);
      if (await Aether.vpnActive()) {
        vpnStarted = true;
        _vpnStartedBySession = true;
      } else {
        vpnStarted = await Aether.vpnStart();
        if (vpnStarted) _vpnStartedBySession = true;
      }
    }

    final took = Stopwatch()..start();
    final realDelayTest = _realDelayTest;
    _connection.transition(
      proxyReady
          ? ConnectionPhase.testingConnectivity
          : ConnectionPhase.waitingForProxy,
    );
    var (connected, ms) = await Aether.waitConnected(
      proc,
      _coreOptions.isConfigured ? _coreOptions.startupSeconds : startupSeconds,
      ct,
      _step,
      realDelayTest,
    );
    if (portConflict) {
      await _stopAttempt(ct: ct); // says nothing about this preset
      return;
    }
    _connectMs[Aether.presets.indexOf(p)] = connected
        ? took.elapsedMilliseconds
        : -1;
    final stat = _stats.putIfAbsent(
      Aether.presets.indexOf(p),
      () => ProtocolStat(),
    );
    if (connected) {
      stat.ok++;
      stat.totalMs += took.elapsedMilliseconds;
      stat.lastOk = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      stat.consecutiveFailures = 0;
      stat.lastFailure = 0;
    } else {
      stat.fail++;
      stat.consecutiveFailures++;
      stat.lastFailure = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    }
    _order = Aether.rerank(
      _autoIndexes(_order),
      _connectMs,
      Aether.presets.indexOf(p),
    );
    // Both lists follow the history: what worked on top, what only failed at the bottom.
    _order = Aether.sortByStats(_order, _stats);
    _menuOrder = Aether.sortByStats(_menuOrder, _stats);
    _saveSettings();
    if (!connected) {
      final failure = proc.exited
          ? '${p.name}: process exited.'
          : '${p.name}: no internet, switching.';
      // Keep the core's own message: it says why, this line only says what happened.
      coreFailed ? _log(failure) : _logError(failure);
      _addStep(failure, red);
      await _stopAttempt(ct: ct);
      return;
    }

    _connection.transition(ConnectionPhase.connected);
    _setStatus('Connected: ${p.name}', seaGreen);
    if (mounted) setState(() => _error = null);
    _step(
      realDelayTest
          ? 'Connected via ${p.name} in ${(took.elapsedMilliseconds / 1000).toStringAsFixed(1)}s, delay $ms ms.'
          : 'Connected via ${p.name} in ${(took.elapsedMilliseconds / 1000).toStringAsFixed(1)}s; local proxy ready, internet not tested.',
      seaGreen,
    );
    _step(
      '${p.name} on this device: ${stat.ok} ok, ${stat.fail} failed, '
      '${stat.ok * 100 ~/ stat.tries}% success, avg ${(stat.avgMs / 1000).toStringAsFixed(1)}s.',
      seaGreen,
    );
    if (!_vpn) {
      _step(
        'Proxy only: HTTP 127.0.0.1:${Aether.httpPort}, SOCKS5 127.0.0.1:${Aether.socksPort}.',
        seaGreen,
      );
    } else if (vpnStarted && await Aether.vpnActive()) {
      _step('VPN on: all apps go through aether.', seaGreen);
    } else {
      _logError(
        'VPN did not establish; stopping to avoid an unprotected session.',
      );
      _addStep('VPN did not establish; connection stopped.', red);
      _connection.transition(
        ConnectionPhase.error,
        message: 'Android did not confirm ownership of the VPN tunnel.',
        reconnectAvailable: true,
      );
      await _stopAttempt(ct: ct);
      return;
    }
    if (!realDelayTest) {
      _setDelay('not tested');
      while (!proc.exited) await ct.delay(1000);
    } else {
      for (var fails = 0; fails < 2;) {
        _setDelay(ms == null ? 'timeout' : '$ms ms');
        await ct.delay(5000);
        if (proc.exited) break;
        ms = await Aether.ping(ct);
        fails = ms == null ? fails + 1 : 0;
      }
    }
    _logError('${p.name}: connection lost, resetting VPN before switching.');
    _exitInfo = null;
    _addStep('${p.name}: connection lost; resetting VPN.', red);
    await _stopAttempt(ct: ct);
  }

  // Every preset needs this port, so rotating on cannot help: stop and let the user choose.
  Future<void> _portInUse(int port, Cancel ct) async {
    final other = port == Aether.socksPort ? Aether.httpPort : Aether.socksPort;
    _logError(
      'Port $port is in use by another app. Close it or pick a new port.',
    );
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
    final other = busy == Aether.socksPort ? Aether.httpPort : Aether.socksPort;
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
              final taken = problem == null && !await Aether.portFree(port!);
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
    final proc = _process;
    _process = null;
    proc?.p.kill(ProcessSignal.sigterm);
  }

  Future<void> _killProcessAndWait() async {
    final proc = _process;
    if (proc == null) return;
    _log('Lifecycle: stopping core pid=${proc.p.pid}.');
    await proc.stop();
    if (identical(_process, proc)) _process = null;
    _log('Lifecycle: core pid=${proc.p.pid} exited; resources released.');
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
    final result = await Navigator.push<AutoOrderResult>(
      context,
      MaterialPageRoute(
        builder: (_) => AutoOrderPage(
          order: _menuOrder,
          checked: _order,
          ranking: _autoIndexes(),
          stats: _stats,
          onChanged: _applyAutoOrder,
        ),
      ),
    );
    if (!mounted || result == null) return;
    _applyAutoOrder(result);
  }

  void _applyAutoOrder(AutoOrderResult r) {
    setState(() {
      _menuOrder = [...r.order];
      _order = [...r.checked];
    });
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(msg)));
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
      '3. Auto rotates the default protocols ($_trySeconds s each), or your own order from Settings > Auto order. Psiphon may need a longer try time.',
      tip,
    );
  }

  Future<void> _loadVersion() async {
    final version = await Aether.appVersion();
    if (mounted) setState(() => _appVersion = version);
  }

  int? _torProgress;

  void _setStatus(String text, Color color) {
    if (mounted)
      setState(() {
        _torProgress = null;
        _status = text;
        _statusColor = color;
      });
  }

  // Green when fast, amber when slow, red when very slow or timed out.
  static Color _pingColor(String delay) {
    final ms = int.tryParse(delay.split(' ').first);
    return ms == null || ms >= Aether.slowPingMs
        ? Palette.disconnected
        : ms < Aether.goodPingMs
        ? Palette.connected
        : Palette.connecting;
  }

  void _setDelay(String text) {
    if (mounted) setState(() => _delay = text);
  }

  void _onExit(ExitInfo exit) {
    if (mounted) setState(() => _exitInfo = exit);
  }

  @override
  void setState(VoidCallback fn) {
    super.setState(fn);
    _changes.value++;
  }

  void _log(String msg, [Color? color]) {
    if (!mounted) return;
    final t = DateTime.now().toIso8601String().substring(11, 19);
    final safe = _diagnosticLog.add('[$t] $msg');
    setState(() {
      _lines.add((safe, color));
      if (_lines.length > _diagnosticLog.maxLines) {
        _lines.removeRange(0, _lines.length - _diagnosticLog.maxLines);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  String _diagnosticReport() => buildDiagnosticReport(
    connectionState: _connection.value.phase.name,
    mode: _vpn ? 'Full-device VPN' : 'Local proxy',
    lines: _diagnosticLog.lines,
    appVersion: _appVersion,
  );

  Future<void> _copyDiagnosticReport() async {
    await Clipboard.setData(ClipboardData(text: _diagnosticReport()));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Redacted diagnostic report copied')),
      );
    }
  }

  Future<void> _saveDiagnosticReport() async {
    try {
      final file = await writeDiagnosticReport(Aether.dir, _diagnosticReport());
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Saved locally: ${file.path}')));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not save diagnostic report')),
      );
    }
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
        title: const Text(
          'Aether',
          style: TextStyle(fontWeight: FontWeight.w700),
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
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // All three actions share one row: same size and shape, status color only on Connect.
                  Row(
                    children: [
                      Expanded(child: _powerButton(busy)),
                      const SizedBox(width: 12),
                      Expanded(child: _resetConnectButton(busy)),
                      const SizedBox(width: 12),
                      Expanded(child: _nextButton(busy)),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _routeLine(),
                  if (_statusColor == orange &&
                      (_route?.toLowerCase().contains('tor') ?? false)) ...[
                    const SizedBox(height: 12),
                    Text(
                      _torProgress == null
                          ? 'Tor: waiting for bootstrap progress…'
                          : 'Tor reaching the network: $_torProgress%',
                    ),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(
                      key: const Key('torBootstrapProgress'),
                      value: _torProgress == null ? null : _torProgress! / 100,
                      semanticsLabel: 'Tor bootstrap',
                      semanticsValue: _torProgress == null
                          ? 'Waiting'
                          : '$_torProgress%',
                      minHeight: 6,
                    ),
                  ],
                  // Once connected, stats sit in small cards; the exit country flag is on the route row.
                  if (_statusColor == seaGreen) ...[
                    const SizedBox(height: 12),
                    _statCards(),
                  ],
                  const SizedBox(height: 12),
                  _protocolMenu(busy),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          key: const Key('autoTrySeconds'),
                          controller: _trySecondsText,
                          enabled: !busy,
                          keyboardType: TextInputType.number,
                          decoration: InputDecoration(
                            labelText: 'Auto try (seconds)',
                            errorText:
                                (int.tryParse(_trySecondsText.text) ?? 0) >=
                                        5 &&
                                    (int.tryParse(_trySecondsText.text) ?? 0) <=
                                        3600
                                ? null
                                : '5–3600',
                          ),
                          onChanged: (value) {
                            final seconds = int.tryParse(value);
                            if (seconds != null &&
                                seconds >= 5 &&
                                seconds <= 3600) {
                              _trySeconds = seconds;
                              _saveSettings();
                            }
                            setState(() {});
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_error != null) ...[
                    _errorCard(_error!, busy),
                    const SizedBox(height: 8),
                  ],
                  if (_connection.value.reconnectAvailable && !busy) ...[
                    FilledButton.icon(
                      key: const Key('reconnectVpn'),
                      onPressed: _connect,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Reconnect Aether'),
                    ),
                    const SizedBox(height: 8),
                  ],
                  if (_steps.isNotEmpty) ...[
                    _stepsCard(busy),
                    const SizedBox(height: 8),
                  ],
                  if (!_vpn) ...[_proxyCard(), const SizedBox(height: 8)],
                  _quickSettings(),
                  if (_appVersion != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Aether $_appVersion',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Palette.secondaryText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // Large square on/off button: red when off, cycling light colors while connecting, green when on; the ping shows beside it.
  // The icon (power, cancel, shield) and the screen-reader label carry the state too, so color is never the only signal.
  static const _actionHeight = 72.0;
  static final _actionShape = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(16),
  );

  // Icon with a small label inside the button.
  Widget _buttonBody(IconData icon, String label, [Color? color]) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(icon, size: 30, color: color),
      const SizedBox(height: 4),
      ExcludeSemantics(
        child: Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(fontSize: 11, color: color),
        ),
      ),
    ],
  );

  Widget _squareButton(Color color, IconData icon, String label) =>
      FilledButton(
        onPressed: _connect,
        style: FilledButton.styleFrom(
          backgroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          shape: _actionShape,
        ),
        child: _buttonBody(icon, label, Palette.background),
      );

  // Secondary actions: same size and shape as Connect, neutral tonal color.
  Widget _tonalAction({
    Key? key,
    required String tooltip,
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required Color background,
    required Color foreground,
  }) => SizedBox(
    height: _actionHeight,
    child: Tooltip(
      message: tooltip,
      child: FilledButton(
        key: key,
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          // Disabled keeps its hue, only quieter, so the row stays colored when Next is idle.
          disabledBackgroundColor: background.withValues(alpha: 0.45),
          disabledForegroundColor: foreground.withValues(alpha: 0.5),
          padding: const EdgeInsets.symmetric(horizontal: 4),
          shape: _actionShape,
        ),
        child: _buttonBody(icon, label),
      ),
    ),
  );

  Widget _nextButton(bool busy) => _tonalAction(
    key: const Key('nextProtocol'),
    tooltip: 'Next protocol',
    icon: Icons.skip_next_rounded,
    label: 'Next',
    background: Palette.nextBg,
    foreground: Palette.next,
    onPressed: busy ? _nextProtocol : null,
  );

  // Light colors the connecting button cycles through, blended smoothly; t runs 0..1.
  static const _lightColors = [
    Color(0xFFFDE68A), // amber
    Color(0xFFFBCFE8), // pink
    Color(0xFFDDD6FE), // lilac
    Color(0xFFBAE6FD), // sky
    Color(0xFFBBF7D0), // mint
  ];
  static Color _lightColorAt(double t) {
    final x = t * _lightColors.length;
    final i = x.floor() % _lightColors.length;
    return Color.lerp(
      _lightColors[i],
      _lightColors[(i + 1) % _lightColors.length],
      x - x.floor(),
    )!;
  }

  Widget _powerButton(bool busy) {
    final connected = _statusColor == seaGreen;
    final icon = connected
        ? Icons.shield_rounded
        : Icons.power_settings_new_rounded;
    return Semantics(
      label: connected
          ? 'Connected'
          : busy
          ? 'Connecting, tap to cancel'
          : 'Connect',
      // Square toggle button filled with the status color; while connecting it drifts through light colors.
      child: SizedBox(
        height: _actionHeight,
        child: busy && !connected
            ? _Loop(
                period: const Duration(seconds: 4),
                builder: (t) => _squareButton(
                  _lightColorAt(t),
                  Icons.close_rounded,
                  'Cancel',
                ),
              )
            : _squareButton(
                _statusColor,
                icon,
                connected ? 'Connected' : 'Connect',
              ),
      ),
    );
  }

  // Which route is used: the one running now, else the saved choice.
  Widget _routeLine() {
    final route =
        _route ??
        (_preset < 0 ? 'Auto - fastest route' : Aether.presets[_preset].name);
    final flag = _statusColor == seaGreen && _exitInfo != null
        ? formatExitFlag(_exitInfo!)
        : null;
    return Row(
      children: [
        const Icon(Icons.bolt_rounded, size: 20, color: Palette.accent),
        const SizedBox(width: 8),
        Flexible(child: Text(route, overflow: TextOverflow.ellipsis)),
        if (flag != null) ...[
          const SizedBox(width: 8),
          Semantics(
            label: 'Exit country: ${exitCountryName(_exitInfo!.countryCode)}',
            child: Text(flag, style: const TextStyle(fontSize: 20)),
          ),
        ],
      ],
    );
  }

  // Round button: forget learned speeds and the saved order, go back to Auto, then connect.
  Widget _resetConnectButton(bool busy) => _tonalAction(
    key: const Key('resetOrderConnect'),
    tooltip: 'Reset order and connect',
    icon: Icons.restart_alt_rounded,
    label: 'Reset',
    background: Palette.resetBg,
    foreground: Palette.accent,
    onPressed: busy ? null : _resetOrderAndConnect,
  );

  Future<void> _resetOrderAndConnect() async {
    setState(() {
      _connectMs = {};
      _order = _autoIndexes();
      _menuOrder = [
        ..._order,
        ...Aether.menuPresetIndexes.where((i) => !_order.contains(i)),
      ];
      _preset = -1;
    });
    _saveSettings();
    await _connect();
  }

  // The main connection choice stays on Home; Auto's detailed order remains in Settings.
  Widget _protocolMenu(bool busy) {
    final label = _preset < 0
        ? 'Auto (order in Settings)'
        : Aether.presets[_preset].label;
    return ListTile(
      key: const Key('connectionProtocol'),
      enabled: !busy,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(4),
        side: BorderSide(color: Theme.of(context).dividerColor),
      ),
      leading: const Icon(Icons.vpn_lock_outlined),
      title: Text(label),
      subtitle: const Text('Tap to choose or drag to reorder'),
      trailing: const Icon(Icons.unfold_more_rounded),
      onTap: busy ? null : _editProtocolOrder,
    );
  }

  Future<void> _editProtocolOrder() async {
    final result = await showModalBottomSheet<ProtocolOrderResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ProtocolOrderSheet(
        order: _menuOrder,
        selected: _preset,
        onReorder: _applyMenuOrder,
      ),
    );
    if (!mounted || result == null) return;
    setState(() => _preset = result.selected);
    _applyMenuOrder(result.order);
  }

  // Main-list order edits: Auto's checked set keeps its members and follows the new order.
  void _applyMenuOrder(List<int> order) {
    setState(() {
      _menuOrder = [...order];
      final checked = _order.toSet();
      _order = [
        for (final i in _menuOrder)
          if (checked.contains(i)) i,
      ];
    });
    _saveSettings();
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

  // Ping, success rate, average connect time and tries for the connected protocol; each value colored by meaning.
  Widget _statCards() {
    final st = _connectedStat;
    final tested = _delay.isNotEmpty && _delay != 'not tested';
    final rate = st == null || st.tries == 0 ? null : st.ok * 100 ~/ st.tries;
    final avg = st == null || st.ok == 0 ? null : st.avgMs / 1000;
    Widget card(String label, String value, Color color) => Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          child: Column(
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  color: Palette.secondaryText,
                ),
              ),
              const SizedBox(height: 4),
              FittedBox(
                child: Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    const gap = SizedBox(width: 8);
    return Row(
      key: const Key('connectedStats'),
      children: [
        card(
          'Ping',
          tested ? _delay : 'not tested',
          tested ? _pingColor(_delay) : Palette.secondaryText,
        ),
        gap,
        card(
          'Success',
          rate == null ? '-' : '$rate%',
          rate == null
              ? Palette.secondaryText
              : rate >= 60
              ? Palette.connected
              : rate >= 30
              ? Palette.connecting
              : Palette.disconnected,
        ),
        gap,
        card(
          'Avg connect',
          avg == null ? '-' : '${avg.toStringAsFixed(1)}s',
          avg == null
              ? Palette.secondaryText
              : avg < 5
              ? Palette.connected
              : avg < 15
              ? Palette.connecting
              : Palette.disconnected,
        ),
        gap,
        card(
          'Tries',
          st == null ? '-' : '${st.ok}/${st.tries}',
          Palette.accent,
        ),
      ],
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
            secondary: const Icon(Icons.bolt_outlined, color: Palette.accent),
            title: const Text('Auto-Connect on Startup'),
            value: _autoConnect,
            onChanged: (v) {
              setState(() => _autoConnect = v);
              _saveSettings();
            },
          ),
          // Android, not the app, can block traffic while the VPN is down, so this opens its setting.
          const ListTile(
            leading: Icon(Icons.block_rounded, color: Palette.disconnected),
            title: Text('Kill Switch'),
            subtitle: Text(
              'Turn on "Always-on VPN" and "Block connections without VPN"',
            ),
            trailing: Icon(Icons.open_in_new_rounded, size: 20),
            onTap: Aether.vpnSettings,
          ),
          ListTile(
            leading: const Icon(Icons.battery_saver_rounded),
            title: const Text('Background running'),
            subtitle: const Text(
              'Step-by-step guide for your phone to keep the VPN running with the screen off',
            ),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const BatteryGuidePage()),
            ),
          ),
        ],
      ),
    ),
  );

  // What the current connect is doing, step by step, so a slow route does not look stuck.
  Widget _stepsCard(bool busy) => Card(
    clipBehavior: Clip.antiAlias,
    child: Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        key: const Key('connectionSteps'),
        initiallyExpanded: true,
        tilePadding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
        childrenPadding: const EdgeInsets.fromLTRB(20, 0, 12, 12),
        title: const Text(
          'Connection steps',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        // Collapsed, the latest step still says what is happening.
        subtitle: Text(
          _steps.last.$1,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: _steps.last.$2 ?? Palette.secondaryText),
        ),
        children: [
          for (final (i, (text, color)) in _steps.indexed)
            Padding(
              padding: const EdgeInsets.only(top: 8),
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
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: busy ? null : () => setState(_steps.clear),
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Clear'),
            ),
          ),
        ],
      ),
    ),
  );

  // 1 at the start of each cycle, fading to 0 by its middle; t may be negative.
  static double _pulse(double t) {
    final p = t - t.floorToDouble();
    return p < 0.5 ? 1 - p * 2 : 0;
  }

  // Color is never the only signal: running, done and failed each have their own icon.
  Widget _stepIcon(Color? color, bool current) {
    if (color == null) {
      // Three dots pulsing one after another for the running step.
      return current
          ? _Loop(
              period: const Duration(milliseconds: 1200),
              builder: (t) => Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (var d = 0; d < 3; d++)
                    Opacity(
                      opacity: 0.3 + 0.7 * _pulse(t - d / 3),
                      child: const SizedBox.square(
                        dimension: 5,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: orange,
                            shape: BoxShape.circle,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
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
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(const SnackBar(content: Text('Error copied')));
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
          DropdownButtonFormField<String>(
            key: ValueKey('psiphon-country-${_coreOptions.psiphonRegion}'),
            initialValue: _coreOptions.psiphonRegion,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Psiphon server country',
              border: OutlineInputBorder(),
            ),
            items: [
              for (final country in psiphonCountries)
                DropdownMenuItem(
                  value: country.code,
                  child: Text(country.label),
                ),
            ],
            onChanged: (value) {
              if (value == null) return;
              try {
                final saved = CoreOptions.savePsiphonRegion(Aether.dir, value);
                setState(() => _coreOptions = saved);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Country saved. Reconnect to apply changes.'),
                  ),
                );
              } catch (_) {
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Could not save country. Please try again.'),
                  ),
                );
              }
            },
          ),
          const SizedBox(height: 12),
          const Text(
            'Saved automatically. Reconnect to apply changes. Applies only to Psiphon protocols. '
            'Automatic lets Psiphon choose. In reverse modes (Psiphon + WARP), '
            'this selects the Psiphon carrier country, not the final WARP exit. '
            'This list is not a live server inventory; country availability is not guaranteed. '
            'Explicit --psiphon-region arguments or AETHER_PSIPHON_REGION environment settings '
            'in Core settings override this selector, including empty values.',
          ),
          if (_coreOptions.hasPsiphonRegionOverride)
            const Text('An advanced Psiphon region override is active.'),
          const SizedBox(height: 16),
          ListTile(
            leading: const Icon(Icons.low_priority_rounded),
            title: const Text('Auto order'),
            subtitle: Text(
              Aether.autoOrder(
                _connectMs,
                _order,
              ).take(3).map((p) => p.name).join(' > '),
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
          SwitchListTile(
            secondary: const Icon(Icons.network_check_rounded),
            title: const Text('Real delay test'),
            subtitle: const Text(
              'Verify internet access and measure delay. When off, only the local proxy is checked.',
            ),
            value: _realDelayTest,
            onChanged: busy
                ? null
                : (v) {
                    setState(() => _realDelayTest = v);
                    _saveSettings();
                  },
          ),
          // Typed URLs are saved once valid; the menu offers well-known ones.
          TextField(
            controller: _testUrlText,
            enabled: _realDelayTest,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(
              labelText: 'Delay test URL',
              helperText: 'Any http(s) page; the ping is how long it takes',
              errorText: _realDelayTest
                  ? Aether.testUrlError(_testUrlText.text)
                  : null,
              suffixIcon: PopupMenuButton<String>(
                tooltip: 'Suggested URLs',
                icon: const Icon(Icons.arrow_drop_down_rounded),
                itemBuilder: (_) => [
                  for (final u in Aether.testUrlSuggestions)
                    PopupMenuItem(value: u, child: Text(u)),
                ],
                onSelected: (u) {
                  _testUrlText.text = Aether.testUrl = u;
                  _saveSettings();
                  setState(() {});
                },
              ),
            ),
            onChanged: (v) {
              if (Aether.testUrlError(v) == null) {
                Aether.testUrl = v.trim();
                _saveSettings();
              }
              setState(() {});
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
          section('Diagnostics'),
          const Text(
            'Reports stay on this device unless you copy them. Credentials and common tokens are redacted, and only recent activity is retained.',
            style: TextStyle(color: Palette.secondaryText),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton.icon(
                key: const Key('copyDiagnostics'),
                onPressed: _copyDiagnosticReport,
                icon: const Icon(Icons.copy_rounded),
                label: const Text('Copy report'),
              ),
              OutlinedButton.icon(
                key: const Key('saveDiagnostics'),
                onPressed: _saveDiagnosticReport,
                icon: const Icon(Icons.save_alt_rounded),
                label: const Text('Save locally'),
              ),
            ],
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
                            : () => setState(() {
                                _lines.clear();
                                _diagnosticLog.clear();
                              }),
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

// Rebuilds with t running 0..1 again and again; holds still at 0 when the system asks for reduced motion.
class _Loop extends StatefulWidget {
  const _Loop({required this.period, required this.builder});
  final Duration period;
  final Widget Function(double t) builder;

  @override
  State<_Loop> createState() => _LoopState();
}

class _LoopState extends State<_Loop> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.period);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    MediaQuery.disableAnimationsOf(context) ? _c.stop() : _c.repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    builder: (_, _) => widget.builder(_c.value),
  );
}
