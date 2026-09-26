// ShiguangFlutter/test/body_profile_card_test.dart
// M5 Task 6：「我的」页身体参数卡——六值展示 + 代谢明细 + 编辑弹层 + 保存链。
// 行为权威源 H5（文案逐字）：
// - js/app.js renderBodyCard(:1571-1579)：身高 `${heightCm} cm`、体重
//   `${weightKg} kg`、BMI Number(bmi).toFixed(1)、年龄 `${age} 岁`、
//   性别 male?男:女、活动量 ACTIVITY[activity]||light 的 label。
// - renderMetab(:1581-1609)：tw=profileData.goal.targetWeight；BMR/TDEE/建议
//   摄入/缺口四数 + 公式注记（`10×W+6.25×H−5×A−161`、`BMR×系数f`、
//   `消耗tdee−缺口realDeficit`、`预设缺口 realDeficit`）+ 标题右 note
//   `基准目标 suggest kcal` + etaText/rangeText 原文。
//   **降级登记**：H5 传 state.actualDeficit（localStorage 近 7 天实际缺口），
//   Flutter 本任务传 null=预设缺口口径（M6 若做实际缺口再补）。
// - openBodySheet/bumpBodyVal/bindStepperNorm(:1612-1666)：身高 ±1 闸 100-250、
//   体重 ±0.5 闸 30-200（bump 定 1 位小数 :1663-1664、norm 定 2 位 :1650）、
//   年龄 ±1 闸 10-100；bump 钳制后不变 → toast「已到上限/已到下限」(:1633 逐字，
//   与体重卡 T8 已落同款逻辑就地同实现)。
// - body-save(:1680-1703)：收集六字段 + bmi=+(w/(h/100)^2).toFixed(1) →
//   先关弹层再 await；updateProfile(b) → syncTarget(:1706-1718，suggest≠
//   goal.dailyKcal 才 PUT /user/goal {dailyKcal,targetWeight}，targetWeight
//   缺省回落当前体重) → toast「身体档案已保存」；catch → 「已本地保存：
//   + (e.message||'网络异常')」(:1701 逐字)。
// 主题债（T5 评审点名）：真主题 shiguangTheme() 必挂——FilledButton
// minimumSize 宽=∞ 在 Row 非 flex 位会整块不渲染，默认主题会漏检。
// 装配样板：抄 test/profile_head_test.dart 的 headContainer（全桩零网络）。
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiguang_flutter/app/auth_state.dart' show tokenStoreProvider;
import 'package:shiguang_flutter/app/theme.dart' show shiguangTheme;
import 'package:shiguang_flutter/data/api_client.dart' show ApiException;
import 'package:shiguang_flutter/data/token_store.dart';
import 'package:shiguang_flutter/domain/dates.dart' show localIso, todayIso;
import 'package:shiguang_flutter/domain/js_compat.dart' show jsFixed1;
import 'package:shiguang_flutter/domain/metabolism.dart' show computeMetabolism;
import 'package:shiguang_flutter/domain/models.dart' show Body;
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider;
import 'package:shiguang_flutter/features/notifications/reminder_scheduler.dart'
    show reminderSchedulerProvider;
import 'package:shiguang_flutter/features/profile/body_profile_card.dart'
    show
        bodyAgeValKey,
        bodyHeightIncKey,
        bodyHeightValKey,
        bodySaveKey,
        bodyWeightIncKey,
        bodyWeightValKey,
        goalEditEntryKey;
import 'package:shiguang_flutter/features/profile/goal_edit_sheet.dart'
    show goalEditValueKey;
import 'package:shiguang_flutter/features/profile/profile_screen.dart'
    show ProfileScreen;
import 'package:shiguang_flutter/features/scale/scale_service.dart';

import 'harness.dart';
import 'scale_fakes.dart';
import 'stubs/stub_health_api.dart';

/// 简报桩资料：body{168,66.66,30,female,moderate,500} + goal{1679,55}
/// （1679 恰为该 body 的 suggest → ④「无变化不重发 goal」天然成立）
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

StubHealthApi newApi() => StubHealthApi(
      bodyMetrics: const <String, dynamic>{'weightKg': 66.66},
      profile: xiaomanProfile(),
    );

