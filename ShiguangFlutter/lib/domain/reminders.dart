// ShiguangFlutter/lib/domain/reminders.dart
// 提醒规则纯函数：三餐槽位表 + 喝水「日期种子分层随机」。
// 权威源：HealthyDiet/app/src/main/java/com/healthydiet/app/Notify.kt
//   常量 WATER_COUNT/START/END：:69-71；三餐 PLAN：:73-79；喝水文案 WATER_TEXTS：:81-90；
//   waterSlots：:151-159；scheduleWater「只留未来项，全过滚次日」语义：:162-172。
// 裁定 R3：H5 用 java.util.Random(seed)，Dart 无法逐位复现也无需复现（通知时刻不是数据
//   契约）。移植的是分布规则——16h 切 8 段、段内随机、两端各留 5 分钟 guard band、
//   日期种子确定性；随机源换 dart:math 的 Random(seed)。
// 本文件只做纯规则；闹钟/通知调度接线在 T6（flutter_local_notifications），不在此处。
// 分层铁律：本文件不得 import package:flutter。
import 'dart:math';

/// 三餐定点槽位 (hour, minute, 通知id, 标题, 正文)——逐字抄 Notify.kt:76-78。
const List<(int, int, int, String, String)> mealSlots = [
  (8, 0, 101, '早餐提醒', '吃早餐了吗？点开记一笔，牛奶面包肉包都在食物库'),
  (12, 0, 102, '午餐提醒', '记录午餐，看看今天的热量缺口还剩多少'),
  (18, 30, 103, '晚餐提醒', '记录晚餐，收个尾看看今日营养达标情况'),
];

/// 喝水提醒文案，按槽位下标取用——逐字抄 Notify.kt:82-89（共 8 条）。
/// 通知 id = WATER_BASE_ID(201, Notify.kt:68) + 下标，即 201..208；id 拼接属调度侧（T6）。
const List<String> waterTexts = [
  '该喝水了：来一杯 200ml，点首页水杯打卡',
  '补水时间到：久坐之余起身接杯水吧',
  '喝水提醒：别等渴了才喝，小口慢喝',
  '来杯 200ml 水，顺便活动一下肩颈',
  '喝水提醒：看看今天的水杯进度条',
  '补水时间：下午来一杯，精神更好',
  '喝水提醒：晚饭后也记得补一杯',
  '今天最后一杯水：小口喝完就打卡收工',
];

/// 每日喝水提醒次数（Notify.kt:69 WATER_COUNT）
const int waterCount = 8;

/// 窗口起点：8:00 的当日分钟数（Notify.kt:70 WATER_START_MIN）
const int waterStartMin = 8 * 60;

/// 窗口终点：24:00 的当日分钟数（Notify.kt:71 WATER_END_MIN）
const int waterEndMin = 24 * 60;

/// 一年中的第几天，1 基（1 月 1 日 = 1），与 Java Calendar.DAY_OF_YEAR 对齐。
/// Dart DateTime 无原生 dayOfYear；只减本地日历日零点，不跨 UTC 切片
/// （与 dates.dart 同一「本地时区安全」前提，本工程运行地中国无夏令时）。
int dayOfYear(DateTime d) => d.difference(DateTime(d.year, 1, 1)).inDays + 1;

/// 按日期做种子的分层随机（Notify.kt:151-159）：把 8:00–24:00 切 8 段，
/// 每段内随机取一点（两端各留 5 分钟 guard band）→ 每天时刻不同且分布均匀。
/// 只取 year 与 dayOfYear 参与种子，同一天内任何时刻调用结果一致。
List<(int, int)> waterSlots(DateTime day) {
  // Notify.kt:152-153 key = year*1000 + DAY_OF_YEAR；种子 = key * 1000003
  // （最大值约 2.03e12，远小于 int 范围，亦小于 JS 安全整数 2^53）
  final key = day.year * 1000 + dayOfYear(day);
  final rnd = Random(key * 1000003);
  const stratum = (waterEndMin - waterStartMin) ~/ waterCount; // 120 分钟/段
  return List<(int, int)>.generate(waterCount, (i) {
    // Notify.kt:156：段首 + 5 分 guard + 段内随机（nextInt(110) → 0..109，上沿 +114）
    final m = waterStartMin + i * stratum + 5 + rnd.nextInt(stratum - 10);
    return (m ~/ 60, m % 60); // Notify.kt:157
  });
}

/// 某刻之后的喝水计划 + **目标日锚**（Notify.kt:162-172 scheduleWater 的纯规则
/// 部分）：只保留 isFuture 判真的当日槽位（targetDay=当日）；全过则滚到次日
/// 完整 8 项（targetDay=次日，次日不再过滤，对齐 Kotlin :169-171 —— 滚动分支
/// 直接取 waterSlots(次日) 全量）。
/// targetDay 随计划一并返回：调度侧（T6）对全部槽位统一用
/// DateTime(targetDay.y, m, d, h, mi) 锚定——等价 Kotlin slotTime(target, h, m)
/// （target 在滚日分支为明天）。不得由调度侧逐条按"钟点是否晚于 now"判日，
/// 否则滚日后钟点晚于 now 的槽会被错锚回今天（终审 Important 缺陷）。
/// isFuture 注入而非读时钟，保持 domain 纯函数可测；调度接线（T6）传真实比较。
({DateTime targetDay, List<(int, int)> slots}) waterPlanFrom(DateTime now, {
  required bool Function(int hour, int minute) isFuture,
}) {
  final remaining =
      waterSlots(now).where((s) => isFuture(s.$1, s.$2)).toList();
  if (remaining.isNotEmpty) return (targetDay: now, slots: remaining);
  // 全过：滚次日，整体锚明天（DateTime 日进位自动处理月末/年末）
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  return (targetDay: tomorrow, slots: waterSlots(tomorrow));
}
