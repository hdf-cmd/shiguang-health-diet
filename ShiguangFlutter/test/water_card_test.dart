// ShiguangFlutter/test/water_card_test.dart
// M6 Task 4：喝水闭环——首页水卡（喝一杯/撤销，乐观更新）+ 目标 goal-sheet（200 步进）。
// 行为权威源 H5（逐字）：
// - 水卡渲染：app.js:409-428 renderWater —— 标题两支（今日「喝水打卡」/非今日
//   「喝水 · {dateLabel}」:413）、ml=n*200（:414）、pct=min(100, ml/goal*100)（:416）、
//   hint 两支（reached「目标已达成 🎉」/「已喝 {n} 杯 · 每杯 200ml」:423）、
//   撤销可见性 n>0（:424，visibility:hidden ≙ Visibility maintainSize）。
//   DOM 结构 index.html:111-131。
// - 喝一杯：app.js:432-449 —— 顶格零请求「目标 {goal}ml 已达成，明天继续」（:433-435）、
//   乐观 +1 → toast「+200ml · 已喝 {ml}ml」→ addWater(1,date) 跟回包 → 失败回滚 +
//   toast「同步失败：{msg}」（msg 缺省「网络异常」，桩恒有 message）。
//   buzz(6) 振动与 SGNative.updateWaterProgress 常驻通知不移植（R4 差异登记，见报告）。
// - 撤销：app.js:452-467 —— 乐观 -1 → toast「已退回一杯 · 剩 {ml}ml」（乐观值口径）
//   → addWater(-1,date) 跟回包 → 失败回滚同支。
// - goal-sheet：app.js:470-493 + index.html:295-308 —— 开层预填当前目标；
//   bumpGoal ±200 截断 [800,3000]、顶格值不动 + toast「最大 3000ml」「最小 800ml」
//   （:480 逐字）；保存 setWaterGoal → 关层 → toast「喝水目标已设为 {回包}ml」；
//   200 步进/失焦归一在 UI 层（app.js:1653-1654），云端只做 [800,3000] 截断。
// - profileProvider invalidate：保存后 goal 行与「我的」页联动（上游事实）。
// 桩云语义锁（评审遗留修正）：setWaterGoal(0) → Number(x)||1600 → 1600（非截断 800）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/theme.dart' show shiguangTheme;
import 'package:shiguang_flutter/data/api_client.dart' show ApiException;
import 'package:shiguang_flutter/domain/dates.dart' show todayIso;
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider;
import 'package:shiguang_flutter/features/home/water_card.dart'
    show
        WaterCard,
        waterTitleKey,
        waterMlKey,
        waterGoalEditKey,
        waterBarKey,
        waterFillKey,
        waterCupKey,
        waterUndoKey;
import 'package:shiguang_flutter/features/home/goal_sheet.dart'
    show goalValueKey, goalDecKey, goalIncKey, goalSaveKey, goalCloseKey;

import 'harness.dart' show useBigSurface;
import 'stubs/stub_health_api.dart';

StubHealthApi newApi({num water = 0}) => StubHealthApi(
  summary: StubHealthApi.summaryMap(water: water),
  profile: StubHealthApi.profileMap(), // goal.waterMl=1600
);

