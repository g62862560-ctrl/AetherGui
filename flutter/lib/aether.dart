import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

import 'core_options.dart';

class Preset {
  final String name, args, httpFlag;
  final int startupSecs;
  final bool autoByDefault;
  const Preset(
    this.name,
    this.args, [
    this.startupSecs = Aether.fastSecs,
    this.httpFlag = '--http-proxy',
    this.autoByDefault = false,
  ]);

  bool get manualOnly => startupSecs > Aether.fastSecs && !autoByDefault;
  String get label => manualOnly ? '$name (manual)' : name;
}

typedef Log = void Function(String);

// How one protocol has done on this device: connects that worked, tries that failed, speed and recency.
class ProtocolStat {
  ProtocolStat({this.ok = 0, this.fail = 0, this.totalMs = 0, this.lastOk = 0});
  int ok, fail, totalMs, lastOk; // lastOk: epoch seconds, 0 = never

  int get tries => ok + fail;
  int get avgMs => ok == 0 ? 0 : totalMs ~/ ok;

  // 'good' works for you, 'bad' mostly fails, 'maybe' too few tries, 'new' never tried.
  String get verdict {
    if (tries == 0) return 'new';
    if (ok == 0 && fail >= 2) return 'bad';
    if (tries < 3) return 'maybe';
    return ok / tries >= 0.6 ? 'good' : 'bad';
  }
}

class Cancelled implements Exception {}

// Stand-in for CancellationToken: delays wake up early and throw once cancelled.
class Cancel {
  final _done = Completer<void>();
  Cancel([Cancel? parent]) {
    parent?._done.future.then((_) => cancel());
  }
  bool get isCancelled => _done.isCompleted;
  void cancel() => isCancelled ? null : _done.complete();
  void check() => isCancelled ? throw Cancelled() : null;
  Future<void> delay(int ms) async {
    await Future.any([
      Future.delayed(Duration(milliseconds: ms)),
      _done.future,
    ]);
    check();
  }
}

// aether, running as a child process of the app (Android kills it together with the app).
class AetherProcess {
  final Process p;
  bool exited = false;
  AetherProcess(this.p) {
    p.exitCode.then((_) => exited = true);
  }
}

// Everything about the aether binary itself: where it lives, starting it, and testing its tunnel.
class Aether {
  static const defaultTestUrl = 'http://www.gstatic.com/generate_204';
  // Offered in Settings; the user may also type any http(s) URL.
  static const testUrlSuggestions = [
    defaultTestUrl,
    'http://cp.cloudflare.com/generate_204',
    'https://www.google.com/generate_204',
    'https://www.cloudflare.com/cdn-cgi/trace',
    'http://www.msftconnecttest.com/connecttest.txt',
  ];
  static var testUrl = defaultTestUrl;

  // Why a typed delay-test URL can't be used, or null if it can.
  static String? testUrlError(String text) {
    final u = Uri.tryParse(text.trim());
    return u != null &&
            (u.scheme == 'http' || u.scheme == 'https') &&
            u.host.isNotEmpty
        ? null
        : 'Enter a full http:// or https:// URL';
  }

  // Ping color thresholds: below good is green, below slow is amber, else red.
  static const goodPingMs = 300, slowPingMs = 800;
  static const connectTimeoutMs =
      10000; // after the proxy is up, the internet test must pass within this
  static const defaultHttpPort = 1819, defaultSocksPort = 1818;
  static var httpPort =
      defaultHttpPort; // HTTP proxy: point Wi-Fi proxy / apps here
  static var socksPort =
      defaultSocksPort; // SOCKS5, free for apps that support it
  static const _internalPort =
      1822; // forward modes' WARP listener, see launchArguments

  // Why a typed port can't be used, or null if it can.
  static String? portError(String text, int other) {
    final p = int.tryParse(text);
    if (p == null || p < 1024 || p > 65535) return '1024 to 65535';
    if (p == other || p == _internalPort) return 'Port $p is already used';
    return null;
  }

  static const _warp = '--turbo -4 --quick-reconnect';
  static const fastSecs =
      30; // default Auto attempt budget; slow Psiphon routes can also be included

