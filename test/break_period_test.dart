import 'package:flutter_test/flutter_test.dart';
import 'package:health_reminder/break_service.dart';

void main() {
  group('BreakPeriod', () {
    test('endMinutes = start + move', () {
      final p = BreakPeriod(startMinutes: 11 * 60, moveMinutes: 5);
      expect(p.endMinutes, 11 * 60 + 5);
    });

    test('round-trip JSON يحافظ على القيم', () {
      final p = BreakPeriod(startMinutes: 14 * 60 + 30, moveMinutes: 7, enabled: false);
      final r = BreakPeriod.fromJson(p.toJson());
      expect(r.startMinutes, p.startMinutes);
      expect(r.moveMinutes, p.moveMinutes);
      expect(r.enabled, p.enabled);
    });

    test('endMinutes لا يتجاوز نهاية اليوم', () {
      final p = BreakPeriod(startMinutes: 23 * 60 + 58, moveMinutes: 30);
      expect(p.endMinutes, lessThanOrEqualTo(24 * 60));
    });
  });
}