Future<ProviderContainer> pumpProfile(WidgetTester tester, StubHealthApi api) async {
  await useBigSurface(tester);
  final container = ProviderContainer(
    overrides: [
      healthApiProvider.overrideWithValue(api),
      tokenStoreProvider.overrideWithValue(InMemoryTokenStore()),
      scaleServiceProvider.overrideWithValue(ScaleService(
        FakeTransport(),
        scanTimeout: const Duration(milliseconds: 300),
        readTimeout: const Duration(milliseconds: 1500),
      )),
      reminderSchedulerProvider.overrideWithValue(NoopReminderScheduler()),
    ],
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: shiguangTheme(), home: const ProfileScreen()),
  ));
  await tester.pumpAndSettle();
  return container;
}

/// 清掉上一用例残留的 SnackBar，防 toast 断言互污（同 profile_head_test 口径）
Future<void> clearSnacks(WidgetTester tester) async {
  tester
      .state<ScaffoldMessengerState>(find.byType(ScaffoldMessenger))
      .clearSnackBars();
  await tester.pumpAndSettle();
}

/// 开弹层（≙ #body-card click → openBodySheet :1658/:1612）
Future<void> openSheet(WidgetTester tester) async {
  await tester.tap(find.text('点击编辑 ›'));
  await tester.pumpAndSettle();
}

/// 弹层「保存档案」（≙ #body-save :1680）——长表单可滚动，先 ensureVisible
Future<void> tapSave(WidgetTester tester) async {
  await tester.ensureVisible(find.byKey(bodySaveKey));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(bodySaveKey));
  await tester.pumpAndSettle();
}

