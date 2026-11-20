import 'package:aether_gui/exit_info.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a full exit line with colo, latency and warp', () {
    final exit = parseExit(
      '[+] masque-in-masque exit: 104.28.214.161, IR via FRA, 448ms to cloudflare, warp on',
    );

    expect(exit, isNotNull);
    final info = exit!;
    expect(info.ip, '104.28.214.161');
    expect(info.countryCode, 'IR');
    expect(info.colo, 'FRA');
    expect(info.latencyMs, 448);
    expect(info.warp, isTrue);
  });

  test('parses a psiphon exit line with no colo and warp off', () {
    final exit = parseExit(
      '[+] psiphon exit: 1.2.3.4, US, 250ms to cloudflare, warp off',
    );

    expect(exit, isNotNull);
    final info = exit!;
    expect(info.ip, '1.2.3.4');
    expect(info.countryCode, 'US');
    expect(info.colo, isNull);
    expect(info.latencyMs, 250);
    expect(info.warp, isFalse);
  });

  test('ignores non-exit lines and malformed exit lines', () {
    expect(parseExit('INFO scanning endpoints'), isNull);
    expect(parseExit('Connected: MASQUE'), isNull);
    expect(
      parseExit('exit: 1.2.3.4, US, 250ms to cloudflare, warp off'),
      isNull,
    );
    expect(
      parseExit('[+] psiphon exit: not-an-ip, US, 5ms to cloudflare, warp off'),
      isNull,
    );
    expect(
      parseExit('[+] psiphon exit: 1.2.3.4, USA, 5ms to cloudflare, warp off'),
      isNull,
    );
    expect(
      parseExit('[+] psiphon exit: 1.2.3.4, U1, 5ms to cloudflare, warp off'),
      isNull,
    );
    expect(parseExit('[+] psiphon exit: 1.2.3.4'), isNull);
  });

  test('looks up known country names and falls back to the code', () {
    expect(exitCountryName('US'), 'United States');
    expect(exitCountryName('DE'), 'Germany');
    expect(exitCountryName('IR'), 'IR');
    expect(exitCountryName('ZZ'), 'ZZ');
  });

  test('derives regional-indicator flag emoji from a two-letter code', () {
    expect(exitCountryFlag('IR'), '🇮🇷');
    expect(exitCountryFlag('US'), '🇺🇸');
    expect(exitCountryFlag('de'), '🇩🇪');
  });

  test('compact connected badge shows only the country flag', () {
    final exit = const ExitInfo(
      ip: '104.28.214.161',
      countryCode: 'IR',
      colo: 'FRA',
      latencyMs: 448,
      warp: true,
    );
    expect(formatExitFlag(exit), '🇮🇷');
    expect(formatExitFlag(exit), isNot(contains(exit.ip)));
    expect(formatExitFlag(exit), isNot(contains('IR')));
  });

  test('formats the C# ShowExit display string', () {
    expect(
      formatExit(
        const ExitInfo(
          ip: '104.28.214.161',
          countryCode: 'IR',
          colo: 'FRA',
          latencyMs: 448,
          warp: true,
        ),
      ),
      '🇮🇷 IR · 104.28.214.161 · 448 ms · WARP',
    );
    expect(
      formatExit(const ExitInfo(ip: '1.2.3.4', countryCode: 'US', warp: false)),
      '🇺🇸 United States · 1.2.3.4',
    );
  });
}
