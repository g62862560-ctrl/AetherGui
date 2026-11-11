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
      expect(find.byKey(const Key('connectionProtocol')), findsNothing);
      expect(find.text('Waiting for logs...'), findsNothing);
      expect(tester.takeException(), isNull);

      // Settings keeps Auto order, the log, and core settings; Protocol stays on Home.
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(DropdownMenu<int>), findsNothing);
      expect(find.text('Auto order'), findsOneWidget);
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
