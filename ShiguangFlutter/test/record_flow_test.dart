// ShiguangFlutter/test/record_flow_test.dart
// M2 Task 9：记录页全流程（餐次分段 / 已记列表删除 / 食物搜索 / 按克加份量弹层）。
// 全部走 StubHealthApi（test/stubs/stub_health_api.dart），零网络。
// 食物与记录字段形状取自 contract/fixtures/diet-core.json 的
// searchFoods/mealRecords responseSample；行为权威源 js/app.js：
//   默认餐次 defaultMeal 603-609、搜索弹层 openSheet/fillSheetResults 615-651、
//   添加 body 678-682、删除确认 557-560、份量弹层 openPortionSheet/updatePortionPreview/
//   portion-save 714-781。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/data/swr_cache.dart' show swrCacheProvider;
import 'package:shiguang_flutter/domain/dates.dart' show todayIso;
import 'package:shiguang_flutter/domain/models.dart' show Per100, Summary;
import 'package:shiguang_flutter/domain/portion.dart' show portionMacros;
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider;
import 'package:shiguang_flutter/features/record/record_controller.dart'
    show defaultMealAt, recordControllerProvider, recordsProvider, summaryProvider;
import 'package:shiguang_flutter/features/record/record_screen.dart'
    show RecordScreen;

import 'stubs/stub_health_api.dart';

Widget harness(StubHealthApi api, {String? initialMeal}) => ProviderScope(
      overrides: [healthApiProvider.overrideWithValue(api)],
      child: MaterialApp(home: RecordScreen(initialMeal: initialMeal)),
    );

/// diet-core.json searchFoods.responseSample[0]（米饭，per100 + baseG=200）
final kRiceFood = <String, dynamic>{
  'id': 'u_06',
  'name': '米饭',
  'meta': '主食 · 1 碗约 150g',
  'kcal': 174,
  'emoji': '🍚',
  'image': 'img/foods/rice.jpg',
  'meals': ['lunch', 'dinner'],
  'protein': 4,
  'carb': 39,
  'fat': 0,
  'per100': {'kcal': 116, 'protein': 2.6, 'carb': 25.9, 'fat': 0.3},
  'baseG': 200,
};

/// 非 per100 普通食物（点按钮文案应为「添加」）
final kEggFood = <String, dynamic>{
  'id': 'u_egg',
  'name': '鸡蛋',
  'meta': '禽蛋 · 1 个约 50g',
  'kcal': 72,
  'emoji': '🥚',
  'image': '',
  'meals': ['breakfast', 'lunch'],
  'protein': 7,
  'carb': 1,
  'fat': 5,
};

Future<void> openSheetAndSearch(WidgetTester tester, String keyword) async {
  await tester.tap(find.text('＋ 记一笔'));
  await tester.pumpAndSettle(); // 弹层出场 + 初始空关键词搜索
  await tester.enterText(find.widgetWithText(TextField, '搜索食物库'), keyword);
  await tester.pump(const Duration(milliseconds: 250)); // H5 200ms 防抖（js/app.js:696-700）
  await tester.pumpAndSettle();
}

