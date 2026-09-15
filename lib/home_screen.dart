import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'backup_service.dart';
import 'break_screen.dart';
import 'break_service.dart';
import 'notify_service.dart';
import 'settings_screen.dart';

/// الواجهة الرئيسية: حالة التفعيل، الفترة القادمة، ملخّص الفترات، وزرّ تجربة.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  Timer? _timer;
  int _tick = 0; // عدّاد الثواني (لتحديث العدّاد الحيّ وفحص الراحة كلّ ٢٠ ثانية)
  bool _breakShowing = false;
  bool _starting = false;
  bool _battOk = true; // هل سُمح بتجاوز توفير البطارية؟ (لعمل المنبّه والجهاز مغلق)
  bool _overlayPerm = true; // «العرض فوق التطبيقات» — يمنح فتح الشاشة فوق أي تطبيق
  bool _fsiOk = true; // إذن إشعارات ملء الشاشة (أندرويد 14+) — لِتقتحم لا تكتفي بإشعار
  bool _autostartDone = false; // أخفى المستخدم بطاقة التشغيل التلقائيّ (لا يمكن كشفها آليًّا)

  /// قناة أصليّة لإرسال التطبيق إلى الخلفية (العودة للتطبيق السابق).
  static const _platform =
      MethodChannel('com.alaoufi.health_reminder/installer');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPerm();
    _loadAutostartFlag();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // تثبيت جديد؟ حاول استعادة الإعدادات من الملفّ المخفيّ بذاكرة الجهاز.
      await _restoreIfFresh();
      // تهيئة الإشعارات وجدولتها بعد ظهور الواجهة (لا تُعطّل الإقلاع إن فشلت).
      try {
        await NotifyService.instance.init();
        await NotifyService.instance.rescheduleAll();
      } catch (_) {}
      await _scheduleNativeBreak(); // المنبّه الدقيق (setAlarmClock) — الأوثق.
      _check();
    });
    // عدّاد حيّ كلّ ثانية لتحديث «راحتك القادمة بعد MM:SS»؛ وفحص الراحة كلّ ٢٠ ثانية.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
      _tick++;
      if (_tick % 20 == 0) _check();
    });
  }

  /// يجدول منبّه الراحة القادمة عبر القناة الأصليّة (setAlarmClock) — أوثق طريقة
  /// للظهور في الوقت بالضبط والتطبيق مغلق (يحترمها MIUI ومعفاة من توفير الطاقة).
  Future<void> _scheduleNativeBreak() async {
    try {
      final svc = BreakService.instance;
      await svc.writeNativeState(); // حالة الجدولة للخدمة الأماميّة.
      final n = svc.nextStart();
      if (!svc.enabled || n == null) {
        await _platform.invokeMethod('cancelExactBreak');
        await _platform.invokeMethod('stopBreakService');
      } else {
        await _platform.invokeMethod(
            'scheduleExactBreak', {'epoch': n.millisecondsSinceEpoch});
        // خدمة أماميّة تُبقي العمليّة حيّة فتظهر الاستراحة حتى أثناء استخدام الجوال.
        await _platform.invokeMethod('startBreakService');
      }
    } catch (_) {}
  }

  Future<void> _refreshPerm() async {
    try {
      final b =
          await _platform.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      if (mounted) setState(() => _battOk = b ?? true);
    } catch (_) {}
    try {
      final p = await FlutterOverlayWindow.isPermissionGranted();
      if (mounted) setState(() => _overlayPerm = p);
    } catch (_) {}
    try {
      final f = await _platform.invokeMethod<bool>('hasFullScreenIntent');
      if (mounted) setState(() => _fsiOk = f ?? true);
    } catch (_) {}
  }

  Future<void> _requestOverlayPerm() async {
    try {
      await FlutterOverlayWindow.requestPermission();
    } catch (_) {}
    await _refreshPerm();
  }

  Future<void> _requestFsi() async {
    try {
      await _platform.invokeMethod('requestFullScreenIntent');
    } catch (_) {}
    await _refreshPerm();
  }

  Future<void> _loadAutostartFlag() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final v = sp.getBool('hr_autostart_done') ?? false;
      if (mounted) setState(() => _autostartDone = v);
    } catch (_) {}
  }

  Future<void> _setAutostartDone(bool v) async {
    setState(() => _autostartDone = v);
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.setBool('hr_autostart_done', v);
    } catch (_) {}
  }

  Future<void> _requestBattery() async {
    try {
      await _platform.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {}
    await _refreshPerm();
  }

  Future<void> _openAutostart() async {
    try {
      await _platform.invokeMethod('openAutostartSettings');
    } catch (_) {}
  }

  /// عند التثبيت الجديد: إن وُجد ملفّ نسخة احتياطية بذاكرة الجهاز، استعِد منه
  /// الإعدادات تلقائيًّا (فلا تُفقد بعد الحذف وإعادة التثبيت).
  Future<void> _restoreIfFresh() async {
    if (!BreakService.instance.wasFreshInstall) return;
    try {
      final raw = await BackupService.read();
      if (raw != null && raw.trim().isNotEmpty) {
        final ok = await BreakService.instance.importJson(raw);
        if (ok && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
              content: Text('استُعيدت إعداداتك المحفوظة على الجهاز ✅')));
          setState(() {});
        }
      }
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPerm();
      // أعِد قراءة المرساة (قد تكون الخدمة صفّرتها بالخمول) قبل الفحص والجدولة.
      BreakService.instance.reloadAnchor().then((_) {
        if (!mounted) return;
        setState(() {});
        _check();
        _scheduleNativeBreak();
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _check() async {
    if (_breakShowing || _starting || !mounted) return;
    final b = BreakService.instance.activeBreakNow();
    if (b == null) return;
    _starting = true;
    try {
      // القفل الصارم: شاشة استراحة داخليّة (نشاط حقيقيّ) تغطّي كامل الشاشة، عدّادها
      // وإغلاقها موثوقان في العزلة الرئيسيّة — يفتحها منبّه setAlarmClock الدقيق.
      await BreakService.instance.beginOverlay(b.index, b.restStart, b.end);
      // نظّف إشعار ملء الشاشة (إن جاء الفتح منه) وجدوِل الراحة القادمة مسبقًا.
      try {
        await _platform.invokeMethod('clearBreakNotification');
      } catch (_) {}
      await _scheduleNativeBreak();
      if (!mounted) return;
      _breakShowing = true;
      await Navigator.of(context).push(MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => BreakScreen(
            index: b.index,
            restStart: b.restStart,
            end: b.end,
            moveToBackOnClose: true),
      ));
      _breakShowing = false;
      // بعد الإغلاق: تأكّد من جدولة الراحة القادمة.
      await _scheduleNativeBreak();
      if (mounted) setState(() {});
    } finally {
      _starting = false;
    }
  }

  Future<void> _testNow() async {
    _breakShowing = true;
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => BreakScreen(
          index: 9999,
          restStart: 0,
          end: DateTime.now().add(const Duration(minutes: 1))),
    ));
    _breakShowing = false;
    if (mounted) setState(() {});
  }

  String _fmtMin(int m) =>
      '${((m ~/ 60) % 24).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  /// صياغة عربيّة للدقائق (تمييز مفرد/مثنّى/جمع).
  String _minsAr(int m) {
    if (m == 1) return 'دقيقة';
    if (m == 2) return 'دقيقتين';
    if (m >= 3 && m <= 10) return '$m دقائق';
    return '$m دقيقة';
  }

  /// صياغة عربيّة للساعات (تمييز مفرد/مثنّى/جمع).
  String _hoursAr(int h) {
    if (h == 1) return 'ساعة';
    if (h == 2) return 'ساعتين';
    if (h >= 3 && h <= 10) return '$h ساعات';
    return '$h ساعة';
  }

  String _nextLabel() {
    final n = BreakService.instance.nextStart();
    if (n == null) return 'التنبيه متوقّف';
    final d = n.difference(DateTime.now());
    if (d.inSeconds <= 0) return 'راحتك القادمة الآن';
    // أقلّ من ساعة: عدّاد حيّ MM:SS يتناقص كلّ ثانية.
    if (d.inMinutes < 60) {
      final m = d.inMinutes;
      final s = d.inSeconds % 60;
      return 'راحتك القادمة بعد '
          '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    final mins = d.inMinutes;
    final h = mins ~/ 60;
    final m = mins % 60;
    if (m == 0) return 'راحتك القادمة بعد ${_hoursAr(h)}';
    return 'راحتك القادمة بعد ${_hoursAr(h)} و${_minsAr(m)}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('لا تجلس طويلًا'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            tooltip: 'الإعدادات',
            onPressed: () async {
              await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()));
              await _scheduleNativeBreak();
              if (mounted) setState(() {});
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: BreakService.instance,
        builder: (context, _) {
          final svc = BreakService.instance;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // بطاقة الحالة.
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  gradient: LinearGradient(
                    colors: svc.enabled
                        ? const [Color(0xFF11998E), Color(0xFF38EF7D)]
                        : [scheme.surfaceContainerHighest, scheme.surface],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Column(
                  children: [
                    Icon(Icons.self_improvement,
                        size: 56,
                        color: svc.enabled ? Colors.white : scheme.primary),
                    const SizedBox(height: 8),
                    Text(
                      svc.enabled ? 'التنبيه مُفعّل ✅' : 'التنبيه متوقّف',
                      style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: svc.enabled ? Colors.white : scheme.onSurface),
                    ),
                    const SizedBox(height: 6),
                    Text(_nextLabel(),
                        style: TextStyle(
                            color: svc.enabled
                                ? Colors.white70
                                : scheme.onSurfaceVariant)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                value: svc.enabled,
                onChanged: (v) async {
                  await svc.save(enabled: v);
                  await NotifyService.instance.rescheduleAll();
                  await _scheduleNativeBreak();
                  await BackupService.write(svc.exportJson()); // نسخة على الجهاز
                },
                title: const Text('تشغيل/إيقاف',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              // بطاقة «العرض فوق التطبيقات» — الشرط الحاسم لِتقتحم الاستراحة الشاشة
              // فوق أي تطبيق (يوتيوب مثلًا)؛ فبدونه يمنع أندرويد الفتح من الخلفية.
              if (!_overlayPerm)
                Card(
                  color: scheme.errorContainer.withValues(alpha: 0.6),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.open_in_full, color: scheme.error),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text('السيطرة على الشاشة فوق أي تطبيق (مهمّ)',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'لِتقتحم الاستراحة الشاشة وأنت في تطبيق آخر (يوتيوب مثلًا) '
                          'أو والجهاز مقفل، امنح «العرض فوق التطبيقات». بدونه يمنع '
                          'النظام فتح الشاشة من الخلفية، فتظهر عند فتح التطبيق فقط.',
                          style: TextStyle(fontSize: 13, height: 1.5),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: _requestOverlayPerm,
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('منح الصلاحية'),
                        ),
                      ],
                    ),
                  ),
                ),
              // بطاقة «إشعارات ملء الشاشة» (أندرويد 14+) — لِتقتحم الاستراحة الشاشة
              // والجهاز مقفل بدل الاكتفاء بإشعار.
              if (!_fsiOk)
                Card(
                  color: scheme.errorContainer.withValues(alpha: 0.6),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.fullscreen, color: scheme.error),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text('إشعارات ملء الشاشة (مهمّ)',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'كي تقتحم الاستراحة الشاشة والجهاز مقفل (بدل إشعار فقط)، '
                          'فعّل «إشعارات ملء الشاشة» لهذا التطبيق.',
                          style: TextStyle(fontSize: 13, height: 1.5),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: _requestFsi,
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('تفعيل'),
                        ),
                      ],
                    ),
                  ),
                ),
              // بطاقة تجاوز توفير البطارية (تظهر حتى يُسمح) — شرط لعمل المنبّه
              // الدقيق في وقته والجهاز مغلق دون أن يوقفه النظام.
              if (!_battOk)
                Card(
                  color: scheme.errorContainer.withValues(alpha: 0.5),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.battery_alert, color: scheme.error),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text('تجاوز توفير البطارية',
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'كي يظهر التنبيه في وقته بالضبط والجهاز مغلق، اسمح '
                          'للتطبيق بتجاوز توفير البطارية — وإلّا قد يوقف النظام '
                          'المنبّه فلا تظهر الشاشة تلقائيًّا.',
                          style: TextStyle(fontSize: 13, height: 1.5),
                        ),
                        const SizedBox(height: 8),
                        FilledButton.icon(
                          onPressed: _requestBattery,
                          icon: const Icon(Icons.open_in_new, size: 18),
                          label: const Text('السماح'),
                        ),
                      ],
                    ),
                  ),
                ),
              // دليل التشغيل الموثوق على أجهزة شاومي/ريدمي (MIUI) — يظهر حتى
              // يؤكّد المستخدم تفعيله (لا يمكن كشف «التشغيل التلقائيّ» آليًّا).
              if (!_autostartDone)
                Card(
                  color: scheme.tertiaryContainer.withValues(alpha: 0.4),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.verified_user, color: scheme.tertiary),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text('ليعمل تلقائيًّا والتطبيق مغلق (مهمّ)',
                                  style:
                                      TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'في أجهزة شاومي/ريدمي وغيرها، يوقف النظام التطبيقات في '
                          'الخلفية فلا تظهر الشاشة تلقائيًّا. فعّل للتطبيق:\n'
                          '• «التشغيل التلقائيّ» (Autostart).\n'
                          '• «اعرض النوافذ المنبثقة أثناء التشغيل في الخلفية».\n'
                          '• «بلا قيود» في توفير البطارية.\n'
                          'ثمّ اقفل التطبيق في قائمة المهامّ الأخيرة (أيقونة القفل).',
                          style: TextStyle(fontSize: 13, height: 1.6),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _openAutostart,
                                icon: const Icon(Icons.open_in_new, size: 18),
                                label: const Text('افتح الإعدادات'),
                              ),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              onPressed: () => _setAutostartDone(true),
                              icon: const Icon(Icons.check, size: 18),
                              label: const Text('فعّلتها'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('فتراتك',
                    style: TextStyle(
                        fontWeight: FontWeight.bold, color: scheme.primary)),
              ),
              if (svc.periods.isEmpty)
                const ListTile(title: Text('لا توجد فترات — أضِفها من الإعدادات')),
              for (var i = 0; i < svc.periods.length; i++)
                Builder(builder: (_) {
                  final p = svc.periods[i];
                  return Card(
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: p.enabled
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerHighest,
                        child: Text('${i + 1}'),
                      ),
                      title: Text(p.startMinutes == 0 &&
                              p.endMinutes >= 24 * 60 - 1
                          ? 'طوال اليوم'
                          : 'من ${_fmtMin(p.startMinutes)} إلى ${_fmtMin(p.endMinutes)}'),
                      subtitle: Text(
                          'راحة ${p.restMinutes} د بعد كل ${p.workMinutes} د عمل'),
                      trailing: Icon(
                        p.enabled
                            ? Icons.check_circle
                            : Icons.pause_circle_outline,
                        color: p.enabled ? Colors.green : null,
                      ),
                    ),
                  );
                }),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _testNow,
                icon: const Icon(Icons.play_circle_outline),
                label: const Text('جرّب الآن (دقيقة)'),
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () async {
                  await Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const SettingsScreen()));
                  await _scheduleNativeBreak();
                  if (mounted) setState(() {});
                },
                icon: const Icon(Icons.tune),
                label: const Text('ضبط الفترات والرمز'),
              ),
            ],
          );
        },
      ),
    );
  }
}
