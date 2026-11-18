// ShiguangFlutter/lib/data/health_api.dart
// HealthAPI 业务方法（M2 + M3-T2 报告所需子集）。契约唯一权威源：js/api.js 的
// HealthAPI（274-358 行）与 ROUTES（59-98 行），并由仓库根
// contract/fixtures/diet-core.json 双端契约测试锁定（本侧
// test/data/contract_test.dart、H5 侧 tests/contract.test.js）。
// 方法名/入参/envelope{path,method,params,body} 与 js 一一对应；
// 数组响应路由（mealRecords/searchFoods/builtinFoods）走 ApiClient.callValue，
// 对齐 js/api.js:264 直接 return data（数组原样返回）。

import 'ai_provider_store.dart';
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

  /// 每日目标（js/api.js:278 setGoal：body 即 goal 对象。H5 两支调用面：
  /// app.js:1456 **单键** {targetWeight}（M7-T5 目标体重弹层）/ app.js:1715
  /// 双键 {dailyKcal,targetWeight}（M5-T6 syncTarget）。null 键剥离 ≙ js 侧
  /// 该键 undefined 序列化不发（同 logWeight :39 先例）；云端 index.js:249-250
  /// 按 truthy 分支部分更新——只发 targetWeight 时 dailyKcal 不动，回包 {ok}）
  Future<Map<String, dynamic>> setGoal({
    num? dailyKcal,
    num? targetWeight,
  }) => _client.call('/user/goal',
    method: 'PUT',
    body: <String, dynamic>{
      'dailyKcal': ?dailyKcal,
      'targetWeight': ?targetWeight,
    },
  );

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

  /// 食物频次（M12-③）：云函数按 uid 全史聚合 {counts:{菜名:次数}, complete}，
  /// 一次往返取代原先的逐日回填（30 请求）。
  Future<Map<String, dynamic>> getFoodFreq() =>
      _client.call('/diet/records/freq');

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

  /* ---------- 运动（M6-T1；路由 js/api.js:75-77） ---------- */

  /// 某日运动记录（js/api.js:325 getExercises；响应数组 → callValue。
  /// 注意：云端不回 createdAt（index.js:347-350），次数型记录刷新后 isRepRecord
  /// 判别退化按分钟显示——H5 同病，bug-for-bug 保留，禁改云）
  Future<List<dynamic>> getExercises(String date) async {
    final data = await _client.callValue('/diet/exercises',
        params: <String, dynamic>{'date': date});
    return data is List ? data : const <dynamic>[];
  }

  /// 新增运动记录（js/api.js:326 addExercise 调用面：{date,key,name,emoji,amount,unit,kcal}；
  /// 云端 kcal 取整后为 0 时回 {ok:false,message} 而非 HTTP 错，调用层判 ok）
  Future<Map<String, dynamic>> addExercise(Map<String, dynamic> record) =>
      _client.call('/diet/exercises', method: 'POST', body: record);

  /// 窗口内已入库的运动去重键（手环同步幂等：重装/多包后合并账本用）。
  /// 返回 externalIds + 内容签名（date|key|amount|kcal，兜底老数据）。
  Future<({Set<String> externalIds, Set<String> signatures})>
      getExerciseExistingKeys(List<String> dates) async {
    final data = await _client.callValue('/diet/exercises/external-ids',
        params: <String, dynamic>{'dates': dates.join(',')});
    Set<String> listOf(String key) {
      if (data is! Map) return const <String>{};
      final v = data[key];
      if (v is! List) return const <String>{};
      return v.map((e) => '$e').where((s) => s.isNotEmpty).toSet();
    }

    return (externalIds: listOf('externalIds'), signatures: listOf('signatures'));
  }

  /// 删除运动记录（js/api.js:327 deleteExercise：DELETE /diet/exercises/:id）
  Future<Map<String, dynamic>> deleteExercise(String id) =>
      _client.call('/diet/exercises/:id',
          method: 'DELETE', params: <String, dynamic>{'id': id});

  /* ---------- 喝水目标（M6-T1；路由 js/api.js:65 waterGoal） ---------- */

  /// 喝水目标（js/api.js:282 setWaterGoal：body {waterGoalMl}；
  /// 云端 index.js:257 按 [800,3000] 截断后回显 {ok,waterGoalMl}——200ml
  /// 对齐是 H5 步进器 UI 职责（app.js:1653-1654），云端不归一）
  Future<Map<String, dynamic>> setWaterGoal(num waterGoalMl) =>
      _client.call('/user/water-goal',
          method: 'PUT', body: <String, dynamic>{'waterGoalMl': waterGoalMl});

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

  /* ---------- 拍照识菜（M13；云函数 /ai/food-scan 与 /foods/custom/upsert） ---------- */

  /// 拍照识菜（M13）：云函数调 DeepSeek，返回 {dish,confidence,per100,note,quota}
  /// （自定义通道无 quota 字段——配额只在内置通道计数）。
  /// 云端函数部署后 60s（spec §2.5），客户端按请求放宽到 30s（其它路由仍默认 15s）。
  ///
  /// M14：可选自带 provider；不可用/未配置时**整键省略**，回退内置通道。
  /// 不能发空对象——云端收到 `provider: {}` 会报「自定义模型配置不完整」。
  Future<Map<String, dynamic>> scanFood(
    String imageDataUrl, {
    AiProviderConfig? provider,
    String? hint,
  }) {
    final h = (hint ?? '').trim();
    return _client.call(
      '/ai/food-scan',
      method: 'POST',
      body: <String, dynamic>{
        'image': imageDataUrl,
        // 菜名提示：空白即整键省略，云端按无提示走原逻辑
        if (h.isNotEmpty) 'hint': h.length > 30 ? h.substring(0, 30) : h,
        if (provider != null && provider.isUsable)
          'provider': <String, dynamic>{
            'id': provider.id,
            'model': provider.model,
            'key': provider.key,
          },
      },
      timeout: const Duration(seconds: 30),
    );
  }

  /// 按菜名估算（M15）：云函数 /ai/food-estimate，返回
  /// {ok,dish,per100,note,quota}；provider 口径与 scanFood 完全一致
  /// （可用才整键带，未配置/半成品整键省略）。服务端 12s 超时，客户端放宽到 20s。
  Future<Map<String, dynamic>> estimateFood(
    String name, {
    AiProviderConfig? provider,
  }) =>
      _client.call(
        '/ai/food-estimate',
        method: 'POST',
        body: <String, dynamic>{
          'name': name,
          if (provider != null && provider.isUsable)
            'provider': <String, dynamic>{
              'id': provider.id,
              'model': provider.model,
              'key': provider.key,
            },
        },
        timeout: const Duration(seconds: 20),
      );

  /// 包装营养成分表识别（M16）：云函数读图后返回
  /// `{ok,name,brand,unit,servingGrams,per100,note,verify,quota}`。
  /// 图片只用于识别、不落库；provider 口径与 [scanFood] 一致。
  Future<Map<String, dynamic>> scanNutritionLabel(
    String imageDataUrl, {
    AiProviderConfig? provider,
    String? hint,
  }) {
    final h = (hint ?? '').trim();
    return _client.call(
      '/ai/nutrition-label',
      method: 'POST',
      body: <String, dynamic>{
        'image': imageDataUrl,
        if (h.isNotEmpty) 'hint': h.length > 30 ? h.substring(0, 30) : h,
        if (provider != null && provider.isUsable)
          'provider': <String, dynamic>{
            'id': provider.id,
            'model': provider.model,
            'key': provider.key,
          },
      },
      timeout: const Duration(seconds: 35),
    );
  }

  /* ---------- M16：条码查询 + 描述一餐 ---------- */

  /// 条码查询（M16）。云端顺序：用户自定义绑定 → OFF 缓存 → OFF 实时。
  /// 返回 `{ok, found, source, food?, message?, code?}`；`found=false` 是正常
  /// 业务结果（条码未收录），不是异常。只有 live OFF 才计每日配额。
  Future<Map<String, dynamic>> lookupBarcode(String code) => _client.call(
        '/foods/barcode',
        params: <String, dynamic>{'code': code},
        timeout: const Duration(seconds: 20),
      );

  /// 描述一餐（M16）：模型只抽食物名与份量，云端再逐条命中内置/自定义库，
  /// 返回 `{ok, items:[{query,quantity,unit,portion,match}], channel, quota}`。
  /// provider 口径与 [scanFood] 完全一致：可用才整键带，未配置整键省略。
  Future<Map<String, dynamic>> parseMealText(
    String text, {
    AiProviderConfig? provider,
    String? meal,
  }) =>
      _client.call(
        '/ai/meal-parse',
        method: 'POST',
        body: <String, dynamic>{
          'text': text,
          if (meal != null && meal.isNotEmpty) 'meal': meal,
          if (provider != null && provider.isUsable)
            'provider': <String, dynamic>{
              'id': provider.id,
              'model': provider.model,
              'key': provider.key,
            },
        },
        timeout: const Duration(seconds: 25),
      );

  /// AI 饮食助手（P3）：云端默认 DeepSeek 主通道、扣子备用，返回
  /// {ok, reply, conversationId?, channel?}；服务端最坏两条通道约 27s，客户端放宽到 30s。
  /// 今日摘要由云端按 uid 取数；[history] 传最近几轮（user/assistant），
  /// DeepSeek 没有服务端会话，多轮上下文靠它补。
  Future<Map<String, dynamic>> cozeChat(
    String message, {
    String? conversationId,
    bool useTodaySummary = true,
    String? date,
    List<Map<String, String>>? history,
  }) =>
      _client.call(
        '/ai/coze-chat',
        method: 'POST',
        body: <String, dynamic>{
          'message': message,
          if (conversationId != null && conversationId.isNotEmpty)
            'conversationId': conversationId,
          'useTodaySummary': useTodaySummary,
          if (date != null && date.isNotEmpty) 'date': date,
          if (history != null && history.isNotEmpty) 'history': history,
        },
        timeout: const Duration(seconds: 30),
      );

  /// 扫码入库（M13）：按菜名 upsert，回 {ok,id|skipped,emoji}
  Future<Map<String, dynamic>> upsertCustomFood(Map<String, dynamic> food) =>
      _client.call('/foods/custom/upsert', method: 'POST', body: food);

  /* ---------- 我的食物库管理（M7-T4；路由 js/api.js:81-85） ---------- */

  /// 自定义食物全量列表（js/api.js:333 listCustomFoods；GET /foods/custom，
  /// 响应数组 → callValue。元素 12 键平铺，云端按 index.js:299-305：
  /// id 为裸 _id（cf_ 前缀只出现在搜索结果 id，index.js:82））
  Future<List<dynamic>> listCustomFoods() async {
    final data = await _client.callValue('/foods/custom');
    return data is List ? data : const <dynamic>[];
  }

  /// 改自定义食物餐次归类（js/api.js:335 setCustomFoodMeals：
  /// PUT /foods/custom/:id，body {meals}；云端白名单过滤
  /// breakfast/lunch/dinner/snack 截 4，回 {ok,id,meals}，index.js:309-316）
  Future<Map<String, dynamic>> setCustomFoodMeals(
    String id,
    List<String> meals,
  ) => _client.call(
    '/foods/custom/:id',
    method: 'PUT',
    params: <String, dynamic>{'id': id},
    body: <String, dynamic>{'meals': meals},
  );

  /// 删除自定义食物（js/api.js:334 deleteCustomFood：DELETE /foods/custom/:id，
  /// 回 {ok:true}，index.js:319-323；id 为裸 _id）
  Future<Map<String, dynamic>> deleteCustomFood(String id) =>
      _client.call('/foods/custom/:id',
          method: 'DELETE', params: <String, dynamic>{'id': id});

  /// 设置内置库「已移除」id 列表（js/api.js:337 setHiddenFoods：
  /// PUT /foods/hidden，body {ids} **全量替换**（云端整列覆写
  /// profile.hiddenFoods，index.js:336-341），回 {ok,ids}）
  Future<Map<String, dynamic>> setHiddenFoods(List<String> ids) =>
      _client.call('/foods/hidden',
          method: 'PUT', body: <String, dynamic>{'ids': ids});

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
