// ShiguangFlutter/test/data/mi_cloud_client_test.dart
// 云客户端用例：登录换票（轮换 passToken/校验跳转）与加密拉取（fake HTTP
// 按真实协议解密请求、加密响应，验证整条编解码链路）。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/data/mi_cloud_client.dart';
import 'package:shiguang_flutter/data/mi_crypto.dart';

class FakeMiHttp implements MiCloudHttp {
  FakeMiHttp({this.ssecurity = const [1, 2, 3, 4]});

  final List<int> ssecurity;
  int getCalls = 0;
  int postCalls = 0;
  String? lastLoginCookie;
  Map<String, dynamic>? lastPayload;
  List<Map<String, dynamic>> pages = const [];
  Map<String, List<Map<String, dynamic>>> daily = const {};

  @override
  Future<MiHttpResponse> get(Uri uri, {Map<String, String>? headers}) async {
    getCalls++;
    if (uri.host == 'account.xiaomi.com' && uri.path == '/pass/serviceLogin') {
      lastLoginCookie = headers?['Cookie'];
      final payload = {
        'passToken': 'NEW_TOKEN',
        'userId': 3209281166,
        'ssecurity': base64.encode(ssecurity),
        'location': 'https://account.xiaomi.com/pass/ok?x=1',
      };
      return MiHttpResponse(
          status: 200, body: '&&&START&&&${jsonEncode(payload)}');
    }
    if (uri.host == 'account.xiaomi.com' && uri.path == '/pass/ok') {
      return const MiHttpResponse(status: 200, body: '', setCookies: [
        'serviceToken=st123; path=/',
        'cUserId=u1; path=/',
      ]);
    }
    return const MiHttpResponse(status: 404, body: '');
  }

  @override
  Future<MiHttpResponse> post(Uri uri,
      {Map<String, String>? headers, String? body}) async {
    postCalls++;
    final form = Uri.splitQueryString(body ?? '');
    final nonce = base64.decode(form['_nonce']!);
    final sn = genSignedNonce(ssecurity, nonce);
    final data =
        utf8.decode(rc4Crypt(sn, base64.decode(form['data']!)));
    lastPayload = jsonDecode(data) as Map<String, dynamic>;
    final key = lastPayload?['key'];
    final Map<String, dynamic> result;
    if (key is String) {
      result = <String, dynamic>{
        'data_list': daily[key] ?? const <Map<String, dynamic>>[],
        'has_more': false,
      };
    } else {
      result = pages.isEmpty ? <String, dynamic>{} : pages.removeAt(0);
    }
    final plain = jsonEncode({'code': 0, 'result': result});
    final encrypted =
        base64.encode(rc4Crypt(sn, utf8.encode(plain)));
    return MiHttpResponse(status: 200, body: encrypted);
  }
}

