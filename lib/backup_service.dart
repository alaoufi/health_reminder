import 'package:flutter/services.dart';

/// نسخة احتياطية للإعدادات في **ملفّ مخفيّ بذاكرة الجهاز العامّة**
/// (Documents/.la_tajlis/settings.json) — تبقى بعد حذف التطبيق، فيسترجعها
/// التطبيق تلقائيًّا عند إعادة التثبيت. تعتمد على صلاحية «الوصول إلى كل الملفّات».
///
/// كل الاستدعاءات آمنة (مغلّفة) وتعمل من عزلة الواجهة الرئيسية فقط (حيث القناة
/// الأصليّة مسجّلة)؛ تفشل بهدوء بلا إسقاط التطبيق إن غابت الصلاحية أو القناة.
class BackupService {
  BackupService._();

  static const _ch = MethodChannel('com.alaoufi.health_reminder/installer');

  /// هل مُنِح الوصول إلى ذاكرة الجهاز العامّة (لازم للحفظ التلقائيّ المستمرّ)؟
  static Future<bool> hasAccess() async {
    try {
      return (await _ch.invokeMethod<bool>('hasAllFilesAccess')) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// يفتح شاشة طلب الصلاحية للمستخدم.
  static Future<void> requestAccess() async {
    try {
      await _ch.invokeMethod('requestAllFilesAccess');
    } catch (_) {}
  }

  /// يكتب نصّ JSON إلى الملفّ المخفيّ. يعيد true عند النجاح.
  static Future<bool> write(String json) async {
    try {
      return (await _ch.invokeMethod<bool>('writeBackup', {'json': json})) ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// يقرأ محتوى الملفّ المخفيّ إن وُجد، وإلّا null.
  static Future<String?> read() async {
    try {
      return await _ch.invokeMethod<String>('readBackup');
    } catch (_) {
      return null;
    }
  }
}