  // The protocol menu aether itself offers. Tor/Psiphon bootstrap slowly (tor tries 75s plainly, then bridges;
  // psiphon waits up to 180s), so they get longer startup budgets. Four Psiphon routes are in Auto by request.
  // The "alone" modes don't serve --http-proxy, so they expose their own HTTP proxy flag on the same port.
  static const presets = <Preset>[
    Preset('MASQUE', '--masque $_warp'),
    Preset('WireGuard', '--wg $_warp'),
    // v2.3 renamed the classic carrier; preserve saved protocol semantics.
    Preset('WARP-in-WARP (gool)', '--gool-classic $_warp'),
    Preset('MASQUE-in-MASQUE', '--mim $_warp'),
    Preset('Tor alone', '--tor-only', 300, '--tor-http'),
    Preset(
      'Tor + WARP',
      '--tor-reverse $_warp',
      300,
    ), // warp reached via tor, exit via warp
    Preset('Psiphon alone', '--psiphon-only', 240, '--psiphon-http'),
    Preset(
      'Psiphon + WARP',
      '--psiphon-reverse $_warp',
      240,
    ), // warp reached via psiphon, exit via warp
    // Append to preserve existing saved preset indexes.
    Preset('MASQUE HTTP/2', '--masque --h2 $_warp'),
    Preset('MASQUE HTTP/2 + fragmentation', '--masque --h2 --fragment $_warp'),
    Preset('MASQUE-in-MASQUE HTTP/2', '--mim --h2 $_warp'),
    Preset('MASQUE → Tor', '--masque --tor $_warp', 300, '--tor-http'),
    Preset(
      'MASQUE HTTP/2 → Tor',
      '--masque --h2 --tor $_warp',
      300,
      '--tor-http',
    ),
    Preset('WireGuard → Tor', '--wg --tor $_warp', 300, '--tor-http'),
    Preset(
      'WARP-in-WARP → Tor',
      '--gool-classic --tor $_warp',
      300,
      '--tor-http',
    ),
    Preset('MASQUE-in-MASQUE → Tor', '--mim --tor $_warp', 300, '--tor-http'),
    Preset(
      'MASQUE → Psiphon',
      '--masque --psiphon $_warp',
      240,
      '--psiphon-http',
    ),
    Preset(
      'MASQUE HTTP/2 → Psiphon',
      '--masque --h2 --psiphon $_warp',
      240,
      '--psiphon-http',
      true,
    ),
    Preset(
      'WireGuard → Psiphon',
      '--wg --psiphon $_warp',
      240,
      '--psiphon-http',
      true,
    ),
    Preset(
      'WARP-in-WARP → Psiphon',
      '--gool-classic --psiphon $_warp',
      240,
      '--psiphon-http',
      true,
    ),
    Preset(
      'MASQUE-in-MASQUE → Psiphon',
      '--mim --psiphon $_warp',
      240,
      '--psiphon-http',
      true,
    ),
    Preset('WireGuard-in-MASQUE (gool)', '--gool $_warp'),
    Preset('WireGuard-in-MASQUE HTTP/2', '--gool --h2 $_warp'),
  ];

  static final menuPresetIndexes = [
    ...(() {
      final auto = [
        for (final (i, p) in presets.indexed)
          if (!p.manualOnly) i,
      ];
      auto.sort(
        (a, b) => _preferredPriority(
          presets[a].name,
        ).compareTo(_preferredPriority(presets[b].name)),
      );
      final manual = [
        for (final (i, p) in presets.indexed)
          if (p.manualOnly) i,
      ];
      return [...auto, ...manual];
    })(),
  ];

  static int nextPresetIndex(int current) {
    final position = menuPresetIndexes.indexOf(current);
    return menuPresetIndexes[(position + 1) % menuPresetIndexes.length];
  }

  static late String
  exe; // libaether.so in nativeLibraryDir, packed by fetch_aether.sh
  static late String
  lyrebird; // tor bridge transport (obfs4, webtunnel), packed beside it as liblyrebird.so
  static late String
  psiphon; // psiphon-tunnel-core, packed beside it as libpsiphon.so
  static late String
  dir; // app files dir: aether's working dir, holds its identity .toml files

  static const _ch = MethodChannel('aether');

  static Future<void> init() async {
    final dirs = await _ch.invokeListMethod<String>('dirs');
    exe = '${dirs![0]}/libaether.so';
    lyrebird = '${dirs[0]}/liblyrebird.so';
    psiphon = '${dirs[0]}/libpsiphon.so';
    dir = dirs[1];
  }