void main() {
  test('login：带 cookie 请求、解析前缀 JSON、换 serviceToken、返回轮换 token',
      () async {
    final http = FakeMiHttp();
    final client = MiCloudClient(http);
    final s = await client.login('3209281166', 'OLD');
    expect(http.lastLoginCookie, 'userId=3209281166; passToken=OLD');
    expect(s.userId, '3209281166');
    expect(s.passToken, 'NEW_TOKEN');
    expect(s.cookies, contains('serviceToken=st123'));
    expect(s.ssecurity, [1, 2, 3, 4]);
  });

  test('login：响应前缀异常 → MiAuthException', () async {
    final http = _BrokenLoginHttp('not-a-login-response');
    final client = MiCloudClient(http);
    await expectLater(
        client.login('u', 'p'), throwsA(isA<MiAuthException>()));
  });

  test('login：不可信跳转地址 → MiAuthException', () async {
    final http = _EvilLocationHttp();
    final client = MiCloudClient(http);
    await expectLater(
        client.login('u', 'p'), throwsA(isA<MiAuthException>()));
  });

  test('login：缺少 serviceToken → MiAuthException', () async {
    final http = _NoServiceTokenHttp();
    final client = MiCloudClient(http);
    await expectLater(
        client.login('u', 'p'), throwsA(isA<MiAuthException>()));
  });

  test('fetchWorkouts：加密请求可被服务端解密，分页与字段解析正确', () async {
    final http = FakeMiHttp()
      ..pages = [
        {
          'sport_records': [
            {
              'sid': 2257914208,
              'key': 'outdoor_running',
              'time': 1794395519,
              'value': jsonEncode({
                'start_time': 1794395519,
                'end_time': 1794396567,
                'duration': 1048,
                'distance': 2834,
                'calories': 190,
                'avg_hrm': 153,
                'max_hrm': 171,
              }),
            }
          ],
          'has_more': true,
          'next_key': 'k2',
        },
        {
          'sport_records': [
            {
              'sid': 2257914208,
              'key': 'rope_skipping',
              'time': 1794991513,
              'value': jsonEncode({
                'start_time': 1794991513,
                'end_time': 1794991615,
                'duration': 102,
                'calories': 6,
              }),
            }
          ],
          'has_more': false,
        },
      ];
    final client = MiCloudClient(http);
    final list = await client.fetchWorkouts(
      session: MiSession(
          userId: 'u',
          passToken: 'p',
          ssecurity: http.ssecurity,
          cookies: 'serviceToken=st123'),
      start: DateTime(2026, 11, 11),
      end: DateTime(2026, 11, 18),
    );
    expect(http.postCalls, 2);
    expect(http.lastPayload?['limit'], 50);
    expect(list, hasLength(2));
    final run = list.first;
    expect(run.activityType, 'outdoor_running');
    expect(run.distanceM, 2834);
    expect(run.caloriesKcal, 190);
    expect(run.avgHeartRate, 153);
    expect(run.durationMinutes, 17);
    final rope = list.last;
    expect(rope.activityType, 'rope_skipping');
    expect(rope.durationMinutes, 1);
  });

  test('fetchDailyActivity：分钟切片去重、热量按天求和', () async {
    final http = FakeMiHttp()
      ..daily = {
        'steps': [
          // 同一分钟两条（手机+手环并行），取步数较大的那条
          {'time': 1794990000, 'value': jsonEncode({'time': 1794990000, 'steps': 40, 'distance': 30})},
          {'time': 1794990005, 'value': jsonEncode({'time': 1794990005, 'steps': 52, 'distance': 39})},
          {'time': 1794990060, 'value': jsonEncode({'time': 1794990060, 'steps': 10, 'distance': 8})},
        ],
        'calories': [
          {'time': 1794990000, 'value': jsonEncode({'time': 1794990000, 'calories': 3})},
          {'time': 1794990060, 'value': jsonEncode({'time': 1794990060, 'calories': 2})},
        ],
      };
    final client = MiCloudClient(http);
    final days = await client.fetchDailyActivity(
      session: MiSession(
          userId: 'u', passToken: 'p', ssecurity: http.ssecurity, cookies: ''),
      start: DateTime(2026, 11, 18),
      end: DateTime(2026, 11, 18),
    );
    expect(days, hasLength(1));
    expect(days.single.steps, 62); // 52 + 10（同分钟取大，不双计）
    expect(days.single.distanceM, closeTo(47, 0.001)); // 39 + 8
    expect(days.single.activeKcal, 5);
  });

  test('页面 code 非 0 → MiApiException', () async {
    final http = _ErrorCodeHttp();
    final client = MiCloudClient(http);
    await expectLater(
      client.fetchWorkouts(
        session: MiSession(
            userId: 'u', passToken: 'p', ssecurity: const [1], cookies: ''),
        start: DateTime(2026, 11, 11),
        end: DateTime(2026, 11, 18),
      ),
      throwsA(isA<MiApiException>()),
    );
  });
}

class _BrokenLoginHttp extends FakeMiHttp {
  _BrokenLoginHttp(this.body);
  final String body;
  @override
  Future<MiHttpResponse> get(Uri uri, {Map<String, String>? headers}) async =>
      body == 'x'
          ? const MiHttpResponse(status: 200, body: 'x')
          : MiHttpResponse(status: 200, body: body);
}

class _EvilLocationHttp extends FakeMiHttp {
  @override
  Future<MiHttpResponse> get(Uri uri, {Map<String, String>? headers}) async {
    if (uri.host == 'account.xiaomi.com' && uri.path == '/pass/serviceLogin') {
      final payload = {
        'passToken': 'NEW',
        'userId': 1,
        'ssecurity': base64.encode(ssecurity),
        'location': 'https://evil.example.com/steal',
      };
      return MiHttpResponse(
          status: 200, body: '&&&START&&&${jsonEncode(payload)}');
    }
    return const MiHttpResponse(status: 200, body: '');
  }
}

class _NoServiceTokenHttp extends FakeMiHttp {
  @override
  Future<MiHttpResponse> get(Uri uri, {Map<String, String>? headers}) async {
    if (uri.host == 'account.xiaomi.com' && uri.path == '/pass/serviceLogin') {
      final payload = {
        'passToken': 'NEW',
        'userId': 1,
        'ssecurity': base64.encode(ssecurity),
        'location': 'https://account.xiaomi.com/pass/ok',
      };
      return MiHttpResponse(
          status: 200, body: '&&&START&&&${jsonEncode(payload)}');
    }
    return const MiHttpResponse(status: 200, body: '', setCookies: [
      'cUserId=u1; path=/',
    ]);
  }
}

class _ErrorCodeHttp extends FakeMiHttp {
  @override
  Future<MiHttpResponse> post(Uri uri,
      {Map<String, String>? headers, String? body}) async {
    final form = Uri.splitQueryString(body ?? '');
    final nonce = base64.decode(form['_nonce']!);
    final sn = genSignedNonce(const [1], nonce);
    final plain = jsonEncode({'code': 401, 'message': 'auth failed'});
    return MiHttpResponse(
        status: 200, body: base64.encode(rc4Crypt(sn, utf8.encode(plain))));
  }
}
