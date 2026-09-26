// ShiguangFlutter/test/stubs/stub_health_api.dart
// 测试共用桩 HealthApi（home 相关 widget 测试用，零网络）。
// 非 *_test.dart 后缀，不会被 flutter test 当作独立用例文件执行。
//
// 桩只需要 getDailySummary / getMealRecords 两个方法；其余成员经
// noSuchMethod 兜底抛 UnsupportedError——这样 HealthApi 之后新增方法时
// 桩不用跟着改（implements 场景下分析器对显式声明 noSuchMethod 豁免
// missing_override 检查）。
import 'dart:async';

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
    this.weekReport,
    this.weekError,
    this.monthReport,
    this.monthError,
    this.weightTrend,
    this.weightTrendError,
    this.summaryGate,
    this.recordsGate,
    this.bodyMetrics,
    this.bodyError,
    this.logWeightError,
    this.profile,
    this.profileError,
    this.exercisesByDate,
    this.exerciseError,
    this.addExerciseError,
    this.deleteExerciseError,
    this.waterGoal,
    this.setWaterGoalError,
    this.waterCupsByDate,
    this.addWaterError,
    this.summaryByDate,
    this.libCustomFoods,
    this.libBuiltins,
  });

  /// 成功返回体（null 时按全零汇总/空记录处理）
  Map<String, dynamic>? summary;
  List<dynamic>? records;

  /// M7-T3：非空时优先按请求 date 取该日汇总（缺日期落 [summary] 再落默认档）。
  /// 跨日用例需要「今天/昨天 summary 不同值」才能证水卡显的是当日真值
  /// （同法 exercisesByDate）。
  Map<String, Map<String, dynamic>>? summaryByDate;

  /// 非空 → 对应方法抛该异常（可在测试中途清空，模拟"重试后成功"）
  ApiException? summaryError;
  ApiException? recordsError;

  /// 调用次数：验证重试确实是重新取数，不是本地缓存翻牌
  int summaryCalls = 0;
  int recordsCalls = 0;

  /// M7-T1：按调用顺序收到的 date（入参原样）。首页 plate-head ‹ › 切日期后，
  /// 五卡应以新 date 重新取数——只数次数看不出「请求的是哪一天」（用例
  /// home_plate_date_test 的 date 序列断言）。
  final List<String> summaryDates = <String>[];
  final List<String> recordDates = <String>[];
  final List<String> exerciseDates = <String>[];

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

  /// 非空 → addFoodRecord 先 await 它再返回（模拟慢网 pending，验证按钮防重）
  Completer<void>? addGate;

  /// M3-T7：非空 → getDailySummary/getMealRecords 先 await 它再返回
  /// （模拟慢网 pending，验证首页加载期骨架与全空态可分辨）
  Completer<void>? summaryGate;
  Completer<void>? recordsGate;

  /* ---------- M5-T5 资料卡：getProfile / updateProfile / updateAvatar ---------- */

  /// getProfile 成功返回体（null → [profileMap] 默认档，键集锁自
  /// contract/fixtures/diet-core.json routes[profile].responseFields）。
  /// 凡挂 ProfileScreen 的既有用例经此默认档渲染资料头，不再触 noSuchMethod。
  Map<String, dynamic>? profile;
  ApiException? profileError;
  int profileCalls = 0;

  /// updateProfile 收到的 data（按调用顺序收集；成功时按云端语义并入，
  /// ≙ api-diet index.js:213-232：nickname/signature 写顶层，身体六字段写
  /// 文档顶层后经 profileToClient(:132-149) 以 p.body 嵌套返回——桩直接把
  /// body 键并进 p['body']；客户端裸 bmi 键不收，仅 h/w 双在时重算（:222-224 同款）
  final List<Map<String, dynamic>> profileUpdateBodies =
      <Map<String, dynamic>>[];
  ApiException? profileUpdateError;

  /* ---------- M5-T6 身体卡：setGoal（PUT /user/goal） ---------- */

  /// setGoal 收到的 {dailyKcal,targetWeight}（按调用顺序收集）/ 次数 / 注错。
  /// 成功时写回 p['goal']，供「重取回真值」断言（≙ api-diet :246-252）。
  final List<Map<String, dynamic>> goalBodies = <Map<String, dynamic>>[];
  int goalCalls = 0;
  ApiException? setGoalError;

  /// updateAvatar 最近一次收到的 dataURL / 调用次数 / 注错
  String? lastAvatarData;
  int avatarCalls = 0;
  ApiException? avatarError;

  /* ---------- M4-T4 体重卡：getBodyMetrics / logWeight ---------- */

  /// getBodyMetrics 成功返回体（null → 契约默认档：H5 兜底 55kg）。
  /// 体重键名 weightKg（contract/fixtures/diet-core.json bodyMetrics；
  /// Dart 消费点 domain/models.dart BodyMetrics.fromMap 同键）。
  Map<String, dynamic>? bodyMetrics;
  ApiException? bodyError;
  int bodyCalls = 0;

  /// logWeight 收到的 (kg, date)（按调用顺序收集，测试断言契约入参）
  final List<({num kg, String? date})> weightLogs =
      <({num kg, String? date})>[];
  ApiException? logWeightError;

  /// 非空 → logWeight 先 await 它再返回（模拟慢网 pending）
  Completer<void>? logWeightGate;

  /* ---------- M5-T7 自定义食物：addCustomFood（POST /foods/custom） ---------- */

  /// addCustomFood 收到的 body（按调用顺序收集；契约 requestSample 十字键，
  /// 见 contract/fixtures/diet-core.json routes[addCustomFood]）/ 注错。
  /// 成功返回体 ≙ 云实返平铺 {ok,id,uid,name,...}（T2 登记），端上只消费
  /// 不校验，桩回 {ok:true,id} + 原 body 即可。
  final List<Map<String, dynamic>> customFoodBodies = <Map<String, dynamic>>[];
  ApiException? customFoodError;

  /// 非空 → addCustomFood 先 await 它再返回（模拟慢网，验证保存按钮防重）
  Completer<void>? customFoodGate;

  /* ---------- M6-T1 运动卡：getExercises / addExercise / deleteExercise ---------- */

  /// getExercises 成功返回体：按日期索引的运动记录列表（null/缺日期 → 空数组，
  /// ≙ 云 index.js:343-351 当日无记录回 []）。单条形状锁自 contract fixture
  /// routes[exercises].responseFields（云端不回 createdAt，见该条登记注）。
  Map<String, List<Map<String, dynamic>>>? exercisesByDate;
  ApiException? exerciseError;
  int exerciseCalls = 0;

  /// addExercise 收到的 record（按调用顺序收集；成功返回体 ≙ 云实返平铺
  /// {ok,id,uid,date,key,name,emoji,amount,unit,kcal,createdAt}）
  final List<Map<String, dynamic>> exerciseBodies = <Map<String, dynamic>>[];
  ApiException? addExerciseError;

  /// M7-T2：非空 → addExercise 先 await 它再走错误/成功支（钉「保存即态」：
  /// 挂住回包，测试在零网络等待下断 temp 行/合计/toast/关层，≙ waterGate 定式）
  Completer<void>? addExerciseGate;

  /// deleteExercise 收到的 id（按调用顺序收集）
  final List<String> deletedExerciseIds = <String>[];
  ApiException? deleteExerciseError;

  /// M7-T2：非空 → deleteExercise 先 await 它再走错误/成功支（钉删除乐观链：
  /// 挂住回包观测「行已摘+toast 已弹」窗口；addExerciseGate 同法）
  Completer<void>? deleteExerciseGate;

  /* ---------- M6-T1 喝水目标：setWaterGoal（PUT /user/water-goal） ---------- */

  /// 成功返回体的水目标 ml（云语义：入参按 [800,3000] 截断后回显；
  /// 桩同步写回 profile.goal.waterMl ≙ index.js:258 profiles.update）
  num? waterGoal;
  final List<num> waterGoalBodies = <num>[];
  ApiException? setWaterGoalError;

  /// 非空 → setWaterGoal 先 await 它再走错误/成功支（M6-T7 F1 在途关层用例钉）
  Completer<void>? setWaterGoalGate;

  /* ---------- M6-T4 水卡：addWater（POST /diet/water） ---------- */

  /// 桩侧当日杯数状态（≙ 云 sg_water.cups，index.js:438-446）：addWater 按
  /// date 读旧值 +delta 截断 [0,15] 后写回并回显 {water}。null/缺日期时以
  /// summary.water 为旧值（测试注 summary 即等价当日已存杯数）。
  Map<String, int>? waterCupsByDate;
  ApiException? addWaterError;

  /// addWater 收到的 (delta,date)（按调用顺序收集，断言 date=当前页 date）
  final List<({int delta, String? date})> waterBodies =
      <({int delta, String? date})>[];

  /// 非空 → addWater 先 await 它再返回（验证乐观中间态，≙ addGate 定式）。
  /// 次序注（M6-T7 F6 勘误）：实现里 addWaterError 抛出在前——两者同设时
  /// 走抛错支，本闸不会被 await。
  Completer<void>? waterGate;

  /// deleteFoodRecord 收到的 id（按调用顺序收集）
  final List<String> deletedIds = <String>[];
  ApiException? deleteError;

  /* ---------- M7-T4 食物库管理：listCustomFoods / setCustomFoodMeals /
  deleteCustomFood / setHiddenFoods / getBuiltinFoods ---------- */

  /// 自定义食物库（可变存储；元素 12 键平铺 ≙ 云 index.js:299-305 GET 返形）。
  /// listCustomFoods 返回浅拷贝；setMeals/delete 成功后对库做同款写操作
  /// （meals 白名单过滤回写、按裸 id 摘除）——重取即见真值。
  /// 注意：用例请传可变 List/Map（[cfFoodMap] 工厂即满足）。
  List<Map<String, dynamic>>? libCustomFoods;

  /// 内置库（元素 7 键含 hidden ≙ 云 index.js:329-332）；setHiddenFoods 按
  /// 云语义 **全量替换** 后同步各条 hidden 旗标。同样需可变形变。
  List<Map<String, dynamic>>? libBuiltins;

  ApiException? listFoodsError;
  ApiException? builtinError;
  ApiException? setMealsError;
  ApiException? deleteCustomError;
  ApiException? setHiddenError;
  int listFoodsCalls = 0;
  int builtinCalls = 0;

  /// setCustomFoodMeals 收到的 (id, 白名单过滤后 meals)（按调用顺序收集；
  /// 回归钉「管理链路 id 恒裸值不含 cf_」的观测面）
  final List<({String id, List<String> meals})> mealSetBodies =
      <({String id, List<String> meals})>[];

  /// deleteCustomFood 收到的 id（按调用顺序收集，注错时亦记录=请求已发出）
  final List<String> deletedCustomIds = <String>[];

  /// setHiddenFoods 收到的全量 ids（按调用顺序收集；云 slice(0,200) 已在桩截断）
  final List<List<String>> hiddenSubmissions = <List<String>>[];

  /// 自定义食物库单条（云 GET /foods/custom 返形 12 键，index.js:299-305；
  /// unit 归一 g/ml、meals 缺省空数组同云）
  static Map<String, dynamic> cfFoodMap({
    required String id,
    required String name,
    num kcal = 0,
    num grams = 0,
    String unit = 'g',
    List<String> meals = const <String>[],
    num protein = 0,
    num carb = 0,
    num fat = 0,
    String portion = '',
    String emoji = '🍽️',
    String image = '',
  }) =>
      <String, dynamic>{
        'id': id,
        'name': name,
        'kcal': kcal,
        'grams': grams,
        'unit': unit == 'ml' ? 'ml' : 'g',
        'meals': List<String>.of(meals),
        'protein': protein,
        'carb': carb,
        'fat': fat,
        'portion': portion,
        'emoji': emoji,
        'image': image,
      };

  /// 内置库单条（云 GET /foods/builtin 返形 7 键，index.js:329-332）
  static Map<String, dynamic> builtinFoodMap({
    required String id,
    required String name,
    String meta = '',
    num kcal = 0,
    String emoji = '🍽️',
    String image = '',
    bool hidden = false,
  }) =>
      <String, dynamic>{
        'id': id,
        'name': name,
        'meta': meta,
        'kcal': kcal,
        'emoji': emoji,
        'image': image,
        'hidden': hidden,
      };

  @override
  Future<List<dynamic>> listCustomFoods() async {
    listFoodsCalls++;
    if (listFoodsError != null) throw listFoodsError!;
    return List<dynamic>.of(libCustomFoods ?? const <Map<String, dynamic>>[]);
  }

  @override
  Future<Map<String, dynamic>> setCustomFoodMeals(
      String id, List<String> meals) async {
    // 云白名单（index.js:311-313）：四 meal 过滤 + slice(0,4)
    final filtered = meals
        .where((m) =>
            m == 'breakfast' || m == 'lunch' || m == 'dinner' || m == 'snack')
        .take(4)
        .toList();
    mealSetBodies.add((id: id, meals: filtered));
    if (setMealsError != null) throw setMealsError!;
    for (final f in libCustomFoods ?? const <Map<String, dynamic>>[]) {
      if (f['id'] == id) f['meals'] = List<String>.of(filtered);
    }
    return <String, dynamic>{'ok': true, 'id': id, 'meals': filtered};
  }

  @override
  Future<Map<String, dynamic>> deleteCustomFood(String id) async {
    deletedCustomIds.add(id);
    if (deleteCustomError != null) throw deleteCustomError!;
    // 云 where({uid,_id}).remove()（index.js:321）：裸 id 摘除
    libCustomFoods?.removeWhere((f) => f['id'] == id);
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<Map<String, dynamic>> setHiddenFoods(List<String> ids) async {
    final full = List<String>.of(ids.take(200)); // 云 slice(0,200)（index.js:338）
    hiddenSubmissions.add(full);
    if (setHiddenError != null) throw setHiddenError!;
    // 全量替换（index.js:339 整列覆写 profile.hiddenFoods）：hidden 旗标随列表
    for (final f in libBuiltins ?? const <Map<String, dynamic>>[]) {
      f['hidden'] = full.contains(f['id']);
    }
    return <String, dynamic>{'ok': true, 'ids': full};
  }

  @override
  Future<List<dynamic>> getBuiltinFoods() async {
    builtinCalls++;
    if (builtinError != null) throw builtinError!;
    return List<dynamic>.of(libBuiltins ?? const <Map<String, dynamic>>[]);
  }

  /* ---------- M3-T4 报告页：week/month；T6 体重趋势 ---------- */

  /// getWeekReport/getMonthReport/getWeightTrend 成功返回体（null → 默认样本，
  /// 形状见 contract/fixtures/diet-core.json weekReport/monthReport/weightTrend
  /// responseSample）
  Map<String, dynamic>? weekReport;
  Map<String, dynamic>? monthReport;
  Map<String, dynamic>? weightTrend;

  /// 非空 → 对应方法抛该异常（可测试中途清空，模拟"重试后成功"）
  ApiException? weekError;
  ApiException? monthError;
  ApiException? weightTrendError;

  /// 调用次数：验证重试确实重新取数
  int weekCalls = 0;
  int monthCalls = 0;
  int trendCalls = 0;

  /// 契约 fixture（contract/fixtures/diet-core.json）的字段形状：
  /// summary → {kcal,target,carb,protein,fat,water}
  static Map<String, dynamic> summaryMap({
    num kcal = 0,
    num target = 1679,
    num carb = 0,
    num protein = 0,
    num fat = 0,
    num water = 0,
  }) => {
    'kcal': kcal,
    'target': target,
    'carb': carb,
    'protein': protein,
    'fat': fat,
    'water': water,
  };

  /// records 单条 → {id,meal,name,portion,kcal,emoji,image,protein,carb,fat}
  static Map<String, dynamic> recordMap({
    required String id,
    required String meal,
    required String name,
    required String portion,
    required num kcal,
  }) => {
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

  /// 周报 fixture 形状 → {days,kcal,target,rates}（contract diet-core.json weekReport）
  static Map<String, dynamic> weekReportMap({
    List<String> days = const ['一', '二', '三', '四', '五', '六', '日'],
    List<num> kcal = const [0, 0, 0, 0, 0, 0, 0],
    num target = 1679,
    num carb = 0,
    num protein = 0,
    num fat = 0,
  }) => {
    'days': days,
    'kcal': kcal,
    'target': target,
    'rates': {'carb': carb, 'protein': protein, 'fat': fat},
  };

  /// 月报 fixture 形状 → {weeks,kcal,target,days,total,rates,isWeek:false}
  /// （contract diet-core.json monthReport.responseSample）。与 weekReportMap
  /// 对称：默认返回即可被 parseMonthReport 解析——此前默认 {} 会在解析期
  /// 抛类型错，坑下游 T5 用例。
  static Map<String, dynamic> monthReportMap({
    List<String> weeks = const ['W1', 'W2', 'W3', 'W4'],
    List<num> kcal = const [1652, 1723, 0, 1688],
    num target = 1679,
    num days = 19,
    num total = 31956,
    num carb = 78,
    num protein = 69,
    num fat = 73,
  }) => {
    'weeks': weeks,
    'kcal': kcal,
    'target': target,
    'days': days,
    'total': total,
    'rates': {'carb': carb, 'protein': protein, 'fat': fat},
    'isWeek': false,
  };

  /// 体重趋势 fixture 形状 → {points:[num], labels:[String]}
  /// （contract diet-core.json weightTrend.responseSample）。与 week/month 桩对称：
  /// 默认可被 WeightTrend.fromMap 解析；7 点递减使 delta 稳定为 -0.80。
  static Map<String, dynamic> weightTrendMap({
    List<num> points = const [67.2, 67, 66.8, 66.66, 66.6, 66.5, 66.4],
    List<String> labels = const [
      '9.19',
      '9.20',
      '9.21',
      '9.22',
      '9.23',
      '9.24',
      '9.25',
    ],
  }) => {'points': points, 'labels': labels};

  @override
  Future<Map<String, dynamic>> getDailySummary(String date) async {
    summaryCalls++;
    summaryDates.add(date);
    if (summaryError != null) throw summaryError!;
    if (summaryGate != null) await summaryGate!.future;
    // M7-T3：summaryByDate 优先（跨日用例按 date 给不同真值），否则回退单值档
    return summaryByDate?[date] ?? summary ?? summaryMap();
  }

  @override
  Future<List<dynamic>> getMealRecords(String date) async {
    recordsCalls++;
    recordDates.add(date);
    if (recordsError != null) throw recordsError!;
    if (recordsGate != null) await recordsGate!.future;
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
  Future<Map<String, dynamic>> addFoodRecord(
    Map<String, dynamic> record,
  ) async {
    addBodies.add(Map<String, dynamic>.from(record));
    if (addGate != null) await addGate!.future;
    if (addError != null) throw addError!;
    return <String, dynamic>{'id': 'rec_added_${addBodies.length}', ...record};
  }

  @override
  Future<Map<String, dynamic>> addCustomFood(Map<String, dynamic> food) async {
    customFoodBodies.add(Map<String, dynamic>.from(food));
    if (customFoodGate != null) await customFoodGate!.future;
    if (customFoodError != null) throw customFoodError!;
    // 云实返平铺（T2）：{ok,id,uid,name,...}；本任务只消费 ok 与否
    return <String, dynamic>{
      'ok': true,
      'id': 'cf_${customFoodBodies.length}',
      ...food,
    };
  }

  @override
  Future<Map<String, dynamic>> deleteFoodRecord(String id) async {
    deletedIds.add(id);
    if (deleteError != null) throw deleteError!;
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<Map<String, dynamic>> getBodyMetrics() async {
    bodyCalls++;
    if (bodyError != null) throw bodyError!;
    return bodyMetrics ?? const <String, dynamic>{'weightKg': 55};
  }

  /// 契约 fixture 形状（diet-core.json routes[profile].responseSample 同键集；
  /// 值取 H5 静态默认 index.html:180-183「食/食光用户/把每一餐，记成时光」）。
  static Map<String, dynamic> profileMap() => <String, dynamic>{
    'id': 'u_test',
    'nickname': '食光用户',
    'avatarText': '食',
    'avatarData': null,
    'signature': '把每一餐，记成时光',
    'goal': {'dailyKcal': 1679, 'targetWeight': 55, 'waterMl': 1600},
    'body': <String, dynamic>{},
    'bodyUpdatedAt': 0,
  };

  @override
  Future<Map<String, dynamic>> getProfile() async {
    profileCalls++;
    if (profileError != null) throw profileError!;
    return profile ?? profileMap();
  }

  @override
  Future<Map<String, dynamic>> updateProfile(Map<String, dynamic> data) async {
    profileUpdateBodies.add(Map<String, dynamic>.from(data));
    if (profileUpdateError != null) throw profileUpdateError!;
    final p = profile ??= profileMap();
    // 云端语义（api-diet index.js:213-232）：身体六字段族并进 body 嵌套返回面，
    // 其余键（nickname/signature）写顶层；客户端裸 bmi 不收，h/w 双在才重算。
    const bodyKeys = {
      'heightCm',
      'weightKg',
      'age',
      'gender',
      'activity',
      'deficit',
    };
    final bodyPatch = <String, dynamic>{
      for (final e in data.entries)
        if (bodyKeys.contains(e.key)) e.key: e.value,
    };
    if (bodyPatch.containsKey('heightCm') &&
        bodyPatch.containsKey('weightKg')) {
      final h = (bodyPatch['heightCm']! as num) / 100;
      final w = bodyPatch['weightKg']! as num;
      bodyPatch['bmi'] = double.parse(
        (w / (h * h)).toStringAsFixed(1),
      ); // ≙ +(W/pow(H/100,2)).toFixed(1)
    }
    p.addAll(<String, dynamic>{
      for (final e in data.entries)
        if (!bodyKeys.contains(e.key) && e.key != 'bmi') e.key: e.value,
    });
    if (bodyPatch.isNotEmpty) {
      final b = Map<String, dynamic>.of(
        (p['body'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{},
      );
      b.addAll(bodyPatch);
      p['body'] = b;
    }
    return <String, dynamic>{'ok': true, ...p};
  }

  @override
  Future<Map<String, dynamic>> setGoal(num dailyKcal, num targetWeight) async {
    goalCalls++;
    goalBodies.add(<String, dynamic>{
      'dailyKcal': dailyKcal,
      'targetWeight': targetWeight,
    });
    if (setGoalError != null) throw setGoalError!;
    final p = profile ??= profileMap();
    final g = Map<String, dynamic>.of(
      (p['goal'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{},
    );
    g['dailyKcal'] = dailyKcal;
    g['targetWeight'] = targetWeight;
    p['goal'] = g; // ≙ api-diet :246-252 云端 goal 列写回
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<Map<String, dynamic>> updateAvatar(String dataUrl) async {
    avatarCalls++;
    lastAvatarData = dataUrl;
    if (avatarError != null) throw avatarError!;
    (profile ??= profileMap())['avatarData'] = dataUrl;
    // 云实返 {ok,avatarData}（contract routes[avatar].responseFields）
    return <String, dynamic>{'ok': true, 'avatarData': dataUrl};
  }

  @override
  Future<Map<String, dynamic>> logWeight(num weightKg, [String? date]) async {
    weightLogs.add((kg: weightKg, date: date));
    if (logWeightGate != null) await logWeightGate!.future;
    if (logWeightError != null) throw logWeightError!;
    // 云端回显形状（js/app.js:934 消费 r.weightKg）
    return <String, dynamic>{'weightKg': weightKg, 'date': date};
  }

  @override
  Future<Map<String, dynamic>> getWeekReport({int offset = 0}) async {
    weekCalls++;
    if (weekError != null) throw weekError!;
    return weekReport ?? weekReportMap();
  }

  @override
  Future<Map<String, dynamic>> getMonthReport({int offset = 0}) async {
    monthCalls++;
    if (monthError != null) throw monthError!;
    return monthReport ?? monthReportMap();
  }

  @override
  Future<Map<String, dynamic>> getWeightTrend() async {
    trendCalls++;
    if (weightTrendError != null) throw weightTrendError!;
    return weightTrend ?? weightTrendMap();
  }

  @override
  Future<List<dynamic>> getExercises(String date) async {
    exerciseCalls++;
    exerciseDates.add(date);
    if (exerciseError != null) throw exerciseError!;
    return exercisesByDate?[date] ?? const <dynamic>[];
  }

  @override
  Future<Map<String, dynamic>> addExercise(Map<String, dynamic> record) async {
    exerciseBodies.add(Map<String, dynamic>.from(record));
    // M7-T2 钉①②：先挂闸（回包前测试可断乐观中间态），再走错误/云态支
    if (addExerciseGate != null) await addExerciseGate!.future;
    if (addExerciseError != null) throw addExerciseError!;
    // 云语义（index.js:353-368）：kcal 取整后为 0 → 回 {ok:false,message}
    // 而非 HTTP 错，由调用层判 ok；有效时回平铺 {ok,id,...doc} 含 createdAt。
    final kcal = (num.tryParse('${record['kcal']}') ?? 0).round().clamp(
      0,
      1 << 31,
    );
    if (kcal == 0) {
      return <String, dynamic>{'ok': false, 'message': '消耗热量无效'};
    }
    final date = (record['date'] as String?)?.isNotEmpty == true
        ? record['date']
        : DateTime.now().toUtc().toIso8601String().substring(
            0,
            10,
          ); // ≙ 云 today()
    final key = '${record['key'] ?? ''}'; // ≙ String(body.key||'').slice(0,20)
    final name = '${record['name'] ?? ''}';
    final emoji = '${record['emoji'] ?? ''}';
    final doc = <String, dynamic>{
      'id': 'x_stub_${exerciseBodies.length}',
      'uid': 'u_test',
      'date': date,
      'key': key.length > 20 ? key.substring(0, 20) : key,
      'name': name.isNotEmpty
          ? (name.length > 60 ? name.substring(0, 60) : name)
          : '运动',
      'emoji': emoji.isNotEmpty ? emoji : '🏃',
      'amount': record['amount'] is num ? record['amount'] : 0,
      'unit': record['unit'] == 'km' ? 'km' : 'min',
      'kcal': kcal,
      'createdAt': DateTime.now().millisecondsSinceEpoch,
    };
    // M7-T2 钉②：POST 成功即落库（≙ 云 add 写 sg_exercises），此后
    // getExercises(date) 回包含真 id 行——「temp 被真值替换」的可观测面。
    // 落库行按 GET 形状剥 createdAt（contract routes[exercises]：云端不回
    // 该键，T1 登记），rep 型刷新后 isRepRecord 退化分钟档 ≙ H5 同款。
    final stored = Map<String, dynamic>.of(doc)..remove('createdAt');
    ((exercisesByDate ??= <String, List<Map<String, dynamic>>>{})[
          date as String
        ] ??=
        <Map<String, dynamic>>[])
        .add(stored);
    return <String, dynamic>{'ok': true, ...doc};
  }

  @override
  Future<Map<String, dynamic>> deleteExercise(String id) async {
    deletedExerciseIds.add(id);
    if (deleteExerciseGate != null) await deleteExerciseGate!.future;
    if (deleteExerciseError != null) throw deleteExerciseError!;
    exercisesByDate?.values.forEach(
      (list) => list.removeWhere((r) => r['id'] == id),
    );
    return <String, dynamic>{'ok': true};
  }

  @override
  Future<Map<String, dynamic>> addWater(int delta, [String? date]) async {
    waterBodies.add((delta: delta, date: date));
    if (addWaterError != null) throw addWaterError!;
    if (waterGate != null) await waterGate!.future;
    // 云语义（api-diet index.js:436-447）：date 缺省=云 today()（UTC 日，同真
    // HealthApi._todayUtc 口径）；cups=当日旧值+delta 截断 [0,15] 写回并回显。
    // 旧值取 summary.water（测试注 seed），≙ 云读 sg_water 当日文档；
    // M7-T3：summaryByDate 在场时先取该日 seed（与 getDailySummary 同档）。
    final key =
        date ?? DateTime.now().toUtc().toIso8601String().substring(0, 10);
    final current = waterCupsByDate?[key] ??
        ((summaryByDate?[key]?['water'] ?? summary?['water']) as num? ?? 0)
            .round();
    final cups = (current + delta).clamp(0, 15);
    (waterCupsByDate ??= <String, int>{})[key] = cups;
    return <String, dynamic>{'water': cups};
  }

  @override
  Future<Map<String, dynamic>> setWaterGoal(num waterGoalMl) async {
    waterGoalBodies.add(waterGoalMl);
    // M6-T7 F1 用例钉：非空 → 先 await 它再走错误/成功支（挂住在途，测试可
    // 在回包前关层）
    if (setWaterGoalGate != null) await setWaterGoalGate!.future;
    if (setWaterGoalError != null) throw setWaterGoalError!;
    // 云语义（index.js:255-260）：Math.max(800, Math.min(3000, Number(x)||1600))
    // 截断后回显 {ok,waterGoalMl}；200ml 对齐是 H5 步进器职责，云端不归一。
    // ||1600 falsy 支：入参 0 → 1600（评审遗留修正——原桩对 0 回 800 与云不符）。
    final ml = waterGoalMl == 0 ? 1600 : waterGoalMl.clamp(800, 3000);
    waterGoal = ml;
    final p = profile ??= profileMap();
    final g = Map<String, dynamic>.of(
      (p['goal'] as Map?)?.cast<String, dynamic>() ?? const <String, dynamic>{},
    );
    g['waterMl'] = ml; // ≙ index.js:258 profiles.update({waterMl})
    p['goal'] = g;
    return <String, dynamic>{'ok': true, 'waterGoalMl': ml};
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('StubHealthApi 未实现：${invocation.memberName}');
}
