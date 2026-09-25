// ShiguangFlutter/test/data/api_client_test.dart
// data 层网络契约单测：期望值逐分支对齐 js/api.js（1-140、235-310 行）——
//   realRequest：单入口 POST、envelope {path,method,params,body}、Bearer=token?accessToken:PK、
//   401→单飞续期→重试一次、仍/净 401→清 token 抛「登录已过期，请重新登录」、
//   非 200→抛 message||`请求失败(${status})`、200+ok:false→抛 message||'操作失败'；
//   _doRefreshToken：GW /auth/v1/token、grant_type=refresh_token、无 Authorization、
//   写回 {accessToken, refreshToken||旧值, expiresIn||7200, savedAt:now}；
//   AuthApi：login/register 恒用 PUBLISHABLE_KEY，错误兜底「登录失败/注册失败」，
//   login 成功 _saveToken({...data.token, savedAt}).
// 分层说明：flutter_secure_storage 在纯 dart 单测无平台通道，故测试注入
// InMemoryTokenStore（TokenStore 接口的内存实现），SecureTokenStore 薄壳不在单测覆盖。
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/data/api_client.dart';
import 'package:shiguang_flutter/data/auth_api.dart';
import 'package:shiguang_flutter/data/token_store.dart';

/// 记录到的请求（dio 原始 RequestOptions + 解码后的请求体文本）
class _Captured {
  _Captured(this.options, this.rawBody);
  final RequestOptions options;
  final String rawBody;

  Map<String, dynamic> get jsonBody => jsonDecode(rawBody) as Map<String, dynamic>;
  String get url => options.uri.toString();
  String? get authorization => options.headers['Authorization'] as String?;
}

/// dio HttpClientAdapter 桩：按 url + 调用序号路由到脚本化响应。
/// handle 返回 (status, bodyObjectOrRawString, latency)。
class _StubAdapter implements HttpClientAdapter {
  _StubAdapter(this.handle);

