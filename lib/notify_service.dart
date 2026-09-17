import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'break_alarm.dart';

/// إشعارات محلية صامتة بملء الشاشة عند حلول كل فترة — تُنبّه حتى إن كان التطبيق
/// مغلقًا؛ فتحه يعرض شاشة الحركة. بلا صوت وبلا اهتزاز.
class NotifyService {
  NotifyService._();
  static final NotifyService instance = NotifyService._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    try {
      tzdata.initializeTimeZones();
      // المنطقة الزمنية لمكّة/الرياض (UTC+3 بلا توقيت صيفيّ) — مناسبة للمستخدم.
      tz.setLocalLocation(tz.getLocation('Asia/Riyadh'));
    } catch (_) {
      try {
        tz.setLocalLocation(tz.getLocation('UTC'));
      } catch (_) {}
    }
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
        const InitializationSettings(android: android));
    final impl = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    try {
      await impl?.requestNotificationsPermission();
      await impl?.requestExactAlarmsPermission();
    } catch (_) {}
    _ready = true;
  }

  /// المُشغّل الموثوق الآن هو منبّه `setAlarmClock` الأصليّ (يُجدوَل من الرئيسية
  /// عبر القناة الأصليّة). هنا **نُلغي** المسارات القديمة (منبّهات
  /// android_alarm_manager وإشعارات الجدولة) لتفادي التعارض وازدواج الإشعارات مع
  /// المسار الجديد.
  Future<void> rescheduleAll() async {
    try {
      await BreakAlarm.cancelAll();
    } catch (_) {}
    try {
      if (!_ready) await init();
      await _plugin.cancelAll();
    } catch (e) {
      debugPrint('cancel old schedules failed: $e');
    }
  }

  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}
