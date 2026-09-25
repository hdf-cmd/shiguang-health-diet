// ShiguangFlutter/lib/features/home/home_controller.dart
// 首页数据层 riverpod provider（M2 Task 8）。
// 组合根模式对齐 auth_state.dart：healthApiProvider 默认走真实链路
// （ApiClient ← auth_state.apiClientProvider），main() 显式构造注入，
// 测试只 override healthApiProvider 即可全链路换桩（见 test/stubs/stub_health_api.dart）。

import 'package:flutter_riverpod/flutter_riverpod.dart';

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
