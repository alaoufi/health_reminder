import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'break_service.dart';
import 'home_screen.dart';
import 'notify_service.dart';
import 'overlay_break.dart';

/// نقطة دخول نافذة القفل (تُرسَم فوق كل التطبيقات) — يشغّلها flutter_overlay_window.
@pragma('vm:entry-point')
void overlayMain() {
  runApp(const MaterialApp(
    debugShowCheckedModeBanner: false,
    home: Scaffold(
      backgroundColor: Colors.transparent,
      body: OverlayBreak(),
    ),
  ));
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BreakService.instance.load();
  // تهيئة الإشعارات وجدولتها (لا تُعطّل الإقلاع إن فشلت).
  try {
    await NotifyService.instance.init();
    await NotifyService.instance.rescheduleAll();
  } catch (_) {}
  runApp(const HealthReminderApp());
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
      home: const HomeScreen(),
    );
  }
}
