import 'dart:io';

import 'package:aether_gui/localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory directory;
  late LocaleStore store;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('aether-locale-');
    store = LocaleStore(File('${directory.path}/locale.txt'));
  });
  tearDown(() => directory.deleteSync(recursive: true));

  test(
    'locale encoding resolves supported variants and rejects unknown values',
    () {
      expect(AppLocales.decode('ar_IQ'), AppLocales.iraqiArabic);
      expect(AppLocales.decode('fa-IR'), AppLocales.persian);
      expect(AppLocales.decode('de'), isNull);
      expect(
        AppLocales.resolve(const Locale('ar', 'EG')),
        AppLocales.iraqiArabic,
      );
    },
  );

  test('controller persists a selected locale and restores it', () async {
    final controller = LocaleController(store);
    await controller.setLocale(AppLocales.persian);
    expect(await store.read(), AppLocales.persian);
    final restored = LocaleController(store);
    await restored.load(systemLocale: const Locale('en'));
    expect(restored.locale, AppLocales.persian);
    expect(restored.textDirection, TextDirection.rtl);
  });

  test('system locale is used when no preference exists', () async {
    final controller = LocaleController(store);
    await controller.load(systemLocale: const Locale('ar', 'IQ'));
    expect(controller.locale, AppLocales.iraqiArabic);
  });

  testWidgets('localized wrapper applies translations, scope, and RTL', (
    tester,
  ) async {
    final controller = LocaleController(store);
    controller.setLocale(AppLocales.iraqiArabic);
    await tester.pumpWidget(
      Localizations(
        locale: controller.locale,
        delegates: const [
          DefaultWidgetsLocalizations.delegate,
          AppLocalizations.delegate,
        ],
        child: Directionality(
          textDirection: controller.textDirection,
          child: LocaleScope(
            controller: controller,
            child: Builder(
              builder: (context) => Text(
                '${context.l10n.settings}:${context.localeController.locale.toLanguageTag()}',
              ),
            ),
          ),
        ),
      ),
    );
    expect(find.text('الإعدادات:ar-IQ'), findsOneWidget);
    final text = tester.widget<Text>(find.text('الإعدادات:ar-IQ'));
    expect(
      Directionality.of(tester.element(find.byWidget(text))),
      TextDirection.rtl,
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });

  test('Persian and Iraqi Arabic cover every declared translation key', () {
    for (final locale in [AppLocales.persian, AppLocales.iraqiArabic]) {
      final l10n = AppLocalizations(locale);
      for (final key in AppLocalizations.keys) {
        expect(
          l10n.hasTranslation(key),
          isTrue,
          reason: '${locale.toLanguageTag()} is missing $key',
        );
      }
    }
  });

  test('missing translation falls back to English then key', () {
    expect(
      const AppLocalizations(AppLocales.persian).text('appName'),
      'ایثر وی‌پی‌ان',
    );
    expect(
      const AppLocalizations(AppLocales.persian).text('unknown'),
      'unknown',
    );
  });
}
