// ShiguangFlutter/test/shell_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/shell.dart';
import 'package:shiguang_flutter/features/home/home_controller.dart' show healthApiProvider;
import 'package:shiguang_flutter/features/notifications/reminder_scheduler.dart'
    show reminderSchedulerProvider;

import 'harness.dart';
import 'stubs/stub_health_api.dart';

void main() {
  // T8 起首页 tab 是真实数据 HomeScreen：provider 必须进测试作用域，
  // healthApi 桩掉（空数据 → 三餐"未记录"），不落真实 TokenStore。
  // T8 缓办 B：「我的」tab 的 ProfileScreen initState 会读
  // reminderSchedulerProvider().enabled()——no-op 桩掉，不真触插件。
  Widget harness() => ProviderScope(
        overrides: [
          healthApiProvider.overrideWithValue(StubHealthApi()),
          reminderSchedulerProvider.overrideWithValue(NoopReminderScheduler()),
        ],
        child: const MaterialApp(home: Shell()),
      );

  testWidgets('默认首页 tab；点"我的"切到真实档案页（M4-T4 体重卡替换占位屏）',
      (tester) async {
    // T7 在体重卡下方追加「消息提醒」卡，页体变高——不撑大视口的话
    // 页尾「退出登录」落在 ListView 默认 800 视口缓存区外不被 build。
    await useBigSurface(tester);
    await tester.pumpWidget(harness());
    expect(find.text('今日盘子'), findsOneWidget);
    await tester.tap(find.text('我的').first);
    await tester.pumpAndSettle();
    // M1 占位 PlaceholderScreen('我的（M2 接入）') 已被 ProfileScreen 替换：
    // M8-① 体重卡迁往报告页——本页残面哨兵改钉提醒卡+食物库入口；
    // 「当前体重」须不在场（反向钉搬家彻底）。
    expect(find.text('我的（M2 接入）'), findsNothing);
    expect(find.text('当前体重'), findsNothing);
    expect(find.text('消息提醒 · 系统通知'), findsOneWidget);
    expect(find.text('食物库'), findsOneWidget);
    expect(find.text('退出登录'), findsOneWidget);
  });

  // M1 遗留核销：ShellState 必须释放 PageController，否则泄漏。
  testWidgets('卸载 Shell 后 PageController 已释放（M1 遗留 dispose 核销）', (tester) async {
    await tester.pumpWidget(harness());
    final state = tester.state<ShellState>(find.byType(Shell));
    await tester.pumpWidget(const SizedBox.shrink()); // 真卸载，触发 State.dispose
    expect(state.mounted, isFalse);
    // 未 dispose 的 controller 仍可挂新视图；已 dispose 再被使用会抛断言错误。
    expect(() => state.debugPageController.addListener(() {}), throwsAssertionError);
    expect(tester.takeException(), isNull);
  });
}
