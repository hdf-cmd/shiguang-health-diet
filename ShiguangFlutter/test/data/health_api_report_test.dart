// ShiguangFlutter/test/data/health_api_report_test.dart
// M3-T2 报告数据层：getWeekReport / getMonthReport / getWeightTrend 的信封断言。
// 零网络：注入记录 adapter，断言 HealthApi 发出的 envelope
// {path, method:'GET', params, body:{}} 与契约（contract/fixtures/diet-core.json
// 的 weekReport/monthReport/weightTrend 三条）一致；响应体原样透传。
// M4-T1：RecordingAdapter 收敛到 test/harness.dart（与 contract_test 共用一份）。
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/data/api_client.dart';
import 'package:shiguang_flutter/data/health_api.dart';
import 'package:shiguang_flutter/data/token_store.dart';

import '../harness.dart';

void main() {
  late RecordingAdapter adapter;
  late HealthApi api;

  /// 回放样本取自 H5 采集口径：fixture 里三条只读路由的 responseSample
  late Map<String, dynamic> fixtureWeek;
  late Map<String, dynamic> fixtureMonth;
  late Map<String, dynamic> fixtureTrend;

  setUp(() {
    final routes = (((jsonDecode(File('../contract/fixtures/diet-core.json')
            .readAsStringSync())
        as Map<String, dynamic>)['routes']) as List)
        .cast<Map<String, dynamic>>();
    Map<String, dynamic> byRoute(String route) => routes
        .firstWhere((e) => e['route'] == route)['responseSample'] as Map<String, dynamic>;
    fixtureWeek = byRoute('weekReport');
    fixtureMonth = byRoute('monthReport');
    fixtureTrend = byRoute('weightTrend');

    adapter = RecordingAdapter(responseText: jsonEncode(fixtureWeek));
    final dio = Dio()..httpClientAdapter = adapter;
    final store = InMemoryTokenStore();
    store.write(TokenData({
      'accessToken': 'at-report',
      'refreshToken': 'rt-report',
      'expiresIn': 7200,
      'savedAt': 1,
    }));
    api = HealthApi(ApiClient(tokenStore: store, dio: dio));
  });

  test('getWeekReport(offset: 1) 发出 GET /report/week 信封，响应原样返回', () async {
    final data = await api.getWeekReport(offset: 1);
    expect(adapter.envelopes, hasLength(1));
    expect(adapter.envelopes.single, {
      'path': '/report/week',
      'method': 'GET',
      'params': {'offset': 1},
      'body': {},
    });
    expect(data, fixtureWeek);
  });

  test('getWeekReport() offset 缺省为 0', () async {
    await api.getWeekReport();
    expect(adapter.envelopes.single['params'], {'offset': 0});
  });

  test('getMonthReport(offset: 1) 发出 GET /report/month 信封，响应原样返回', () async {
    adapter.responseText = jsonEncode(fixtureMonth);
    final data = await api.getMonthReport(offset: 1);
    expect(adapter.envelopes.single, {
      'path': '/report/month',
      'method': 'GET',
      'params': {'offset': 1},
      'body': {},
    });
    expect(data, fixtureMonth);
  });

  test('getMonthReport() offset 缺省为 0', () async {
    await api.getMonthReport();
    expect(adapter.envelopes.single['params'], {'offset': 0});
  });

  test('getWeightTrend 发出 GET /report/weight-trend 信封（params 空对象），响应原样返回', () async {
    adapter.responseText = jsonEncode(fixtureTrend);
    final data = await api.getWeightTrend();
    expect(adapter.envelopes.single, {
      'path': '/report/weight-trend',
      'method': 'GET',
      'params': {},
      'body': {},
    });
    expect(data, fixtureTrend);
  });
}
