// ShiguangFlutter/test/reminder_scheduler_test.dart
// M4-T6 提醒调度接线单测：ReminderScheduler × FakePort（不 mock 插件本体）。
// 断言面：
//  - sync(on:true) → 3 条 periodDaily（id/时刻/文案逐字对 domain mealSlots）
//    + 喝水 at()（id=201+原始槽位下标，文案=waterTexts[同下标]，时刻严格未来）；
//  - 当日全过 → 滚次日 8 项（Kotlin scheduleWater :169-171 语义）；
//  - sync(on:false) → cancelAll；
//  - enabled/setEnabled ↔ SharedPreferences `sg_reminders_on` 往返；
//  - 测试按钮走真实文案（testMeal 取近未来一条 / testWater 轮询 waterTexts）；
//  - init 幂等。
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:shiguang_flutter/domain/reminders.dart';
import 'package:shiguang_flutter/features/notifications/reminder_scheduler.dart';

class FakePort implements NotificationPort {
  int initCalls = 0;
  int cancelAllCalls = 0;
  final List<
      ({int id, int hour, int minute, String title, String body})> daily = [];
  final List<({int id, DateTime scheduledDate, String title, String body})>
      atCalls = [];
  final List<({int id, String title, String body})> shown = [];

  @override
  Future<void> init() async => initCalls++;
  @override
  Future<void> periodDaily({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async =>
      daily.add((id: id, hour: hour, minute: minute, title: title, body: body));
  @override
  Future<void> at({
    required int id,
    required DateTime scheduledDate,
    required String title,
    required String body,
  }) async =>
      atCalls.add(
          (id: id, scheduledDate: scheduledDate, title: title, body: body));
  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
  }) async =>
      shown.add((id: id, title: title, body: body));
  @override
  Future<void> cancelAll() async => cancelAllCalls++;
}

