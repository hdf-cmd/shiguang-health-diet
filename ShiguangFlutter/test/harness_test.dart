// ShiguangFlutter/test/harness_test.dart
// 测试地基自身的用例（M4-T1）：RecordingAdapter 既被三处数据层用例依赖，
// 它自己的语义就得锁住，否则"adapter 记了几次"这个断言本身不可信：
//  ① envelope 记录 + 请求计数；② 路由键取 envelope.path、裸请求回落 uri.path；
//  ③ 缺省响应可整体改，routes 按路由覆盖，两者互不干扰；④ delay 门控生效。
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

Future<({int status, String body})> _post(
  Dio dio,
  String url,
  Map<String, dynamic> envelope,
) async {
  final resp = await dio.post<String>(
    url,
    data: envelope,
    options: Options(contentType: 'application/json', responseType: ResponseType.plain,
        validateStatus: (_) => true),
  );
  return (status: resp.statusCode ?? 0, body: resp.data ?? '');
}

const _apiBase = 'https://example.test/v1/functions/api-diet';
const _refreshUrl = 'https://example.test/auth/v1/token';

void main() {
  test('记录 envelope 与请求计数；缺省恒 200 + {}', () async {
    final adapter = RecordingAdapter();
    final dio = Dio()..httpClientAdapter = adapter;

    final r = await _post(dio, _apiBase, {
      'path': '/diet/summary',
      'method': 'GET',
      'params': {'date': '2026-09-25'},
      'body': {},
    });

    expect(r.status, 200);
    expect(r.body, '{}');
    expect(adapter.requestCount, 1);
    expect(adapter.envelopes.single['path'], '/diet/summary');
    expect(adapter.envelopes.single['params'], {'date': '2026-09-25'});
    expect(adapter.keys.single, '/diet/summary');
    expect(adapter.countOf('/diet/summary'), 1);
    expect(adapter.countOf('/diet/records'), 0);
  });

  test('routes 按路由覆盖响应，未命中路由走缺省值', () async {
    final adapter = RecordingAdapter(
      responseText: '{"ok":true}',
      routes: const {
        '/auth/v1/token': (status: 400, text: '{"error":"invalid_grant"}'),
      },
    );
    final dio = Dio()..httpClientAdapter = adapter;

    final biz = await _post(dio, _apiBase, {
      'path': '/report/week',
      'method': 'GET',
      'params': {'offset': 0},
      'body': {},
    });
    final refresh = await _post(dio, _refreshUrl, {'grant_type': 'refresh_token'});

    expect(biz.status, 200);
    expect(biz.body, '{"ok":true}');
    expect(refresh.status, 400);
    expect(jsonDecode(refresh.body), {'error': 'invalid_grant'});
    // 无 envelope.path → 回落 uri.path 作路由键
    expect(adapter.keys, ['/report/week', '/auth/v1/token']);
    expect(adapter.requestCount, 2);
  });

  test('整体改 status 可模拟服务端错误；delay 在出响应前被 await', () async {
    var delayedFor = <String>[];
    final adapter = RecordingAdapter(
      status: 500,
      responseText: '{"message":"服务开小差了"}',
      delay: (key) {
        delayedFor.add(key);
        return Future.value();
      },
    );
    final dio = Dio()..httpClientAdapter = adapter;

    final r = await _post(dio, _apiBase, {
      'path': '/diet/water',
      'method': 'POST',
      'params': {},
      'body': {'delta': 250},
    });

    expect(r.status, 500);
    expect(jsonDecode(r.body), {'message': '服务开小差了'});
    expect(delayedFor, ['/diet/water']);
    expect(adapter.envelopes.single['body'], {'delta': 250});
  });
}
