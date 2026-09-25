// ShiguangFlutter/test/profile_reminders_test.dart
// M4 Task 7：「我的」页提醒开关区（消息提醒卡）。
// 文案权威源 H5：index.html:227-237（卡标题「消息提醒 · 系统通知」、副文案、
// 两按钮「发一条测试通知」「发一条喝水到点提醒（测试）」、switch aria-label
// 「消息提醒」）、js/app.js:1043-1059（开/关 toast 与测试按钮 toast 文案）。
// 依赖面：只消费 T6 ReminderScheduler 的 enabled/setEnabled/testMeal/testWater
// （setEnabled 已联动 sync，UI 不再补 sync 调用——现码 reminder_scheduler.dart:179-183 核实）。
// 注入方式：override reminderSchedulerProvider 为 FakeScheduler（记录调用/可抛），
// 零插件零 SharedPreferences。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider;
import 'package:shiguang_flutter/features/notifications/reminder_scheduler.dart';
import 'package:shiguang_flutter/features/profile/profile_screen.dart'
    show ProfileScreen;
import 'package:shiguang_flutter/features/scale/scale_service.dart';

import 'harness.dart';
import 'scale_fakes.dart';
import 'stubs/stub_health_api.dart';

/// 端口占位：FakeScheduler 覆写了全部会触端口的方法，这里只需满足构造。
class _NullPort implements NotificationPort {
  @override
  Future<void> init() async {}
  @override
  Future<void> periodDaily(
          {required int id,
          required int hour,
          required int minute,
          required String title,
          required String body}) async =>
      throw UnimplementedError();
  @override
  Future<void> at(
          {required int id,
          required DateTime scheduledDate,
          required String title,
          required String body}) async =>
      throw UnimplementedError();
  @override
  Future<void> show(
          {required int id,
          required String title,
          required String body}) async =>
      throw UnimplementedError();
  @override
  Future<void> cancelAll() async => throw UnimplementedError();
}

/// 记录型调度器：覆写 UI 消费的四个方法，不触碰 sync/端口/偏好。
class FakeScheduler extends ReminderScheduler {
  FakeScheduler({bool enabledValue = false})
      : _enabled = enabledValue,
        super(port: _NullPort());

  bool _enabled;
  final List<bool> setEnabledCalls = [];
  int testMealCalls = 0;
  int testWaterCalls = 0;
  bool throwOnEnabled = false;
  bool throwOnSetEnabled = false;
  bool throwOnTest = false;

  @override
  Future<bool> enabled() async {
    if (throwOnEnabled) throw Exception('boom');
    return _enabled;
  }

  @override
  Future<void> setEnabled(bool on) async {
    if (throwOnSetEnabled) throw Exception('boom');
    setEnabledCalls.add(on);
    _enabled = on; // 真调度器同为「落盘 + 联动 sync」，状态随调用更新
  }

  @override
  Future<void> testMeal() async {
    if (throwOnTest) throw Exception('boom');
    testMealCalls++;
  }

  @override
  Future<void> testWater() async {
    if (throwOnTest) throw Exception('boom');
    testWaterCalls++;
  }
}

Future<({ProviderContainer container, FakeScheduler scheduler})> pumpProfile(
  WidgetTester tester,
  FakeScheduler scheduler,
) async {
  await useBigSurface(tester);
  final container = ProviderContainer(
    overrides: [
      healthApiProvider
          .overrideWithValue(StubHealthApi(bodyMetrics: const {'weightKg': 60})),
      reminderSchedulerProvider.overrideWithValue(scheduler),
      scaleServiceProvider.overrideWithValue(
          ScaleService(FakeTransport(),
              scanTimeout: const Duration(milliseconds: 300),
              readTimeout: const Duration(milliseconds: 1500))),
    ],
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: ProfileScreen()),
  ));
  await tester.pumpAndSettle();
  return (container: container, scheduler: scheduler);
}

bool switchValue(WidgetTester tester) =>
    tester.widget<Switch>(find.byType(Switch)).value;

