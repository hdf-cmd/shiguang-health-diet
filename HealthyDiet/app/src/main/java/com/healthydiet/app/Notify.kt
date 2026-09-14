package com.healthydiet.app

import android.app.AlarmManager
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.webkit.JavascriptInterface
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import java.util.Calendar
import java.util.Random

/**
 * 系统级消息提醒：通知渠道 + 定时闹钟 + JS 桥接开关。
 * 三餐定点提醒（重复闹钟）+ 喝水随机提醒（每天 8 次，8:00–24:00 分层随机，一次性闹钟链式排次日）。
 * 到点由 ReminderReceiver 发横幅通知（App 未开也弹）；开机/启动 App 时恢复闹钟。
 */
object Notify {
    const val CHANNEL_ID = "sg_reminder"

    fun ensureChannel(ctx: Context) {
        val nm = ctx.getSystemService(NotificationManager::class.java) ?: return
        if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
            if (nm.getNotificationChannel(CHANNEL_ID) == null) {
                val ch = NotificationChannel(CHANNEL_ID, "饮食提醒", NotificationManager.IMPORTANCE_HIGH)
                ch.description = "三餐/喝水提醒，横幅弹出"
                ch.enableVibration(true)
                nm.createNotificationChannel(ch)
            }
        }
    }

    fun post(ctx: Context, id: Int, title: String, text: String) {
        ensureChannel(ctx)
        val intent = Intent(ctx, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val pi = PendingIntent.getActivity(
            ctx, 0, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
        val n = NotificationCompat.Builder(ctx, CHANNEL_ID)
            .setSmallIcon(R.mipmap.ic_launcher)
            .setContentTitle(title)
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setAutoCancel(true)
            .setContentIntent(pi)
            .build()
        try {
            NotificationManagerCompat.from(ctx).notify(id, n)
        } catch (_: SecurityException) {
            // 通知权限未授予（Android 13+）：静默跳过，前端开关仍可保存偏好
        }
    }
}

/** 提醒计划：三餐定点（重复闹钟）+ 喝水每日 8 次随机（一次性闹钟） */
object Reminders {
    private const val PREF = "sg_prefs"
    private const val KEY_ON = "reminders_on"
    private const val KEY_WATER_DAY = "water_day"
    private const val WATER_BASE_ID = 201
    private const val WATER_COUNT = 8
    private const val WATER_START_MIN = 8 * 60      // 早上 8 点
    private const val WATER_END_MIN = 24 * 60       // 晚上 12 点结束

    data class Slot(val hour: Int, val min: Int, val id: Int, val title: String, val text: String)

    val PLAN = listOf(
        Slot(8, 0, 101, "早餐提醒", "吃早餐了吗？点开记一笔，牛奶面包肉包都在食物库"),
        Slot(12, 0, 102, "午餐提醒", "记录午餐，看看今天的热量缺口还剩多少"),
        Slot(18, 30, 103, "晚餐提醒", "记录晚餐，收个尾看看今日营养达标情况")
    )

    private val WATER_TEXTS = listOf(
        "该喝水了：来一杯 200ml，点首页水杯打卡",
        "补水时间到：久坐之余起身接杯水吧",
        "喝水提醒：别等渴了才喝，小口慢喝",
        "来杯 200ml 水，顺便活动一下肩颈",
        "喝水提醒：看看今天的水杯进度条",
        "补水时间：下午来一杯，精神更好",
        "喝水提醒：晚饭后也记得补一杯",
        "今天最后一杯水：小口喝完就打卡收工"
    )

    fun enabled(ctx: Context): Boolean =
        ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE).getBoolean(KEY_ON, false)

    fun setEnabled(ctx: Context, on: Boolean) {
        ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE).edit().putBoolean(KEY_ON, on).apply()
        if (on) {
            schedule(ctx)
            scheduleWater(ctx, Calendar.getInstance())
        } else {
            cancel(ctx)
            cancelWater(ctx)
        }
    }

    /* ---------- 三餐定点 ---------- */

    fun schedule(ctx: Context) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (s in PLAN) {
            // 非精确重复闹钟：提醒类场景无需分钟级精度，避免精确闹钟权限限制
            am.setInexactRepeating(AlarmManager.RTC_WAKEUP, nextAt(s), AlarmManager.INTERVAL_DAY, pending(ctx, s))
        }
    }

    fun cancel(ctx: Context) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (s in PLAN) am.cancel(pending(ctx, s))
    }

    private fun pending(ctx: Context, s: Slot): PendingIntent {
        val i = Intent(ctx, ReminderReceiver::class.java).apply {
            putExtra("title", s.title)
            putExtra("text", s.text)
            putExtra("nid", s.id)
        }
        return PendingIntent.getBroadcast(
            ctx, s.id, i,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun nextAt(s: Slot): Long {
        val c = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, s.hour)
            set(Calendar.MINUTE, s.min)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) add(Calendar.DAY_OF_YEAR, 1)
        }
        return c.timeInMillis
    }

    /* ---------- 喝水随机提醒：每天 8 次，8:00–24:00 分层随机 ---------- */

    /** 按日期做种子的分层随机：把 16 小时切 8 段，每段内随机取一点 → 每天时刻不同且分布均匀 */
    fun waterSlots(day: Calendar): List<Pair<Int, Int>> {
        val key = day.get(Calendar.YEAR) * 1000 + day.get(Calendar.DAY_OF_YEAR)
        val rnd = Random(key.toLong() * 1000003L)
        val stratum = (WATER_END_MIN - WATER_START_MIN) / WATER_COUNT   // 120 分钟
        return (0 until WATER_COUNT).map { i ->
            val m = WATER_START_MIN + i * stratum + 5 + rnd.nextInt(stratum - 10)
            m / 60 to m % 60
        }
    }

    /** 排某天的喝水闹钟：只保留晚于当前时刻的点；当天已排完则自动滚到次日 */
    fun scheduleWater(ctx: Context, day: Calendar) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (i in 0 until WATER_COUNT) am.cancel(waterPending(ctx, i, "", false))
        val now = Calendar.getInstance()
        var target = day
        var remaining = waterSlots(target).withIndex()
            .filter { slotTime(target, it.value.first, it.value.second).after(now) }
        if (remaining.isEmpty()) {
            target = (day.clone() as Calendar).apply { add(Calendar.DAY_OF_YEAR, 1) }
            remaining = waterSlots(target).withIndex().toList()
        }
        remaining.forEachIndexed { idx, entry ->
            val isLast = idx == remaining.size - 1
            am.set(
                AlarmManager.RTC_WAKEUP,
                slotTime(target, entry.value.first, entry.value.second).timeInMillis,
                waterPending(ctx, entry.index, WATER_TEXTS[entry.index], isLast)
            )
        }
        ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE).edit()
            .putString(KEY_WATER_DAY, dayStamp(target)).apply()
    }

    fun cancelWater(ctx: Context) {
        val am = ctx.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        for (i in 0 until WATER_COUNT) am.cancel(waterPending(ctx, i, "", false))
        ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE).edit().remove(KEY_WATER_DAY).apply()
    }

    /** App 启动时调用：今天的喝水闹钟没排过（或跨天/漏排）则补排 */
    fun ensureWaterSchedule(ctx: Context) {
        val today = dayStamp(Calendar.getInstance())
        val saved = ctx.getSharedPreferences(PREF, Context.MODE_PRIVATE).getString(KEY_WATER_DAY, null)
        if (saved != today) scheduleWater(ctx, Calendar.getInstance())
    }

    private fun waterPending(ctx: Context, i: Int, text: String, isLast: Boolean): PendingIntent {
        val intent = Intent(ctx, ReminderReceiver::class.java).apply {
            putExtra("title", "喝水提醒")
            putExtra("text", text)
            putExtra("nid", WATER_BASE_ID + i)
            putExtra("isLastWater", isLast)
        }
        return PendingIntent.getBroadcast(
            ctx, WATER_BASE_ID + i, intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    private fun slotTime(day: Calendar, h: Int, m: Int): Calendar =
        (day.clone() as Calendar).apply {
            set(Calendar.HOUR_OF_DAY, h)
            set(Calendar.MINUTE, m)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }

    private fun dayStamp(c: Calendar): String =
        String.format("%04d-%02d-%02d", c.get(Calendar.YEAR), c.get(Calendar.MONTH) + 1, c.get(Calendar.DAY_OF_MONTH))
}

/** 闹钟触发 → 发系统通知；喝水当日最后一响后链式排次日批次 */
class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        val title = intent.getStringExtra("title") ?: "食光提醒"
        val text = intent.getStringExtra("text") ?: "该记录饮食了"
        val id = intent.getIntExtra("nid", 101)
        Notify.post(ctx, id, title, text)
        if (intent.getBooleanExtra("isLastWater", false) && Reminders.enabled(ctx)) {
            val tomorrow = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, 1) }
            Reminders.scheduleWater(ctx, tomorrow)
        }
    }
}