Future<void> pumpCard(
  WidgetTester tester,
  StubHealthApi api, {
  String? date,
}) async {
  await useBigSurface(tester);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [healthApiProvider.overrideWithValue(api)],
      // 生产语境 ≙ Shell Scaffold（toast 需 Scaffold 注册位）
      child: MaterialApp(
        theme: shiguangTheme(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: WaterCard(date: date ?? todayIso()),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  /* ---------- ① 渲染（app.js:409-428 + index.html:111-131） ---------- */

  testWidgets(
    '①water=3/goal1600：标题「喝水打卡」、ml 600、hint「已喝 3 杯 · 每杯 200ml」、进度 37.5%、撤销可见',
    (tester) async {
      await pumpCard(tester, newApi(water: 3));

      expect(find.byKey(waterTitleKey), findsOneWidget);
      expect(find.text('喝水打卡'), findsOneWidget); // :413 今日支
      expect(
        tester.widget<Text>(find.byKey(waterMlKey)).data,
        '600',
      ); // 3×200（:414 water-ml 大数字）
      expect(find.text('已喝 3 杯 · 每杯 200ml'), findsOneWidget); // :423 逐字
      final bar = tester.getRect(find.byKey(waterBarKey));
      final fill = tester.getRect(find.byKey(waterFillKey));
      expect(
        fill.width / bar.width,
        closeTo(0.375, 0.001),
      ); // :416 pct=min(100,·)
      expect(
        tester.widget<Visibility>(find.byKey(waterUndoKey)).visible,
        isTrue,
      ); // :424
      expect(
        find.textContaining('目标 1600 ml'),
        findsOneWidget,
      ); // index.html:115 goal 行
    },
  );

  testWidgets(
    '①b water=0：撤销隐藏（visibility:hidden 保位，:424）；water=8=1600ml：hint「目标已达成 🎉」且进度封顶 100%',
    (tester) async {
      await pumpCard(tester, newApi());
      expect(
        tester.widget<Visibility>(find.byKey(waterUndoKey)).visible,
        isFalse,
      );
      expect(find.text('已喝 0 杯 · 每杯 200ml'), findsOneWidget);

      await pumpCard(tester, newApi(water: 8));
      expect(find.text('目标已达成 🎉'), findsOneWidget); // :423 reached 支逐字
      final bar = tester.getRect(find.byKey(waterBarKey));
      final fill = tester.getRect(find.byKey(waterFillKey));
      expect(fill.width / bar.width, closeTo(1.0, 0.001)); // 8×200/1600=100%
    },
  );

  testWidgets('①c 非今日：标题「喝水 · 1月1日」（:413 非今日支，dateLabelOf 复用）', (tester) async {
    await pumpCard(tester, newApi(water: 2), date: '2026-01-01');
    expect(find.text('喝水 · 1月1日'), findsOneWidget);
    expect(find.text('喝水打卡'), findsNothing);
  });

  /* ---------- ② 喝一杯（app.js:432-449） ---------- */

  testWidgets(
    '②喝一杯：gate 下乐观 +1 即显 800 并 toast「+200ml · 已喝 800ml」；回包 water=4 后仍 800；addWater(1,今日) 被调',
    (tester) async {
      final api = newApi(water: 3);
      await pumpCard(tester, api);
      final gate = Completer<void>();
      api.waterGate = gate;

      await tester.tap(find.byKey(waterCupKey));
      await tester.pump();
      expect(find.text('800'), findsOneWidget); // 乐观（:439-440 先渲染）
      expect(find.text('+200ml · 已喝 800ml'), findsOneWidget); // :441 逐字
      expect(api.waterBodies, [
        (delta: 1, date: todayIso()),
      ]); // :443 date=当前页 date

      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('800'), findsOneWidget); // 跟回包 water=4（:444-445）
      expect(find.text('600'), findsNothing);
    },
  );

  testWidgets(
    '②b 顶格：water=8（1600ml≥goal1600）再点 → toast「目标 1600ml 已达成，明天继续」且零请求、显示不动',
    (tester) async {
      final api = newApi(water: 8);
      await pumpCard(tester, api);

      await tester.tap(find.byKey(waterCupKey));
      await tester.pumpAndSettle();
      expect(find.text('目标 1600ml 已达成，明天继续'), findsOneWidget); // :434 逐字
      expect(api.waterBodies, isEmpty); // :435 return，零请求
      expect(find.text('1600'), findsWidgets); // 仍 8 杯
      expect(find.text('目标已达成 🎉'), findsOneWidget);
    },
  );

  testWidgets(
    '②c 失败：addWaterError(boom) → 回滚 600 + toast「同步失败：boom」（:446-448）',
    (tester) async {
      final api = newApi(water: 3);
      api.addWaterError = ApiException('boom');
      await pumpCard(tester, api);

      await tester.tap(find.byKey(waterCupKey));
      await tester.pumpAndSettle();
      expect(find.text('同步失败：boom'), findsOneWidget); // :448 逐字族
      expect(find.text('600'), findsOneWidget); // 回滚（:447 prev）
      expect(find.text('800'), findsNothing);
    },
  );

  /* ---------- ③ 撤销（app.js:452-467） ---------- */

  testWidgets(
    '③撤销：点撤销 → addWater(-1,今日)、乐观 2 杯 toast「已退回一杯 · 剩 400ml」；回包 water=2 为准',
    (tester) async {
      final api = newApi(water: 3);
      api.waterCupsByDate = {todayIso(): 3};
      final gate = Completer<void>();
      api.waterGate = gate;

      await pumpCard(tester, api);
      await tester.tap(find.byKey(waterUndoKey));
      await tester.pump();
      expect(find.text('400'), findsOneWidget); // 乐观 -1（:456-457）
      expect(find.text('已退回一杯 · 剩 400ml'), findsOneWidget); // :458 逐字（乐观值口径）

      gate.complete();
      await tester.pumpAndSettle();
      expect(api.waterBodies, [
        (delta: -1, date: todayIso()),
      ]); // :460 addWater(-1)
      expect(find.text('400'), findsOneWidget); // 以回包 water 为准（:461-462）
    },
  );

  testWidgets('③b 撤销失败：回滚 600 + toast「同步失败：boom」（:463-465 同支）', (tester) async {
    final api = newApi(water: 3);
    api.addWaterError = ApiException('boom');
    await pumpCard(tester, api);

    await tester.tap(find.byKey(waterUndoKey));
    await tester.pumpAndSettle();
    expect(find.text('同步失败：boom'), findsOneWidget);
    expect(find.text('600'), findsOneWidget);
    expect(find.text('400'), findsNothing);
  });

  /* ---------- ④ 目标 goal-sheet（app.js:470-493 + index.html:295-308） ---------- */

  Future<void> openSheet(WidgetTester tester, StubHealthApi api) async {
    await pumpCard(tester, api);
    await tester.tap(find.byKey(waterGoalEditKey));
    await tester.pumpAndSettle();
  }

  String fieldValue(WidgetTester tester) =>
      tester.widget<TextField>(find.byKey(goalValueKey)).controller!.text;

  testWidgets(
    '④开层预填 1600；＋ 一次 → 1800；连点到 3000 再点 → 值不动 + toast「最大 3000ml」（:476-482）',
    (tester) async {
      await openSheet(tester, newApi());
      expect(fieldValue(tester), '1600'); // :473 预填当前目标

      await tester.tap(find.byKey(goalIncKey));
      await tester.pump();
      expect(fieldValue(tester), '1800'); // +200 步进

      for (var i = 0; i < 6; i++) {
        // 1800→3000 共 6 步
        await tester.tap(find.byKey(goalIncKey));
        await tester.pump();
      }
      expect(fieldValue(tester), '3000');
      await tester.tap(find.byKey(goalIncKey));
      await tester.pump();
      expect(fieldValue(tester), '3000'); // 顶格值不动（:479 Math.min 后 next===cur）
      expect(find.text('最大 3000ml'), findsOneWidget); // :480 逐字
    },
  );

  testWidgets('④b − 到 800 再点 → toast「最小 800ml」（:480 低边界）', (tester) async {
    await openSheet(tester, newApi());
    for (var i = 0; i < 4; i++) {
      // 1600→800 共 4 步
      await tester.tap(find.byKey(goalDecKey));
      await tester.pump();
    }
    expect(fieldValue(tester), '800');
    await tester.tap(find.byKey(goalDecKey));
    await tester.pump();
    expect(fieldValue(tester), '800');
    expect(find.text('最小 800ml'), findsOneWidget);
  });

  testWidgets(
    '④c 保存：输入 2000 → setWaterGoal(2000)、toast「喝水目标已设为 2000ml」、关层、invalidate profileProvider → goal 行「目标 2000 ml」',
    (tester) async {
      final api = newApi(water: 3);
      await openSheet(tester, api);
      await tester.enterText(find.byKey(goalValueKey), '2000');
      await tester.tap(find.byKey(goalSaveKey));
      await tester.pumpAndSettle();

      expect(api.waterGoalBodies, [
        2000,
      ]); // :487 PUT /user/water-goal {waterGoalMl}
      expect(find.text('喝水目标已设为 2000ml'), findsOneWidget); // :492 逐字
      expect(find.byKey(goalValueKey), findsNothing); // 关层（:490 closeSheet）
      expect(
        find.textContaining('目标 2000 ml'),
        findsOneWidget,
      ); // profile 回写+invalidate（:491）
      expect(find.text('已喝 3 杯 · 每杯 200ml'), findsOneWidget); // 600/2000 未达成
    },
  );

  /* ---------- M6-T7 评审结转钉（F1/F2/F3） ---------- */

  testWidgets(
    '④d F2 归一 parseFloat 前缀语义：输入「1600.」保存 → setWaterGoal(1600)、'
    'toast「喝水目标已设为 1600ml」（H5 parseFloat("1600.")=1600；原 '
    'num.tryParse=null→NaN→800 分歧已闭合，js_compat.jsParseFloat）',
    (tester) async {
      final api = newApi(water: 3);
      await openSheet(tester, api);
      await tester.enterText(find.byKey(goalValueKey), '1600.');
      await tester.tap(find.byKey(goalSaveKey));
      await tester.pumpAndSettle();
      expect(api.waterGoalBodies, [
        1600,
      ]); // ≙ H5 norm 后 value=1600 → Number=1600
      expect(find.text('喝水目标已设为 1600ml'), findsOneWidget);
    },
  );

  testWidgets(
    '④e F1 mounted 守卫：setWaterGoal 在途（gate 挂住）✕ 关层，回包错误后 '
    'catch 支不再触碰已销毁 context（修复前 Overlay.of(deactivated) 抛未处理'
    '异步错 → 本用例红）',
    (tester) async {
      final api = newApi();
      api.setWaterGoalError = ApiException('boom');
      api.setWaterGoalGate = Completer<void>();
      await openSheet(tester, api);
      await tester.tap(find.byKey(goalSaveKey));
      await tester.pump(); // 在途：await setWaterGoalGate
      expect(find.text('同步失败：boom'), findsNothing);
      await tester.tap(find.byKey(goalCloseKey)); // 在途关层
      await tester.pumpAndSettle();
      expect(find.byKey(goalValueKey), findsNothing);
      api.setWaterGoalGate!.complete(); // 错误此刻才落——守卫应静默吞掉
      await tester.pumpAndSettle();
      expect(find.text('同步失败：boom'), findsNothing); // 层已销毁，无 toast
    },
  );

  testWidgets(
    '①c F3 ||1600 falsy 口径：profile.goal.waterMl=0 → 目标行「目标 1600 ml」，'
    '0 杯仍可喝一杯（≙ app.js:1948 falsy 支；修复前 goal=0 → 顶格闸恒触发）',
    (tester) async {
      final p = StubHealthApi.profileMap();
      final goal = Map<String, dynamic>.of(
        (p['goal'] as Map).cast<String, dynamic>(),
      );
      goal['waterMl'] = 0;
      p['goal'] = goal;
      final api = StubHealthApi(
        summary: StubHealthApi.summaryMap(water: 0),
        profile: p,
      );
      await pumpCard(tester, api);
      expect(
        find.textContaining('目标 1600 ml'),
        findsOneWidget,
      ); // ||1600 落 1600 档
      expect(find.text('目标已达成 🎉'), findsNothing); // 闸不恒触发（0≥0 支死）
      await tester.tap(find.byKey(waterCupKey));
      await tester.pumpAndSettle();
      expect(api.waterBodies, [
        (delta: 1, date: todayIso()),
      ]); // 喝一杯真发请求
      expect(find.text('200'), findsOneWidget);
    },
  );

  /* ---------- 桩云语义锁（评审遗留：0 值 ≙ Number(x)||1600 → 1600） ---------- */

  test('桩 setWaterGoal：0→1600（Number(x)||1600 falsy 支）、-10→800、5000→3000（截断支，index.js:257）', () async {
    final api = newApi();
    expect(await api.setWaterGoal(0), containsPair('waterGoalMl', 1600));
    expect(await api.setWaterGoal(-10), containsPair('waterGoalMl', 800));
    expect(await api.setWaterGoal(5000), containsPair('waterGoalMl', 3000));
    expect(await api.setWaterGoal(2000), containsPair('waterGoalMl', 2000));
  });

  testWidgets(
    '④f 终审 I1 步进链 Number 全串语义：输入「1600.」点加 → 1800'
    '（H5 :478 Number("1600.")=1600 +200；原 num.tryParse=null→0→200→clamp '
    '800 分岔。失焦归一先行时两版同值，本钉锁 _bump 自身口径）',
    (tester) async {
      final api = newApi(water: 3);
      await openSheet(tester, api);
      await tester.enterText(find.byKey(goalValueKey), '1600.');
      await tester.pump();
      await tester.tap(find.byKey(goalIncKey));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byKey(goalValueKey)).controller!.text,
        '1800',
      );
      expect(find.text('最大 3000ml'), findsNothing); // 非顶格无 toast
    },
  );
}
