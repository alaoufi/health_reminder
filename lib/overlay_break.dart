import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// واجهة القفل التي تُرسَم **كنافذة نظام فوق كل التطبيقات**. تقرأ وقت الانتهاء
/// والرمز من التخزين المشترك، وتغلق نفسها بانتهاء المدّة أو إدخال الرمز.
class OverlayBreak extends StatefulWidget {
  const OverlayBreak({super.key});

  @override
  State<OverlayBreak> createState() => _OverlayBreakState();
}

class _OverlayBreakState extends State<OverlayBreak> {
  Timer? _tick;
  DateTime? _end;
  String _code = '';
  Duration _remaining = Duration.zero;
  int _phase = 0;

  static const List<List<Color>> _gradients = [
    [Color(0xFF134E5E), Color(0xFF71B280)],
    [Color(0xFF1A2980), Color(0xFF26D0CE)],
    [Color(0xFF360033), Color(0xFF0B8793)],
    [Color(0xFF2C3E50), Color(0xFF4CA1AF)],
    [Color(0xFF11998E), Color(0xFF38EF7D)],
    [Color(0xFF283048), Color(0xFF859398)],
  ];

  static const List<String> _phrases = [
    'جلستَ كثيرًا، ولصحّتك لن نسمح لك بإضرار نفسك.\n'
        'تحرّك بهدوء دقائق فقط ثم تعود لعملك.\nصحّتك مهمّة فحافظ عليها.',
    'استغلّ هذه البُسطة لصحّتك:\n'
        'اشرب ماءً 💧، وتنفّس بعمق 🌬️، وتحرّك بهدوء 🚶.',
    'قِف، وتمشَّ قليلًا،\nوحرّك كتفيك ورقبتك برفق.',
    'راحة قصيرة الآن\n= تركيز وطاقة أفضل بعد قليل.',
  ];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final sp = await SharedPreferences.getInstance();
      final ms = sp.getInt('hr_active_end');
      _code = sp.getString('hr_bypass_code') ?? '';
      _end = ms != null ? DateTime.fromMillisecondsSinceEpoch(ms) : null;
    } catch (_) {}
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final end = _end;
      if (end == null) return;
      final r = end.difference(DateTime.now());
      if (r <= Duration.zero) {
        _close();
      } else {
        setState(() {
          _remaining = r;
          _phase = DateTime.now().second ~/ 6;
        });
      }
    });
  }

  Future<void> _close() async {
    _tick?.cancel();
    try {
      await FlutterOverlayWindow.closeOverlay();
    } catch (_) {}
  }

  bool _checkCode(String v) => _code.trim().isNotEmpty && v.trim() == _code.trim();

  Future<void> _trySkip() async {
    if (_code.trim().isEmpty) return;
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إدخال رمز التخطّي'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            hintText: 'أدخل الرمز المعقّد',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (_) => Navigator.pop(ctx, _checkCode(ctrl.text)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, _checkCode(ctrl.text)),
              child: const Text('تخطّي')),
        ],
      ),
    );
    if (ok == true) await _close();
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final g = _gradients[_phase % _gradients.length];
    final phrase = _phrases[_phase % _phrases.length];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 1200),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: g,
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Spacer(),
                const Icon(Icons.self_improvement, size: 60, color: Colors.white),
                const SizedBox(height: 10),
                const Text('لا تجلس طويلًا',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 28,
                        fontWeight: FontWeight.bold)),
                const SizedBox(height: 22),
                Text(phrase,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        height: 1.8,
                        fontWeight: FontWeight.w600)),
                const SizedBox(height: 28),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 26, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(18),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.4)),
                  ),
                  child: Text(_fmt(_remaining),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 42,
                          fontWeight: FontWeight.bold,
                          fontFeatures: [FontFeature.tabularFigures()])),
                ),
                const Spacer(),
                if (_code.trim().isNotEmpty)
                  TextButton.icon(
                    onPressed: _trySkip,
                    icon: const Icon(Icons.lock_open,
                        color: Colors.white70, size: 18),
                    label: const Text('تخطّي بالرمز (للضرورة)',
                        style: TextStyle(color: Colors.white70)),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
