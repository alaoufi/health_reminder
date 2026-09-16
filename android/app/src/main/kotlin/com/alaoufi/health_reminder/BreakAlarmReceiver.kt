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
                val nextAnchor = now + rest // الراحة الحاليّة تنتهي بعد rest
                val next = nextAnchor + work
                sp.edit()
                    .putLong("flutter.hr_anchor", nextAnchor)
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
