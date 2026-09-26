// ShiguangFlutter/test/goal_edit_sheet_test.dart
// M7 Task 5：目标体重编辑弹层钉。行为权威源 js/app.js:1425-1465 +
// index.html:335-351（行号以 09-27 实读为准，简报漂移已勘正）。
// 钉面（简报 Step 1）：
// ① 预填 profile.goal.targetWeight（|| 55 falsy 兜底：null/0/缺 goal）；
// ② ±0.5 步进 +(x±0.5).toFixed(1) 串形（52.0→'52'、51.5；'52.' 输入 ≙
//    Number() 全串语义 52——M6 终审 I1 口径）；
// ③ 顶格闸 30/150：值不动 + toast「最小 30 kg」「最大 150 kg」（逐字含半角空格）；
// ④ hint 逐字（en-dash 30–150）+ 标题/aria/钮文案在场；
// ⑤ 保存：setGoal **单键** body {targetWeight}（双键 dailyKcal 不发）→
//    invalidate profileProvider（重取 +1，宿主行联动新值 ≙ 代谢卡刷新）→
//    关层 → toast「目标体重已更新」；
// ⑥ 保存前归一 clamp（输 200 → 150 发出）；
// ⑦ 失败：「保存失败：boom」层不关；ApiException('') → 「保存失败：网络异常」
//    （jsOr 口径）；失败不 invalidate。
// 主题：必挂 shiguangTheme()（弹层族 T4 评审定式，FilledButton 通栏位检）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/theme.dart' show shiguangTheme;
import 'package:shiguang_flutter/data/api_client.dart' show ApiException;
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider;
import 'package:shiguang_flutter/features/profile/goal_edit_sheet.dart'
    show
        goalEditValueKey,
        goalEditDecKey,
        goalEditIncKey,
        goalEditSaveKey,
        goalEditCloseKey,
        openGoalEditSheet;
import 'package:shiguang_flutter/features/profile/profile_providers.dart'
    show profileProvider;

import 'harness.dart' show useBigSurface;
import 'stubs/stub_health_api.dart';

/// 目标体重可配的桩档案（goal.targetWeight=null ≙ 缺键/无 goal 两支兜底测试）
StubHealthApi apiWithGoalTw(num? tw) => StubHealthApi(
  profile: <String, dynamic>{
    ...StubHealthApi.profileMap(),
    'goal': <String, dynamic>{
      'dailyKcal': 1800,
      'targetWeight': ?tw, // null 时丢键（≙ goal 缺 targetWeight）
      'waterMl': 1600,
    },
  },
);

/// 直调宿主：常驻页 watch profileProvider（invalidate 重取观测位 + 联动行）
/// + 开层钮 ≙ body_profile_card 代谢卡「点击修改」入口。
class _Host extends ConsumerWidget {
  const _Host();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(profileProvider);
    final tw = (p.value?['goal'] as Map?)?['targetWeight'];
    return Scaffold(
      body: Column(
        children: [
          Text('goal-tw:$tw'), // 联动断言位（≙ #goal-weight + renderMetab）
          TextButton(
            onPressed: () => openGoalEditSheet(context, ref),
            child: const Text('open-sheet'),
          ),
        ],
      ),
    );
  }
}

