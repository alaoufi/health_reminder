import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

import 'backup_service.dart';
import 'break_alarm.dart';
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
  bool _breakShowing = false;
  bool _starting = false;
  bool _overlayPerm = false;
  bool _battOk = true; // هل سُمح بتجاوز توفير البطارية؟ (لعمل المنبّه والجهاز مغلق)

  /// قناة أصليّة لإرسال التطبيق إلى الخلفية (العودة للتطبيق السابق).
  static const _platform =
      MethodChannel('com.alaoufi.health_reminder/installer');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPerm();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // تثبيت جديد؟ حاول استعادة الإعدادات من الملفّ المخفيّ بذاكرة الجهاز.
      await _restoreIfFresh();
      // تهيئة الإشعارات وجدولتها بعد ظهور الواجهة (لا تُعطّل الإقلاع إن فشلت).
      try {
        await NotifyService.instance.init();
        await NotifyService.instance.rescheduleAll();
      } catch (_) {}
      _check();
    });
    _timer = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {}); // تحديث «راحتك القادمة بعد …» بشكل تنازليّ
      _check();
    });
  }

  Future<void> _refreshPerm() async {
    try {
      final p = await FlutterOverlayWindow.isPermissionGranted();
      if (mounted) setState(() => _overlayPerm = p);
    } catch (_) {}
    try {
      final b =
          await _platform.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      if (mounted) setState(() => _battOk = b ?? true);
    } catch (_) {}
  }

  Future<void> _requestOverlayPerm() async {
    try {
      await FlutterOverlayWindow.requestPermission();
    } catch (_) {}
    await _refreshPerm();
  }

  Future<void> _requestBattery() async {
    try {
      await _platform.invokeMethod('requestIgnoreBatteryOptimizations');
    } catch (_) {}
    await _refreshPerm();
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
      _check();
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
      // القفل فوق كل التطبيقات (نافذة نظام) عند منح الصلاحية — يبقى فوق أي تطبيق.
      if (_overlayPerm && !await FlutterOverlayWindow.isActive()) {
        await BreakService.instance.beginOverlay(b.index, b.restStart, b.end);
        await FlutterOverlayWindow.showOverlay(
          height: WindowSize.fullCover,
          width: WindowSize.matchParent,
          alignment: OverlayAlignment.center,
          flag: OverlayFlag.focusPointer,
          overlayTitle: 'لا تجلس طويلًا',
          enableDrag: false,
        );
        // طبقة أمان: إغلاق مستقلّ عند نهاية الراحة (يمنع بقاء الشاشة عالقةً).
        await BreakAlarm.scheduleClose(b.end);
        // أرسِل التطبيق للخلفية لتطفو النافذة فوق التطبيق السابق؛ فعند إغلاقها
        // يعود المستخدم إلى ما كان يستخدمه بدل رئيسية «لا تجلس طويلًا».
        try {
          await _platform.invokeMethod('moveToBack');
        } catch (_) {}
        return;
      }
      // احتياط داخل التطبيق (بلا صلاحية العرض فوق التطبيقات).
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
    final mins = n.difference(DateTime.now()).inMinutes;
    if (mins <= 0) return 'راحتك القادمة الآن';
    if (mins < 60) return 'راحتك القادمة بعد ${_minsAr(mins)}';
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
                  await BackupService.write(svc.exportJson()); // نسخة على الجهاز
                },
                title: const Text('تشغيل/إيقاف',
                    style: TextStyle(fontWeight: FontWeight.bold)),
              ),
              // بطاقة صلاحية القفل فوق كل التطبيقات (تظهر حتى تُمنح).
              if (!_overlayPerm)
                Card(
                  color: scheme.errorContainer.withValues(alpha: 0.5),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.layers, color: scheme.error),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text('القفل فوق كل التطبيقات',
                                  style: TextStyle(fontWeight: FontWeight.bold)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'ليظهر التنبيه تلقائيًّا فوق أي تطبيق (والجهاز مغلق) '
                          'ويُغطّي الشاشة كاملة — لا داخل هذا التطبيق فقط — امنح '
                          'صلاحية «العرض فوق التطبيقات». بدونها لن تظهر الشاشة '
                          'إلا عند فتح التطبيق يدويًّا.',
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
                      title: Text(
                          'من ${_fmtMin(p.startMinutes)} إلى ${_fmtMin(p.endMinutes)}'),
                      subtitle: Text(
                          'عمل ${p.workMinutes} د · راحة ${p.restMinutes} د · ${p.restStarts().length} راحات'),
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
