import 'dart:async';
import 'dart:io';

import 'package:aether_gui/aether.dart';
import 'package:aether_gui/connection.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'stale pid metadata is removed without killing an unrelated process',
    () {
      final dir = Directory.systemTemp.createTempSync('aether-stale-pid-');
      addTearDown(() => dir.deleteSync(recursive: true));
      Aether.dir = dir.path;
      final file = File('${dir.path}/core.pid')..writeAsStringSync('not-a-pid');

      expect(Aether.killStale(), isFalse);
      expect(file.existsSync(), isFalse);
    },
  );

  test(
    'vpn start succeeds only when the native call acknowledges ownership',
    () async {
      const channel = MethodChannel('aether');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'vpnStart');
        expect(call.arguments, Aether.socksPort);
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      expect(await Aether.vpnStart(), isTrue);

      messenger.setMockMethodCallHandler(
        channel,
        (_) async =>
            throw PlatformException(code: 'vpn_start', message: 'failed'),
      );
      expect(await Aether.vpnStart(), isFalse);
    },
  );

  test(
    'vpn stop waits for native acknowledgement and rejects failure',
    () async {
      const channel = MethodChannel('aether');
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        expect(call.method, 'vpnStop');
        return true;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      expect(await Aether.vpnStop(), isTrue);

      messenger.setMockMethodCallHandler(
        channel,
        (_) async =>
            throw PlatformException(code: 'vpn_stop', message: 'stale'),
      );
      expect(await Aether.vpnStop(), isFalse);
    },
  );

  test(
    'cancelled probe closes its socket and a new session can probe',
    () async {
      final previousOverrides = HttpOverrides.current;
      HttpOverrides.global = _RealHttpOverrides();
      addTearDown(() => HttpOverrides.global = previousOverrides);
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final oldPort = Aether.httpPort;
      Aether.httpPort = server.port;
      addTearDown(() async {
        Aether.httpPort = oldPort;
        await server.close(force: true);
      });
      final received = Completer<HttpRequest>();
      final subscription = server.listen((request) {
        if (!received.isCompleted) {
          received.complete(
            request,
          ); // Simulate a proxy stalled by network loss.
        } else {
          request.response.statusCode = 204;
          request.response.close();
        }
      });
      addTearDown(subscription.cancel);
      final ct = Cancel();
      final probe = Aether.ping(ct);
      final expectation = expectLater(probe, throwsA(isA<Cancelled>()));
      final request = await received.future;
      final socket = await request.response.detachSocket(writeHeaders: false);
      final closed = socket.drain<void>();
      ct.cancel();
      await expectation;
      await closed.timeout(const Duration(seconds: 2));
      expect(await Aether.ping(Cancel()), isNotNull);
    },
  );

  test('core stop confirms exit before releasing owned pid metadata', () async {
    final dir = Directory.systemTemp.createTempSync('aether-core-stop-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final process = await Process.start(Platform.resolvedExecutable, [
      '--version',
    ]);
    final file = File('${dir.path}/core.pid')
      ..writeAsStringSync('${process.pid}');
    final core = AetherProcess(process, file);
    await core.stop();
    await process.exitCode;
    expect(core.exited, isTrue);
    expect(file.existsSync(), isFalse);
    await core.stop();
  });

  test('Tor bootstrap parses real percentages, not unrelated progress', () {
    expect(
      Aether.torBootstrapProgress(
        '[notice] Bootstrapped 43% (loading): Loading',
      ),
      43,
    );
    expect(Aether.torBootstrapProgress('Bootstrapped 100% (done): Done'), 100);
    expect(Aether.torBootstrapProgress('Bootstrapped 0% (starting)'), 0);
    expect(Aether.torBootstrapProgress('Bootstrapped 101%'), isNull);
    expect(Aether.torBootstrapProgress('download 43%'), isNull);
    expect(Aether.torBootstrapProgress('tor reaching the network: 15%'), 15);
    expect(
      Aether.torBootstrapProgress(
        '[INFO aether::tor] tor reaching the network: 100%',
      ),
      100,
    );
    expect(
      Aether.torBootstrapProgress('tor reaching the network: 101%'),
      isNull,
    );
  });

  test('native state validates payload', () {
    expect(NativeVpnState.from(null), isNull);
    expect(NativeVpnState.from({'owned': true}), isNull);
    final state = NativeVpnState.from({
      'state': 'error',
      'owned': false,
      'error': 'failed',
      'reason': 'revoked',
    });
    expect(state?.state, 'error');
    expect(state?.owned, isFalse);
    expect(state?.error, 'failed');
    expect(state?.reason, 'revoked');
  });

  test(
    'controller exposes explicit phases and serializes lifecycle work',
    () async {
      final controller = ConnectionController();
      addTearDown(controller.dispose);
      controller.transition(
        ConnectionPhase.recovering,
        message: 'revoked',
        reconnectAvailable: true,
      );
      expect(controller.value.phase, ConnectionPhase.recovering);
      expect(controller.value.reconnectAvailable, isTrue);

      final order = <int>[];
      final gate = Completer<void>();
      final first = controller.serialize(() async {
        order.add(1);
        await gate.future;
        order.add(2);
      });
      final second = controller.serialize(() async => order.add(3));
      await Future<void>.delayed(Duration.zero);
      expect(order, [1]);
      gate.complete();
      await Future.wait([first, second]);
      expect(order, [1, 2, 3]);
    },
  );
}
