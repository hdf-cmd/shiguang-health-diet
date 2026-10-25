// ShiguangFlutter/test/food_scan_entry_test.dart
// M13-T7：拍照识菜两处入口接线。
// 判据（task-7-brief）：
// ① 记一笔弹层搜索框右侧 📷（sheet-scan-open）→ 来源选择「从相册选」→
//    识别成功 → showShiguangSheet 打开 FoodScanSheet（recordMeal=true，
//    date/meal 用弹层入参）；
// ② scanError=ApiException('网络异常') → 「识别失败：网络异常」、不打开
//    FoodScanSheet；「手动填写」落自定义食物表单；
// ③ 食物库层底「📷 拍照添加」（lib-scan-add）存在且走同一流程
//    （recordMeal=false、date=plateDateProvider、meal='lunch'）；
// ④ 修复轮（评审 Important#1）：食物库入口扫码保存入库、表单关闭返回后
//    必须重取自定义列表——listFoodsCalls 增加、空态消失、sub 计数更新；
// 选图一律经 scanImagePickProvider 注入固定 dataURL（不拉起系统选择器）；
// 识别经 StubHealthApi.scanFood（scanResult/scanError/scanCalls）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/theme.dart' show shiguangTheme;
import 'package:shiguang_flutter/data/api_client.dart' show ApiException;
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider, plateDateProvider;
import 'package:shiguang_flutter/features/profile/food_lib_sheet.dart'
    show libScanAddKey, openFoodLibSheet;
import 'package:shiguang_flutter/features/record/custom_food_sheet.dart'
    show cfNameKey;
import 'package:shiguang_flutter/features/record/food_freq.dart'
    show FoodFreqStore, foodFreqStoreProvider;
import 'package:shiguang_flutter/features/record/food_scan_sheet.dart'
    show
        FoodScanSheet,
        estimateGramsKey,
        estimateManualKey,
        estimateNameKey,
        estimateSubmitKey,
        scanHintKey,
        scanImagePickProvider,
        scanSaveKey;
import 'package:shiguang_flutter/features/record/search_sheet.dart'
    show SearchSheet;

import 'harness.dart' show useBigSurface;
import 'stubs/stub_health_api.dart';

/// 内存版频次存储（桌面测试不注入会抛 UnimplementedError：SearchSheet /
/// 食物库 initState 的 ensureLoaded 与 addRecord 成功支都会触到）。
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

/// 固定选图回包（≙ 生产 512px/q75 压缩后的 dataURL；字段口径同 PickedImageData）
/// 直接以记录字面量注入 scanImagePickProvider.overrideWithValue，不引私有类型。

