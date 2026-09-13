import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// فترة «كسر جلوس»: وقت البداية (دقائق من منتصف الليل) ومدّة الحركة بالدقائق.
class BreakPeriod {
  int startMinutes;
  int moveMinutes;
  bool enabled;

  BreakPeriod({
    required this.startMinutes,
    required this.moveMinutes,
    this.enabled = true,
  });

  int get endMinutes => (startMinutes + moveMinutes).clamp(0, 24 * 60);

  Map<String, dynamic> toJson() =>
      {'s': startMinutes, 'm': moveMinutes, 'e': enabled};

  factory BreakPeriod.fromJson(Map<String, dynamic> j) => BreakPeriod(
        startMinutes: (j['s'] as num?)?.toInt() ?? 0,
        moveMinutes: (j['m'] as num?)?.toInt() ?? 5,
        enabled: j['e'] as bool? ?? true,
      );
}

/// حالة التطبيق: إعداد الفترات ورمز التخطّي، ومنطق تحديد الفترة الفعّالة الآن.
class BreakService extends ChangeNotifier {
  BreakService._();
  static final BreakService instance = BreakService._();

  static const _kEnabled = 'hr_enabled';
  static const _kPeriods = 'hr_periods';
  static const _kCode = 'hr_bypass_code';
  static const _kDone = 'hr_done_keys';

  bool _enabled = true;
  List<BreakPeriod> _periods = [];
  String _bypassCode = '';
  Set<String> _doneKeys = {};

  bool get enabled => _enabled;
  List<BreakPeriod> get periods => List.unmodifiable(_periods);
  String get bypassCode => _bypassCode;
  bool get hasBypassCode => _bypassCode.trim().isNotEmpty;

  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _enabled = sp.getBool(_kEnabled) ?? true;
      _bypassCode = sp.getString(_kCode) ?? '';
      final raw = sp.getString(_kPeriods);
      if (raw != null && raw.isNotEmpty) {
        _periods = (jsonDecode(raw) as List)
            .map((e) => BreakPeriod.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      } else {
        _periods = _defaults();
      }
      final today = _dayKey();
      _doneKeys = (sp.getStringList(_kDone) ?? const [])
          .where((k) => k.startsWith('$today-'))
          .toSet();
    } catch (_) {
      _periods = _defaults();
    }
    notifyListeners();
  }

  List<BreakPeriod> _defaults() => [
        BreakPeriod(startMinutes: 11 * 60, moveMinutes: 5),
        BreakPeriod(startMinutes: 14 * 60, moveMinutes: 5),
        BreakPeriod(startMinutes: 17 * 60, moveMinutes: 5),
      ];

  Future<void> save({
    bool? enabled,
    List<BreakPeriod>? periods,
    String? bypassCode,
  }) async {
    if (enabled != null) _enabled = enabled;
    if (periods != null) _periods = periods.take(3).toList();
    if (bypassCode != null) _bypassCode = bypassCode.trim();
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kEnabled, _enabled);
    await sp.setString(
        _kPeriods, jsonEncode(_periods.map((p) => p.toJson()).toList()));
    await sp.setString(_kCode, _bypassCode);
    notifyListeners();
  }

  String _dayKey([DateTime? d]) {
    final n = d ?? DateTime.now();
    return '${n.year}${n.month.toString().padLeft(2, '0')}${n.day.toString().padLeft(2, '0')}';
  }

  DateTime _todayAt(int minutes) {
    final n = DateTime.now();
    return DateTime(n.year, n.month, n.day).add(Duration(minutes: minutes));
  }

  bool _isDone(int index) => _doneKeys.contains('${_dayKey()}-$index');

  Future<void> markDone(int index) async {
    _doneKeys.add('${_dayKey()}-$index');
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(_kDone, _doneKeys.toList());
    } catch (_) {}
  }

  /// الفترة الفعّالة الآن مع وقت انتهائها — أو null.
  ({int index, DateTime end})? activeBreakNow() {
    if (!_enabled) return null;
    final now = DateTime.now();
    for (var i = 0; i < _periods.length; i++) {
      final p = _periods[i];
      if (!p.enabled || p.moveMinutes <= 0) continue;
      final start = _todayAt(p.startMinutes);
      final end = start.add(Duration(minutes: p.moveMinutes));
      if (now.isAfter(start) && now.isBefore(end) && !_isDone(i)) {
        return (index: i, end: end);
      }
    }
    return null;
  }

  /// موعد أقرب فترة قادمة اليوم/غدًا (للعرض في الرئيسية).
  DateTime? nextStart() {
    if (!_enabled) return null;
    final now = DateTime.now();
    DateTime? best;
    for (final p in _periods) {
      if (!p.enabled) continue;
      var start = _todayAt(p.startMinutes);
      if (!start.isAfter(now)) start = start.add(const Duration(days: 1));
      if (best == null || start.isBefore(best)) best = start;
    }
    return best;
  }

  bool checkCode(String input) =>
      hasBypassCode && input.trim() == _bypassCode.trim();
}
