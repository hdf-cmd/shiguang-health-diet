// ShiguangFlutter/lib/features/profile/profile_providers.dart
// 用户资料唯一读取源（GET /user/profile 一次拿全：nickname/signature/avatar/
// goal/body/bodyUpdatedAt，fixture 契约已锁 responseFields，见
// contract/fixtures/diet-core.json routes[profile]）。T5 资料卡头部/编辑弹层
// 与 T6 身体卡共用。非 autoDispose：与 profileWeightProvider 同属账号级缓存，
// 登出/换号经 auth_state._invalidateAccountScopedCaches 显式失效（终审 I1 口径）。
// M7-T7 增件：actualDeficitProvider（近 7 天实际缺口，H5 反馈3 接线）。
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/swr_cache.dart' show swrCacheProvider;
import '../../data/swr_disk.dart' show swrDiskProvider;
import '../../domain/dates.dart' show localIso;
import '../../domain/deficit.dart' show avgDeficitFromRows;
import '../../domain/metabolism.dart' show computeMetabolism;
import '../../domain/models.dart' show Body;
import '../exercise/exercise_controller.dart' show exerciseKcalProvider;
// 文件级环（profile_providers ↔ exercise_controller）Dart 合法，
// auth_state.dart:13-14 同注。
import '../home/home_controller.dart'
    show healthApiProvider, summaryProvider, todayProvider;

final profileProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  final p = await ref.watch(healthApiProvider).getProfile();
  // M11-T3：profile 是本会话第一个「确知当前账号」的点。绑定后磁盘层才开闸
  // 落盘；uid 变化由 bindOwner 内部先清盘（不 await：落盘绑定属旁路，
  // 绝不能拖慢/拖挂所有下游都依赖的 profile 链）。
  // 绑定完必须补一次 syncDisk：绑定前首页的写入只在盘层留了快照、并未落盘，
  // 缺这一步冷启动永远播不出数据（v2.7.2 真机实测缺陷，钉 test ⑭）。
  final disk = ref.read(swrDiskProvider);
  if (disk != null) {
    final uid = '${p['id'] ?? ''}';
    unawaited(disk.bindOwner(uid).then((_) {
      if (ref.mounted) ref.read(swrCacheProvider).syncDisk();
    }));
  }
  return p;
});

/// profile.goal.waterMl 的水目标口径（M6-T7 评审 F3+F4：收敛 water_card /
/// advice_card 两份近重复 `_goalOf` 为单一工具，并复刻 H5 falsy 支）。
/// ≙ app.js:1948 `state.waterGoalMl = profile.goal.waterMl || 1600`——
/// null/0 皆落 1600（state.js:13 初值），在途/失败无数据同档。
/// round 系显示取整（云回包恒整数值，对 advice 消费点为恒等；原 advice
/// 版不 round 的语义差在此闭合，登记 task-7-report）。
/// 消费点：water_card（goal 行/顶格闸）、advice_card（buildAdvice ctx）。
int waterGoalMlOf(AsyncValue<Map<String, dynamic>> profile) {
  final wm = profile.maybeWhen(
    data: (p) {
      final goal = p['goal'];
      final v = goal is Map ? goal['waterMl'] : null;
      return v is num ? v : null;
    },
    orElse: () => null,
  );
  if (wm == null || wm == 0) return 1600; // ≙ `|| 1600` falsy 支（F3）
  return wm.round();
}

/* ================= M7-T7 近 7 天实际缺口（≙ app.js:1511-1569 反馈3） ================= */

/// 历史基准缓存持久层（≙ loadActualDeficitCache/saveActualDeficitCache
/// :1513-1518 的 localStorage 读写；prefs 是本地件，≙ 组合根注入面同
/// food_freq FoodFreqStore 先例）。
abstract class ActualDeficitStore {
  Future<Map<String, dynamic>?> load(String uid);
  Future<void> save(String uid, Map<String, dynamic> value);
}

/// 键名逐字 ≙ H5 :1511-1512 `sg_actual_deficit_` + (uid||'anon')（跨栈对齐）。
String actualDeficitKeyFor(String uid) =>
    'sg_actual_deficit_${uid.isEmpty ? 'anon' : uid}';

class PrefsActualDeficitStore implements ActualDeficitStore {
  PrefsActualDeficitStore();

  Future<SharedPreferences>? _inst;
  Future<SharedPreferences> get _prefs =>
      _inst ??= SharedPreferences.getInstance();

  @override
  Future<Map<String, dynamic>?> load(String uid) async {
    // ≙ :1514 `try { JSON.parse(getItem(k)) || null } catch { null }`
    try {
      final raw = (await _prefs).getString(actualDeficitKeyFor(uid));
      if (raw == null || raw.isEmpty) return null;
      final m = jsonDecode(raw);
      return m is Map ? Map<String, dynamic>.from(m) : null;
    } catch (_) {
      return null; // 损坏/平台通道异常即弃（测试未挂 prefs mock 时同路）
    }
  }

