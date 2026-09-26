// ShiguangFlutter/lib/features/home/home_controller.dart
// 首页数据层 riverpod provider（M2 Task 8）。
// 组合根模式对齐 auth_state.dart：healthApiProvider 默认走真实链路
// （ApiClient ← auth_state.apiClientProvider），main() 显式构造注入，
// 测试只 override healthApiProvider 即可全链路换桩（见 test/stubs/stub_health_api.dart）。

// riverpod 3.x：StateProvider 收敛在 legacy 导出（未废弃，@publicInLegacy，
// 与 report_controller.dart:6-7 同法）。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/legacy.dart' show StateProvider;

import '../../app/auth_state.dart' show apiClientProvider;
import '../../data/health_api.dart';
import '../../domain/dates.dart';
import '../../domain/models.dart';

final healthApiProvider =
    Provider<HealthApi>((ref) => HealthApi(ref.watch(apiClientProvider)));

/// 今日（localIso 语义，对齐 js/logic.js:50-64；H5 state.date 初始值=今天）。
/// 查看非今日时由调用方直接把 date 传给 family provider，不覆盖本 provider。
final todayProvider = Provider<String>((ref) => todayIso());

/// 某日热量汇总（HealthAPI.getDailySummary → 契约 dailySummary：
/// {kcal,target,carb,protein,fat,water}，target 由云函数派生，端上不硬编码）。
final summaryProvider =
    FutureProvider.autoDispose.family<Summary, String>((ref, date) async {
  final m = await ref.watch(healthApiProvider).getDailySummary(date);
  return Summary.fromMap(m);
});

/// 某日三餐记录（HealthAPI.getMealRecords → 契约 mealRecords 数组：
/// {id,meal,name,portion,kcal,...}；元素防御性过滤为非 Map 即丢，
/// 云端返回恒为对象数组，见 contract/fixtures/diet-core.json）。
final recordsProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, String>((ref, date) async {
  final list = await ref.watch(healthApiProvider).getMealRecords(date);
  return list
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList(growable: false);
});

/* ---------- M7-T3 水卡乐观态 per-date 化（M6 遗留「跨日遮蔽」债根治） ---------- */

/// 某日喝水乐观杯数（null=无本地态，显示跟 [summaryProvider]）。
/// 旧形态是 WaterCard 的单值 widget 字段 `_waterOverride`：切日期/他处
/// invalidate 后仍以旧日乐观值遮蔽新日 summary 真值。H5 无此债——乐观写
/// 直改 state.summary.water 本体（app.js:438/457 实读），切日期即
/// loadSummary 整体重写（:222 实读）；Flutter 侧 summary 是不可直写的
/// family 缓存，故乐观值独立成壳，并按 date 隔离（根治点=per-date key）。
/// keepAlive（非 autoDispose）：切走再回同日，回包前写入的态仍在
/// （water_card_test ⑤ 钉；同日真值同步由回包/回滚路径负责）。
/// 登出/换号整族失效见 auth_state._invalidateAccountScopedCaches。
final waterOverrideProvider =
    NotifierProvider.family<WaterOverride, int?, String>(
  WaterOverride.new,
);

class WaterOverride extends Notifier<int?> {
  /// M7-T8（T3 Minor③ 销账）：family 实参 date 系形态必需（构造签名要求），
  /// 但本类体内零读取——乐观杯数纯 UI 态，date 已由 provider key 承载
  /// （异于 T2 ExercisesNotifier：其 date 为 getExercises 取数入参）。
  /// 旧形态 `final String date` 字段属写入无读取 dead state，收口为无名形参。
  WaterOverride(String date);

  @override
  int? build() => null;

  /// 乐观写（≙ 旧 setState(_waterOverride = prev ± 1)）：base 为点击时
  /// 显示杯数（override ?? summary 杯数），≙ H5 `prev`（app.js:437/456）。
  void bump(int base, int delta) => state = base + delta;

