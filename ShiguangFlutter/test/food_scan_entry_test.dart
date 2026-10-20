// ShiguangFlutter/test/food_scan_entry_test.dart
// M13-T7：拍照识菜两处入口接线。
// 判据（task-7-brief）：
// ① 记一笔弹层搜索框右侧 📷（sheet-scan-open）→ 来源选择「从相册选」→
//    识别成功 → showShiguangSheet 打开 FoodScanSheet（recordMeal=true，
//    date/meal 用弹层入参）；
// ② scanError=ApiException('网络异常') → 「识别失败：网络异常」、不打开
//    FoodScanSheet；「手动填写」落自定义食物表单；
// ③ 食物库层底「📷 拍照添加」（lib-scan-add）存在且走同一流程
//    （recordMeal=false、date=plateDateProvider、meal='lunch'）。
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
    show FoodScanSheet, scanImagePickProvider;
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

  /// 开记一笔 → 点 📷 → 来源对话框 → 选「从相册选」，等识别链落定。
  Future<void> tapScanFromSheet(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('sheet-scan-open')));
    await tester.pumpAndSettle();
    expect(find.text('识菜照片'), findsOneWidget); // 来源选择标题
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
    expect(find.text('识菜照片'), findsOneWidget);

    await tester.tapAt(const Offset(5, 5)); // 对话框外（barrier）→ null
    await tester.pumpAndSettle();
    expect(find.text('识菜照片'), findsNothing);
    expect(api.scanCalls, 0);
    expect(find.byType(FoodScanSheet), findsNothing);
  });

  testWidgets('② 识别失败 → 「识别失败：网络异常」，不打开表单；'
      '「手动填写」落自定义食物表单', (tester) async {
    final api = StubHealthApi()..scanError = ApiException('网络异常');
    await tester.pumpWidget(searchApp(api));
    await tester.pumpAndSettle();

    await tapScanFromSheet(tester);

    expect(find.byType(FoodScanSheet), findsNothing);
    expect(find.textContaining('识别失败'), findsOneWidget);
    expect(find.text('识别失败：网络异常'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    expect(find.text('手动填写'), findsOneWidget);

    await tester.tap(find.text('手动填写'));
    await tester.pumpAndSettle();
    expect(find.text('自定义食物'), findsOneWidget); // 既有表单标题
    expect(find.byKey(cfNameKey), findsOneWidget);
  });

  testWidgets('③ 食物库「📷 拍照添加」在层底、走同一流程：'
      'recordMeal=false，date=plate 日期，meal=lunch', (tester) async {
    await useBigSurface(tester);
    const plateDate = '2026-10-01';
    final api = StubHealthApi(libCustomFoods: <Map<String, dynamic>>[]);
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
    container.read(plateDateProvider.notifier).state = plateDate;

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

    // 层底双钮：左保留原「＋ 添加自定义食物」，右新增「📷 拍照添加」
    expect(find.text('＋ 添加自定义食物'), findsOneWidget);
    expect(find.text('📷 拍照添加'), findsOneWidget);
    expect(find.byKey(libScanAddKey), findsOneWidget);

    await tester.tap(find.byKey(libScanAddKey));
    await tester.pumpAndSettle();
    expect(find.text('识菜照片'), findsOneWidget);
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
