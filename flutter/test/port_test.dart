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
}
