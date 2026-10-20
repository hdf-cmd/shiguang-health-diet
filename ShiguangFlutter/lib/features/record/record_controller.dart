// ShiguangFlutter/lib/features/record/record_controller.dart
// 记录页数据层（M2 Task 9）。recordsProvider/summaryProvider/todayProvider/
// healthApiProvider 直接复用 home_controller 的 family 实例（同一 Provider
// 对象同参数即同一缓存，记录页与首页天然共享，不重建）。
// 行为权威源 js/app.js：defaultMeal 603-609、搜索弹层取数 628-651、
// 添加/删除后「静默对账云端」refreshToday+loadRecordPage（572-573、683）。

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/swr_cache.dart' show SwrCache, swrCacheProvider;
import '../../domain/models.dart' show Summary;
import '../home/home_controller.dart'
    show
        SwrFamilyNotifier,
        healthApiProvider,
        recordsProvider,
        summaryProvider;
import 'food_freq.dart';
import 'food_search_local.dart';

// 记录页/弹层只 import 本文件即可拿到复用的地基 provider。
export '../home/home_controller.dart'
    show healthApiProvider, recordsProvider, summaryProvider, todayProvider;
export 'food_search_local.dart'
    show FoodQuery, filterFoodLibrary, foodsFullCacheKey, searchCacheKey;

/// 按当前小时智能默认餐次。逐分支镜像 js/app.js:603-609 defaultMeal：
/// <10 早餐 / <15 午餐 / <21 晚餐 / 其余零食。
/// 小时由调用方注入（DateTime.now().hour 或测试固定值），保证可测。
String defaultMealAt(int hour) {
  if (hour < 10) return 'breakfast';
  if (hour < 15) return 'lunch';
  if (hour < 21) return 'dinner';
  return 'snack';
}

/// 云端返回的 dynamic 数组 → 端上地图（元素防御性过滤非 Map，同 RecordsNotifier）。
List<Map<String, dynamic>> asFoodList(List<dynamic> list) => list
    .whereType<Map>()
    .map((e) => Map<String, dynamic>.from(e))
    .toList(growable: false);

/// 食物搜索结果（契约 searchFoods 数组：{id,name,meta,kcal,emoji,image,meals,
/// protein,carb,fat,per100?,baseG?,unit?}）。meal 恒传当前选中餐次（H5 亦恒传
/// state.mealChosen，js/app.js:633）。常吃排序（方案 B）：按 foodFreqProvider
/// 计数稳定降序，计数更新自动重排。
///
/// M11-T1：改为「空词快照 + 端上过滤」，逐词不再发网络请求；结果键进 SWR，
/// 回删/重打同一个词即时播种。截断守卫见 [foodLibraryLooksTruncated]。
/// 快照存 SwrCache（键 `foods.full.<meal>`）且**命中即短路**——这与
/// [SwrFamilyNotifier] 的「命中也后台刷新」相反：食物库只在被增删改时才需要
/// 重取（见 [invalidateFoodLibrary]），后台重刷只会把网关往返塞进打字路径。
/// 快照为什么在 fetch 内部取而不另立 provider：Riverpod 3.4.3 实测——AsyncNotifier
/// 的 build 抛错时它的 `.future` **永不 settle**（有监听者也一样，只有 AsyncValue
/// 正常落 AsyncError），若在此 await 别人的 `.future`，断网会让弹层永久停在
/// 「搜索中…」，而不是既有契约的「搜索失败：msg」+「重试」
/// （search_sheet.dart:213-223，钉见 search_local_test ⑥）。
final searchProvider = AsyncNotifierProvider.autoDispose
    .family<SearchNotifier, List<Map<String, dynamic>>, FoodQuery>(
        SearchNotifier.new);

class SearchNotifier
    extends SwrFamilyNotifier<List<Map<String, dynamic>>, FoodQuery> {
  SearchNotifier(super.query);

  @override
  String cacheKey(FoodQuery q) => searchCacheKey(q);

  @override
  Future<List<Map<String, dynamic>>> fetch(FoodQuery q) async {
    // watch 一律先于首个 await（Riverpod 3 生命周期，同 profile_providers:127 注）
    final counts = ref.watch(foodFreqProvider);
    final cache = ref.read(swrCacheProvider);
    final key = foodsFullCacheKey(q.meal);
    var full = cache.read<List<Map<String, dynamic>>>(key);
    if (full == null) {
      // 空词 + meal ≙ 现网「开弹层即出结果」那次请求，字段与顺序原样保留
      final list = await ref.read(healthApiProvider).searchFoods('', q.meal);
      full = asFoodList(list);
      cache.write(key, full);
    }
    if (foodLibraryLooksTruncated(full)) {
      // 快照里的自定义项撞上服务端 limit(20)：回落逐词，宁慢不漏
      final list =
          await ref.read(healthApiProvider).searchFoods(q.keyword, q.meal);
      return sortFoodByFreq(asFoodList(list), counts);
    }
    return sortFoodByFreq(
        filterFoodLibrary(full: full, keyword: q.keyword), counts);
  }
}

