// ShiguangFlutter/test/home_screen_test.dart
// M2 Task 8：首页接真实数据（todayProvider/summaryProvider/recordsProvider）。
// 全部走 StubHealthApi（test/stubs/stub_health_api.dart），零网络。
// 数据形状取自 contract/fixtures/diet-core.json 的
// dailySummary/mealRecords responseSample。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/data/api_client.dart';
import 'package:shiguang_flutter/features/home/home_controller.dart';
import 'package:shiguang_flutter/features/home/home_screen.dart';

import 'stubs/stub_health_api.dart';

Widget harness(StubHealthApi api) => ProviderScope(
      overrides: [healthApiProvider.overrideWithValue(api)],
      child: const MaterialApp(home: HomeScreen()),
    );

void main() {
  final kSummary = StubHealthApi.summaryMap(kcal: 712, target: 1679, carb: 60, protein: 45, fat: 30, water: 3);
  final kRecords = <dynamic>[
    StubHealthApi.recordMap(
        id: 'rec_test_1', meal: 'breakfast', name: '鸡蛋', portion: '禽蛋 · 1 个约 50g', kcal: 72),
    StubHealthApi.recordMap(
        id: 'rec_test_2', meal: 'dinner', name: '鸡胸肉', portion: '禽肉 · 1 块约 100g', kcal: 133),
  ];

  testWidgets('有记录：环中心=还可摄入(budget-kcal)，aside 已摄入/额度行，三餐行渲染真实记录', (tester) async {
    final api = StubHealthApi(summary: kSummary, records: kRecords);
    await tester.pumpWidget(harness(api));
    await tester.pumpAndSettle();

    expect(find.text('今日盘子'), findsOneWidget);
    // M3-T7：环中心改显 max(0, budget-kcal)=1679-712（H5 renderRing app.js:300）
    expect(find.text('967'), findsOneWidget);
    expect(find.textContaining('已摄入 712 kcal'), findsOneWidget); // aside 行（云函数 target，非硬编码）
    expect(find.text('1975'), findsNothing);
    expect(find.textContaining('鸡蛋'), findsOneWidget);
    expect(find.textContaining('72 kcal'), findsOneWidget);
    expect(find.textContaining('鸡胸肉'), findsOneWidget);
    expect(find.textContaining('133 kcal'), findsOneWidget);
    expect(find.textContaining('1 块约 100g'), findsOneWidget); // portion 上屏
    expect(find.text('早餐'), findsOneWidget);
    expect(find.text('午餐'), findsOneWidget);
    expect(find.text('晚餐'), findsOneWidget);
    expect(find.text('未记录'), findsOneWidget); // 仅午餐空态
  });

  testWidgets('全空：三餐都是"未记录"，环中心=预算全额（摄入 0）', (tester) async {
    final api = StubHealthApi(summary: StubHealthApi.summaryMap(target: 1679));
    await tester.pumpWidget(harness(api));
    await tester.pumpAndSettle();

    expect(find.text('1679'), findsOneWidget); // 环中心 = budget-0（H5：无记录即全额可吃）
    expect(find.textContaining('已摄入 0 kcal'), findsOneWidget);
    expect(find.text('未记录'), findsNWidgets(3));
  });

  testWidgets('error 态：显示 ApiException.message + 重试，点击重取成功后渲染', (tester) async {
    final api = StubHealthApi(
      summaryError: ApiException('登录已过期，请重新登录'),
      recordsError: ApiException('登录已过期，请重新登录'),
    );
    await tester.pumpWidget(harness(api));
    await tester.pumpAndSettle();

    expect(find.text('登录已过期，请重新登录'), findsOneWidget);
    expect(find.text('重试'), findsOneWidget);
    expect(find.text('967'), findsNothing);

    // 桩翻转为成功 → 点重试（ref.invalidate 重新取数）
    api.summaryError = null;
    api.recordsError = null;
    api.summary = kSummary;
    api.records = kRecords;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();

    expect(find.text('登录已过期，请重新登录'), findsNothing);
    expect(find.textContaining('已摄入 712 kcal'), findsOneWidget);
    expect(find.textContaining('鸡胸肉'), findsOneWidget);
    expect(api.summaryCalls, 2); // 证明确实重发请求，非缓存翻牌
    expect(api.recordsCalls, 2);
  });
}
