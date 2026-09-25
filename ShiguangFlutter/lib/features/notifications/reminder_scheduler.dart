// ShiguangFlutter/lib/features/notifications/reminder_scheduler.dart
// M4-T6 提醒调度接线：把 domain/reminders.dart（T5）的纯规则接上
// flutter_local_notifications，实现渠道/三餐每日重复/喝水当日排程/开关持久化。
//
// 权威源 HealthyDiet/app/src/main/java/com/healthydiet/app/Notify.kt：
//  - 渠道 sg_reminder/「饮食提醒」/IMPORTANCE_HIGH/描述逐字：:23, :29-31；
//  - 三餐 setInexactRepeating 每日：:112-118（Flutter 面：zonedSchedule +
//    matchDateTimeComponents.time + AndroidScheduleMode.inexactAllowWhileIdle，
//    同为非精确，规避 Android 14 SCHEDULE_EXACT_ALARM 权限门槛）；
//  - 喝水一次性排程 + 链式次日（scheduleWater :162-183、ReminderReceiver
//    :380-383）——M4 已知降级：不做多天链式闹钟，改为每次 App 启动
//    bootstrapReminders→init→sync 重排"当日剩余"（对齐 H5 ensureWaterSchedule
//    自愈 :105/:191-196 的精神；插件自带 ScheduledNotificationBootReceiver 在
//    重启后恢复已排通知，覆盖面更好）。多天不打开 App 则喝水只排当天，
//    登记于 task-6 报告；
//  - id 段：三餐 101-103（mealSlots 表内）、喝水 201+槽位下标
//    （Notify.kt:68 WATER_BASE_ID=201），文案与下标对位（"晚饭后补一杯"
//    永远落在晚间槽位）；
//  - 开关 sg_prefs/reminders_on：:65-66, :92-93（默认 false）。Flutter 侧
//    SharedPreferences 本就是独立 XML 文件，键名 `sg_reminders_on` =
//    H5 "文件 sg_prefs + 键 reminders_on" 的语义拼接对齐；
//  - 测试按钮发真实文案（Notify.kt:95-96 sampleWaterText、:415-421
//    testWaterReminder 语义），不是占位假文案。
//
// 插件 API 核对记录（铁律：只信安装源。flutter_local_notifications 22.3.1，
// 逐文件读 pub.flutter-io.cn 缓存）：
//  - initialize({required InitializationSettings settings, onDidReceive…})：
//    lib/src/flutter_local_notifications_plugin.dart :111（命名参数 settings）；
//  - zonedSchedule({required id, required TZDateTime scheduledDate, required
//    NotificationDetails, required AndroidScheduleMode, title, body,
//    matchDateTimeComponents})：同文件 :409-494。17.x 的
//    uiLocalNotificationDateInterpretation 参数在 22.x **已删除**；
//  - TZDateTime 必需 → timezone 包（插件传递依赖，本文件直接 import 故在
//    pubspec 显式声明）。**无需 flutter_timezone**：原生用
//    ZoneId.of(timeZoneName)（android/…/FlutterLocalNotificationsPlugin.java
//    :622,:1372）解析时区名，故用「设备当前 UTC 偏移」构造固定偏移 Location
//    （名如 GMT+08:00，ZoneId.of 合法）。前提与 domain/dates.dart 一致：
//    运行地中国无夏令时，固定偏移即真本地时区；
//  - AndroidScheduleMode.inexactAllowWhileIdle → 原生
//    AlarmManagerCompat.setAndAllowWhileIdle（非精确，不触
//    checkCanScheduleExactAlarms，同文件 :753-793）；每日重复由插件在每次
//    触发后自行续排（ScheduledNotificationReceiver →
//    scheduleNextNotification，重复语义不依赖 setInexactRepeating 分支）；
//  - Importance.high 的 value=4 即 NotificationManager.IMPORTANCE_HIGH
//    （安装源 android/enums.dart :158-165 逐字对应文档；简报注"=max"与
//    安装源不符——max=5 是 IMPORTANCE_MAX，按源用 high）；
//  - AndroidManifest 必配（README「AndroidManifest.xml setup」：16+ 起插件
//    只自带 POST_NOTIFICATIONS/VIBRATE）：RECEIVE_BOOT_COMPLETED +
//    ScheduledNotificationReceiver/ScheduledNotificationBootReceiver
//    （exported=false，Android 14 的 RECEIVER_EXPORTED 门禁对 manifest 声明
//    的私有 receiver 以 exported="false" 显式满足）。全 inexact，因此**不**
//    声明 SCHEDULE_EXACT_ALARM/USE_EXACT_ALARM。
//
// 分层：AndroidNotificationPort 是全工程**唯一** import 插件处；
// ReminderScheduler 只依赖 NotificationPort 抽象（测试注入 FakePort）。
// domain 规则层不在此重复实现——一切时刻/文案来自 reminders.dart（T5）。

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../domain/reminders.dart';

