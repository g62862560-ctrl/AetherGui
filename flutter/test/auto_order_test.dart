import 'package:flutter_test/flutter_test.dart';
import 'package:aether_gui/aether.dart';
import 'package:aether_gui/auto_order_page.dart';

void main() {
  int index(String name) => Aether.presets.indexWhere((p) => p.name == name);

  test('Next protocol follows menu order and wraps around', () {
    final order = Aether.menuPresetIndexes;
    for (var i = 0; i < order.length; i++) {
      expect(Aether.nextPresetIndex(order[i]), order[(i + 1) % order.length]);
    }
  });

  test('fresh Auto includes the four requested Psiphon routes', () {
    final names = Aether.autoOrder({}).map((p) => p.name).toSet();
    expect(
      names,
      containsAll([
        'MASQUE HTTP/2 → Psiphon',
        'WireGuard → Psiphon',
        'WARP-in-WARP → Psiphon',
        'MASQUE-in-MASQUE → Psiphon',
      ]),
    );
    expect(names.length, 13);
    expect(names, isNot(contains('MASQUE → Psiphon')));
    expect(names, isNot(contains('Psiphon alone')));
  });

  test('cancelling a connection also cancels its current attempt', () async {
    final connection = Cancel();
    final attempt = Cancel(connection);
    connection.cancel();
    await expectLater(attempt.delay(1000), throwsA(isA<Cancelled>()));
  });

  test('WireGuard is first in the fresh default Auto order', () {
    for (var run = 0; run < 20; run++) {
      expect(Aether.autoOrder({}).first.name, 'WireGuard');
    }
    final failed = {index('WireGuard'): -1};
    expect(Aether.autoOrder(failed).first.name, isNot('WireGuard'));
  });

  test('Auto tries the fastest past connect first and failed ones last', () {
    final past = {
      index('WireGuard'): 9000,
      index('MASQUE'): 3000,
      index('MASQUE-in-MASQUE'): -1,
    };
    for (var run = 0; run < 20; run++) {
      final order = Aether.autoOrder(past).map((p) => p.name).toList();
      expect(order.take(2), ['MASQUE', 'WireGuard']);
      expect(order.last, 'MASQUE-in-MASQUE');
      expect(order.length, Aether.presets.where((p) => !p.manualOnly).length);
    }
  });

  test('a saved order is used as is; junk dropped', () {
    final saved = Aether.parseOrder(
      '${index('Tor alone')},x,${index('MASQUE')},${index('Tor alone')},999,-1',
    );
    expect(Aether.autoOrder({}, saved).map((p) => p.name), [
      'Tor alone',
      'MASQUE',
    ]);
  });

  test('rerank moves only the tested protocol', () {
    final past = {index('WireGuard'): 9000, index('MASQUE'): 3000};
    final m = index('MASQUE'), w = index('WireGuard'), t = index('Tor alone');
    expect(Aether.rerank([w, t, m], {...past, m: 2000}, m), [m, w, t]);
    expect(Aether.rerank([w, t, m], {...past, w: -1}, w), [t, m, w]);
    expect(Aether.rerank([w, t, m], past, index('MASQUE HTTP/2')), [w, t, m]);
  });

  test('arrows move every checked protocol together', () {
    // 0 1* 2 3* 4  -up->  1* 0 3* 2 4  -up->  1* 3* 0 2 4  -down x2->  0 2 1* 3* 4
    final items = [0, 1, 2, 3, 4], on = {1, 3};
    moveChecked(items, on, -1);
    expect(items, [1, 0, 3, 2, 4]);
    moveChecked(items, on, -1);
    expect(items, [1, 3, 0, 2, 4]);
    moveChecked(items, on, 1);
    moveChecked(items, on, 1);
    expect(items, [0, 2, 1, 3, 4]);
  });

  test('connect times round-trip and junk is dropped', () {
    final past = {index('MASQUE'): 3000, index('MASQUE-in-MASQUE'): -1};
    final saved = Aether.parseConnectMs(
      '${Aether.formatConnectMs(past)},999:5,x:1',
    );
    expect(saved, past);
  });
}
