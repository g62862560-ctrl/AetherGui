import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aether_gui/aether.dart';
import 'package:aether_gui/core_options.dart';
import 'package:aether_gui/core_settings_page.dart';
import 'package:aether_gui/psiphon_countries.dart';
import 'package:aether_gui/main.dart';

void main() {
  test('C# list, flags, normalization and validation', () {
    expect(
      psiphonCountries.map((c) => c.code).join(','),
      ',AT,BE,CA,CH,CZ,DE,DK,ES,FI,FR,GB,HU,IE,IN,IT,JP,NL,NO,PL,RO,RS,SE,SG,SK,US',
    );
    expect(psiphonCountries.first.label, '🌐 Automatic');
    expect(psiphonCountries.last.label, '🇺🇸 United States (US)');
    for (final country in psiphonCountries) {
      expect(
        CoreOptions.normalizePsiphonRegion(' ${country.code.toLowerCase()} '),
        country.code,
      );
    }
    expect(CoreOptions.normalizePsiphonRegion(null), '');
    for (final invalid in ['ZZ', 'USA', 'Automatic', 'U1']) {
      expect(
        () => CoreOptions.normalizePsiphonRegion(invalid),
        throwsFormatException,
      );
    }
    expect(const CoreOptions().isConfigured, isFalse);
    expect(const CoreOptions(psiphonRegion: 'DE').isConfigured, isTrue);
  });

  test(
    'missing, legacy, normalized persistence, reset and invalid storage',
    () async {
      final dir = Directory.systemTemp.createTempSync('country-test-');
      addTearDown(() => dir.deleteSync(recursive: true));
      expect(CoreOptions.load(dir.path).psiphonRegion, '');
      final file = File('${dir.path}/core-options.json');
      file.writeAsStringSync(
        '{"arguments":[],"environment":{},"startupSeconds":450}',
      );
      expect(CoreOptions.load(dir.path).psiphonRegion, '');
      final options = CoreOptions.parse(
        '["--stats"]',
        '{"AETHER_PSIPHON_REGION":""}',
        '450',
        psiphonRegion: ' de ',
      );
      await options.save(dir.path);
      final loaded = CoreOptions.load(dir.path);
      expect(loaded.psiphonRegion, 'DE');
      expect(loaded.arguments, options.arguments);
      expect(loaded.environment, options.environment);
      expect(loaded.startupSeconds, 450);
      await const CoreOptions().save(dir.path);
      expect(CoreOptions.load(dir.path).arguments, isEmpty);
      final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
      data['psiphonRegion'] = 'ZZ';
      file.writeAsStringSync(jsonEncode(data));
      expect(() => CoreOptions.load(dir.path), throwsFormatException);
      expect(
        () => const CoreOptions(psiphonRegion: 'ZZ').save(dir.path),
        throwsFormatException,
      );
    },
  );

  test(
    'all presets scope country correctly and preserve explicit overrides',
    () {
      Aether.lyrebird = '/native/liblyrebird.so';
      Aether.psiphon = '/native/libpsiphon.so';
      for (final preset in Aether.presets) {
        final relevant = preset.args
            .split(' ')
            .any(
              (a) => [
                '--psiphon',
                '--psiphon-only',
                '--psiphon-reverse',
              ].contains(a),
            );
        final baseline = Aether.launchArguments(preset, const CoreOptions());
        expect(baseline, isNot(contains('--psiphon-region')));
        final args = Aether.launchArguments(
          preset,
          const CoreOptions(psiphonRegion: ' de '),
        );
        expect(
          args.contains('--psiphon-region'),
          relevant,
          reason: preset.name,
        );
        if (relevant) {
          final index = args.indexOf('--psiphon-region');
          expect(args[index + 1], 'DE');
          args.removeRange(index, index + 2);
        }
        expect(args, baseline);
        for (final explicit in [
          const CoreOptions(
            arguments: ['--psiphon-region', 'US'],
            psiphonRegion: 'DE',
          ),
          const CoreOptions(
            arguments: ['--psiphon-region='],
            psiphonRegion: 'DE',
          ),
          const CoreOptions(
            environment: {'AETHER_PSIPHON_REGION': ''},
            psiphonRegion: 'DE',
          ),
          const CoreOptions(
            environment: {'aether_psiphon_region': 'US'},
            psiphonRegion: 'DE',
          ),
        ]) {
          expect(explicit.hasPsiphonRegionOverride, isTrue);
          final actual = Aether.launchArguments(preset, explicit);
          expect(actual, isNot(contains('DE')));
          expect(actual, containsAll(explicit.arguments));
        }
      }
      expect(
        const CoreOptions(
          arguments: ['--psiphon-region-extra=US'],
        ).hasPsiphonRegionOverride,
        isFalse,
      );
      expect(
        const CoreOptions(
          arguments: ['--PSIPHON-REGION=US'],
        ).hasPsiphonRegionOverride,
        isFalse,
      );
    },
  );

  testWidgets(
    'main settings saves country; stale advanced reset preserves it',
    (tester) async {
      const channel = MethodChannel('aether');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      final dir = Directory.systemTemp.createTempSync('country-widget-');
      Aether.dir = dir.path;
      Aether.exe = '${dir.path}/missing-core';
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      addTearDown(() async {
        await tester.runAsync(() async {
          for (var attempt = 0; ; attempt++) {
            try {
              dir.deleteSync(recursive: true);
              break;
            } on FileSystemException {
              if (attempt == 20) rethrow;
              await Future<void>.delayed(const Duration(milliseconds: 100));
            }
          }
        });
      });
      await tester.pumpWidget(
        MaterialApp(theme: Palette.theme, home: const HomePage()),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Psiphon server country'), findsOneWidget);
      expect(
        tester
            .widget<DropdownButton<String>>(find.byType(DropdownButton<String>))
            .items,
        hasLength(26),
      );
      expect(find.textContaining('not the final WARP exit'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('🇦🇹 Austria (AT)').last);
      await tester.pumpAndSettle();

      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(CoreOptions.load(dir.path).psiphonRegion, 'AT');
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        MaterialApp(
          home: CoreSettingsPage(
            options: const CoreOptions(psiphonRegion: 'DE'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DropdownButtonFormField<String>), findsNothing);
      CoreOptions.savePsiphonRegion(dir.path, 'JP');
      await tester.scrollUntilVisible(
        find.text('Reset fields to defaults'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Reset fields to defaults'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save'));
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pumpAndSettle();
      expect(CoreOptions.load(dir.path).psiphonRegion, 'JP');
      expect(CoreOptions.load(dir.path).arguments, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}