void main() {
  /* ---------- 默认餐次 = H5 defaultMeal 逻辑（js/app.js:603-609） ---------- */

  test('defaultMealAt 与 H5 逐分支一致：<10 早餐 / <15 午餐 / <21 晚餐 / 其余零食', () {
    expect(defaultMealAt(6), 'breakfast');
    expect(defaultMealAt(12), 'lunch'); // 「默认同 H5 逻辑 lunch」的日间档位
    expect(defaultMealAt(18), 'dinner');
    expect(defaultMealAt(22), 'snack');
  });

  /* ---------- ① 餐次分段 + 已记列表 ---------- */

  testWidgets('①午餐 tab：只渲染该餐次已记记录（名/portion/kcal），其他餐次不出现',
      (tester) async {
    final api = StubHealthApi(records: [
      StubHealthApi.recordMap(
          id: 'rec_l_1', meal: 'lunch', name: '米饭', portion: '200g', kcal: 232),
      StubHealthApi.recordMap(
          id: 'rec_b_1', meal: 'breakfast', name: '鸡蛋', portion: '1 个', kcal: 72),
    ]);
    await tester.pumpWidget(harness(api, initialMeal: 'lunch'));
    await tester.pumpAndSettle();

    expect(find.text('饮食记录'), findsOneWidget);
    // 四个餐次分段（文案逐字抄 H5 MEAL_NAMES / index.html:281-284）
    expect(find.text('早餐'), findsOneWidget);
    expect(find.text('午餐'), findsOneWidget);
    expect(find.text('晚餐'), findsOneWidget);
    expect(find.text('零食'), findsOneWidget);
    // 已记列表：名 / portion / kcal
    expect(find.textContaining('米饭'), findsOneWidget);
    expect(find.textContaining('200g'), findsOneWidget);
    expect(find.text('232 kcal'), findsNWidgets(2)); // 行 kcal + 餐次合计（均 232）
    expect(find.textContaining('鸡蛋'), findsNothing); // 早餐记录不在午餐 tab
    expect(find.text('这一天还没有记录'), findsNothing);
  });

  testWidgets('①b 切到早餐 tab：显示对应记录；空餐次显示「未记录」+「＋ 加一份」',
      (tester) async {
    final api = StubHealthApi(records: [
      StubHealthApi.recordMap(
          id: 'rec_l_1', meal: 'lunch', name: '米饭', portion: '200g', kcal: 232),
    ]);
    await tester.pumpWidget(harness(api, initialMeal: 'lunch'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('早餐'));
    await tester.pumpAndSettle();
    // 全天有记录但早餐为空 → 对齐 H5 空餐组（js/app.js:532-538）
    expect(find.text('未记录'), findsOneWidget);
    expect(find.text('＋ 加一份'), findsOneWidget);
    expect(find.text('这一天还没有记录'), findsNothing);
  });

  testWidgets('①c 全天无记录：统一空态文案（js/app.js:521-528）', (tester) async {
    final api = StubHealthApi();
    await tester.pumpWidget(harness(api, initialMeal: 'lunch'));
    await tester.pumpAndSettle();

    expect(find.text('这一天还没有记录'), findsOneWidget);
    expect(find.text('点下方「记一笔」记下第一餐，开始追踪热量'), findsOneWidget);
  });

  /* ---------- ② 搜索 → 添加普通食物 ---------- */

  testWidgets('②搜索→点「添加」：addFoodRecord 收到正确 body，成功后当日记录 invalidate 重取',
      (tester) async {
    final api = StubHealthApi(
      records: [
        StubHealthApi.recordMap(
            id: 'rec_l_1', meal: 'lunch', name: '米饭', portion: '200g', kcal: 232),
      ],
      foods: [kEggFood, kRiceFood],
    );
    await tester.pumpWidget(harness(api, initialMeal: 'lunch'));
    await tester.pumpAndSettle();
    expect(api.recordsCalls, 1);

    await openSheetAndSearch(tester, '鸡');
    // M11-T1：开层拉一份空词快照（meal 仍按当前餐次，js/app.js:633），
    // 打字改端上过滤 → 网络请求总数不因关键词增加。
    expect(api.searchCalls, 1);
    expect(api.lastSearchKeyword, '');
    expect(api.lastSearchMeal, 'lunch');
    // 结果行：名/meta/kcal + 按钮文案（per100→「按克加」，普通→「添加」，js/app.js:642）
    expect(find.textContaining('鸡蛋'), findsOneWidget);
    expect(find.text('添加'), findsOneWidget);
    // 端上过滤真生效的新证据：搜「鸡」时米饭必须被滤掉。
    // 量具说明：结果行与记录行都渲染菜名，`textContaining('米饭')` 会同时命中
    // 记录区那条（本用例 records 里就有米饭），故改用**只出现在搜索结果行**的
    // per100 按钮「按克加」作尺（米饭是唯一 per100 项，它不在＝已被滤掉）。
    // per100 的正向覆盖由 ③/③b 独立承担，本处删除不构成减 Coverage。
    expect(find.text('按克加'), findsNothing);
    expect(find.textContaining('米饭'), findsOneWidget); // 仅剩记录区那一行

    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    // body 字段逐一对齐 js/app.js:678-682
    expect(api.addBodies, hasLength(1));
    expect(api.addBodies.single, <String, dynamic>{
      'date': todayIso(),
      'meal': 'lunch',
      'name': '鸡蛋',
      'portion': '禽蛋 · 1 个约 50g', // portion = f.meta
      'kcal': 72,
      'emoji': '🥚',
      'protein': 7,
      'carb': 1,
      'fat': 5,
      'image': '',
    });

    // 关闭弹层后，当日 recordsProvider 已被 invalidate 并重取（列表对账云端）
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(api.recordsCalls, greaterThanOrEqualTo(2));
  });

  /* ---------- ②b pending 防重（H5 btn.disabled js/app.js:677/693） ---------- */

  testWidgets('②b 慢网双击：添加在途期间按钮禁用为「请稍候…」，连点两次 addFoodRecord 只发一次',
      (tester) async {
    final api = StubHealthApi(foods: [kEggFood]);
    api.addGate = Completer<void>(); // addFoodRecord 挂起，模拟慢网 pending
    await tester.pumpWidget(harness(api, initialMeal: 'lunch'));
    await tester.pumpAndSettle();

    await openSheetAndSearch(tester, '鸡');
    expect(find.text('添加'), findsOneWidget);

    await tester.tap(find.text('添加'));
    await tester.pump(); // 一帧：进入 pending（不 settle，否则等 addGate）
    expect(api.addBodies, hasLength(1));
    // 文案对齐 H5 提交态（js/app.js:1902 btn.textContent = '请稍候…'）
    expect(find.text('请稍候…'), findsOneWidget);
    expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('food-action-u_egg')))
            .onPressed,
        isNull); // 禁用（js/app.js:677 btn.disabled = true）

    // 连点两次：disabled 吞掉点击，控制器在途集再兜一层 → 不重复记一笔
    await tester.tap(find.text('请稍候…'));
    await tester.tap(find.text('请稍候…'));
    await tester.pump();
    expect(api.addBodies, hasLength(1));

    api.addGate!.complete();
    await tester.pumpAndSettle();
    expect(api.addBodies, hasLength(1));
    // 完成后恢复可点（js/app.js:693 finally btn.disabled = false）+ 成功 toast
    expect(find.text('请稍候…'), findsNothing);
    expect(
        tester
            .widget<TextButton>(find.byKey(const ValueKey('food-action-u_egg')))
            .onPressed,
        isNotNull);
    expect(find.text('已添加 鸡蛋 · 可继续添加'), findsOneWidget);
  });

  /* ---------- ③ per100 食物：份量弹层 按克加 ---------- */
  testWidgets('③per100「按克加」：初始=baseG 实时预览；± 步进预览随之变化；确认后 body 宏量=portionMacros',
      (tester) async {
    final api = StubHealthApi(foods: [kRiceFood]);
    await tester.pumpWidget(harness(api, initialMeal: 'lunch'));
    await tester.pumpAndSettle();

    await openSheetAndSearch(tester, '米');
    await tester.tap(find.text('按克加'));
    await tester.pumpAndSettle();

    // 标题对齐 js/app.js:721 `${f.name} · 自定义份量`
    expect(find.text('米饭 · 自定义份量'), findsOneWidget);
    // 初始 = baseG=200：portionMacros({116,2.6,25.9,0.3}, 200) = {232, 5.2, 51.8, 0.6}
    // 预览文案对齐 js/app.js:737
    expect(find.text('200g ≈ 232 kcal · 蛋白 5.2g / 碳水 51.8g / 脂肪 0.6g'),
        findsOneWidget);

    // ± 步进（老大 09-27 反馈滑杆改加减，一档 5g）→ 预览数字必须变化
    await tester.tap(find.text('＋'));
    await tester.pumpAndSettle();
    expect(find.text('205g ≈ 238 kcal · 蛋白 5.3g / 碳水 53.1g / 脂肪 0.6g'),
        findsOneWidget); // 200→205 线性换算（portionMacros 口径）
    expect(find.text('200g ≈ 232 kcal · 蛋白 5.2g / 碳水 51.8g / 脂肪 0.6g'),
        findsNothing);
    expect(find.textContaining('kcal · 蛋白'), findsOneWidget);

    await tester.tap(find.text('确认添加'));
    await tester.pumpAndSettle();

    expect(api.addBodies, hasLength(1));
    final body = api.addBodies.single;
    expect(body['name'], '米饭');
    expect(body['date'], todayIso());
    expect(body['meal'], 'lunch');
    // portion = `${g}g`（js/app.js:753/767）；宏量按当前克数线性换算（domain/portion.dart）
    final portion = body['portion'] as String;
    expect(portion, endsWith('g'));
    final g = int.parse(portion.substring(0, portion.length - 1));
    expect(g, isNot(200)); // 确实随 ± 步进变了
    final r = portionMacros(
        Per100.fromMap(Map<String, Object?>.from(kRiceFood['per100'] as Map)), g);
    expect(body['kcal'], r.kcal);
    expect(body['protein'], r.protein);
    expect(body['carb'], r.carb);
    expect(body['fat'], r.fat);
    expect(body['emoji'], '🍚');
    expect(body['image'], 'img/foods/rice.jpg');
  });

  testWidgets('③b 不步进直接确认：200g（baseG 预设）→ body kcal/三素精确等于 232/5.2/51.8/0.6',
      (tester) async {
    final api = StubHealthApi(foods: [kRiceFood]);
    await tester.pumpWidget(harness(api, initialMeal: 'lunch'));
    await tester.pumpAndSettle();

    await openSheetAndSearch(tester, '米');
    await tester.tap(find.text('按克加'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认添加'));
    await tester.pumpAndSettle();

    expect(api.addBodies.single['portion'], '200g');
    expect(api.addBodies.single['kcal'], 232.0);
    expect(api.addBodies.single['protein'], 5.2);
    expect(api.addBodies.single['carb'], 51.8);
    expect(api.addBodies.single['fat'], 0.6);
  });

  /* ---------- ④ 删除：长按 → 确认 → deleteFoodRecord ---------- */

  testWidgets('④长按记录→「确认删除」弹层→deleteFoodRecord 被调且当日重取', (tester) async {
    final api = StubHealthApi(records: [
      StubHealthApi.recordMap(
          id: 'rec_l_1', meal: 'lunch', name: '米饭', portion: '200g', kcal: 232),
    ]);
    await tester.pumpWidget(harness(api, initialMeal: 'lunch'));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey('record-rec_l_1')));
    await tester.pumpAndSettle();
    // 确认弹层文案逐字抄 js/app.js:559
    expect(find.text('确认删除'), findsWidgets);
    expect(find.text('删除后无法恢复，确定要删除这条记录吗？'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, '确认删除'));
    await tester.pumpAndSettle();

    expect(api.deletedIds, ['rec_l_1']);
    expect(api.recordsCalls, 2); // 删除成功 → invalidate 当日重取
    expect(find.text('已删除记录'), findsOneWidget); // js/app.js:571 toast
  });

  testWidgets('④b 长按→取消：不调 deleteFoodRecord', (tester) async {
    final api = StubHealthApi(records: [
      StubHealthApi.recordMap(
          id: 'rec_l_1', meal: 'lunch', name: '米饭', portion: '200g', kcal: 232),
    ]);
    await tester.pumpWidget(harness(api, initialMeal: 'lunch'));
    await tester.pumpAndSettle();

    await tester.longPress(find.byKey(const ValueKey('record-rec_l_1')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();

    expect(api.deletedIds, isEmpty);
    expect(api.recordsCalls, 1);
  });

  /* ---------- ⑤ 空结果文案 ---------- */

  testWidgets('⑤搜索无结果：「没找到「keyword」换个说法…」文案抄 H5（js/app.js:644-645）',
      (tester) async {
    final api = StubHealthApi(foods: const <dynamic>[]);
    await tester.pumpWidget(harness(api, initialMeal: 'lunch'));
    await tester.pumpAndSettle();

    await openSheetAndSearch(tester, '豆腐脑');
    expect(find.text('没找到「豆腐脑」'), findsOneWidget);
    expect(find.text('换个说法，或添加自定义食物'), findsOneWidget);
  });

  /* ---------- M9 终审 I-1 钉①：addRecord 成功链「写删键」缓存面锁 ---------- */

  test('M11-T2 改判据（原 M9终审I-1钉①「写后双删键」）：键保留，但绝不播种到写前旧数'
      '（乐观写 + 提交后 stamp/重建对账两件事共同保证；摘任一件本钉即红）',
      () async {
    final api = StubHealthApi(records: [
      StubHealthApi.recordMap(
          id: 'rec_l_1', meal: 'lunch', name: '米饭', portion: '200g', kcal: 232),
    ]);
    final container = ProviderContainer(
      overrides: [healthApiProvider.overrideWithValue(api)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    final date = todayIso();
    final cache = container.read(swrCacheProvider);
    // 预置「写前旧数」（≙ 读播种面的回写形态），用来验终态里它已被冲掉。
    cache.write(
        'records.$date',
        <Map<String, dynamic>>[
          StubHealthApi.recordMap(
              id: 'rec_old', meal: 'lunch', name: '写前旧餐', portion: '1 份', kcal: 1),
        ]);
    cache.write('summary.$date', Summary.fromMap(StubHealthApi.summaryMap(kcal: 232)));
    expect(cache.read<Object>('records.$date'), isNotNull);
    expect(cache.read<Object>('summary.$date'), isNotNull);
    // 挂监听者 ≙ 首页/记录页在场：invalidate 才会真的重建并重取对账
    final subR = container.listen(recordsProvider(date), (_, _) {});
    final subS = container.listen(summaryProvider(date), (_, _) {});
    addTearDown(subR.close);
    addTearDown(subS.close);

    final ok = await container.read(recordControllerProvider).addRecord(
          date,
          <String, dynamic>{
            'date': date,
            'meal': 'lunch',
            'name': '鸡蛋',
            'portion': '禽蛋 · 1 个约 50g',
            'kcal': 72,
          },
          pendingKey: 'u_egg',
        );
    expect(ok, isTrue);
    expect(api.addBodies, hasLength(1)); // 成功链确实走过网络层（非半途抛错）
    await Future<void>.delayed(const Duration(milliseconds: 1)); // 对账回包落地

    expect(cache.read<Object>('records.$date'), isNotNull,
        reason: 'M11-T2：写后保留键——回访必须先播种，删键＝白屏一个往返');
    final names =
        (cache.read<List<Map<String, dynamic>>>('records.$date')!)
            .map((e) => e['name'])
            .toList();
    expect(names, isNot(contains('写前旧餐')),
        reason: '旧数必须被云端真行冲掉（这才是 I-1 当初要守的不变量）');
    expect(names, containsAll(<String>['米饭', '鸡蛋']));
    // summary 只断「键保留」：对账以云端为准，而本桩的 summary 恒返 kcal=0
    // （未随入库累加），故「环数=232+72」在这里不成立——环的乐观加算与失败
    // 回滚由 test/record/optimistic_write_test.dart ①②⑥ 覆盖，不在本桩形上重复钉。
    expect(cache.read<Object>('summary.$date'), isNotNull);
  });
}
