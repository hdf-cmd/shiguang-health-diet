// ShiguangFlutter/lib/features/record/food_freq.dart
// 「常吃排序」（老大 2026-09-25 拍板方案 B）：
// ① 首次使用拉最近 30 天云端记录（/diet/records 只读，逐日并发）聚合出
//    {菜名: 次数} 落本地 prefs 并打初始化标记；② App 内每记一笔同名 +1；
// ③ 食物列表按频次**稳定降序**——常吃在前，同频次/零频次保持云端原序。
// 键用菜名：云端记录（sg_records）只有 name 没有食物库 id，H5 历史也只能
// 按名字聚合；名字同时是列表条目的天然匹配键。
// 云函数零改动（排序纯客户端，历史走既有只读路由）。

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../home/home_controller.dart' show healthApiProvider, todayProvider;
// M7-T8 分账号键的 uid 源（文件级环 profile_providers ↔ … Dart 合法，
// exercise_controller 同注先例）。
import '../profile/profile_providers.dart' show profileProvider;
import '../../domain/dates.dart';

/// 按频次稳定降序。counts 缺项按 0；不修改入参列表。
List<Map<String, dynamic>> sortFoodByFreq(
  List<Map<String, dynamic>> list,
  Map<String, int> counts,
) {
  if (counts.isEmpty) return list; // 初始化未完成/无历史 → 原序（不重排）
  // 稳定排序：先记原索引，比较频次、平局比原索引（Dart List.sort 不稳定，
  // 故显式带上索引兜底保序）。
  final indexed = List.generate(list.length, (i) => i);
  indexed.sort((a, b) {
    final fa = counts[list[a]['name'] ?? ''] ?? 0;
    final fb = counts[list[b]['name'] ?? ''] ?? 0;
    if (fa != fb) return fb.compareTo(fa); // 降序
    return a.compareTo(b); // 平局保持原相对顺序
  });
  return indexed.map((i) => list[i]).toList(growable: false);
}

/// 把逐日记录聚合成 {菜名: 总次数}。空名/无名条目不计。
Map<String, int> aggregateFreqFromRecords(
  Map<String, List<Map<String, dynamic>>> recordsByDate,
) {
  final out = <String, int>{};
  for (final recs in recordsByDate.values) {
    for (final r in recs) {
      final name = (r['name'] as String? ?? '').trim();
      if (name.isEmpty) continue;
      out[name] = (out[name] ?? 0) + 1;
    }
  }
  return out;
}

/// 以 [end] 为最后一天、往前共 [days] 天的本地 ISO 日期表（含 end，降序）。
List<String> recentIsoDates(DateTime end, int days) {
  return List.generate(days, (i) => localIso(end.subtract(Duration(days: i))));
}

/// 常吃计数持久层。生产用 SharedPreferences（[PrefsFoodFreqStore]），
/// 测试注入内存实现——组合根模式同 M2 TokenStore。
/// M7-T8（T4 池收口）：prefs 键分账号——uid 由 [FoodFreqNotifier] 经
/// profileProvider 解析后传入（≙ actualDeficitKeyFor 的 `uid||'anon'` 档）。
abstract class FoodFreqStore {
  Future<Map<String, int>> loadCounts(String uid);
  Future<void> saveCounts(String uid, Map<String, int> counts);
  Future<bool> isInitialized(String uid);
  Future<void> markInitialized(String uid);
}

class PrefsFoodFreqStore implements FoodFreqStore {
  PrefsFoodFreqStore();
  Future<SharedPreferences>? _inst;
  Future<SharedPreferences> get _prefs => _inst ??= SharedPreferences.getInstance();

  // ===== M7-T8 分账号键（不迁移旧键）=====
  // 新键 `sg_food_freq_counts_<uid>`（init 标记同法分账号——否则 B 账号读到
  // A 的标记即直返空计数、30 天回填永不触发）。**注销旧全局键**
  // `sg_food_freq_counts`/`sg_food_freq_init_v1`：不迁移其内容——ensureLoaded
  // 的 30 天云端回填机制可自重建，迁移属 YAGNI；任一方法触盘时读到旧键即删
  // （见 [_purgeLegacy] 注释登记）。
  static const _kCountsLegacy = 'sg_food_freq_counts';
  static const _kInitLegacy = 'sg_food_freq_init_v1';
  static String _kCounts(String uid) =>
      'sg_food_freq_counts_${uid.isEmpty ? 'anon' : uid}';
  static String _kInit(String uid) =>
      'sg_food_freq_init_v1_${uid.isEmpty ? 'anon' : uid}';

