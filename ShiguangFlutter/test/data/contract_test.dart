// ShiguangFlutter/test/data/contract_test.dart
// 双栈契约测试（Dart 侧）：读仓库根 contract/fixtures/diet-core.json（与 H5
// tests/contract.test.js 同一份契约），对 health_api.dart 每个契约登记方法：
//   ① 注入 recording adapter 调方法，断言 envelope 的 path/method/params/body
//      与 fixture 的模板路径、httpMethod、requestSample 一致（:param 按 js/api.js:242
//      的 encodeURIComponent 语义回填）；
//   ② 只读路由的 responseSample 逐段 containsKey 覆盖 fixture.responseFields
//      （点路径导航；responseShape=array 时作用于首元素）。
// flutter test 的工作目录是 ShiguangFlutter/，故 fixture 用 ../contract/ 相对路径。
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/data/api_client.dart';
import 'package:shiguang_flutter/data/health_api.dart';
import 'package:shiguang_flutter/data/token_store.dart';

/// 记录 envelope 的 adapter：恒 200 + {}（契约流其余分支由 api_client_test.dart 覆盖，
/// 这里只关心 HealthApi 发出了什么 envelope）
class _RecordingAdapter implements HttpClientAdapter {
  final List<Map<String, dynamic>> envelopes = [];

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    final raw = requestStream == null
        ? '{}'
        : utf8.decode((await requestStream.expand((c) => c).toList()));
    envelopes.add(jsonDecode(raw) as Map<String, dynamic>);
    return ResponseBody.fromString('{}', 200, headers: {
      'content-type': ['application/json; charset=utf-8'],
    });
  }

  @override
  void close({bool force = false}) {}
}

/// fixture 的一条路由契约
class _Route {
  _Route(this.raw);
  final Map<String, dynamic> raw;

  String get route => raw['route'] as String;
  String get dartMethod => raw['dartMethod'] as String;
  String get path => raw['path'] as String;
  String get httpMethod => raw['httpMethod'] as String;
  bool get readOnly => raw['readOnly'] as bool;
  Map<String, dynamic> get requestSample =>
      (raw['requestSample'] as Map).cast<String, dynamic>();
  Map<String, dynamic> get sampleParams =>
      ((requestSample['params'] ?? const <String, dynamic>{}) as Map)
          .cast<String, dynamic>();
  Map<String, dynamic> get sampleBody =>
      ((requestSample['body'] ?? const <String, dynamic>{}) as Map)
          .cast<String, dynamic>();
  List<dynamic> get responseFields => raw['responseFields'] as List;
  String get responseShape => raw['responseShape'] as String;
  Object? get responseSample => raw['responseSample'];
}

/// js/api.js:242 的 :param 回填语义（每 key 替换首次出现，encodeURIComponent）
String fillPath(String template, Map<String, dynamic> params) {
  var p = template;
  params.forEach((k, v) {
    p = p.replaceFirst(':$k', Uri.encodeComponent('$v'));
  });
  return p;
}

List<_Route> _loadRoutes() {
  final file = File('../contract/fixtures/diet-core.json');
  if (!file.existsSync()) {
    throw StateError('契约 fixture 缺失：仓库根 contract/fixtures/diet-core.json');
  }
  return ((jsonDecode(file.readAsStringSync()) as Map<String, dynamic>)['routes']
          as List)
      .cast<Map<String, dynamic>>()
      .map(_Route.new)
      .toList();
}

void main() {
  final routes = _loadRoutes();

  late _RecordingAdapter adapter;
  late HealthApi api;

  setUp(() {
    adapter = _RecordingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;
    // 恒有登录态：Bearer 选择分支由 api_client_test.dart 覆盖
    final store = InMemoryTokenStore();
    store.write(TokenData({
      'accessToken': 'at-contract',
      'refreshToken': 'rt-contract',
      'expiresIn': 7200,
      'savedAt': 1,
    }));
    api = HealthApi(ApiClient(tokenStore: store, dio: dio));
  });

  /// 按 dartMethod 调 HealthApi 对应方法，实参全部取自 fixture.requestSample
  Future<void> invoke(HealthApi api, _Route r) {
    final p = r.sampleParams;
    final b = r.sampleBody;
    switch (r.dartMethod) {
      case 'getProfile':
        return api.getProfile();
      case 'getBodyMetrics':
        return api.getBodyMetrics();
      case 'getDailySummary':
        return api.getDailySummary(p['date'] as String);
      case 'getMealRecords':
        return api.getMealRecords(p['date'] as String);
      case 'addFoodRecord':
        return api.addFoodRecord(Map<String, dynamic>.from(b));
      case 'deleteFoodRecord':
        return api.deleteFoodRecord(p['id'] as String);
      case 'addWater':
        return api.addWater(b['delta'] as int, b['date'] as String?);
      case 'searchFoods':
        return api.searchFoods(p['keyword'] as String, p['meal'] as String?);
      case 'getBuiltinFoods':
        return api.getBuiltinFoods();
      case 'logWeight':
        return api.logWeight(b['weightKg'] as num, b['date'] as String?);
      case 'getWeekReport':
        return api.getWeekReport(offset: p['offset'] as int);
      case 'getMonthReport':
        return api.getMonthReport(offset: p['offset'] as int);
      case 'getWeightTrend':
        return api.getWeightTrend();
      default:
        throw StateError('contract_test 未接入的 dartMethod: ${r.dartMethod}');
    }
  }

  group('契约①：HealthApi 每个方法的 envelope path/httpMethod/requestSample 与 fixture 一致', () {
    for (final r in routes) {
      test('${r.dartMethod} → ${fillPath(r.path, r.sampleParams)} (${r.httpMethod})', () async {
        await invoke(api, r);
        expect(adapter.envelopes, hasLength(1));
        final env = adapter.envelopes.single;
        expect(env['path'], fillPath(r.path, r.sampleParams));
        expect(env['method'], r.httpMethod);
        expect(env['params'], r.sampleParams);
        expect(env['body'], r.sampleBody);
      });
    }
  });

  group('契约②：只读路由 responseSample 覆盖 fixture.responseFields', () {
    for (final r in routes.where((r) => r.readOnly && r.responseSample != null)) {
      test('${r.dartMethod} 响应字段覆盖（${r.responseFields.length} 项）', () {
        Object? node = r.responseSample;
        if (r.responseShape == 'array') {
          expect(node, isA<List>(), reason: '${r.route} 样本应为数组');
          final list = node! as List;
          expect(list, isNotEmpty);
          node = list.first;
        }
        for (final field in r.responseFields) {
          final segs = (field as String).split('.');
          var cur = node;
          for (final seg in segs) {
            expect(cur, isA<Map>(),
                reason: '${r.route}.$field 导航中途不是对象');
            final map = cur! as Map;
            expect(map.containsKey(seg), isTrue,
                reason: '真实采集样本缺少契约声明字段: ${r.route}.$field');
            cur = map[seg];
          }
        }
      });
    }
  });
}