void main() {
  late FakePort port;

  setUp(() {
    port = FakePort();
    SharedPreferences.setMockInitialValues({});
  });

  group('ReminderScheduler.init', () {
    test('幂等：多次 init 只透传一次', () async {
      final s = ReminderScheduler(port: port);
      await s.init();
      await s.init();
      expect(port.initCalls, 1);
    });

    test('sync 前自动 init（渠道/权限就位）', () async {
      final s = ReminderScheduler(port: port, now: () => DateTime(2026, 9, 25, 7));
      await s.sync(on: true);
      expect(port.initCalls, 1);
    });
  });

  group('sync(on:true) 三餐', () {
    test('3 条 periodDaily，id/时刻/标题/正文逐字等于 mealSlots', () async {
      final s = ReminderScheduler(
          port: port, now: () => DateTime(2026, 9, 25, 7));
      await s.sync(on: true);
      expect(port.daily.length, 3);
      for (var i = 0; i < mealSlots.length; i++) {
        final (h, m, id, title, body) = mealSlots[i];
        expect(port.daily[i].id, id);
        expect(port.daily[i].hour, h);
        expect(port.daily[i].minute, m);
        expect(port.daily[i].title, title);
        expect(port.daily[i].body, body);
      }
      expect(port.daily.map((e) => e.id), [101, 102, 103]);
    });
  });

  group('sync(on:true) 喝水', () {
    test('早 7 点：当日 8 项全排，id 201..208，文案对位，时刻为当日未来', () async {
      final now = DateTime(2026, 9, 25, 7);
      final s = ReminderScheduler(port: port, now: () => now);
      await s.sync(on: true);
      final water = port.atCalls;
      expect(water.length, 8);
      final slots = waterSlots(now);
      for (var i = 0; i < 8; i++) {
        expect(water[i].id, 201 + i);
        expect(water[i].title, '喝水提醒');
        expect(water[i].body, waterTexts[i]);
        expect(water[i].scheduledDate,
            DateTime(2026, 9, 25, slots[i].$1, slots[i].$2));
        expect(water[i].scheduledDate.isAfter(now), isTrue);
      }
    });

    test('23:59 全过：滚次日整 8 项（Kotlin :169-171）', () async {
      final now = DateTime(2026, 9, 25, 23, 59);
      final s = ReminderScheduler(port: port, now: () => now);
      await s.sync(on: true);
      final water = port.atCalls;
      expect(water.length, 8);
      final tomorrow = waterSlots(DateTime(2026, 9, 26));
      for (var i = 0; i < 8; i++) {
        expect(water[i].id, 201 + i);
        expect(water[i].body, waterTexts[i]);
        expect(water[i].scheduledDate,
            DateTime(2026, 9, 26, tomorrow[i].$1, tomorrow[i].$2));
      }
    });

    test('下午中间时刻：只排未来项且 id/文案保持“原始下标”对齐（后缀性）', () async {
      final now = DateTime(2026, 9, 25, 15);
      final s = ReminderScheduler(port: port, now: () => now);
      await s.sync(on: true);
      final today = waterSlots(now);
      final expected = <int>[
        for (var i = 0; i < today.length; i++)
          if (DateTime(now.year, now.month, now.day, today[i].$1, today[i].$2)
              .isAfter(now))
          i
      ];
      final water = port.atCalls;
      expect(water.length, expected.length);
      for (var k = 0; k < expected.length; k++) {
        final i = expected[k];
        expect(water[k].id, 201 + i, reason: '第 $k 项应保留原始槽位下标 $i');
        expect(water[k].body, waterTexts[i]);
        expect(water[k].scheduledDate,
            DateTime(now.year, now.month, now.day, today[i].$1, today[i].$2));
      }
    });

    test('waterPlanFrom 与自算计划一致（消费 T5 规则不另起炉灶）', () async {
      final now = DateTime(2026, 9, 25, 15);
      final s = ReminderScheduler(port: port, now: () => now);
      await s.sync(on: true);
      final plan = waterPlanFrom(
        now,
        isFuture: (h, m) =>
            DateTime(now.year, now.month, now.day, h, m).isAfter(now),
      );
      expect(port.atCalls.length, plan.length);
      expect(port.atCalls.map((e) => (e.scheduledDate.hour, e.scheduledDate.minute)),
          plan);
    });
  });

  group('sync(on:false)', () {
    test('cancelAll 一次，不排任何闹钟', () async {
      final s = ReminderScheduler(
          port: port, now: () => DateTime(2026, 9, 25, 7));
      await s.sync(on: false);
      expect(port.cancelAllCalls, 1);
      expect(port.daily, isEmpty);
      expect(port.atCalls, isEmpty);
    });
  });

  group('开关持久化 sg_reminders_on', () {
    test('默认 false', () async {
      final s = ReminderScheduler(port: port);
      expect(await s.enabled(), isFalse);
    });

    test('setEnabled 往返：落盘 + 联动 sync；重启读回 true', () async {
      DateTime now() => DateTime(2026, 9, 25, 7);
      final s = ReminderScheduler(port: port, now: now);
      await s.setEnabled(true);
      expect(await s.enabled(), isTrue);
      expect(port.daily.length, 3);
      expect(port.atCalls.length, 8);
      // 模拟"重启"：新实例读同一 SharedPreferences
      final s2 = ReminderScheduler(port: FakePort(), now: now);
      expect(await s2.enabled(), isTrue);
      await s.setEnabled(false);
      expect(await s.enabled(), isFalse);
      expect(port.cancelAllCalls, 1);
    });

    test('键名与 H5 sg_prefs/reminders_on 语义对齐（独立文件不冲突）', () async {
      final s = ReminderScheduler(port: port);
      await s.setEnabled(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('sg_reminders_on'), isTrue);
    });
  });

  group('测试按钮（真实文案，对齐 Notify.kt:95 语义）', () {
    test('testMeal：早 7 点取早餐条；13 点取近未来晚餐条', () async {
      final s = ReminderScheduler(
          port: port, now: () => DateTime(2026, 9, 25, 7));
      await s.testMeal();
      expect(port.shown.length, 1);
      expect(port.shown.first.title, '早餐提醒');
      expect(port.shown.first.body, mealSlots[0].$5);

      final s2 = ReminderScheduler(
          port: FakePort(), now: () => DateTime(2026, 9, 25, 13));
      await s2.testMeal();
      // 13:00 后最近的是 18:30 晚餐（早餐要等 19h）
      expect(port.shown.length, 1); // 第一个 port 未被复用
      final shown2 = (s2.port as FakePort).shown;
      expect(shown2.first.title, '晚餐提醒');
      expect(shown2.first.body, mealSlots[2].$5);
    });

    test('testWater：轮询 waterTexts，文案互不重复且都在表内', () async {
      final s = ReminderScheduler(port: port);
      await s.testWater();
      await s.testWater();
      expect(port.shown.length, 2);
      expect(waterTexts, contains(port.shown[0].body));
      expect(waterTexts, contains(port.shown[1].body));
      expect(port.shown[0].body, isNot(port.shown[1].body));
      final i0 = waterTexts.indexOf(port.shown[0].body);
      final i1 = waterTexts.indexOf(port.shown[1].body);
      expect(i1, (i0 + 1) % waterCount);
      expect(port.shown.first.title, '喝水提醒');
    });
  });
}
