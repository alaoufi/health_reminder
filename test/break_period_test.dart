import 'package:flutter_test/flutter_test.dart';
import 'package:health_reminder/break_service.dart';

void main() {
  group('BreakPeriod — نافذة عمل + راحات متكرّرة', () {
    test('راحات كل ٦٠ د داخل نافذة ٤م–١١م تُنتج ٦ راحات', () {
      // 16:00 → 23:00 = 420 دقيقة. دورة (عمل 60 + راحة 5) = 65.
      // أوقات بدء الراحات: 60,125,190,255,320,385 (كلها +5 ضمن 420).
      final p = BreakPeriod(
          startMinutes: 16 * 60,
          endMinutes: 23 * 60,
          workMinutes: 60,
          restMinutes: 5);
      final starts = p.restStarts();
      expect(starts.length, 6);
      expect(starts.first, 16 * 60 + 60); // أوّل راحة بعد أوّل ساعة عمل
    });

    test('round-trip JSON يحافظ على القيم', () {
      final p = BreakPeriod(
          startMinutes: 9 * 60,
          endMinutes: 17 * 60,
          workMinutes: 45,
          restMinutes: 3,
          enabled: false);
      final r = BreakPeriod.fromJson(p.toJson());
      expect(r.startMinutes, p.startMinutes);
      expect(r.endMinutes, p.endMinutes);
      expect(r.workMinutes, p.workMinutes);
      expect(r.restMinutes, p.restMinutes);
      expect(r.enabled, p.enabled);
    });

    test('لا راحات إذا كان العمل أطول من النافذة', () {
      final p = BreakPeriod(
          startMinutes: 10 * 60,
          endMinutes: 10 * 60 + 30,
          workMinutes: 60,
          restMinutes: 5);
      expect(p.restStarts(), isEmpty);
    });

    test('يدعم الراحات داخل نافذة تعبر منتصف الليل', () {
      final p = BreakPeriod(
          startMinutes: 22 * 60,
          endMinutes: 2 * 60,
          workMinutes: 60,
          restMinutes: 15);
      expect(p.restStarts(), [23 * 60, 15, 90]);
    });
  });
}
