import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/update_service.dart';

/// بوّابة تحديث إلزاميّة تغلّف التطبيق: تفحص التحديث عند الإقلاع وعند العودة
/// للواجهة (إن وُجد إنترنت). عند توفّر نسخة أحدث تعرض شاشة حاجبة «تحديث مطلوب».
/// إن تعذّر الفحص (لا إنترنت) لا تحجب — يعمل التطبيق عاديًّا.
class ForceUpdateGate extends StatefulWidget {
  final Widget child;
  const ForceUpdateGate({super.key, required this.child});

  @override
  State<ForceUpdateGate> createState() => _ForceUpdateGateState();
}

class _ForceUpdateGateState extends State<ForceUpdateGate>
    with WidgetsBindingObserver {
  UpdateInfo? _update;
  bool _downloading = false;
  bool _autoStarted = false;
  double _progress = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkQuietly();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _update == null) _checkQuietly();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _checkQuietly() async {
    try {
      final u = await UpdateService.instance.check();
      if (mounted && u != null) {
        setState(() => _update = u);
        // يبدأ التنزيل تلقائيًا عند اكتشاف نسخة أحدث؛ يظل تأكيد التثبيت
        // النهائي بيد Android ما لم يكن الجهاز مُدارًا Device Owner.
        if (!_autoStarted) {
          _autoStarted = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _updateNow();
          });
        }
      }
    } catch (_) {/* لا إنترنت أو تعذّر الفحص ⇒ لا نحجب */}
  }

  Future<void> _updateNow() async {
    final u = _update;
    if (u == null || _downloading) return;
    setState(() {
      _downloading = true;
      _progress = 0;
      _error = null;
    });
    try {
      await UpdateService.instance.downloadAndInstall(
        u.url,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (mounted) setState(() => _downloading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'تعذّر التنزيل. جرّب «التنزيل عبر المتصفّح».';
          _downloading = false;
        });
      }
    }
  }

  Future<void> _browser() async {
    final uri = Uri.parse(UpdateService.browserUrl);
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final u = _update;
    if (u == null) return widget.child;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: const Color(0xFF11998E),
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Spacer(),
                  const Icon(Icons.system_update,
                      size: 72, color: Colors.white),
                  const SizedBox(height: 16),
                  const Text('تحديث مطلوب',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 26,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  Text('تتوفّر نسخة أحدث (${u.version}). حدّث للمتابعة.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.white70, fontSize: 15)),
                  const SizedBox(height: 28),
                  if (_downloading) ...[
                    LinearProgressIndicator(
                      value: _progress > 0 ? _progress : null,
                      backgroundColor: Colors.white24,
                      color: Colors.white,
                    ),
                    const SizedBox(height: 8),
                    Text('${(_progress * 100).round()}%',
                        style: const TextStyle(color: Colors.white)),
                  ] else
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: const Color(0xFF11998E),
                            padding: const EdgeInsets.symmetric(vertical: 14)),
                        onPressed: _updateNow,
                        icon: const Icon(Icons.download),
                        label: const Text('تحديث الآن',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(_error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(color: Colors.amberAccent)),
                  ],
                  const SizedBox(height: 12),
                  TextButton.icon(
                    onPressed: _browser,
                    icon: const Icon(Icons.open_in_browser, color: Colors.white70),
                    label: const Text('التنزيل عبر المتصفّح',
                        style: TextStyle(color: Colors.white70)),
                  ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
