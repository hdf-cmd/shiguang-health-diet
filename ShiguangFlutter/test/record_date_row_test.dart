// ShiguangFlutter/test/record_date_row_test.dart
// M7 Task 6：记录页顶部 7 天日期行 + 与首页共享 plateDateProvider。
// 行为权威源 js/app.js renderDateRow（:498-516 一带，行号以实读为准）：
// - 7 chip = 今天往前 7 天（i=0..6 → 今-6..今，:501-503）；
// - 文案：末位（i==6）「今天」，其余「M/D」（:506 `${d.getMonth()+1}/${d.getDate()}`，
//   不补零、非 dateLabelOf 的「M月D日」——实读确认）；
// - 点击置全局 state.date（:512）并刷新（:515 并行拉取）——Flutter 侧 = 写
//   plateDateProvider（T1 共享日期源），recordsProvider(date) family 随 watch 重取；
// - 无未来闸（行内本无未来日，:510-512 不判）；选中态 .chip.active 唯一（:505）。
// 共享日期回归钉（spec §7）：记录页选「3 天前」→ 同 container 切回首页 tab
// （PageView 不重建 ProviderScope）→ 餐盘胶囊停同一天（≙ H5 :514 renderPlateDate）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/shell.dart' show Shell, ShellState;
import 'package:shiguang_flutter/app/theme.dart' show Tokens, shiguangTheme;
import 'package:shiguang_flutter/domain/dates.dart' show localIso;
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider, plateDateProvider;
import 'package:shiguang_flutter/features/notifications/reminder_scheduler.dart'
    show reminderSchedulerProvider;
import 'package:shiguang_flutter/features/record/record_screen.dart'
    show RecordScreen;

import 'harness.dart' show NoopReminderScheduler, useBigSurface;
import 'stubs/stub_health_api.dart';

/// 与 domain/dates.dart 同口径的「N 天前」（日历日相减，非 24h 定长）
String isoDaysAgo(int n) {
  final now = DateTime.now();
  return localIso(DateTime(now.year, now.month, now.day - n));
}

DateTime _dt(String iso) => DateTime.parse('${iso}T00:00:00');

/// chip 文本：≙ app.js:506（末位「今天」，其余 M/D 不补零）
String chipLabel(int daysAgo) {
  if (daysAgo == 0) return '今天';
  final d = _dt(isoDaysAgo(daysAgo));
  return '${d.month}/${d.day}';
}

Key chipKey(int daysAgo) => ValueKey('date-chip-${isoDaysAgo(daysAgo)}');

StubHealthApi newApi() => StubHealthApi(
      records: <dynamic>[
        StubHealthApi.recordMap(
            id: 'rec_l_1', meal: 'lunch', name: '米饭', portion: '200g', kcal: 232),
      ],
      summary: StubHealthApi.summaryMap(kcal: 200, target: 1679),
      profile: StubHealthApi.profileMap(),
      exercisesByDate: <String, List<Map<String, dynamic>>>{},
    );

/// 单记录页（自带 container 供直读 plateDateProvider）
Future<(ProviderContainer, StubHealthApi)> pumpRecord(WidgetTester tester) async {
  final api = newApi();
  final container = ProviderContainer(
    overrides: [healthApiProvider.overrideWithValue(api)],
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: shiguangTheme(), // 工程纪律：widget 测试必挂真主题
      home: const RecordScreen(initialMeal: 'lunch'),
    ),
  ));
  await tester.pumpAndSettle();
  return (container, api);
}

/// Shell 四 tab（同 container，PageView 切 tab 不重建 ProviderScope）
Future<(ProviderContainer, StubHealthApi)> pumpShell(WidgetTester tester) async {
  await useBigSurface(tester);
  final api = newApi();
  final container = ProviderContainer(
    overrides: [
      healthApiProvider.overrideWithValue(api),
      reminderSchedulerProvider.overrideWithValue(NoopReminderScheduler()),
    ],
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: shiguangTheme(), home: const Shell()),
  ));
  await tester.pumpAndSettle();
  return (container, api);
}

/// 选中态高亮 chip 的 iso 列表（≙ .chip.active 唯一性检查）：
/// 逐 chip 读 AnimatedContainer 装饰色，primary=选中。
List<String> activeChips(WidgetTester tester) {
  final actives = <String>[];
  for (var n = 6; n >= 0; n--) {
    final iso = isoDaysAgo(n);
    final c = tester.widget<AnimatedContainer>(find.byKey(chipKey(n)));
    final deco = c.decoration;
    if (deco is BoxDecoration && deco.color == Tokens.primary) actives.add(iso);
  }
  return actives;
}

