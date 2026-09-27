// ShiguangFlutter/test/food_lib_sheet_test.dart
// M7-T4「我的食物库」管理弹层十钉。行为权威源 js/app.js:1288-1398
// （openFoodLib/renderLibList/lib-list 事件族）+ index.html:561-575（lib-sheet DOM）。
// 文案逐字口径：seg 双钮「我的自定义/内置常菜」（:570-571）、sub
// 「自定义 N 条 · 点餐次标签可改归类」/「内置 N 条 · 已移除 M」(:1309/:1324)、
// 归类 toast「已归到早餐/零食/正餐 · 搜索时只在对应餐次出现」(:1362，
// lunch/dinner 同归「正餐」文案——CF_MEAL_MAP :1176 + kind 三态 :1316)、
// 删除确认「删除自定义食物/删除后不可恢复；已记录的饮食不受影响。」(:1369)
// →「已删除」(:1374)、内置钮 移除⇄恢复 + 「已移除「名」/已恢复「名」」
// (:1394，提交 setHiddenFoods(全量 ids) :1385-1391)、加载失败
// 「加载失败：msg||网络异常」+ 重试 (:1338-1339)、空态 (:1320)。
// 层内 toast 走 SheetToast（OverlayEntry，Ticker 驱动 2400ms）：toast 断言前
// 只 pump()，不可 pumpAndSettle（动画跑完 toast 自删，profile_reminders ③ 同法）。
// 回归钉：管理链路 bodies id 恒裸值不含 cf_（cf_ 前缀只在搜索结果 id，
// 云 index.js:82；listCustomFoods 回裸 _id，index.js:300）。
// 修复轮 1（评审 Important#1）：钉⑧ 增「空态在场时下方有可点添加钮」断言；
// 新增钉⑩/⑩b —— #lib-add（index.html:574）→ closeFoodLib → openCustomFoodSheet
// 链路可达（js/app.js:1347），钮双 tab/失败态常驻。
// M9-T4（perf 批 A1/A2/A3）：新增 M9-T4钉（首开单帧骨架+并行预取各 1 次；关层
// 重开会话缓存直显零新请求）与钉b（写路径先删键再刷新）；钉①「内置不预取」
// 语义按本任务有意变更为「随并行预取取一次」，行渲染/sub/文案逐字各钉未弱化；
// 关层 ✕ 走 ensureSemantics + bySemanticsLabel(RegExp(r'^关闭'))（goal_edit ④
// 定式：label 并子 Text「✕」须前锚；handle 须用例体内 dispose）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/theme.dart' show shiguangTheme;
import 'package:shiguang_flutter/data/api_client.dart' show ApiException;
import 'package:shiguang_flutter/data/swr_cache.dart' show swrCacheProvider;
import 'package:shiguang_flutter/domain/dates.dart' show localIso;
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider, plateDateProvider;
import 'package:shiguang_flutter/features/notifications/reminder_scheduler.dart'
    show reminderSchedulerProvider;
import 'package:shiguang_flutter/features/profile/food_lib_sheet.dart';
import 'package:shiguang_flutter/features/profile/profile_screen.dart'
    show ProfileScreen;
import 'package:shiguang_flutter/features/record/custom_food_sheet.dart'
    show cfKcalKey, cfNameKey, cfSaveAddKey;
import 'package:shiguang_flutter/features/scale/scale_service.dart';

import 'harness.dart';
import 'scale_fakes.dart';
import 'stubs/stub_health_api.dart';

/// 默认自定义库：裸 id（回归钉观测面）+ 早/正餐/未归类三档 kind 覆盖
List<Map<String, dynamic>> customStore() => <Map<String, dynamic>>[
      StubHealthApi.cfFoodMap(
        id: 'raw_1',
        name: '鸡胸肉盖饭',
        kcal: 543,
        grams: 150,
        meals: ['breakfast'],
        protein: 43,
        carb: 66,
        fat: 12,
        portion: '150g',
        emoji: '🍗',
      ),
      StubHealthApi.cfFoodMap(
        id: 'raw_2',
        name: '测试饭团',
        kcal: 234,
        grams: 100,
        meals: ['lunch', 'dinner'],
        protein: 5,
        carb: 40,
        fat: 6,
        portion: '100g',
        emoji: '🍙',
      ),
      StubHealthApi.cfFoodMap(id: 'raw_3', name: '无归类汤', kcal: 90),
    ];