/// 食物库变更（新增/删除自定义食物、改归类、改内置隐藏项）后的统一失效：
/// 内存两份缓存（空词快照 + 逐词结果）+ 逐词 provider。
/// 形参取 WidgetRef：四个写路径调用点全在 ConsumerState 内（Riverpod 的
/// MutationTarget 未列入公共导出；测试侧 ProviderContainer 的等价展开见
/// search_local_test ⑧）。
void invalidateFoodLibrary(WidgetRef ref) {
  clearFoodLibraryCache(ref.read(swrCacheProvider));
  ref.invalidate(searchProvider);
}

/// 写动作编排：成功后 invalidate 当日 records+summary（H5 添加/删除成功后的
/// `Promise.all([refreshToday(), loadRecordPage()])` 对账语义，
/// js/app.js:572-573、683、770）。失败原样抛 ApiException 由 UI 出 toast。
class RecordController {
  RecordController(this._ref);

  final Ref _ref;

  /// 添加在途键集合（H5「点击即 btn.disabled，finally 恢复」的等价物，
  /// js/app.js:677/693）。慢网双击时第二次调用同键直接丢弃：不发请求、
  /// 不重复记一笔。键由 UI 提供（食物 id，缺 id 时退化为 name），
  /// 故搜索弹层与份量弹层对同一食物共享这一在途状态。
  final Set<String> _inFlight = <String>{};

  /// 该食物的添加请求是否仍在途（UI 据此禁用按钮并显示「请稍候…」）
  bool isInFlight(String key) => _inFlight.contains(key);

  /// 记一笔。返回 true=本次真正发出请求并成功；false=同键请求在途，本次丢弃。
  ///
  /// M11-T2 乐观落位：temp 入列表 + summary 四项加算发生在 `await` **之前的同步
  /// 段**，≙ H5 js/app.js:669-676「乐观更新：立即入列表+环，不等网络（反馈8）」；
  /// 回包后静默对账（:683-684），失败按 :685-693 摘回 temp 并减算。
  Future<bool> addRecord(
    String date,
    Map<String, dynamic> record, {
    required String pendingKey,
  }) async {
    if (!_inFlight.add(pendingKey)) return false; // 连点兜底：同键第二次不进网络层
    final temp = _optimisticAdd(date, record);
    try {
      await _ref.read(healthApiProvider).addFoodRecord(record);
      // 常吃续算（方案 B）：仅成功计数，删除不回减（"吃过"是事实）。
      // 计数是尽力而为的旁路——持久层异常绝不打断记餐主流程。
      final name = record['name'] as String?;
      if (name != null) {
        try {
          await _ref.read(foodFreqProvider.notifier).record(name);
        } catch (_) {/* 排序降级为原序，记录本身已落库 */}
      }
      return true;
    } catch (_) {
      _removeOptimistic(date, temp, sign: 1);
      rethrow;
    } finally {
      _inFlight.remove(pendingKey);
      _reconcileDay(date); // 提交/回滚都收口：解挂 + 作废过期在途 + 重建对账
    }
  }

  /// 删一笔。乐观移除 + 减算在请求前（≙ H5 :563-571），失败把该条放回并加算
  /// （:577-581 放回的是 `push` 到列表尾部，本处 bug-for-bug 同形）。
  Future<void> deleteRecord(String date, String id) async {
    final cache = _ref.read(swrCacheProvider);
    final rows = _cachedRows(cache, date);
    Map<String, dynamic>? removed;
    if (rows != null) {
      final i = rows.indexWhere((r) => '${r['id']}' == id);
      if (i >= 0) {
        removed = rows[i];
        rows.removeAt(i);
        cache.write('records.$date', rows);
        _patchSummary(cache, date, removed, sign: -1);
        _holdDay(cache, date);
        _invalidateDay(date);
      }
    }
    try {
      await _ref.read(healthApiProvider).deleteFoodRecord(id);
    } catch (_) {
      if (removed != null) {
        final back = _cachedRows(_ref.read(swrCacheProvider), date);
        if (back != null) {
          back.add(removed);
          _ref.read(swrCacheProvider).write('records.$date', back);
        }
        _patchSummary(_ref.read(swrCacheProvider), date, removed, sign: 1);
      }
      rethrow;
    } finally {
      _reconcileDay(date);
    }
  }

