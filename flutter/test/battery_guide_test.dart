import 'package:flutter_test/flutter_test.dart';
import 'package:aether_gui/battery_guide.dart';

void main() {
  test('maps sub-brands to their parent family', () {
    expect(brandOf('Xiaomi', 'POCO'), PhoneBrand.xiaomi);
    expect(brandOf('HONOR', 'honor'), PhoneBrand.huawei);
    expect(brandOf('realme', 'realme'), PhoneBrand.oppo);
    expect(brandOf('Google', 'google'), PhoneBrand.stock);
  });

  test('battery step is dropped when already done', () {
    final todo = guideFor(PhoneBrand.samsung, 34);
    final done = guideFor(PhoneBrand.samsung, 34, batteryDone: true);
    expect(todo.length, done.length + 1);
    expect(todo.first.setting, 'battery');
    expect(
      guideFor(PhoneBrand.stock, 21).any((s) => s.setting == 'battery'),
      isFalse,
    );
  });
}
