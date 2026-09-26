// ShiguangFlutter/test/exercise_sheet_test.dart
// M6 Task 2：运动控制器（exercisesProvider/add/delete）+ 记运动弹层。
// 行为权威源 js/app.js:1758-1852（chips 重置量/步进三型上下限/预览/保存闸/
// 成功失败文案/删除确认），index.html:415-434（记运动 DOM），
// js/state.js:18（exerciseChosen:'run' / exerciseAmount:5 初值）。
// 断言链①~⑥逐字简报 Step1；简报②「顶格 toast」按裁废弃——H5 :1796-1806
// Math.min/max 静默，逐字对齐 H5：顶格再点数字不动、无 toast。
// 退化断言说明（上游事实，T1 登记）：云 GET 不回 createdAt → isRepRecord
// 恒退化按分钟显示；且 Flutter 侧不做本地 temp 行（乐观简化裁定：写后统一
// invalidate 重取真值），故「次数」显示只存在于 H5 当日会话。⑤的「列表不含
// temp」相应退化为「invalidate 重取后列表 = 云端真值（桩不含新行）」。
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
    // 挂住当日 provider：⑤「invalidate 重取」计数 + ⑥「回插」断言的观测位
    final list = ref.watch(exercisesProvider(kDate));
    final n = list.maybeWhen(data: (l) => l.length, orElse: () => -1);
    void toast(String m) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(m)));
    }

    return Scaffold(
      body: Column(
        children: [
          Text('ex-n:$n'), // 云端真值行数（不含 temp：本实现无 temp 行）
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

  testWidgets('④b 正常保存：俯卧撑 40 次 @66.66 → body 逐键（unit 直传 lib.unit=rep）、弹层关、toast「已记录俯卧撑 · 消耗 12 kcal」',
      (tester) async {
    final api = newApi();
    await pumpHost(tester, api);
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
    await pumpHostSettle(tester);
    expect(find.text('ex-n:0'), findsOneWidget); // 重取=云端真值，无本地 temp（裁定简化，头注登记）
  });

  /* ---------- ⑤ 失败回滚（:1823-1829） ---------- */

  testWidgets('⑤addExerciseError → toast「记录失败：boom」+ invalidate 重取（列表不含 temp）',
      (tester) async {
    final api = newApi();
    api.addExerciseError = ApiException('boom');
    await pumpHost(tester, api);
    final callsBefore = api.exerciseCalls;
    await openSheet(tester);
    await tapKey(tester, exSaveKey); // 默认跑步 5km@66.66 → 345kcal 过闸
    expect(find.text('记录失败：boom'), findsOneWidget); // :1828 「记录失败：+msg」
    expect(api.exerciseBodies.length, 1); // 请求确实发出
    await pumpHostSettle(tester);
    expect(api.exerciseCalls, greaterThan(callsBefore)); // 失败也 invalidate 重取
    expect(find.text('ex-n:0'), findsOneWidget); // 列表恒 = 云端真值（无 temp 可回滚）
  });

  testWidgets('⑤b 云态 kcal=0（ok:false 非抛错）→ toast「记录失败：消耗热量无效」',
      (tester) async {
    final api = newApi();
    api.profile = StubHealthApi.profileMap(); // 55kg：1 次俯卧撑 → 云 kcal 取整 0
    await pumpHost(tester, api);
    await tapKey(tester, const Key('direct-add'));
    // 桩 ≙ 云 index.js:353-355 回 {ok:false,message} 而非 HTTP 错 → 调用层判 ok
    expect(find.text('记录失败：消耗热量无效'), findsOneWidget);
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

  testWidgets('⑥b 确认删除 → deleteExercise(x1) + toast「已删除运动记录」+ invalidate 重取列表空',
      (tester) async {
    final api = newApi(exercises: {kDate: [x1()]});
    await pumpHost(tester, api);
    await tapKey(tester, const Key('delete-x1'));
    await tester.tap(find.widgetWithText(TextButton, '确认删除'));
    await tester.pumpAndSettle();
    expect(api.deletedExerciseIds, ['x1']); // :1843 deleteExercise(id)
    expect(find.text('已删除运动记录'), findsOneWidget); // :1842 逐字
    expect(find.text('ex-n:0'), findsOneWidget); // 桩成功即删行 → invalidate 重取
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

  testWidgets('⑥c deleteExerciseError → toast「删除失败：boom」+ invalidate 后列表回插',
      (tester) async {
    final api = newApi(exercises: {kDate: [x1()]});
    api.deleteExerciseError = ApiException('boom');
    await pumpHost(tester, api);
    await tapKey(tester, const Key('delete-x1'));
    await tester.tap(find.widgetWithText(TextButton, '确认删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除失败：boom'), findsOneWidget); // :1850 逐字
    expect(find.text('ex-n:1'), findsOneWidget); // 失败也 invalidate = 重取真值回插
  });
}

/// toast/SnackBar 弹出后列表重取在途：多泵一轮 settle 让 invalidate 链走完
Future<void> pumpHostSettle(WidgetTester tester) async {
  await tester.pump();
  await tester.pumpAndSettle();
}
