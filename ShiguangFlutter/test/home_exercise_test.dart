// ShiguangFlutter/test/home_exercise_test.dart
// M6 Task 3：首页运动卡（HomeExerciseCard）+ 餐盘环额度真实联动 + 身体卡今日运动行。
// 行为权威源 H5：
// - 运动卡：app.js:1740-1754（renderExerciseList：标题两支 :1741、副行「消耗 N kcal」
//   :1742、行结构 emoji/名/meta/「-kcal kcal」/✕ :1743-1751、空态 :1754）+
//   index.html:133-137（卡位 home 末位、按钮「＋ 记运动」）。
// - 环接线：app.js:298-309（budget=target+ex、ring-exercise、note 两支逐字）。
// - 身体卡：app.js:1584-1601（metab-exercise 常驻、tdee/suggest 值含 ex、
//   公式注记 ex>0 支、metab-note 含运动支）+ index.html:214-221（DOM 序：
//   今日运动=第 5 行，在每日缺口之后）。
// - 删除防重入：app.js:1832「确认框已开则 return」（T2 评审移交①）。
// 退化钉死（T1 登记）：云 GET 无 createdAt → isRepRecord 恒 false → pushup
// 样本按「10 分钟」显示（非「10 次」），bug-for-bug。M7-T2 钉④补全时序的另一
// 半：保存即插的 temp 行自带 createdAt（app.js:1813）→ 即显「N 次」，重取回
// 云真值后退化分钟档——「即显次数、刷新退化」的 H5 同款窗口在本文件锁死。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/theme.dart' show shiguangTheme;
import 'package:shiguang_flutter/data/api_client.dart' show ApiException;
import 'package:shiguang_flutter/domain/constants.dart' show exerciseLib;
import 'package:shiguang_flutter/domain/dates.dart' show todayIso;
import 'package:shiguang_flutter/features/exercise/exercise_controller.dart'
    show exercisesProvider;
import 'package:shiguang_flutter/features/exercise/exercise_sheet.dart'
    show exChipKey, exSaveKey;
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider;
import 'package:shiguang_flutter/features/home/home_screen.dart'
    show HomeScreen, HomeExerciseCard, homeExDelKey;
import 'package:shiguang_flutter/features/profile/body_profile_card.dart'
    show BodyProfileCard;

import 'harness.dart' show useBigSurface;
import 'stubs/stub_health_api.dart';

/// 简报②样本二条（云 GET 形状：无 createdAt）。
Map<String, dynamic> x1() => <String, dynamic>{
      'id': 'x1', 'key': 'run', 'name': '跑步', 'emoji': '🏃',
      'amount': 5, 'unit': 'km', 'kcal': 181,
    };
Map<String, dynamic> x2() => <String, dynamic>{
      'id': 'x2', 'key': 'pushup', 'name': '俯卧撑', 'emoji': '💪',
      'amount': 10, 'unit': 'min', 'kcal': 12,
    };

/// 简报④桩资料（同 body_profile_card_test xiaomanProfile：
/// bmr1406/tdee2179/suggest1679 核算基线）。
Map<String, dynamic> xiaomanProfile() => <String, dynamic>{
      'id': 'u_test',
      'nickname': '小满',
      'avatarText': '满',
      'avatarData': null,
      'signature': '把每一餐，记成时光',
      'goal': {'dailyKcal': 1679, 'targetWeight': 55, 'waterMl': 1600},
      'body': {
        'heightCm': 168, 'weightKg': 66.66, 'bmi': 23.6, 'age': 30,
        'gender': 'female', 'activity': 'moderate', 'deficit': 500,
      },
      'bodyUpdatedAt': 0,
    };

StubHealthApi newApi({List<Map<String, dynamic>>? exercises}) => StubHealthApi(
      profile: xiaomanProfile(),
      exercisesByDate: {
        todayIso(): <Map<String, dynamic>>[
          ...(exercises ?? const <Map<String, dynamic>>[])
        ],
      },
    );

