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
  static const _kShowPhrases = 'hr_show_phrases'; // عرض العبارات أم شاشة صامتة
  static const _kIdleReset = 'hr_idle_reset'; // عتبة الخمول (دقائق) لاعتباره راحة
  static const _kAnchor = 'hr_anchor'; // مرساة الدورة: بداية شوط العمل الحاليّ

  bool _enabled = true;
  List<BreakPeriod> _periods = [];
  String _bypassCode = '';
  Set<String> _doneKeys = {};
  DateTime? _anchor; // آخر بداية شوط عمل — الراحة القادمة = المرساة + مدّة العمل
  bool _showPhrases = true; // true: عبارات تحفيزية، false: شاشة صامتة بعدّاد فقط
  int _idleResetMinutes = 15; // خمول ≥ هذه المدّة (بإطفاء الشاشة) يُصفّر عدّاد العمل
  bool _wasFresh = false; // true إن لم تكن هناك إعدادات محفوظة عند التحميل (تثبيت جديد)

  bool get enabled => _enabled;
  /// هل هذا تثبيت جديد بلا إعدادات محفوظة؟ (لمحاولة الاستعادة من ملفّ الجهاز)
  bool get wasFreshInstall => _wasFresh;
  List<BreakPeriod> get periods => List.unmodifiable(_periods);
  String get bypassCode => _bypassCode;
  bool get hasBypassCode => _bypassCode.trim().isNotEmpty;
  bool get showPhrases => _showPhrases;
  int get idleResetMinutes => _idleResetMinutes;

  Future<void> load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      _enabled = sp.getBool(_kEnabled) ?? true;
      _bypassCode = sp.getString(_kCode) ?? '';
      _showPhrases = sp.getBool(_kShowPhrases) ?? true;
      _idleResetMinutes = sp.getInt(_kIdleReset) ?? 15;
      final raw = sp.getString(_kPeriods);
      if (raw != null && raw.isNotEmpty) {
        _wasFresh = false;
        _periods = (jsonDecode(raw) as List)
            .map((e) => BreakPeriod.fromJson((e as Map).cast<String, dynamic>()))
            .toList();
      } else {
        _wasFresh = true; // لا إعدادات محفوظة ⇒ تثبيت جديد (حاول الاستعادة).
        _periods = _defaults();
      }
      final am = sp.getInt(_kAnchor);
      _anchor = am != null ? DateTime.fromMillisecondsSinceEpoch(am) : null;
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
            startMinutes: 0, // طوال اليوم افتراضيًّا (يعمل في أي وقت)
            endMinutes: 24 * 60 - 1, // ٢٣:٥٩
            workMinutes: 60,
            restMinutes: 5),
      ];

  Future<void> save({
    bool? enabled,
    List<BreakPeriod>? periods,
    String? bypassCode,
    bool? showPhrases,
    int? idleResetMinutes,
  }) async {
    if (enabled != null) _enabled = enabled;
    if (periods != null) _periods = periods.take(3).toList();
    if (bypassCode != null) _bypassCode = bypassCode.trim();
    if (showPhrases != null) _showPhrases = showPhrases;
    if (idleResetMinutes != null) {
      _idleResetMinutes = idleResetMinutes.clamp(1, 120);
    }
    // أعِد ضبط المرساة على «الآن» عند أي حفظ للإعدادات وهي مفعّلة — فتصبح الراحة
    // القادمة = الآن + مدّة العمل (يبدأ العدّ من لحظة الحفظ لا من بداية النافذة).
    _anchor = _enabled ? DateTime.now() : null;
    final sp = await SharedPreferences.getInstance();
    await sp.setBool(_kEnabled, _enabled);
    await sp.setString(
        _kPeriods, jsonEncode(_periods.map((p) => p.toJson()).toList()));
    await sp.setString(_kCode, _bypassCode);
    await sp.setBool(_kShowPhrases, _showPhrases);
    await sp.setInt(_kIdleReset, _idleResetMinutes);
    if (_anchor != null) {
      await sp.setInt(_kAnchor, _anchor!.millisecondsSinceEpoch);
    } else {
      await sp.remove(_kAnchor);
    }
    notifyListeners();
  }

  /// يضبط المرساة (بداية شوط العمل) ويحفظها — يُستدعى عند بدء الراحة (نهايتها تصبح
  /// المرساة الجديدة) فتتدحرج الدورة: الراحة التالية = نهاية هذه الراحة + مدّة العمل.
  Future<void> setAnchor(DateTime t) async {
    _anchor = t;
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setInt(_kAnchor, t.millisecondsSinceEpoch);
    } catch (_) {}
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

  /// نافذة الفترة المحيطة بـ [now] كـ (بداية، نهاية) — **تدعم عبور منتصف الليل**
  /// (مثل ١٠:٠٠→٠٢:٠٠). تعيد null إن كان «الآن» خارج النافذة.
  ({DateTime ws, DateTime we})? _windowAround(BreakPeriod p, DateTime now) {
    final base = DateTime(now.year, now.month, now.day);
    final s = p.startMinutes, e = p.endMinutes;
    if (s <= e) {
      // نافذة داخل اليوم نفسه.
      final ws = base.add(Duration(minutes: s));
      final we = base.add(Duration(minutes: e));
      if (!now.isBefore(ws) && now.isBefore(we)) return (ws: ws, we: we);
      return null;
    }
    // تعبر منتصف الليل: [start..24:00) ثمّ [00:00..end).
    final nowMin = now.hour * 60 + now.minute;
    if (nowMin >= s) {
      // في الجزء المسائيّ — تنتهي غدًا.
      final ws = base.add(Duration(minutes: s));
      final we = base.add(const Duration(days: 1)).add(Duration(minutes: e));
      return (ws: ws, we: we);
    }
    if (nowMin < e) {
      // في جزء ما بعد منتصف الليل — بدأت أمس.
      final ws =
          base.subtract(const Duration(days: 1)).add(Duration(minutes: s));
      final we = base.add(Duration(minutes: e));
      return (ws: ws, we: we);
    }
    return null;
  }

  /// أقرب بداية نافذة قادمة للفترة (بعد [now]) — لوقت بدء الفترة (لا يعبر منتصف الليل هنا).
  DateTime _nextWindowStart(BreakPeriod p, DateTime now) {
    final base = DateTime(now.year, now.month, now.day);
    var ws = base.add(Duration(minutes: p.startMinutes));
    if (!ws.isAfter(now)) ws = ws.add(const Duration(days: 1));
    return ws;
  }

  /// الراحة القادمة (وقت البدء + مدّة الراحة) بنموذج **التدحرج من الآن**:
  /// داخل نافذة نشطة ⇒ المرساة + مدّة العمل؛ خارجها ⇒ أقرب بداية نافذة + مدّة العمل.
  ({DateTime start, int rest})? _nextBreak() {
    if (!_enabled) return null;
    final now = DateTime.now();
    final anchor = _anchor ?? now;
    for (final p in _periods) {
      if (!p.enabled) continue;
      final w = _windowAround(p, now);
      if (w == null) continue;
      var nb = anchor.add(Duration(minutes: p.workMinutes));
      if (nb.isBefore(w.ws)) nb = w.ws.add(Duration(minutes: p.workMinutes));
      // فات تمامًا (تجاوز نهاية الراحة) ⇒ ابدأ دورة جديدة من الآن.
      if (!nb.add(Duration(minutes: p.restMinutes)).isAfter(now)) {
        nb = now.add(Duration(minutes: p.workMinutes));
      }
      if (nb.isBefore(w.we)) return (start: nb, rest: p.restMinutes);
    }
    // خارج النوافذ: أقرب بداية فترة قادمة + مدّة العمل.
    DateTime? best;
    int bestRest = 5;
    for (final p in _periods) {
      if (!p.enabled) continue;
      final ws = _nextWindowStart(p, now);
      final cand = ws.add(Duration(minutes: p.workMinutes));
      if (best == null || cand.isBefore(best)) {
        best = cand;
        bestRest = p.restMinutes;
      }
    }
    if (best == null) return null;
    return (start: best, rest: bestRest);
  }

  /// الراحة الفعّالة الآن (إن حان وقتها ولم تنتهِ بعد).
  ({int index, int restStart, DateTime end})? activeBreakNow() {
    final nb = _nextBreak();
    if (nb == null) return null;
    final now = DateTime.now();
    final end = nb.start.add(Duration(minutes: nb.rest));
    if (!now.isBefore(nb.start) && now.isBefore(end)) {
      return (index: 0, restStart: 0, end: end);
    }
    return null;
  }

  /// عند بدء الراحة: تصبح نهايتها المرساةَ الجديدة فتتدحرج الدورة؛ ويُخزَّن وقت
  /// الانتهاء (خطّ أمان لعرض القفل).
  Future<void> beginOverlay(int index, int restStart, DateTime end) async {
    await setAnchor(end); // الراحة التالية = نهاية هذه الراحة + مدّة العمل
    try {
      final sp = await SharedPreferences.getInstance();
      var mins = end.difference(DateTime.now()).inMinutes;
      if (mins < 1) mins = 1;
      if (mins > 30) mins = 30;
      await sp.setInt('hr_active_end', end.millisecondsSinceEpoch);
      await sp.setInt('hr_active_minutes', mins);
    } catch (_) {}
  }

  /// موعد الراحة القادمة — للعرض في الرئيسية وجدولة المنبّه.
  DateTime? nextStart() => _nextBreak()?.start;

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

  /// نسخة احتياطية: يصدّر كل الإعدادات كنصّ JSON (للنسخ ثم اللصق لاحقًا).
  String exportJson() => jsonEncode({
        'v': 1,
        'enabled': _enabled,
        'showPhrases': _showPhrases,
        'idleResetMinutes': _idleResetMinutes,
        'bypassCode': _bypassCode,
        'periods': _periods.map((p) => p.toJson()).toList(),
      });

  /// استيراد نسخة احتياطية من نصّ JSON. يعيد true عند النجاح.
  Future<bool> importJson(String raw) async {
    try {
      final j = (jsonDecode(raw.trim()) as Map).cast<String, dynamic>();
      final periods = (j['periods'] as List?)
          ?.map((e) => BreakPeriod.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      await save(
        enabled: j['enabled'] as bool?,
        showPhrases: j['showPhrases'] as bool?,
        idleResetMinutes: (j['idleResetMinutes'] as num?)?.toInt(),
        bypassCode: j['bypassCode'] as String?,
        periods: periods,
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
