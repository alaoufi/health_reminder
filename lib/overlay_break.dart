import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  Timer? _safety; // خطّ أمان مستقلّ: يُغلق النافذة مهما تعطّل المؤقّت الرئيسيّ.
  DateTime? _end;
  String _code = '';
  Duration _remaining = Duration.zero;
  int _phase = 0;
  bool _closed = false;
  bool _showPhrases = true; // عرض العبارات أم شاشة صامتة بعدّاد فقط

  /// سقف أقصى مطلق لمدّة القفل — مهما كانت البيانات، تُغلق النافذة خلاله.
  static const Duration _maxCap = Duration(minutes: 30);

  /// مدّة بديلة إن تعذّر تحديد وقت الانتهاء (لئلّا تبقى النافذة بلا نهاية).
  static const int _fallbackMinutes = 5;

  /// مخرج الطوارئ: مدّة الضغط المطوّل المطلوبة للإغلاق (طويلة نسبيًّا عمدًا).
  static const Duration _holdToClose = Duration(seconds: 5);
  Timer? _holdTimer;
  double _holdProgress = 0; // 0..1 تقدّم الضغط المطوّل

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
    // وضع غامر: يُخفي شريطي الحالة والتنقّل ليُغطّي القفل الشاشة كاملة بلا منفذ خروج.
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {}
    _load();
  }

  Future<void> _load() async {
    DateTime? end;
    var fallbackMins = _fallbackMinutes;
    try {
      final sp = await SharedPreferences.getInstance();
      final ms = sp.getInt('hr_active_end');
      final fm = sp.getInt('hr_active_minutes');
      if (fm != null && fm > 0) fallbackMins = fm;
      _code = sp.getString('hr_bypass_code') ?? '';
      _showPhrases = sp.getBool('hr_show_phrases') ?? true;
      if (ms != null) end = DateTime.fromMillisecondsSinceEpoch(ms);
    } catch (_) {}

    final now = DateTime.now();
    // لا نترك النافذة بلا نهاية صالحة إطلاقًا (وإلا يتجمّد الجهاز بلا عدّاد).
    end ??= now.add(Duration(minutes: fallbackMins));
    // سقف أمان: مهما فسدت البيانات، تُغلق النافذة خلال الحدّ الأقصى.
    final maxEnd = now.add(_maxCap);
    if (end.isAfter(maxEnd)) end = maxEnd;
    _end = end;

    // لو انتهى الوقت فعلًا (بيانات قديمة) أغلق فورًا بدل حبس المستخدم.
    if (!end.isAfter(now)) {
      _close();
      return;
    }

    // اعرض العدّاد فورًا بلا ثانية «00:00» أولى.
    if (mounted) setState(() => _remaining = end!.difference(now));

    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final e = _end;
      if (e == null) {
        _close();
        return;
      }
      final r = e.difference(DateTime.now());
      if (r <= Duration.zero) {
        _close();
      } else if (mounted) {
        setState(() {
          _remaining = r;
          _phase = DateTime.now().second ~/ 6;
        });
      }
    });

    // خطّ أمان مستقلّ عن المؤقّت الرئيسيّ: إغلاق مضمون خلال السقف الأقصى.
    _safety = Timer(_maxCap + const Duration(seconds: 2), _close);
  }

  Future<void> _close() async {
    if (_closed) return; // إغلاق مرّة واحدة (idempotent)
    _closed = true;
    _tick?.cancel();
    _safety?.cancel();
    _holdTimer?.cancel();
    // استعادة شريطي الحالة والتنقّل قبل إغلاق النافذة.
    try {
      await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {}
    try {
      await FlutterOverlayWindow.closeOverlay();
    } catch (_) {}
    // نظّف علامة النشاط حتى لا تُقرأ نهاية قديمة في مرّة لاحقة.
    try {
      final sp = await SharedPreferences.getInstance();
      await sp.remove('hr_active_end');
      await sp.remove('hr_active_minutes');
    } catch (_) {}
  }

  // مخرج الطوارئ: يبدأ العدّ عند الضغط، ويُلغى عند الرفع قبل الاكتمال.
  void _startHold() {
    _holdTimer?.cancel();
    final start = DateTime.now();
    _holdTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final p = DateTime.now().difference(start).inMilliseconds /
          _holdToClose.inMilliseconds;
      if (p >= 1.0) {
        _cancelHold();
        _close();
      } else if (mounted) {
        setState(() => _holdProgress = p);
      }
    });
  }

  void _cancelHold() {
    _holdTimer?.cancel();
    _holdTimer = null;
    if (mounted && _holdProgress != 0) setState(() => _holdProgress = 0);
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
    _safety?.cancel();
    _holdTimer?.cancel();
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
      // مخرج الطوارئ: الضغط المطوّل في أي مكان يبدأ العدّ للإغلاق، والرفع يُلغيه.
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _startHold(),
        onPointerUp: (_) => _cancelHold(),
        onPointerCancel: (_) => _cancelHold(),
        child: Stack(
          children: [
            AnimatedContainer(
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
                      const Icon(Icons.self_improvement,
                          size: 60, color: Colors.white),
                      const SizedBox(height: 10),
                      const Text('لا تجلس طويلًا',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 28,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 22),
                      if (_showPhrases)
                        Text(phrase,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                height: 1.8,
                                fontWeight: FontWeight.w600)),
                      if (_showPhrases) const SizedBox(height: 28),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 26, vertical: 12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4)),
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
                      const SizedBox(height: 6),
                      Text(
                        'للطوارئ: اضغط مطوّلًا في أي مكان '
                        '${_holdToClose.inSeconds} ثوانٍ للإغلاق',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_holdProgress > 0) _buildHoldIndicator(),
          ],
        ),
      ),
    );
  }

  /// مؤشّر تقدّم الضغط المطوّل (يظهر أثناء الضغط فقط).
  Widget _buildHoldIndicator() => Positioned.fill(
        child: IgnorePointer(
          child: Container(
            color: Colors.black.withValues(alpha: 0.35),
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 88,
                  height: 88,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: _holdProgress,
                        strokeWidth: 6,
                        color: Colors.white,
                        backgroundColor: Colors.white24,
                      ),
                      Text('${(_holdProgress * 100).round()}%',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                const Text('استمرّ بالضغط للإغلاق…',
                    style: TextStyle(color: Colors.white, fontSize: 14)),
              ],
            ),
          ),
        ),
      );
}
