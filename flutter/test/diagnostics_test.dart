import 'dart:io';

import 'package:aether_gui/diagnostics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('redacts credentials, authorization and URL user info', () {
    final redacted = redactDiagnostic(
      'token=abc123 password: hunter2 Authorization: Bearer xyz '
      'https://alice:secret@example.com/?key=qwerty',
    );
    expect(redacted, isNot(contains('abc123')));
    expect(redacted, isNot(contains('hunter2')));
    expect(redacted, isNot(contains('xyz')));
    expect(redacted, isNot(contains('alice:secret')));
    expect(redacted, isNot(contains('qwerty')));
    expect(redacted, contains('[REDACTED]'));
  });

  test('diagnostic log bounds count and line length', () {
    final log = DiagnosticLog(maxLines: 2, maxLineLength: 5);
    log.add('first');
    log.add('second');
    log.add('third-long');
    expect(log.lines, ['secon…', 'third…']);
  });

  test('report is redacted and writes atomically to local directory', () async {
    final dir = Directory.systemTemp.createTempSync('aether-diagnostic-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final report = buildDiagnosticReport(
      connectionState: 'error',
      mode: 'VPN',
      lines: ['secret=do-not-share'],
      generatedAt: DateTime.utc(2026),
    );
    expect(report, contains('secret=[REDACTED]'));
    final file = await writeDiagnosticReport(dir.path, report);
    expect(file.path, endsWith('aether-diagnostic.txt'));
    expect(await file.readAsString(), report);
    expect(File('${file.path}.tmp').existsSync(), isFalse);
  });
}
