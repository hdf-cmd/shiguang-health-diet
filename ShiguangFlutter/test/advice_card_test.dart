// ShiguangFlutter/test/advice_card_test.dart
// M6 Task 5：首页每日建议卡接线（纯 UI 接线；domain/advice.dart 已逐字移植并有
// test/domain/advice_test.dart 纯函数用例，本文件只钉装配六入参 + 渲染 + 卡位）。
// 行为权威源 H5（逐字）：
// - app.js:348-362 renderDailyAdvice —— `if (!s || !el) return` 不渲染语义：
//   summary 未就绪（在途/失败）时建议不渲染（H5 卡框系静态 HTML 占位，非渲染
//   决策；Flutter 无静态骨架 → 整卡不渲染，差异登记见报告）；
//   ctx 六入参：summary / exerciseKcal: state.exerciseKcal||0 / records /
//   isToday: state.date===todayIso() / weightKg: state.body.weightKg||55（本仓
//   按上游裁定用 ??，0 值 falsy 支不引入——与 water_card 评审遗留同类）/
//   waterGoalMl: state.waterGoalMl。
//   tips.map → li：icon span + text span（:361）。
// - index.html:106-109 .card.advice-home —— 标题实源「每日建议」+ .more
//   「根据今日记录实时生成」（简报写「今日建议」，按实源，T4 先例）；
//   卡位实序 plate(70) → advice(106) → water(111) → exercise(133)。
// - R2 >110 死分支回归（简报③）：kcal=1.11*budget 样本下不出现「超标」类
//   文案——现行 ADVICE_RULES 超标表述恒为「超今日额度 N kcal」（logic.js:184/194），
//   比例>110% 触发的「超标」句在本规则表从未存在（死分支/未立分支），钉回归。
// 样本直出（①）：UI 行与 buildAdvice(makeAdviceCtx(同参)) 纯函数输出逐字比对，
// 另钉一条已知样本「蛋白质还差 100g，下一餐加一份蛋、豆制品或鱼虾」
// （简报原话「蛋白质…偏低」，实源文案为「还差 Xg」支，按实源钉）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/theme.dart' show shiguangTheme;
import 'package:shiguang_flutter/domain/advice.dart'
    show makeAdviceCtx, buildAdvice;
import 'package:shiguang_flutter/domain/dates.dart' show todayIso;
import 'package:shiguang_flutter/domain/models.dart' show Summary;
import 'package:shiguang_flutter/features/home/advice_card.dart'
    show AdviceCard, adviceCardKey, adviceTitleKey, adviceRowKey;
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider;
import 'package:shiguang_flutter/features/home/home_screen.dart' show HomeScreen;
import 'package:shiguang_flutter/features/home/water_card.dart'
    show waterTitleKey;

import 'harness.dart' show useBigSurface;
import 'stubs/stub_health_api.dart';

/// 桩 profile：可变体重/喝水目标（其余键走 StubHealthApi.profileMap 默认档）
Map<String, dynamic> profileWith({num? weightKg, num waterMl = 1600}) =>
    <String, dynamic>{
      ...StubHealthApi.profileMap(),
      'body': weightKg == null
          ? <String, dynamic>{}
          : <String, dynamic>{'weightKg': weightKg},
      'goal': {'dailyKcal': 1679, 'targetWeight': 55, 'waterMl': waterMl},
    };

StubHealthApi newApi({
  required Map<String, dynamic> summary,
  List<dynamic> records = const <dynamic>[],
  Map<String, dynamic>? profile,
  List<Map<String, dynamic>> exercises = const <Map<String, dynamic>>[],
}) =>
    StubHealthApi(
      summary: summary,
      records: records,
      profile: profile ?? profileWith(),
      exercisesByDate: {todayIso(): <Map<String, dynamic>>[...exercises]},
    );