  @override
  Future<void> save(String uid, Map<String, dynamic> value) async {
    // ≙ :1517 `try { setItem(k, JSON.stringify(v)) } catch { 忽略 }`
    try {
      await (await _prefs)
          .setString(actualDeficitKeyFor(uid), jsonEncode(value));
    } catch (_) {/* 忽略 */}
  }
}

/// 默认即真实链路（prefs）。与 foodFreqStoreProvider 的「组合根 throw 待注入」
/// 不同处：本 provider 唯一消费面是代谢卡，root_container 零改动即可用；
/// 测试 override 内存 Fake（actual_deficit_test）。
final actualDeficitStoreProvider = Provider<ActualDeficitStore>(
    (ref) => PrefsActualDeficitStore());

/// 近 7 天实际日均缺口（值 ≙ deficit.dart 的 {avgDeficit, days, tdee} 或
/// null=不足 2 天走预设缺口）。
///
/// **autoDispose（M7 终审 I2，方案①）**：本 build watch 今日
/// summaryProvider(today)/exerciseKcalProvider(today) 两个 autoDispose
/// family 元素——若本 provider keepAlive，首访我的页后常驻监听永驻，钉死
/// 今日元素永不 dispose，之后离页回访零重取（外源变更在「今天」这一日不再
/// 被刷新），正是 T2 立论（keepAlive 派生会钉死 autoDispose 依赖，
/// exercise_controller.dart:22-23/186-187）的反向复发。改 autoDispose 后
/// 消费点（代谢卡 watch）即持有者：离页即卸、回访重建重发今日实时两读；
/// prefs 当日缓存闸（build 内 cache['date']==today 即零历史重拉）使重建
/// 成本≈0，语义回归 H5 每次进页 loadSummary/loadExercises（app.js:221-223/
/// 515）。回归钉 actual_deficit_test ⑦。
/// 换号：缓存键随 uid 天然隔离（prefs 键 `sg_actual_deficit_<uid>`），且
/// autoDispose 后无跨栈常驻态，无需另挂 auth_state 失效面。
///
/// provider 形态取舍（简报裁定「形态自定」）：AsyncNotifier 而非
/// FutureProvider——① 与 H5 对齐的「watch 驱动重算」需要监听承载的
/// watch 集（profile/今日 summary/今日运动合计），记录链 invalidate
/// summaryProvider 即自动重算（≙ renderRing :344 recomputeActualDeficitLive
/// 挂点，spec §3.4「invalidate 驱动」）；② 未来若有 force 重拉口（H5
/// refreshActualDeficit(true) 暂无消费面）Notifier 天然可扩展。
final actualDeficitProvider =
    AsyncNotifierProvider.autoDispose<ActualDeficitNotifier, Map<String, Object>?>(
  ActualDeficitNotifier.new,
);

class ActualDeficitNotifier extends AsyncNotifier<Map<String, Object>?> {
  @override
  FutureOr<Map<String, Object>?> build() async {
    // 全部 watch 必须同步先于首个 await（Riverpod 3 AsyncNotifier 生命周期：
    // await 后 watch 会让 build 重入挂死，diag 实测 AsyncLoading 永驻）。
    final today = ref.watch(todayProvider);
    // 次序 ≙ H5：refreshActualDeficit 排在 getProfile 之后（:1941-1952），
    // 档案未到手 ≙ fetchDeficitHistory :1521 `!b` 支 → null（卡走预设口径）；
    // 档案编辑 invalidate profileProvider 亦由此重入（当日缓存命中，仅
    // 重算——cache.tdee 当日不随档案刷新，H5 同款 staleness，bug-for-bug）。
    final p = ref.watch(profileProvider).maybeWhen(
          data: (v) => v,
          orElse: () => null, // 在途/失败 ≙ H5 state.body 未就绪
        );
    // 今日实时值（≙ state.summary.kcal / state.exerciseKcal，:1547-1548。
    // H5 取「当前展示日」且仅在 date==today 时重算；Flutter 钉死取今日族
    // provider——消费点（代谢卡）永远显示今日缺口，两处等值）。记录链
    // invalidate summaryProvider → 本 watch 重跑 ≙ renderRing :344 挂点。
    final todayKcal = ref.watch(summaryProvider(today)).maybeWhen(
          data: (s) => s.kcal,
          orElse: () => 0, // 在途/失败 ≙ H5 loadSummary 前 state.summary 缺省
        );
    final todayEx = ref.watch(exerciseKcalProvider(today));
    if (p == null) return null;
    final uid = (p['id'] as String?) ?? ''; // ≙ currentUid() :1479 || ''
    return _refreshAndCompute(p, uid, today, todayKcal, todayEx);
  }

  /// 在途历史拉取去重：profile/summary/exercise 依赖各自 loading→data 会让
  /// build 连续重入，首跑回包写缓存前若不去重会双发 12 请求（H5 单线程
  /// boot 单次 refresh 天然无此题，Flutter watch 模型的实现护栏）。
  Future<Map<String, Object>?>? _fetchInflight;

