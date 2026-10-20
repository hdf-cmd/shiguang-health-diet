// ShiguangFlutter/test/food_scan_sheet_test.dart
// M13-T6：识菜确认表单 + 保存链六条判据。
// 记账断言一律走 StubHealthApi.addBodies（既有按次收集 addFoodRecord 入参），
// 不另造记录字段。toast 是 Ticker 驱动：断言 toast 文本用 pump 两次，不能
// pumpAndSettle（会把 2400ms toast 跑到自删）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/data/api_client.dart' show ApiException;
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider;
import 'package:shiguang_flutter/features/record/food_freq.dart'
    show FoodFreqStore, foodFreqStoreProvider;
import 'package:shiguang_flutter/features/record/food_scan_sheet.dart';

import 'stubs/stub_health_api.dart';

/// 内存版频次存储（桌面测试不注入会抛 UnimplementedError——addRecord 成功
/// 支会调 foodFreq.record(name)）。
class _MemStore implements FoodFreqStore {
  final Map<String, Map<String, int>> _counts = <String, Map<String, int>>{};
  final Set<String> _init = <String>{};

  @override
  Future<Map<String, int>> loadCounts(String uid) async =>
      Map<String, int>.of(_counts[uid] ?? const <String, int>{});

  @override
  Future<void> saveCounts(String uid, Map<String, int> counts) async {
    _counts[uid] = Map<String, int>.of(counts);
  }

  @override
  Future<bool> isInitialized(String uid) async => _init.contains(uid);

  @override
  Future<void> markInitialized(String uid) async => _init.add(uid);
}

Future<void> pumpScan(
  WidgetTester tester,
  StubHealthApi api, {
  bool recordMeal = true,
}) async {
  await tester.pumpWidget(ProviderScope(
    overrides: [
      healthApiProvider.overrideWithValue(api),
      foodFreqStoreProvider.overrideWithValue(_MemStore()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: FoodScanSheet(
          date: '2026-10-25',
          meal: 'lunch',
          scan: api.scanResult,
          initialImage: 'data:image/jpeg;base64,AAA',
          recordMeal: recordMeal,
        ),
      ),
    ),
  ));
  await tester.pump();
}

void main() {
  testWidgets('预填模型建议；改克数实时改汇总', (tester) async {
    final api = StubHealthApi();
    await pumpScan(tester, api);
    expect(find.text('蒜薹鸡块'), findsOneWidget);
    expect(find.textContaining('312 kcal'), findsOneWidget); // 200g 默认
    await tester.enterText(find.byKey(const Key('scan-grams')), '150');
    await tester.pump();
    expect(find.textContaining('234 kcal'), findsOneWidget);
  });

  testWidgets('低置信度提示', (tester) async {
    final api = StubHealthApi()
      ..scanResult = {
        ...StubHealthApi().scanResult,
        'confidence': 'low',
      };
    await pumpScan(tester, api);
    expect(find.textContaining('识别把握不大'), findsOneWidget);
  });

  testWidgets('保存：upsert 入参按份、记录带同一张入库照片', (tester) async {
    final api = StubHealthApi();
    await pumpScan(tester, api);
    await tester.tap(find.byKey(const Key('scan-save')));
    await tester.pumpAndSettle();
    expect(api.lastUpsertBody!['name'], '蒜薹鸡块');
    expect(api.lastUpsertBody!['grams'], 200);
    expect(api.lastUpsertBody!['kcal'], 312);
    expect(api.lastUpsertBody!['portion'], '200g');
    expect(api.lastUpsertBody!['image'], startsWith('data:image/jpeg;base64,'));
    expect(api.addBodies.single['kcal'], 312);
    expect(api.addBodies.single['image'], api.lastUpsertBody!['image']);
  });

  testWidgets('内置同名：不入库但照常记账', (tester) async {
    final api = StubHealthApi()
      ..upsertResult = {'ok': true, 'skipped': 'builtin', 'emoji': '🍚'};
    await pumpScan(tester, api);
    await tester.tap(find.byKey(const Key('scan-save')));
    await tester.pump();
    expect(api.addBodies, hasLength(1));
  });

  testWidgets('入库失败：停留表单并显示错误', (tester) async {
    final api = StubHealthApi()..upsertError = ApiException('网络异常');
    await pumpScan(tester, api);
    await tester.tap(find.byKey(const Key('scan-save')));
    await tester.pumpAndSettle();
    expect(find.textContaining('保存失败'), findsOneWidget);
    expect(api.addBodies, isEmpty);
  });

  testWidgets('食物库入口（recordMeal=false）只入库不记账', (tester) async {
    final api = StubHealthApi();
    await pumpScan(tester, api, recordMeal: false);
    await tester.tap(find.byKey(const Key('scan-save')));
    await tester.pumpAndSettle();
    expect(api.lastUpsertBody, isNotNull);
    expect(api.addBodies, isEmpty);
  });
}
