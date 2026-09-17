package com.alaoufi.health_reminder

import android.app.AlarmManager
import android.app.KeyguardManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.media.RingtoneManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.Environment
import android.os.PowerManager
import android.provider.Settings
import android.view.WindowManager
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

/// قناة التثبيت الأصليّة للتحديث الذاتيّ: فحص الصلاحية، فتح إعدادها، وتشغيل مثبّت
/// النظام على ملفّ APK عبر FileProvider.
class MainActivity : FlutterActivity() {
    private val channel = "com.alaoufi.health_reminder/installer"

    companion object {
        /// قفل صارم فعّال: يمنع مغادرة شاشة الاستراحة بزرّ الهوم/السحب من الأسفل.
        @JvmStatic
        var breakLockActive = false
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applyBreakWindowFlags()
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        applyBreakWindowFlags()
    }

    /// عند محاولة المغادرة (زرّ الهوم/السحب من الأسفل/المهامّ) أثناء القفل الصارم:
    /// أعِد الشاشة إلى الواجهة فورًا — فلا تُغلق إلا بالرمز أو الضغط المطوّل.
    override fun onUserLeaveHint() {
        super.onUserLeaveHint()
        if (breakLockActive) {
            try {
                val i = Intent(this, MainActivity::class.java).apply {
                    addFlags(
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                            Intent.FLAG_ACTIVITY_SINGLE_TOP
                    )
                }
                startActivity(i)
            } catch (_: Exception) {
            }
        }
    }

    /// عند الفتح من منبّه الراحة: أيقِظ الشاشة واعرِض فوق قفل الشاشة (قفل صارم).
    private fun applyBreakWindowFlags() {
        if (intent?.getBooleanExtra("show_break", false) != true) return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(true)
            setTurnScreenOn(true)
            try {
                val km = getSystemService(Context.KEYGUARD_SERVICE) as KeyguardManager
                km.requestDismissKeyguard(this, null)
            } catch (_: Exception) {
            }
        } else {
            @Suppress("DEPRECATION")
            window.addFlags(
                WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED or
                    WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON or
                    WindowManager.LayoutParams.FLAG_DISMISS_KEYGUARD or
                    WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, channel)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "consumeBreakRequest" -> {
                        val launch = intent
                        val end = launch?.getLongExtra("break_end_ms", 0L) ?: 0L
                        val requested = launch?.getBooleanExtra("show_break", false) == true
                        launch?.removeExtra("show_break")
                        launch?.removeExtra("break_end_ms")
                        result.success(if (requested && end > System.currentTimeMillis()) end else null)
                    }
                    "hasNotifications" -> result.success(
                        androidx.core.app.NotificationManagerCompat.from(this).areNotificationsEnabled()
                    )
                    "requestNotifications" -> {
                        if (Build.VERSION.SDK_INT >= 33 && checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                            requestPermissions(arrayOf(android.Manifest.permission.POST_NOTIFICATIONS), 8120)
                        } else {
                            startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, Uri.parse("package:$packageName")))
                        }
                        result.success(true)
                    }
                    "hasExactAlarm" -> result.success(
                        Build.VERSION.SDK_INT < 31 || (getSystemService(Context.ALARM_SERVICE) as AlarmManager).canScheduleExactAlarms()
                    )
                    "requestExactAlarm" -> {
                        if (Build.VERSION.SDK_INT >= 31) startActivity(Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, Uri.parse("package:$packageName")))
                        result.success(true)
                    }
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
                    "hasFullScreenIntent" -> {
                        // أندرويد 14+: إذن إشعارات ملء الشاشة (وإلّا تظهر كإشعار عاديّ).
                        val ok = if (Build.VERSION.SDK_INT >=
                            Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            (getSystemService(Context.NOTIFICATION_SERVICE)
                                as NotificationManager).canUseFullScreenIntent()
                        } else true
                        result.success(ok)
                    }
                    "requestFullScreenIntent" -> {
                        if (Build.VERSION.SDK_INT >=
                            Build.VERSION_CODES.UPSIDE_DOWN_CAKE) {
                            try {
                                val i = Intent(
                                    Settings.ACTION_MANAGE_APP_USE_FULL_SCREEN_INTENT,
                                    Uri.parse("package:$packageName")
                                )
                                i.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                                startActivity(i)
                            } catch (_: Exception) {}
                        }
                        result.success(true)
                    }
                    "startBreakService" -> {
                        try {
                            val i = Intent(this, BreakForegroundService::class.java)
                            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                                startForegroundService(i)
                            } else {
                                startService(i)
                            }
                        } catch (_: Exception) {}
                        result.success(true)
                    }
                    "stopBreakService" -> {
                        try {
                            stopService(Intent(this, BreakForegroundService::class.java))
                        } catch (_: Exception) {}
                        result.success(true)
                    }
                    "setBreakLock" -> {
                        // يُفعّل/يوقف القفل الصارم (منع المغادرة أثناء الاستراحة).
                        breakLockActive = call.argument<Boolean>("on") ?: false
                        result.success(true)
                    }
                    "playChime" -> {
                        // جرس قصير (صوت الإشعار الافتراضيّ) — لبداية/نهاية الراحة.
                        try {
                            val uri = RingtoneManager.getDefaultUri(
                                RingtoneManager.TYPE_NOTIFICATION
                            )
                            RingtoneManager.getRingtone(applicationContext, uri)?.play()
                        } catch (_: Exception) {
                        }
                        result.success(true)
                    }
                    "scheduleExactBreak" -> {
                        // يجدول منبّه راحة دقيقًا عبر setAlarmClock (يحترمه MIUI
                        // حتى في توفير الطاقة) — أوثق طريقة للظهور والتطبيق مغلق.
                        val epoch = call.argument<Number>("epoch")?.toLong()
                        if (epoch != null) scheduleExactBreak(epoch)
                        result.success(true)
                    }
                    "cancelExactBreak" -> {
                        cancelExactBreak()
                        result.success(true)
                    }
                    "clearBreakNotification" -> {
                        try {
                            (getSystemService(Context.NOTIFICATION_SERVICE)
                                as android.app.NotificationManager).cancel(9911)
                        } catch (_: Exception) {}
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

    private fun pendingFlags(): Int {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
    }

    private fun breakOperation(): PendingIntent {
        val i = Intent(this, BreakAlarmReceiver::class.java)
            .setAction("com.alaoufi.health_reminder.BREAK_NOW")
        return PendingIntent.getBroadcast(this, 7100, i, pendingFlags())
    }

    /// يجدول منبّه راحة دقيقًا عبر setAlarmClock (الأعلى أولويّةً، معفى من Doze
    /// وتحترمه أجهزة الشركات المصنّعة) — يُطلق مُستقبِل الراحة في الوقت بالضبط.
    private fun scheduleExactBreak(epoch: Long) {
        val am = getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val op = breakOperation()
        try {
            val show = PendingIntent.getActivity(
                this, 7101,
                Intent(this, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                pendingFlags()
            )
            am.setAlarmClock(AlarmManager.AlarmClockInfo(epoch, show), op)
        } catch (e: Exception) {
            try {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, epoch, op)
            } catch (_: Exception) {
            }
        }
    }

    private fun cancelExactBreak() {
        try {
            (getSystemService(Context.ALARM_SERVICE) as AlarmManager)
                .cancel(breakOperation())
        } catch (_: Exception) {
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
