import 'dart:async';
import 'dart:io';

import 'package:aether_gui/aether.dart';
import 'package:aether_gui/connection.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

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
