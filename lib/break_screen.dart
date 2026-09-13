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
  const BreakScreen(
      {super.key,
      required this.index,
      required this.restStart,
      required this.end});

  @override
  State<BreakScreen> createState() => _BreakScreenState();
}

class _BreakScreenState extends State<BreakScreen> {
  Timer? _tick;
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

  Future<void> _finish() async {
    _tick?.cancel();
    await BreakService.instance.markDone(widget.index, widget.restStart);
    if (mounted) Navigator.of(context).maybePop();
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
    return PopScope(
      canPop: false,
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: SystemUiOverlayStyle.light,
        child: Scaffold(
          body: AnimatedContainer(
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
                    const SizedBox(height: 36),
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
                        style: TextStyle(color: Colors.white70, fontSize: 13)),
                    const Spacer(),
                    if (BreakService.instance.hasBypassCode)
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
        ),
      ),
    );
  }
}
