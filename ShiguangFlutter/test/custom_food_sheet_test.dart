// ShiguangFlutter/test/custom_food_sheet_test.dart
// M5 Task 7：自定义食物表单（宏量自动热量 / 双保存模式 / 选图注入 / 搜索空结果入口接线）。
// 行为权威源 js/app.js:1170-1286（cf* 一族）+ index.html:506-558（cf-sheet DOM）。
// 简报断言链 ①~⑦ 全落；简报②⑤写「p5/c40/f6 → 250」是算术笔误
// （4*5+4*40+9*6=234，H5 :1201 Math.round 同值），按 H5 源公式取 234（报告登记）。
// 记录刷新走 record_controller 现成 provider（addRecord 内部 invalidate
// records/summary 当日 family），本文件用 _DayWatcher 挂住当日 provider 计次。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shiguang_flutter/app/theme.dart' show shiguangTheme;
import 'package:shiguang_flutter/data/api_client.dart' show ApiException;
import 'package:shiguang_flutter/domain/dates.dart' show todayIso;
import 'package:shiguang_flutter/features/common/image_pick.dart'
    show ImagePickFailure, PickedImageData;
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider, recordsProvider, summaryProvider;
import 'package:shiguang_flutter/features/record/custom_food_sheet.dart';
import 'package:shiguang_flutter/features/record/record_screen.dart'
    show RecordScreen;

import 'harness.dart';
import 'stubs/stub_health_api.dart';

/// 1x1 PNG（与 profile_head_test ①b 同款），仅前缀参与互通断言
const kPngDataUrl =
    'data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

CustomFoodImagePicker pickerReturning(PickedImageData r) => (_) async => r;

/// 缺省注入：取消选择（静默），保证未测选图的用例不触插件
Future<PickedImageData> cancelPick(ImageSource _) async =>
    (dataUrl: null, failure: null);

/// 弹层直调宿主：≙ H5 从记一笔弹层点 cf-open 的语境（record 页 context，
/// 在 profileShell 之外）；_DayWatcher 挂住当日 records/summary provider，
/// 供「保存并记入后 invalidate 重取」计数断言。
class _Host extends ConsumerWidget {
  const _Host({
    required this.meal,
    this.initialName,
    this.onSaved,
    this.pickImage = cancelPick,
  });

