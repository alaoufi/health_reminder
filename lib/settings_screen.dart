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
            endMinutes: p.endMinutes,
            workMinutes: p.workMinutes,
            restMinutes: p.restMinutes,
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

  Future<void> _pickTime(int cur, ValueChanged<int> onPick) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (cur ~/ 60) % 24, minute: cur % 60),
    );
    if (t != null) onPick(t.hour * 60 + t.minute);
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
                onPressed: () => setState(() => _periods.add(BreakPeriod(
                    startMinutes: 16 * 60,
                    endMinutes: 23 * 60,
                    workMinutes: 60,
                    restMinutes: 5))),
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
            // نافذة العمل: من … إلى …
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickTime(
                        p.startMinutes, (v) => setState(() => p.startMinutes = v)),
                    icon: const Icon(Icons.login, size: 16),
                    label: Text('تبدأ ${_fmtMin(p.startMinutes)}'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _pickTime(
                        p.endMinutes, (v) => setState(() => p.endMinutes = v)),
                    icon: const Icon(Icons.logout, size: 16),
                    label: Text('تنتهي ${_fmtMin(p.endMinutes)}'),
                  ),
                ),
              ],
            ),
            // مدّة العمل المتواصل
            Row(
              children: [
                const SizedBox(
                    width: 96,
                    child: Text('مدّة العمل:', style: TextStyle(fontSize: 13))),
                Expanded(
                  child: Slider(
                    value: p.workMinutes.toDouble().clamp(5, 180),
                    min: 5,
                    max: 180,
                    divisions: 35,
                    label: '${p.workMinutes} د',
                    onChanged: (v) => setState(() => p.workMinutes = v.round()),
                  ),
                ),
                SizedBox(
                    width: 54,
                    child: Text('${p.workMinutes} د',
                        style: const TextStyle(fontWeight: FontWeight.w600))),
              ],
            ),
            // مدّة الراحة/الحركة
            Row(
              children: [
                const SizedBox(
                    width: 96,
                    child: Text('مدّة الراحة:', style: TextStyle(fontSize: 13))),
                Expanded(
                  child: Slider(
                    value: p.restMinutes.toDouble().clamp(1, 30),
                    min: 1,
                    max: 30,
                    divisions: 29,
                    label: '${p.restMinutes} د',
                    onChanged: (v) => setState(() => p.restMinutes = v.round()),
                  ),
                ),
                SizedBox(
                    width: 54,
                    child: Text('${p.restMinutes} د',
                        style: const TextStyle(fontWeight: FontWeight.w600))),
              ],
            ),
            // ملخّص: عدد الراحات المتولّدة
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text('عدد الراحات: ${p.restStarts().length}',
                  style: TextStyle(fontSize: 12, color: scheme.primary)),
            ),
          ],
        ),
      ),
    );
  }
}