List<Map<String, dynamic>> builtinStore() => <Map<String, dynamic>>[
      StubHealthApi.builtinFoodMap(
          id: 'u_01', name: '纯牛奶', meta: '奶类 · 1 盒 250ml', kcal: 175, emoji: '🥛'),
      StubHealthApi.builtinFoodMap(
          id: 'u_06', name: '米饭', meta: '主食 · 1 碗约 150g', kcal: 174, emoji: '🍚', hidden: true),
      StubHealthApi.builtinFoodMap(
          id: 'u_11', name: '西兰花', meta: '蔬菜 · 1 份约 200g', kcal: 68, emoji: '🥦', hidden: true),
    ];

class _Host extends ConsumerStatefulWidget {
  const _Host();

  @override
  ConsumerState<_Host> createState() => _HostState();
}

class _HostState extends ConsumerState<_Host> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: TextButton(
          // M7 终审 I1：宿主传 ref（openFoodLibSheet 续链直读 plateDateProvider）
          onPressed: () => openFoodLibSheet(context, ref),
          child: const Text('open-lib'),
        ),
      ),
    );
  }
}

Future<void> pumpSheet(WidgetTester tester, StubHealthApi api,
    {String? plateDate}) async {
  await useBigSurface(tester);
  final container = ProviderContainer(
    overrides: [healthApiProvider.overrideWithValue(api)],
    retry: (_, _) => null,
  );
  if (plateDate != null) {
    // M7 终审 I1：预置共享日期源（≙ 用户已在首页 ‹ 翻到该日）
    container.read(plateDateProvider.notifier).state = plateDate;
  }
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    // 真主题必须上（弹层族与真机同通道，custom_food_sheet_test 同法）
    child: MaterialApp(theme: shiguangTheme(), home: const _Host()),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open-lib'));
  await tester.pumpAndSettle(); // 滑入 + 首载（此间无 toast，可 settle）
}

/// 「toast 可能在场」的常规 pump 对（层内 SheetToast 不可 pumpAndSettle 的替代）
Future<void> flush(WidgetTester tester) =>
    tester.pump().then((_) => tester.pump());

Future<void> tapKey(WidgetTester tester, Key key) async {
  final f = find.byKey(key);
  await tester.ensureVisible(f);
  await tester.pump(); // 滚动动画落定，取位不过期
  await tester.tap(f);
}

Future<void> tapText(WidgetTester tester, String text) async {
  final f = find.text(text);
  await tester.ensureVisible(f);
  await tester.pump();
  await tester.tap(f);
}

/// 懒构建行取回：测试环境弹层 0.72*600=432px，行高约 240，第三行起落在
/// ListView 构建区外（真机 0.72*屏高不存在此界）——先拖滚再 ensureVisible
Future<void> reveal(WidgetTester tester, Finder f) async {
  for (var i = 0; i < 6 && f.evaluate().isEmpty; i++) {
    await tester.drag(find.byType(ListView), const Offset(0, -160));
    await tester.pumpAndSettle();
  }
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
}

bool segSelected(WidgetTester tester, String tab) =>
    tester.widget<LibSegButton>(find.byKey(libSegKey(tab))).selected;

bool mealSelected(WidgetTester tester, String id, String kind) =>
    tester.widget<LibMealChip>(find.byKey(libMealKey(id, kind))).selected;

String subText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(libSubKey)).data!;

/// 内置行钮文案（key 挂 TextButton，取其后代 Text.data——移除⇄恢复二态观测面）
String togLabel(WidgetTester tester, String id) => tester
    .widget<Text>(find.descendant(
        of: find.byKey(libTogKey(id)), matching: find.byType(Text)))
    .data!;

/// 「我的」页入口用例的挂具（profile_screen_test 组合根同构，零网络零插件）
Future<void> pumpProfile(WidgetTester tester, StubHealthApi api) async {
  await useBigSurface(tester);
  final container = ProviderContainer(
    overrides: [
      healthApiProvider.overrideWithValue(api),
      reminderSchedulerProvider.overrideWithValue(NoopReminderScheduler()),
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
    child: MaterialApp(theme: shiguangTheme(), home: const ProfileScreen()),
  ));
  await tester.pumpAndSettle();
}