/// 喝水通知 id 基座（Notify.kt:68 WATER_BASE_ID）；id = 201 + 槽位原始下标。
const int waterBaseId = 201;

/// 喝水通知标题（Notify.kt:200 waterPending putExtra("title","喝水提醒")）。
const String waterTitle = '喝水提醒';

/// 开关持久化键。H5 为 sg_prefs 文件 + reminders_on 键（Notify.kt:65-66）；
/// Flutter SharedPreferences 独立文件，键名拼接对齐语义，注释登记（T6 简报）。
const String remindersOnPrefKey = 'sg_reminders_on';

/// 通知调度端口（抽象隔离插件；测试用 FakePort 记录调用，不 mock 插件本体）。
abstract class NotificationPort {
  /// 初始化：插件 initialize + 创建 sg_reminder 渠道 + Android 13+ 通知权限请求。
  Future<void> init();

  /// 每日重复：每天 hour:minute 发一条（非精确面，inexactAllowWhileIdle）。
  Future<void> periodDaily({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
  });

  /// 一次性：[scheduledDate]（本地墙钟）时刻发一条，调用方保证为未来。
  Future<void> at({
    required int id,
    required DateTime scheduledDate,
    required String title,
    required String body,
  });

  /// 立刻发一条（测试按钮：真实文案预览，对齐 Notify.kt:410-421）。
  Future<void> show({
    required int id,
    required String title,
    required String body,
  });

  /// 取消全部已排 + 已显示（sync(on:false) 面；22.x cancelAll 文档 :365 覆盖
  /// scheduled 与 presented 两类，等价 Kotlin cancel()+cancelWater() 全撤）。
  Future<void> cancelAll();
}

/// 提醒调度器：规则消费 T5 纯函数，动作全部经 [NotificationPort]。
class ReminderScheduler {
  ReminderScheduler({required this.port, DateTime Function()? now})
      : _now = now ?? DateTime.now;

  final NotificationPort port;
  final DateTime Function() _now;

  bool _inited = false;
  int _waterCursor = 0;

  /// 幂等：只有第一次真正调 port.init()。
  Future<void> init() async {
    if (_inited) return;
    await port.init();
    _inited = true;
  }

