// ShiguangFlutter/test/food_scan_sheet_test.dart
// M13-T6：识菜确认表单 + 保存链六条判据。
// 记账断言一律走 StubHealthApi.addBodies（既有按次收集 addFoodRecord 入参），
// 不另造记录字段。toast 是 Ticker 驱动：断言 toast 文本用 pump 两次，不能
// pumpAndSettle（会把 2400ms toast 跑到自删）。
// 修复轮 1（评审 Important#1 + Minor 2/3）：补四组断言——①a 缓存失效时机
// （正常保存删 foods.custom 键 / skipped=builtin 哨兵仍在）、①b 记账失败仍
// pop、①c 校验拦截零请求、①d 换图/移除照片进 upsert；另钉 '160.' 的 JS
// Number 语义与汇总「20g」串形（jsNumber/jsNumText）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/data/api_client.dart' show ApiException;
import 'package:shiguang_flutter/data/swr_cache.dart'
    show SwrCache, swrCacheProvider;
import 'package:shiguang_flutter/features/common/sheet.dart'
    show showShiguangSheet;
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider;
import 'package:shiguang_flutter/features/record/food_freq.dart'
    show FoodFreqStore, foodFreqStoreProvider;
import 'package:shiguang_flutter/features/record/food_scan_sheet.dart';

import 'harness.dart' show useBigSurface;
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

/// 表单宿主：≙ 生产入口形态（openFoodScanFlow 以 showShiguangSheet 弹层打开，
/// 不是把表单当路由根 body）。若表单本身是根路由，保存链的 Navigator.pop 会清空
/// Navigator 历史，下一帧 build 触发框架 `_history.isNotEmpty` 断言——那是测试
/// 地基缺陷，不是实现缺陷。
class _ScanHost extends StatelessWidget {
  const _ScanHost({
    required this.date,
    required this.meal,
    required this.scan,
    required this.initialImage,
    required this.recordMeal,
  });

  final String date;
  final String meal;
  final Map<String, dynamic> scan;
  final String initialImage;
  final bool recordMeal;

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            key: const Key('open-scan'),
            onPressed: () => showShiguangSheet<void>(
              context,
              title: '识菜确认',
              child: FoodScanSheet(
                date: date,
                meal: meal,
                scan: scan,
                initialImage: initialImage,
                recordMeal: recordMeal,
              ),
            ),
            child: const Text('open-scan'),
          ),
        ),
      );
}

