// ShiguangFlutter/test/plate_swipe_test.dart
// M8-③：盘子卡卡内横滑切日（老大 09-27 真机反馈「右滑看历史无效果」翻案
// 落地）。钉三面：①卡内右滑=前一天且壳层 PageView 不切 tab；②左滑回今天、
// 再左滑吃未来闸 toast「已经到今天了」（shiftPlateDate 既有语义复用）；
// ③卡外横滑仍走壳层 PageView 切 tab（手势竞技场互不侵占）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/shell.dart' show Shell, ShellState;
import 'package:shiguang_flutter/domain/dates.dart' show dateLabelOf, todayIso;
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider, plateDateProvider;
import 'package:shiguang_flutter/features/notifications/reminder_scheduler.dart'
    show reminderSchedulerProvider;

import 'harness.dart';
import 'stubs/stub_health_api.dart';

void main() {
  Future<ProviderContainer> pumpShell(WidgetTester tester) async {
    await useBigSurface(tester);
    final container = ProviderContainer(
      overrides: [
        healthApiProvider.overrideWithValue(StubHealthApi()),
        reminderSchedulerProvider.overrideWithValue(NoopReminderScheduler()),
      ],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(home: Shell()),
    ));
    await tester.pumpAndSettle();
    return container;
  }

  String shiftIso(int days) {
    final now = DateTime.now();
    final d = DateTime(now.year, now.month, now.day + days);
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$dd';
  }

  testWidgets('卡内右滑=前一天、PageView 不切 tab；左滑两步回今天后再滑吃未来闸', (tester) async {
    final container = await pumpShell(tester);

    // 右滑（dx>0）=看历史 → 前一天
    await tester.drag(
        find.byKey(const ValueKey('plate-swipe')), const Offset(150, 0));
    await tester.pumpAndSettle();
    expect(container.read(plateDateProvider), shiftIso(-1));
    expect(find.text(dateLabelOf(shiftIso(-1))),
        findsWidgets); // 胶囊主文案「昨天」
    expect(tester.state<ShellState>(find.byType(Shell)).debugPageController.page,
        0.0); // 壳层没切页

    // 左滑回今天
    await tester.drag(
        find.byKey(const ValueKey('plate-swipe')), const Offset(-150, 0));
    await tester.pumpAndSettle();
    expect(container.read(plateDateProvider), todayIso());

    // 今天再左滑 → 未来闸拦下 + toast「已经到今天了」（M7-T1 既有语义）
    await tester.drag(
        find.byKey(const ValueKey('plate-swipe')), const Offset(-150, 0));
    await tester.pumpAndSettle();
    expect(container.read(plateDateProvider), todayIso());
    expect(find.text('已经到今天了'), findsOneWidget);
  });

  testWidgets('卡外横滑（问候头/标题区）仍走壳层 PageView 切 tab', (tester) async {
    final container = await pumpShell(tester);

    await tester.drag(find.text('今日盘子'), const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(
        tester.state<ShellState>(find.byType(Shell)).debugPageController.page,
        1.0); // → 记录页
    expect(find.text('饮食记录'), findsOneWidget);
    expect(container.read(plateDateProvider), todayIso()); // 没碰日期
  });
}
