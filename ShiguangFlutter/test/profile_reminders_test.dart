// ShiguangFlutter/test/profile_reminders_test.dart
// M4 Task 7：「我的」页提醒开关区（消息提醒卡）。
// M6 Task 6 方案 A（本文件现状）：卡面一行化——两枚测试钮从卡面迁进
// 「提醒设置」弹层「诊断」区（向 H5 remind-card 一行观感靠拢），测试断言
// 随之迁移：①卡面不再出现两测试钮文本、卡高 < 基线一半；③/③b/④b 先开
// 弹层再点测试钮（弹层内 toast 走 OverlayEntry 通道，断言用 pump()，
// pumpAndSettle 会把 2.4s toast 动画跑到自删）；⑥新增关层回归：✕ 关闭后
// 页级 SnackBar 通道恢复。开关直拨链（②/④/④c/⑤）零改动。
// 文案权威源 H5：index.html:227-237（卡标题「消息提醒 · 系统通知」、副文案、
// 两按钮「发一条测试通知」「发一条喝水到点提醒（测试）」、switch aria-label
// 「消息提醒」）、js/app.js:1043-1059（开/关 toast 与测试按钮 toast 文案）。
// 依赖面：只消费 T6 ReminderScheduler 的 enabled/setEnabled/testMeal/testWater
// （setEnabled 已联动 sync，UI 不再补 sync 调用——现码 reminder_scheduler.dart:179-183 核实）。
// 注入方式：override reminderSchedulerProvider 为 FakeScheduler（记录调用/可抛），
// 零插件零 SharedPreferences。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/theme.dart' show shiguangTheme;
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

  /// 非空 → setEnabled 先挂在该 Completer 上（T8 缓办 C：模拟在途窗口，
  /// 测 _reminderBusy 重入门禁）。
  Completer<void>? setEnabledGate;

  @override
  Future<bool> enabled() async {
    if (throwOnEnabled) throw Exception('boom');
    return _enabled;
  }

  @override
  Future<void> setEnabled(bool on) async {
    final gate = setEnabledGate;
    if (gate != null) await gate.future;
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
    // M6-T6：挂 shiguangTheme()（弹层/按钮族与真机同通道；filledButtonTheme
    // 有限值约束进装配，基线卡高在挂壳下重测，见 task-6-report）。
    child: MaterialApp(
        theme: shiguangTheme(), home: const ProfileScreen()),
  ));
  await tester.pumpAndSettle();
  return (container: container, scheduler: scheduler);
}

bool switchValue(WidgetTester tester) =>
    tester.widget<Switch>(find.byType(Switch)).value;

/// 提醒卡 Container 高度（方案 A 压缩断言基准）。
double remindCardHeight(WidgetTester tester) {
  final card = find
      .ancestor(
          of: find.text('消息提醒 · 系统通知'), matching: find.byType(Container))
      .first;
  return tester.getRect(card).height;
}

/// 卡面「提醒设置」入口点开弹层（M6-T6：测试钮断言迁移至弹层路径）。
/// 入口是卡面唯一 Icons.settings_outlined；不用 bySemanticsLabel 定位点击
/// （该 finder 需 ensureSemantics，且弹层打开后标题文本亦产同字 label）。
Future<void> openReminderSheet(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.settings_outlined));
  await tester.pumpAndSettle();
}

