// ShiguangFlutter/lib/data/health_api.dart
// HealthAPI 业务方法（M2 所需子集）。契约唯一权威源：js/api.js 的
// HealthAPI（274-358 行）与 ROUTES（59-98 行），并由仓库根
// contract/fixtures/diet-core.json 双端契约测试锁定（本侧
// test/data/contract_test.dart、H5 侧 tests/contract.test.js）。
// 方法名/入参/envelope{path,method,params,body} 与 js 一一对应；
// 数组响应路由（mealRecords/searchFoods/builtinFoods）走 ApiClient.callValue，
// 对齐 js/api.js:264 直接 return data（数组原样返回）。

import 'api_client.dart';

class HealthApi {
  HealthApi(this._client);

  final ApiClient _client;

  /// js TODAY 语义（js/api.js:104-106 的 toISOString().slice(0,10)，UTC 日历日）。
  static String _todayUtc() =>
      DateTime.now().toUtc().toIso8601String().substring(0, 10);

  /* ---------- 用户 ---------- */

  /// 用户资料（js/api.js:276 getProfile）
  Future<Map<String, dynamic>> getProfile() =>
      _client.call('/user/profile');

  /// 身高体重 BMI（路由表 js/api.js:68 bodyMetrics；HealthAPI 未暴露同名方法，
  /// Dart 侧按 M2 需要补齐，GET /user/body-metrics）
  Future<Map<String, dynamic>> getBodyMetrics() =>
      _client.call('/user/body-metrics');

  /// 记录每日体重（js/api.js:284 logWeight：body {weightKg, date}；
  /// date 省略时 JSON 序列化丢键，云端按 index.js:561 回落当日）
  Future<Map<String, dynamic>> logWeight(num weightKg, [String? date]) =>
      _client.call('/user/weight',
          method: 'POST',
          body: <String, dynamic>{
            'weightKg': weightKg,
            'date': ?date, // null 时丢键（对齐 js JSON.stringify 对 undefined 的剥离）
          });

  /* ---------- 饮食记录 ---------- */

  /// 某日热量与营养素汇总（js/api.js:320 getDailySummary）
  Future<Map<String, dynamic>> getDailySummary(String date) =>
      _client.call('/diet/summary', params: <String, dynamic>{'date': date});

  /// 某日三餐记录（js/api.js:321 getMealRecords；响应是数组 → callValue）
  Future<List<dynamic>> getMealRecords(String date) async {
    final data =
        await _client.callValue('/diet/records', params: <String, dynamic>{'date': date});
    return data is List ? data : const <dynamic>[];
  }

  /// 新增一条饮食记录（js/api.js:322 addFoodRecord：record 原样进 body）
  Future<Map<String, dynamic>> addFoodRecord(Map<String, dynamic> record) =>
      _client.call('/diet/records', method: 'POST', body: record);

  /// 删除饮食记录（js/api.js:323 deleteFoodRecord：DELETE /diet/records/:id）
  Future<Map<String, dynamic>> deleteFoodRecord(String id) =>
      _client.call('/diet/records/:id',
          method: 'DELETE', params: <String, dynamic>{'id': id});

  /// 记一杯水（js/api.js:324 addWater：body {date: date||TODAY, delta}）
  Future<Map<String, dynamic>> addWater(int delta, [String? date]) =>
      _client.call('/diet/water',
          method: 'POST',
          body: <String, dynamic>{
            'date': date ?? _todayUtc(),
            'delta': delta,
          });

  /* ---------- 食物库 ---------- */

  /// 食物搜索（js/api.js:330 searchFoods(keyword, meal)；meal 省略时
  /// JSON 序列化丢键，云端按 index.js:60 不做餐次过滤；响应数组 → callValue）
  Future<List<dynamic>> searchFoods(String keyword, [String? meal]) async {
    final data = await _client.callValue('/foods/search',
        params: <String, dynamic>{
          'keyword': keyword,
          'meal': ?meal, // null 时丢键（对齐 js：params.meal undefined 序列化剥离）
        });
    return data is List ? data : const <dynamic>[];
  }

  /// 内置食物库（含 hidden 标记）（js/api.js:336 getBuiltinFoods；响应数组）
  Future<List<dynamic>> getBuiltinFoods() async {
    final data = await _client.callValue('/foods/builtin');
    return data is List ? data : const <dynamic>[];
  }
}
