// ShiguangFlutter/test/exercise_sheet_test.dart
// M6 Task 2 弹层钉 + M7-T2 乐观 temp 链（R4 差异 #1/#2 退役批）。
// 行为权威源 js/app.js:1758-1852（chips 重置量/步进三型上下限/预览/保存闸/
// 保存乐观链 :1807-1830/删除乐观链 :1831-1852），index.html:415-434，
// js/state.js:18（exerciseChosen:'run' / exerciseAmount:5 初值）。
// 断言链①~⑦逐字简报 Step1；简报②「顶格 toast」按裁废弃——H5 :1796-1806
// Math.min/max 静默，逐字对齐 H5：顶格再点数字不动、无 toast。
// M7-T2 时序（M6「乐观简化裁定」退役）：保存 → temp 行即插（:1813，
// id=tmpx_<ms> 自带 createdAt）→ 合计即涨（fold 含 temp ≙ :1814 +=）→
// toast 即弹不等回包（:1818）→ await → 成功 loadExercises 重取真值替换
// （:1826 then）/ 失败摘 temp+「记录失败：msg||网络异常」（:1827-1828，
// 失败不重取——H5 catch 不调 loadExercises）。删除链同款：确认 → 乐观删
// →「已删除运动记录」即弹 → await → 失败回插+「删除失败：msg」（:1848）。
// 云 GET 不回 createdAt（T1 登记）→ 刷新后 rep 型退化分钟档；temp 行自带
// createdAt → 即显「N 次」（home_exercise_test 钉④锁死该时序）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/theme.dart' show shiguangTheme;
import 'package:shiguang_flutter/data/api_client.dart' show ApiException;
import 'package:shiguang_flutter/domain/constants.dart' show Exercise, exerciseLib;
import 'package:shiguang_flutter/features/exercise/exercise_controller.dart';
import 'package:shiguang_flutter/features/exercise/exercise_sheet.dart';
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider;

import 'harness.dart';
import 'stubs/stub_health_api.dart';

const kDate = '2026-09-26';

final Exercise pushup =
    exerciseLib.firstWhere((l) => l.key == 'pushup'); // 俯卧撑 rep/次

/// 默认档：profile.body.weightKg=66.66（简报③样本体重；亦 ④ toast 12kcal 源）。
/// 需要 55kg 缺省档时用例内改写 api.profile。
StubHealthApi newApi({
  Map<String, List<Map<String, dynamic>>>? exercises,
}) =>
    StubHealthApi(
      profile: <String, dynamic>{
        ...StubHealthApi.profileMap(),
        'body': <String, dynamic>{'weightKg': 66.66},
      },
      exercisesByDate: exercises,
    );

/// 直调宿主：≙ T3 首页语境（openExerciseSheet 的 context+ref 来自常驻列表页）。
/// delete-x1 钮镜像 T3 将来的接线序：confirmDeleteExercise → deleteExerciseRecord。
class _Host extends ConsumerWidget {
  const _Host();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 挂住当日 provider：钉①②「temp 即插/真值替换」+ ⑥「回插」断言的观测位。
    // M7-T2：ex-kcal 走 exerciseKcalProvider fold（含 temp ≙ :1814 合计即涨）
    final list = ref.watch(exercisesProvider(kDate));
    final n = list.maybeWhen(data: (l) => l.length, orElse: () => -1);
    final total = ref.watch(exerciseKcalProvider(kDate));
    void toast(String m) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }

    return Scaffold(
      body: Column(
        children: [
          Text('ex-n:$n'), // 当日列表现值（M7-T2 起含 temp 行）
          Text('ex-kcal:$total'), // 合计现值（乐观即涨，失败回滚即扣）
          TextButton(
            onPressed: () => openExerciseSheet(context, ref, date: kDate),
            child: const Text('open-sheet'),
          ),
          // ⑤b 云态失败（ok:false 非抛错）直调控制器：弹层保存闸挡不到这条，
          // 只能绕过 UI 验证 addExerciseRecord 的 res['ok']==false 分支
          TextButton(
            key: const Key('direct-add'),
            onPressed: () =>
                addExerciseRecord(ref, kDate, pushup, 1, toast), // 1 次 @55kg → kcal 0
            child: const Text('direct-add'),
          ),
          TextButton(
            key: const Key('delete-x1'),
            onPressed: () async {
              final ok = await confirmDeleteExercise(context);
              if (!ok || !context.mounted) return;
              final rec = ref.read(exercisesProvider(kDate))
                  .maybeWhen(data: (l) => l.isEmpty ? null : l.first, orElse: () => null);
              if (rec == null) return;
              await deleteExerciseRecord(ref, kDate, rec, toast);
            },
            child: const Text('delete-x1'),
          ),
        ],
      ),
    );
  }
}

