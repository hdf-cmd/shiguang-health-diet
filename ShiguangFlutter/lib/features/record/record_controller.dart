// ShiguangFlutter/lib/features/record/record_controller.dart
// 记录页数据层（M2 Task 9）。recordsProvider/summaryProvider/todayProvider/
// healthApiProvider 直接复用 home_controller 的 family 实例（同一 Provider
// 对象同参数即同一缓存，记录页与首页天然共享，不重建）。
// 行为权威源 js/app.js：defaultMeal 603-609、搜索弹层取数 628-651、
// 添加/删除后「静默对账云端」refreshToday+loadRecordPage（572-573、683）。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/swr_cache.dart' show swrInvalidate;
import '../home/home_controller.dart';
import 'food_freq.dart';

// 记录页/弹层只 import 本文件即可拿到复用的地基 provider。
export '../home/home_controller.dart'
    show healthApiProvider, recordsProvider, summaryProvider, todayProvider;

/// 按当前小时智能默认餐次。逐分支镜像 js/app.js:603-609 defaultMeal：
/// <10 早餐 / <15 午餐 / <21 晚餐 / 其余零食。
/// 小时由调用方注入（DateTime.now().hour 或测试固定值），保证可测。
String defaultMealAt(int hour) {
  if (hour < 10) return 'breakfast';
  if (hour < 15) return 'lunch';
  if (hour < 21) return 'dinner';
  return 'snack';
}

/// searchProvider family 键：record 类型自带结构相等，keyword+meal 任一变化即新查询
/// （对齐 H5：改关键词或切餐次都重新 fillSheetResults，js/app.js:697-700、708-712）。
typedef FoodQuery = ({String keyword, String meal});

/// 食物搜索结果（HealthAPI.searchFoods → 契约 searchFoods 数组：
/// {id,name,meta,kcal,emoji,image,meals,protein,carb,fat,per100?,baseG?,unit?}）。
/// meal 恒传当前选中餐次（H5 亦恒传 state.mealChosen，js/app.js:633）。
/// 常吃排序（方案 B）：按 foodFreqProvider 计数稳定降序，计数更新自动重排。
final searchProvider = FutureProvider.autoDispose
    .family<List<Map<String, dynamic>>, FoodQuery>((ref, q) async {
  final list =
      await ref.watch(healthApiProvider).searchFoods(q.keyword, q.meal);
  final mapped = list
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList(growable: false);
  return sortFoodByFreq(mapped, ref.watch(foodFreqProvider));
});

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
  Future<bool> addRecord(
    String date,
    Map<String, dynamic> record, {
    required String pendingKey,
  }) async {
    if (!_inFlight.add(pendingKey)) return false; // 连点兜底：同键第二次不进网络层
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
      _syncDay(date);
      return true;
    } finally {
      _inFlight.remove(pendingKey);
    }
  }

  Future<void> deleteRecord(String date, String id) async {
    await _ref.read(healthApiProvider).deleteFoodRecord(id);
    _syncDay(date);
  }

  void _syncDay(String date) {
    swrInvalidate(_ref, 'records.$date'); // M9：写后删键，防回访播种写前旧数
    swrInvalidate(_ref, 'summary.$date');
    _ref.invalidate(recordsProvider(date));
    _ref.invalidate(summaryProvider(date));
  }
}

final recordControllerProvider =
    Provider<RecordController>((ref) => RecordController(ref));