  /// 当日缓存里的记录行（**可变副本**）；无缓存返回 null（调用方据此跳过乐观位，
  /// 不凭空造一个只有单条的列表——那会让云端其余条目在回包前消失）。
  List<Map<String, dynamic>>? _cachedRows(SwrCache cache, String date) {
    final cached = cache.read<List<Map<String, dynamic>>>('records.$date');
    return cached == null ? null : List<Map<String, dynamic>>.from(cached);
  }

  Map<String, dynamic> _optimisticAdd(String date, Map<String, dynamic> body) {
    // 十字段形态逐字对齐 H5 temp（js/app.js:664-668）：portion=食物 meta、
    // image 缺省补空串、三素缺省补 0。
    final temp = <String, dynamic>{
      'id': 'tmp_${DateTime.now().millisecondsSinceEpoch}',
      'meal': body['meal'] ?? '',
      'name': body['name'] ?? '',
      'portion': body['portion'] ?? '',
      'kcal': body['kcal'] ?? 0,
      'emoji': body['emoji'] ?? '',
      'image': body['image'] ?? '',
      'protein': body['protein'] ?? 0,
      'carb': body['carb'] ?? 0,
      'fat': body['fat'] ?? 0,
    };
    final cache = _ref.read(swrCacheProvider);
    final rows = _cachedRows(cache, date);
    if (rows != null) {
      rows.add(temp);
      cache.write('records.$date', rows);
    }
    _patchSummary(cache, date, temp, sign: 1);
    _holdDay(cache, date); // 提交前的一切后台刷新回包一律作废（见 SwrCache.hold）
    _invalidateDay(date);
    return temp;
  }

  /// 回滚一次乐观加：按 temp.id 摘除，并把四项减回去（sign 传 1 表示原为加）。
  void _removeOptimistic(
      String date, Map<String, dynamic> temp, {required int sign}) {
    final cache = _ref.read(swrCacheProvider);
    final rows = _cachedRows(cache, date);
    if (rows != null) {
      rows.removeWhere((r) => r['id'] == temp['id']);
      cache.write('records.$date', rows);
    }
    _patchSummary(cache, date, temp, sign: -sign);
  }

  /// 环/宏量的乐观增减。**只动 kcal 与三素，target/water 原样保留**
  /// （≙ H5 :670-673 的四行；target 由云函数按档案派生，端上不得改）。
  /// 当日 summary 未缓存时直接跳过：宁可少一次乐观刷新，也不造出
  /// target=0 的假汇总。
  void _patchSummary(SwrCache cache, String date, Map<String, dynamic> row,
      {required int sign}) {
    final key = 'summary.$date';
    final base = cache.read<Summary>(key);
    if (base == null) return;
    num d(Object? v) => (v is num ? v : 0) * sign;
    cache.write(
      key,
      Summary(
        kcal: base.kcal + d(row['kcal']),
        target: base.target,
        carb: base.carb + d(row['carb']),
        protein: base.protein + d(row['protein']),
        fat: base.fat + d(row['fat']),
        water: base.water,
      ),
    );
  }

  /// 写路径统一收口：**保留**缓存键、只让 provider 重建（重建即「先播种乐观值，
  /// 后台对账覆盖」）。M9 旧口径在此删键，代价是写后整卡回骨架等一个 400ms 往返
  /// ——现改由乐观写本身保证「不会播种到写前旧数」，键无须删。
  void _invalidateDay(String date) {
    _ref.invalidate(recordsProvider(date));
    _ref.invalidate(summaryProvider(date));
  }

  /// 写操作在途期间挂起该日两键：其间任何后台刷新回包一律不得落缓存。
  /// 为什么必须有它：删一笔提交**之前**发起的刷新，服务端此刻确实还留着那条记录
  /// （是合法读数，代次判据也判不出来），落缓存就表现为「删掉的行闪一下又回来」
  /// 约一个往返（~400ms）——实测复现见 test/record/optimistic_write_test.dart ④。
  void _holdDay(SwrCache cache, String date) {
    cache.hold('records.$date');
    cache.hold('summary.$date');
  }

  /// 提交/回滚后的统一收口（放 finally）：解挂 → stamp（作废挂起期间到期的在途
  /// 读数）→ 重建 provider 对账。异常路径同样收口，绝不留悬挂的 hold。
  void _reconcileDay(String date) {
    final cache = _ref.read(swrCacheProvider);
    for (final key in ['records.$date', 'summary.$date']) {
      cache.release(key);
      cache.stamp(key);
    }
    _invalidateDay(date);
  }
}

final recordControllerProvider =
    Provider<RecordController>((ref) => RecordController(ref));
