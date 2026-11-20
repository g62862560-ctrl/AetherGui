import 'dart:io';

import 'package:aether_gui/aether.dart';
import 'package:aether_gui/auto_order_page.dart';
import 'package:aether_gui/battery_guide.dart';
import 'package:aether_gui/localization.dart';
import 'package:aether_gui/protocol_order_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pumpLocalized(
  WidgetTester tester,
  Locale locale,
  Widget home,
) async {
  final directory = Directory.systemTemp.createTempSync(
    'aether-secondary-i18n-',
  );
  addTearDown(() => directory.deleteSync(recursive: true));
  final controller = LocaleController(
    LocaleStore(File('${directory.path}/locale.txt')),
    initialLocale: locale,
  );
  await tester.pumpWidget(
    LocalizedApp(controller: controller, theme: ThemeData(), home: home),
  );
  await tester.pump();
}

void main() {
  test('battery guide data is accurately localized', () {
    final fa = guideFor(
      PhoneBrand.xiaomi,
      34,
      l10n: const AppLocalizations(AppLocales.persian),
    );
    expect(fa.first.title, 'بهینه‌سازی باتری');
    expect(fa.any((step) => step.title == 'اجرای خودکار'), isTrue);
    final ar = guideFor(
      PhoneBrand.samsung,
      34,
      l10n: const AppLocalizations(AppLocales.iraqiArabic),
    );
    expect(ar.first.button, 'فتح تحسين البطارية');
    expect(ar.any((step) => step.title == 'تطبيقات ما تدخل بالنوم'), isTrue);
  });

  testWidgets('auto order renders Persian in RTL', (tester) async {
    await pumpLocalized(
      tester,
      AppLocales.persian,
      AutoOrderPage(
        order: Aether.menuPresetIndexes.take(2).toList(),
        checked: [Aether.menuPresetIndexes.first],
        ranking: Aether.menuPresetIndexes.take(2).toList(),
      ),
    );
    expect(find.text('ترتیب خودکار'), findsOneWidget);
    expect(find.text('ذخیره'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('ترتیب خودکار'))),
      TextDirection.rtl,
    );
  });

  testWidgets('protocol sheet renders Iraqi Arabic in RTL', (tester) async {
    await pumpLocalized(
      tester,
      AppLocales.iraqiArabic,
      Scaffold(
        body: ProtocolOrderSheet(
          order: Aether.menuPresetIndexes.take(2).toList(),
          selected: -1,
        ),
      ),
    );
    expect(find.text('ترتيب البروتوكولات'), findsOneWidget);
    expect(find.text('تلقائي (الترتيب بالإعدادات)'), findsOneWidget);
    expect(
      Directionality.of(tester.element(find.text('ترتيب البروتوكولات'))),
      TextDirection.rtl,
    );
  });

  test('secondary translations do not fall back to English', () {
    const keys = [
      'batteryGuideTitle',
      'autoOrder',
      'protocolOrder',
      'coreSettings',
      'saveSettingsFailed',
    ];
    const en = AppLocalizations(AppLocales.english);
    const fa = AppLocalizations(AppLocales.persian);
    const ar = AppLocalizations(AppLocales.iraqiArabic);
    for (final key in keys) {
      expect(fa.text(key), isNot(en.text(key)), reason: 'Persian $key');
      expect(ar.text(key), isNot(en.text(key)), reason: 'Iraqi Arabic $key');
    }
  });
}
