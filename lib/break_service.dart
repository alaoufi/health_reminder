import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// فترة عمل: نافذة زمنية [start..end] يتخلّلها **راحات متكرّرة**: بعد كل
/// [workMinutes] عملٍ متواصل، راحة/حركة مدّتها [restMinutes].
///
/// مثال: من ٤م إلى ١١م، عمل ٦٠ د، راحة ٥ د ⇒ راحة كل ساعة داخل النافذة.
class BreakPeriod {
  int startMinutes; // بداية النافذة (دقائق من منتصف الليل)
  int endMinutes; // نهاية النافذة
  int workMinutes; // مدّة العمل المتواصل قبل كل راحة
  int restMinutes; // مدّة الراحة (الحركة)
  bool enabled;

  BreakPeriod({
    required this.startMinutes,
    required this.endMinutes,
    required this.workMinutes,
    required this.restMinutes,
    this.enabled = true,
  });

  /// أوقات بدء الراحات (دقائق من منتصف الليل) المكتملة داخل النافذة.
  List<int> restStarts() {
    final out = <int>[];
    if (workMinutes <= 0 || restMinutes <= 0 || endMinutes <= startMinutes) {
      return out;
    }
    var t = startMinutes + workMinutes; // أوّل راحة بعد أوّل مدّة عمل
    var guard = 0;
    while (t + restMinutes <= endMinutes && guard < 200) {
      out.add(t);
      t += restMinutes + workMinutes;
      guard++;
    }
    return out;
  }

  Map<String, dynamic> toJson() => {
        'st': startMinutes,
        'en': endMinutes,
        'w': workMinutes,
        'r': restMinutes,
        'e': enabled,
      };

  factory BreakPeriod.fromJson(Map<String, dynamic> j) => BreakPeriod(
        startMinutes: (j['st'] as num?)?.toInt() ?? 16 * 60,
        endMinutes: (j['en'] as num?)?.toInt() ?? 23 * 60,
        workMinutes: (j['w'] as num?)?.toInt() ?? 60,
        restMinutes: (j['r'] as num?)?.toInt() ?? 5,
        enabled: j['e'] as bool? ?? true,
      );
}

/// حالة التطبيق: فترات العمل ورمز التخطّي، ومنطق تحديد الراحة الفعّالة الآن.
class BreakService extends ChangeNotifier {
  BreakService._();
  static final BreakService instance = BreakService._();

  static const _kEnabled = 'hr_enabled';
  static const _kPeriods = 'hr_periods2'; // مفتاح جديد (نموذج نافذة+راحات)
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
        BreakPeriod(
            startMinutes: 16 * 60, // ٤ م
            endMinutes: 23 * 60, // ١١ م
            workMinutes: 60,
            restMinutes: 5),
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

  bool _isDone(int index, int restStart) =>
      _doneKeys.contains('${_dayKey()}-$index-$restStart');

  /// يُعلّم راحةً بعينها (فترة + وقت بدء) منجَزةً فلا تتكرّر اليوم.
  Future<void> markDone(int index, int restStart) async {
    _doneKeys.add('${_dayKey()}-$index-$restStart');
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList(_kDone, _doneKeys.toList());
    } catch (_) {}
  }

  /// الراحة الفعّالة الآن (إن وُجدت): الفترة + وقت البدء + وقت الانتهاء.
  ({int index, int restStart, DateTime end})? activeBreakNow() {
    if (!_enabled) return null;
    final now = DateTime.now();
    for (var i = 0; i < _periods.length; i++) {
      final p = _periods[i];
      if (!p.enabled) continue;
      for (final rs in p.restStarts()) {
        final start = _todayAt(rs);
        final end = start.add(Duration(minutes: p.restMinutes));
        if (now.isAfter(start) && now.isBefore(end) && !_isDone(i, rs)) {
          return (index: i, restStart: rs, end: end);
        }
      }
    }
    return null;
  }

  /// يخزّن وقت انتهاء الراحة لنافذة القفل، ويُعلّمها منجَزةً.
  ///
  /// نخزّن أيضًا **مدّة الراحة بالدقائق** كخطّ أمان: إن تعذّر على عزلة النافذة
  /// قراءة وقت الانتهاء، تحسب نهاية بديلة من هذه المدّة بدل أن تبقى بلا نهاية
  /// (وهو ما كان يحبس الجهاز بلا عدّاد).
  Future<void> beginOverlay(int index, int restStart, DateTime end) async {
    try {
      final sp = await SharedPreferences.getInstance();
      var mins = end.difference(DateTime.now()).inMinutes;
      if (mins < 1) mins = 1; // حدّ أدنى
      if (mins > 30) mins = 30; // سقف أمان
      await sp.setInt('hr_active_end', end.millisecondsSinceEpoch);
      await sp.setInt('hr_active_minutes', mins);
    } catch (_) {}
    await markDone(index, restStart);
  }

  /// موعد أقرب راحة قادمة (اليوم أو غدًا) — للعرض في الرئيسية.
  DateTime? nextStart() {
    if (!_enabled) return null;
    final now = DateTime.now();
    DateTime? best;
    for (final p in _periods) {
      if (!p.enabled) continue;
      for (final rs in p.restStarts()) {
        var t = _todayAt(rs);
        if (!t.isAfter(now)) t = t.add(const Duration(days: 1));
        if (best == null || t.isBefore(best)) best = t;
      }
    }
    return best;
  }

  /// كل أوقات بدء الراحات (لكل الفترات المفعّلة) — لجدولة الإشعارات.
  List<int> allRestStarts() {
    final out = <int>[];
    for (final p in _periods) {
      if (p.enabled) out.addAll(p.restStarts());
    }
    return out;
  }

  bool checkCode(String input) =>
      hasBypassCode && input.trim() == _bypassCode.trim();
}
