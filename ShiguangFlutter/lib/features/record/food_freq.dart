// ShiguangFlutter/lib/features/record/food_freq.dart
// 「常吃排序 + 吃过次数」（M12 改版）：
// ① 首次使用拉一次 `/diet/records/freq`（云函数按 uid 全史聚合 {菜名: 次数}）
//    落本地 prefs 并打初始化标记；M11 前的「逐日 30 请求」整体删除。
// ② App 内每记一笔同名 +1；③ 食物列表按频次**稳定降序**，搜索结果与食物库
//    行尾徽标共用同一份计数。
// 键用菜名：云端记录（sg_records）只有 name 没有食物库 id，H5 历史也只能
// 按名字聚合；名字同时是列表条目的天然匹配键。
// 计数口径（老大 2026-10-20 裁决）＝**全部历史**，不是近 30 天；因此常吃排序
// 也按全史排——当年定 30 天窗口的唯一理由是「要发 30 次请求」，该前提被
// M12-③ 一次往返消掉。若要「最近常吃的排前面」，另加时间衰减再议。

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../home/home_controller.dart' show healthApiProvider;
// M7-T8 分账号键的 uid 源（文件级环 profile_providers ↔ … Dart 合法，
// exercise_controller 同注先例）。
import '../profile/profile_providers.dart' show profileProvider;

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

/// 解析云函数 freq 响应：`counts` 缺失/非对象返回 null（调用方按失败处理，
/// 不把「空表」当成「一道菜都没吃过」——M11 静默降级的教训）。
Map<String, int>? parseFoodFreqCounts(Object? raw) {
  if (raw is! Map) return null;
  final out = <String, int>{};
  raw.forEach((k, v) {
    if (v is num) out['$k'] = v.toInt();
  });
  return out;
}

/// 常吃计数持久层。生产用 SharedPreferences（[PrefsFoodFreqStore]），
/// 测试注入内存实现——组合根模式同 M2 TokenStore。
/// 键分账号（M7-T8）：uid 由 [FoodFreqNotifier] 经 profileProvider 解析后传入。
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

  // ===== M12：键升 v2（计数口径由「近 30 天」改「全史」）=====
  // v1 的分账号键（`sg_food_freq_counts_<uid>` / `sg_food_freq_init_v1_<uid>`）
  // 与更早的全局键一律读到即删：v1 标记若被当成「已初始化」，老用户会永远
  // 停在 30 天计数上看不到全史数。任何方法触盘时顺手清理（见 [_purgeLegacy]）。
  static const _kCountsLegacy = 'sg_food_freq_counts';
  static const _kInitLegacy = 'sg_food_freq_init_v1';
  static String _kCounts(String uid) =>
      'sg_food_freq_counts_v2_${uid.isEmpty ? 'anon' : uid}';
  static String _kInit(String uid) =>
      'sg_food_freq_init_v2_${uid.isEmpty ? 'anon' : uid}';

  static bool _isLegacy(String k) =>
      (k.startsWith(_kCountsLegacy) && !k.startsWith('sg_food_freq_counts_v2_')) ||
      k.startsWith(_kInitLegacy);

  /// 旧键读到即删（v2 键与 v2 无关键不动）。
  Future<void> _purgeLegacy(SharedPreferences p) async {
    for (final k in p.getKeys().toList()) {
      if (_isLegacy(k)) await p.remove(k);
    }
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

final foodFreqStoreProvider = Provider<FoodFreqStore>(
    (ref) => throw UnimplementedError('组合根注入'));

/// 频次计数状态。keepAlive（非 autoDispose）：整 App 生命周期一份。
/// watch 方（searchProvider family / 食物库行）在计数变化时自动重排/重绘。
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

  /// 幂等：标记已落盘即直返回放。未初始化时发 1 次 freq 请求（全史计数）。
  /// 响应缺 `counts` 或网络失败 → 不落标记、本会话可再试（[state] 保持空，
  /// 列表按云端原序显示）。`complete=false`（服务端翻页被截断）照用计数并
  /// 落标记：结果是下界，但重复查询只会得到同样的下界。
  Future<void> ensureLoaded() async {
    if (_started) return;
    _started = true;
    final uid = await _resolveUid();
    final store = ref.read(foodFreqStoreProvider);
    if (await store.isInitialized(uid)) {
      state = await store.loadCounts(uid);
      return;
    }
    try {
      final data = await ref.read(healthApiProvider).getFoodFreq();
      final counts = parseFoodFreqCounts(data['counts']);
      if (counts == null) throw const FormatException('freq 响应缺 counts');
      state = counts;
      await store.saveCounts(uid, counts);
      await store.markInitialized(uid);
    } catch (_) {
      _started = false; // 本会话内下次开弹层可再试
    }
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
