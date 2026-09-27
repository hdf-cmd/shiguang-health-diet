// ShiguangFlutter/test/home_screen_test.dart
// M2 Task 8：首页接真实数据（todayProvider/summaryProvider）。
// 全部走 StubHealthApi（test/stubs/stub_health_api.dart），零网络。
// 数据形状取自 contract/fixtures/diet-core.json 的
// dailySummary/mealRecords responseSample。
// M6-T3 注：首页新挂 exercisesProvider（运动卡/环额度），首载多一轮异步泵帧，
// 会推着 pumpAndSettle 的虚拟时钟越过 riverpod 默认失败退避重试的定时器——
// error 态用例的 summaryCalls 因此 +1。改走 UncontrolledProviderScope +
// `retry: (_,_) => null`（exercise_sheet_test 同法）关掉自动重试，
// 「重试按钮=真重发」的计数断言恢复原语义。
// M6-T5 注：首页新挂 AdviceCard（默认 800×600 视口下把三餐卡推出 ListView
// 缓存区 → find 不到，harness.dart 注②既有病症），harness 统一 useBigSurface。
// M8-②：三餐记录卡整卡删除——首页不再 watch recordsProvider，本文件
// 餐次行断言反转为「不再在场」，error 闸收敛为 summary 单路。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/theme.dart' show shiguangTheme;
import 'package:shiguang_flutter/data/api_client.dart';
import 'package:shiguang_flutter/features/home/home_controller.dart';
import 'package:shiguang_flutter/features/home/home_screen.dart';

import 'harness.dart' show useBigSurface;
import 'stubs/stub_health_api.dart';

Future<void> harness(WidgetTester tester, StubHealthApi api) async {
  await useBigSurface(tester);
  final container = ProviderContainer(
    overrides: [healthApiProvider.overrideWithValue(api)],
    retry: (_, _) => null, // 禁默认退避重试（见头注）
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    // M7-T8（终审复核点名）：裸 MaterialApp 改挂真主题——工程纪律
    // 「widget 测试必挂 shiguangTheme()」，FilledButton/间距等装饰面与生产一致
    child: MaterialApp(theme: shiguangTheme(), home: const HomeScreen()),
  ));
}

void main() {
  final kSummary = StubHealthApi.summaryMap(kcal: 712, target: 1679, carb: 60, protein: 45, fat: 30, water: 3);

  testWidgets('有记录：环中心=还可摄入(budget-kcal)，aside 已摄入/额度行；M8-② 三餐卡不再在场', (tester) async {
    final api = StubHealthApi(summary: kSummary);
    await harness(tester, api);
    await tester.pumpAndSettle();

    expect(find.text('今日盘子'), findsOneWidget);
    // M3-T7：环中心改显 max(0, budget-kcal)=1679-712（H5 renderRing app.js:300）
    expect(find.text('967'), findsOneWidget);
    expect(find.textContaining('已摄入 712 kcal'), findsOneWidget); // aside 行（云函数 target，非硬编码）
    expect(find.text('1975'), findsNothing);
    // M8-②：三餐记录卡整卡删除——卡题与餐次行都不再渲染，
    // 首页也不再发 getMealRecords（recordsCalls 恒 0）
    expect(find.text('三餐记录'), findsNothing);
    expect(find.text('早餐'), findsNothing);
    expect(find.text('未记录'), findsNothing);
    expect(api.recordsCalls, 1); // 首页不显餐次但建议卡引擎仍拉 records（advice_card.dart:80）
  });

  testWidgets('全空：环中心=预算全额（摄入 0），无骨架/无餐次残留', (tester) async {
    final api = StubHealthApi(summary: StubHealthApi.summaryMap(target: 1679));
    await harness(tester, api);
    await tester.pumpAndSettle();

    expect(find.text('1679'), findsOneWidget); // 环中心 = budget-0（H5：无记录即全额可吃）
    expect(find.textContaining('已摄入 0 kcal'), findsOneWidget);
    expect(find.text('未记录'), findsNothing); // M8-②：三餐「未记录」行随卡退役
    expect(find.byKey(const ValueKey('meal-skeleton')), findsNothing);
  });

  testWidgets('error 态：显示 ApiException.message + 重试，点击重取成功后渲染', (tester) async {
    final api = StubHealthApi(
      summaryError: ApiException('登录已过期，请重新登录'),
    );
    await harness(tester, api);
    await tester.pumpAndSettle();

    expect(find.text('登录已过期，请重新登录'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('967'), findsNothing);

    // 桩翻转为成功 → 点重试（ref.invalidate 重新取数）
    api.summaryError = null;
    api.summary = kSummary;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('登录已过期，请重新登录'), findsNothing);
    expect(find.textContaining('已摄入 712 kcal'), findsOneWidget);
    expect(api.summaryCalls, 2); // 证明确实重发请求，非缓存翻牌
  });
}
