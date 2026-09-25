// ShiguangFlutter/test/stubs/stub_health_api.dart
// 测试共用桩 HealthApi（home 相关 widget 测试用，零网络）。
// 非 *_test.dart 后缀，不会被 flutter test 当作独立用例文件执行。
//
// 桩只需要 getDailySummary / getMealRecords 两个方法；其余成员经
// noSuchMethod 兜底抛 UnsupportedError——这样 HealthApi 之后新增方法时
// 桩不用跟着改（implements 场景下分析器对显式声明 noSuchMethod 豁免
// missing_override 检查）。
import 'package:shiguang_flutter/data/api_client.dart';
import 'package:shiguang_flutter/data/health_api.dart';

class StubHealthApi implements HealthApi {
  StubHealthApi({
    this.summary,
    this.records,
    this.summaryError,
    this.recordsError,
    this.foods,
    this.searchError,
  });

  /// 成功返回体（null 时按全零汇总/空记录处理）
  Map<String, dynamic>? summary;
  List<dynamic>? records;

  /// 非空 → 对应方法抛该异常（可在测试中途清空，模拟"重试后成功"）
  ApiException? summaryError;
  ApiException? recordsError;

  /// 调用次数：验证重试确实是重新取数，不是本地缓存翻牌
  int summaryCalls = 0;
  int recordsCalls = 0;

  /* ---------- T9 记录页：search / add / delete ---------- */

  /// searchFoods 成功返回体（null → 空数组，模拟"没找到"）
  List<dynamic>? foods;
  ApiException? searchError;
  int searchCalls = 0;
  String? lastSearchKeyword;
  String? lastSearchMeal;

  /// addFoodRecord 收到的 body（按调用顺序收集，测试断言契约字段）
  final List<Map<String, dynamic>> addBodies = <Map<String, dynamic>>[];
  ApiException? addError;

  /// deleteFoodRecord 收到的 id（按调用顺序收集）
  final List<String> deletedIds = <String>[];
  ApiException? deleteError;

  /// 契约 fixture（contract/fixtures/diet-core.json）的字段形状：
  /// summary → {kcal,target,carb,protein,fat,water}
  static Map<String, dynamic> summaryMap({
    num kcal = 0,
    num target = 1679,
    num carb = 0,
    num protein = 0,
    num fat = 0,
    num water = 0,
  }) =>
      {'kcal': kcal, 'target': target, 'carb': carb, 'protein': protein, 'fat': fat, 'water': water};

  /// records 单条 → {id,meal,name,portion,kcal,emoji,image,protein,carb,fat}
  static Map<String, dynamic> recordMap({
    required String id,
    required String meal,
    required String name,
    required String portion,
    required num kcal,
  }) =>
      {
        'id': id,
        'meal': meal,
        'name': name,
        'portion': portion,
        'kcal': kcal,
        'emoji': '',
        'image': '',
        'protein': 0,
        'carb': 0,
        'fat': 0,
      };

  @override
  Future<Map<String, dynamic>> getDailySummary(String date) async {
    summaryCalls++;
    if (summaryError != null) throw summaryError!;
    return summary ?? summaryMap();
  }

  @override
  Future<List<dynamic>> getMealRecords(String date) async {
    recordsCalls++;
    if (recordsError != null) throw recordsError!;
    return records ?? const <dynamic>[];
  }

  @override
  Future<List<dynamic>> searchFoods(String keyword, [String? meal]) async {
    searchCalls++;
    lastSearchKeyword = keyword;
    lastSearchMeal = meal;
    if (searchError != null) throw searchError!;
    return foods ?? const <dynamic>[];
  }

  @override
  Future<Map<String, dynamic>> addFoodRecord(Map<String, dynamic> record) async {
    addBodies.add(Map<String, dynamic>.from(record));
    if (addError != null) throw addError!;
    return <String, dynamic>{'id': 'rec_added_${addBodies.length}', ...record};
  }

  @override
  Future<Map<String, dynamic>> deleteFoodRecord(String id) async {
    deletedIds.add(id);
    if (deleteError != null) throw deleteError!;
    return <String, dynamic>{'ok': true};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('StubHealthApi 未实现：${invocation.memberName}');
}
