import 'dart:async';
import 'dart:ui';

import 'package:android_alarm_manager_plus/android_alarm_manager_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'break_service.dart';
import 'features/update/force_update_gate.dart';
import 'home_screen.dart';
import 'overlay_break.dart';

/// أخطاء الإقلاع — تُعرض للمستخدم بدل الانهيار الصامت.
final List<String> startupErrors = [];

/// نقطة دخول نافذة القفل (تُرسَم فوق كل التطبيقات) — يشغّلها flutter_overlay_window.
///
/// مهمّ: عزلة النافذة منفصلة، فيجب تهيئة الربط وتسجيل الإضافات فيها؛ وإلّا تتعلّق
/// نداءات الإضافات (SharedPreferences/closeOverlay) بلا نهاية فتتجمّد الشاشة على
/// 00:00 بلا إغلاق (السبب الجذريّ للتجمّد الذي أجبر على إعادة تشغيل الجهاز).
@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    DartPluginRegistrant.ensureInitialized();
  } catch (_) {}
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: Colors.black,
      body: OverlayBreak(),
    ),
  ));
}

Future<void> _safe(String name, Future<void> Function() step) async {
  try {
    await step();
  } catch (e) {
    startupErrors.add('$name: $e');
  }
}

Future<void> main() async {
  var started = false;
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();

    // بدل شاشة رمادية عند فشل بناء أي واجهة، نعرض نصّ الخطأ ليُصوَّر.
    ErrorWidget.builder = (details) => Directionality(
          textDirection: TextDirection.rtl,
          child: Material(
            color: Colors.white,
            child: SafeArea(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('⚠️ خطأ — صوّر هذه الرسالة وأرسلها:',
                        style: TextStyle(
                            color: Colors.red, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    SelectableText('${details.exception}',
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            ),
          ),
        );
    FlutterError.onError = (d) => startupErrors.add('Flutter: ${d.exceptionAsString()}');

    await _safe('settings', () => BreakService.instance.load());
    // نظّف علم «استراحة نشطة» عند الإقلاع (قد يكون عالقًا من جلسة قُتلت) كي لا
    // تتوقّف الخدمة عن الجدولة؛ تُعيده شاشة الاستراحة لو ظهرت.
    await _safe('breakflag', () => BreakService.instance.setBreakActiveFlag(false));
    // مدير المنبّهات الخلفيّة الدقيقة (لعرض القفل في وقت الراحة حتى لو التطبيق مغلق).
    await _safe('alarm', () => AndroidAlarmManager.initialize());
    // ملاحظة: تهيئة الإشعارات مؤجَّلة إلى ما بعد ظهور الواجهة (في HomeScreen) كي لا
    // تُعطّل الإقلاع أو تُخفي سببه إن فشلت.
    runApp(const HealthReminderApp());
    started = true;
  }, (e, st) {
    startupErrors.add('Uncaught: $e');
    if (!started) runApp(_ErrorApp(message: '$e\n\n$st'));
  });
}

class _ErrorApp extends StatelessWidget {
  final String message;
  const _ErrorApp({required this.message});
  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            appBar: AppBar(title: const Text('تعذّر بدء التطبيق')),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(message,
                  style: const TextStyle(fontSize: 12)),
            ),
          ),
        ),
      );
}

class HealthReminderApp extends StatelessWidget {
  const HealthReminderApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF11998E),
      brightness: Brightness.light,
    );
    return MaterialApp(
      title: 'لا تجلس طويلًا',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar'), Locale('en')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      builder: (context, child) => Directionality(
        textDirection: TextDirection.rtl,
        child: child ?? const SizedBox.shrink(),
      ),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: scheme,
        appBarTheme: AppBarTheme(
          backgroundColor: scheme.primary,
          foregroundColor: Colors.white,
          centerTitle: true,
        ),
      ),
      home: const ForceUpdateGate(child: HomeScreen()),
    );
  }
}