void main() {
  /* ---------- ① 卡渲染 + 初值来自 enabled() ---------- */

  testWidgets('①消息提醒卡：标题/副文案/两按钮文案逐字（index.html:227-236），Switch 初值=enabled()=true',
      (tester) async {
    await pumpProfile(tester, FakeScheduler(enabledValue: true));

    expect(find.text('消息提醒 · 系统通知'), findsOneWidget); // index.html:230 逐字
    expect(find.text('三餐定点 8:00/12:00/18:30 + 喝水每天 8 次随机（8:00–24:00），横幅弹出'),
        findsOneWidget); // index.html:231 逐字
    expect(find.text('发一条测试通知'), findsOneWidget); // index.html:235 逐字
    expect(find.text('发一条喝水到点提醒（测试）'), findsOneWidget); // index.html:236 逐字
    expect(switchValue(tester), isTrue); // 初值取自 scheduler.enabled()
  });

  testWidgets('①b enabled()=false → Switch 初值关', (tester) async {
    await pumpProfile(tester, FakeScheduler(enabledValue: false));
    expect(switchValue(tester), isFalse);
  });

  /* ---------- ② 切换 → setEnabled 收到新值（联动 sync 由 T6 内部保证） ---------- */

  testWidgets('②开→关→开：setEnabled 依次收到 false/true，toast 文案逐字（app.js:1048）',
      (tester) async {
    final fake = FakeScheduler(enabledValue: true);
    await pumpProfile(tester, fake);

    await tester.tap(find.byType(Switch)); // 开 → 关
    await tester.pumpAndSettle();
    expect(fake.setEnabledCalls, [false]);
    expect(switchValue(tester), isFalse);
    expect(find.text('提醒已关闭'), findsOneWidget); // app.js:1048 逐字

    await tester.tap(find.byType(Switch)); // 关 → 开
    await tester.pumpAndSettle();
    expect(fake.setEnabledCalls, [false, true]);
    expect(switchValue(tester), isTrue);
    expect(find.text('提醒已开启：每天定点弹系统通知'), findsOneWidget); // 逐字
  });

  /* ---------- ③ 测试按钮各触发一次 ---------- */

  testWidgets('③点「发一条测试通知」→ testMeal 恰一次 + toast（app.js:1051 逐字）',
      (tester) async {
    final fake = FakeScheduler();
    await pumpProfile(tester, fake);

    await tester.tap(find.text('发一条测试通知'));
    await tester.pumpAndSettle();
    expect(fake.testMealCalls, 1);
    expect(fake.testWaterCalls, 0); // 不串线
    expect(find.text('测试通知已发，看通知栏'), findsOneWidget);
  });

  testWidgets('③b点「发一条喝水到点提醒（测试）」→ testWater 恰一次 + 已发出 toast',
      (tester) async {
    final fake = FakeScheduler();
    await pumpProfile(tester, fake);

    await tester.tap(find.text('发一条喝水到点提醒（测试）'));
    await tester.pumpAndSettle();
    expect(fake.testWaterCalls, 1);
    expect(fake.testMealCalls, 0);
    expect(find.text('已发出：看通知栏'), findsOneWidget); // H5「胶囊/通知栏」去胶囊（Flutter 无灵动岛，报告登记）
  });

  /* ---------- ④ 失败路径：toast 错误、不崩、开关回弹 ---------- */

  testWidgets('④setEnabled 抛异常 → toast 失败、开关回弹到原值、App 不崩',
      (tester) async {
    final fake = FakeScheduler(enabledValue: true)..throwOnSetEnabled = true;
    await pumpProfile(tester, fake);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('提醒开关设置失败'), findsOneWidget);
    expect(switchValue(tester), isTrue); // 乐观置位后回弹
  });

  testWidgets('④b testMeal/testWater 抛异常 → 各自 toast 发送失败，不崩', (tester) async {
    final fake = FakeScheduler()..throwOnTest = true;
    await pumpProfile(tester, fake);

    await tester.tap(find.text('发一条测试通知'));
    await tester.pumpAndSettle();
    expect(find.text('测试通知发送失败'), findsOneWidget);

    await tester.tap(find.text('发一条喝水到点提醒（测试）'));
    await tester.pumpAndSettle();
    expect(find.text('喝水提醒发送失败'), findsOneWidget);
    expect(tester.takeException(), isNull); // 无未处理异常
  });

  testWidgets('④c enabled() 初值读取抛异常 → 开关按默认关渲染，不弹 toast、不崩',
      (tester) async {
    final fake = FakeScheduler()..throwOnEnabled = true;
    await pumpProfile(tester, fake);

    expect(switchValue(tester), isFalse); // H5 默认关（Notify.kt:92-93 语义）
    expect(find.text('提醒开关设置失败'), findsNothing); // 初值失败静默
    expect(tester.takeException(), isNull);
  });
}
