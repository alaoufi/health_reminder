import 'package:flutter/material.dart';

import 'break_service.dart';
import 'notify_service.dart';

/// إعداد الفترات (حتى ٣) ورمز التخطّي.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late bool _enabled;
  late List<BreakPeriod> _periods;
  final _codeCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final svc = BreakService.instance;
    _enabled = svc.enabled;
    _periods = svc.periods
        .map((p) => BreakPeriod(
            startMinutes: p.startMinutes,
            moveMinutes: p.moveMinutes,
            enabled: p.enabled))
        .toList();
    _codeCtrl.text = svc.bypassCode;
  }

  @override
  void dispose() {
    _codeCtrl.dispose();
    super.dispose();
  }

  String _fmtMin(int m) =>
      '${((m ~/ 60) % 24).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

  Future<void> _pickStart(int i) async {
    final cur = _periods[i].startMinutes;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (cur ~/ 60) % 24, minute: cur % 60),
    );
    if (t != null) {
      setState(() => _periods[i].startMinutes = t.hour * 60 + t.minute);
    }
  }

  Future<void> _save() async {
    await BreakService.instance
        .save(enabled: _enabled, periods: _periods, bypassCode: _codeCtrl.text);
    await NotifyService.instance.rescheduleAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('حُفظ الإعداد')));
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('الإعدادات')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SwitchListTile(
            value: _enabled,
            onChanged: (v) => setState(() => _enabled = v),
            title: const Text('تفعيل التنبيه',
                style: TextStyle(fontWeight: FontWeight.bold)),
            contentPadding: EdgeInsets.zero,
          ),
          const Divider(),
          const SizedBox(height: 4),
          Text('الفترات (حتى ٣)',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: scheme.primary)),
          const SizedBox(height: 8),
          for (var i = 0; i < _periods.length; i++) _periodCard(i, scheme),
          if (_periods.length < 3)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => setState(() => _periods
                    .add(BreakPeriod(startMinutes: 13 * 60, moveMinutes: 5))),
                icon: const Icon(Icons.add),
                label: const Text('إضافة فترة'),
              ),
            ),
          const Divider(),
          const SizedBox(height: 8),
          Text('رمز التخطّي (للضرورة)',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: scheme.primary)),
          const SizedBox(height: 8),
          TextField(
            controller: _codeCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'رمز معقّد (أرقام)',
              hintText: 'مثال: 738214',
              helperText:
                  'يُطلب لفتح الشاشة قبل انتهاء المدّة. اتركه فارغًا لمنع التخطّي.',
              helperMaxLines: 2,
              border: OutlineInputBorder(),
              prefixIcon: Icon(Icons.password),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  Widget _periodCard(int i, ColorScheme scheme) {
    final p = _periods[i];
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
        child: Column(
          children: [
            Row(
              children: [
                Text('فترة ${i + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const Spacer(),
                Switch(
                    value: p.enabled,
                    onChanged: (v) => setState(() => p.enabled = v)),
                IconButton(
                  tooltip: 'حذف',
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                  onPressed: () => setState(() => _periods.removeAt(i)),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickStart(i),
                    icon: const Icon(Icons.schedule, size: 18),
                    label: Text('تبدأ ${_fmtMin(p.startMinutes)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Chip(
                    label: Text('تنتهي ${_fmtMin(p.endMinutes)}',
                        style: const TextStyle(fontSize: 12))),
              ],
            ),
            Row(
              children: [
                const Text('مدّة الحركة:'),
                Expanded(
                  child: Slider(
                    value: p.moveMinutes.toDouble().clamp(1, 30),
                    min: 1,
                    max: 30,
                    divisions: 29,
                    label: '${p.moveMinutes} د',
                    onChanged: (v) => setState(() => p.moveMinutes = v.round()),
                  ),
                ),
                Text('${p.moveMinutes} دقيقة',
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
