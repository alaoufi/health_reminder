import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'break_service.dart';

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

  static const _channel = AndroidNotificationDetails(
    'break_channel',
    'تنبيه كسر الجلوس',
    channelDescription: 'تنبيه صامت بملء الشاشة عند حلول وقت الحركة',
    importance: Importance.max,
    priority: Priority.high,
    playSound: false,
    enableVibration: false,
    fullScreenIntent: true,
    category: AndroidNotificationCategory.reminder,
  );

  tz.TZDateTime _nextInstance(int minutes) {
    final now = tz.TZDateTime.now(tz.local);
    var t = tz.TZDateTime(
        tz.local, now.year, now.month, now.day, minutes ~/ 60, minutes % 60);
    if (!t.isAfter(now)) t = t.add(const Duration(days: 1));
    return t;
  }

  /// يُعيد جدولة كل الفترات المفعّلة (تلغى القديمة أولًا).
  Future<void> rescheduleAll() async {
    if (!_ready) await init();
    try {
      await _plugin.cancelAll();
      final svc = BreakService.instance;
      if (!svc.enabled) return;
      final periods = svc.periods;
      for (var i = 0; i < periods.length; i++) {
        final p = periods[i];
        if (!p.enabled) continue;
        await _plugin.zonedSchedule(
          100 + i,
          'حان وقت الحركة 🧘',
          'قِف وتحرّك بهدوء دقائق — صحّتك أهمّ. افتح التطبيق للبدء.',
          _nextInstance(p.startMinutes),
          const NotificationDetails(android: _channel),
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
          matchDateTimeComponents: DateTimeComponents.time, // يوميًّا
        );
      }
    } catch (e) {
      debugPrint('rescheduleAll failed: $e');
    }
  }

  Future<void> cancelAll() async {
    try {
      await _plugin.cancelAll();
    } catch (_) {}
  }
}
