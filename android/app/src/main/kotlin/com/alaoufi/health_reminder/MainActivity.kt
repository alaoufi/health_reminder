package com.alaoufi.health_reminder

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// قناة التثبيت الأصليّة للتحديث الذاتيّ: فحص الصلاحية، فتح إعدادها، وتشغيل مثبّت
/// النظام على ملفّ APK عبر FileProvider.
class MainActivity : FlutterActivity() {
    private val channel = "com.alaoufi.health_reminder/installer"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "canInstall" -> {
                        val can = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            packageManager.canRequestPackageInstalls()
                        } else true
                        result.success(can)
                    }
                    "openInstallSettings" -> {
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                            val intent = Intent(
                                Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                                Uri.parse("package:$packageName")
                            )
                            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                            startActivity(intent)
                        }
                        result.success(true)
                    }
                    "hasAllFilesAccess" -> {
                        // هل يملك التطبيق وصولًا لذاكرة الجهاز العامّة (ليكتب ملفّ
                        // نسخة احتياطية يبقى بعد حذف التطبيق)؟
                        val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                            Environment.isExternalStorageManager()
                        } else {
                            checkSelfPermission(
                                android.Manifest.permission.WRITE_EXTERNAL_STORAGE
                            ) == PackageManager.PERMISSION_GRANTED
                        }
                        result.success(ok)
                    }
                    "requestAllFilesAccess" -> {
                        // يفتح طلب «الوصول إلى كل الملفّات» (أو صلاحية التخزين القديمة).
                        try {
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                                val intent = Intent(
                                    Settings.ACTION_MANAGE_APP_ALL_FILES_ACCESS_PERMISSION,
                                    Uri.parse("package:$packageName")
                                )
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                            } else {
                                requestPermissions(
                                    arrayOf(
                                        android.Manifest.permission.WRITE_EXTERNAL_STORAGE
                                    ),
                                    4201
                                )
                            }
                        } catch (e: Exception) {
                            try {
                                val intent = Intent(
                                    Settings.ACTION_MANAGE_ALL_FILES_ACCESS_PERMISSION
                                )
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                            } catch (_: Exception) {}
                        }
                        result.success(true)
                    }
                    "writeBackup" -> {
                        // يكتب النسخة الاحتياطية في ملفّ مخفيّ بذاكرة الجهاز العامّة
                        // (مجلّد Documents/.la_tajlis) — يبقى بعد حذف التطبيق.
                        val json = call.argument<String>("json")
                        if (json == null) {
                            result.error("no_json", "لا بيانات", null)
                            return@setMethodCallHandler
                        }
                        try {
                            val file = backupFile()
                            file.parentFile?.mkdirs()
                            file.writeText(json)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("write_failed", e.message, null)
                        }
                    }
                    "readBackup" -> {
                        // يقرأ ملفّ النسخة الاحتياطية إن وُجد (لاستعادة الإعدادات بعد
                        // إعادة التثبيت)، وإلّا يعيد null.
                        try {
                            val file = backupFile()
                            if (file.exists()) result.success(file.readText())
                            else result.success(null)
                        } catch (e: Exception) {
                            result.success(null)
                        }
                    }
                    "isIgnoringBatteryOptimizations" -> {
                        // هل سُمح للتطبيق بتجاوز توفير البطارية؟ (شرط لعمل المنبّهات
                        // الدقيقة والجهاز مغلق دون أن يوقفها النظام.)
                        val ok = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            val pm = getSystemService(Context.POWER_SERVICE) as PowerManager
                            pm.isIgnoringBatteryOptimizations(packageName)
                        } else true
                        result.success(ok)
                    }
                    "requestIgnoreBatteryOptimizations" -> {
                        // يفتح طلب النظام لتجاوز توفير البطارية لهذا التطبيق.
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                            try {
                                val intent = Intent(
                                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                                    Uri.parse("package:$packageName")
                                )
                                intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(intent)
                            } catch (e: Exception) {
                                // بديل: افتح شاشة إعدادات تجاوز التوفير العامّة.
                                try {
                                    val intent = Intent(
                                        Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS
                                    )
                                    intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                    startActivity(intent)
                                } catch (_: Exception) {}
                            }
                        }
                        result.success(true)
                    }
                    "openAutostartSettings" -> {
                        // يفتح صفحة «التشغيل التلقائيّ» في شاومي/ريدمي (MIUI) إن
                        // وُجدت، وإلّا صفحة تفاصيل التطبيق — لتفعيل الظهور من
                        // الخلفية وعدم إيقاف التطبيق.
                        val opened = tryOpen(
                            Intent().setClassName(
                                "com.miui.securitycenter",
                                "com.miui.permcenter.autostart.AutoStartManagementActivity"
                            )
                        ) || tryOpen(
                            Intent().setClassName(
                                "com.miui.securitycenter",
                                "com.miui.appmanager.ApplicationsDetailsActivity"
                            ).putExtra("package_name", packageName)
                        )
                        if (!opened) {
                            tryOpen(
                                Intent(
                                    Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                                    Uri.parse("package:$packageName")
                                )
                            )
                        }
                        result.success(true)
                    }
                    "moveToBack" -> {
                        // أرسِل المهمّة إلى الخلفية ليعود المستخدم إلى التطبيق
                        // السابق بعد انتهاء الاستراحة (بدل البقاء على هذا التطبيق).
                        moveTaskToBack(true)
                        result.success(true)
                    }
                    "install" -> {
                        val path = call.argument<String>("path")
                        if (path == null) {
                            result.error("no_path", "المسار غير موجود", null)
                            return@setMethodCallHandler
                        }
                        try {
                            installApk(path)
                            result.success(true)
                        } catch (e: Exception) {
                            result.error("install_failed", e.message, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    /// يحاول فتح شاشة (Intent) ويعيد true عند النجاح.
    private fun tryOpen(intent: Intent): Boolean {
        return try {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            startActivity(intent)
            true
        } catch (e: Exception) {
            false
        }
    }

    /// ملفّ النسخة الاحتياطية المخفيّ في ذاكرة الجهاز العامّة (يبقى بعد حذف التطبيق).
    private fun backupFile(): File {
        val docs = Environment.getExternalStoragePublicDirectory(
            Environment.DIRECTORY_DOCUMENTS
        )
        return File(File(docs, ".la_tajlis"), "settings.json")
    }

    private fun installApk(path: String) {
        val file = File(path)
        val uri: Uri = FileProvider.getUriForFile(
            this, "$packageName.fileprovider", file
        )
        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        }
        startActivity(intent)
    }
}