  /// 开关联动排程（Notify.kt setEnabled :98-108 的 schedule/cancel 两面）。
  /// on=true：三餐 3 条 periodDaily + 喝水 waterPlanFrom(now) 计划 at()，
  /// 时刻整体锚 plan.targetDay（今日后缀→今日；滚日全量→明天）；
  /// on=false：cancelAll。
  ///
  /// 重排不撤旧：同 id 的 zonedSchedule 在原生以 requestCode=id 的
  /// PendingIntent FLAG_UPDATE_CURRENT 覆盖旧闹钟（README/原生
  /// getBroadcastPendingIntent），与 Kotlin scheduleWater 先 cancel 8 条再排
  /// 等效；喝水下标具后缀性（槽位时刻严格递增），旧日"漏网"pending 必已过期
  /// 触发或被覆盖，无残留面。
  Future<void> sync({required bool on}) async {
    await init();
    if (!on) {
      await port.cancelAll();
      return;
    }
    for (final (h, m, id, title, body) in mealSlots) {
      await port.periodDaily(
          id: id, hour: h, minute: m, title: title, body: body);
    }
    final now = _now();
    bool isFuture(int h, int m) =>
        _todayAt(now, h, m).isAfter(now);
    final plan = waterPlanFrom(now, isFuture: isFuture);
    // waterPlanFrom 连同**目标日**返回：当日过滤后的后缀（targetDay=今日）
    // 或次日全量（targetDay=明日，T5 语义）。全部槽位统一按 targetDay 的
    // h:m 锚定，等价 Kotlin scheduleWater 的 slotTime(target, h, m)
    // （Notify.kt:169-171 滚日分支 target=明天）——**不能**逐条 _nextAt 按
    // 钟点判日：滚日后钟点晚于 now 的槽会被错锚回今天，今晚提前响、明天丢。
    // 后缀起始下标 = waterCount - plan.slots.length，据此保持 id/文案与
    // "一天中第几段"对位（Kotlin scheduleWater entry.index，:173-179）。
    final day = plan.targetDay;
    final firstIndex = waterCount - plan.slots.length;
    for (var i = 0; i < plan.slots.length; i++) {
      final (h, m) = plan.slots[i];
      final idx = firstIndex + i;
      await port.at(
        id: waterBaseId + idx,
        scheduledDate: DateTime(day.year, day.month, day.day, h, m),
        title: waterTitle,
        body: waterTexts[idx],
      );
    }
  }

  /// 开关状态（默认关，对齐 Notify.kt:92-93 getBoolean(KEY_ON, false)）。
  Future<bool> enabled() async =>
      (await SharedPreferences.getInstance()).getBool(remindersOnPrefKey) ??
      false;

  /// 写偏好 + 立即联动排程/撤销（setEnabled :98-108 同构）。
  Future<void> setEnabled(bool on) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(remindersOnPrefKey, on);
    await sync(on: on);
  }

  /// 测试按钮·三餐：立即发一条**真实**提醒（取当前时刻之后最近的一条
  /// mealSlots；全过则自然轮到明早——按"下次触发最近"判定，无"全过"态）。
  Future<void> testMeal() async {
    await init();
    final now = _now();
    final slot = mealSlots.reduce(
        (a, b) => _nextAt(now, a.$1, a.$2).isBefore(_nextAt(now, b.$1, b.$2)) ? a : b);
    await port.show(id: slot.$3, title: slot.$4, body: slot.$5);
  }

  /// 测试按钮·喝水：立即发一条真实喝水文案，轮询推进（比 Kotlin
  /// sampleWaterText 恒取首条略进一步：8 条都能被验到；语义同为
  /// "测试发出的通知与到点通知完全一致"，Notify.kt:95 注释）。
  Future<void> testWater() async {
    await init();
    final idx = _waterCursor % waterCount;
    _waterCursor++;
    await port.show(
        id: waterBaseId + idx, title: waterTitle, body: waterTexts[idx]);
  }

  // ---- 时刻工具（本地墙钟，端口内再转 TZDateTime） ----

  static DateTime _todayAt(DateTime now, int h, int m) =>
      DateTime(now.year, now.month, now.day, h, m);

  /// hh:mm 的下一次到达（今日未到则今日，秒/毫秒清零；已过滚明日）。
  static DateTime _nextAt(DateTime now, int h, int m) {
    final t = _todayAt(now, h, m);
    return t.isAfter(now) ? t : t.add(const Duration(days: 1));
  }
}

/// 真实端口：全工程唯一 import flutter_local_notifications 处。
class AndroidNotificationPort implements NotificationPort {
  static const _channelId = 'sg_reminder';
  static const _channelName = '饮食提醒';
  static const _channelDescription = '三餐/喝水提醒，横幅弹出';

  static const _androidDetails = AndroidNotificationDetails(
    _channelId,
    _channelName,
    channelDescription: _channelDescription,
    // 安装源核对：Importance.high(value=4)≙IMPORTANCE_HIGH（enums.dart :161
    // 文档逐字）；Kotlin Notify.kt:29 正是 IMPORTANCE_HIGH。
    importance: Importance.high,
    priority: Priority.high,
    enableVibration: true, // Notify.kt:31 ch.enableVibration(true)
  );