/** 开机后恢复闹钟（用户已开启提醒时） */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(ctx: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED && Reminders.enabled(ctx)) {
            Reminders.schedule(ctx)
            Reminders.scheduleWater(ctx, Calendar.getInstance())
        }
    }
}

/** WebView JS 桥接：window.SGNative */
class NativeBridge(private val ctx: Context) {
    @JavascriptInterface
    fun remindersEnabled(): Boolean = Reminders.enabled(ctx)

    @JavascriptInterface
    fun setReminders(on: Boolean): Boolean {
        Reminders.setEnabled(ctx, on)
        if (on) Notify.post(ctx, 999, "提醒已开启", "三餐定点 8:00/12:00/18:30 + 喝水每天 8 次随机提醒（8:00–24:00）")
        return on
    }

    @JavascriptInterface
    fun testNotify(): Boolean {
        Notify.post(ctx, 998, "食光测试通知", "看到这条说明系统通知工作正常 ✅ 点击可打开食光")
        return true
    }

    /** 调试/展示用：返回今天剩余的喝水提醒时刻（HH:mm 列表） */
    @JavascriptInterface
    fun waterPlanToday(): String {
        val now = java.util.Calendar.getInstance()
        val day = java.util.Calendar.getInstance()
        val slots = Reminders.waterSlots(day)
        val left = slots.filter { (h, m) ->
            val c = (day.clone() as java.util.Calendar).apply {
                set(java.util.Calendar.HOUR_OF_DAY, h)
                set(java.util.Calendar.MINUTE, m)
            }
            c.after(now)
        }
        return left.joinToString(", ") { String.format("%02d:%02d", it.first, it.second) }
    }
}
