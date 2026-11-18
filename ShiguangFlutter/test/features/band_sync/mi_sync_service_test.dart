// ShiguangFlutter/test/features/band_sync/mi_sync_service_test.dart
// 自动同步服务：登录换票、每日活动落缓存、运动去重自动导入、部分失败记账。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiguang_flutter/data/mi_cloud_client.dart';
import 'package:shiguang_flutter/data/mi_crypto.dart';
import 'package:shiguang_flutter/data/mi_daily_activity_store.dart';
import 'package:shiguang_flutter/features/band_sync/mi_credentials_store.dart';
import 'package:shiguang_flutter/features/band_sync/mi_import_store.dart';
import 'package:shiguang_flutter/features/band_sync/mi_sync_service.dart';

class FakeCreds implements MiCredentialStore {
  FakeCreds([this.value]);
  MiCredentials? value;
  @override
  Future<MiCredentials?> load() async => value;
  @override
  Future<void> save(MiCredentials c) async => value = c;
  @override
  Future<void> clear() async => value = null;
}

class FakeSessionStore implements MiSessionStore {
  FakeSessionStore([this.value]);
  MiSession? value;
  int saves = 0;
  @override
  Future<MiSession?> load() async => value;
  @override
  Future<void> save(MiSession s) async {
    value = s;
    saves++;
  }

  @override
  Future<void> clear() async => value = null;
}

class FakeHttp implements MiCloudHttp {
  FakeHttp({this.loginOk = true, this.workouts = const [], this.daily = const {}});
  final bool loginOk;
  int getCalls = 0;
  bool loginDone = false;
  bool acceptWithoutLogin = false;
  Map<String, dynamic>? lastPayload;
  List<Map<String, dynamic>> workouts;
  Map<String, List<Map<String, dynamic>>> daily;
  static const ssecurity = [1, 2, 3, 4];
  String? lastTokenSaved;

  @override
  Future<MiHttpResponse> get(Uri uri, {Map<String, String>? headers}) async {
    getCalls++;
    if (uri.path == '/pass/serviceLogin') {
      if (!loginOk) return const MiHttpResponse(status: 200, body: 'bad');
      loginDone = true;
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
      'serviceToken=st; path=/',
    ]);
  }

  @override
  Future<MiHttpResponse> post(Uri uri,
      {Map<String, String>? headers, String? body}) async {
    if (!acceptWithoutLogin && !loginDone) {
      return const MiHttpResponse(status: 401, body: '');
    }
    final form = Uri.splitQueryString(body ?? '');
    final sn = genSignedNonce(ssecurity, base64.decode(form['_nonce']!));
    final payload =
        jsonDecode(utf8.decode(rc4Crypt(sn, base64.decode(form['data']!))))
            as Map<String, dynamic>;
    lastPayload = payload;
    final Map<String, dynamic> result;
    final key = payload['key'];
    if (key is String) {
      result = {
        'data_list': daily[key] ?? const <Map<String, dynamic>>[],
        'has_more': false,
      };
    } else {
      result = {
        'sport_records': workouts,
        'has_more': false,
      };
    }
    final plain = jsonEncode({'code': 0, 'result': result});
    return MiHttpResponse(
        status: 200, body: base64.encode(rc4Crypt(sn, utf8.encode(plain))));
  }
}

