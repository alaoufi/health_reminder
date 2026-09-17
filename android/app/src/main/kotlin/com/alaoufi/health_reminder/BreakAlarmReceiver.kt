package com.alaoufi.health_reminder

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat

/// مُستقبِل منبّه الراحة: يُنفَّذ في وقت الراحة بالضبط (عبر setAlarmClock) — وهو
/// أعلى أنواع المنبّهات أولويّةً وتحترمه أجهزة شاومي/ريدمي حتى في توفير الطاقة.
///
/// ينشر **إشعار ملء الشاشة صامتًا** يوقظ الشاشة ويفتح شاشة الاستراحة (نشاطًا
/// حقيقيًّا يغطّي كامل الشاشة)، ويحاول أيضًا فتحها مباشرةً.
class BreakAlarmReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        // منبّهات AlarmManager لا تبقى بعد إعادة تشغيل الجهاز؛ أعد جدولة الموعد
        // المحفوظ دون عرض شاشة استراحة أثناء الإقلاع.
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED ||
            intent.action == "android.intent.action.QUICKBOOT_POWERON" ||
            intent.action == "com.htc.intent.action.QUICKBOOT_POWERON") {
            val sp = context.getSharedPreferences(
                "FlutterSharedPreferences", Context.MODE_PRIVATE
            )
            if (sp.getBoolean("flutter.hr_enabled", true)) {
                val now = System.currentTimeMillis()
                val savedNext = sp.getLong("flutter.hr_next_ms", 0L)
                if (savedNext > now) {
                    scheduleNext(context, savedNext)
                } else {
                    // إذا فات الموعد أثناء الإقلاع، ابدأ دورة جديدة من الآن بدل
                    // ترك التطبيق بلا منبّه حتى يفتح المستخدم الإعدادات.
                    val work = sp.getLong("flutter.hr_work_ms", 30L * 60000)
                        .coerceAtLeast(60000L)
                    val next = now + work
                    sp.edit()
                        .putLong("flutter.hr_anchor", now)
                        .putLong("flutter.hr_next_ms", next)
                        .apply()
                    scheduleNext(context, next)
                }
            }
            return
        }
        val state = context.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
        if (!state.getBoolean("flutter.hr_enabled", true)) return
        val breakEnd = System.currentTimeMillis() + state.getLong("flutter.hr_rest_ms", 5L * 60000).coerceAtLeast(60000L)
        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE)
                as NotificationManager
        val chId = "break_fullscreen"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                chId, "تنبيه الحركة", NotificationManager.IMPORTANCE_HIGH
            )
            ch.setSound(null, null) // صامت — بلا صوت
            ch.enableVibration(false) // بلا اهتزاز
            nm.createNotificationChannel(ch)
        }

        val activity = Intent(context, MainActivity::class.java).apply {
            addFlags(
                Intent.FLAG_ACTIVITY_NEW_TASK or
                    Intent.FLAG_ACTIVITY_CLEAR_TOP or
                    Intent.FLAG_ACTIVITY_SINGLE_TOP
            )
            putExtra("show_break", true)
            putExtra("break_end_ms", breakEnd)
        }
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pi = PendingIntent.getActivity(context, 7102, activity, flags)

        val n = NotificationCompat.Builder(context, chId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("حان وقت الحركة 🧘")
            .setContentText("قف وتحرّك دقائق — اضغط للبدء")
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_ALARM)
            .setFullScreenIntent(pi, true) // يفتح الشاشة كاملةً عند إطفاء/قفل الشاشة
            .setContentIntent(pi)
            .setAutoCancel(true)
            .setSilent(true)
            .build()
        nm.notify(9911, n)

        // محاولة فتح مباشرة أيضًا (تعمل والتطبيق في الخلفية على بعض الأجهزة).
        try {
            context.startActivity(activity)
        } catch (_: Exception) {
        }

        // **نظام المنبّه**: أعِد جدولة الراحة التالية بنفسك فورًا — كي تستمرّ
        // السلسلة موثوقةً دون الاعتماد على فتح التطبيق أو بقاء الخدمة حيّة.
        try {
            val sp = context.getSharedPreferences(
                "FlutterSharedPreferences", Context.MODE_PRIVATE
            )
            if (sp.getBoolean("flutter.hr_enabled", true)) {
                val work = sp.getLong("flutter.hr_work_ms", 30L * 60000)
                val rest = sp.getLong("flutter.hr_rest_ms", 5L * 60000)
                val now = System.currentTimeMillis()
                // اترك المرساة عند بداية شوط العمل الذي انتهى الآن، كي ترى Dart
                // الراحة الفعّالة وتفتح BreakScreen بدل إعادة بناء الصفحة الرئيسية.
                // بعد بدء الشاشة ستنقل Dart المرساة إلى نهاية الراحة.
                val activeAnchor = now - work
                val next = now + rest + work
                sp.edit()
                    .putLong("flutter.hr_anchor", activeAnchor)
                    .putLong("flutter.hr_next_ms", next)
                    .apply()
                scheduleNext(context, next)
            }
        } catch (_: Exception) {
        }
    }

    /// يجدول منبّه الراحة التالية عبر setAlarmClock (بنفس معرّف التطبيق 7100).
    private fun scheduleNext(context: Context, epoch: Long) {
        val am = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val op = PendingIntent.getBroadcast(
            context, 7100,
            Intent(context, BreakAlarmReceiver::class.java)
                .setAction("com.alaoufi.health_reminder.BREAK_NOW"),
            flags
        )
        try {
            val show = PendingIntent.getActivity(
                context, 7101,
                Intent(context, MainActivity::class.java)
                    .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                flags
            )
            am.setAlarmClock(AlarmManager.AlarmClockInfo(epoch, show), op)
        } catch (e: Exception) {
            try {
                am.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, epoch, op)
            } catch (_: Exception) {
            }
        }
    }
}