  static const _details = NotificationDetails(android: _androidDetails);

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  @override
  Future<void> init() async {
    _ensureLocalLocation();
    await _plugin.initialize(
      settings: const InitializationSettings(
        // 对齐 H5 Notify.post 的 R.mipmap.ic_launcher（Flutter 模板同名资源）
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    final android = _plugin
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    // 渠道显式建一次（Kotlin ensureChannel :25-35 语义）；zonedSchedule/show
    // 的 channelAction=createIfNotExists 仍是兜底。
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.high,
      enableVibration: true,
    ));
    // Android 13+ POST_NOTIFICATIONS 运行时权限（简报 Step 3 指定经
    // permission_handler）。拒绝**不抛**：对齐 H5 Notify.post 捕
    // SecurityException 静默跳过（:55-59）——偏好仍可保存，提醒仍可排。
    await Permission.notification.request();
  }

  @override
  Future<void> periodDaily({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    final now = DateTime.now();
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: _tzAt(ReminderScheduler._nextAt(now, hour, minute)),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  @override
  Future<void> at({
    required int id,
    required DateTime scheduledDate,
    required String title,
    required String body,
  }) async {
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: _tzAt(scheduledDate),
      notificationDetails: _details,
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
    );
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) =>
      _plugin.show(id: id, title: title, body: body, notificationDetails: _details);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  /// 本地墙钟 DateTime → 设备偏移固定时区的 TZDateTime（按字段重建，不换算
  /// 瞬间；22.x 原生以「墙钟 + timeZoneName」还原触发时刻，见文件头核对）。
  static tz.TZDateTime _tzAt(DateTime wallClock) => tz.TZDateTime(
      tz.local,
      wallClock.year,
      wallClock.month,
      wallClock.day,
      wallClock.hour,
      wallClock.minute,
      wallClock.second);

  bool _tzReady = false;
  /// 只构造「设备 UTC 偏移」固定时区的 local Location，**不加载 tzdb**
  /// （评审 M-a：原 import data/latest_all.dart 全量库纯属浪费）。依据
  /// （安装源核对，timezone 0.11.1 + 插件 22.3.1）：插件 Dart 面对排程只做
  /// tz_datetime_mapper.dart 的字段序列化（timeZoneName=location.name +
  /// 墙钟/ISO 串），Android 端恢复/每日续排在原生以 ZoneId.of(name) 还原；
  /// 插件 lib 全目录 grep 无任何 tz.getLocation/initializeTimeZones 依赖，
  /// 本文件也只用自定义 Location 构造 TZDateTime → zonedSchedule 不需要
  /// tz 数据库，省去数 MB tzdb 资源。
  void _ensureLocalLocation() {
    if (_tzReady) return;
    final offset = DateTime.now().timeZoneOffset; // 设备当前 UTC 偏移
    final abs = offset.abs();
    String two(int n) => n.toString().padLeft(2, '0');
    final name =
        'GMT${offset.isNegative ? '-' : '+'}${two(abs.inHours)}:${two(abs.inMinutes % 60)}';
    // 唯一过渡点覆盖全 epoch 的固定偏移（评审 M-c：与 timezone 包
    // src/env.dart `_utc` 同款形制 Location(name, [minTime], [0], [zone])，
    // 原用 [0] 使 1970 前落不进缓存段——本域全未来日期虽无实际影响，仍对齐）。
    // 中国无夏令时前提见文件头。
    tz.setLocalLocation(tz.Location(
        name, const [tz.minTime], const [0], [tz.TimeZone(offset, isDst: false, abbreviation: name)]));
    _tzReady = true;
  }
}

// ===== Provider（组合根模式：T7 测试 override notificationPortProvider）=====

final notificationPortProvider =
    Provider<NotificationPort>((ref) => AndroidNotificationPort());

final reminderSchedulerProvider = Provider<ReminderScheduler>(
    (ref) => ReminderScheduler(port: ref.watch(notificationPortProvider)));