Future<void> pumpScan(
  WidgetTester tester,
  StubHealthApi api, {
  bool recordMeal = true,
  SwrCache? cache,
  ScanImagePick? imagePick,
}) async {
  await useBigSurface(tester); // 弹层限高 78%，小视口下保存钮会滚出屏
  await tester.pumpWidget(ProviderScope(
    // 每阶段重建容器：swr 缓存/计数器不跨阶段串味（修复轮 a/d 同测两段）
    key: UniqueKey(),
    overrides: [
      healthApiProvider.overrideWithValue(api),
      // 桌面测试不注入会抛 UnimplementedError（addRecord 成功支 record(name)）
      foodFreqStoreProvider.overrideWithValue(_MemStore()),
      if (cache != null) swrCacheProvider.overrideWithValue(cache),
      if (imagePick != null) scanImagePickProvider.overrideWithValue(imagePick),
    ],
    child: MaterialApp(
      home: _ScanHost(
        date: '2026-10-25',
        meal: 'lunch',
        scan: api.scanResult,
        initialImage: 'data:image/jpeg;base64,AAA',
        recordMeal: recordMeal,
      ),
    ),
  ));
  await tester.pump();
  // 开层（此刻无 toast，settle 安全）
  await tester.tap(find.byKey(const Key('open-scan')));
  await tester.pumpAndSettle();
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

    // 修复轮②：'160.' 钉 H5 Number('160.')=160 的尾点语义（jsNumber 全串）；
    // 150g 下 160×1.5=240。注：Dart 3.13.4 的 num.tryParse('160.') 实测也是
    // 160，本断言不区分新旧解析器，只锁口径不回退
    await tester.enterText(find.byKey(const Key('scan-kcal')), '160.');
    await tester.pump();
    expect(find.textContaining('240 kcal'), findsOneWidget);

    // 修复轮③：整值营养素走 JS 串形「20g」，不是 Dart double 的「20.0g」
    // （克数回 200g：10/100g × 2 = 20）
    await tester.enterText(find.byKey(const Key('scan-grams')), '200');
    await tester.enterText(find.byKey(const Key('scan-protein')), '10');
    await tester.pump();
    expect(find.textContaining('蛋白 20g'), findsOneWidget);
    expect(find.textContaining('20.0g'), findsNothing);
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
    // 记账体四键：date/meal 取入口入参、portion 按份、emoji 取 upsert 回包
    // （桩默认 '🍗'）而非写死——钉「emoji 来自入库回包」这条链
    expect(api.addBodies.single['date'], '2026-10-25');
    expect(api.addBodies.single['meal'], 'lunch');
    expect(api.addBodies.single['emoji'], isNotEmpty);
    expect(api.addBodies.single['emoji'], api.upsertResult['emoji']);
    expect(api.addBodies.single['portion'], '200g');
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

  /* ---------- 修复轮①a：缓存失效时机（评审 Important#1） ---------- */

  testWidgets('a. 正常保存删除 foods.custom 键；skipped=builtin 时哨兵键仍在',
      (tester) async {
    // 正常入库：写路径「先删键再刷新」——键必须被删
    final api = StubHealthApi();
    final cache = SwrCache()
      ..write('foods.custom', <dynamic>[
        <String, dynamic>{'id': 'old'},
      ]);
    await pumpScan(tester, api, cache: cache);
    expect(cache.read('foods.custom'), isNotNull); // 预置哨兵在场
    await tester.tap(find.byKey(const Key('scan-save')));
    await tester.pumpAndSettle();
    expect(cache.read('foods.custom'), isNull);

    // 内置同名：本轮未写自定义库 → 不失效（哨兵原样保留）
    final api2 = StubHealthApi()
      ..upsertResult = <String, dynamic>{
        'ok': true,
        'skipped': 'builtin',
        'emoji': '🍚',
      };
    final cache2 = SwrCache()
      ..write('foods.custom', <dynamic>[
        <String, dynamic>{'id': 'old'},
      ]);
    await pumpScan(tester, api2, cache: cache2);
    expect(cache2.read('foods.custom'), isNotNull);
    await tester.tap(find.byKey(const Key('scan-save')));
    await tester.pump();
    await tester.pump();
    expect(cache2.read('foods.custom'), isNotNull);
  });

  /* ---------- 修复轮①b：记账失败仍 pop（表单已关） ---------- */

  testWidgets('b. 记账失败：toast「已入库，本餐记入失败」且表单已关', (tester) async {
    final api = StubHealthApi()..addError = ApiException('网络异常');
    await pumpScan(tester, api);
    await tester.tap(find.byKey(const Key('scan-save')));
    // 只泵两帧、不 pumpAndSettle（2400ms toast 会被跑到自删）。第二帧带
    // 220ms：盖过底部弹层 200ms 退场，弹层销毁而 toast 仍在播
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 220));
    expect(api.lastUpsertBody, isNotNull); // 入库已成功
    expect(find.textContaining('已入库，本餐记入失败'), findsOneWidget);
    expect(find.byType(FoodScanSheet), findsNothing); // 仍关层
  });

  /* ---------- 修复轮①c：校验拦截零请求 ---------- */

  testWidgets('c. 空菜名/克数 0：点保存零 upsert 请求', (tester) async {
    final api = StubHealthApi();
    await pumpScan(tester, api);

    await tester.enterText(find.byKey(const Key('scan-name')), '');
    await tester.tap(find.byKey(const Key('scan-save')));
    await tester.pump();
    expect(api.lastUpsertBody, isNull); // 菜名空 → 闸在 upsert 前

    await tester.enterText(find.byKey(const Key('scan-name')), '蒜薹鸡块');
    await tester.enterText(find.byKey(const Key('scan-grams')), '0');
    await tester.tap(find.byKey(const Key('scan-save')));
    await tester.pump();
    expect(api.lastUpsertBody, isNull); // 克数 0 → 同样零请求
    expect(api.upsertCalls, 0);
  });

  /* ---------- 修复轮①d：换图/移除照片进 upsert ---------- */

  testWidgets('d. scan-pick-photo 换的图随保存入库；scan-remove-photo 后 image 为空串',
      (tester) async {
    // 换图（选图注入面固定回 BBB）
    final api = StubHealthApi();
    await pumpScan(tester, api,
        imagePick: (_) async =>
            (dataUrl: 'data:image/jpeg;base64,BBB', failure: null));
    await tester.tap(find.byKey(const Key('scan-pick-photo')));
    await tester.pump(); // 选图回包 → _image=BBB
    await tester.tap(find.byKey(const Key('scan-save')));
    await tester.pumpAndSettle();
    expect('${api.lastUpsertBody!['image']}', endsWith('BBB'));

    // 移除（初值=识别图 AAA → 清空）
    final api2 = StubHealthApi();
    await pumpScan(tester, api2);
    await tester.tap(find.byKey(const Key('scan-remove-photo')));
    await tester.pump();
    await tester.tap(find.byKey(const Key('scan-save')));
    await tester.pumpAndSettle();
    expect(api2.lastUpsertBody!['image'], '');
  });
}
