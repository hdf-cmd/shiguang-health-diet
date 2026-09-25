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

  /// updateProfile 收到的 data（按调用顺序收集；成功时浅合并进 [profile]，
  /// ≙ 云端语义 js/api.js:277「部分字段浅合并进用户文档」——供重取断言）
  final List<Map<String, dynamic>> profileUpdateBodies =
      <Map<String, dynamic>>[];
  ApiException? profileUpdateError;

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

  /// deleteFoodRecord 收到的 id（按调用顺序收集）
  final List<String> deletedIds = <String>[];
  ApiException? deleteError;

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

  /// 周报 fixture 形状 → {days,kcal,target,rates}（contract diet-core.json weekReport）
  static Map<String, dynamic> weekReportMap({
    List<String> days = const ['一', '二', '三', '四', '五', '六', '日'],
    List<num> kcal = const [0, 0, 0, 0, 0, 0, 0],
    num target = 1679,
    num carb = 0,
    num protein = 0,
    num fat = 0,
  }) =>
      {
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
  }) =>
      {
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
      '9.19', '9.20', '9.21', '9.22', '9.23', '9.24', '9.25'
    ],
  }) =>
      {'points': points, 'labels': labels};

  @override
  Future<Map<String, dynamic>> getDailySummary(String date) async {
    summaryCalls++;
    if (summaryError != null) throw summaryError!;
    if (summaryGate != null) await summaryGate!.future;
    return summary ?? summaryMap();
  }

  @override
  Future<List<dynamic>> getMealRecords(String date) async {
    recordsCalls++;
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
  Future<Map<String, dynamic>> addFoodRecord(Map<String, dynamic> record) async {
    addBodies.add(Map<String, dynamic>.from(record));
    if (addGate != null) await addGate!.future;
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
    p.addAll(data); // 云端浅合并（js/api.js:277 注释面）
    return <String, dynamic>{'ok': true, ...p};
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
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('StubHealthApi 未实现：${invocation.memberName}');
}