Future<void> pumpCard(
  WidgetTester tester,
  StubHealthApi api, {
  String? date,
}) async {
  await useBigSurface(tester);
  await tester.pumpWidget(ProviderScope(
    overrides: [healthApiProvider.overrideWithValue(api)],
    child: MaterialApp(
      theme: shiguangTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: AdviceCard(date: date ?? todayIso()),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

/// ①直出比对核心：UI 第 i 行 = tips[i] 的 icon+text；行数与 tips 相等（无第 N 行）
void expectAdviceRows(List<(String, String)> tips) {
  for (var i = 0; i < tips.length; i++) {
    final row = find.byKey(adviceRowKey(i));
    expect(row, findsOneWidget, reason: '第 $i 行应渲染');
    expect(
      find.descendant(of: row, matching: find.text(tips[i].$1)),
      findsOneWidget,
      reason: '第 $i 行 icon ≙ :361 <span class=ai>',
    );
    expect(
      find.descendant(of: row, matching: find.text(tips[i].$2)),
      findsOneWidget,
      reason: '第 $i 行文案与 buildAdvice 输出逐字一致',
    );
  }
  expect(find.byKey(adviceRowKey(tips.length)), findsNothing); // 行数不多不少
}

void main() {
  /* ---------- ① 样本直出（app.js:348-362 + logic.js ADVICE_RULES） ---------- */

  testWidgets(
      '①样本 kcal200/target1679 仅早餐：渲染 3 行与 buildAdvice 输出逐字一致；钉已知句「蛋白质还差 100g…」；标题「每日建议」',
      (tester) async {
    final api = newApi(
      summary: StubHealthApi.summaryMap(
          kcal: 200, target: 1679, carb: 30, protein: 5, fat: 10, water: 1),
      records: [
        StubHealthApi.recordMap(
            id: 'r1', meal: 'breakfast', name: '鸡蛋', portion: '1 个', kcal: 200),
      ],
    );
    await pumpCard(tester, api);

    expect(find.byKey(adviceCardKey), findsOneWidget);
    expect(find.byKey(adviceTitleKey), findsOneWidget);
    expect(find.text('每日建议'), findsOneWidget); // index.html:107 实源
    expect(find.text('根据今日记录实时生成'), findsOneWidget); // :107 .more

    final expected = buildAdvice(makeAdviceCtx(
      summary: const Summary(
          kcal: 200, target: 1679, carb: 30, protein: 5, fat: 10, water: 1),
      exerciseKcal: 0,
      records: const [
        {'meal': 'breakfast'}
      ],
      isToday: true,
      weightKg: 55, // profile.body 空 → 缺省 55（:357）
      waterGoalMl: 1600, // goal.waterMl（:358）
    ));
    expect(expected.length, 3); // meal-room/protein-meal/carb，water 被 take(3) 截
    expectAdviceRows(expected);
    // 已知样本直钉一条（防纯函数与用例共错）：pGap=105-5=100
    expect(
      find.text('蛋白质还差 100g，下一餐加一份蛋、豆制品或鱼虾'),
      findsOneWidget,
    );
  });

  testWidgets(
      '①b 六入参装配源：ex=100 进 budget、profile 体重 60 进快走文案、waterMl 2000 进水tip——UI 与同参纯函数逐字一致',
      (tester) async {
    final api = newApi(
      summary: StubHealthApi.summaryMap(
          kcal: 1200, target: 1000, carb: 100, protein: 60, fat: 20, water: 9),
      records: [
        StubHealthApi.recordMap(
            id: 'r1', meal: 'breakfast', name: 'a', portion: 'p', kcal: 400),
        StubHealthApi.recordMap(
            id: 'r2', meal: 'lunch', name: 'b', portion: 'p', kcal: 400),
        StubHealthApi.recordMap(
            id: 'r3', meal: 'dinner', name: 'c', portion: 'p', kcal: 400),
      ],
      profile: profileWith(weightKg: 60, waterMl: 2000),
      exercises: [
        <String, dynamic>{
          'id': 'x1', 'key': 'walk', 'name': '快走', 'emoji': '🚶',
          'amount': 30, 'unit': 'min', 'kcal': 100,
        }
      ],
    );
    await pumpCard(tester, api);

    final expected = buildAdvice(makeAdviceCtx(
      summary: const Summary(
          kcal: 1200, target: 1000, carb: 100, protein: 60, fat: 20, water: 9),
      exerciseKcal: 100, // exercisesProvider → exerciseKcalProvider（T3 已接）
      records: const [
        {'meal': 'breakfast'},
        {'meal': 'lunch'},
        {'meal': 'dinner'},
      ],
      isToday: true,
      weightKg: 60, // profileProvider body.weightKg（:357）
      waterGoalMl: 2000, // profileProvider goal.waterMl（:358）
    ));
    // snack-over（remain=-100，快走值含 weightKg=60）+ water（1800<2000）
    expect(expected.length, 2);
    expectAdviceRows(expected);
  });

  testWidgets('①c 非今日：isToday=false → empty 规则走非今日支；水规则不触发', (tester) async {
    final api = newApi(summary: StubHealthApi.summaryMap(target: 1679));
    await pumpCard(tester, api, date: '2026-01-01');
    final expected = buildAdvice(makeAdviceCtx(
      summary: const Summary(
          kcal: 0, target: 1679, carb: 0, protein: 0, fat: 0, water: 0),
      isToday: false,
    ));
    expectAdviceRows(expected);
    expect(
      find.text('这一天还没有记录，可在记录页切换日期查看'),
      findsOneWidget,
    );
    expect(find.textContaining('喝水'), findsNothing); // water 规则 isToday 门
  });

  /* ---------- ①d 体重入参 falsy 闸（M7-T8 终审 Minor-2；≙ :357 `(state.body
     && state.body.weightKg) || 55` 直测——UI 现值面两口径不可分辨，
     domain/exercise.dart exerciseKcalOf 对 0 另有 falsy 回退 55，
     故闸语义由纯单元钉） ---------- */

  test('①d weightOf：0/null/缺body/非数值/在途 → 55；正常数值直取（falsy 口径）', () {
    AsyncValue<Map<String, dynamic>> data(Map<String, dynamic> p) =>
        AsyncData<Map<String, dynamic>>(p);
    // ≙ :357 `weightKg: (state.body && state.body.weightKg) || 55`
    expect(AdviceCard.weightOf(data(profileWith(weightKg: 0))), 55); // 0 falsy 支
    expect(AdviceCard.weightOf(data(profileWith())), 55); // body 空 map
    expect(
        AdviceCard.weightOf(data(<String, dynamic>{
          ...StubHealthApi.profileMap(),
          'body': {'weightKg': '60'} // 非数值串（fixture 锁 num，防御位）
        })),
        55);
    expect(AdviceCard.weightOf(const AsyncLoading<Map<String, dynamic>>()),
        55); // 在途 ≙ H5 state.body 未就绪
    expect(AdviceCard.weightOf(data(profileWith(weightKg: 60))), 60); // 真值直取
  });

  /* ---------- ② 就绪态：summary loading → 不渲染（:351 if (!s) return） ---------- */

  testWidgets('②summary 在途：整卡不渲染（标题/行都无）；回包后出现', (tester) async {
    final api = newApi(summary: StubHealthApi.summaryMap(target: 1679));
    final gate = Completer<void>();
    api.summaryGate = gate;

    await useBigSurface(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: [healthApiProvider.overrideWithValue(api)],
      child: MaterialApp(
        theme: shiguangTheme(),
        home: const Scaffold(body: AdviceCard(date: '2026-01-01')),
      ),
    ));
    await tester.pump();

    expect(find.byKey(adviceCardKey), findsNothing); // :351 不渲染语义
    expect(find.text('每日建议'), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(adviceCardKey), findsOneWidget); // summary 到齐即渲染
    expect(find.text('每日建议'), findsOneWidget);
  });

  /* ---------- ③ R2 >110 死分支回归（kcal=1.11×budget → 无「超标」类文案） ---------- */

  testWidgets(
      '③kcal1110/budget1000（111%）：不出现「超标」字样；超标表述恒为现行「已超今日额度 110 kcal」支',
      (tester) async {
    final api = newApi(
      summary: StubHealthApi.summaryMap(
          kcal: 1110, target: 1000, carb: 120, protein: 60, fat: 20, water: 9),
      records: [
        StubHealthApi.recordMap(
            id: 'r1', meal: 'breakfast', name: 'a', portion: 'p', kcal: 1110),
      ],
    );
    await pumpCard(tester, api);

    // 「超标」比例句在现行规则表从未存在（死分支）——任何一行都不得含
    for (final t in find.textContaining('超标').evaluate()) {
      fail('死分支复活：${(t.widget as Text).data}');
    }
    expect(find.textContaining('超标'), findsNothing);

    final expected = buildAdvice(makeAdviceCtx(
      summary: const Summary(
          kcal: 1110, target: 1000, carb: 120, protein: 60, fat: 20, water: 9),
      records: const [
        {'meal': 'breakfast'}
      ],
      isToday: true,
      weightKg: 55,
      waterGoalMl: 1600,
    ));
    expect(expected.first.$2, contains('已超今日额度 110 kcal')); // 现行活支
    expectAdviceRows(expected);
  });

  /* ---------- ④ 卡位：餐盘环卡与喝水卡之间（index.html:70/106/111 实序） ---------- */

  testWidgets('④HomeScreen 卡序：餐盘卡 → 建议卡 → 水卡 → 三餐卡 → 运动卡（advice bottom < water title top）',
      (tester) async {
    final api = newApi(
      summary: StubHealthApi.summaryMap(
          kcal: 200, target: 1679, carb: 30, protein: 5, fat: 10, water: 1),
      records: [
        StubHealthApi.recordMap(
            id: 'r1', meal: 'breakfast', name: '鸡蛋', portion: '1 个', kcal: 200),
      ],
    );
    await useBigSurface(tester);
    await tester.pumpWidget(ProviderScope(
      overrides: [healthApiProvider.overrideWithValue(api)],
      child: MaterialApp(theme: shiguangTheme(), home: const HomeScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(adviceCardKey), findsOneWidget);
    // 环卡内 note（home_screen.dart ValueKey('ring-note')，plate 卡底部）之后
    final ringNote = tester.getRect(find.byKey(const ValueKey('ring-note')));
    final advice = tester.getRect(find.byKey(adviceCardKey));
    final waterTitle = tester.getRect(find.byKey(waterTitleKey));
    final exTitle = tester.getRect(find.text('今日运动'));
    expect(advice.top, greaterThan(ringNote.bottom)); // 餐盘卡之后
    expect(advice.bottom, lessThan(waterTitle.top)); // 水卡之前
    expect(waterTitle.bottom, lessThan(exTitle.top)); // 运动卡仍在水卡之后（回归不破坏）
  });
}
