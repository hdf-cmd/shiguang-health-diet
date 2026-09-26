// ShiguangFlutter/test/home_plate_date_test.dart
// M7 Task 1：首页日期状态机（plateDateProvider）+ 餐盘卡 plate-head ‹ › 导航 + 问候头。
// 行为权威源 H5（文案逐字）：
// - js/app.js:201-214 renderPlateDate —— 胶囊三态：
//   今天 → `今天<small>· 右滑看历史</small>`；昨天 → `昨天<small>M/D</small>`；
//   其余 → `M月D日<small>周X</small>`（weeks=['日','一','二','三','四','五','六']
//   按 JS getDay 下标，Dart weekday%7 同序）；`date==今天` 时 #plate-next
//   style.visibility='hidden'（保位不可点，≙ :213）。‹ #plate-prev 恒在（:225）。
// - js/app.js:215-224 shiftDate(delta) —— `next > todayIso()` → toast
//   「已经到今天了」并 return（零状态变更、零请求）；否则改 state.date 后重渲染
//   +并行拉取（Flutter 侧各 family provider 随 watch 自动重取，见 home_screen 注）。
// - js/app.js:287-294 renderGreeting(nickname) —— 五档问候 + `nickname ?
//   「{greet}，{nickname}」`（全角逗号逐字），下挂 `M月D日 · 星期X`；
//   **恒用系统时钟**（不随 ‹ › 变，≙ H5 仅在 loadMainBundle 调用一次）。
// 未来闸的 UI 可达性：› 在 date==今天 时按 H5 :213 保位隐藏（不可点），故
// 「已在今天再点 ›」的 toast 只能直调 shiftPlateDate 验（H5 同款：该文案经
// 卡内滑动通道触达，本任务不移植手势——见 task-1-report 差异登记）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/theme.dart' show shiguangTheme;
import 'package:shiguang_flutter/data/api_client.dart' show ApiException;
import 'package:shiguang_flutter/domain/dates.dart' show localIso;
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show
        healthApiProvider,
        plateDateLabelOf,
        plateDateProvider,
        shiftPlateDate;
import 'package:shiguang_flutter/features/home/home_screen.dart'
    show
        HomeScreen,
        greetingDateLineOf,
        greetingKey,
        greetingTextOf,
        plateDateKey,
        plateNextKey,
        platePrevKey;

import 'harness.dart' show useBigSurface;
import 'stubs/stub_health_api.dart';

const _weeks = ['日', '一', '二', '三', '四', '五', '六'];

/// 与 domain/dates.dart 同口径的「N 天前」（日历日相减，非 24h 定长）
String isoDaysAgo(int n) {
  final now = DateTime.now();
  return localIso(DateTime(now.year, now.month, now.day - n));
}

DateTime _dt(String iso) => DateTime.parse('${iso}T00:00:00');

/// 桩：summary/records 对任意日期同值（本文件只钉「请求带的 date」与文案态）
StubHealthApi newApi() => StubHealthApi(
      summary: StubHealthApi.summaryMap(
          kcal: 200, target: 1679, carb: 30, protein: 5, fat: 10, water: 1),
      records: <dynamic>[
        StubHealthApi.recordMap(
            id: 'r1', meal: 'breakfast', name: '鸡蛋', portion: '1 个', kcal: 200),
      ],
      profile: <String, dynamic>{
        ...StubHealthApi.profileMap(),
        'nickname': '小满',
      },
      exercisesByDate: <String, List<Map<String, dynamic>>>{},
    );

/// 借一个挂载中的 Consumer 把 WidgetRef 交给用例（未来闸直调需要）
class _RefProbe extends ConsumerWidget {
  const _RefProbe(this.handle);
  final RefHandle handle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    handle.ref = ref;
    return const SizedBox.shrink();
  }
}

class RefHandle {
  WidgetRef? ref;
}