  /// ≙ refreshActualDeficit(force=false) :1552-1564：当日缓存命中零请求；
  /// 跨日重拉并写回；拉取异常沿用旧缓存（:1560，实际不可达——单日失败
  /// 已被内部 catch 消化，保留该支为 H5 同构兜底）。
  Future<Map<String, Object>?> _refreshAndCompute(
      Map<String, dynamic> p, String uid, String today, num todayKcal,
      [num todayEx = 0]) async {
    final store = ref.read(actualDeficitStoreProvider);
    Map<String, dynamic>? cache = await store.load(uid);
    if (cache == null || cache['date'] != today) {
      final mine = _fetchInflight ??= _fetchHistory(p, today);
      final Map<String, Object>? fresh;
      try {
        fresh = await mine;
      } finally {
        _fetchInflight = null;
      }
      if (fresh != null) {
        cache = fresh;
        await store.save(uid, Map<String, dynamic>.from(fresh)); // :1559
      }
    }
    return _avgFromCache(cache, today, todayKcal, todayEx); // :1562
  }

  /// ≙ fetchDeficitHistory :1520-1541（见逐行注）。
  Future<Map<String, Object>?> _fetchHistory(
      Map<String, dynamic> p, String today) async {
    final b = Body.fromMap(
        ((p['body'] ?? const <String, dynamic>{}) as Map).cast<String, Object?>());
    // :1522 tw=profileData.goal.targetWeight（profile 必在场，本函数仅在
    // await profile 后调用；goal 缺键 ≙ undefined → computeMetabolism 当前体重支）
    final goal = p['goal'];
    final tw = goal is Map ? (goal['targetWeight'] as num?)?.toDouble() : null;
    final tdee = computeMetabolism(b, tw).tdee; // :1523
    final base = DateTime.parse('${today}T00:00:00');
    // :1525-1528 i=1..6 昨天起 6 天，**不含今天**（今天用实时值并入）
    final dates = [
      for (var i = 1; i <= 6; i++) // 日历日减一 ≙ setDate(getDate()-i)
        localIso(DateTime(base.year, base.month, base.day - i)),
    ];
    final api = ref.read(healthApiProvider);
    // :1529-1532 两组 Promise.all 并行；单日失败各按 .catch(()=>null/[]) 吞掉
    final sumFuts = <Future<Map<String, dynamic>?>>[
      for (final dt in dates)
        api
            .getDailySummary(dt)
            .then<Map<String, dynamic>?>((v) => v, onError: (_, _) => null),
    ];
    final exFuts = <Future<List<dynamic>>>[
      for (final dt in dates)
        api
            .getExercises(dt)
            .then<List<dynamic>>((v) => v, onError: (_, _) => const []),
    ];
    final sums = await Future.wait(sumFuts);
    final exs = await Future.wait(exFuts);
    final history = <Map<String, Object?>>[];
    for (var i = 0; i < dates.length; i++) {
      final s = sums[i];
      final kcal = s?['kcal'];
      // :1536 `!s || !(s.kcal > 0)` 未记录日不计。M7-T8（T7 Minor②）登记：
      // `kcal is num` 类型闸比 H5 JS 强算 falsy 口径严（kcal='300' 串在 H5
      // 会真值入行）——contract fixture 锁 kcal 为 num、该形不可达，
      // 防御方向有意取严。
      if (s == null || !(kcal is num && kcal > 0)) continue;
      // :1537 exKcal=该日运动记录 kcal 合计（缺/坏项按 0 fold）
      final exKcal = exs[i].fold<num>(
          0, (a, r) => a + ((r is Map ? r['kcal'] : null) as num? ?? 0));
      history.add({'date': dates[i], 'intake': kcal, 'exKcal': exKcal}); // :1538
    }
    return {'date': today, 'tdee': tdee, 'history': history}; // :1540
  }

  /// ≙ computeAvgDeficit :1543-1550：历史 rows + 今日实时行 → 域均值
  /// （<2 天 null 闸在 deficit.dart，minDays 缺省 2 ≙ H5 调用面省参）。
  Map<String, Object>? _avgFromCache(
      Map<String, dynamic>? cache, String today, num todayKcal, num todayEx) {
    if (cache == null) return null;
    final h = cache['history'];
    if (h is! List) return null; // ≙ :1544 !cache.history
    final tdee = cache['tdee'];
    // H5 缺 tdee 会算出 NaN→显示退化；Flutter 缓存形状本文件自写，仅防
    // 手工塞坏缓存的场景，落预设支比 NaN 稳（差异登记 task-7-report）。
    if (tdee is! num) return null;
    final rows = <Map>[...h.whereType<Map>()]; // :1545 slice
    if (todayKcal > 0) {
      // :1547-1548 今日行 intake=summary.kcal、exKcal=state.exerciseKcal||0
      rows.add({'date': today, 'intake': todayKcal, 'exKcal': todayEx});
    }
    return avgDeficitFromRows(tdee, rows); // :1549
  }
}