  final (int, Object, Duration) Function(_Captured pending, int apiCount, int refreshCount) handle;
  final List<_Captured> requests = [];
  int apiCount = 0;
  int refreshCount = 0;

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<List<int>>? requestStream,
      Future<void>? cancelFuture) async {
    String raw = '';
    if (requestStream != null) {
      raw = utf8.decode(await requestStream.expand((c) => c).toList());
    }
    final isRefresh = options.uri.toString() == '${ApiClient.gwBase}/auth/v1/token';
    final captured = _Captured(options, raw);
    requests.add(captured);
    // 先取序号再自增：handle 依据「本请求之前已有几个同类请求」选脚本响应
    final intApi = apiCount;
    final intRefresh = refreshCount;
    if (isRefresh) {
      refreshCount++;
    } else {
      apiCount++;
    }
    final (status, body, latency) = handle(captured, intApi, intRefresh);
    await Future<void>.delayed(latency);
    return ResponseBody.fromString(
      body is String ? body : jsonEncode(body),
      status,
      headers: {
        'content-type': ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late InMemoryTokenStore store;

  setUp(() {
    store = InMemoryTokenStore();
  });

  ApiClient clientWith(
      (int, Object, Duration) Function(_Captured pending, int apiCount, int refreshCount) handle,
      List<_Captured> sink) {
    final adapter = _StubAdapter((pending, apiCount, refreshCount) {
      final r = handle(pending, apiCount, refreshCount);
      sink.add(pending);
      return r;
    });
    final dio = Dio()..httpClientAdapter = adapter;
    return ApiClient(tokenStore: store, dio: dio);
  }

  TokenData signedInToken() => TokenData({
        'accessToken': 'old-at',
        'refreshToken': 'rt-1',
        'expiresIn': 7200,
        'savedAt': 1000,
      });

  group('单入口 envelope 与 Bearer 选择', () {
    test('POST 到 API_BASE，envelope 为 {path,method,params,body}，外层恒 POST、body 缺省为 {}', () async {
      final reqs = <_Captured>[];
      final client = clientWith((_, _, _) => (200, {'ok': true, 'kcal': 10}, Duration.zero), reqs);

      final data = await client.call('/diet/records/:id', method: 'DELETE', params: {'id': 'r_01'});
      expect(data['ok'], isTrue);

      expect(reqs, hasLength(1));
      final req = reqs.single;
      expect(req.url, ApiClient.apiBase);
      expect(req.options.method, 'POST'); // 云函数单入口：HTTP 层恒 POST
      expect(req.jsonBody, {
        'path': '/diet/records/r_01', // :id 已被替换（encodeURIComponent 语义）
        'method': 'DELETE', // 业务方法在 envelope 里
        'params': {'id': 'r_01'}, // params 原样保留（对齐 js：path 替换后仍透传）
        'body': {}, // body 缺省 → {}
      });
    });

    test('body 原样进 envelope；无 token → Bearer PUBLISHABLE_KEY', () async {
      final reqs = <_Captured>[];
      final client = clientWith((_, _, _) => (200, {'ok': true}, Duration.zero), reqs);

      await client.call('/user/goal', method: 'PUT', body: {'dailyKcal': 1800});
      expect(reqs.single.jsonBody['body'], {'dailyKcal': 1800});
      expect(reqs.single.authorization, 'Bearer ${ApiClient.publishableKey}');
    });

    test('有 token → Bearer accessToken（优先于 PUBLISHABLE_KEY）', () async {
      final reqs = <_Captured>[];
      await store.write(signedInToken());
      final client = clientWith((_, _, _) => (200, {'ok': true}, Duration.zero), reqs);

      await client.call('/user/profile');
      expect(reqs.single.authorization, 'Bearer old-at');
    });
  });

  group('401 → 单飞续期 → 重试一次', () {
    test('续期成功：写回新 token（refresh_token 轮换、expires_in 缺省 7200），重试一次并返回数据', () async {
      final reqs = <_Captured>[];
      await store.write(signedInToken());
      final client = clientWith((pending, apiCount, refreshCount) {
        if (pending.url != ApiClient.apiBase) return (200, {'access_token': 'new-at', 'refresh_token': 'rt-2'}, Duration.zero);
        return apiCount == 0 ? (401, <String, dynamic>{}, Duration.zero) : (200, {'ok': true, 'water': 3}, Duration.zero);
      }, reqs);

      final data = await client.call('/diet/water', method: 'POST', body: {'delta': 1});
      expect(data['water'], 3);

      // 恰两次 API 调用 + 一次续期
      final apiReqs = reqs.where((r) => r.url == ApiClient.apiBase).toList();
      final refreshReqs = reqs.where((r) => r.url != ApiClient.apiBase).toList();
      expect(apiReqs, hasLength(2));
      expect(refreshReqs, hasLength(1));
      // 首次用旧 accessToken，续期后用新 accessToken 重试
      expect(apiReqs[0].authorization, 'Bearer old-at');
      expect(apiReqs[1].authorization, 'Bearer new-at');
      // 续期请求：POST GW /auth/v1/token，grant_type=refresh_token，不带 Authorization
      expect(refreshReqs.single.url, '${ApiClient.gwBase}/auth/v1/token');
      expect(refreshReqs.single.options.method, 'POST');
      expect(refreshReqs.single.authorization, isNull);
      expect(refreshReqs.single.jsonBody, {'grant_type': 'refresh_token', 'refresh_token': 'rt-1'});
      // token 写回：轮换 refresh_token、expires_in 缺省 7200、savedAt 刷新（> 原值 1000）
      final saved = await store.read();
      expect(saved!.accessToken, 'new-at');
      expect(saved.refreshToken, 'rt-2');
      expect(saved.expiresIn, 7200);
      expect(saved.savedAt, greaterThan(1000));
    });

    test('续期成功但重试仍 401 → 清 token，抛「登录已过期，请重新登录」', () async {
      final reqs = <_Captured>[];
      await store.write(signedInToken());
      final client = clientWith((pending, apiCount, refreshCount) {
        if (pending.url != ApiClient.apiBase) return (200, {'access_token': 'new-at'}, Duration.zero);
        return (401, <String, dynamic>{}, Duration.zero);
      }, reqs);

      await expectLater(
        client.call('/user/profile'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', '登录已过期，请重新登录')),
      );
      expect(await store.read(), isNull); // _clearToken
      expect(reqs.where((r) => r.url == ApiClient.apiBase), hasLength(2)); // 只重试一次，不再循环
    });

    test('续期失败（/auth/v1/token 非 2xx）→ 不重试，清 token，抛「登录已过期，请重新登录」', () async {
      final reqs = <_Captured>[];
      await store.write(signedInToken());
      final client = clientWith((pending, apiCount, refreshCount) {
        if (pending.url != ApiClient.apiBase) return (400, {'error': 'invalid_grant'}, Duration.zero);
        return (401, <String, dynamic>{}, Duration.zero);
      }, reqs);

      await expectLater(
        client.call('/user/profile'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', '登录已过期，请重新登录')),
      );
      expect(await store.read(), isNull);
      expect(reqs.where((r) => r.url == ApiClient.apiBase), hasLength(1)); // 不重试
      expect(reqs.where((r) => r.url != ApiClient.apiBase), hasLength(1));
    });

    test('并发 401 单飞：两个在途请求共享同一次续期', () async {
      final reqs = <_Captured>[];
      await store.write(signedInToken());
      final client = clientWith((pending, apiCount, refreshCount) {
        if (pending.url != ApiClient.apiBase) return (200, {'access_token': 'new-at'}, const Duration(milliseconds: 60));
        // 两个接口首次均 401（各 1 次），重试均 200（同 path 已有在途请求则视为重试）
        final retried = reqs
            .where((r) =>
                r != pending &&
                r.url == ApiClient.apiBase &&
                r.jsonBody['path'] == pending.jsonBody['path'])
            .length;
        return retried == 0 ? (401, <String, dynamic>{}, Duration.zero) : (200, {'ok': true}, Duration.zero);
      }, reqs);

      final results = await Future.wait([
        client.call('/user/profile'),
        client.call('/diet/summary'),
      ]);
      expect(results.every((d) => d['ok'] == true), isTrue);
      expect(reqs.where((r) => r.url != ApiClient.apiBase), hasLength(1)); // 续期仅一次
      // 两次重试都用新 token
      final apiReqs = reqs.where((r) => r.url == ApiClient.apiBase).toList();
      expect(apiReqs, hasLength(4));
      expect(apiReqs.sublist(2).every((r) => r.authorization == 'Bearer new-at'), isTrue);
    });
  });

  group('401/非 200/ok:false 错误映射', () {
    test('无 token 直接 401 → 不续期，仍抛「登录已过期，请重新登录」', () async {
      final reqs = <_Captured>[];
      final client = clientWith((_, _, _) => (401, <String, dynamic>{}, Duration.zero), reqs);

      await expectLater(
        client.call('/user/profile'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', '登录已过期，请重新登录')),
      );
      expect(reqs, hasLength(1)); // t 为 null → 不进 _refreshToken
    });

    test('ok:false → 抛 message；message 空则「操作失败」', () async {
      final reqs = <_Captured>[];
      final client = clientWith((pending, apiCount, _) =>
          apiCount == 0
              ? (200, {'ok': false, 'message': '今日记录不存在'}, Duration.zero)
              : (200, {'ok': false}, Duration.zero), reqs);

      await expectLater(
        client.call('/diet/records', method: 'DELETE', params: {'id': 'x'}),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', '今日记录不存在')),
      );
      await expectLater(
        client.call('/diet/records', method: 'DELETE', params: {'id': 'x'}),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', '操作失败')),
      );
    });

    test('非 200 → 抛 message||请求失败(status)；非 JSON 响应体按空对象处理', () async {
      final reqs = <_Captured>[];
      final client = clientWith((pending, apiCount, _) {
        if (apiCount == 0) return (500, {'message': '云函数内部错误'}, Duration.zero);
        return (503, 'Service Unavailable', Duration.zero); // 非 JSON 文本
      }, reqs);

      await expectLater(
        client.call('/user/profile'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', '云函数内部错误')),
      );
      await expectLater(
        client.call('/user/profile'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', '请求失败(503)')),
      );
    });
  });

  group('AuthApi（login/register 恒用 PUBLISHABLE_KEY，不走 401 续期）', () {
    test('loginByUsername：envelope=/auth/login，成功写 token（含 savedAt）并返回', () async {
      final reqs = <_Captured>[];
      await store.write(signedInToken()); // 已登录也应恒用 PK（js 里 login 不经 realRequest）
      final client = clientWith((_, _, _) => (200, {
            'ok': true,
            'token': {'accessToken': 'at-9', 'refreshToken': 'rt-9', 'expiresIn': 3600},
          }, Duration.zero), reqs);
      final auth = AuthApi(client, store);

      final token = await auth.loginByUsername('xiao', 'pw');
      expect(token.accessToken, 'at-9');
      expect(reqs.single.url, ApiClient.apiBase);
      expect(reqs.single.authorization, 'Bearer ${ApiClient.publishableKey}');
      expect(reqs.single.jsonBody, {
        'path': '/auth/login',
        'method': 'POST',
        'params': {},
        'body': {'username': 'xiao', 'password': 'pw'},
      });
      final saved = await store.read();
      expect(saved!.accessToken, 'at-9');
      expect(saved.refreshToken, 'rt-9');
      expect(saved.expiresIn, 3600);
      expect(saved.savedAt, greaterThan(0));
      expect(await auth.isLoggedIn(), isTrue);
    });

    test('loginByUsername 失败：非 2xx 或 ok:false → message，缺省「登录失败」', () async {
      final reqs = <_Captured>[];
      final client = clientWith((pending, apiCount, _) =>
          apiCount == 0 ? (401, {'message': '用户名或密码错误'}, Duration.zero) : (200, {'ok': false}, Duration.zero), reqs);
      final auth = AuthApi(client, store);

      await expectLater(
        auth.loginByUsername('xiao', 'bad'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', '用户名或密码错误')),
      );
      await expectLater(
        auth.loginByUsername('xiao', 'bad'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', '登录失败')),
      );
      expect(await store.read(), isNull); // 失败不写 token
    });

    test('registerByUsername：envelope=/auth/register，成功不写 token；失败兜底「注册失败」', () async {
      final reqs = <_Captured>[];
      final client = clientWith((pending, apiCount, _) =>
          apiCount == 0 ? (200, {'ok': true}, Duration.zero) : (200, {'ok': false}, Duration.zero), reqs);
      final auth = AuthApi(client, store);

      await auth.registerByUsername('new', 'pw');
      expect(reqs[0].jsonBody['path'], '/auth/register');
      expect(reqs[0].authorization, 'Bearer ${ApiClient.publishableKey}');
      expect(await store.read(), isNull);

      await expectLater(
        auth.registerByUsername('dup', 'pw'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message', '注册失败')),
      );
    });

    test('logout 清 token → isLoggedIn false', () async {
      final reqs = <_Captured>[];
      await store.write(signedInToken());
      final client = clientWith((_, _, _) => (200, {'ok': true}, Duration.zero), reqs);
      final auth = AuthApi(client, store);

      await auth.logout();
      expect(await store.read(), isNull);
      expect(await auth.isLoggedIn(), isFalse);
    });
  });

  group('TokenStore（内存实现，接口对齐 js _loadToken/_saveToken/_clearToken）', () {
    test('write/read/clear 往返；clear 幂等', () async {
      expect(await store.read(), isNull);
      final t = signedInToken();
      await store.write(t);
      final r = await store.read();
      expect(r!.accessToken, 'old-at');
      expect(r.expiresIn, 7200);
      await store.clear();
      expect(await store.read(), isNull);
      await store.clear();
      expect(await store.read(), isNull);
    });
  });
}