/// 挂首页（生产语境 ≙ Shell Scaffold，toast 需 Scaffold 注册位），
/// 返回探针供用例直调 shiftPlateDate。
Future<RefHandle> pumpHome(WidgetTester tester, StubHealthApi api) async {
  await useBigSurface(tester);
  final handle = RefHandle();
  final container = ProviderContainer(
    overrides: [healthApiProvider.overrideWithValue(api)],
    retry: (_, _) => null, // 禁默认退避重试（home_screen_test 同法）
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: shiguangTheme(), // 工程纪律：widget 测试必挂真主题
      home: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(child: HomeScreen()),
            Positioned(
              left: 0,
              bottom: 0,
              child: _RefProbe(handle),
            ),
          ],
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return handle;
}

/// › / ‹ 的可见态（≙ H5 style.visibility）
bool nextVisible(WidgetTester tester) => tester
    .widget<Visibility>(find
        .ancestor(of: find.byKey(plateNextKey), matching: find.byType(Visibility)))
    .visible;

void main() {
  /* ---------- ① 初值=今天：三态文案「今天」支 + › 保位隐藏 ---------- */

  testWidgets('①初值今天：胶囊「今天」+小字「· 右滑看历史」逐字；‹ 恒在、› 保位隐藏',
      (tester) async {
    final api = newApi();
    await pumpHome(tester, api);

    expect(find.byKey(plateDateKey), findsOneWidget);
    expect(find.text('今天'), findsOneWidget); // 主文案
    expect(find.text('· 右滑看历史'), findsOneWidget); // small 小字逐字（含中点+空格）
    // 完整串形 ≙ H5 #plate-date.textContent（今天支）
    expect(plateDateLabelOf(isoDaysAgo(0)), '今天· 右滑看历史');
    // ‹ 恒在（index.html:72）
    expect(find.byKey(platePrevKey), findsOneWidget);
    // › 仍占格（visibility:hidden 语义：在树、保位、不可点）
    expect(find.byKey(plateNextKey), findsOneWidget);
    expect(nextVisible(tester), isFalse);
    expect(api.summaryDates, [isoDaysAgo(0)]); // 首屏只取今天
    // 版式次序（advice_card_test ④ 同法，相对断言不钉绝对卡高）：
    // 问候头 → plate-head（餐盘卡顶）→ 环/aside（ring-note 在卡底部）
    final greet = tester.getRect(find.byKey(greetingKey));
    final head = tester.getRect(find.byKey(plateDateKey));
    final ringNote = tester.getRect(find.byKey(const ValueKey('ring-note')));
    expect(greet.top, lessThan(head.top));
    expect(head.top, lessThan(ringNote.top));
  });

  /* ---------- ② 点 ‹ 一次：昨天态 + 各卡按 date 重新取数 ---------- */

  testWidgets('②点 ‹ 一次：胶囊「昨天」+小字 M/D；plateDateProvider 落昨天且五卡按新 date 重取',
      (tester) async {
    final api = newApi();
    final handle = await pumpHome(tester, api);

    await tester.tap(find.byKey(platePrevKey));
    await tester.pumpAndSettle();

    final y = isoDaysAgo(1);
    final yd = _dt(y);
    expect(find.text('昨天'), findsOneWidget);
    expect(find.text('${yd.month}/${yd.day}'), findsOneWidget); // 昨天支小字 = M/D
    expect(find.text('今天'), findsNothing);
    expect(handle.ref!.read(plateDateProvider), y);
    expect(nextVisible(tester), isTrue); // 非今天 → › 复现
    // 桩 date 序列：summary/records/exercises 均随新 date 重取（≙ :223 并行拉取）
    expect(api.summaryDates, [isoDaysAgo(0), y]);
    expect(api.recordDates, [isoDaysAgo(0), y]);
    expect(api.exerciseDates, [isoDaysAgo(0), y]);
  });

  /* ---------- ②b M7-T2 carried 收口：同一天回访必须重取（T1 头注登记债） ---------- */

  testWidgets('②b ‹ 昨天再 › 回今天：运动链对同一 date 重发请求（≙ H5 每次切日期 loadExercises :223，非缓存翻牌）',
      (tester) async {
    final api = newApi();
    await pumpHome(tester, api);
    expect(api.exerciseDates, [isoDaysAgo(0)]); // 首屏取今日一次

    await tester.tap(find.byKey(platePrevKey)); // → 昨天
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(plateNextKey)); // → 回今天（同一天回访）
    await tester.pumpAndSettle();

    // M6 keepAlive FutureProvider 在此为 [今天, 昨天]（回访吃缓存）——
    // M7-T2 exercisesProvider autoDispose 化收口：切走即弃，回访必重取。
    expect(api.exerciseDates, [isoDaysAgo(0), isoDaysAgo(1), isoDaysAgo(0)]);
  });

  /* ---------- ③ 点 › 回今天；已在今天 → 未来闸 toast 零变更零请求 ---------- */

  testWidgets('③› 回今天后再触发前移：toast「已经到今天了」逐字、日期不变、零请求',
      (tester) async {
    final api = newApi();
    final handle = await pumpHome(tester, api);

    await tester.tap(find.byKey(platePrevKey)); // → 昨天
    await tester.pumpAndSettle();
    expect(find.text('昨天'), findsOneWidget);

    await tester.tap(find.byKey(plateNextKey)); // → 今天
    await tester.pumpAndSettle();
    expect(find.text('今天'), findsOneWidget);
    expect(nextVisible(tester), isFalse);
    final datesBefore = List<String>.of(api.summaryDates);
    final callsBefore = api.summaryCalls + api.recordsCalls + api.exerciseCalls;

    // 已在今天：› 按 H5 :213 保位隐藏不可点，故直调同一函数验未来闸（见头注）
    final toasts = <String>[];
    await shiftPlateDate(handle.ref!, 1, toasts.add);
    await tester.pumpAndSettle();

    expect(toasts, ['已经到今天了']); // app.js:219 逐字
    expect(handle.ref!.read(plateDateProvider), isoDaysAgo(0)); // 零状态变更
    expect(api.summaryDates, datesBefore); // 零请求
    expect(
      api.summaryCalls + api.recordsCalls + api.exerciseCalls,
      callsBefore,
    );
    expect(find.text('昨天'), findsNothing);
  });

  /* ---------- ④ 往前 8 天：M月D日 + 周X（weeks 表逐字） ---------- */

  testWidgets('④往前 8 天：胶囊「M月D日」+小字「周X」（weeks 表逐字），‹ 无下限',
      (tester) async {
    final api = newApi();
    final handle = await pumpHome(tester, api);

    for (var i = 0; i < 8; i++) {
      await tester.tap(find.byKey(platePrevKey));
      await tester.pumpAndSettle();
    }

    final d8 = isoDaysAgo(8);
    final dt = _dt(d8);
    expect(find.text('${dt.month}月${dt.day}日'), findsOneWidget);
    expect(find.text('周${_weeks[dt.weekday % 7]}'), findsOneWidget);
    expect(handle.ref!.read(plateDateProvider), d8);
    expect(nextVisible(tester), isTrue);
    // 八天逐日翻牌 ⇒ 每改一次日期即一次重取（今日 + 8 天）
    expect(api.summaryDates.length, 9);
    expect(api.summaryDates.last, d8);
    // 逐日回今天：8 次 › 后 › 再次隐藏（‹› 对称性）
    for (var i = 0; i < 8; i++) {
      await tester.tap(find.byKey(plateNextKey));
      await tester.pumpAndSettle();
    }
    expect(find.text('今天'), findsOneWidget);
    expect(nextVisible(tester), isFalse);
  });

  /* ---------- ⑤ 五卡日期源已切 plateDateProvider（Step 4） ---------- */

  testWidgets('⑤切到昨天：水卡/运动卡卡题走「· 昨天」支，建议卡走非今日支（五卡同源）',
      (tester) async {
    final api = StubHealthApi(
      // 零记录样本（kcal=0 + records 空）→ 建议卡走 empty 规则：今天支/非今日
      // 两支文案不同，可据此判定 advice 吃到的是 plate 日期（advice_card_test ①c）
      summary: StubHealthApi.summaryMap(target: 1679),
      records: const <dynamic>[],
      profile: StubHealthApi.profileMap(),
      exercisesByDate: <String, List<Map<String, dynamic>>>{},
    );
    await pumpHome(tester, api);
    await tester.pumpAndSettle();

    // 今天态：三张带卡题两支的卡均走「今日」支
    expect(find.text('喝水打卡'), findsOneWidget); // water_card :148
    expect(find.text('今日运动'), findsOneWidget);

    await tester.tap(find.byKey(platePrevKey));
    await tester.pumpAndSettle();

    expect(find.text('喝水 · 昨天'), findsOneWidget); // water_card :149
    expect(find.text('今日运动'), findsNothing);
    expect(find.text('运动 · 昨天'), findsOneWidget); // home_screen :556
    expect(
      find.text('这一天还没有记录，可在记录页切换日期查看'),
      findsOneWidget,
    ); // advice_card 非今日支（isToday=false）
    expect(api.exerciseDates.last, isoDaysAgo(1));
  });

  /* ---------- ⑤b error 态：plate-head 不随取数失败消失（H5 静态卡头） ---------- */

  testWidgets('⑤b summary/records 双失败：错误卡内 plate-head 仍在场，‹ 仍可翻到昨天',
      (tester) async {
    final api = newApi()
      ..summaryError = ApiException('登录已过期，请重新登录')
      ..recordsError = ApiException('登录已过期，请重新登录');
    await pumpHome(tester, api);

    expect(find.text('登录已过期，请重新登录'), findsOneWidget); // home_screen 错误支
    expect(find.byKey(plateDateKey), findsOneWidget); // 卡头未被整张卡吞掉
    await tester.tap(find.byKey(platePrevKey));
    await tester.pumpAndSettle();
    expect(find.text('昨天'), findsOneWidget);
    expect(api.summaryDates.last, isoDaysAgo(1)); // 翻牌后仍按新 date 重取
  });

  /* ---------- ⑥ 问候头（app.js:287-294） ---------- */  test('⑥a 五档问候语 + 昵称拼接逐字（:289-290）', () {
    expect(greetingTextOf(0, null), '夜深了');
    expect(greetingTextOf(5, ''), '夜深了'); // '' falsy ≙ H5 nickname ?
    expect(greetingTextOf(6, null), '早上好');
    expect(greetingTextOf(10, null), '早上好');
    expect(greetingTextOf(11, null), '中午好');
    expect(greetingTextOf(13, null), '中午好');
    expect(greetingTextOf(14, null), '下午好');
    expect(greetingTextOf(17, null), '下午好');
    expect(greetingTextOf(18, null), '晚上好');
    expect(greetingTextOf(23, null), '晚上好');
    expect(greetingTextOf(8, '小满'), '早上好，小满'); // 全角逗号逐字
    expect(greetingTextOf(20, '小满'), '晚上好，小满');
  });

  test('⑥b 问候头日期行 `M月D日 · 星期X`（:291-293，weeks 表逐字）', () {
    // 2026-09-26 是星期六（weekday=6 → 六）；2026-09-27 星期日（weekday=7 → 日）
    expect(greetingDateLineOf(DateTime(2026, 9, 26)), '9月26日 · 星期六');
    expect(greetingDateLineOf(DateTime(2026, 9, 27)), '9月27日 · 星期日');
    expect(greetingDateLineOf(DateTime(2026, 1, 5)), '1月5日 · 星期一');
  });

  testWidgets('⑥c 问候头挂 profile 昵称，且恒用系统时钟——不随 ‹ › 变',
      (tester) async {
    final api = newApi();
    await pumpHome(tester, api);

    final now = DateTime.now();
    final expectedGreet = greetingTextOf(now.hour, '小满');
    expect(find.byKey(greetingKey), findsOneWidget);
    expect(find.text(expectedGreet), findsOneWidget);
    expect(find.text(greetingDateLineOf(now)), findsOneWidget); // 当日行

    await tester.tap(find.byKey(platePrevKey));
    await tester.pumpAndSettle();
    expect(find.text('昨天'), findsOneWidget);
    // 日期行不跟 plate 日期（≙ H5 renderGreeting 不吃 state.date）：
    // 仍显今天那行，昨天那行从未出现
    expect(find.text(greetingDateLineOf(now)), findsOneWidget);
    expect(
      find.text(greetingDateLineOf(DateTime(now.year, now.month, now.day - 1))),
      findsNothing,
    );
  });
}
