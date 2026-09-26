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
// 样本按「10 分钟」显示（非「10 次」），bug-for-bug。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/theme.dart' show shiguangTheme;
import 'package:shiguang_flutter/domain/dates.dart' show todayIso;
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

  /* ---------- ⑤ 删除链（✕ → T2 确认框 → deleteExerciseRecord） ---------- */

  testWidgets('⑤✕→确认框「确认删除」文案逐字；取消零请求；确认后 delete(x1)+toast+列表回剩 12',
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
    await tester.tap(find.widgetWithText(TextButton, '确认删除'));
    await tester.pumpAndSettle();
    expect(api.deletedExerciseIds, ['x1']); // 云 DELETE /diet/exercises/x1
    expect(find.text('已删除运动记录'), findsOneWidget); // :1842 逐字
    expect(find.text('消耗 12 kcal'), findsOneWidget); // invalidate 重取：剩 x2
    expect(find.text('-181 kcal'), findsNothing);
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
}