  // Full-device VPN (tun2socks onto the SOCKS port); false if the user declined the VPN prompt.
  static Future<bool> vpnStart() async =>
      await _ch.invokeMethod<bool>('vpnStart', socksPort) ?? false;
  static Future<void> vpnStop() => _ch.invokeMethod('vpnStop');
  // Proxy mode: the same service without a tun, only so Android keeps the app alive in the background.
  static Future<void> keepAlive() => _ch.invokeMethod('keepAlive');

  static const guiRepo = 'g62862560-ctrl/AetherGui';
  static Future<String?> appVersion() => _ch.invokeMethod<String>('appVersion');
  static Future<void> openUrl(String url) => _ch.invokeMethod('openUrl', url);
  static Future<bool> vpnActive() async {
    try {
      return await _ch.invokeMethod<bool>('vpnActive') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> vpnSettings() => _ch.invokeMethod('vpnSettings');

  // "v1.2.0" or "1.2.0+3" -> [1, 2, 0]; null if it is not a version.
  // Preferred Psiphon routes stay at the top of a fresh Auto order.
  static const _preferredAutoPresets = [
    'MASQUE HTTP/2 → Psiphon',
    'MASQUE-in-MASQUE → Psiphon',
    'WARP-in-WARP → Psiphon',
  ];

  static int _preferredPriority(String name) {
    final i = _preferredAutoPresets.indexOf(name);
    return i < 0 ? _preferredAutoPresets.length : i;
  }

  static int _speedKey(Map<int, int> connectMs, int i) =>
      switch (connectMs[i]) {
        null => fastSecs * 1000,
        < 0 => 1 << 31,
        final ms => ms,
      };

  // A saved order (kept current by rerank, editable by the user) is used as is. Otherwise the preferred
  // Psiphon routes come first, then from past connects (preset index -> ms to connect, -1 = failed last time):
  // fastest first, then never tried (WireGuard first), then failed; other ties shuffled (List.sort is not
  // stable, so ties use the shuffle position).
  static List<Preset> autoOrder(Map<int, int> connectMs, [List<int>? saved]) {
    if (saved != null && saved.isNotEmpty)
      return [for (final i in saved) presets[i]];
    int key(int i) => _speedKey(connectMs, i);
    final shuffled = [
      for (final (i, p) in presets.indexed)
        if (!p.manualOnly) i,
    ]..shuffle();
    final rank = {for (final (pos, i) in shuffled.indexed) i: pos};
    shuffled.sort((a, b) {
      final aPreferred = _preferredPriority(presets[a].name);
      final bPreferred = _preferredPriority(presets[b].name);
      if (aPreferred != bPreferred) return aPreferred.compareTo(bPreferred);
      final c = key(a).compareTo(key(b));
      if (c != 0) return c;
      final aDefault =
          presets[a].name == 'WireGuard' && !connectMs.containsKey(a);
      final bDefault =
          presets[b].name == 'WireGuard' && !connectMs.containsKey(b);
      if (aDefault != bDefault) return aDefault ? -1 : 1;
      return rank[a]!.compareTo(rank[b]!);
    });
    return [for (final i in shuffled) presets[i]];
  }

  // After a connect attempt only the tested preset moves: before the first one that was slower (to the end if it failed).
  // Everything else keeps its place, so the user's own moves survive.
  static List<int> rerank(
    List<int> order,
    Map<int, int> connectMs,
    int tested,
  ) {
    if (!order.contains(tested)) return order;
    final rest = [
      for (final i in order)
        if (i != tested) i,
    ];
    final key = _speedKey(connectMs, tested);
    final at = rest.indexWhere((i) => _speedKey(connectMs, i) > key);
    return rest..insert(at < 0 ? rest.length : at, tested);
  }

  // Saved as "3,0,8"; unknown, malformed and repeated indexes are dropped.
  static List<int> parseOrder(String? s) => [
    ...{
      for (final i in (s ?? '').split(',').map(int.tryParse))
        if (i != null && i >= 0 && i < presets.length) i,
    },
  ];

  // Saved as "0:4200,8:-1"; unknown or malformed entries are dropped.
  static Map<int, int> parseConnectMs(String? s) => {
    for (final m in RegExp(r'(\d+):(-?\d+)').allMatches(s ?? ''))
      if (int.parse(m.group(1)!) < presets.length)
        int.parse(m.group(1)!): int.parse(m.group(2)!),
  };

  static String formatConnectMs(Map<int, int> connectMs) =>
      connectMs.entries.map((e) => '${e.key}:${e.value}').join(',');

  // Saved as "0:5:2:21000:1762850000;..." = preset:ok:fail:totalOkMs:lastOkEpochSeconds.
  static Map<int, ProtocolStat> parseStats(String? s) => {
    for (final m in RegExp(
      r'(\d+):(\d+):(\d+):(\d+):(\d+)',
    ).allMatches(s ?? ''))
      if (int.parse(m.group(1)!) < presets.length)
        int.parse(m.group(1)!): ProtocolStat(
          ok: int.parse(m.group(2)!),
          fail: int.parse(m.group(3)!),
          totalMs: int.parse(m.group(4)!),
          lastOk: int.parse(m.group(5)!),
        ),
  };

  static String formatStats(Map<int, ProtocolStat> stats) => stats.entries
      .map(
        (e) =>
            '${e.key}:${e.value.ok}:${e.value.fail}:${e.value.totalMs}:${e.value.lastOk}',
      )
      .join(';');

  static List<int>? parseVersion(String? s) {
    final m = RegExp(r'(\d+)\.(\d+)(?:\.(\d+))?').firstMatch(s ?? '');
    return m == null
        ? null
        : [for (var g = 1; g <= 3; g++) int.parse(m.group(g) ?? '0')];
  }

  static bool isNewer(List<int> a, List<int> b) {
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  // The latest GitHub release as (tag, page), or null when none is published yet (404).
  // The core is packed in the APK, so on Android a new core arrives with a new app release.
  static Future<(String, String)?> latestGuiRelease() async {
    final http = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final req = await http.getUrl(
        Uri.parse('https://api.github.com/repos/$guiRepo/releases/latest'),
      );
      req.headers.set('User-Agent', 'AetherGui');
      final res = await req.close().timeout(const Duration(seconds: 15));
      final body = await res.transform(utf8.decoder).join();
      if (res.statusCode == 404) return null;
      if (res.statusCode != 200)
        throw HttpException('GitHub answered ${res.statusCode}');
      final json = jsonDecode(body) as Map<String, dynamic>;
      return (json['tag_name'] as String, json['html_url'] as String);
    } finally {
      http.close();
    }
  }

  // A real request through aether's HTTP proxy measures the real delay.
  static final _http = HttpClient()
    ..findProxy = ((_) => 'PROXY 127.0.0.1:$httpPort')
    ..connectionTimeout = const Duration(seconds: 3);

  static final _ansi = RegExp(r'\x1B\[[0-9;]*[A-Za-z]');
  static final _errorLine = RegExp(
    r'^Error:\s*(.+)$|\bERROR\b[:\s]+(.+)$|(\bpanicked at\b.*)$',
  );
  static final _wrapped = RegExp(r'^Other\("(.*)"\)$');

  // The message of a core output line that reports an error, or null for any other line.
  static String? coreError(String line) {
    final m = _errorLine.firstMatch(line.replaceAll(_ansi, '').trim());
    if (m == null) return null;
    final text = (m.group(1) ?? m.group(2) ?? m.group(3))!.trim();
    final inner = _wrapped.firstMatch(text)?.group(1);
    return inner?.replaceAll(r'\"', '"') ?? text;
  }

  // The port named by a core error about an occupied local listener, or null for any other error.
  static int? busyPort(String error) {
    if (!error.contains('Address already in use')) return null;
    return int.tryParse(
      RegExp(r'127\.0\.0\.1:(\d+)').firstMatch(error)?.group(1) ?? '',
    );
  }

  // The foreground service keeps the app process alive after its screen is destroyed, but dispose() may not run,
  // so the previous core lives on holding the ports ("port in use" with no other app involved). True if one was killed.
  // shortcut: kills only aether itself, not the tor/psiphon helpers it spawned; they exit when their parent link closes.
  static bool killStale() {
    try {
      final pid = int.parse(File('$dir/core.pid').readAsStringSync().trim());
      // The pid may have been reused by another process since: only kill what really is our core.
      if (!File(
        '/proc/$pid/cmdline',
      ).readAsStringSync().contains('libaether')) {
        return false;
      }
      return Process.killPid(pid, ProcessSignal.sigkill);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> portFree(int port) async {
    try {
      await (await ServerSocket.bind('127.0.0.1', port)).close();
      return true;
    } catch (_) {
      return false;
    }
  }

  // The nearest usable port above an occupied one, or null if none of the next 100 is free.
  static Future<int?> freePort(int busy, int other) async {
    for (var p = busy + 1; p <= busy + 100; p++) {
      if (portError('$p', other) == null && await portFree(p)) return p;
    }
    return null;
  }

  static List<String> launchArguments(Preset p, CoreOptions options) {
    final args = p.args
        .split(' ')
        .where((a) => !['--turbo', '-4', '--quick-reconnect'].contains(a))
        .toList();
    final torExit = args.contains('--tor');
    final psiphonExit = args.contains('--psiphon');
    return [
      ...args, ...options.arguments,
      if (p.args.contains('--tor')) ...['--tor-pt', lyrebird],
      if (p.args.contains('--psiphon')) ...['--psiphon-bin', psiphon],
      // Forward modes have TWO listeners: the VPN and latency test must use
      // the second (Tor/Psiphon) exit, not silently stay on the WARP exit.
      '--bind',
      '127.0.0.1:${torExit || psiphonExit ? _internalPort : socksPort}',
      if (torExit) ...['--tor-bind', '127.0.0.1:$socksPort'],
      if (psiphonExit) ...['--psiphon-bind', '127.0.0.1:$socksPort'],
      p.httpFlag, '127.0.0.1:$httpPort',
    ];
  }

  static Future<AetherProcess?> start(
    Preset p,
    Log log, [
    CoreOptions options = const CoreOptions(),
    String scan = 'turbo',
  ]) async {
    try {
      final proc = await Process.start(
        exe,
        launchArguments(p, options),
        workingDirectory: dir,
        environment: {
          'HOME': dir,
          'AETHER_SCAN': scan,
          'AETHER_IP': 'v4', // the core accepts v4, v6 or both
          'AETHER_QUICK_RECONNECT': '1',
          ...options.environment,
        },
      );
      for (final s in [proc.stdout, proc.stderr]) {
        // Prompts (including email OTP) may not end with a newline.
        s.transform(const Utf8Decoder(allowMalformed: true)).listen((chunk) {
          for (final line in chunk.split(RegExp(r'[\r\n]+'))) {
            if (line.trim().isNotEmpty) log(line);
          }
        }, onError: (_) => log('Core output stream failed.'));
      }
      File('$dir/core.pid').writeAsStringSync('${proc.pid}');
      return AetherProcess(proc);
    } catch (_) {
      // ProcessException can include arguments containing access tokens.
      log('Core start failed. Check bundled binaries and core settings.');
      return null;
    }
  }

  // Waits for the proxy and, unless disabled, a passing internet test. Gives up once the startup budget is spent
  // and the proxy has been up for connectTimeoutMs without passing (tor opens its port long before it can carry traffic).
  static Future<(bool, int?)> waitConnected(
    AetherProcess proc,
    int startupSecs,
    Cancel ct, [
    Log? step,
    bool realDelayTest = true,
  ]) async {
    final sw = Stopwatch()..start();
    int? upAt;
    var reportAt = 15000;
    while (!proc.exited) {
      if (upAt == null && await _portOpen()) {
        upAt = sw.elapsedMilliseconds;
        step?.call(
          realDelayTest
              ? 'Local proxy ready, testing internet...'
              : 'Local proxy ready; internet test disabled.',
        );
        if (!realDelayTest) return (true, null);
      }
      if (upAt != null) {
        final ms = await ping(ct);
        if (ms != null) return (true, ms);
      }
      final t = sw.elapsedMilliseconds;
      if (t > startupSecs * 1000 &&
          (upAt == null || t - upAt > connectTimeoutMs))
        return (false, null);
      if (t >= reportAt) {
        reportAt += 15000;
        step?.call('Still connecting: ${t ~/ 1000}s of ${startupSecs}s...');
      }
      await ct.delay(500);
    }
    return (false, null);
  }

  // Whether aether's local SOCKS port is accepting connections.
  static Future<bool> portOpen() => _portOpen();

  static Future<bool> _portOpen() async {
    try {
      (await Socket.connect(
        '127.0.0.1',
        socksPort,
        timeout: const Duration(seconds: 1),
      )).destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  static Future<int?> ping(Cancel ct) async {
    final sw = Stopwatch()..start();
    Future<int?> get() async {
      final req = await _http.getUrl(Uri.parse(testUrl));
      req.persistentConnection = false;
      final res = await req.close();
      await res.drain<void>();
      // Any success counts, since user URLs may answer 200 rather than 204.
      return res.statusCode < 400 ? sw.elapsedMilliseconds : null;
    }

    int? ms;
    try {
      ms = await get().timeout(const Duration(seconds: 3));
    } catch (_) {}
    ct.check();
    return ms;
  }
}
