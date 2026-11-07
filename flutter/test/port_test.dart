import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:aether_gui/aether.dart';

void main() {
  test(
    'proxy ports must be unprivileged, distinct and not the internal one',
    () {
      expect(Aether.portError('1819', 1818), isNull);
      expect(Aether.portError('', 1818), isNotNull);
      expect(Aether.portError('80', 1818), isNotNull);
      expect(Aether.portError('70000', 1818), isNotNull);
      expect(Aether.portError('1818', 1818), isNotNull);
      expect(Aether.portError('1822', 1818), isNotNull);
    },
  );

  test('delay test URL must be a full http(s) URL', () {
    for (final u in Aether.testUrlSuggestions) {
      expect(Aether.testUrlError(u), isNull);
    }
    expect(Aether.testUrlError('gstatic.com/generate_204'), isNotNull);
    expect(Aether.testUrlError('ftp://example.com'), isNotNull);
    expect(Aether.testUrlError(''), isNotNull);
  });

  test('disabled real delay test only requires the local proxy', () async {
    final dir = Directory.systemTemp.createTempSync('aether-delay-test-');
    final script = File('${dir.path}/wait.dart')
      ..writeAsStringSync(
        'Future<void> main() => Future<void>.delayed(const Duration(minutes: 1));',
      );
    final process = await Process.start(Platform.resolvedExecutable, [
      script.path,
    ]);
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    final previousPort = Aether.socksPort;
    Aether.socksPort = server.port;
    addTearDown(() async {
      Aether.socksPort = previousPort;
      process.kill();
      await process.exitCode;
      await server.close();
      dir.deleteSync(recursive: true);
    });

    final result = await Aether.waitConnected(
      AetherProcess(process),
      1,
      Cancel(),
      null,
      false,
    ).timeout(const Duration(seconds: 2));

    expect(result.$1, isTrue);
    expect(result.$2, isNull);
  });
}