void main() {
  /* ---------- ① 卡渲染（M6-T6 一行化）+ 初值来自 enabled() ---------- */

  testWidgets(
      '①消息提醒卡（一行）：标题/副文案逐字（index.html:230-231），卡面无两测试钮、'
      '卡高<基线一半，「提醒设置」入口在，Switch 初值=enabled()=true', (tester) async {
    await pumpProfile(tester, FakeScheduler(enabledValue: true));

    expect(find.text('消息提醒 · 系统通知'), findsOneWidget); // index.html:230 逐字
    expect(find.text('三餐定点 8:00/12:00/18:30 + 喝水每天 8 次随机（8:00–24:00），横幅弹出'),
        findsOneWidget); // index.html:231 逐字
    // 方案 A：两测试钮收进弹层，卡面不再出现（M4 自加诊断钮压缩回 H5 一行观感）
    expect(find.text('发一条测试通知'), findsNothing);
    expect(find.text('发一条喝水到点提醒（测试）'), findsNothing);
    // 基线 217.0（旧实现两通栏钮版，挂 shiguangTheme、500×1600 面实测，
    // 数值与出处见 task-6-report），一行化后应不足一半。
    // M6-T7 评审 F5：本断言绑卡面一行形态——提醒卡卡面任何增删元素需重测
    // 基线并重钉此数，勿只放宽阈值。
    expect(remindCardHeight(tester), lessThan(217 / 2));
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget); // 弹层入口
    expect(switchValue(tester), isTrue); // 初值取自 scheduler.enabled()

    // 入口可及性：Semantics label「提醒设置」（简报 Step 1 ②），弹层未开时唯一
    final handle = tester.ensureSemantics();
    await tester.pump();
    expect(find.bySemanticsLabel('提醒设置'), findsOneWidget);
    handle.dispose();
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

  /* ---------- ③ 测试按钮各触发一次（M6-T6：迁移至弹层路径） ---------- */

  testWidgets(
      '③开弹层：说明/诊断区/两钮俱在；点「发一条测试通知」→ testMeal 恰一次 + 层内 toast（app.js:1051 逐字）',
      (tester) async {
    final fake = FakeScheduler();
    await pumpProfile(tester, fake);
    await openReminderSheet(tester);

    expect(find.text('开启后每天定点弹系统通知'), findsOneWidget); // 弹层说明
    expect(find.text('诊断'), findsOneWidget); // 诊断区小标题
    expect(find.text('发一条测试通知'), findsOneWidget); // index.html:235 逐字（迁入弹层）
    expect(find.text('发一条喝水到点提醒（测试）'), findsOneWidget); // :236 逐字（迁入弹层）

    await tester.tap(find.text('发一条测试通知'));
    await tester.pump(); // handler 微任务完成 + OverlayEntry 插入
    await tester.pump(); // 层内 toast 首帧（不可 pumpAndSettle：2.4s 动画跑完 toast 自删）
    expect(fake.testMealCalls, 1);
    expect(fake.testWaterCalls, 0); // 不串线
    expect(find.text('测试通知已发，看通知栏'), findsOneWidget);
  });

  testWidgets('③b弹层内点「发一条喝水到点提醒（测试）」→ testWater 恰一次 + 已发出 toast',
      (tester) async {
    final fake = FakeScheduler();
    await pumpProfile(tester, fake);
    await openReminderSheet(tester);

    await tester.tap(find.text('发一条喝水到点提醒（测试）'));
    await tester.pump();
    await tester.pump();
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

  testWidgets('④b 弹层内 testMeal/testWater 抛异常 → 各自层内 toast 发送失败，不崩',
      (tester) async {
    final fake = FakeScheduler()..throwOnTest = true;
    await pumpProfile(tester, fake);
    await openReminderSheet(tester);

    await tester.tap(find.text('发一条测试通知'));
    await tester.pump();
    await tester.pump();
    expect(find.text('测试通知发送失败'), findsOneWidget);

    await tester.tap(find.text('发一条喝水到点提醒（测试）'));
    await tester.pump();
    await tester.pump();
    expect(find.text('喝水提醒发送失败'), findsOneWidget); // 后发顶掉前条（同通道单条）
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

  /* ---------- ⑤ 重入门禁（T8 缓办 C，仿体重 _saving） ---------- */

  testWidgets('⑤setEnabled 在途连拨两次：只发一次 setEnabled，在途开关禁用',
      (tester) async {
    final fake = FakeScheduler(enabledValue: false)
      ..setEnabledGate = Completer<void>();
    await pumpProfile(tester, fake);

    await tester.tap(find.byType(Switch)); // 关→开，setEnabled 挂 gate 在途
    await tester.pump();
    expect(switchValue(tester), isTrue); // 乐观置位（app.js:1043-1049 先翻 UI）
    expect(fake.setEnabledCalls, isEmpty); // 尚未落地

    await tester.tap(find.byType(Switch)); // 在途连拨：busy → onChanged=null no-op
    await tester.pump();
    expect(fake.setEnabledCalls, isEmpty);
    expect(switchValue(tester), isTrue); // 不被二次拨回

    fake.setEnabledGate!.complete();
    await tester.pumpAndSettle();
    expect(fake.setEnabledCalls, [true]); // 全程只发一次
    expect(switchValue(tester), isTrue);
    expect(find.text('提醒已开启：每天定点弹系统通知'), findsOneWidget);

    // 门禁解除后可正常再拨（busy 已复位）
    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(fake.setEnabledCalls, [true, false]);
  });

  /* ---------- ⑥ M6-T6 弹层生命周期：关闭回卡面，toast 通道复位 ---------- */

  testWidgets('⑥✕关层：测试钮消失；关层后拨开关 toast 回页级 SnackBar 通道',
      (tester) async {
    final fake = FakeScheduler(enabledValue: false);
    await pumpProfile(tester, fake);
    await openReminderSheet(tester);
    expect(find.text('发一条测试通知'), findsOneWidget);

    await tester.tap(find.text('✕')); // 关层（弹层族 ✕ 定式，≙ aria 关闭）
    await tester.pumpAndSettle();
    expect(find.text('发一条测试通知'), findsNothing);

    await tester.tap(find.byType(Switch)); // 通道复位验证：开关 toast 走 SnackBar
    await tester.pumpAndSettle();
    expect(fake.setEnabledCalls, [true]);
    expect(find.text('提醒已开启：每天定点弹系统通知'), findsOneWidget);
  });
}