void main() {
  /* ---------- ① 7 chip 渲染：日期序列 + 文案逐字 ---------- */

  testWidgets('①7 chip 在场：序列=今-6..今、末位「今天」逐字、其余「M/D」不补零（≙ app.js:501-506）',
      (tester) async {
    await pumpRecord(tester);

    expect(
      find.byWidgetPredicate((w) =>
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('date-chip-')),
      findsNWidgets(7),
    );
    for (var n = 6; n >= 0; n--) {
      expect(find.byKey(chipKey(n)), findsOneWidget, reason: '$n天前 chip 缺位');
    }
    // 文案逐字：末位「今天」；其余 M/D（月/日均不补零，实读 :506）
    expect(find.text('今天'), findsOneWidget);
    for (var n = 6; n >= 1; n--) {
      expect(find.text(chipLabel(n)), findsOneWidget, reason: '$n天前 chip 文案');
    }
    // 默认选中=今天（plateDateProvider 初值 todayIso，≙ H5 state.date=今天）
    expect(activeChips(tester), [isoDaysAgo(0)]);
  });

  /* ---------- ② 点第 3 个 chip：写共享日期源 + recordsProvider(date) 重取 ---------- */

  testWidgets('②点第 3 个 chip（=今-4）：plateDateProvider 落对应日期，recordsProvider 按新 date 重取',
      (tester) async {
    final (container, api) = await pumpRecord(tester);
    expect(api.recordDates, [isoDaysAgo(0)]); // 首屏取今天一次

    await tester.tap(find.byKey(chipKey(4))); // 左起第 3 个 = 今-4
    await tester.pumpAndSettle();

    expect(container.read(plateDateProvider), isoDaysAgo(4));
    expect(api.recordDates, [isoDaysAgo(0), isoDaysAgo(4)]); // ≙ :515 loadRecordPage
    expect(activeChips(tester), [isoDaysAgo(4)]); // 高亮跟过去
  });

  /* ---------- ③ 选中态高亮唯一 ---------- */

  testWidgets('③选中态高亮唯一：初态只有「今天」亮，点选后只有被点 chip 亮',
      (tester) async {
    await pumpRecord(tester);
    expect(activeChips(tester), hasLength(1));

    await tester.tap(find.byKey(chipKey(2)));
    await tester.pumpAndSettle();
    expect(activeChips(tester), [isoDaysAgo(2)]);

    // 再点末位「今天」：唯一性保持，且回到今天
    await tester.tap(find.byKey(chipKey(0)));
    await tester.pumpAndSettle();
    expect(activeChips(tester), [isoDaysAgo(0)]);
  });

  /* ---------- ④ 共享日期回归钉（spec §7）：记录页选日 → 首页餐盘停同一天 ---------- */

  testWidgets('④同 container 跨 tab：记录页选「3 天前」→ 切回首页 → 餐盘胶囊「M月D日 周X」同天',
      (tester) async {
    final (container, api) = await pumpShell(tester);

    // 首页 → 记录 tab（ShellState.goToTab，≙ H5 swiper 切屏，ProviderScope 不重建）
    tester.state<ShellState>(find.byType(Shell)).goToTab(1);
    await tester.pumpAndSettle();
    expect(find.text('饮食记录'), findsOneWidget);

    await tester.tap(find.byKey(chipKey(3))); // 记录页选 3 天前
    await tester.pumpAndSettle();
    expect(container.read(plateDateProvider), isoDaysAgo(3));
    expect(api.recordDates.last, isoDaysAgo(3));

    // 切回首页：餐盘日期胶囊停在同一日（≙ :514 renderPlateDate 同 state.date）
    tester.state<ShellState>(find.byType(Shell)).goToTab(0);
    await tester.pumpAndSettle();

    final d = _dt(isoDaysAgo(3));
    const weeks = ['日', '一', '二', '三', '四', '五', '六'];
    expect(find.byKey(const ValueKey('plate-date')), findsOneWidget);
    expect(find.text('${d.month}月${d.day}日'), findsOneWidget); // 非今昨支主文案
    expect(find.text('周${weeks[d.weekday % 7]}'), findsOneWidget); // 副文案 周X
    expect(api.summaryDates.last, isoDaysAgo(3)); // 首页五卡同天重取
    expect(container.read(plateDateProvider), isoDaysAgo(3)); // 未复位
  });

  /* ---------- ⑤ 日期行不影响既有记录链路：切日后「＋ 记一笔」body date=所选日 ---------- */

  testWidgets('⑤切到 3 天前再「＋ 记一笔」→ 添加：addFoodRecord body.date=所选日（列表随日切换的数据面）',
      (tester) async {
    final (container, api) = await pumpRecord(tester);
    api.foods = <dynamic>[
      <String, dynamic>{
        'id': 'u_egg',
        'name': '鸡蛋',
        'meta': '禽蛋 · 1 个约 50g',
        'kcal': 72,
        'emoji': '🥚',
        'image': '',
        'meals': ['lunch'],
        'protein': 7,
        'carb': 1,
        'fat': 5,
      },
    ];

    await tester.tap(find.byKey(chipKey(3)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('＋ 记一笔'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '搜索食物库'), '鸡');
    await tester.pump(const Duration(milliseconds: 250)); // H5 200ms 防抖
    await tester.pumpAndSettle();

    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();
    expect(api.addBodies.single['date'], container.read(plateDateProvider));
    expect(api.addBodies.single['date'], isoDaysAgo(3));
  });
}