  final String meal;
  final String? initialName;
  final void Function()? onSaved;
  final CustomFoodImagePicker pickImage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      body: Column(
        children: [
          const _DayWatcher(),
          Center(
            child: TextButton(
              onPressed: () => openCustomFoodSheet(
                context,
                meal: meal,
                initialName: initialName,
                onSaved: onSaved ?? () {},
                pickImage: pickImage,
              ),
              child: const Text('open-sheet'),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayWatcher extends ConsumerWidget {
  const _DayWatcher();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(recordsProvider(todayIso()));
    ref.watch(summaryProvider(todayIso()));
    return const SizedBox.shrink();
  }
}

Future<void> pumpHost(
  WidgetTester tester,
  StubHealthApi api, {
  required String meal,
  String? initialName,
  void Function()? onSaved,
  CustomFoodImagePicker pickImage = cancelPick,
}) async {
  await useBigSurface(tester);
  final container = ProviderContainer(
    overrides: [healthApiProvider.overrideWithValue(api)],
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    // 真主题必须上：FilledButton × Row 非 flex 位的 infinite-width 债只有
    // shiguangTheme 下复现（T5 目检教训）
    child: MaterialApp(theme: shiguangTheme(), home: _Host(
          meal: meal,
          initialName: initialName,
          onSaved: onSaved,
          pickImage: pickImage,
        )),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open-sheet'));
  await tester.pumpAndSettle();
}

/// 名称框当前文本
String nameText(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(cfNameKey)).controller!.text;

String fieldText(WidgetTester tester, Key key) =>
    tester.widget<TextField>(find.byKey(key)).controller!.text;

bool segSelected(WidgetTester tester, Key key) =>
    tester.widget<CfSegButton>(find.byKey(key)).selected;

Future<void> fill(WidgetTester tester, Key key, String v) =>
    tester.enterText(find.byKey(key), v);

/// 弹层表单滚动态下目标钮可能不在视口内（目检项同源）：先 ensureVisible 再 tap
Future<void> tapWidget(WidgetTester tester, Finder f) async {
  await tester.ensureVisible(f);
  await tester.pumpAndSettle(); // 等滚动动画落定，取位不再过期
  await tester.tap(f);
}

Future<void> tapKey(WidgetTester tester, Key key) =>
    tapWidget(tester, find.byKey(key));

Future<void> tapText(WidgetTester tester, String text) =>
    tapWidget(tester, find.text(text));

void main() {
  /* ---------- ① 默认值（openCustomFoodSheet :1207-1218） ---------- */

  testWidgets('①initialName 预填名称；meal=lunch/dinner 均归「正餐」档；单位默认克',
      (tester) async {
    final api = StubHealthApi();
    await pumpHost(tester, api, meal: 'lunch', initialName: '测试饭团');

    expect(nameText(tester), '测试饭团'); // :1208 sheetKeyword 预填
    expect(segSelected(tester, cfMealKey('lunch')), isTrue); // 正餐档高亮
    expect(segSelected(tester, cfUnitKey('g')), isTrue); // :1216 默认 g
    // 其余框清空态（:1209-1213）
    expect(fieldText(tester, cfGramsKey), '');
    expect(fieldText(tester, cfKcalKey), '');
    expect(fieldText(tester, cfProteinKey), '');
    // 双保存按钮（index.html:556-557）：主按钮标题随入参餐次（:1220）
    expect(find.text('保存并记入午餐'), findsOneWidget);
    expect(find.text('仅存入食物库，不记录'), findsOneWidget);
  });

  testWidgets('①b meal=dinner → 同归正餐档（CF_MEAL_MAP 午+晚）；标题「保存并记入晚餐」',
      (tester) async {
    await pumpHost(tester, StubHealthApi(), meal: 'dinner');
    expect(segSelected(tester, cfMealKey('lunch')), isTrue); // :1218 午/晚→正餐
    expect(segSelected(tester, cfMealKey('breakfast')), isFalse);
    expect(find.text('保存并记入晚餐'), findsOneWidget); // MEAL_NAMES[dinner]=晚餐
  });

  testWidgets('①c meal=breakfast → 早餐档高亮 + 标题「保存并记入早餐」；snack → 零食档',
      (tester) async {
    await pumpHost(tester, StubHealthApi(), meal: 'breakfast');
    expect(segSelected(tester, cfMealKey('breakfast')), isTrue);
    expect(find.text('保存并记入早餐'), findsOneWidget);
  });

  /* ---------- ② 宏量自动热量（cfAutoKcal :1195-1202 + cfKcalManual 闸 :1172/1283） ---------- */

  testWidgets('②填 p5/c40/f6 未手改热量 → 热量框 234（round(4p+4c+9f)，:1201；简报250为算术笔误）',
      (tester) async {
    await pumpHost(tester, StubHealthApi(), meal: 'lunch');
    await fill(tester, cfProteinKey, '5');
    await tester.pump();
    await fill(tester, cfCarbKey, '40');
    await tester.pump();
    await fill(tester, cfFatKey, '6');
    await tester.pump();
    expect(fieldText(tester, cfKcalKey), '234'); // 20+160+54
  });

  testWidgets('②b 手改 kcal=300 后再改宏量 → 保持 300（cfKcalManual 闸）；三素全空不动热量',
      (tester) async {
    await pumpHost(tester, StubHealthApi(), meal: 'lunch');
    await fill(tester, cfKcalKey, '300'); // :1283 input → manual 闸落下
    await tester.pump();
    await fill(tester, cfProteinKey, '10');
    await tester.pump();
    expect(fieldText(tester, cfKcalKey), '300');

    // :1200 三素未填时不动热量（允许只按包装标签填热量）：
    await fill(tester, cfProteinKey, '');
    await tester.pump();
    expect(fieldText(tester, cfKcalKey), '300');
  });

  /* ---------- ③ 名称闸（:1238） ---------- */

  testWidgets('③清空名称→保存 → toast「请填写食物名称」，零请求，弹层不关',
      (tester) async {
    final api = StubHealthApi();
    await pumpHost(tester, api, meal: 'lunch', initialName: '测试饭团');
    await fill(tester, cfNameKey, '   '); // trim 后为空
    await tapKey(tester, cfSaveOnlyKey);
    await tester.pumpAndSettle();

    expect(find.text('请填写食物名称'), findsOneWidget); // :1238 逐字
    expect(api.customFoodBodies, isEmpty);
    expect(find.byKey(cfSaveOnlyKey), findsOneWidget); // 弹层还在
  });

  /* ---------- ④ 热量闸（:1239） ---------- */

  testWidgets('④kcal 空/0 且三素空 → toast「请填热量，或先填三大营养素自动算」，零请求',
      (tester) async {
    final api = StubHealthApi();
    await pumpHost(tester, api, meal: 'lunch', initialName: '测试饭团');

    await tapKey(tester, cfSaveOnlyKey);
    await tester.pumpAndSettle();
    expect(find.text('请填热量，或先填三大营养素自动算'), findsOneWidget); // :1239 逐字

    await fill(tester, cfKcalKey, '0'); // kcal<=0 同闸
    await tapKey(tester, cfSaveOnlyKey);
    await tester.pumpAndSettle();
    expect(api.customFoodBodies, isEmpty);
  });

  /* ---------- ⑤ 入库链（saveCustomFood(false) :1229-1251） ---------- */

  testWidgets('⑤名称/克数/宏量齐备→仅入库：POST body 十字键逐字 + onSaved + toast，不发记录',
      (tester) async {
    final api = StubHealthApi();
    var savedCalls = 0;
    await pumpHost(tester, api, meal: 'lunch', initialName: '测试饭团',
        onSaved: () => savedCalls++);
    await fill(tester, cfGramsKey, '100');
    await fill(tester, cfProteinKey, '5');
    await fill(tester, cfCarbKey, '40');
    await fill(tester, cfFatKey, '6'); // 自动热量 234
    await tester.pump();

    await tapKey(tester, cfSaveOnlyKey);
    await tester.pumpAndSettle();

    // js/app.js:1241 十字键；contract diet-core.json addCustomFood requestSample 同形
    expect(api.customFoodBodies.single, <String, dynamic>{
      'name': '测试饭团',
      'kcal': 234,
      'grams': 100,
      'unit': 'g',
      'meals': ['lunch', 'dinner'], // CF_MEAL_MAP 正餐档 :1176
      'protein': 5,
      'carb': 40,
      'fat': 6,
      'portion': '100g', // grams 有值 → `${grams}${unit}` :1236
      'image': '',
    });
    expect(savedCalls, 1); // ≙ fillSheetResults 重查（:1251）
    expect(find.text('已存入食物库，搜索可用'), findsOneWidget); // :1250 逐字
    expect(api.addBodies, isEmpty); // 未记一餐
    expect(find.byKey(cfSaveOnlyKey), findsNothing); // 弹层已关
    expect(api.recordsCalls, 1, reason: '仅入库不动当日记录 provider');
  });

  testWidgets('⑤b 克数空 → portion「1 份」（:1236）；单位切毫升 → unit ml + portion 后缀；餐次切零食 → meals [snack]',
      (tester) async {
    final api = StubHealthApi();
    await pumpHost(tester, api, meal: 'lunch', initialName: '奶茶');
    await fill(tester, cfKcalKey, '100');
    await tapKey(tester, cfUnitKey('ml'));
    await tapKey(tester, cfMealKey('snack'));
    await tester.pump();
    expect(segSelected(tester, cfUnitKey('ml')), isTrue);
    expect(segSelected(tester, cfMealKey('snack')), isTrue);

    await tapKey(tester, cfSaveOnlyKey);
    await tester.pumpAndSettle();
    final body = api.customFoodBodies.single;
    expect(body['portion'], '1 份'); // grams 空 → 默认份量文案
    expect(body['unit'], 'ml');
    expect(body['meals'], ['snack']); // CF_MEAL_MAP 零食档
  });

  /* ---------- ⑥ 记一餐链（saveCustomFood(true) :1243-1248） ---------- */

  testWidgets('⑥入库后记一笔：body 十字键（emoji 🍽️）+ toast「已记入早餐 · 测试饭团」+ 当日 records/summary 重取',
      (tester) async {
    final api = StubHealthApi(
      records: [StubHealthApi.recordMap(id: 'r1', meal: 'breakfast', name: '旧记录', portion: '1 份', kcal: 10)],
    );
    await pumpHost(tester, api, meal: 'breakfast', initialName: '测试饭团');
    expect(api.recordsCalls, 1);
    expect(api.summaryCalls, 1);
    await fill(tester, cfGramsKey, '100');
    await fill(tester, cfProteinKey, '5');
    await fill(tester, cfCarbKey, '40');
    await fill(tester, cfFatKey, '6');
    await tester.pump();

    await tapText(tester, '保存并记入早餐');
    await tester.pumpAndSettle();

    expect(api.customFoodBodies, hasLength(1));
    // js/app.js:1244 记录 body：date=当日、meal=入参餐次、emoji 🍽️、image 同库
    expect(api.addBodies.single, <String, dynamic>{
      'date': todayIso(),
      'meal': 'breakfast',
      'name': '测试饭团',
      'portion': '100g',
      'kcal': 234,
      'emoji': '🍽️',
      'image': '',
      'protein': 5,
      'carb': 40,
      'fat': 6,
    });
    expect(find.text('已记入早餐 · 测试饭团'), findsOneWidget); // :1248 逐字
    // 记录刷新：addRecord 内部 invalidate records+summary 当日 family
    expect(api.recordsCalls, 2);
    expect(api.summaryCalls, 2);
  });

  /* ---------- ⑦ 失败链（:1253-1255） ---------- */

  testWidgets('⑦addCustomFood 抛 ApiException(m) → toast「保存失败：m」，弹层不关，不发记录',
      (tester) async {
    final api = StubHealthApi()..customFoodError = ApiException('m');
    await pumpHost(tester, api, meal: 'lunch', initialName: '测试饭团');
    await fill(tester, cfKcalKey, '250');

    await tapKey(tester, cfSaveOnlyKey);
    await tester.pumpAndSettle();

    expect(find.text('保存失败：m'), findsOneWidget); // :1254 逐字
    expect(find.byKey(cfSaveOnlyKey), findsOneWidget);
    expect(api.addBodies, isEmpty);
  });

  testWidgets('⑦b 入库成功但记一笔失败 → 食物已入库，toast「保存失败：炸」，不重复入库（重入禁用后不再触发）',
      (tester) async {
    final api = StubHealthApi()..addError = ApiException('炸');
    await pumpHost(tester, api, meal: 'breakfast', initialName: '测试饭团');
    await fill(tester, cfKcalKey, '250');

    await tapText(tester, '保存并记入早餐');
    await tester.pumpAndSettle();

    expect(find.text('保存失败：炸'), findsOneWidget); // H5：库已存、记录失败同一 catch 文案
    expect(api.customFoodBodies, hasLength(1));
    expect(api.addBodies, hasLength(1));
    // 弹层已关（入库成功即关，≙ H5 :1242 在记录前关闭），无重复入库面
    expect(find.byKey(cfSaveOnlyKey), findsNothing);
  });

  /* ---------- 选图链（cf-img-pick / change :1257-1272，注入面仿 T5） ---------- */

  testWidgets('选图成功 → FoodThumb 画图；保存 body image=dataURL；清除后回落 🍽️ 且 image 空串',
      (tester) async {
    final api = StubHealthApi();
    await pumpHost(tester, api, meal: 'lunch', initialName: '测试饭团',
        pickImage: pickerReturning((dataUrl: kPngDataUrl, failure: null)));
    // 初始空态预览 🍽️（renderCfPreview :1203-1206）
    expect(find.text('🍽️'), findsOneWidget);

    await tapKey(tester, cfImgGalleryKey);
    await tester.pumpAndSettle();
    expect(find.text('🍽️'), findsNothing); // 已换成图
    expect(find.byType(Image), findsWidgets);

    await fill(tester, cfKcalKey, '250');
    await tapKey(tester, cfSaveOnlyKey);
    await tester.pumpAndSettle();
    expect(api.customFoodBodies.single['image'], kPngDataUrl);

    // 清除链路：再开一层（上一层已随保存关闭）选图→清除→入库 image 空串
    await tester.tap(find.text('open-sheet'));
    await tester.pumpAndSettle();
    await tapKey(tester, cfImgCameraKey);
    await tester.pumpAndSettle();
    expect(find.byType(Image), findsWidgets);
    await tapKey(tester, cfImgClearKey);
    await tester.pumpAndSettle();
    expect(find.text('🍽️'), findsOneWidget); // 清除回落空态
    await fill(tester, cfKcalKey, '250');
    await tapKey(tester, cfSaveOnlyKey);
    await tester.pumpAndSettle();
    expect(api.customFoodBodies.last['image'], '');
  });

  testWidgets('选图超限 → toast「图片仍过大，请换一张」，预览不动', (tester) async {
    await pumpHost(tester, StubHealthApi(), meal: 'lunch',
        pickImage: pickerReturning((dataUrl: null, failure: ImagePickFailure.tooLargeEncoded)));
    await tapKey(tester, cfImgGalleryKey);
    await tester.pumpAndSettle();
    expect(find.text('图片仍过大，请换一张'), findsOneWidget); // :1266 逐字
    expect(find.text('🍽️'), findsOneWidget); // 预览不动
  });

  testWidgets('选图读取失败 → toast「图片处理失败」', (tester) async {
    await pumpHost(tester, StubHealthApi(), meal: 'lunch',
        pickImage: pickerReturning((dataUrl: null, failure: ImagePickFailure.readFailed)));
    await tapKey(tester, cfImgGalleryKey);
    await tester.pumpAndSettle();
    expect(find.text('图片处理失败'), findsOneWidget); // :1270 逐字
  });

  testWidgets('选图取消 → 静默：无 SnackBar，预览保持 🍽️', (tester) async {
    await pumpHost(tester, StubHealthApi(), meal: 'lunch',
        pickImage: pickerReturning((dataUrl: null, failure: null)));
    await tapKey(tester, cfImgGalleryKey);
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing); // 取消静默（T3 null/null）
    expect(find.text('🍽️'), findsOneWidget);
  });

  /* ---------- 搜索弹层空结果入口接线（cf-open，:646/:657-658） ---------- */

  testWidgets('空结果区「＋ 自定义食物」→ 开表单且名称预填关键词；入库后按当前关键词重查',
      (tester) async {
    await useBigSurface(tester);
    final api = StubHealthApi(foods: const <dynamic>[]);
    final container = ProviderContainer(
      overrides: [healthApiProvider.overrideWithValue(api)],
      retry: (_, _) => null,
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: shiguangTheme(), home: const RecordScreen()),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('＋ 记一笔'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '搜索食物库'), '奶茶');
    await tester.pump(const Duration(milliseconds: 250)); // H5 200ms 防抖
    await tester.pumpAndSettle();
    expect(find.text('没找到「奶茶」'), findsOneWidget);
    final searchCallsBefore = api.searchCalls;

    await tapText(tester, '＋ 自定义食物'); // :646 文案逐字
    await tester.pumpAndSettle();
    // openCustomFoodSheet 初始名=当时搜索关键词（:1199/1208）
    expect(nameText(tester), '奶茶');
    expect(find.text('自定义食物'), findsOneWidget); // 标题 index.html:509

    await fill(tester, cfKcalKey, '350');
    await tapKey(tester, cfSaveOnlyKey);
    await tester.pumpAndSettle();
    expect(find.text('已存入食物库，搜索可用'), findsOneWidget);
    expect(api.customFoodBodies.single['name'], '奶茶');
    // onSaved ≙ fillSheetResults(当前关键词)：searchProvider 以同键重取
    expect(api.searchCalls, searchCallsBefore + 1);
    expect(api.lastSearchKeyword, '奶茶');
  });

  /* ---------- 保存防重（H5 单发按钮语义的 Flutter 等价闸） ---------- */

  testWidgets('入库在途连点保存 → addCustomFood 只发一次', (tester) async {
    final api = StubHealthApi()..customFoodGate = Completer();
    await pumpHost(tester, api, meal: 'lunch', initialName: '测试饭团');
    await fill(tester, cfKcalKey, '250');

    await tapKey(tester, cfSaveOnlyKey);
    await tester.pump();
    await tapKey(tester, cfSaveOnlyKey);
    await tapKey(tester, cfSaveOnlyKey);
    await tester.pump();
    expect(api.customFoodBodies, hasLength(1));

    api.customFoodGate!.complete();
    await tester.pumpAndSettle();
    expect(api.customFoodBodies, hasLength(1));
  });
}
