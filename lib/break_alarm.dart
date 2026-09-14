import 'dart:ui';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'break_service.dart';

/// منبّه خلفيّ **دقيق** يعرض نافذة الحركة فوق كل التطبيقات في وقت الراحة بالضبط —
/// حتى إن كان التطبيق مغلقًا أو المستخدم في تطبيق آخر (لا يعتمد على فتح التطبيق).
/// يكمّل المسارين الآخرين (الإشعار + الفحص داخل التطبيق) كمُشغّل أساسيّ للقفل القسريّ.
class BreakAlarm {
  BreakAlarm._();

  static const int _base = 700000; // نطاق معرّفات ثابت لمنبّهات الراحة.
  static const int _closeId = 690001; // معرّف منبّه إغلاق النافذة (طبقة أمان).
  static int _idFor(int periodIndex, int restStart) =>
      _base + periodIndex * 2000 + restStart; // restStart < 1440 < 2000

  /// يجدول منبّهًا لمرّة واحدة عند [end] يُغلق النافذة العائمة من عزلة مستقلّة —
  /// طبقة أمان: تُغلق الشاشة حتى لو تجمّدت عزلة النافذة نفسها (فلا حاجة لإعادة
  /// تشغيل الجهاز إطلاقًا). يُلغى القديم أولًا.
  static Future<void> scheduleClose(DateTime end) async {
    try {
      await AndroidAlarmManager.cancel(_closeId);
    } catch (_) {}
    // سقف أمان: لا يتجاوز الإغلاق ٣١ دقيقة مهما فسدت البيانات.
    var when = end;
    final cap = DateTime.now().add(const Duration(minutes: 31));
    if (when.isAfter(cap)) when = cap;
    if (!when.isAfter(DateTime.now())) {
      when = DateTime.now().add(const Duration(seconds: 2));
    }
    try {
      await AndroidAlarmManager.oneShotAt(
        when,
        _closeId,
        breakCloseFire,
        exact: true,
        wakeup: true,
        allowWhileIdle: true,
        rescheduleOnReboot: false,
      );
    } catch (_) {}
  }

  /// يجدول منبّهًا يوميًّا دقيقًا لكل بداية راحة مفعّلة (يلغي القديمة أولًا).
  static Future<void> rescheduleAll() async {
    await _cancelKnown();
    final svc = BreakService.instance;
    if (!svc.enabled) {
      await _saveKnown(const []);
      return;
    }
    final now = DateTime.now();
    final periods = svc.periods;
    final scheduled = <int>[];
    for (var pi = 0; pi < periods.length; pi++) {
      final p = periods[pi];
      if (!p.enabled) continue;
      for (final rs in p.restStarts()) {
        final id = _idFor(pi, rs);
        var when = DateTime(now.year, now.month, now.day, rs ~/ 60, rs % 60);
        if (!when.isAfter(now)) when = when.add(const Duration(days: 1));
        try {
          await AndroidAlarmManager.periodic(
            const Duration(days: 1),
            id,
            breakAlarmFire,
            startAt: when,
            exact: true,
            wakeup: true,
            allowWhileIdle: true,
            rescheduleOnReboot: true,
          );
          scheduled.add(id);
        } catch (_) {/* لا تُعطّل التطبيق إن تعذّرت الجدولة */}
      }
    }
    await _saveKnown(scheduled);
  }

  static Future<void> _cancelKnown() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final ids = sp.getStringList('hr_alarm_ids') ?? const [];
      for (final s in ids) {
        final id = int.tryParse(s);
        if (id != null) {
          try {
            await AndroidAlarmManager.cancel(id);
          } catch (_) {}
        }
      }
    } catch (_) {}
  }

  static Future<void> _saveKnown(List<int> ids) async {
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setStringList('hr_alarm_ids', ids.map((e) => '$e').toList());
    } catch (_) {}
  }

  static Future<void> cancelAll() async {
    await _cancelKnown();
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove('hr_alarm_ids');
    } catch (_) {}
  }
}

/// يُنفَّذ في **عزلة خلفيّة** عند حلول وقت الراحة — يعرض النافذة فوق كل التطبيقات.
@pragma('vm:entry-point')
Future<void> breakAlarmFire() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized(); // تسجيل الإضافات في عزلة الخلفية.
  try {
    final svc = BreakService.instance;
    await svc.load();
    final b = svc.activeBreakNow(); // الراحة الواقعة الآن (المنبّه يفتح في بدايتها).
    if (b == null) return;

    final sp = await SharedPreferences.getInstance();
    var mins = b.end.difference(DateTime.now()).inMinutes;
    if (mins < 1) mins = 1;
    if (mins > 30) mins = 30;
    await sp.setInt('hr_active_end', b.end.millisecondsSinceEpoch);
    await sp.setInt('hr_active_minutes', mins);
    await svc.markDone(b.index, b.restStart); // يمنع تكرار الفتح لنفس الراحة.

    final granted = await FlutterOverlayWindow.isPermissionGranted();
    final active = await FlutterOverlayWindow.isActive();
    if (granted && !active) {
      await FlutterOverlayWindow.showOverlay(
        height: WindowSize.fullCover,
        width: WindowSize.matchParent,
        alignment: OverlayAlignment.center,
        flag: OverlayFlag.focusPointer,
        overlayTitle: 'لا تجلس طويلًا',
        enableDrag: false,
      );
      // طبقة أمان: جدولة إغلاق مستقلّ عند نهاية الراحة (لا اعتماد على عزلة النافذة).
      await BreakAlarm.scheduleClose(b.end);
    }
  } catch (_) {/* لا شيء — لا نُسقط التطبيق من عزلة الخلفية */}
}

/// يُنفَّذ في عزلة مستقلّة عند نهاية الراحة — يُغلق النافذة العائمة ويُنظّف
/// علامات النشاط. طبقة الأمان التي تمنع بقاء الشاشة عالقةً بلا إغلاق.
@pragma('vm:entry-point')
Future<void> breakCloseFire() async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  try {
    if (await FlutterOverlayWindow.isActive()) {
      await FlutterOverlayWindow.closeOverlay();
    }
  } catch (_) {}
  try {
    final sp = await SharedPreferences.getInstance();
    await sp.remove('hr_active_end');
    await sp.remove('hr_active_minutes');
  } catch (_) {}
}
