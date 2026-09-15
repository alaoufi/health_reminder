import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'break_service.dart';

/// شاشة «لا تجلس طويلًا» — تغطية كاملة صامتة بخلفيات متدرّجة متغيّرة وعبارات صحّية
/// وعدّاد تنازليّ. لا تُغلق إلا بانتهاء المدّة أو إدخال الرمز المعقّد.
class BreakScreen extends StatefulWidget {
  final int index;
  final int restStart;
  final DateTime end;

  /// عند الإغلاق: أرسِل التطبيق للخلفية ليعود المستخدم إلى ما كان يستخدمه قبل
  /// الاستراحة (للاستراحات الحقيقية)، بدل البقاء على رئيسية التطبيق.
  final bool moveToBackOnClose;
  const BreakScreen(
      {super.key,
      required this.index,
      required this.restStart,
      required this.end,
      this.moveToBackOnClose = false});

  @override
  State<BreakScreen> createState() => _BreakScreenState();
}

class _BreakScreenState extends State<BreakScreen> {
  Timer? _tick;
  Duration _remaining = Duration.zero;
  int _phase = 0;

  /// مخرج الطوارئ: مدّة الضغط المطوّل المطلوبة للإغلاق (طويلة نسبيًّا عمدًا).
  static const Duration _holdToClose = Duration(seconds: 5);
  Timer? _holdTimer;
  double _holdProgress = 0; // 0..1 تقدّم الضغط المطوّل
  bool _finishing = false; // حارس: إغلاق مرّة واحدة فقط

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
    // وضع غامر: يُخفي شريطي الحالة والتنقّل السفليّ فيغطّي التنبيه الشاشة كاملة
    // ولا يبقى «أسفل» ظاهرًا يمكّن من الخروج. (يُستعاد الوضع الطبيعيّ عند الإغلاق.)
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    } catch (_) {}
    // قفل صارم للاستراحات الحقيقية: يمنع المغادرة بزرّ الهوم/السحب من الأسفل.
    if (widget.moveToBackOnClose) {
      try {
        _platform.invokeMethod('setBreakLock', {'on': true});
      } catch (_) {}
    }
    // جرس بداية الراحة (إن فُعّل الخيار).
    if (BreakService.instance.soundAlert) {
      try {
        _platform.invokeMethod('playChime');
      } catch (_) {}
    }
    _computeRemaining();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      _computeRemaining();
      if (_remaining <= Duration.zero) {
        _finish();
      } else {
        setState(() => _phase = DateTime.now().second ~/ 6);
      }
    });
  }

  void _computeRemaining() {
    final r = widget.end.difference(DateTime.now());
    setState(() => _remaining = r.isNegative ? Duration.zero : r);
  }

  /// قناة أصليّة لإرسال التطبيق إلى الخلفية (العودة للتطبيق السابق).
  static const _platform =
      MethodChannel('com.alaoufi.health_reminder/installer');

  Future<void> _finish() async {
    if (_finishing) return; // إغلاق مرّة واحدة فقط
    _finishing = true;
    _tick?.cancel();
    _holdTimer?.cancel();
    // ارفع القفل الصارم وشغّل جرس النهاية (إن فُعّل) قبل الإغلاق.
    if (widget.moveToBackOnClose) {
      try {
        await _platform.invokeMethod('setBreakLock', {'on': false});
      } catch (_) {}
    }
    if (BreakService.instance.soundAlert) {
      try {
        await _platform.invokeMethod('playChime');
      } catch (_) {}
    }
    await BreakService.instance.markDone(widget.index, widget.restStart);
    // pop() المباشر لا يحجبه PopScope(canPop:false) — بخلاف maybePop() الذي كان
    // يُحترَم فيبقى العدّاد ثابتًا على 00:00 بلا إغلاق (سبب تجمّد الشاشة).
    if (mounted) Navigator.of(context).pop();
    // للاستراحات الحقيقية: أرسِل التطبيق للخلفية ليعود التطبيق السابق للواجهة.
    if (widget.moveToBackOnClose) {
      try {
        await _platform.invokeMethod('moveToBack');
      } catch (_) {}
    }
  }

  Future<void> _trySkip() async {
    final svc = BreakService.instance;
    if (!svc.hasBypassCode) return;
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
          onSubmitted: (_) => Navigator.pop(ctx, svc.checkCode(ctrl.text)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, svc.checkCode(ctrl.text)),
              child: const Text('تخطّي')),
        ],
      ),
    );
    if (ok == true) {
      await _finish();
    } else if (ok == false && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('الرمز غير صحيح'),
          duration: Duration(milliseconds: 1200)));
    }
  }

  // مخرج الطوارئ: يبدأ العدّ عند الضغط، ويُلغى عند الرفع قبل الاكتمال.
  void _startHold() {
    _holdTimer?.cancel();
    final start = DateTime.now();
    _holdTimer = Timer.periodic(const Duration(milliseconds: 50), (_) {
      final p = DateTime.now().difference(start).inMilliseconds /
          _holdToClose.inMilliseconds;
      if (p >= 1.0) {
        _holdTimer?.cancel();
        _holdTimer = null;
        _finish();
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

  @override
  void dispose() {
    _tick?.cancel();
    _holdTimer?.cancel();
    // أمان: ارفع القفل الصارم دائمًا عند التخلّص من الشاشة (كي لا يبقى الجهاز محبوسًا).
    try {
      _platform.invokeMethod('setBreakLock', {'on': false});
    } catch (_) {}
    // استعادة شريطي الحالة والتنقّل بعد انتهاء الاستراحة.
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {}
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
    final showPhrases = BreakService.instance.showPhrases;
    return PopScope(
      canPop: false,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          // مخرج الطوارئ: الضغط المطوّل في أي مكان يبدأ العدّ للإغلاق.
          body: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => _startHold(),
            onPointerUp: (_) => _cancelHold(),
            onPointerCancel: (_) => _cancelHold(),
            child: Stack(
              children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 1200),
                  width: double.infinity,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: g,
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.all(28),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Spacer(),
                          const Icon(Icons.self_improvement,
                              size: 64, color: Colors.white),
                          const SizedBox(height: 12),
                          const Text('لا تجلس طويلًا',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 28),
                          if (showPhrases)
                            AnimatedSwitcher(
                              duration: const Duration(milliseconds: 500),
                              child: Text(
                                phrase,
                                key: ValueKey(phrase),
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 19,
                                    height: 1.8,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          if (showPhrases) const SizedBox(height: 36),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 28, vertical: 14),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.4)),
                            ),
                            child: Text(
                              _fmt(_remaining),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 46,
                                  fontWeight: FontWeight.bold,
                                  fontFeatures: [FontFeature.tabularFigures()]),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text('تعود تلقائيًّا عند انتهاء الوقت',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 13)),
                          const Spacer(),
                          if (BreakService.instance.hasBypassCode)
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