Future<ProviderContainer> pumpHost(WidgetTester tester, StubHealthApi api) async {
  await useBigSurface(tester);
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
  return container;
}

Future<void> openSheet(WidgetTester tester) async {
  await tester.tap(find.text('open-sheet'));
  await tester.pumpAndSettle();
}

String amountOf(WidgetTester tester) =>
    tester.widget<TextField>(find.byKey(exAmountKey)).controller!.text;

Future<void> tapKey(WidgetTester tester, Key key) async {
  final f = find.byKey(key);
  await tester.ensureVisible(f);
  await tester.pumpAndSettle();
  await tester.tap(f);
  await tester.pumpAndSettle();
}

Future<void> tapChip(WidgetTester tester, String key) =>
    tapKey(tester, exChipKey(key));

Future<void> setAmount(WidgetTester tester, String v) async {
  await tester.enterText(find.byKey(exAmountKey), v);
  await tester.pumpAndSettle();
}

void main() {
  /* ---------- ① chips 选择重置数量（app.js:1784-1791 逐字） ---------- */

  testWidgets('①默认跑步 amount=5/距离/km；chips 点选重置：俯卧撑10(次)、跳绳10(个)、跑步5、时长型20(分钟)',
      (tester) async {
    await pumpHost(tester, newApi());
    await openSheet(tester);

    expect(find.text('记运动'), findsOneWidget); // index.html:420 逐字
    expect(amountOf(tester), '5'); // state.js:18 exerciseAmount:5
    expect(find.text('距离'), findsOneWidget); // exerciseAmountLabel km 档
    expect(find.text('km'), findsOneWidget);

    await tapChip(tester, 'pushup'); // :1787 rep→10
    expect(amountOf(tester), '10');
    expect(find.text('数量'), findsOneWidget);
    expect(find.text('次'), findsOneWidget); // repUnit 次

    await tapChip(tester, 'rope'); // 跳绳 rep→10
    expect(amountOf(tester), '10');
    expect(find.text('个'), findsOneWidget); // repUnit 个

    await tapChip(tester, 'run'); // 跑步 km→5
    expect(amountOf(tester), '5');

    await tapChip(tester, 'swim'); // 时长型→20
    expect(amountOf(tester), '20');
    expect(find.text('时长'), findsOneWidget);
    expect(find.text('分钟'), findsOneWidget);
  });

  /* ---------- ② 步进三型上下限（app.js:1792-1806 逐支；顶格静默） ---------- */

  testWidgets('②km 型 ±0.5：5→5.5→6（整值去 .0）；下限 0.5 再减不动；99.9→100 顶格再点不动、无 toast',
      (tester) async {
    await pumpHost(tester, newApi());
    await openSheet(tester); // 默认跑步 km 档

    await tapKey(tester, exIncKey);
    expect(amountOf(tester), '5.5');
    await tapKey(tester, exIncKey);
    expect(amountOf(tester), '6'); // +((5.5+0.5).toFixed(1)) → 6

    await setAmount(tester, '1');
    await tapKey(tester, exDecKey);
    expect(amountOf(tester), '0.5'); // Math.max(step, 0.5)
    await tapKey(tester, exDecKey);
    expect(amountOf(tester), '0.5'); // 下限不动

    await setAmount(tester, '99.9');
    await tapKey(tester, exIncKey);
    expect(amountOf(tester), '100'); // min(100, 100.4)
    await tapKey(tester, exIncKey);
    expect(amountOf(tester), '100'); // 顶格静默（H5 Math.min 无 toast，简报已裁）
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('②b rep 型 ±5：下限 5、上限 2000 顶格静默；min 型：下限 5、上限 300 顶格静默',
      (tester) async {
    await pumpHost(tester, newApi());
    await openSheet(tester);

    await tapChip(tester, 'pushup'); // rep：10
    await tapKey(tester, exDecKey);
    expect(amountOf(tester), '5');
    await tapKey(tester, exDecKey);
    expect(amountOf(tester), '5'); // max(5, 0) 下限
    await setAmount(tester, '1998');
    await tapKey(tester, exIncKey);
    expect(amountOf(tester), '2000'); // min(2000, 2003)
    await tapKey(tester, exIncKey);
    expect(amountOf(tester), '2000');
    expect(find.byType(SnackBar), findsNothing);

    await tapChip(tester, 'yoga'); // min：20
    expect(amountOf(tester), '20');
    await setAmount(tester, '8');
    await tapKey(tester, exDecKey);
    expect(amountOf(tester), '5'); // max(5, 3)
    await setAmount(tester, '298');
    await tapKey(tester, exIncKey);
    expect(amountOf(tester), '300'); // min(300, 303)
    await tapKey(tester, exIncKey);
    expect(amountOf(tester), '300');
    expect(find.byType(SnackBar), findsNothing);
  });

  /* ---------- ③ 预览「预计消耗 N kcal」（updateExercisePreview :1761-1769） ---------- */

  testWidgets('③体重 66.66：跑步 5km → 345（1.036×66.66×5=345.2988）；换游泳 20min → 187',
      (tester) async {
    await pumpHost(tester, newApi());
    await openSheet(tester);
    // :1766 w = state.body ? weightKg : 55 —— profileProvider.body.weightKg
    expect(find.textContaining('预计消耗 345 kcal'), findsOneWidget);
    await tapChip(tester, 'swim'); // 8×3.5×66.66/200×20=186.648 → 187
    expect(find.textContaining('预计消耗 187 kcal'), findsOneWidget);
  });

  testWidgets('③b 体重缺省 55（profile.body 无 weightKg）：跑步 5km → 285（1.036×55×5=284.9）',
      (tester) async {
    final api = newApi();
    api.profile = StubHealthApi.profileMap(); // body:{} → weightKg 缺省 55
    await pumpHost(tester, api);
    await openSheet(tester);
    expect(find.textContaining('预计消耗 285 kcal'), findsOneWidget);
  });

  /* ---------- ④ 保存（:1807-1830）：保存闸 + 成功体逐键 + 成功 toast ---------- */

  testWidgets('④保存闸：1 次俯卧撑 @55kg → kcal 0 → toast「请先设置运动量」，零请求、弹层不关',
      (tester) async {
    final api = newApi();
    api.profile = StubHealthApi.profileMap(); // 55kg 档使 1 次 → round(0.2475)=0
    await pumpHost(tester, api);
    await openSheet(tester);
    await tapChip(tester, 'pushup');
    await setAmount(tester, '1');
    await tapKey(tester, exSaveKey);
    expect(find.text('请先设置运动量'), findsOneWidget); // :1812 逐字
    expect(api.exerciseBodies, isEmpty); // 不发请求
    expect(find.text('记运动'), findsOneWidget); // 弹层不关
  });

  testWidgets('④b 正常保存：俯卧撑 40 次 @66.66 → body 逐键（unit 直传 lib.unit=rep）、弹层关、toast「已记录俯卧撑 · 消耗 12 kcal」；M7-T2：回包重取后 temp 被云真值替换（1 行、id=x_stub_1）',
      (tester) async {
    final api = newApi();
    final container = await pumpHost(tester, api);
    await openSheet(tester);
    await tapChip(tester, 'pushup');
    await setAmount(tester, '40');
    await tapKey(tester, exSaveKey);

    // :1820-1822 七键逐字；unit 直传 lib.unit（云 index.js:362 归一 min 是云端的事）
    expect(api.exerciseBodies.single, <String, dynamic>{
      'date': kDate,
      'key': 'pushup',
      'name': '俯卧撑',
      'emoji': '💪',
      'amount': 40,
      'unit': 'rep',
      'kcal': 12, // 0.0045×66.66×40=11.9988 → 12
    });
    expect(find.text('记运动'), findsNothing); // 弹层关（≙ :1818 closeExerciseSheet）
    expect(find.text('已记录俯卧撑 · 消耗 12 kcal'), findsOneWidget); // :1819 逐字
    // M7-T2 钉①同款零等待：保存即 temp 行入列（本用例无 gate，仍在微任务前）
    expect(find.text('ex-n:1'), findsOneWidget); // ≙ :1813 push(temp)
    await pumpHostSettle(tester);
    // :1826 then→loadExercises：桩 POST 成功即落库 → 重取回真值，1 行替换非叠加
    expect(find.text('ex-n:1'), findsOneWidget);
    expect(find.text('ex-kcal:12'), findsOneWidget); // 1814 += 与 fold 重算同值
    final ids = (container.read(exercisesProvider(kDate)).value!)
        .map((r) => '${r['id']}')
        .toList();
    expect(ids, ['x_stub_1']); // temp（tmpx_ 前缀）已被云行替换
  });

  /* ---------- M7-T2 乐观链四钉（简报 Step1 ①②③；④在 home_exercise_test） ---------- */

  testWidgets('M7钉① 保存即态（:1813-:1818 零等待）：gate 挂住 addExercise → temp 行已入列（云 kcal 客户端值）、合计已涨、toast 已弹、层已关',
      (tester) async {
    final api = newApi()..addExerciseGate = Completer<void>();
    final container = await pumpHost(tester, api);
    final callsBefore = api.exerciseCalls;
    await openSheet(tester);
    await tapKey(tester, exSaveKey); // 默认跑步 5km@66.66 → 345kcal 过闸
    await tester.pump(); // 一帧泵出状态写与 SnackBar 挂载——不 await 任何回包

    expect(api.exerciseBodies, hasLength(1)); // 请求已发出（挂在闸上）
    expect(find.text('ex-n:1'), findsOneWidget); // ≙ :1813 temp 即插
    expect(find.text('ex-kcal:345'), findsOneWidget); // ≙ :1814 合计即涨
    expect(find.text('已记录跑步 · 消耗 345 kcal'), findsOneWidget); // :1818 toast 即弹
    expect(find.text('记运动'), findsNothing); // 层已关
    // temp 行逐字段 ≙ :1813：id=tmpx_<ms>、kcal 客户端值、createdAt=now
    final temp = container.read(exercisesProvider(kDate)).value!.single;
    expect('${temp['id']}', startsWith('tmpx_'));
    expect(temp['key'], 'run');
    expect(temp['name'], '跑步');
    expect(temp['kcal'], 345);
    expect((temp['createdAt'] as num).toInt(), greaterThan(0));
    expect(api.exerciseCalls, callsBefore); // 回包前不重取（≙ H5 then 未到）
    // gate 不放行即收尾：addExercise 永久 pending，测试结束随容器丢弃（零悬挂回写）
  });

  testWidgets('M7钉② 成功回包：gate 放行 → loadExercises 重取（:1826 then），temp 被真 id 行替换（1 行不叠加）',
      (tester) async {
    final api = newApi()..addExerciseGate = Completer<void>();
    final container = await pumpHost(tester, api);
    final callsBefore = api.exerciseCalls; // 首载已取 1 次
    await openSheet(tester);
    await tapKey(tester, exSaveKey);
    await tester.pump();
    expect(find.text('ex-n:1'), findsOneWidget); // 钉①中间态：temp 行

    api.addExerciseGate!.complete(); // 云落库 + 回包
    await pumpHostSettle(tester);

    expect(api.exerciseCalls, callsBefore + 1); // then→loadExercises 恰好再发一次
    final rows = container.read(exercisesProvider(kDate)).value!;
    expect(rows.single['id'], 'x_stub_1'); // 云真值行（桩 GET 形状无 createdAt）
    expect(rows.single['unit'], 'km'); // km 档云白名单原样保留（index.js:362）
    expect(rows.single['kcal'], 345);
    expect(find.text('ex-n:1'), findsOneWidget); // 替换非叠加
    expect(find.text('ex-kcal:345'), findsOneWidget);
    expect(find.text('已记录跑步 · 消耗 345 kcal'), findsOneWidget); // 成功 toast 不回收（H5 同款）
  });

  testWidgets('M7钉③ 失败回滚（:1826-:1828）：addExerciseError → temp 摘除、合计扣回、「记录失败：boom」；失败不重取（H5 catch 不调 loadExercises）',
      (tester) async {
    final api = newApi()..addExerciseError = ApiException('boom');
    await pumpHost(tester, api);
    final callsBefore = api.exerciseCalls;
    await openSheet(tester);
    await tapKey(tester, exSaveKey); // 跑步 5km → 345

    expect(find.text('记录失败：boom'), findsOneWidget); // :1828 「记录失败：+msg||网络异常」
    expect(find.text('ex-n:0'), findsOneWidget); // temp 已摘除（按 id 过滤）
    expect(find.text('ex-kcal:0'), findsOneWidget); // 合计扣回（fold 重算）
    await pumpHostSettle(tester);
    expect(api.exerciseCalls, callsBefore); // 失败路径零重取 ≙ H5 :1826-1829 catch 段
    expect(api.exerciseBodies, hasLength(1));
  });

  /* ---------- ⑤ 失败回滚（:1823-1829；temp 摘除主钉见 M7钉③） ---------- */

  testWidgets('⑤addExerciseError 空 msg（≙ H5 err.message falsy）→ toast「记录失败：网络异常」+ temp 摘除、合计扣回、零重取',
      (tester) async {
    final api = newApi();
    api.addExerciseError = ApiException(''); // '' falsy ≙ JS undefined → '网络异常'（:1828）
    await pumpHost(tester, api);
    final callsBefore = api.exerciseCalls;
    await openSheet(tester);
    await tapKey(tester, exSaveKey); // 默认跑步 5km@66.66 → 345kcal 过闸
    expect(find.text('记录失败：网络异常'), findsOneWidget); // 「记录失败：+msg||网络异常」
    expect(find.text('ex-n:0'), findsOneWidget); // temp 已摘 ≙ :1826 filter
    expect(find.text('ex-kcal:0'), findsOneWidget); // 合计扣回 ≙ :1826 -=kcal
    expect(api.exerciseBodies.length, 1); // 请求确实发出
    await pumpHostSettle(tester);
    expect(api.exerciseCalls, callsBefore); // 失败不重取（≙ H5 catch 段无 loadExercises）
  });

  testWidgets('⑤b 云态 kcal=0（ok:false 非抛错）→ temp 先显后摘 + toast「记录失败：消耗热量无效」（:263 → :1828 链）',
      (tester) async {
    final api = newApi();
    api.profile = StubHealthApi.profileMap(); // 55kg：1 次俯卧撑 → 云 kcal 取整 0
    await pumpHost(tester, api);
    await tapKey(tester, const Key('direct-add'));
    // 桩 ≙ 云 index.js:353-355 回 {ok:false,message}；ApiClient:130 实链会
    // throw（message 优先），stub 直回 → 控制器侧判 ok 走同一失败文案
    expect(find.text('记录失败：消耗热量无效'), findsOneWidget);
    expect(find.text('ex-n:0'), findsOneWidget); // temp 摘除（0 kcal 行不留存）
    expect(api.exerciseBodies.length, 1);
  });

  /* ---------- ⑥ 删除（:1831-1852）：确认框 + 成功/取消/失败 ---------- */

  /* ---------- ⑦ 运动量输入框 Semantics（T2 评审移交②，index.html:428 aria-label） ---------- */

  testWidgets('⑦弹层运动量输入框带 Semantics「运动量」（index.html:428 aria-label 逐字）',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpHost(tester, newApi());
    await openSheet(tester);
    expect(find.bySemanticsLabel('运动量'), findsOneWidget);
    handle.dispose();
  });

  Map<String, dynamic> x1() => <String, dynamic>{
        'id': 'x1',
        'key': 'run',
        'name': '跑步',
        'emoji': '🏃',
        'amount': 5,
        'unit': 'km',
        'kcal': 345,
      };

  testWidgets('⑥删除确认框文案逐字（「确认删除」/「删除后无法恢复，确定要删除这条运动吗？」）；取消 → 零请求',
      (tester) async {
    final api = newApi(exercises: {kDate: [x1()]});
    await pumpHost(tester, api);
    expect(find.text('ex-n:1'), findsOneWidget);

    await tapKey(tester, const Key('delete-x1'));
    expect(find.text('删除后无法恢复，确定要删除这条运动吗？'), findsOneWidget); // :1833 逐字
    expect(find.text('确认删除'), findsNWidgets(2)); // 标题 + 确认钮均「确认删除」
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(api.deletedExerciseIds, isEmpty); // 取消零请求（:1834 return）
    expect(find.text('ex-n:1'), findsOneWidget);
  });

  testWidgets('⑥b 确认删除 → 乐观删零等待（:1836-1842）：gate 挂住回包，行已摘、合计已扣、「已删除运动记录」已弹；放行后 delete(x1)+重取真值同态',
      (tester) async {
    final api = newApi(exercises: {kDate: [x1()]})
      ..deleteExerciseGate = Completer<void>();
    await pumpHost(tester, api);
    expect(find.text('ex-n:1'), findsOneWidget); // 前置态
    await tapKey(tester, const Key('delete-x1'));
    await tester.tap(find.widgetWithText(TextButton, '确认删除'));
    await tester.pump(); // 确认框落定后单帧：回包还挂在闸上
    expect(find.text('ex-n:0'), findsOneWidget); // ≙ :1837 filter 乐观删（零等待）
    expect(find.text('ex-kcal:0'), findsOneWidget); // ≙ :1837 -=kcal
    expect(find.text('已删除运动记录'), findsOneWidget); // :1842 即弹，不等回包
    expect(api.deletedExerciseIds, ['x1']); // 请求已发出（挂在闸上）

    api.deleteExerciseGate!.complete(); // 云删 + then→loadExercises
    await pumpHostSettle(tester);
    expect(find.text('ex-n:0'), findsOneWidget); // 真值 = 乐观态（桩删库后回空）
    expect(api.exerciseCalls, greaterThan(0)); // then 段真的重发 getExercises
  });

  testWidgets('②c 终审 I1 步进链 Number 全串语义：输入「5.」点加 → 5.5'
      '（H5 Number("5.")=5 再 +0.5；原 num.tryParse=null→0→jsFixed1(0.5) 分岔）',
      (tester) async {
    await pumpHost(tester, newApi());
    await openSheet(tester); // 默认跑步 km 档
    await setAmount(tester, '5.');
    await tapKey(tester, exIncKey);
    expect(amountOf(tester), '5.5'); // :1801 +((Number(v)+step).toFixed(1))
  });

  testWidgets('⑥c deleteExerciseError → 先乐观删（gate 窗口可观测）、「删除失败：boom」第二条 toast + rec 回插（:1846-1850 双 toast 链）',
      (tester) async {
    final api = newApi(exercises: {kDate: [x1()]})
      ..deleteExerciseError = ApiException('boom')
      ..deleteExerciseGate = Completer<void>();
    await pumpHost(tester, api);
    await tapKey(tester, const Key('delete-x1'));
    await tester.tap(find.widgetWithText(TextButton, '确认删除'));
    await tester.pump(); // 回包挂闸：乐观删窗口真实存在（微任务链未跑完）
    expect(find.text('ex-n:0'), findsOneWidget); // ≙ :1837 即删
    expect(find.text('已删除运动记录'), findsOneWidget); // :1842 先弹（H5 同款双 toast）

    api.deleteExerciseGate!.complete(); // 放行 → 抛 boom → 回插支
    await pumpHostSettle(tester);
    expect(find.text('删除失败：boom'), findsOneWidget); // :1850 逐字（hideCurrent 后为在场条）
    expect(find.text('ex-n:1'), findsOneWidget); // :1848 push(rec) 末位回插
    expect(find.text('ex-kcal:345'), findsOneWidget); // 合计回补
    // 失败支不重取（H5 catch 只回插）：exercise 请求仅首载一次
    expect(api.exerciseCalls, 1);
  });
}

/// toast/SnackBar 弹出后列表重取在途：多泵一轮 settle 让 invalidate 链走完
Future<void> pumpHostSettle(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}
