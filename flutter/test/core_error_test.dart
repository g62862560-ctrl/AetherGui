import 'package:aether_gui/aether.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('reads the message of a fatal core error', () {
    expect(
      Aether.coreError(
        r'Error: Other("the socks5 listener cannot use 127.0.0.1:10808: Address already in use (os error 98)")',
      ),
      'the socks5 listener cannot use 127.0.0.1:10808: Address already in use (os error 98)',
    );
    expect(Aether.coreError(r'Error: Other("bad \"value\"")'), 'bad "value"');
  });

  test('reads log-level errors and panics, with or without colors', () {
    expect(
      Aether.coreError('2026-11-01T19:35:58Z ERROR aether: no endpoint'),
      'aether: no endpoint',
    );
    expect(Aether.coreError('\x1B[31mERROR\x1B[0m no endpoint'), 'no endpoint');
    expect(
      Aether.coreError("thread 'main' panicked at src/main.rs:1:1"),
      'panicked at src/main.rs:1:1',
    );
  });

  test('ignores ordinary output', () {
    expect(Aether.coreError('INFO scanning endpoints'), isNull);
    expect(Aether.coreError('WARN handshake failed, retrying'), isNull);
    expect(Aether.coreError('error rate is 0'), isNull);
  });
}