Future<ProviderContainer> pumpHost(
  WidgetTester tester,
  StubHealthApi api,
) async {
  await useBigSurface(tester);
  final container = ProviderContainer(
    overrides: [healthApiProvider.overrideWithValue(api)],
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(theme: shiguangTheme(), home: const _Host()),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

Future<void> openSheet(WidgetTester tester) async {
  await tester.tap(find.text('open-sheet'));
  await tester.pumpAndSettle();
}

String fieldValue(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(goalEditValueKey)).controller!.text;

void main() {
  /* ---------- ① 预填（openGoalEditSheet :1429 || 55） ---------- */

  testWidgets('①预填 52.5→「52.5」；55(int)→「55」；缺 targetWeight/0 → 「55」兜底', (
    tester,
  ) async {
    await pumpHost(tester, apiWithGoalTw(52.5));
    await openSheet(tester);
    expect(fieldValue(tester), '52.5'); // :1429 预填
    await tester.tap(find.byKey(goalEditCloseKey));
    await tester.pumpAndSettle();

    final api2 = apiWithGoalTw(52); // goal 整数值
    await pumpHost(tester, api2);
    await openSheet(tester);
    expect(fieldValue(tester), '52'); // jsNumText 串形：52.0 → '52'
    await tester.tap(find.byKey(goalEditCloseKey));
    await tester.pumpAndSettle();

    await pumpHost(tester, apiWithGoalTw(null)); // goal 无 targetWeight 键
    await openSheet(tester);
    expect(fieldValue(tester), '55'); // || 55 falsy 支
  });

  /* ---------- ② ±0.5 步进 + toFixed(1) 串形 ---------- */

  testWidgets('②52 点−→「51.5」，再点＋→「52」（52.0→\'52\' toFixed 串形）；'
      '输入「52.」点−→「51.5」（Number 全串 ≙ 52，I1 口径）', (tester) async {
    await pumpHost(tester, apiWithGoalTw(52));
    await openSheet(tester);

    await tester.tap(find.byKey(goalEditDecKey));
    await tester.pump();
    expect(fieldValue(tester), '51.5'); // +(52−0.5).toFixed(1)
    await tester.tap(find.byKey(goalEditIncKey));
    await tester.pump();
    expect(fieldValue(tester), '52'); // +(51.5+0.5).toFixed(1)=52.0 → '52'

    await tester.enterText(find.byKey(goalEditValueKey), '52.');
    await tester.tap(find.byKey(goalEditDecKey)); // 失焦归一 52.→52 后 bump
    await tester.pump();
    expect(fieldValue(tester), '51.5'); // Number('52.')=52（非 NaN/非 52.0 串形）
  });

  /* ---------- ③ 顶格闸（:1442-1450 值不动 + toast 逐字） ---------- */

  testWidgets('③30 点−→「最小 30 kg」值不动；150 点＋→「最大 150 kg」值不动（逐字含半角空格）', (
    tester,
  ) async {
    await pumpHost(tester, apiWithGoalTw(30));
    await openSheet(tester);
    await tester.tap(find.byKey(goalEditDecKey));
    await tester.pump();
    expect(fieldValue(tester), '30'); // Math.max(30, 29.5) → next===cur
    expect(find.text('最小 30 kg'), findsOneWidget); // :1444 逐字
    await tester.tap(find.byKey(goalEditCloseKey)); // 先关层再重挂（防 barrier 吞 tap）
    await tester.pumpAndSettle();

    await pumpHost(tester, apiWithGoalTw(150));
    await openSheet(tester);
    await tester.tap(find.byKey(goalEditIncKey));
    await tester.pump();
    expect(fieldValue(tester), '150'); // Math.min(150, 150.5) → next===cur
    expect(find.text('最大 150 kg'), findsOneWidget); // :1450 逐字
  });

  /* ---------- ④ 文案在场（index.html:335-351 逐字，en-dash） ---------- */

  testWidgets('④标题「编辑目标体重」；hint「体重范围 30–150 kg · 点数字可直接输入 · '
      '热量目标由系统按档案自动计算」逐字（en-dash U+2013）；钮「保存目标」；aria 步进钮', (tester) async {
    // ensureSemantics 开语义树（exercise_sheet_test ⑦ 定式）；钮 label 会被
    // 合并进子 Text 字形（'减少 0.5 kg −'），故 RegExp 前锚不钉全等。
    final handle = tester.ensureSemantics();
    await pumpHost(tester, apiWithGoalTw(55));
    await openSheet(tester);
    expect(find.text('编辑目标体重'), findsOneWidget); // :339
    expect(
      find.text('体重范围 30–150 kg · 点数字可直接输入 · 热量目标由系统按档案自动计算'),
      findsOneWidget,
    ); // :350 逐字
    expect(find.text('目标体重'), findsOneWidget); // :343 section label
    expect(find.text('保存目标'), findsOneWidget); // :351
    expect(find.text('kg'), findsOneWidget); // :346 <small>
    expect(
      find.bySemanticsLabel(RegExp(r'^减少 0\.5 kg')),
      findsOneWidget,
    ); // :345 aria 逐字
    expect(
      find.bySemanticsLabel(RegExp(r'^增加 0\.5 kg')),
      findsOneWidget,
    ); // :347 aria 逐字
    expect(
      find.bySemanticsLabel(RegExp(r'^目标体重 kg')),
      findsOneWidget,
    ); // :346 aria
    expect(find.bySemanticsLabel(RegExp(r'^关闭')), findsOneWidget); // :340 aria
    handle.dispose();
  });

  /* ---------- ⑤ 保存成功链（:1453-1461 单键 + invalidate + 关层 + toast） ---------- */

  testWidgets(
    '⑤保存 57.5：PUT /user/goal 单键 body {targetWeight:57.5}（无 dailyKcal）；'
    'profileProvider 重取+1；关层；toast「目标体重已更新」；宿主联动 57.5',
    (tester) async {
      final api = apiWithGoalTw(55);
      await pumpHost(tester, api);
      await openSheet(tester);
      final getBefore = api.profileCalls;

      await tester.enterText(find.byKey(goalEditValueKey), '57.5');
      await tester.tap(find.byKey(goalEditSaveKey));
      await tester.pumpAndSettle();

      expect(api.goalCalls, 1);
      expect(api.goalBodies.single, <String, dynamic>{
        'targetWeight': 57.5,
      }); // **单键**：dailyKcal 不发（null 键剥离 ≙ js 序列化）
      expect(
        api.profileCalls,
        getBefore + 1,
      ); // invalidate ≙ 回写+goal-weight+renderMetab
      expect(find.byKey(goalEditSaveKey), findsNothing); // 层已关（:1460）
      expect(find.text('目标体重已更新'), findsOneWidget); // :1461 逐字（关层后 SnackBar）
      expect(
        find.text('goal-tw:57.5'),
        findsOneWidget,
      ); // 宿主联动新值（桩按 truthy 部分更新回写）
    },
  );

  /* ---------- ⑥ 保存前归一 clamp（bindStepperNorm :1652） ---------- */

  testWidgets('⑥输入 200 保存：归一 clamp 150 → 单键 body {targetWeight:150}', (
    tester,
  ) async {
    final api = apiWithGoalTw(55);
    await pumpHost(tester, api);
    await openSheet(tester);
    await tester.enterText(find.byKey(goalEditValueKey), '200');
    await tester.tap(find.byKey(goalEditSaveKey));
    await tester.pumpAndSettle();
    expect(api.goalBodies.single, <String, dynamic>{
      'targetWeight': 150,
    }); // ≙ norm→150
    expect(
      find.textContaining('goal-tw:150'),
      findsOneWidget,
    ); // 宿主回写值（150.0 串形前锚）
  });

  /* ---------- ⑦ 失败链（:1462-1464 层不关） ---------- */

  testWidgets('⑦setGoalError(boom)：toast「保存失败：boom」逐字；层不关；不 invalidate', (
    tester,
  ) async {
    final api = apiWithGoalTw(55)..setGoalError = ApiException('boom');
    await pumpHost(tester, api);
    await openSheet(tester);
    final getBefore = api.profileCalls;

    await tester.tap(find.byKey(goalEditSaveKey));
    await tester.pump(); // 层内 toast 用 pump 不 settle（SheetToast 播完自删）

    expect(find.text('保存失败：boom'), findsOneWidget); // :1463 逐字
    expect(find.byKey(goalEditSaveKey), findsOneWidget); // 层不关
    expect(find.text('目标体重已更新'), findsNothing);
    expect(api.profileCalls, getBefore); // 失败无回写（H5 catch 不动 profileData）
    expect(find.text('goal-tw:55'), findsOneWidget); // 宿主值未变
  });

  testWidgets(
    '⑦b ApiException(\'\') 空 message → falsy 兜底「保存失败：网络异常」（jsOr 口径）',
    (tester) async {
      final api = apiWithGoalTw(55)..setGoalError = ApiException('');
      await pumpHost(tester, api);
      await openSheet(tester);
      await tester.tap(find.byKey(goalEditSaveKey));
      await tester.pump();
      expect(find.text('保存失败：网络异常'), findsOneWidget);
      expect(find.byKey(goalEditSaveKey), findsOneWidget);
    },
  );
}
