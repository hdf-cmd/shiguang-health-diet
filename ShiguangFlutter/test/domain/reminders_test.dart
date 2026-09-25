// ShiguangFlutter/test/domain/reminders_test.dart
// 提醒规则纯函数测试。权威源：HealthyDiet/.../Notify.kt（:69-71 常量、:75-79 三餐、
// :81-90 喝水文案、:151-159 waterSlots、:162-183 scheduleWater 语义）。
// 裁定 R3：随机源换 Dart，不断具体分钟值，只断窗口/分层带/确定性/异日不同。
import 'package:flutter_test/flutter_test.dart';

import 'package:shiguang_flutter/domain/reminders.dart';

/// 把 (h, m) 折算成当日总分钟，便于断带
int _minOf((int, int) slot) => slot.$1 * 60 + slot.$2;

void main() {
  group('mealSlots（Notify.kt:75-79 逐字）', () {
    test('三条槽位：时刻/id/标题/正文与 Kotlin 逐字一致', () {
      expect(mealSlots, hasLength(3));
      expect(mealSlots[0], (8, 0, 101, '早餐提醒', '吃早餐了吗？点开记一笔，牛奶面包肉包都在食物库'));
      expect(mealSlots[1], (12, 0, 102, '午餐提醒', '记录午餐，看看今天的热量缺口还剩多少'));
      expect(mealSlots[2], (18, 30, 103, '晚餐提醒', '记录晚餐，收个尾看看今日营养达标情况'));
    });
  });

  group('waterTexts（Notify.kt:81-90 逐字）', () {
    test('共 8 条，内容与 WATER_TEXTS 逐字一致', () {
      expect(waterTexts, hasLength(8));
      expect(waterTexts, const [
        '该喝水了：来一杯 200ml，点首页水杯打卡',
        '补水时间到：久坐之余起身接杯水吧',
        '喝水提醒：别等渴了才喝，小口慢喝',
        '来杯 200ml 水，顺便活动一下肩颈',
        '喝水提醒：看看今天的水杯进度条',
        '补水时间：下午来一杯，精神更好',
        '喝水提醒：晚饭后也记得补一杯',
        '今天最后一杯水：小口喝完就打卡收工',
      ]);
    });
  });

  group('waterSlots（Notify.kt:151-159 分布规则，R3：不断具体分钟）', () {
    test('同一天两次调用逐位相等（日期种子确定性）', () {
      final day = DateTime(2026, 9, 25);
      expect(waterSlots(day), waterSlots(day));
    });

    test('只按日期取种：同一天的时刻/秒字段不影响结果', () {
      expect(
        waterSlots(DateTime(2026, 9, 25, 23, 59, 12)),
        waterSlots(DateTime(2026, 9, 25)),
      );
    });

    test('恒 8 项，全部落在 [8:00, 24:00) 窗口内', () {
      for (final day in [
        DateTime(2026, 1, 1),
        DateTime(2026, 2, 28),
        DateTime(2024, 2, 29), // 闰年 dayOfYear=60，key 仍唯一
        DateTime(2026, 9, 25),
        DateTime(2026, 12, 31), // dayOfYear=365，跨年 key 不断档
      ]) {
        final slots = waterSlots(day);
        expect(slots, hasLength(8), reason: '$day');
        for (final s in slots) {
          expect(_minOf(s), inInclusiveRange(8 * 60, 24 * 60 - 1), reason: '$day → $s');
        }
      }
    });

    test('第 i 项落在第 i 分层带 [480+120i+5, 480+120i+114]（段内随机 ±5 分 guard band）', () {
      for (final day in [
        DateTime(2025, 3, 14),
        DateTime(2026, 9, 25),
        DateTime(2027, 7, 1),
      ]) {
        final slots = waterSlots(day);
        for (var i = 0; i < 8; i++) {
          expect(
            _minOf(slots[i]),
            inInclusiveRange(480 + 120 * i + 5, 480 + 120 * i + 114),
            reason: '$day 第 $i 段越界：$slots',
          );
        }
      }
    });

    test('不同日期大概率产出不同序列（多样本，至少一项不同）', () {
      final days = [
        DateTime(2026, 1, 1),
        DateTime(2026, 1, 2),
        DateTime(2026, 3, 9),
        DateTime(2026, 6, 21),
        DateTime(2026, 9, 25),
        DateTime(2026, 12, 31),
        DateTime(2027, 1, 1), // 与 2026-12-31 相邻：验证 year*1000+dayOfYear 跨年后种子变化
      ];
      for (var a = 0; a < days.length; a++) {
        for (var b = a + 1; b < days.length; b++) {
          expect(
            waterSlots(days[a]),
            isNot(waterSlots(days[b])),
            reason: '${days[a]} 与 ${days[b]} 产出完全相同，种子疑似未生效',
          );
        }
      }
    });
  });

  group('waterPlanFrom（Notify.kt:162-172 语义：只留未来项，全过滚次日）', () {
    bool Function(int, int) afterClock(DateTime now) =>
        (h, m) => DateTime(now.year, now.month, now.day, h, m).isAfter(now);

    test('07:00 起点：8 项全留，等于当日 waterSlots', () {
      final now = DateTime(2026, 9, 25, 7, 0);
      expect(waterPlanFrom(now, isFuture: afterClock(now)), waterSlots(now));
    });

    test('23:59 起点：全部已过 → 滚次日，等于次日 waterSlots 完整 8 项', () {
      final now = DateTime(2026, 9, 25, 23, 59);
      final tomorrow = DateTime(2026, 9, 26);
      final plan = waterPlanFrom(now, isFuture: afterClock(now));
      expect(plan, hasLength(8));
      expect(plan, waterSlots(tomorrow));
    });

    test('10:00 起点：第 0 段（最迟 9:54）必已过，第 1..7 段（最早 10:05）必保留 → 恰好 7 项', () {
      final now = DateTime(2026, 9, 25, 10, 0);
      final plan = waterPlanFrom(now, isFuture: afterClock(now));
      final all = waterSlots(now);
      expect(plan, hasLength(7));
      expect(plan, all.sublist(1));
    });

    test('滚次日时用的是次日的日期种子（不是当日重排）', () {
      // 只要两日序列不同（前面已断言种子按日期变化），滚次日的结果就必须等于次日而非当日
      final now = DateTime(2026, 9, 25, 23, 59);
      final plan = waterPlanFrom(now, isFuture: afterClock(now));
      expect(plan, isNot(waterSlots(DateTime(2026, 9, 25))));
    });
  });
}
