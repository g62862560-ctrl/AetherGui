import 'package:flutter_test/flutter_test.dart';
import 'package:aether_gui/aether.dart';

void main() {
  statsTests();
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

  test(
    'preferred Psiphon routes are first in the fresh default Auto order',
    () {
      const preferred = [
        'MASQUE HTTP/2 → Psiphon',
        'MASQUE-in-MASQUE → Psiphon',
        'WARP-in-WARP → Psiphon',
      ];
      for (var run = 0; run < 20; run++) {
        expect(Aether.autoOrder({}).take(3).map((p) => p.name), preferred);
      }
      final failed = {index('MASQUE HTTP/2 → Psiphon'): -1};
      expect(Aether.autoOrder(failed).take(3).map((p) => p.name), preferred);
    },
  );

  test(
    'preferred routes come first, then fastest; failed non-preferred last',
    () {
      final past = {
        index('WireGuard'): 9000,
        index('MASQUE'): 3000,
        index('MASQUE-in-MASQUE'): -1,
      };
      const preferred = [
        'MASQUE HTTP/2 → Psiphon',
        'MASQUE-in-MASQUE → Psiphon',
        'WARP-in-WARP → Psiphon',
      ];
      for (var run = 0; run < 20; run++) {
        final order = Aether.autoOrder(past).map((p) => p.name).toList();
        expect(order.take(3), preferred);
        expect(order.indexOf('MASQUE'), lessThan(order.indexOf('WireGuard')));
        expect(order.length, Aether.presets.where((p) => !p.manualOnly).length);
      }
      expect(Aether.autoOrder({index('WireGuard'): -1}).last.name, 'WireGuard');
    },
  );

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

  test('connect times round-trip and junk is dropped', () {
    final past = {index('MASQUE'): 3000, index('MASQUE-in-MASQUE'): -1};
    final saved = Aether.parseConnectMs(
      '${Aether.formatConnectMs(past)},999:5,x:1',
    );
    expect(saved, past);
  });
}

void statsTests() {
  test('protocol stats round-trip and give a verdict', () {
    final stats = Aether.parseStats(
      '0:5:2:21000:1762850000;1:0:3:0:0;99:1:1:1:1',
    );
    expect(stats.length, 2); // unknown preset dropped
    expect(Aether.parseStats(Aether.formatStats(stats))[0]!.avgMs, 4200);
    expect(stats[0]!.verdict, 'good');
    expect(stats[1]!.verdict, 'bad');
    expect(ProtocolStat().verdict, 'new');
    expect(ProtocolStat(ok: 1).verdict, 'maybe');
  });
}
