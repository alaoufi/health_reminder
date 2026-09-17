import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';

/// يمنع تشغيل الجدولة قبل منح الصلاحيات التي يعتمد عليها التنبيه من الخلفية.
class PermissionGate extends StatefulWidget {
  final Widget child;
  const PermissionGate({super.key, required this.child});

  @override
  State<PermissionGate> createState() => _PermissionGateState();
}

class _PermissionGateState extends State<PermissionGate> with WidgetsBindingObserver {
  static const _channel = MethodChannel('com.alaoufi.health_reminder/installer');
  bool? _battery;
  bool? _fullscreen;
  bool? _overlay;
  bool _notifications = false;
  bool _exact = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final b = await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      final f = await _channel.invokeMethod<bool>('hasFullScreenIntent');
      final o = await FlutterOverlayWindow.isPermissionGranted();
      final n = await _channel.invokeMethod<bool>('hasNotifications') ?? false;
      final e = await _channel.invokeMethod<bool>('hasExactAlarm') ?? false;
      if (mounted) setState(() { _battery = b ?? false; _fullscreen = f ?? false; _overlay = o; _notifications = n; _exact = e; _error = null; });
      if (!_ready) {
        await _channel.invokeMethod('cancelExactBreak');
        await _channel.invokeMethod('stopBreakService');
      }
    } catch (_) {
      if (mounted) setState(() { _battery = false; _fullscreen = false; _overlay = false; _notifications = false; _exact = false; _error = 'تعذّر فحص الصلاحيات. اضغط إعادة الفحص.'; });
    }
  }

  bool get _ready => _battery == true && _fullscreen == true && _overlay == true && _notifications && _exact;

  Future<void> _open(String kind) async {
    try {
      if (kind == 'notifications') {
        await _channel.invokeMethod('requestNotifications');
      } else if (kind == 'exact') {
        await _channel.invokeMethod('requestExactAlarm');
      } else if (kind == 'battery') {
        await _channel.invokeMethod('requestIgnoreBatteryOptimizations');
      } else if (kind == 'fullscreen') {
        await _channel.invokeMethod('requestFullScreenIntent');
      } else {
        await FlutterOverlayWindow.requestPermission();
      }
    } catch (_) {}
    await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    if (_battery == null || _fullscreen == null || _overlay == null) {
      return const Directionality(textDirection: TextDirection.rtl,
          child: Scaffold(body: Center(child: CircularProgressIndicator())));
    }
    if (_ready) return widget.child;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('إعداد التطبيق قبل التشغيل')),
        body: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            const Icon(Icons.security, size: 64),
            const SizedBox(height: 12),
            const Text('يجب تفعيل المتطلبات التالية قبل تشغيل التنبيهات.', textAlign: TextAlign.center),
            const SizedBox(height: 20),
            if (_error != null) Text(_error!),
            _item('الإشعارات', _notifications, 'notifications'),
            _item('المنبّهات الدقيقة', _exact, 'exact'),
            _item('تجاوز توفير البطارية', _battery == true, 'battery'),
            _item('إشعارات ملء الشاشة', _fullscreen == true, 'fullscreen'),
            _item('العرض فوق التطبيقات', _overlay == true, 'overlay'),
            const SizedBox(height: 16),
            OutlinedButton.icon(onPressed: _refresh, icon: const Icon(Icons.refresh), label: const Text('إعادة الفحص')),
          ],
        ),
      ),
    );
  }

  Widget _item(String title, bool ok, String kind) => Card(
        child: ListTile(
          leading: Icon(ok ? Icons.check_circle : Icons.warning, color: ok ? Colors.green : Colors.orange),
          title: Text(title),
          trailing: ok ? null : FilledButton(onPressed: () => _open(kind), child: const Text('تفعيل')),
        ),
      );
}