  /// 回包跟值 / 失败回滚（≙ app.js:444/447、462/465 对 state 的直写）。
  void apply(int cups) => state = cups;
}

/* ---------- M7-T1 首页日期状态机（≙ H5 state.date + renderPlateDate/shiftDate） ---------- */

/// 首页/记录页共享日期（≙ H5 state.date，app.js:215-224）。初值=今天；
/// 跨午夜不自愈 ≙ H5 仅交互时重算 todayIso()（同款行为，登记不修：H5 停留
/// 首页过午夜后 ‹ › 仍以旧 today 为闸，本仓不挂午夜定时器，见 spec §3.1）。
/// 消费方：home 五卡（本任务）、水卡 per-date（T3）、记录页 7 天行（T6）。
final plateDateProvider = StateProvider<String>((ref) => todayIso());

/// 餐盘日期胶囊三态（≙ app.js:209-211 renderPlateDate 的 HTML 拆分：
/// 主文案 + `<small>` 副文案；H5 间距由 .plate-date small{margin-left:4px}
/// 承担，故两态直拼即等于 #plate-date.textContent）。
/// 返回 (主, 副) 供 UI 分别排版（--text-sm/600 与 --text-xs/ink3/400）。
(String, String) plateDatePartsOf(String date) {
  final t = todayIso();
  if (date == t) return ('今天', '· 右滑看历史'); // 「右滑看历史」系文案，非手势（本任务不移植卡内滑动）
  final now = DateTime.now();
  // JS: const yd = new Date(); yd.setDate(yd.getDate()-1) —— 日历日减一
  final yIso = localIso(DateTime(now.year, now.month, now.day - 1));
  // JS: new Date(iso + 'T00:00:00') —— 无 Z 按本地解析，Dart 同语义
  final d = DateTime.parse('${date}T00:00:00');
  if (date == yIso) return ('昨天', '${d.month}/${d.day}');
  // JS weeks 表下标=getDay()（日=0…六=6）；Dart weekday%7 同序（Sun 7→0）
  const weeks = ['日', '一', '二', '三', '四', '五', '六'];
  return ('${d.month}月${d.day}日', '周${weeks[d.weekday % 7]}');
}

/// 胶囊完整文案（主+副直拼 ≙ H5 #plate-date.textContent 单串形态）
String plateDateLabelOf(String date) {
  final (main, small) = plateDatePartsOf(date);
  return '$main$small';
}

/// 前后翻一天（≙ app.js:215-224 shiftDate(delta)）。dir：-1=更早（‹），
/// +1=更近（›）。未来闸逐字 :219 `next > todayIso()` → toast「已经到今天了」
/// 并 return（**零状态变更、零请求**）；往过去无下限（H5 同款）。
///
/// 取数不在此处发起：五卡 watch plateDateProvider 且 provider 皆 date 的
/// family，日期一变即各自起新流（≙ :221-223 的并行拉取）。此处若再手动
/// 「invalidate 一梭子」，autoDispose family 会在同帧重复起流（多打请求，
/// 桩 date 序列即失真的回归点），故刻意不做（简报 Step3 裁定）。
/// T1 carried 已在 M7-T2 收口：exercisesProvider 已 Notifier 化并 autoDispose
/// （连同派生 exerciseKcalProvider），「切走再切回同一天」必重发 getExercises
/// ——与 H5 每次切日期都 loadExercises（:223）同语义，同日回访不再吃缓存。
Future<void> shiftPlateDate(
  WidgetRef ref,
  int dir,
  void Function(String) toast,
) async {
  final cur = ref.read(plateDateProvider);
  final d = DateTime.parse('${cur}T00:00:00');
  final next = localIso(DateTime(d.year, d.month, d.day + dir));
  if (next.compareTo(todayIso()) > 0) {
    toast('已经到今天了'); // :219 逐字
    return;
  }
  ref.read(plateDateProvider.notifier).state = next; // :220
}

