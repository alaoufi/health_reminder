import 'dart:async';

import 'package:flutter/material.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    _timer = Timer.periodic(const Duration(seconds: 20), (_) => _check());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _check();
  }

  @override
  void dispose() {
    _timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _check() async {
    if (_breakShowing || !mounted) return;
    final b = BreakService.instance.activeBreakNow();
    if (b == null) return;
    _breakShowing = true;
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => BreakScreen(index: b.index, end: b.end),
    ));
    _breakShowing = false;
    if (mounted) setState(() {});
  }

  Future<void> _testNow() async {
    _breakShowing = true;
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => BreakScreen(
          index: 9999, end: DateTime.now().add(const Duration(minutes: 1))),
    ));
    _breakShowing = false;
    if (mounted) setState(() {});
  }

  String _fmtMin(int m) =>
      '${((m ~/ 60) % 24).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  String _nextLabel() {
    final n = BreakService.instance.nextStart();
    if (n == null) return 'التنبيه متوقّف';
    final now = DateTime.now();
    final sameDay = n.day == now.day && n.month == now.month;
    final t = '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
    return sameDay ? 'الفترة القادمة اليوم $t' : 'الفترة القادمة غدًا $t';
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
                },
                title: const Text('تشغيل/إيقاف',
                    style: TextStyle(fontWeight: FontWeight.bold)),
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
                Card(
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: svc.periods[i].enabled
                          ? scheme.primaryContainer
                          : scheme.surfaceContainerHighest,
                      child: Text('${i + 1}'),
                    ),
                    title: Text(
                        'من ${_fmtMin(svc.periods[i].startMinutes)} إلى ${_fmtMin(svc.periods[i].endMinutes)}'),
                    subtitle: Text('مدّة الحركة: ${svc.periods[i].moveMinutes} دقيقة'),
                    trailing: Icon(
                      svc.periods[i].enabled
                          ? Icons.check_circle
                          : Icons.pause_circle_outline,
                      color: svc.periods[i].enabled ? Colors.green : null,
                    ),
                  ),
                ),
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