  /// 旧全局键读到即删（键分账号后旧键永不再被读取，留着只占位/串号）。
  Future<void> _purgeLegacy(SharedPreferences p) async {
    if (p.containsKey(_kCountsLegacy)) await p.remove(_kCountsLegacy);
    if (p.containsKey(_kInitLegacy)) await p.remove(_kInitLegacy);
  }

  @override
  Future<Map<String, int>> loadCounts(String uid) async {
    final p = await _prefs;
    await _purgeLegacy(p);
    final raw = p.getString(_kCounts(uid));
    if (raw == null || raw.isEmpty) return {};
    try {
      final m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return m.map((k, v) => MapEntry(k, (v as num).toInt()));
    } catch (_) {
      return {}; // 损坏即弃，下次初始化重来
    }
  }

  @override
  Future<void> saveCounts(String uid, Map<String, int> counts) async {
    final p = await _prefs;
    await _purgeLegacy(p);
    await p.setString(_kCounts(uid), jsonEncode(counts));
  }

  @override
  Future<bool> isInitialized(String uid) async {
    final p = await _prefs;
    await _purgeLegacy(p);
    return p.getBool(_kInit(uid)) ?? false;
  }

  @override
  Future<void> markInitialized(String uid) async {
    final p = await _prefs;
    await _purgeLegacy(p);
    await p.setBool(_kInit(uid), true);
  }
}

/// 初始化窗口：近 30 天（老大拍板 B 方案）。
const int kFreqInitDays = 30;

final foodFreqStoreProvider = Provider<FoodFreqStore>(
    (ref) => throw UnimplementedError('组合根注入'));

/// 频次计数状态。keepAlive（非 autoDispose）：整 App 生命周期一份。
/// watch 方（searchProvider family）在计数变化时自动重排。
final foodFreqProvider =
    NotifierProvider<FoodFreqNotifier, Map<String, int>>(FoodFreqNotifier.new);

class FoodFreqNotifier extends Notifier<Map<String, int>> {
  @override
  Map<String, int> build() {
    // 打开记一笔弹层时由 UI 调 ensureLoaded()；此处不自动发网络。
    return const {};
  }

  /// 分账号键的 uid 源（M7-T8）：profileProvider `id`（≙ actualDeficit
  /// :1521 同法，H5 currentUid()||'anon' 档）；档案拉取失败落 ''（anon）且
  /// 不缓存失败值，下次再解析。
  String? _uid;
  Future<String> _resolveUid() async {
    final cached = _uid;
    if (cached != null) return cached;
    try {
      final p = await ref.read(profileProvider.future);
      final id = p['id'];
      return _uid = id == null ? '' : '$id';
    } catch (_) {
      return ''; // 档案失败：anon 档兜底（本会话可再解析）
    }
  }

  /// 幂等：已初始化/已加载即直返。失败容忍：部分日期取回即用但不打标记，
  /// 下次冷启再补齐；全失败返回空且不标记（本次按无频次原序显示）。
  Future<void> ensureLoaded() async {
    if (_started) return;
    _started = true;
    final uid = await _resolveUid();
    final store = ref.read(foodFreqStoreProvider);
    if (await store.isInitialized(uid)) {
      state = await store.loadCounts(uid);
      return;
    }
    final api = ref.read(healthApiProvider);
    // 时钟走 todayProvider（测试可固定窗口，跨零点重开弹层即新窗口）
    final dates = recentIsoDates(
        DateTime.parse(ref.read(todayProvider)), kFreqInitDays);
    final byDate = <String, List<Map<String, dynamic>>>{};
    var failures = 0;
    await Future.wait(dates.map((d) async {
      try {
        final recs = await api.getMealRecords(d);
        byDate[d] = recs.map((e) => Map<String, dynamic>.from(e)).toList();
      } catch (_) {
        failures++; // 该日失败：本次仍可用成功日聚合，但不打标记，下次冷启补齐
      }
    }));
    if (byDate.isEmpty) {
      _started = false; // 全失败：本会话内下次开弹层可再试
      return;
    }
    final counts = aggregateFreqFromRecords(byDate);
    state = counts;
    await store.saveCounts(uid, counts);
    if (failures == 0) await store.markInitialized(uid);
  }

  bool _started = false;

  /// 记一笔成功续算：同名 +1 并落盘（删除记录不回减——"吃过"是事实）。
  Future<void> record(String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final next = Map<String, int>.from(state)..[trimmed] = (state[trimmed] ?? 0) + 1;
    state = next;
    final store = ref.read(foodFreqStoreProvider);
    await store.saveCounts(await _resolveUid(), next);
  }
}
