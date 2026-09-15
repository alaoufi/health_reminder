import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'backup_service.dart';
import 'break_screen.dart';
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
  late bool _soundAlert;
  late int _idleResetMinutes;
  late List<BreakPeriod> _periods;
  final _codeCtrl = TextEditingController();
  String _appVersion = '';
  bool _deviceBackupOn = false; // هل مُنِح الوصول لذاكرة الجهاز (حفظ يبقى بعد الحذف)؟

  @override
  void initState() {
    super.initState();
    final svc = BreakService.instance;
    _enabled = svc.enabled;
    _showPhrases = svc.showPhrases;
    _soundAlert = svc.soundAlert;
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
    _refreshBackupAccess();
  }

  Future<void> _refreshBackupAccess() async {
    final ok = await BackupService.hasAccess();
    if (mounted) setState(() => _deviceBackupOn = ok);
  }

  /// يطلب صلاحية الوصول لذاكرة الجهاز، ثم — إن كان تثبيتًا جديدًا ووُجد ملفّ محفوظ
  /// — يستعيد الإعدادات فورًا (يعالج «حذفت وثبّت ولم ترجع»)، وإلّا يكتب النسخة الحاليّة.
  Future<void> _enableDeviceBackup() async {
    await BackupService.requestAccess();
    await _refreshBackupAccess();
    if (!_deviceBackupOn) return;
    var msg = 'فُعّل الحفظ التلقائيّ على الجهاز ✅';
    if (BreakService.instance.wasFreshInstall) {
      final restored = await _restoreFromDevice(silent: true);
      if (restored) {
        msg = 'استُعيدت إعداداتك المحفوظة على الجهاز ✅';
      } else {
        await _persist();
      }
    } else {
      await _persist();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    }
  }

  /// يقرأ ملفّ النسخة من الجهاز ويستورده إلى الإعدادات. يعيد true عند النجاح.
  Future<bool> _restoreFromDevice({bool silent = false}) async {
    final raw = await BackupService.read();
    if (raw == null || raw.trim().isEmpty) {
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('لا توجد نسخة محفوظة على الجهاز')));
      }
      return false;
    }
    final ok = await BreakService.instance.importJson(raw);
    if (ok && mounted) {
      final svc = BreakService.instance;
      setState(() {
        _enabled = svc.enabled;
        _showPhrases = svc.showPhrases;
        _soundAlert = svc.soundAlert;
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
      if (!silent && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('استُعيدت إعداداتك ✅')));
      }
    } else if (!ok && !silent && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('تعذّرت الاستعادة — الملفّ غير صالح')));
    }
    return ok;
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

  /// يحفظ الإعدادات ويعيد جدولة التنبيهات (بلا إغلاق الشاشة).
  Future<void> _persist() async {
    await BreakService.instance.save(
        enabled: _enabled,
        periods: _periods,
        bypassCode: _codeCtrl.text,
        showPhrases: _showPhrases,
        soundAlert: _soundAlert,
        idleResetMinutes: _idleResetMinutes);
    await NotifyService.instance.rescheduleAll();
    // نسخة احتياطية تلقائيّة في ملفّ مخفيّ بذاكرة الجهاز (تبقى بعد الحذف).
    await BackupService.write(BreakService.instance.exportJson());
  }

  Future<void> _save() async {
    await _persist();
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(const SnackBar(content: Text('حُفظ الإعداد')));
    Navigator.pop(context);
  }

  /// تجربة على الإعدادات المحفوظة: يحفظ أولًا ثم يعرض شاشة الاستراحة بمدّة الراحة
  /// الفعليّة لأوّل فترة مفعّلة وبإعداد العبارات كما هو محفوظ (للخروج: ضغط مطوّل).
  Future<void> _testSaved() async {
    await _persist();
    if (!mounted) return;
    var restMin = 1; // بديل إن لا توجد فترة مفعّلة
    for (final p in _periods) {
      if (p.enabled && p.restMinutes > 0) {
        restMin = p.restMinutes;
        break;
      }
    }
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('تجربة على الإعدادات المحفوظة'),
        duration: Duration(milliseconds: 900)));
    await Navigator.of(context).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => BreakScreen(
          index: 9998,
          restStart: 0,
          end: DateTime.now().add(Duration(minutes: restMin))),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // حفظ تلقائيّ عند الخروج (زرّ الرجوع/إيماءة النظام) كي لا يضيع أي تعديل ولا
    // يبقى موعد الراحة قديمًا لو نسي المستخدم زرّ «حفظ».
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        await _persist();
        if (context.mounted) Navigator.of(context).pop();
      },
      child: Scaffold(
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
          SwitchListTile(
            value: _soundAlert,
            onChanged: (v) => setState(() => _soundAlert = v),
            title: const Text('جرس تنبيه (بداية/نهاية الراحة)',
                style: TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(_soundAlert
                ? 'يُصدر جرسًا قصيرًا عند بدء الراحة وعند انتهائها.'
                : 'صامت تمامًا (بلا صوت).'),
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
          Text('النسخة الاحتياطية التلقائيّة',
              style: TextStyle(
                  fontWeight: FontWeight.bold, color: scheme.primary)),
          const SizedBox(height: 4),
          // الحفظ التلقائيّ في ملفّ مخفيّ بذاكرة الجهاز (يبقى بعد حذف التطبيق).
          Card(
            color: _deviceBackupOn
                ? scheme.primaryContainer.withValues(alpha: 0.35)
                : scheme.errorContainer.withValues(alpha: 0.5),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                          _deviceBackupOn
                              ? Icons.cloud_done
                              : Icons.sd_storage,
                          color: _deviceBackupOn
                              ? Colors.green
                              : scheme.error),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text('حفظ تلقائيّ على الجهاز (يبقى بعد الحذف)',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _deviceBackupOn
                        ? 'مُفعّل: تُحفظ إعداداتك في ملفّ مخفيّ بذاكرة الجهاز، '
                            'وتُستعاد تلقائيًّا إذا حذفتَ التطبيق ثمّ أعدتَ تثبيته.'
                        : 'فعّله ليُحفظ إعدادك تلقائيًّا في ملفّ مخفيّ يبقى بعد '
                            'حذف التطبيق، فيسترجعها التطبيق وحده بعد إعادة التثبيت. '
                            'يتطلّب السماح بالوصول إلى الملفّات.',
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                  const SizedBox(height: 8),
                  if (!_deviceBackupOn)
                    FilledButton.icon(
                      onPressed: _enableDeviceBackup,
                      icon: const Icon(Icons.open_in_new, size: 18),
                      label: const Text('تفعيل الحفظ على الجهاز'),
                    )
                  else
                    OutlinedButton.icon(
                      onPressed: () => _restoreFromDevice(),
                      icon: const Icon(Icons.restore, size: 18),
                      label: const Text('استعادة إعداداتي من الجهاز'),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('حفظ'),
          ),
          const SizedBox(height: 10),
          // تجربة على الإعدادات المحفوظة (يحفظ ثم يعرض شاشة الاستراحة الفعليّة).
          OutlinedButton.icon(
            onPressed: _testSaved,
            icon: const Icon(Icons.play_circle_outline),
            label: const Text('تجربة على الإعدادات المحفوظة'),
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
            // نافذة العمل (ساعات التفعيل): من … إلى …
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
            // زرّ سريع: اجعل التفعيل طوال اليوم (يعمل في أي وقت الآن).
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  p.startMinutes = 0;
                  p.endMinutes = 24 * 60 - 1;
                }),
                icon: const Icon(Icons.all_inclusive, size: 16),
                label: const Text('طوال اليوم'),
              ),
            ),
            // مدّة العمل المتواصل — حقل كتابة حرّ (بالدقائق)
            _numberField('مدّة العمل:', p.workMinutes,
                (v) => setState(() => p.workMinutes = v),
                ValueKey('work_${identityHashCode(p)}')),
            // مدّة الراحة/الحركة — حقل كتابة حرّ (بالدقائق)
            _numberField('مدّة الراحة:', p.restMinutes,
                (v) => setState(() => p.restMinutes = v),
                ValueKey('rest_${identityHashCode(p)}')),
            // ملخّص: راحة بعد كل مدّة عمل، ضمن ساعات التفعيل.
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: Text(
                  'راحة ${p.restMinutes} د بعد كل ${p.workMinutes} د عمل، '
                  '${p.startMinutes == 0 && p.endMinutes >= 24 * 60 - 1 ? "طوال اليوم" : "بين ${_fmtMin(p.startMinutes)} و${_fmtMin(p.endMinutes)}"}',
                  style: TextStyle(fontSize: 12, color: scheme.primary)),
            ),
          ],
        ),
      ),
    );
  }
}
