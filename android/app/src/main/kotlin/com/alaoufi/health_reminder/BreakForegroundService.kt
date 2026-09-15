package com.alaoufi.health_reminder

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import androidx.core.app.NotificationCompat

/// خدمة أماميّة دائمة تُبقي العمليّة حيّة، فتظهر الاستراحة في وقتها **حتى وأنت
/// تستخدم الجوال في تطبيق آخر** (لا يكفي إشعار ملء الشاشة إلا والشاشة مقفلة)،
/// وتنفّذ منطق الخمول: إن أُطفئت الشاشة مدّةً ≥ عتبة الخمول تُصفَّر دورة العمل.
///
/// تقرأ حالة التطبيق من تخزين Flutter المشترك (يكتبها Dart): المفتاح الأصليّ هنا
/// يحمل بادئة "flutter." وملفّه "FlutterSharedPreferences".
class BreakForegroundService : Service() {
    private val handler = Handler(Looper.getMainLooper())
    private var lastLaunchedMs = 0L
    private val chId = "break_service"
    private val notifId = 4411

    private fun prefs() =
        getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)

    private val screenReceiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val sp = prefs()
            val now = System.currentTimeMillis()
            when (intent.action) {
                Intent.ACTION_SCREEN_OFF ->
                    sp.edit().putLong("flutter.hr_screen_off_at", now).apply()
                Intent.ACTION_USER_PRESENT, Intent.ACTION_SCREEN_ON -> {
                    val off = sp.getLong("flutter.hr_screen_off_at", 0L)
                    val idle = sp.getLong("flutter.hr_idle_ms", 15L * 60000)
                    if (off > 0L && now - off >= idle) {
                        // خمول طويل ⇒ راحة ⇒ صفّر الدورة (تبدأ من الآن).
                        val work = sp.getLong("flutter.hr_work_ms", 30L * 60000)
                        sp.edit()
                            .putLong("flutter.hr_anchor", now)
                            .putLong("flutter.hr_next_ms", now + work)
                            .putLong("flutter.hr_screen_off_at", 0L)
                            .apply()
                        lastLaunchedMs = 0L
                    } else {
                        sp.edit().putLong("flutter.hr_screen_off_at", 0L).apply()
                    }
                }
            }
        }
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        createChannel()
        startForegroundNotice()
        val f = IntentFilter().apply {
            addAction(Intent.ACTION_SCREEN_OFF)
            addAction(Intent.ACTION_SCREEN_ON)
            addAction(Intent.ACTION_USER_PRESENT)
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            registerReceiver(screenReceiver, f, Context.RECEIVER_NOT_EXPORTED)
        } else {
            @Suppress("UnspecifiedRegisterReceiverFlag")
            registerReceiver(screenReceiver, f)
        }
        handler.post(tick)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onDestroy() {
        try {
            unregisterReceiver(screenReceiver)
        } catch (_: Exception) {
        }
        handler.removeCallbacksAndMessages(null)
        super.onDestroy()
    }

    private val tick = object : Runnable {
        override fun run() {
            try {
                checkBreak()
            } catch (_: Exception) {
            }
            handler.postDelayed(this, 2000)
        }
    }

    /// إن حان وقت الراحة ولم تكن استراحة نشطة الآن، افتح شاشة الاستراحة فورًا.
    private fun checkBreak() {
        val sp = prefs()
        if (!sp.getBoolean("flutter.hr_enabled", true)) return
        if (sp.getBoolean("flutter.hr_break_active", false)) return
        val next = sp.getLong("flutter.hr_next_ms", 0L)
        if (next <= 0L) return
        val now = System.currentTimeMillis()
        if (now >= next && now - next < 5L * 60000 && next != lastLaunchedMs) {
            lastLaunchedMs = next
            val i = Intent(this, MainActivity::class.java).apply {
                addFlags(
                    Intent.FLAG_ACTIVITY_NEW_TASK or
                        Intent.FLAG_ACTIVITY_REORDER_TO_FRONT or
                        Intent.FLAG_ACTIVITY_SINGLE_TOP
                )
                putExtra("show_break", true)
            }
            try {
                startActivity(i)
            } catch (_: Exception) {
            }
        }
    }

    private fun createChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val ch = NotificationChannel(
                chId, "خدمة التنبيه", NotificationManager.IMPORTANCE_MIN
            )
            ch.setSound(null, null)
            ch.enableVibration(false)
            ch.setShowBadge(false)
            (getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager)
                .createNotificationChannel(ch)
        }
    }

    private fun startForegroundNotice() {
        val flags = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        } else {
            PendingIntent.FLAG_UPDATE_CURRENT
        }
        val pi = PendingIntent.getActivity(
            this, 7200,
            Intent(this, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            flags
        )
        val n = NotificationCompat.Builder(this, chId)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle("لا تجلس طويلًا — التنبيه نشط")
            .setContentText("يعمل ليذكّرك بالحركة في وقتها")
            .setPriority(NotificationCompat.PRIORITY_MIN)
            .setOngoing(true)
            .setSilent(true)
            .setShowWhen(false)
            .setContentIntent(pi)
            .build()
        startForeground(notifId, n)
    }
}