void main() {
  /* ---------- 钉⓪「我的」页入口（spec §4.2：提醒卡后 soft 钮，R4 视觉） ---------- */

  testWidgets('钉⓪ 入口钮「食物库」在提醒卡后；点击开「我的食物库」层', (tester) async {
    final api = StubHealthApi(libCustomFoods: customStore());
    await pumpProfile(tester, api);

    final btn = find.text('食物库');
    expect(btn, findsOneWidget); // index.html:249 文案逐字
    final btnRect = tester.getRect(btn);
    final cardRect = tester.getRect(find.text('消息提醒 · 系统通知'));
    expect(btnRect.top, greaterThan(cardRect.bottom),
        reason: '入口位于提醒卡之后、退出登录之前');

    await tester.tap(btn);
    await tester.pumpAndSettle();
    expect(find.text('我的食物库'), findsOneWidget); // index.html:566 逐字
    expect(api.listFoodsCalls, 1);
  });

  /* ---------- 钉① 默认自定义 tab + sub 文案 + 行族渲染 ---------- */

  testWidgets('钉① 开层默认自定义 tab；sub「自定义 N 条 · 点餐次标签可改归类」；'
      '行 meta「150g · 543 kcal · 蛋白 43g / 碳水 66g / 脂肪 12g」逐字；'
      '内置随并行预取取一次（M9-T4/A3 有意改 H5「不预取」原语义）',
      (tester) async {
    final api = StubHealthApi(
        libCustomFoods: customStore(), libBuiltins: builtinStore());
    await pumpSheet(tester, api);

    expect(find.text('我的食物库'), findsOneWidget);
    expect(segSelected(tester, 'custom'), isTrue); // 默认 tab（openFoodLib :1293）
    expect(segSelected(tester, 'builtin'), isFalse);
    expect(subText(tester), '自定义 3 条 · 点餐次标签可改归类'); // :1309 逐字
    expect(find.text('鸡胸肉盖饭'), findsOneWidget);
    expect(
        find.text('150g · 543 kcal · 蛋白 43g / 碳水 66g / 脂肪 12g'),
        findsOneWidget); // :1315 meta 模板（grams 有值带前缀）
    // 测试环境弹层仅 0.72*600=432px 高，第三行落在 ListView 懒构建区外
    //（真机 0.72*屏高足够）——先滚到在场再断言
    await reveal(tester, find.text('90 kcal · 蛋白 0g / 碳水 0g / 脂肪 0g'));
    expect(find.text('90 kcal · 蛋白 0g / 碳水 0g / 脂肪 0g'), findsOneWidget,
        reason: 'grams=0 → 前缀省略（:1315 三元falsy支）');
    expect(api.builtinCalls, 1,
        reason: 'M9-A3 并行预取：内置首开即随自定义拉一次（原钉「未开不取数」'
        '被本任务有意替换；切 tab 命中缓存零新请求仍由钉②守住）');
    expect(api.listFoodsCalls, 1);
  });

  /* ---------- 钉② 内置 tab：sub + 钮二态 + 缓存不重取 ---------- */

  testWidgets('钉② 内置 tab：sub「内置 N 条 · 已移除 M」；hidden 行钮「恢复」、'
      '未移除钮「移除」；meta「奶类 · 1 盒 250ml · 175 kcal」；来回切 tab 只取一次'
      '（≙ libBuiltinCache :1322）', (tester) async {
    final api = StubHealthApi(
        libCustomFoods: customStore(), libBuiltins: builtinStore());
    await pumpSheet(tester, api);

    await tapKey(tester, libSegKey('builtin'));
    await tester.pumpAndSettle();
    expect(segSelected(tester, 'builtin'), isTrue);
    expect(subText(tester), '内置 3 条 · 已移除 2'); // :1324 逐字
    expect(find.text('奶类 · 1 盒 250ml · 175 kcal'), findsOneWidget); // :1330
    expect(togLabel(tester, 'u_01'), '移除');
    expect(togLabel(tester, 'u_06'), '恢复');

    await tapKey(tester, libSegKey('custom'));
    await tester.pumpAndSettle();
    await tapKey(tester, libSegKey('builtin'));
    await tester.pumpAndSettle();
    expect(api.builtinCalls, 1, reason: '缓存命中不再发请求（:1322 ||短路）');
    expect(api.listFoodsCalls, 2, reason: '自定义 tab 每次 renderLibList 重取');
  });

  /* ---------- 钉③ 归类点按链（kind 三态映射逐字 CF_MEAL_MAP） ---------- */

  testWidgets('钉③ 点「正餐」钮：meals 提交 [lunch,dinner]、toast「已归到正餐 · …」、'
      '成功后重取列表、高亮跟变', (tester) async {
    final api = StubHealthApi(libCustomFoods: customStore());
    await pumpSheet(tester, api);

    expect(mealSelected(tester, 'raw_1', 'breakfast'), isTrue); // meals=['breakfast']
    expect(mealSelected(tester, 'raw_1', 'lunch'), isFalse);

    await tapKey(tester, libMealKey('raw_1', 'lunch'));
    await flush(tester);

    expect(api.mealSetBodies.single.id, 'raw_1');
    expect(api.mealSetBodies.single.meals, ['lunch', 'dinner']); // CF_MEAL_MAP :1176
    expect(find.text('已归到正餐 · 搜索时只在对应餐次出现'), findsOneWidget); // :1362 逐字
    expect(api.listFoodsCalls, 2); // 成功 → renderLibList 重取（:1363）
    expect(mealSelected(tester, 'raw_1', 'lunch'), isTrue,
        reason: '重取回包 meals=[lunch,dinner] → kind=lunch 高亮');
    expect(mealSelected(tester, 'raw_1', 'breakfast'), isFalse);
  });

  testWidgets('钉③b 点「零食」→ [snack]「已归到零食 · …」；点「早餐」→ [breakfast]「已归到早餐 · …」',
      (tester) async {
    final api = StubHealthApi(libCustomFoods: customStore());
    await pumpSheet(tester, api);

    await tapKey(tester, libMealKey('raw_2', 'snack'));
    await flush(tester);
    expect(api.mealSetBodies.single.meals, ['snack']);
    expect(find.text('已归到零食 · 搜索时只在对应餐次出现'), findsOneWidget);

    await tapKey(tester, libMealKey('raw_3', 'breakfast'));
    await flush(tester);
    expect(api.mealSetBodies.last.meals, ['breakfast']);
    expect(find.text('已归到早餐 · 搜索时只在对应餐次出现'), findsOneWidget);
  });

  testWidgets('钉③c 归类失败 → toast「设置失败：boom」、不重取、钮可再点（≙ disabled 复位）',
      (tester) async {
    final api = StubHealthApi(libCustomFoods: customStore())
      ..setMealsError = ApiException('boom');
    await pumpSheet(tester, api);

    await tapKey(tester, libMealKey('raw_1', 'snack'));
    await flush(tester);
    expect(find.text('设置失败：boom'), findsOneWidget); // :1364 逐字
    expect(api.listFoodsCalls, 1, reason: '失败支不重取（:1363 在 try 成功路径）');

    api.setMealsError = null;
    await tapKey(tester, libMealKey('raw_1', 'snack'));
    await flush(tester);
    expect(api.mealSetBodies, hasLength(2), reason: '失败后可重按（disabled 复位）');
  });

  /* ---------- 钉④ kind 高亮三态（cfMealKind :1178-1185） ---------- */

  testWidgets('钉④ meals=[lunch,dinner]→正餐亮；=[]→三钮全不亮；含 dinner→正餐',
      (tester) async {
    final api = StubHealthApi(libCustomFoods: customStore());
    await pumpSheet(tester, api);

    expect(mealSelected(tester, 'raw_2', 'lunch'), isTrue); // lunch,dinner→kind lunch
    expect(mealSelected(tester, 'raw_2', 'breakfast'), isFalse);
    // raw_3 行在测试视口构建区外（同钉①注释）——滚入后再断言三钮
    await reveal(tester, find.byKey(libMealKey('raw_3', 'breakfast')));
    expect(mealSelected(tester, 'raw_3', 'breakfast'), isFalse); // 未归类无高亮
    expect(mealSelected(tester, 'raw_3', 'lunch'), isFalse);
    expect(mealSelected(tester, 'raw_3', 'snack'), isFalse);
    // 单 dinner 也归「正餐」档（cfMealKind indexOf lunch||dinner 支 :1183）
    api.libCustomFoods = <Map<String, dynamic>>[
      StubHealthApi.cfFoodMap(id: 'raw_4', name: '晚汤', meals: ['dinner']),
    ];
    await tapKey(tester, libSegKey('builtin')); // 借 tab 往返触发重取
    await tester.pumpAndSettle();
    await tapKey(tester, libSegKey('custom'));
    await tester.pumpAndSettle();
    expect(mealSelected(tester, 'raw_4', 'lunch'), isTrue);
  });

  /* ---------- 钉⑤ 删除确认链 ---------- */

  testWidgets('钉⑤ 删除钮→确认层（标题/文案逐字）→取消：零请求零重取；'
      '再点→「确认删除」→ DELETE 裸 id → toast「已删除」→ 重取行消失', (tester) async {
    final api = StubHealthApi(libCustomFoods: customStore());
    await pumpSheet(tester, api);

    await tapKey(tester, libDelKey('raw_1'));
    await tester.pumpAndSettle();
    expect(find.text('删除自定义食物'), findsOneWidget); // :1369 标题逐字
    expect(find.text('删除后不可恢复；已记录的饮食不受影响。'), findsOneWidget); // :1369 逐字

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(api.deletedCustomIds, isEmpty); // 取消零请求（:1370 if(!ok) return）
    expect(api.listFoodsCalls, 1);

    await tapKey(tester, libDelKey('raw_1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认删除'));
    await flush(tester);
    expect(api.deletedCustomIds, ['raw_1']);
    expect(find.text('已删除'), findsOneWidget); // :1374 逐字
    await tester.pump(const Duration(seconds: 3)); // toast 自删后再验列表
    await tester.pumpAndSettle();
    expect(find.text('鸡胸肉盖饭'), findsNothing); // 重取回包已无该行
    expect(api.listFoodsCalls, 2);
  });

  testWidgets('钉⑤b 删除失败 → toast「删除失败：boom」、行不消失', (tester) async {
    final api = StubHealthApi(libCustomFoods: customStore())
      ..deleteCustomError = ApiException('boom');
    await pumpSheet(tester, api);

    await tapKey(tester, libDelKey('raw_1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认删除'));
    await flush(tester);
    expect(find.text('删除失败：boom'), findsOneWidget); // :1376 逐字
    expect(api.listFoodsCalls, 1, reason: '失败支不重取');
    expect(find.text('鸡胸肉盖饭'), findsOneWidget);
  });

  /* ---------- 钉⑥ 内置移除/恢复：全量 ids 提交 + 本地翻转不重取 ---------- */

  testWidgets('钉⑥ 点「移除」→ setHiddenFoods 收到全量 ids（含既有已移除）→ '
      '钮变「恢复」+ sub 已移除+1 + toast「已移除「纯牛奶」」；再点恢复 → ids 摘除 + '
      '「已恢复「纯牛奶」」；全程 getBuiltinFoods 只 1 次', (tester) async {
    final api = StubHealthApi(
        libCustomFoods: customStore(), libBuiltins: builtinStore());
    await pumpSheet(tester, api);
    await tapKey(tester, libSegKey('builtin'));
    await tester.pumpAndSettle();

    await tapKey(tester, libTogKey('u_01'));
    await flush(tester);
    expect(api.hiddenSubmissions.single, ['u_06', 'u_11', 'u_01'],
        reason: '全量替换语义（:1385-1391：现有 hidden + 本条）');
    expect(togLabel(tester, 'u_01'), '恢复');
    expect(subText(tester), '内置 3 条 · 已移除 3');
    expect(find.text('已移除「纯牛奶」'), findsOneWidget); // :1394 逐字

    await tapKey(tester, libTogKey('u_01'));
    await flush(tester);
    expect(api.hiddenSubmissions.last, ['u_06', 'u_11']); // 摘除本条
    expect(togLabel(tester, 'u_01'), '移除');
    expect(find.text('已恢复「纯牛奶」'), findsOneWidget); // :1394 逐字
    expect(api.builtinCalls, 1, reason: '本地 cache 翻转不重取（:1392 直改 item.hidden）');
  });

  testWidgets('钉⑥b 提交失败 → toast「操作失败：boom」、钮态与 sub 计数均不变',
      (tester) async {
    final api = StubHealthApi(
        libCustomFoods: customStore(), libBuiltins: builtinStore())
      ..setHiddenError = ApiException('boom');
    await pumpSheet(tester, api);
    await tapKey(tester, libSegKey('builtin'));
    await tester.pumpAndSettle();

    await tapKey(tester, libTogKey('u_01'));
    await flush(tester);
    expect(find.text('操作失败：boom'), findsOneWidget); // :1395 逐字
    expect(togLabel(tester, 'u_01'), '移除');
    expect(subText(tester), '内置 3 条 · 已移除 2'); // 未翻转（flip 在 await 之后）
  });

  /* ---------- 钉⑦ 加载失败空态 + 重试 ---------- */

  testWidgets('钉⑦ 加载失败 → 「⚠️ 加载失败：boom」+ 重试钮；清空错误点重试 → 恢复行族',
      (tester) async {
    final api = StubHealthApi(libCustomFoods: customStore())
      ..listFoodsError = ApiException('boom');
    await pumpSheet(tester, api);

    expect(find.text('⚠️'), findsOneWidget); // :1338 art 族
    expect(find.text('加载失败：boom'), findsOneWidget); // :1338 逐字
    expect(find.text('重试'), findsOneWidget); // #lib-retry

    api.listFoodsError = null;
    await tapText(tester, '重试');
    await tester.pumpAndSettle();
    expect(api.listFoodsCalls, 2);
    expect(find.text('鸡胸肉盖饭'), findsOneWidget);
    expect(subText(tester), '自定义 3 条 · 点餐次标签可改归类');
  });

  /* ---------- 钉⑧ 自定义空态 + 层底添加钮（修复轮 1：Important#1） ---------- */

  testWidgets('钉⑧ 自定义空库 → 「还没有自定义食物\n点下方按钮添加你的常吃菜」（:1320 逐字）；'
      '空态文案在场时下方存在可点「＋ 添加自定义食物」钮（≙ index.html:574 层底常驻）',
      (tester) async {
    final api = StubHealthApi(libCustomFoods: <Map<String, dynamic>>[]);
    await pumpSheet(tester, api);
    expect(find.text('还没有自定义食物\n点下方按钮添加你的常吃菜'), findsOneWidget);
    expect(subText(tester), '自定义 0 条 · 点餐次标签可改归类');

    // 评审钉：空态指涉「点下方按钮」必须落地——层底钮在场、可点、位于文案下方
    expect(find.text('＋ 添加自定义食物'), findsOneWidget); // index.html:574 逐字
    expect(tester.widget<FilledButton>(find.byKey(libAddKey)).onPressed,
        isNotNull);
    final emptyRect =
        tester.getRect(find.text('还没有自定义食物\n点下方按钮添加你的常吃菜'));
    final addRect = tester.getRect(find.byKey(libAddKey));
    expect(addRect.top, greaterThan(emptyRect.bottom),
        reason: '钮在空态文案下方（btn-block 层底）');
  });

  /* ---------- 钉⑩ 添加钮链路（≙ js/app.js:1347 closeFoodLib→openCustomFoodSheet(true)） ---------- */

  testWidgets('钉⑩ 点「＋ 添加自定义食物」→ 关管理层、开自定义食物表单（cf-name 在场）；'
      '管理链路不 mock 相机——表单打开即证', (tester) async {
    final api = StubHealthApi(libCustomFoods: <Map<String, dynamic>>[]);
    await pumpSheet(tester, api);

    await tapKey(tester, libAddKey);
    await tester.pumpAndSettle(); // 管理层 pop 动画
    await tester.pumpAndSettle(); // openFoodLibSheet 续链推入表单层

    expect(find.text('我的食物库'), findsNothing); // ≙ closeFoodLib()（先关层）
    expect(find.text('自定义食物'), findsOneWidget); // 表单标题 index.html:509
    expect(find.byKey(cfNameKey), findsOneWidget); // 表单字段在场=链路可达
    expect(find.byKey(cfSaveAddKey), findsOneWidget);
    expect(api.listFoodsCalls, 1, reason: '开表单不触发额外取数');
  });

  testWidgets('钉⑩b 添加钮常驻：内置 tab 与加载失败态均在层底在场（#lib-add 在 #lib-list 之外）',
      (tester) async {
    final api = StubHealthApi(
        libCustomFoods: customStore(), libBuiltins: builtinStore());
    await pumpSheet(tester, api);
    expect(find.byKey(libAddKey), findsOneWidget); // 自定义 tab

    await tapKey(tester, libSegKey('builtin'));
    await tester.pumpAndSettle();
    expect(find.byKey(libAddKey), findsOneWidget); // 内置 tab（双 tab 均在）

    api.listFoodsError = ApiException('boom');
    await tapKey(tester, libSegKey('custom'));
    await tester.pumpAndSettle();
    expect(find.text('加载失败：boom'), findsOneWidget);
    expect(find.byKey(libAddKey), findsOneWidget); // 失败态仍常驻
  });

  /* ---------- 钉⑨ 回归钉：管理链路 bodies id 恒裸值（不含 cf_ 前缀） ---------- */

  testWidgets('钉⑨ 归类/删除/hidden 全链路的 id 均为裸值不含 cf_ '
      '（cf_ 前缀只存在于搜索结果 id，云 index.js:82；管理页不经剥除路径）',
      (tester) async {
    final api = StubHealthApi(
        libCustomFoods: customStore(), libBuiltins: builtinStore());
    await pumpSheet(tester, api);

    await tapKey(tester, libMealKey('raw_1', 'snack'));
    await flush(tester);
    await tapKey(tester, libDelKey('raw_2'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认删除'));
    await flush(tester);
    await tapKey(tester, libSegKey('builtin'));
    await tester.pumpAndSettle();
    await tapKey(tester, libTogKey('u_01'));
    await flush(tester);

    expect(api.mealSetBodies.map((e) => e.id), everyElement('raw_1'));
    expect(
        api.mealSetBodies.every((e) => !e.id.contains('cf_')), isTrue);
    expect(api.deletedCustomIds, ['raw_2']);
    expect(api.deletedCustomIds.every((e) => !e.contains('cf_')), isTrue);
    expect(api.hiddenSubmissions.single,
        everyElement(isNot(contains('cf_'))));
  });

  /* ---------- 钉⑪ M7-T8 卫生批：在途即时置灰（T4 Minor②）+ lib-add 连点闸（T4 Minor⑤） ---------- */

  testWidgets('钉⑪a 归类在途即时置灰：慢网挂回包，点下单帧泵后钮即 disabled=true（≙ H5 :1359 即时赋值）；成功链后复位',
      (tester) async {
    final api = StubHealthApi(libCustomFoods: customStore())
      ..setMealsGate = Completer<void>();
    await pumpSheet(tester, api);

    await tapKey(tester, libMealKey('raw_1', 'lunch'));
    await tester.pump(); // 仅一泵：回包挂在闸上，任何重取都未发生

    // M7-T8 修前红：_busy 裸 mutate 无 setState → 本帧钮仍 disabled=false
    expect(
        tester.widget<LibMealChip>(find.byKey(libMealKey('raw_1', 'lunch'))).disabled,
        isTrue,
        reason: '在途当帧即灰（:1359 mealChip.disabled=true 即时观感）');
    // 同钮重按被闸拦截（幂等：不双发）
    await tapKey(tester, libMealKey('raw_1', 'lunch'));
    expect(api.mealSetBodies, hasLength(1));

    api.setMealsGate!.complete(); // 放行：toast + 重取 + finally 复位
    await flush(tester);
    expect(find.text('已归到正餐 · 搜索时只在对应餐次出现'), findsOneWidget);
    expect(
        tester.widget<LibMealChip>(find.byKey(libMealKey('raw_1', 'lunch'))).disabled,
        isFalse,
        reason: '链路终态复位（≙ H5 成功支 renderLibList 重建非灰钮）');
  });

  testWidgets('钉⑪b lib-add 连点闸：pop 窗口内同帧二击 onPressed（连点等价模拟，绕过路由 AbsorbPointer 的输入屏蔽）不穿透下方路由，表单恰开一次',
      (tester) async {
    final api = StubHealthApi(libCustomFoods: customStore());
    await pumpSheet(tester, api);

    await tester.ensureVisible(find.byKey(libAddKey));
    await tester.pump();
    final btn = tester.widget<FilledButton>(find.byKey(libAddKey));
    btn.onPressed!(); // 第一击：pop(true) 起关闭动画
    btn.onPressed!(); // 第二击：动画窗口内（层仍在 Navigator 栈）——M7-T8 修前
    // 红：二次 pop 把模态路由再摘一层/打断转场断言，openFoodLibSheet 续链
    // 语境被破坏，表单不开或宿主路由被吞
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(find.text('自定义食物'), findsOneWidget); // 表单恰开一次（链路仍可达）
    expect(find.byKey(cfNameKey), findsOneWidget);
    expect(find.text('open-lib'), findsOneWidget,
        reason: '弹层下方宿主路由未被第二发 pop 吞掉');
  });

  /* ---------- M7 终审 I1：lib-add 记餐日期锚 plate 日期（≙ H5 :1244 全局 state.date） ---------- */

  testWidgets('I1钉 plate=昨天时食物库「＋添加」→「保存并记入」→ 记餐 body date=昨天'
      '（修前 todayIso() 写死即落今天，背离 H5 state.date）', (tester) async {
    final now = DateTime.now();
    final y = localIso(DateTime(now.year, now.month, now.day - 1)); // ‹ 翻一天 ≙ T1 语义
    final api = StubHealthApi(libCustomFoods: <Map<String, dynamic>>[]);
    await pumpSheet(tester, api, plateDate: y);

    await tapKey(tester, libAddKey);
    await tester.pumpAndSettle(); // 管理层 pop 动画
    await tester.pumpAndSettle(); // 续链开表单

    await tester.enterText(find.byKey(cfNameKey), '回归饭团');
    await tester.enterText(find.byKey(cfKcalKey), '123');
    await tester.pump();
    await tapKey(tester, cfSaveAddKey); // 保存并记入
    await tester.pumpAndSettle();

    expect(api.customFoodBodies, hasLength(1)); // 入库链先成
    expect(api.addBodies, hasLength(1));
    expect(api.addBodies.single['date'], y,
        reason: '记餐落 plate 日期（H5 :1244 addFoodRecord({date: state.date})）');
  });

  /* ---------- M9-T4 钉：会话缓存重开直显 + 并行预取 + 骨架（A1/A2/A3） ---------- */

  testWidgets('M9-T4钉 首开单帧有骨架、双列表并行各拉1次；关层重开缓存直显'
      '——首帧无骨架、零新请求（foods.* 无 TTL，写路径才失效——spec §1 口径）',
      (tester) async {
    final api = StubHealthApi(
      libCustomFoods: <Map<String, dynamic>>[
        StubHealthApi.cfFoodMap(id: 'cf1', name: '妈妈牌红烧肉'),
      ],
      libBuiltins: <Map<String, dynamic>>[
        for (var i = 1; i <= 35; i++)
          StubHealthApi.builtinFoodMap(id: 'b$i', name: '内$i'),
      ], // 35 条契约形状
    );
    await useBigSurface(tester);
    // bySemanticsLabel 需语义树在场（✕ 钮 ≙ :567 aria-label '关闭'，goal_edit ④
    // 定式：handle 须在用例体内 dispose——期末校验早于 addTearDown）
    final semantics = tester.ensureSemantics();
    final container = ProviderContainer(
      overrides: [healthApiProvider.overrideWithValue(api)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: shiguangTheme(), home: const _Host()),
    ));
    await tester.pumpAndSettle();

    // 首开：未回包单帧 → 骨架在场（M9-A2 替换旧「加载中…」文本）
    await tester.tap(find.text('open-lib'));
    await tester.pump(); // 仅一帧：若走网络必有骨架
    expect(find.byKey(const ValueKey('lib-skeleton')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.textContaining('自定义 1 条'), findsOneWidget); // H5 哨兵逐字
    await tapKey(tester, libSegKey('builtin'));
    await tester.pumpAndSettle();
    expect(find.textContaining('内置 35 条 · 已移除 0'), findsOneWidget); // :1324 口径
    expect(api.listFoodsCalls, 1, reason: '并行预取：自定义首开拉 1 次');
    expect(api.builtinCalls, 1, reason: '并行预取：内置同轮也拉 1 次（M9-A3）');

    // 关层再开：双键缓存命中——首帧无骨架、直显、零新请求
    // （label 与子 Text「✕」并节点 ⇒ RegExp 前缀，goal_edit_sheet :196 同式）
    await tester.tap(find.bySemanticsLabel(RegExp(r'^关闭')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('open-lib'));
    await tester.pump(); // 仅一帧：若走网络必有骨架
    expect(find.byKey(const ValueKey('lib-skeleton')), findsNothing,
        reason: '重开 0ms 直显（M9-A1 会话缓存，跨弹层开关存活）');
    expect(find.textContaining('自定义 1 条'), findsOneWidget);
    expect(api.listFoodsCalls, 1,
        reason: 'foods.custom 命中即短路——无 TTL，写路径才删键（spec §1）');
    expect(api.builtinCalls, 1, reason: 'foods.builtin 同上');
    await tester.pumpAndSettle(); // 收尾：模态转场落定
    semantics.dispose();
  });

  testWidgets('M9-T4钉b 写路径「先删键再刷新」：删除成功链后 foods.custom 键随新列表'
      '（无 raw_1）；重开弹层直显已是最新数据', (tester) async {
    final api = StubHealthApi(libCustomFoods: customStore());
    await useBigSurface(tester);
    final semantics = tester.ensureSemantics(); // 钉b 同法：关层用 ✕ 语义钮
    final container = ProviderContainer(
      overrides: [healthApiProvider.overrideWithValue(api)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: shiguangTheme(), home: const _Host()),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open-lib'));
    await tester.pumpAndSettle(); // 首开取数入键

    await tapKey(tester, libDelKey('raw_1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('确认删除'));
    await flush(tester);
    await tester.pumpAndSettle(); // 删键 → _render 重取 → 新列表回写
    final cached =
        container.read(swrCacheProvider).read<List<dynamic>>('foods.custom');
    expect(cached, isNotNull);
    expect(cached!.map((f) => (f as Map)['id']), isNot(contains('raw_1')),
        reason: '成功链删键后重取回写——键面不留旧行（对照 weight_log_card :145 定式）');

    // 关层重开：直显的即是删后 2 条（若写链漏删键，重开首帧仍会显 3 条旧缓存）
    await tester.tap(find.bySemanticsLabel(RegExp(r'^关闭')).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('open-lib'));
    await tester.pump(); // 一帧：缓存命中零请求直显
    expect(find.text('鸡胸肉盖饭'), findsNothing);
    expect(subText(tester), '自定义 2 条 · 点餐次标签可改归类');
    expect(api.listFoodsCalls, 2, reason: '开1 + 删后重取1；重开命中零新请求');
    await tester.pumpAndSettle();
    semantics.dispose();
  });
}