Future<void> pumpHome(WidgetTester tester, StubHealthApi api) async {
  await useBigSurface(tester);
  await tester.pumpWidget(ProviderScope(
    overrides: [healthApiProvider.overrideWithValue(api)],
    // 生产语境 ≙ Shell Scaffold（shell.dart:40-45），toast 需 Scaffold 注册位
    child: MaterialApp(
        theme: shiguangTheme(),
        home: const Scaffold(body: HomeScreen())),
  ));
  await tester.pumpAndSettle();
}

Future<void> pumpBodyCard(WidgetTester tester, StubHealthApi api) async {
  await useBigSurface(tester);
  await tester.pumpWidget(ProviderScope(
    overrides: [healthApiProvider.overrideWithValue(api)],
    child: MaterialApp(
      theme: shiguangTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: BodyProfileCard(),
          ),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  /* ---------- ① 空态（app.js:1741/1742/1754） ---------- */

  testWidgets('①空态：卡题「今日运动」+副行「消耗 0 kcal」+空态文案+「＋ 记运动」；环 note 回落基准支',
      (tester) async {
    await pumpHome(tester, newApi());

    expect(find.text('今日运动'), findsOneWidget); // :1741 今日支
    expect(find.text('消耗 0 kcal'), findsOneWidget); // :1742
    expect(find.text('今天还没运动，点下方「记运动」'), findsOneWidget); // :1754 逐字
    expect(find.text('＋ 记运动'), findsOneWidget); // index.html:136
    // 环 note ex=0 支（app.js:309 逐字，M3 已落，回归不破坏）
    expect(find.text('基准目标 1679 kcal · 记运动后额度自动上调'), findsOneWidget);
  });

  /* ---------- ② 列表行（app.js:1743-1751）＋退化钉死 ---------- */

  testWidgets('②行：跑步「5 km」「-181 kcal」；俯卧撑无 createdAt → 退化「10 分钟」（非「10 次」）；合计「消耗 193 kcal」',
      (tester) async {
    await pumpHome(tester, newApi(exercises: [x1(), x2()]));

    expect(find.text('🏃'), findsOneWidget);
    expect(find.text('跑步'), findsOneWidget);
    expect(find.text('5 km'), findsOneWidget); // :1750 km 支
    expect(find.text('💪'), findsOneWidget);
    expect(find.text('俯卧撑'), findsOneWidget);
    expect(find.text('10 分钟'), findsOneWidget); // isRepRecord false → 分钟（退化钉死）
    expect(find.text('10 次'), findsNothing);
    expect(find.text('-181 kcal'), findsOneWidget); // :1750 「-{kcal} kcal」
    expect(find.text('-12 kcal'), findsOneWidget);
    expect(find.text('消耗 193 kcal'), findsOneWidget); // :1742 reduce 合计
  });

  /* ---------- M7-T2 钉④：temp 行即显「N 次」、刷新退化「N 分钟」 ---------- */

  testWidgets('M7钉④ 保存俯卧撑 10 次（:1813 temp 自带 createdAt）：回包前卡片即显「10 次」+「-3 kcal」；gate 放行重取后（云无 createdAt）退化「10 分钟」——H5 同款时序钉死',
      (tester) async {
    final api = newApi()..addExerciseGate = Completer<void>();
    await pumpHome(tester, api);

    await tester.tap(find.text('＋ 记运动'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(exChipKey('pushup'))); // rep 档重置 10
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(exSaveKey));
    await tester.pump(); // 单帧：回包未到（gate 挂住）

    expect(find.text('10 次'), findsOneWidget); // temp.createdAt → isRepRecord 命中
    expect(find.text('10 分钟'), findsNothing);
    expect(find.text('俯卧撑'), findsOneWidget);
    expect(find.text('-3 kcal'), findsOneWidget); // 0.0045×66.66×10=2.9997→3
    expect(find.text('消耗 3 kcal'), findsOneWidget); // 合计含 temp（≙ :1814）
    expect(find.text('已记录俯卧撑 · 消耗 3 kcal'), findsOneWidget); // :1818 即弹

    api.addExerciseGate!.complete(); // 放行：落库 + then→loadExercises
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.text('10 次'), findsNothing); // 云 GET 无 createdAt → 退化
    expect(find.text('10 分钟'), findsOneWidget); // ≙ 上方「退化钉死」注
    expect(find.text('消耗 3 kcal'), findsOneWidget); // 真值同 kcal，合计不动
    expect(find.text('-3 kcal'), findsOneWidget);
  });

  testWidgets('M7钉④b 退化态稳定：无 gate 直过（temp 一闪→重取）终态恒「10 分钟」，非渲染抖动回翻',
      (tester) async {
    final api = newApi();
    await pumpHome(tester, api);
    await tester.tap(find.text('＋ 记运动'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(exChipKey('pushup')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(exSaveKey)); // 无 gate：即时序上下一帧即回包
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text('10 分钟'), findsOneWidget); // 退化态稳定
    expect(find.text('10 次'), findsNothing);
  });

  /* ---------- ③ 环接线（app.js:298-309） ---------- */

  testWidgets('③target1679+ex193：额度行 1872、环中心 1872（kcal=0）、运动消耗 193、note「额度 1872 = 基准 1679 + 运动 193 kcal」',
      (tester) async {
    await pumpHome(tester, newApi(exercises: [x1(), x2()]));

    expect(find.textContaining('今日额度 1872'), findsOneWidget); // :302 budget
    expect(find.text('1872'), findsOneWidget); // 环中心 remain=max(0,1872-0)（:300/324）
    expect(find.textContaining('运动消耗 193'), findsOneWidget); // :304 ring-exercise
    expect(find.text('额度 1872 = 基准 1679 + 运动 193 kcal'), findsOneWidget); // :307 逐字
  });

  /* ---------- ④ 身体卡今日运动行（app.js:1584-1605） ---------- */

  testWidgets('④身体卡 ex=193：今日运动行 193、TDEE 值 2372+注记「BMR×系数1.55＋今日运动193」、建议 1872+注记「＋运动193」、note「含今日运动 193 kcal · 基准 1679」、注记「今日运动记录累计」',
      (tester) async {
    await pumpBodyCard(tester, newApi(exercises: [x1(), x2()]));

    expect(find.text('今日运动'), findsOneWidget); // :219 行 label（DOM 第 5 行）
    expect(find.text('193 kcal'), findsOneWidget); // :1588 metab-exercise 值
    expect(find.text('今日运动记录累计'), findsOneWidget); // :1601 注记逐字
    expect(find.text('2372 kcal'), findsOneWidget); // :1587 tdee+ex（2179+193）
    expect(find.text('BMR×系数1.55＋今日运动193'), findsOneWidget); // :1599 ex>0 支
    expect(find.text('1872 kcal'), findsOneWidget); // :1589 suggest+ex（1679+193）
    expect(find.text('消耗2179−缺口500＋运动193'), findsOneWidget); // :1600 ex>0 支
    expect(find.text('含今日运动 193 kcal · 基准 1679'), findsOneWidget); // :1605 含运动支
  });

  testWidgets('④b 身体卡 ex=0：今日运动行仍常驻「0 kcal」；TDEE/建议/公式/note 全回落 ex=0 支（app.js:1587-1605）',
      (tester) async {
    await pumpBodyCard(tester, newApi());

    expect(find.text('今日运动'), findsOneWidget); // 常驻（H5 值 0 也显）
    expect(find.text('0 kcal'), findsOneWidget);
    expect(find.text('2179 kcal'), findsOneWidget);
    expect(find.text('BMR×系数1.55'), findsOneWidget); // 无「＋今日运动」尾注
    expect(find.text('1679 kcal'), findsWidgets); // suggest 不含 ex
    expect(find.text('消耗2179−缺口500'), findsOneWidget);
    expect(find.textContaining('基准目标 1679 kcal'), findsOneWidget); // note 回落
    expect(find.textContaining('含今日运动'), findsNothing);
  });

  /* ---------- ⑤ 删除链（✕ → T2 确认框 → deleteExerciseRecord ≙ M7-T2 起
     notifier.remove 乐观链：行即摘、toast 即弹，await 后失败回插） ---------- */

  testWidgets('⑤✕→确认框「确认删除」文案逐字；取消零请求；确认后行即摘（零等待）+delete(x1)+toast+回剩 12',
      (tester) async {
    final api = newApi(exercises: [x1(), x2()]);
    await pumpHome(tester, api);

    await tester.tap(find.byKey(homeExDelKey('x1')));
    await tester.pumpAndSettle();
    expect(find.text('删除后无法恢复，确定要删除这条运动吗？'), findsOneWidget); // app.js:1833
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(api.deletedExerciseIds, isEmpty); // :1834 取消零请求

    await tester.tap(find.byKey(homeExDelKey('x1')));
    await tester.pumpAndSettle();
    final gate = Completer<void>();
    api.deleteExerciseGate = gate; // 挂住回包：乐观窗口真实可观测
    await tester.tap(find.widgetWithText(TextButton, '确认删除'));
    await tester.pump(); // 单帧：回包未到，断乐观即态（:1836-1842）
    expect(find.text('消耗 12 kcal'), findsOneWidget); // 跑步行即刻消失，合计即扣
    expect(find.text('-181 kcal'), findsNothing);
    expect(find.text('已删除运动记录'), findsOneWidget); // :1842 即弹
    gate.complete();
    await tester.pumpAndSettle();
    expect(api.deletedExerciseIds, ['x1']); // 云 DELETE /diet/exercises/x1
    expect(find.text('消耗 12 kcal'), findsOneWidget); // then loadExercises 真值同态
  });

  /* ---------- ⑥ 防重入守卫（T2 移交①，app.js:1832「确认框已开则 return」） ---------- */

  testWidgets('⑥守卫：同一回调连击两次（长按+click 双触等价模拟）→ 只开一个确认框、取消后零请求',
      (tester) async {
    final api = newApi(exercises: [x1(), x2()]);
    await pumpHome(tester, api);

    final gd = tester.widget<GestureDetector>(find.byKey(homeExDelKey('x1')));
    gd.onTap!(); // 第一次：置守卫、进 await 确认框
    gd.onTap!(); // 第二次同步：守卫命中 return（H5 :1832 等价）
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget); // 只有一个框
    await tester.tap(find.widgetWithText(TextButton, '取消'));
    await tester.pumpAndSettle();
    expect(api.deletedExerciseIds, isEmpty);
  });

  /* ---------- ⑦ ＋记运动 → T2 弹层 ---------- */

  testWidgets('⑦「＋ 记运动」打开记运动弹层（openExerciseSheet，hostRef=首页 ref、date=今日）',
      (tester) async {
    await pumpHome(tester, newApi());

    await tester.tap(find.text('＋ 记运动'));
    await tester.pumpAndSettle();
    expect(find.text('记运动'), findsOneWidget); // index.html:420
    expect(find.text('保存记录'), findsOneWidget); // :433
  });

  /* ---------- ⑧ 非今日标题支（app.js:1741 两支；首页恒今日，组件级直测） ---------- */

  testWidgets('⑧date≠今日：卡题「运动 · 1月1日」（dateLabelOf 复用，:1741 非今日支）',
      (tester) async {
    await useBigSurface(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: [healthApiProvider.overrideWithValue(newApi())],
      child: MaterialApp(
        theme: shiguangTheme(),
        home: const Scaffold(
          body: SingleChildScrollView(
            child: HomeExerciseCard(date: '2026-01-01'),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('运动 · 1月1日'), findsOneWidget);
    expect(find.text('今日运动'), findsNothing);
  });

  /* ---------- ⑨ M7-T8 结转件（评审 T2 Minor① 等值闸 + T1 deferred 桩对齐） ---------- */

  test('⑨a remove 失败回插闸：乐观窗口内并发写链重取把该行吞回 → 失败支不再插幽灵行（≙ H5 :1835/:1844 if(rec) 等值闸）',
      () async {
    final api = newApi(exercises: [x1()])
      ..deleteExerciseGate = Completer<void>();
    final c = ProviderContainer(
      overrides: [healthApiProvider.overrideWithValue(api)],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    final sub = c.listen(exercisesProvider(todayIso()), (_, _) {});
    addTearDown(sub.close);
    await c.read(exercisesProvider(todayIso()).future); // 首取 [x1]
    final notifier = c.read(exercisesProvider(todayIso()).notifier);
    final msgs = <String>[];

    final removeFut = notifier.remove(x1(), msgs.add); // 乐观删 → state []
    await null; await null; // 放行 remove 同步前缀至 await deleteExercise
    expect(c.read(exercisesProvider(todayIso())).value, isEmpty);

    // 并发写链：add 成功支 :1826 _reload 重取——DELETE 未落地（桩挂在闸上），
    // 回包含 x1 → 行被「吞回」（幽灵行温床：失败支若裸 push 即双份 x1）
    await notifier.add(
        exerciseLib.firstWhere((l) => l.key == 'pushup'), 10, 12, (_) {});
    expect(
        c.read(exercisesProvider(todayIso()))
            .value!
            .where((r) => r['id'] == 'x1')
            .length,
        1);

    api.deleteExerciseError = ApiException('服务器错误');
    api.deleteExerciseGate!.complete(); // 放行 → DELETE 抛 → 失败支
    await removeFut;

    // 闸命中（M7-T8 修前红：_reinsert 裸 push → x1 双行）；双 toast 文案链不变
    expect(
        c.read(exercisesProvider(todayIso()))
            .value!
            .where((r) => r['id'] == 'x1')
            .length,
        1,
        reason: '失败回插须判「该行仍不在 state」，在场即吞（≙ H5 :1836/:1844 rec '
            '缺席两支 skip push；并发重取吞回后本端对齐其下一拍抹平稳态）');
    expect(msgs, ['已删除运动记录', '删除失败：服务器错误']); // :1842/:1850 照弹不受闸影响
  });

  test('⑨b 桩云语义对齐（T1 deferred 销账）：amount/kcal Number() 强转 + kcal 无上界（云 index.js:354/:362）',
      () async {
    final api = StubHealthApi();
    Map<String, dynamic> body(Object amount, Object kcal) => <String, dynamic>{
          'date': todayIso(),
          'key': 'run',
          'name': '跑步',
          'emoji': '🏃',
          'amount': amount,
          'unit': 'km',
          'kcal': kcal,
        };
    // 数字串：云 Number('5')/'600' 强转入库（旧桩 is num 闸把 '5' 落 0）
    final r1 = await api.addExercise(body('5', '600'));
    expect(r1['ok'], true);
    expect(r1['amount'], 5);
    expect(r1['kcal'], 600);
    // 非数值串 ≙ Number('abc')=NaN||0 → kcal 0 → :355 !kcal 拒（ok:false 非 HTTP 错）
    final r2 = await api.addExercise(body('abc', 'abc'));
    expect(r2['ok'], false);
    // amount 非数值而 kcal 有效：≙ :362 Number('abc')||0 落 0，行照样入库
    final r2b = await api.addExercise(body('abc', 60));
    expect(r2b['ok'], true);
    expect(r2b['amount'], 0);
    // 负值 ≙ Math.max(0,·) 地板 → 0 → 拒；**无上界**（旧桩 clamp 1<<31 自加已去）
    final r3 = await api.addExercise(body(5, -300));
    expect(r3['ok'], false);
    final r4 = await api.addExercise(body(5, 5000000000)); // > 2^31
    expect(r4['ok'], true);
    expect(r4['kcal'], 5000000000);
  });
}
