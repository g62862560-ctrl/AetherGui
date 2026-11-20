import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aether_gui/aether.dart';
import 'package:aether_gui/main.dart';
import 'package:aether_gui/localization.dart';

void main() {
  testWidgets('language selector is ordered, persisted, and switches to RTL', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('aether-locale-ui-');
    Aether.dir = dir.path;
    Aether.exe = '${dir.path}/missing-core';
    final controller = LocaleController(defaultLocaleStore(dir.path));
    addTearDown(() => dir.deleteSync(recursive: true));

    await tester.pumpWidget(
      LocalizedApp(
        controller: controller,
        theme: Palette.theme,
        home: const HomePage(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    final selector = find.byKey(const Key('languageSelector'));
    expect(selector, findsOneWidget);
    expect(tester.getSize(selector).height, greaterThanOrEqualTo(48));
    await tester.tap(selector);
    await tester.pumpAndSettle();
    final labels = ['English', 'Persian', 'Iraqi Arabic'];
    for (final label in labels) {
      expect(find.text(label), findsWidgets);
    }
    expect(
      labels
          .map((label) => tester.getTopLeft(find.text(label).last).dy)
          .toList(),
      orderedEquals(
        labels
            .map((label) => tester.getTopLeft(find.text(label).last).dy)
            .toList()
          ..sort(),
      ),
    );

    await tester.tap(find.text('Persian').last);
    await tester.pumpAndSettle();
    expect(controller.locale, AppLocales.persian);
    expect(find.text('تنظیمات'), findsWidgets);
    expect(find.text('زبان'), findsWidgets);
    expect(
      Directionality.of(tester.element(find.byType(Scaffold).last)),
      TextDirection.rtl,
    );
    expect(File('${dir.path}/locale.txt').readAsStringSync(), 'fa');

    await tester.tap(selector);
    await tester.pumpAndSettle();
    await tester.tap(find.text('عربی عراقی').last);
    await tester.pumpAndSettle();
    expect(controller.locale, AppLocales.iraqiArabic);
    expect(find.text('الإعدادات'), findsWidgets);
    expect(find.text('اللغة'), findsWidgets);
    expect(File('${dir.path}/locale.txt').readAsStringSync(), 'ar-IQ');
  });

  testWidgets(
    'VPN revocation stops the connection and explains what happened',
    (tester) async {
      final dir = Directory.systemTemp.createTempSync('aether-revoked-');
      Aether.dir = dir.path;
      Aether.exe = '${dir.path}/missing-core';
      const channel = MethodChannel('aether');
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      addTearDown(() {
        messenger.setMockMethodCallHandler(channel, null);
        dir.deleteSync(recursive: true);
      });
      await tester.pumpWidget(
        MaterialApp(theme: Palette.theme, home: const HomePage()),
      );
      await tester.pumpAndSettle();

      await messenger.handlePlatformMessage(
        'aether',
        const StandardMethodCodec().encodeMethodCall(
          const MethodCall('vpnState', {
            'state': 'disconnected',
            'owned': false,
            'reason': 'revoked',
          }),
        ),
        (_) {},
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Another VPN took over'), findsWidgets);
      expect(find.byKey(const Key('reconnectVpn')), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('requested VPN stop does not look like a takeover', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('aether-vpn-stop-');
    Aether.dir = dir.path;
    Aether.exe = '${dir.path}/missing-core';
    const channel = MethodChannel('aether');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      dir.deleteSync(recursive: true);
    });
    await tester.pumpWidget(
      MaterialApp(theme: Palette.theme, home: const HomePage()),
    );
    await tester.pumpAndSettle();

    await messenger.handlePlatformMessage(
      'aether',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('vpnState', {
          'state': 'disconnected',
          'owned': false,
          'reason': 'requested',
        }),
      ),
      (_) {},
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Another VPN took over'), findsNothing);
    expect(find.byKey(const Key('reconnectVpn')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('a failed connect shows its error on home until dismissed', (
    tester,
  ) async {
    final dir = Directory.systemTemp.createTempSync('aether-error-');
    Aether.dir = dir.path;
    Aether.exe = '${dir.path}/missing-core';
    const channel = MethodChannel('aether');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (_) async => null);
    addTearDown(() {
      messenger.setMockMethodCallHandler(channel, null);
      dir.deleteSync(recursive: true);
    });
    await tester.pumpWidget(
      MaterialApp(theme: Palette.theme, home: const HomePage()),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('Connect'));
    await tester.pumpAndSettle();
    expect(find.textContaining('aether binary missing'), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss error'));
    await tester.pumpAndSettle();
    expect(find.textContaining('aether binary missing'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('protocol can be selected on Home and is saved', (tester) async {
    final dir = Directory.systemTemp.createTempSync('aether-protocol-');
    Aether.dir = dir.path;
    Aether.exe = '${dir.path}/missing-core';
    addTearDown(() => dir.deleteSync(recursive: true));
    await tester.pumpWidget(
      MaterialApp(theme: Palette.theme, home: const HomePage()),
    );
    await tester.pumpAndSettle();

    final wireGuard = Aether.presets.indexWhere((p) => p.name == 'WireGuard');
    await tester.tap(find.byKey(const Key('connectionProtocol')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('WireGuard').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();

    expect(
      find.descendant(
        of: find.byKey(const Key('connectionProtocol')),
        matching: find.text('WireGuard'),
      ),
      findsOneWidget,
    );
    expect(
      File('${dir.path}/settings.txt').readAsStringSync(),
      contains('Preset=$wireGuard'),
    );
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Auto try seconds are saved only in range', (tester) async {
    final dir = Directory.systemTemp.createTempSync('aether-try-seconds-');
    Aether.dir = dir.path;
    Aether.exe = '${dir.path}/missing-core';
    addTearDown(() => dir.deleteSync(recursive: true));
    await tester.pumpWidget(
      MaterialApp(theme: Palette.theme, home: const HomePage()),
    );
    await tester.pumpAndSettle();

    final field = find.byKey(const Key('autoTrySeconds'));
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('nextProtocol')))
          .onPressed,
      isNull,
    );
    await tester.enterText(field, '45');
    await tester.pump();
    expect(
      File('${dir.path}/settings.txt').readAsStringSync(),
      contains('TrySeconds=45'),
    );
    await tester.enterText(field, '2');
    await tester.pump();
    expect(
      File('${dir.path}/settings.txt').readAsStringSync(),
      contains('TrySeconds=45'),
    );
    expect(find.text('5–3600'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final size in [
    const Size(320, 568),
    const Size(844, 390),
    const Size(1200, 800),
  ]) {
    testWidgets('home stays simple and settings hold the rest at $size', (
      tester,
    ) async {
      final dir = Directory.systemTemp.createTempSync('aether-layout-');
      Aether.dir = dir.path;
      Aether.exe = '${dir.path}/missing-core';
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = size;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
        dir.deleteSync(recursive: true);
      });
      await tester.pumpWidget(
        MaterialApp(theme: Palette.theme, home: const HomePage()),
      );
      await tester.pumpAndSettle();

      // Home: connect, the full protocol list in stable order, and quick settings.
      expect(find.bySemanticsLabel('Connect'), findsOneWidget);
      expect(find.text('Auto - fastest route'), findsOneWidget);
      expect(find.text('You are not protected'), findsNothing);
      expect(find.byKey(const Key('resetOrderConnect')), findsOneWidget);
      expect(find.byKey(const Key('connectionProtocol')), findsOneWidget);
      expect(find.text('Waiting for logs...'), findsNothing);
      expect(tester.takeException(), isNull);

      // Settings keeps Auto order, the log, and core settings; Protocol stays on Home.
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownMenu<int>), findsNothing);
      expect(find.text('Psiphon server country'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Auto order'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Auto order'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Waiting for logs...'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Waiting for logs...'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.scrollUntilVisible(
        find.text('Core settings'),
        -200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('Core settings'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Additional arguments (JSON array)'),
        150,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Additional arguments (JSON array)'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
