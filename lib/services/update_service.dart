import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

/// معلومات نسخة متاحة للتحديث.
class UpdateInfo {
  final String version;
  final int build;
  final String url;
  UpdateInfo(this.version, this.build, this.url);
}

/// خدمة التحديث الذاتيّ عبر GitHub Releases (توزيع APK مباشر — لا Google Play).
///
/// تقرأ `version.json` من إصدار `latest` (مع مصادر احتياطية)، وتقارن **اسم
/// النسخة** دلاليًّا (لأن split-per-abi يزيح رقم البناء). ثم تنزّل الـAPK وتفتح
/// مثبّت النظام عبر قناة أصليّة.
class UpdateService {
  UpdateService._();
  static final UpdateService instance = UpdateService._();

  static const _owner = 'alaoufi';
  static const _repo = 'health_reminder';
  static const _appName = 'HealthReminder';

  static const _channel =
      MethodChannel('com.alaoufi.health_reminder/installer');

  /// مصادر version.json بالترتيب (إصدار latest ثم raw ثم jsDelivr).
  static const List<String> _versionUrls = [
    'https://github.com/$_owner/$_repo/releases/download/latest/version.json',
    'https://raw.githubusercontent.com/$_owner/$_repo/main/version.json',
    'https://cdn.jsdelivr.net/gh/$_owner/$_repo@main/version.json',
  ];

  /// رابط التنزيل عبر المتصفّح (احتياط).
  static const browserUrl =
      'https://github.com/$_owner/$_repo/releases/download/latest/$_appName.apk';

  /// يفحص التحديث؛ يعيد [UpdateInfo] إن توفّرت نسخة أحدث، أو null.
  Future<UpdateInfo?> check() async {
    final data = await _fetchVersionJson();
    if (data == null) return null;
    final latest = (data['version'] ?? '').toString().trim();
    final build =
        (data['build'] is num) ? (data['build'] as num).toInt() : 0;
    final url = (data['url'] ?? '').toString().trim();
    if (latest.isEmpty || url.isEmpty) return null;
    String current;
    try {
      current = (await PackageInfo.fromPlatform()).version;
    } catch (_) {
      current = '0.0.0';
    }
    return _isNewer(latest, current) ? UpdateInfo(latest, build, url) : null;
  }

  Future<Map<String, dynamic>?> _fetchVersionJson() async {
    for (final u in _versionUrls) {
      try {
        final r = await http
            .get(Uri.parse(u))
            .timeout(const Duration(seconds: 8));
        if (r.statusCode == 200) {
          final j = jsonDecode(utf8.decode(r.bodyBytes));
          if (j is Map) return j.cast<String, dynamic>();
        }
      } catch (_) {/* جرّب المصدر التالي */}
    }
    return null;
  }

  /// مقارنة دلاليّة: هل [a] أحدث من [b]؟ (1.2.75 > 1.2.72)
  static bool _isNewer(String a, String b) {
    List<int> parts(String s) => s
        .split(RegExp(r'[.+\-]'))
        .map((x) => int.tryParse(x) ?? 0)
        .toList();
    final pa = parts(a), pb = parts(b);
    final n = pa.length > pb.length ? pa.length : pb.length;
    for (var i = 0; i < n; i++) {
      final x = i < pa.length ? pa[i] : 0;
      final y = i < pb.length ? pb[i] : 0;
      if (x != y) return x > y;
    }
    return false;
  }

  /// ينزّل الـAPK (مع تقدّم 0..1) ثم يفتح مثبّت النظام.
  Future<void> downloadAndInstall(
    String url, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/$_appName-update.apk');
    if (await file.exists()) {
      try {
        await file.delete();
      } catch (_) {}
    }
    final client = http.Client();
    try {
      final resp = await client
          .send(http.Request('GET', Uri.parse(url)))
          .timeout(const Duration(seconds: 60));
      final total = resp.contentLength ?? 0;
      final sink = file.openWrite();
      var received = 0;
      await for (final chunk in resp.stream) {
        sink.add(chunk);
        received += chunk.length;
        if (total > 0) onProgress?.call(received / total);
      }
      await sink.flush();
      await sink.close();
    } finally {
      client.close();
    }
    await _install(file.path);
  }

  Future<void> _install(String path) async {
    try {
      final can = await _channel.invokeMethod<bool>('canInstall') ?? false;
      if (!can) {
        // افتح إعداد «تثبيت تطبيقات غير معروفة» مرّة، ثم تابع محاولة التثبيت.
        await _channel.invokeMethod('openInstallSettings');
      }
      await _channel.invokeMethod('install', {'path': path});
    } catch (_) {
      // بديل: افتح الملفّ عبر مدير الملفّات/المثبّت.
      try {
        await OpenFilex.open(path);
      } catch (_) {}
    }
  }
}