void main() {
  /* ---------- ① 卡面六值（renderBodyCard :1571-1579） ---------- */

  testWidgets('①六值：168 cm / 66.66 kg / BMI 23.6 / 30 岁 / 女 / 中度',
      (tester) async {
    await pumpProfile(tester, newApi());

    expect(find.textContaining('168 cm'), findsOneWidget); // :1573
    expect(find.textContaining('66.66 kg'), findsWidgets); // :1574（体重卡「当前体重」同值同屏，故 findsWidgets）
    expect(find.textContaining('23.6'), findsWidgets); // :1575 Number(bmi).toFixed(1)（弹层未开，仅卡面）
    expect(find.textContaining('30 岁'), findsOneWidget); // :1576
    expect(find.text('女'), findsOneWidget); // :1577
    expect(find.text('中度'), findsOneWidget); // :1578 ACTIVITY[moderate].label
  });

  /* ---------- ② 代谢区（renderMetab :1581-1609，actualInfo=null 口径） ---------- */

  testWidgets('②代谢：BMR/TDEE/建议摄入三数与纯 Dart computeMetabolism 直比；缺口行标「预设缺口」',
      (tester) async {
    await pumpProfile(tester, newApi());

    final m = computeMetabolism(
        Body.fromMap(<String, Object?>{
          'heightCm': 168, 'weightKg': 66.66, 'age': 30,
          'gender': 'female', 'activity': 'moderate', 'deficit': 500,
        }),
        55, // goal.targetWeight
        null); // 降级：预设缺口口径
    // 纯 Dart 期望值直比（锁死移植公式：1406/2179/1679）
    expect(m.bmr, 1406);
    expect(m.tdee, 2179);
    expect(m.suggest, 1679);

    expect(find.textContaining('1406 kcal'), findsWidgets); // metab-bmr
    expect(find.textContaining('2179 kcal'), findsOneWidget); // metab-tdee
    expect(find.textContaining('1679 kcal'), findsWidgets); // metab-suggest
    expect(find.text('预设缺口 500'), findsOneWidget); // :1601 非 useActual 支（降级标注；精确匹配防 etaText 内含同串）
    expect(find.textContaining('基准目标 1679 kcal'), findsOneWidget); // :1605 note
    expect(
        find.textContaining('10×66.66+6.25×168−5×30−161'), findsOneWidget); // :1598 公式逐字
    expect(find.textContaining('BMR×系数1.55'), findsOneWidget); // :1599 ex=0 支
    expect(find.textContaining('消耗2179−缺口500'), findsOneWidget); // :1600 ex=0 支
    expect(find.textContaining(m.etaText), findsOneWidget); // etaText 原文
    expect(find.textContaining('按预设缺口 500 kcal 估算'), findsOneWidget); // :metabolism eta 预设支片段（eta 含当日日期，取稳定段）
    expect(find.textContaining(m.rangeText), findsOneWidget); // rangeText 原文
  });

  /* ---------- ③ 保存链：updateProfile → setGoal 联动（body-save :1680-1703 + syncTarget :1706-1718） ---------- */

  testWidgets('③弹层改身高 168→170→保存：PUT /user/profile 六字段+bmi；第二发 PUT /user/goal {suggest:1698,targetWeight:55}；profileProvider 重取+1；toast「身体档案已保存」；卡面刷新 170',
      (tester) async {
    final api = newApi();
    await pumpProfile(tester, api);
    final getBefore = api.profileCalls; // 首屏 1 次

    await openSheet(tester);
    // 弹层预填 = 当前档案（openBodySheet :1614-1616）
    expect(
        tester.widget<TextField>(find.byKey(bodyHeightValKey)).controller!.text,
        '168');
    expect(
        tester.widget<TextField>(find.byKey(bodyWeightValKey)).controller!.text,
        '66.66');
    expect(
        tester.widget<TextField>(find.byKey(bodyAgeValKey)).controller!.text,
        '30');
    // 六组控件在场：身高/体重/年龄 stepper + 性别 + 活动量 + 缺口
    for (final t in ['女', '男', '久坐', '轻度', '中度', '重度', '极大', '温和 300', '标准 500', '积极 750']) {
      expect(find.text(t), findsWidgets, reason: '弹层缺控件 $t');
    }

    await tester.tap(find.byKey(bodyHeightIncKey)); // ＋1 ×2 → 170
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(bodyHeightIncKey));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byKey(bodyHeightValKey)).controller!.text,
        '170');

    await tapSave(tester);

    // 第一发 PUT /user/profile：六字段 + bmi（bmi=+(66.66/(170/100)^2).toFixed(1)=23.1）
    expect(api.profileUpdateBodies, hasLength(1));
    expect(api.profileUpdateBodies.single, <String, dynamic>{
      'heightCm': 170,
      'weightKg': 66.66,
      'age': 30,
      'gender': 'female',
      'activity': 'moderate',
      'deficit': 500,
      'bmi': jsFixed1(66.66 / math.pow(170 / 100, 2)), // 23.1（弹层收集时算，简报裁定）
    });
    // 第二发 PUT /user/goal：suggest=重算值≠1679 → 联动首页目标
    final suggest = computeMetabolism(
        Body.fromMap(<String, Object?>{
          'heightCm': 170, 'weightKg': 66.66, 'age': 30,
          'gender': 'female', 'activity': 'moderate', 'deficit': 500,
        }),
        55,
        null);
    expect(suggest.suggest, 1698); // 10×66.66+6.25×170−150−161→1418；×1.55→2198；−500→1698
    expect(api.goalBodies, hasLength(1));
    expect(api.goalBodies.single['dailyKcal'], suggest.suggest);
    expect(api.goalBodies.single['targetWeight'], 55);
    // profileProvider 重取恰 +1（invalidate ≙ 重取回真值）
    expect(api.profileCalls, getBefore + 1);
    // toast 逐字（:1699）；弹层已关；卡面刷新
    expect(find.text('身体档案已保存'), findsOneWidget);
    expect(find.byKey(bodySaveKey), findsNothing);
    expect(find.textContaining('170 cm'), findsOneWidget);
  });

  /* ---------- ④ 无变化不重发 goal（syncTarget :1610 `if (target === suggest) return`） ---------- */

  testWidgets('④原值保存：suggest(1679)==goal.dailyKcal → 仅 1 发 PUT /user/profile，0 发 goal，仍 toast 成功',
      (tester) async {
    final api = newApi();
    await pumpProfile(tester, api);

    await openSheet(tester);
    await tapSave(tester);

    expect(api.profileUpdateBodies, hasLength(1));
    expect(api.goalCalls, 0); // 无变化不重发
    expect(find.text('身体档案已保存'), findsOneWidget);
  });

  /* ---------- ⑤ 失败链（body-save :1700-1702） ---------- */

  testWidgets('⑤PUT /user/profile 失败(500,x)：toast「已本地保存：x」逐字；不发 setGoal；invalidate 仍发生（重取回真值 168）',
      (tester) async {
    final api = newApi()..profileUpdateError = ApiException('x'); // status 500 message「x」的业务面等价
    await pumpProfile(tester, api);
    final getBefore = api.profileCalls;

    await openSheet(tester);
    await tester.tap(find.byKey(bodyHeightIncKey));
    await tester.pumpAndSettle();
    await tapSave(tester);

    expect(find.text('已本地保存：x'), findsOneWidget); // :1701 逐字
    expect(api.goalCalls, 0); // 失败链不发 goal
    expect(api.profileCalls, getBefore + 1); // finally invalidate 仍重取
    expect(find.textContaining('168 cm'), findsOneWidget); // 云端未变 → 回真值
    expect(find.byKey(bodySaveKey), findsNothing); // H5 先关层再 await：失败也已关
  });

  testWidgets('⑤b ApiException.message 空串 → falsy 兜底「已本地保存：网络异常」（H5 e.message||网络异常）',
      (tester) async {
    final api = newApi()..profileUpdateError = ApiException('');
    await pumpProfile(tester, api);

    await openSheet(tester);
    await tapSave(tester);

    expect(find.text('已本地保存：网络异常'), findsOneWidget);
  });

  /* ---------- ⑦ M7-T5 收口钉：双 try 失败分流（spec §4.3，M5 旧账） ---------- */

  testWidgets('⑦updateProfile 成功 + setGoal 抛错(boom)：toast「目标同步失败：boom」，非「已本地保存/身体档案已保存」；invalidate 仍发生',
      (tester) async {
    final api = newApi()..setGoalError = ApiException('boom'); // profile 支正常
    await pumpProfile(tester, api);
    final getBefore = api.profileCalls;

    await openSheet(tester);
    await tester.tap(find.byKey(bodyHeightIncKey)); // 168→169 → suggest≠1679 → setGoal 发
    await tester.pumpAndSettle();
    await tapSave(tester);

    expect(api.profileUpdateBodies, hasLength(1)); // 资料确实已存成功
    expect(api.goalCalls, 1); // 第二发确实打了 goal
    expect(find.text('目标同步失败：boom'), findsOneWidget); // 新支逐字
    expect(find.textContaining('已本地保存'), findsNothing); // 不再冒充资料失败
    expect(find.text('身体档案已保存'), findsNothing);
    expect(api.profileCalls, getBefore + 1); // 无论成败 invalidate 仍发生
  });

  testWidgets('⑦b setGoal 空 message → 「目标同步失败：网络异常」（同族 jsOr 兜底）',
      (tester) async {
    final api = newApi()..setGoalError = ApiException('');
    await pumpProfile(tester, api);

    await openSheet(tester);
    await tester.tap(find.byKey(bodyHeightIncKey));
    await tester.pumpAndSettle();
    await tapSave(tester);

    expect(find.text('目标同步失败：网络异常'), findsOneWidget);
  });

  /* ---------- ⑥ 步进器边界闸（bumpBodyVal :1627-1634 逐字 toast） ---------- */

  testWidgets('⑥身高顶到 250 再点＋→「已到上限」不动；年龄 10 点−→「已到下限」；体重 200 点＋→「已到上限」（±0.5 定 1 位小数）',
      (tester) async {
    await pumpProfile(tester, newApi());
    await openSheet(tester);

    await tester.enterText(find.byKey(bodyHeightValKey), '250');
    await tester.tap(find.byKey(bodyHeightIncKey));
    await tester.pumpAndSettle();
    expect(find.text('已到上限'), findsOneWidget); // :1633 逐字
    expect(
        tester.widget<TextField>(find.byKey(bodyHeightValKey)).controller!.text,
        '250'); // 顶格不动
    await clearSnacks(tester);

    await tester.enterText(find.byKey(bodyAgeValKey), '10');
    await tester.tap(find.byKey(const Key('age-dec')));
    await tester.pumpAndSettle();
    expect(find.text('已到下限'), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byKey(bodyAgeValKey)).controller!.text,
        '10');
    await clearSnacks(tester);

    // 体重 bump ±0.5 定 1 位小数（:1663-1664）：66.66 → ＋ → 67.2
    await tester.tap(find.byKey(bodyWeightIncKey));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TextField>(find.byKey(bodyWeightValKey)).controller!.text,
        '67.2'); // +(66.66+0.5).toFixed(1)
    await tester.enterText(find.byKey(bodyWeightValKey), '200');
    await tester.tap(find.byKey(bodyWeightIncKey));
    await tester.pumpAndSettle();
    expect(find.text('已到上限'), findsOneWidget);
    expect(
        tester.widget<TextField>(find.byKey(bodyWeightValKey)).controller!.text,
        '200');
  });

  /* ---------- ⑧ M7-T5 代谢卡目标体重行入口（≙ #btn-edit-goal） ---------- */

  testWidgets('⑧代谢卡「目标体重」行：点「点击修改」开目标弹层（预填 55），不触发整卡身体档案 GestureDetector',
      (tester) async {
    await pumpProfile(tester, newApi()); // goal.targetWeight=55

    expect(find.text('目标体重'), findsOneWidget); // 行 label（≙ goal-banner :196）
    expect(find.text('点击修改 ›'), findsOneWidget); // 入口文案（spec §4.3）

    await tester.tap(find.byKey(goalEditEntryKey));
    await tester.pumpAndSettle();

    expect(find.byKey(goalEditValueKey), findsOneWidget); // 目标弹层已开
    expect(
        tester.widget<TextField>(find.byKey(goalEditValueKey)).controller!.text,
        '55'); // 预填 ≙ :1429
    expect(find.byKey(bodySaveKey), findsNothing); // 整卡开层手势未被误触
  });

  /* ---------- ⑨ M7-T7 实际缺口消费点（renderMetab :1601/:1604 useActual 支） ---------- */

  testWidgets('⑨近2天有记录：缺口行值=实际均值、注记「近2天均值(消耗−摄入)」逐字、note「缺口为近 2 天实际日均 · 预设 500」逐字、eta 实际支',
      (tester) async {
    SharedPreferences.setMockInitialValues({}); // 真 PrefsActualDeficitStore 落 mock，不落平台通道
    final api = newApi();
    // 昨/前日两条有效记录（其余日 kcal=0 不入 rows；今日 0 不并入）
    api.summaryByDate = <String, Map<String, dynamic>>{
      _back(1): StubHealthApi.summaryMap(kcal: 1800),
      _back(2): StubHealthApi.summaryMap(kcal: 2000),
    };
    api.exercisesByDate = <String, List<Map<String, dynamic>>>{
      _back(1): <Map<String, dynamic>>[
        {'kcal': 200},
      ],
    };
    await pumpProfile(tester, api);

    // tdee2179 → rows=[{1800,200},{2000,0}] → avg=(579+179)/2=379
    expect(find.text('379 kcal'), findsOneWidget); // 每日缺口值 effDeficit=avgDeficit
    expect(find.text('近2天均值(消耗−摄入)'), findsOneWidget); // :1601 useActual 支逐字
    expect(find.text('缺口为近 2 天实际日均 · 预设 500'), findsOneWidget); // :1604 逐字
    expect(find.text('预设缺口 500'), findsNothing); // 降级支已让位
    expect(find.textContaining('按近 2 天实际日均缺口 379 kcal 估算'),
        findsOneWidget); // computeMetabolism eta useActual 支
    // 历史六日双请求确实发出（消费点触发的拉取链）
    expect(
        api.summaryDates.where((d) => d != todayIso()).toList(), hasLength(6));
    expect(
        api.exerciseDates.where((d) => d != todayIso()).toList(), hasLength(6));
  });

  testWidgets('⑩prefs 当日缓存命中：代谢卡出实际缺口态且零历史请求（先显缓存值 ≙ 缓存语义）',
      (tester) async {
    final cached = <String, Object?>{
      'date': todayIso(),
      'tdee': 2179,
      'history': <Object?>[
        {'date': _back(1), 'intake': 1800, 'exKcal': 200},
        {'date': _back(2), 'intake': 2000, 'exKcal': 0},
      ],
    };
    SharedPreferences.setMockInitialValues({
      'sg_actual_deficit_u_test': jsonEncode(cached), // 键名逐字 ≙ H5 :1511
    });
    final api = newApi();
    await pumpProfile(tester, api);

    expect(find.text('379 kcal'), findsOneWidget);
    expect(find.text('近2天均值(消耗−摄入)'), findsOneWidget);
    // 零历史请求：summary/exercise 仅今日 watch 各 1 次
    expect(api.summaryDates.where((d) => d != todayIso()), isEmpty);
    expect(api.exerciseDates.where((d) => d != todayIso()), isEmpty);
  });
}

/// 昨起回退 i 天（真实时钟锚，≙ app.js:1526 setDate 日历日减一）
String _back(int i) {
  final n = DateTime.now();
  return localIso(DateTime(n.year, n.month, n.day - i));
}
