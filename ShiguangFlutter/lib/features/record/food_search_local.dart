// ShiguangFlutter/lib/features/record/food_search_local.dart
// M11-T1：搜索的端上过滤纯函数与缓存键。
//
// 为什么要有这一层：网关单程 ~400ms 是 M9 §0 实测地板，而旧实现每敲一个词发
// 一次请求（打字 3 词＝3 次往返），且服务端每次还要再串 2 趟数据库
// （index.js:54 getOrCreateProfile + :68 custom_foods 查询）。食物库总量只有
// 内置 35 条 + 自定义 ≤200 条，端上一次装得下——故改为「开层拉一份空词快照，
// 打字纯本地过滤」。数据源仍是云端搜索路由，**不在 Dart 侧建食物副本**，
// 因此不存在 foods.js ↔ Dart 漂移。
//
// 餐次维为什么不做在端上：搜索结果元素不带 meals（index.js:81-92 手工拼装），
// 端上无从复判；而空词请求传 meal 时服务端已把两支都过滤完（:60 内置、:72
// 自定义）。故快照按餐次各取一份，键含 meal。

import '../../data/swr_cache.dart';

/// 搜索 family 键：record 类型自带结构相等，keyword+meal 任一变化即新查询
/// （对齐 H5：改关键词或切餐次都重新 fillSheetResults，js/app.js:697-700、
/// 708-712）。
typedef FoodQuery = ({String keyword, String meal});

/// 空词快照键（按餐次一份）。
const String foodsFullCachePrefix = 'foods.full';
String foodsFullCacheKey(String meal) => '$foodsFullCachePrefix.$meal';

/// 逐词结果键前缀（端上过滤后仍走 SWR 播种：回删/重打同词零延迟零请求）。
const String searchCachePrefix = 'search';
String searchCacheKey(FoodQuery q) =>
    '$searchCachePrefix.${q.meal}.${q.keyword}';

/// 服务端 `db.collection('custom_foods').where(...).limit(20)`（index.js:68）
/// 意味着空词快照里的自定义项最多 20 条；一旦真的取满 20，第 21 条以后不在
/// 快照内，端上过滤会**静默搜不到**——此时回落云端逐词搜索（宁可慢，不可漏）。
bool foodLibraryLooksTruncated(List<Map<String, dynamic>> full) =>
    full.where((f) => isCustomFoodId(f['id'])).length >= 20;

/// 搜索结果里的自定义食物 id 形如 `cf_<docId>`（index.js:82）。
bool isCustomFoodId(Object? id) => '${id ?? ''}'.startsWith('cf_');

/// 端上关键词过滤。逐字复刻云端的匹配语义：
/// - 内置：`f.name.includes(kw)`——**区分大小写**（index.js:60）
/// - 自定义：`db.RegExp({regexp: esc, options: 'i'})`——**不区分大小写**
///   （index.js:64-66，转义后按字面匹配）
/// 入参 [full] 必须是同一 meal 的快照（餐次维已在服务端做完），返回保持
/// 「内置在前、自定义在后」的云端原序。
List<Map<String, dynamic>> filterFoodLibrary({
  required List<Map<String, dynamic>> full,
  required String keyword,
}) {
  final kw = keyword.trim(); // ≙ index.js:53 `(keyword || "").trim()`
  if (kw.isEmpty) return full;
  final lowerKw = kw.toLowerCase();
  final out = <Map<String, dynamic>>[];
  for (final f in full) {
    final name = f['name'] as String? ?? '';
    final hit = isCustomFoodId(f['id'])
        ? name.toLowerCase().contains(lowerKw)
        : name.contains(kw);
    if (hit) out.add(f);
  }
  return out;
}

/// 食物库发生变更后清两份内存缓存（快照 + 逐词结果）。provider 侧的失效由
/// record_controller 的 `invalidateFoodLibrary` 负责（本文件保持纯函数层，
/// 不反向依赖 provider 定义）。
void clearFoodLibraryCache(SwrCache cache) {
  cache.invalidatePrefix('$foodsFullCachePrefix.');
  cache.invalidatePrefix('$searchCachePrefix.');
}
