import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

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
  late bool _showPhrases;
  late int _idleResetMinutes;
  late List<BreakPeriod> _periods;
  final _codeCtrl = TextEditingController();
  String _appVersion = '';

  @override
  void initState() {
    super.initState();
    final svc = BreakService.instance;
    _enabled = svc.enabled;
    _showPhrases = svc.showPhrases;
    _idleResetMinutes = svc.idleResetMinutes;
    // رقم النسخة (يظهر أسفل الإعدادات).
    PackageInfo.fromPlatform().then((info) {
      if (mounted) {
        setState(() =>
            _appVersion = '${info.version} (${info.buildNumber})');
      }
    }).catchError((_) {});
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

  /// حقل كتابة حرّ لعدد الدقائق — يكتب المستخدم الرقم الذي يريده بلا خيارات مفروضة.
  Widget _numberField(
      String label, int value, ValueChanged<int> onPick, Key fieldKey) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
              width: 96,
              child: Text(label, style: const TextStyle(fontSize: 13))),
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              key: fieldKey,
              initialValue: value.toString(),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: const InputDecoration(
                isDense: true,
                suffixText: 'دقيقة',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              ),
              onChanged: (s) {
                final n = int.tryParse(s.trim());
                if (n != null && n > 0) onPick(n);
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickTime(int cur, ValueChanged<int> onPick) async {
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: (cur ~/ 60) % 24, minute: cur % 60),
    );
    if (t != null) onPick(t.hour * 60 + t.minute);
  }

  Future<void> _save() async {
    await BreakService.instance.save(
        enabled: _enabled,
        periods: _periods,
        bypassCode: _codeCtrl.text,
        showPhrases: _showPhrases,
        idleResetMinutes: _idleResetMinutes);
    await NotifyService.instance.rescheduleAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('حُفظ الإعداد')));
    Navigator.pop(context);
  }

  String _currentJson() => jsonEncode({
        'v': 1,
        'enabled': _enabled,
        'showPhrases': _showPhrases,
        'idleResetMinutes': _idleResetMinutes,
        'bypassCode': _codeCtrl.text.trim(),
        'periods': _periods.map((p) => p.toJson()).toList(),
      });

  Future<void> _exportBackup() async {
    final data = _currentJson();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('نسخة احتياطية للإعدادات'),
        content: SingleChildScrollView(
          child: SelectableText(data,
              style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إغلاق')),
          FilledButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: data));
              if (ctx.mounted) Navigator.pop(ctx);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                    content:
                        Text('نُسخت النسخة الاحتياطية — احفظها في ملاحظاتك')));
              }
            },
            icon: const Icon(Icons.copy, size: 18),
            label: const Text('نسخ'),
          ),
        ],
      ),
    );
  }

  Future<void> _importBackup() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استيراد نسخة احتياطية'),
        content: TextField(
          controller: ctrl,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'الصق نصّ النسخة الاحتياطية هنا',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('استيراد')),
        ],
      ),
    );
    if (ok != true) return;
    final done = await BreakService.instance.importJson(ctrl.text);
    if (!mounted) return;
    if (done) {
      final svc = BreakService.instance;
      setState(() {
        _enabled = svc.enabled;
        _showPhrases = svc.showPhrases;
        _idleResetMinutes = svc.idleResetMinutes;
        _codeCtrl.text = svc.bypassCode;
        _periods = svc.periods
            .map((p) => BreakPeriod(
                startMinutes: p.startMinutes,
                endMinutes: p.endMinutes,
                workMinutes: p.workMinutes,
                restMinutes: p.restMinutes,
                enabled: p.enabled))
            .toList();
      });
      await NotifyService.instance.rescheduleAll();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('تمّ استيراد الإعدادات ✅')));
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذّر الاستيراد — تأكّد من صحّة النصّ')));
    }
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
          SwitchListTile(
            value: _showPhrases,
            onChanged: (v) => setState(() => _showPhrases = v),
            title: const Text('عرض العبارات التحفيزية',
                style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(_showPhrases
                ? 'تظهر عبارات صحّية متغيّرة على شاشة الاستراحة.'
                : 'شاشة صامتة بعدّاد فقط بلا عبارات.'),
            contentPadding: EdgeInsets.zero,
          ),
          const Divider(),
          const SizedBox(height: 4),
          Text('ربط العمل بنشاط الجهاز',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: scheme.primary)),
          const SizedBox(height: 4),
          Text(
            'إذا أُطفئت الشاشة (ابتعدتَ عن الجهاز) مدّةً لا تقلّ عن '
            '$_idleResetMinutes دقيقة، تُحتسب راحةً ويعود عدّاد العمل للصفر.',
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
          _numberField('مدّة الخمول:', _idleResetMinutes,
              (v) => setState(() => _idleResetMinutes = v),
              const ValueKey('idle')),
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
          const Divider(),
          const SizedBox(height: 8),
          Text('نسخة احتياطية للإعدادات',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: scheme.primary)),
          const SizedBox(height: 4),
          const Text(
            'صدّر إعداداتك واحفظها في ملاحظاتك؛ ولاستعادتها بعد إعادة التثبيت '
            'الصقها في «استيراد» — فلا تفقد شيئًا.',
            style: TextStyle(fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _exportBackup,
                  icon: const Icon(Icons.ios_share, size: 18),
                  label: const Text('تصدير'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _importBackup,
                  icon: const Icon(Icons.download, size: 18),
                  label: const Text('استيراد'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('حفظ'),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              _appVersion.isEmpty
                  ? 'لا تجلس طويلًا'
                  : 'لا تجلس طويلًا · الإصدار $_appVersion',
              style: TextStyle(
                  fontSize: 12, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(height: 8),
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
            // مدّة العمل المتواصل — حقل كتابة حرّ (بالدقائق)
            _numberField('مدّة العمل:', p.workMinutes,
                (v) => setState(() => p.workMinutes = v),
                ValueKey('work_${identityHashCode(p)}')),
            // مدّة الراحة/الحركة — حقل كتابة حرّ (بالدقائق)
            _numberField('مدّة الراحة:', p.restMinutes,
                (v) => setState(() => p.restMinutes = v),
                ValueKey('rest_${identityHashCode(p)}')),
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