Map<String, dynamic> sportRecord(String id, String key, int ts, int cal) => {
      'sid': 1,
      'key': key,
      'time': ts,
      'value': jsonEncode({
        'start_time': ts,
        'end_time': ts + 600,
        'duration': 600,
        'distance': key == 'outdoor_running' ? 2000 : null,
        'calories': cal,
      }),
    };

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('未绑定凭据 → 返回 null，零动作', () async {
    final svc = MiSyncService(
      credentials: FakeCreds(),
      importStore: MiImportStore(),
      dailyStore: MiDailyActivityStore(),
      addExercise: (p) async => {'ok': true},
      clientFactory: () => MiCloudClient(FakeHttp()),
    );
    expect(await svc.run(weightKg: 76), isNull);
  });

  test('正常：轮换 token 保存、每日活动落缓存、新运动自动导入并记账', () async {
    final creds = FakeCreds(const MiCredentials(userId: '1', passToken: 'OLD'));
    final http = FakeHttp()
      ..workouts = [
        sportRecord('outdoor_running', 'outdoor_running', 1794990000, 200),
        sportRecord('rope_skipping', 'rope_skipping', 1794991000, 6),
      ]
      ..daily = {
        'steps': [
          {'time': 1794990000, 'value': jsonEncode({'time': 1794990000, 'steps': 100, 'distance': 80})},
        ],
        'calories': [
          {'time': 1794990000, 'value': jsonEncode({'time': 1794990000, 'calories': 5})},
        ],
      };
    final added = <Map<String, dynamic>>[];
    final svc = MiSyncService(
      credentials: creds,
      importStore: MiImportStore(),
      dailyStore: MiDailyActivityStore(),
      addExercise: (p) async {
        added.add(p);
        return {'ok': true};
      },
      clientFactory: () => MiCloudClient(http),
    );
    final out = await svc.run(weightKg: 76);
    expect(out, isNotNull);
    expect(out!.error, isNull);
    expect(out.imported, 1); // 跳绳类型不支持被跳过
    expect(added.single['key'], 'run');
    expect(creds.value!.passToken, 'NEW'); // 轮换 token 已落盘
    final daily = await MiDailyActivityStore().load();
    expect(daily.isNotEmpty, true);
    expect(daily.values.first.activeKcal, 5);
    final ledger = await MiImportStore().load();
    expect(ledger, hasLength(1));
    expect(svc.lastOkAt, isNotNull);
  });

  test('已导入的记录不重复导入', () async {
    SharedPreferences.setMockInitialValues({
      bandImportedIdsPrefKey: ['mi:1_outdoor_running_1794990000'],
    });
    final http = FakeHttp()
      ..workouts = [
        sportRecord('outdoor_running', 'outdoor_running', 1794990000, 200),
      ];
    var calls = 0;
    final svc = MiSyncService(
      credentials: FakeCreds(const MiCredentials(userId: '1', passToken: 'P')),
      importStore: MiImportStore(),
      dailyStore: MiDailyActivityStore(),
      addExercise: (p) async {
        calls++;
        return {'ok': true};
      },
      clientFactory: () => MiCloudClient(http),
    );
    final out = await svc.run(weightKg: 76);
    expect(out!.imported, 0);
    expect(calls, 0);
  });

  test('部分失败：已成功条目记账，错误如实返回', () async {
    final http = FakeHttp()
      ..workouts = [
        sportRecord('outdoor_running', 'outdoor_running', 1794990000, 200),
        sportRecord('outdoor_running', 'outdoor_running', 1794991000, 210),
      ];
    var n = 0;
    final svc = MiSyncService(
      credentials: FakeCreds(const MiCredentials(userId: '1', passToken: 'P')),
      importStore: MiImportStore(),
      dailyStore: MiDailyActivityStore(),
      addExercise: (p) async {
        n++;
        if (n == 2) return {'ok': false, 'message': '消耗热量无效'};
        return {'ok': true};
      },
      clientFactory: () => MiCloudClient(http),
    );
    final out = await svc.run(weightKg: 76);
    expect(out!.imported, 1);
    expect(out.error, '消耗热量无效');
    final ledger = await MiImportStore().load();
    expect(ledger, hasLength(1)); // 只记成功的那条
  });

  test('登录失效 → 错误分类，不写账本', () async {
    final svc = MiSyncService(
      credentials: FakeCreds(const MiCredentials(userId: '1', passToken: 'P')),
      importStore: MiImportStore(),
      dailyStore: MiDailyActivityStore(),
      addExercise: (p) async => {'ok': true},
      clientFactory: () => MiCloudClient(FakeHttp(loginOk: false)),
    );
    final out = await svc.run(weightKg: 76);
    expect(out!.error, contains('登录失效'));
    expect(await MiImportStore().load(), isEmpty);
  });

  test('缓存会话命中：不登录不轮换 token', () async {
    final session = MiSession(
        userId: '1', passToken: 'CACHED', ssecurity: FakeHttp.ssecurity, cookies: 'serviceToken=st');
    final sessionStore = FakeSessionStore(session);
    final http = FakeHttp()..acceptWithoutLogin = true;
    final svc = MiSyncService(
      credentials: FakeCreds(const MiCredentials(userId: '1', passToken: 'OLD')),
      importStore: MiImportStore(),
      dailyStore: MiDailyActivityStore(),
      sessionStore: sessionStore,
      addExercise: (p) async => {'ok': true},
      clientFactory: () => MiCloudClient(http),
    );
    final out = await svc.run(weightKg: 76);
    expect(out, isNotNull);
    expect(http.getCalls, 0); // 未调用登录
    expect(sessionStore.saves, 0);
  });

  test('缓存会话 401：丢弃缓存并重新登录，保存新会话', () async {
    final sessionStore = FakeSessionStore(MiSession(
        userId: '1', passToken: 'STALE', ssecurity: FakeHttp.ssecurity, cookies: 'stale'));
    final http = FakeHttp(); // 未登录前 post 全 401
    final creds = FakeCreds(const MiCredentials(userId: '1', passToken: 'OLD'));
    final svc = MiSyncService(
      credentials: creds,
      importStore: MiImportStore(),
      dailyStore: MiDailyActivityStore(),
      sessionStore: sessionStore,
      addExercise: (p) async => {'ok': true},
      clientFactory: () => MiCloudClient(http),
    );
    final out = await svc.run(weightKg: 76);
    expect(out, isNotNull);
    expect(http.getCalls, 2); // 重登一次（serviceLogin + location）
    expect(creds.value!.passToken, 'NEW');
    expect(sessionStore.saves, 1); // 新会话已缓存
  });

  test('动态窗口：距上次同步 12 天 → 拉取窗口扩展到 13 天', () async {
    final twelveAgo = DateTime.now().subtract(const Duration(days: 12));
    final iso = '${twelveAgo.year}-'
        '${twelveAgo.month.toString().padLeft(2, '0')}-'
        '${twelveAgo.day.toString().padLeft(2, '0')}';
    SharedPreferences.setMockInitialValues({miLastSyncPrefKey: iso});
    final http = FakeHttp()..workouts = [];
    final svc = MiSyncService(
      credentials: FakeCreds(const MiCredentials(userId: '1', passToken: 'P')),
      importStore: MiImportStore(),
      dailyStore: MiDailyActivityStore(),
      addExercise: (p) async => {'ok': true},
      clientFactory: () => MiCloudClient(http),
    );
    await svc.run(weightKg: 76);
    final start = http.lastPayload?['start_time'] as int?;
    expect(start, isNotNull);
    final days = (DateTime.now().millisecondsSinceEpoch ~/ 1000 - start!) / 86400;
    expect(days, greaterThanOrEqualTo(12));
  });
}
