import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:aether_gui/aether.dart';
import 'package:aether_gui/main.dart';

void main() {
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

      // Home: the connect switch, quick settings and the status banner; nothing technical.
      expect(find.bySemanticsLabel('Connect'), findsOneWidget);
      expect(find.text('Auto - fastest route'), findsOneWidget);
      expect(find.text('You are not protected'), findsOneWidget);
      expect(find.byType(DropdownMenu<int>), findsNothing);
      expect(find.text('Waiting for logs...'), findsNothing);
      expect(tester.takeException(), isNull);

      // Settings: protocol list in stable order, the log, and core settings.
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      final menu = tester.widget<DropdownMenu<int>>(
        find.byType(DropdownMenu<int>),
      );
      final entries = menu.dropdownMenuEntries;
      expect(entries.first.value, -1);
      final expectedIndexes = [
        for (final manualOnly in [false, true])
          for (final (i, p) in Aether.presets.indexed)
            if (p.manualOnly == manualOnly) i,
      ];
      expect(entries.skip(1).map((e) => e.value), expectedIndexes);
      for (final entry in entries.skip(1)) {
        expect(entry.label, Aether.presets[entry.value].label);
      }
      await tester.scrollUntilVisible(
        find.text('Waiting for logs...'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Waiting for logs...'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Show activity log'));
      await tester.pumpAndSettle();
      expect(find.text('Waiting for logs...'), findsNothing);

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