/// 食物库入口地基（③/④ 共用）：建容器 + 挂 _LibHost + 点开「我的食物库」层。
/// 返回容器供用例预置 plateDate / 直读 plateDateProvider；api 由用例持有以
/// 断言调用面（listFoodsCalls / scanCalls / upsertCalls）。
Future<ProviderContainer> pumpLib(
  WidgetTester tester,
  StubHealthApi api, {
  String? plateDate,
}) async {
  await useBigSurface(tester);
  final container = ProviderContainer(
    overrides: [
      healthApiProvider.overrideWithValue(api),
      foodFreqStoreProvider.overrideWithValue(_MemStore()),
      scanImagePickProvider.overrideWithValue(
          (_) async => (dataUrl: 'data:image/jpeg;base64,AAA', failure: null)),
    ],
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  if (plateDate != null) {
    container.read(plateDateProvider.notifier).state = plateDate;
  }
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: shiguangTheme(),
      home: const _LibHost(),
    ),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open-lib'));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  Widget searchApp(StubHealthApi api) => ProviderScope(
        overrides: [
          healthApiProvider.overrideWithValue(api),
          foodFreqStoreProvider.overrideWithValue(_MemStore()),
          scanImagePickProvider.overrideWithValue(
              (_) async => (dataUrl: 'data:image/jpeg;base64,AAA', failure: null)),
        ],
        child: MaterialApp(
          theme: shiguangTheme(),
          // 生产形态是 showShiguangSheet 内的 SearchSheet；本文件只测入口
          // 接线，直接挂 body 即可（FoodScanSheet 的宿主形态由实现保证）。
          home: const Scaffold(
            body: SearchSheet(date: '2026-10-25', meal: 'lunch'),
          ),
        ),
      );

  /// 开记一笔 → 点 📷 → 菜名/来源层（可带 hint）→ 选「从相册选」，等识别链落定。
  Future<void> tapScanFromSheet(WidgetTester tester, {String? hint}) async {
    await tester.tap(find.byKey(const Key('sheet-scan-open')));
    await tester.pumpAndSettle();
    expect(find.text('拍照识菜'), findsOneWidget); // 输入层标题
    expect(find.byKey(scanHintKey), findsOneWidget);
    if (hint != null) {
      await tester.enterText(find.byKey(scanHintKey), hint);
    }
    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('从相册选'), findsOneWidget);
    await tester.tap(find.text('从相册选'));
    await tester.pumpAndSettle();
  }

  testWidgets('① 记一笔 📷 → 从相册选 → 识别成功开 FoodScanSheet'
      '（recordMeal=true，date/meal 用弹层入参）', (tester) async {
    final api = StubHealthApi();
    await tester.pumpWidget(searchApp(api));
    await tester.pumpAndSettle();

    await tapScanFromSheet(tester);

    expect(api.scanCalls, 1, reason: '选图回包后发一次识别');
    expect(find.byType(FoodScanSheet), findsOneWidget);
    final sheet = tester.widget<FoodScanSheet>(find.byType(FoodScanSheet));
    expect(sheet.date, '2026-10-25');
    expect(sheet.meal, 'lunch');
    expect(sheet.recordMeal, isTrue);
    expect(sheet.initialImage, 'data:image/jpeg;base64,AAA',
        reason: '识别用的 dataURL 原样作为入库照片初值');
    expect(find.text('确认食物'), findsOneWidget); // showShiguangSheet 标题
  });

  testWidgets('①b 来源对话框取消（点外）→ 静默返回，零识别零表单', (tester) async {
    final api = StubHealthApi();
    await tester.pumpWidget(searchApp(api));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('sheet-scan-open')));
    await tester.pumpAndSettle();
    expect(find.text('拍照识菜'), findsOneWidget);

    await tester.tapAt(const Offset(5, 5)); // 对话框外（barrier）→ null
    await tester.pumpAndSettle();
    expect(find.text('拍照识菜'), findsNothing);
    expect(api.scanCalls, 0);
    expect(find.byType(FoodScanSheet), findsNothing);
  });

  testWidgets('①c 输入菜名 → 随识别请求透传（trim）；不输入则不带', (tester) async {
    final api = StubHealthApi();
    await tester.pumpWidget(searchApp(api));
    await tester.pumpAndSettle();

    await tapScanFromSheet(tester, hint: ' 番茄炒蛋 ');
    expect(api.scanCalls, 1);
    expect(api.lastScanHint, '番茄炒蛋');
  });

  testWidgets('①d 带菜名识别失败 → 按菜名估算弹窗预填该菜名', (tester) async {
    final api = StubHealthApi()..scanError = ApiException('网络异常');
    await tester.pumpWidget(searchApp(api));
    await tester.pumpAndSettle();

    await tapScanFromSheet(tester, hint: '番茄炒蛋');
    expect(api.lastScanHint, '番茄炒蛋');
    expect(find.text('识别失败：网络异常'), findsOneWidget);

    await tester.tap(find.text('按菜名估算'));
    await tester.pumpAndSettle();
    final field = tester.widget<TextField>(find.byKey(estimateNameKey));
    expect(field.controller?.text, '番茄炒蛋');
  });

  testWidgets('② 识别失败 → 「按菜名估算」→ 估算成功开确认表单'
      '（fromText、克数预填、无照片块）', (tester) async {
    final api = StubHealthApi()..scanError = ApiException('网络异常');
    await tester.pumpWidget(searchApp(api));
    await tester.pumpAndSettle();

    await tapScanFromSheet(tester);

    expect(find.byType(FoodScanSheet), findsNothing);
    expect(find.textContaining('识别失败'), findsOneWidget);
    expect(find.text('识别失败：网络异常'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('按菜名估算'), findsOneWidget);
    expect(find.text('手动填写'), findsNothing);

    await tester.tap(find.text('按菜名估算'));
    await tester.pumpAndSettle();
    expect(find.byKey(estimateNameKey), findsOneWidget);
    expect(find.byKey(estimateGramsKey), findsOneWidget);

    await tester.enterText(find.byKey(estimateNameKey), ' 番茄炒蛋 ');
    await tester.enterText(find.byKey(estimateGramsKey), '150');
    await tester.tap(find.byKey(estimateSubmitKey));
    await tester.pumpAndSettle();

    expect(api.estimateCalls, 1);
    expect(api.lastEstimateName, '番茄炒蛋');
    expect(api.lastEstimateProvider, isNull, reason: '未配置自带 Key 走内置通道');
    expect(find.byType(FoodScanSheet), findsOneWidget);
    final sheet = tester.widget<FoodScanSheet>(find.byType(FoodScanSheet));
    expect(sheet.fromText, isTrue);
    expect(sheet.initialGrams, 150);
    expect(find.text('确认食物'), findsOneWidget);
    expect(find.text('番茄炒蛋'), findsOneWidget);
    expect(find.textContaining('150 kcal'), findsOneWidget); // 100/100g × 150g
    expect(find.text('估算值，请核对菜名与数值'), findsOneWidget);
    expect(find.text('入库照片'), findsNothing, reason: '文本估算没有照片');
  });

  testWidgets('②a 估算弹窗校验：空菜名 / 克数越界不发请求', (tester) async {
    final api = StubHealthApi()..scanError = ApiException('网络异常');
    await tester.pumpWidget(searchApp(api));
    await tester.pumpAndSettle();
    await tapScanFromSheet(tester);
    await tester.tap(find.text('按菜名估算'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(estimateSubmitKey));
    await tester.pump();
    expect(find.text('请填写菜名'), findsOneWidget);
    expect(api.estimateCalls, 0);

    await tester.enterText(find.byKey(estimateNameKey), '番茄炒蛋');
    await tester.enterText(find.byKey(estimateGramsKey), '0');
    await tester.tap(find.byKey(estimateSubmitKey));
    await tester.pump();
    expect(find.text('克数需在 1–2000 之间'), findsOneWidget);
    expect(api.estimateCalls, 0);
    expect(find.byType(FoodScanSheet), findsNothing);
  });

  testWidgets('②b 「直接手填」保留旧兜底：关估算弹窗并开自定义食物表单，'
      '菜名带过去', (tester) async {
    final api = StubHealthApi()..scanError = ApiException('网络异常');
    await tester.pumpWidget(searchApp(api));
    await tester.pumpAndSettle();
    await tapScanFromSheet(tester);
    await tester.tap(find.text('按菜名估算'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(estimateNameKey), '妈妈牌红烧肉');
    await tester.tap(find.byKey(estimateManualKey));
    await tester.pumpAndSettle();

    expect(api.estimateCalls, 0);
    expect(find.text('自定义食物'), findsOneWidget);
    expect(find.byKey(cfNameKey), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byKey(cfNameKey)).controller!.text,
        '妈妈牌红烧肉');
  });

  testWidgets('②c 估算失败 → 弹窗内提示，停留可重试，不打开确认表单', (tester) async {
    final api = StubHealthApi()..scanError = ApiException('网络异常');
    api.estimateError = ApiException('今日识别次数已用完（50 次）');
    await tester.pumpWidget(searchApp(api));
    await tester.pumpAndSettle();
    await tapScanFromSheet(tester);
    await tester.tap(find.text('按菜名估算'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(estimateNameKey), '番茄炒蛋');
    await tester.tap(find.byKey(estimateSubmitKey));
    await tester.pumpAndSettle();

    expect(api.estimateCalls, 1);
    expect(find.text('估算失败：今日识别次数已用完（50 次）'), findsOneWidget);
    expect(find.byKey(estimateNameKey), findsOneWidget, reason: '弹窗不关，可改菜名重试');
    expect(find.byType(FoodScanSheet), findsNothing);
  });

  testWidgets('③ 食物库「📷 拍照添加」在层底、走同一流程：'
      'recordMeal=false，date=plate 日期，meal=lunch', (tester) async {
    const plateDate = '2026-10-01';
    final api = StubHealthApi(libCustomFoods: <Map<String, dynamic>>[]);
    await pumpLib(tester, api, plateDate: plateDate);

    // 层底双钮：左保留原「＋ 添加自定义食物」，右新增「📷 拍照添加」
    expect(find.text('＋ 添加自定义食物'), findsOneWidget);
    expect(find.text('📷 拍照添加'), findsOneWidget);
    expect(find.byKey(libScanAddKey), findsOneWidget);

    await tester.tap(find.byKey(libScanAddKey));
    await tester.pumpAndSettle();
    expect(find.text('拍照识菜'), findsOneWidget);
    await tester.tap(find.text('从相册选'));
    await tester.pumpAndSettle();

    expect(api.scanCalls, 1);
    expect(find.byType(FoodScanSheet), findsOneWidget);
    final sheet = tester.widget<FoodScanSheet>(find.byType(FoodScanSheet));
    expect(sheet.recordMeal, isFalse, reason: '食物库入口只入库不记账');
    expect(sheet.date, plateDate, reason: 'date 取 plateDateProvider（H5 state.date 同源）');
    expect(sheet.meal, 'lunch');
    expect(find.textContaining('保存后记入'), findsNothing,
        reason: 'recordMeal=false 不显示记账提示');
  });

  testWidgets('④ 食物库扫码入库保存后返回：按 renderLibList 重取列表'
      '（listFoodsCalls 增加、空态消失、「自定义 N 条」更新；'
      '修复前停留在旧值/空态，须切 tab 或重开层）', (tester) async {
    final api = StubHealthApi(libCustomFoods: <Map<String, dynamic>>[]);
    await pumpLib(tester, api, plateDate: '2026-10-01');

    // 进入流程前：首开预取 1 次，空库空态与「自定义 0 条」在场
    final before = api.listFoodsCalls;
    expect(before, 1);
    expect(find.text('还没有自定义食物\n点下方按钮添加你的常吃菜'), findsOneWidget);
    expect(find.text('自定义 0 条 · 点餐次标签可改归类'), findsOneWidget);

    await tester.tap(find.byKey(libScanAddKey));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从相册选'));
    await tester.pumpAndSettle(); // 识别 → 确认表单
    expect(find.byType(FoodScanSheet), findsOneWidget);
    expect(api.scanCalls, 1);

    // 桩 upsert 只记 body 不落库：手工写入模拟「云端已落库」（本钉锁端上
    // 保存后重取链，非桩仿真度；对照 food_lib_sheet_test T9结转钉 同法）
    api.libCustomFoods!.insert(
        0,
        StubHealthApi.cfFoodMap(
            id: 'scan_1',
            name: '蒜薹鸡块',
            kcal: 312,
            grams: 200,
            portion: '200g'));

    await tester.tap(find.byKey(scanSaveKey));
    await tester.pumpAndSettle(); // upsert → pop 表单 → 回食物库层 → _render 重取

    expect(api.upsertCalls, 1);
    expect(api.addBodies, isEmpty, reason: 'food_lib 入口只入库不记账');
    expect(api.listFoodsCalls, greaterThan(before),
        reason: 'openFoodScanFlow 结束后必须重取'
            '（修复前该数停在 before，列表停留空态直到切 tab/重开层）');
    expect(find.text('我的食物库'), findsOneWidget, reason: '重取不关层');
    expect(find.text('还没有自定义食物\n点下方按钮添加你的常吃菜'), findsNothing);
    expect(find.text('蒜薹鸡块'), findsOneWidget, reason: '重取回包已见新入库行');
    expect(find.text('自定义 1 条 · 点餐次标签可改归类'), findsOneWidget,
        reason: 'sub 行按新取数重写（修复前仍是「自定义 0 条」）');
  });
}

/// 食物库入口宿主（≙ 生产「我的」页调用 openFoodLibSheet(context, ref)）
class _LibHost extends ConsumerWidget {
  const _LibHost();

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => openFoodLibSheet(context, ref),
            child: const Text('open-lib'),
          ),
        ),
      );
}
