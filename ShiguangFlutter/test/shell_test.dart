// ShiguangFlutter/test/shell_test.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/shell.dart';
import 'package:shiguang_flutter/features/home/home_controller.dart' show healthApiProvider;

import 'stubs/stub_health_api.dart';

void main() {
  // T8 起首页 tab 是真实数据 HomeScreen：provider 必须进测试作用域，
  // healthApi 桩掉（空数据 → 三餐"未记录"），不落真实 TokenStore。
  Widget harness() => ProviderScope(
        overrides: [healthApiProvider.overrideWithValue(StubHealthApi())],
        child: const MaterialApp(home: Shell()),
      );

  testWidgets('默认首页 tab；点"我的"切到档案占位屏', (tester) async {
    await tester.pumpWidget(harness());
    expect(find.text('今日盘子'), findsOneWidget);
    await tester.tap(find.text('我的'));
    await tester.pumpAndSettle();
    expect(find.text('我的（M2 接入）'), findsOneWidget);
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
