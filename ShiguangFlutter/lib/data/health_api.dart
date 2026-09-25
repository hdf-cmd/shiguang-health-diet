// ShiguangFlutter/lib/data/health_api.dart
// HealthAPI 业务方法（M2 + M3-T2 报告所需子集）。契约唯一权威源：js/api.js 的
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

  /// 修改资料/身体档案（js/api.js:277 updateProfile：部分字段浅合并进用户文档，
  /// 云函数按 key 覆写——T5 发 {nickname,signature}、T6 发 body 六字段+bmi，互不越界）
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) =>
      _client.call('/user/profile', method: 'PUT', body: data);

  /// 每日目标（js/api.js:278 setGoal：body 即 {dailyKcal, targetWeight}）
  Future<Map<String, dynamic>> setGoal(num dailyKcal, num targetWeight) =>
      _client.call('/user/goal',
          method: 'PUT',
          body: <String, dynamic>{
            'dailyKcal': dailyKcal,
            'targetWeight': targetWeight,
          });

  /// 上传头像 dataURL（js/api.js:280 updateAvatar：body {data}，云端原样存字符串）
  Future<Map<String, dynamic>> updateAvatar(String dataUrl) =>
      _client.call('/user/avatar',
          method: 'PUT', body: <String, dynamic>{'data': dataUrl});

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

  /// 新增自定义食物（js/app.js:1241 调用面：{name,kcal,grams,unit,meals,protein,carb,fat,portion,image}）
  Future<Map<String, dynamic>> addCustomFood(Map<String, dynamic> food) =>
      _client.call('/foods/custom', method: 'POST', body: food);

  /* ---------- 报告（M3-T2；路由 js/api.js:92-94，响应契约 index.js:462-546/579-601） ---------- */

  /// 本周（周一起）7 天柱状 + 宏量达标率（js/api.js:348 getWeekReport；
  /// rates 云端封顶 100；offset 往回推周数，缺省 0 = 本周）
  Future<Map<String, dynamic>> getWeekReport({int offset = 0}) => _client
      .call('/report/week', params: <String, dynamic>{'offset': offset});

  /// 月报（js/api.js:350 getMonthReport；kcal 为各周有记录日的日均，
  /// days=有记录天数，total=月总热量，isWeek 恒 false）
  Future<Map<String, dynamic>> getMonthReport({int offset = 0}) => _client
      .call('/report/month', params: <String, dynamic>{'offset': offset});

  /// 体重趋势最近 7 条（js/api.js:351 getWeightTrend；无日志时云端回推
  /// 7 个重复当前体重。响应可能带 bodyFat/muscle——v1.3.1 体成分下线，不消费）
  Future<Map<String, dynamic>> getWeightTrend() =>
      _client.call('/report/weight-trend');
}
