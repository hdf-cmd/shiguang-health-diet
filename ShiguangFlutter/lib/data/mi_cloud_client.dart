// ShiguangFlutter/lib/data/mi_cloud_client.dart
// 小米运动健康云端只读客户端（社区逆向协议，参考 mi_fitness_data_bridge
// 的行为独立实现，未复制其源码）。
//
// 链路（与 Python 参考实现逐字段对齐）：
// 1) GET account.xiaomi.com/pass/serviceLogin?_json=true&sid=miothealth
//    Cookie: userId/passToken → 返回轮换后的 passToken + ssecurity + location；
// 2) GET location → Set-Cookie 里的 serviceToken 即数据接口会话；
// 3) POST hlth.io.mi.com/app/v1/data/get_sport_records_by_time，
//    RC4 + SHA1 签名（见 mi_crypto.dart），响应 RC4 解密。
// 注意：passToken 每次登录都会轮换，调用方必须把返回的新值写回安全存储，
// 否则下次登录必然失败。
//
// 分层：HTTP 走 [MiCloudHttp] 抽象（真实现 MiDioHttp），单测注入 fake。
import 'dart:convert';

import 'package:dio/dio.dart';

import 'mi_crypto.dart';

class MiAuthException implements Exception {
  const MiAuthException(this.message);
  final String message;
  @override
  String toString() => 'MiAuthException($message)';
}

class MiApiException implements Exception {
  const MiApiException(this.message, {this.code});
  final String message;
  final int? code;
  @override
  String toString() => 'MiApiException($code: $message)';
}

/// 一次登录后的会话（passToken 可能已被服务端轮换）。
class MiSession {
  const MiSession({
    required this.userId,
    required this.passToken,
    required this.ssecurity,
    required this.cookies,
  });

  final String userId;
  final String passToken;
  final List<int> ssecurity;
  final String cookies;
}

/// 云端一条运动记录（字段来自 sport_records[].value）。
class MiWorkout {
  const MiWorkout({
    required this.workoutId,
    required this.activityType,
    required this.startAt,
    required this.endAt,
    required this.durationMinutes,
    this.distanceM,
    this.caloriesKcal,
    this.avgHeartRate,
    this.maxHeartRate,
    this.steps,
  });

  final String workoutId;
  final String activityType;
  final DateTime startAt;
  final DateTime endAt;
  final int durationMinutes;
  final double? distanceM;
  final double? caloriesKcal;
  final int? avgHeartRate;
  final int? maxHeartRate;
  final int? steps;
}

/// 云端一天的活动汇总（全天口径，含日常活动与单次运动）。
class MiDailyActivity {
  const MiDailyActivity({
    required this.date,
    required this.steps,
    required this.distanceM,
    required this.activeKcal,
  });

  final String date;
  final int steps;
  final double distanceM;

  /// 全天活动热量（分钟切片求和，手环口径）。
  final double activeKcal;
}

class MiHttpResponse {
  const MiHttpResponse({
    required this.status,
    required this.body,
    this.setCookies = const [],
  });

  final int status;
  final String body;
  final List<String> setCookies;
}

/// HTTP 门面（单测注入 fake；真实现见 MiDioHttp）。
abstract class MiCloudHttp {
  Future<MiHttpResponse> get(Uri uri, {Map<String, String>? headers});
  Future<MiHttpResponse> post(Uri uri,
      {Map<String, String>? headers, String? body});
}

/// 真实现：独立 Dio 实例，不挂任何业务拦截器，也不带 cookies 管理器。
class MiDioHttp implements MiCloudHttp {
  MiDioHttp([Dio? dio])
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 20),
              followRedirects: false,
              validateStatus: (_) => true,
            ));

  final Dio _dio;

  MiHttpResponse _wrap(Response<dynamic> r) {
    final headers = r.headers.map;
    final setCookies = <String>[
      if (headers['set-cookie'] != null) ...headers['set-cookie']!,
    ];
    return MiHttpResponse(
      status: r.statusCode ?? 0,
      body: r.data is String ? r.data as String : jsonEncode(r.data),
      setCookies: setCookies,
    );
  }

  @override
  Future<MiHttpResponse> get(Uri uri, {Map<String, String>? headers}) async =>
      _wrap(await _dio.getUri<String>(uri, options: Options(headers: headers)));

  @override
  Future<MiHttpResponse> post(Uri uri,
          {Map<String, String>? headers, String? body}) async =>
      _wrap(await _dio.postUri<String>(uri,
          data: body, options: Options(headers: headers)));
}

const _loginPrefix = '&&&START&&&';

class MiCloudClient {
  MiCloudClient(this._http);

  final MiCloudHttp _http;

  static final Uri _loginUri = Uri.parse(
      'https://account.xiaomi.com/pass/serviceLogin?_json=true&sid=miothealth');

  /// 用 userId + passToken 登录。返回的 [MiSession.passToken] 必须写回存储。
  Future<MiSession> login(String userId, String passToken) async {
    final resp = await _http.get(_loginUri,
        headers: {'Cookie': 'userId=$userId; passToken=$passToken'});
    if (resp.status != 200 || !resp.body.startsWith(_loginPrefix)) {
      throw const MiAuthException('登录响应异常，凭据可能已失效');
    }
    final Map<String, dynamic> payload;
    try {
      payload = jsonDecode(resp.body.substring(_loginPrefix.length))
          as Map<String, dynamic>;
    } catch (_) {
      throw const MiAuthException('登录响应解析失败');
    }
    final newPass = payload['passToken'];
    final newUser = '${payload['userId'] ?? ''}';
    final ssecurityB64 = payload['ssecurity'];
    final location = payload['location'];
    if (newPass is! String ||
        newPass.isEmpty ||
        newUser.isEmpty ||
        ssecurityB64 is! String ||
        ssecurityB64.isEmpty ||
        location is! String ||
        location.isEmpty) {
      throw const MiAuthException('登录响应缺少必要字段');
    }
    final loc = Uri.tryParse(location);
    if (loc == null ||
        loc.scheme != 'https' ||
        !(loc.host == 'xiaomi.com' ||
            loc.host.endsWith('.xiaomi.com') ||
            loc.host == 'mi.com' ||
            loc.host.endsWith('.mi.com'))) {
      throw const MiAuthException('登录跳转地址不可信');
    }
    final redirect = await _http.get(loc);
    final cookieParts = redirect.setCookies
        .map((c) => c.split(';').first.trim())
        .where((c) => c.isNotEmpty)
        .toList();
    if (!cookieParts.any((c) => c.startsWith('serviceToken=') && c != 'serviceToken=')) {
      throw const MiAuthException('登录未返回 serviceToken');
    }
    return MiSession(
      userId: newUser,
      passToken: newPass,
      ssecurity: base64.decode(ssecurityB64),
      cookies: cookieParts.join('; '),
    );
  }

  /// 拉取 [start, end]（按设备本地日历日）内的运动记录，自动翻页。
  Future<List<MiWorkout>> fetchWorkouts({
    required MiSession session,
    required DateTime start,
    required DateTime end,
    int maxPages = 50,
  }) async {
    final startTs = DateTime(start.year, start.month, start.day)
            .millisecondsSinceEpoch ~/
        1000;
    final endTs = DateTime(end.year, end.month, end.day, 23, 59, 59)
            .millisecondsSinceEpoch ~/
        1000;
    final out = <MiWorkout>[];
    String? nextKey;
    final seen = <String>{};
    for (var page = 1; page <= maxPages; page++) {
      final payload = <String, dynamic>{
        'start_time': startTs,
        'end_time': endTs,
        'limit': 50,
        'next_key': ?nextKey,
      };
      final result = await _request(session, '/app/v1/data/get_sport_records_by_time', payload);
      final records = result['sport_records'];
      if (records is List) {
        for (final r in records) {
          if (r is! Map) continue;
          final w = _parseWorkout(Map<String, dynamic>.from(r));
          if (w != null) out.add(w);
        }
      }
      final hasMore = result['has_more'] == true;
      final nk = result['next_key'];
      if (!hasMore || nk == null) break;
      final key = '$nk';
      if (!seen.add(key)) {
        throw const MiApiException('分页游标循环');
      }
      nextKey = key;
    }
    return out;
  }

  /// 拉取 [start, end] 内每天的步数/距离/活动热量（分钟切片聚合）。
  /// 步数按「日期+分钟」去重取最大，避免手机与手环并行上报双计；
  /// 热量按参考实现口径直接按天求和。
  Future<List<MiDailyActivity>> fetchDailyActivity({
    required MiSession session,
    required DateTime start,
    required DateTime end,
    int maxPages = 50,
  }) async {
    final stepItems = await _fetchKey(session, 'steps', start, end, maxPages);
    final calItems = await _fetchKey(session, 'calories', start, end, maxPages);

    final perMinute = <String, Map<String, _MinuteSlice>>{};
    for (final item in stepItems) {
      final payload = _valueOf(item);
      final ts = _asInt(payload['time'] ?? item['time'] ?? payload['timestamp']);
      if (ts == null) continue;
      final t = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      final date = _localDateOf(t);
      final minute = '${t.hour.toString().padLeft(2, '0')}:'
          '${t.minute.toString().padLeft(2, '0')}';
      final steps = _asInt(payload['steps']) ?? 0;
      final slice = _MinuteSlice(
        steps: steps,
        distanceM: _asDouble(payload['distance']) ?? 0,
      );
      final day = perMinute.putIfAbsent(date, () => <String, _MinuteSlice>{});
      final existing = day[minute];
      if (existing == null || slice.steps > existing.steps) {
        day[minute] = slice;
      }
    }
    final kcalByDate = <String, double>{};
    for (final item in calItems) {
      final payload = _valueOf(item);
      final ts = _asInt(payload['time'] ?? item['time'] ?? payload['timestamp']);
      if (ts == null) continue;
      final date = _localDateOf(
          DateTime.fromMillisecondsSinceEpoch(ts * 1000));
      kcalByDate[date] =
          (kcalByDate[date] ?? 0) + (_asDouble(payload['calories']) ?? 0);
    }

    final dates = <String>{...perMinute.keys, ...kcalByDate.keys}.toList()
      ..sort();
    return [
      for (final d in dates)
        MiDailyActivity(
          date: d,
          steps: (perMinute[d] ?? const <String, _MinuteSlice>{})
              .values
              .fold<int>(0, (a, s) => a + s.steps),
          distanceM: (perMinute[d] ?? const <String, _MinuteSlice>{})
              .values
              .fold<double>(0, (a, s) => a + s.distanceM),
          activeKcal: kcalByDate[d] ?? 0,
        ),
    ];
  }

  /// 通用键值拉取（get_fitness_data_by_time），返回 data_list 原始项。
  Future<List<Map<String, dynamic>>> _fetchKey(
      MiSession session, String key, DateTime start, DateTime end, int maxPages) async {
    final startTs = DateTime(start.year, start.month, start.day)
            .millisecondsSinceEpoch ~/
        1000;
    final endTs = DateTime(end.year, end.month, end.day, 23, 59, 59)
            .millisecondsSinceEpoch ~/
        1000;
    final out = <Map<String, dynamic>>[];
    String? nextKey;
    final seen = <String>{};
    for (var page = 1; page <= maxPages; page++) {
      final payload = <String, dynamic>{
        'start_time': startTs,
        'end_time': endTs,
        'key': key,
        'next_key': ?nextKey,
      };
      final result = await _request(session, '/app/v1/data/get_fitness_data_by_time', payload);
      final list = result['data_list'];
      if (list is List) {
        for (final item in list) {
          if (item is Map) out.add(Map<String, dynamic>.from(item));
        }
      }
      final nk = result['next_key'];
      if (result['has_more'] != true || nk == null) break;
      final k = '$nk';
      if (!seen.add(k)) throw const MiApiException('分页游标循环');
      nextKey = k;
    }
    return out;
  }

  static Map<String, dynamic> _valueOf(Map<String, dynamic> item) {
    final raw = item['value'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is String) {
      try {
        final m = jsonDecode(raw);
        if (m is Map) return Map<String, dynamic>.from(m);
      } catch (_) {}
    }
    return <String, dynamic>{};
  }

  MiWorkout? _parseWorkout(Map<String, dynamic> item) {
    dynamic raw = item['value'];
    if (raw is String) {
      try {
        raw = jsonDecode(raw);
      } catch (_) {
        return null;
      }
    }
    final payload = raw is Map ? Map<String, dynamic>.from(raw) : <String, dynamic>{};
    final startTs = _asInt(payload['start_time']) ?? _asInt(item['time']);
    if (startTs == null) return null;
    final durationSec = _asInt(payload['duration']) ?? 0;
    final endTs = _asInt(payload['end_time']) ??
        (durationSec > 0 ? startTs + durationSec : null);
    if (endTs == null || endTs <= startTs) return null;
    var minutes = durationSec > 0 ? durationSec ~/ 60 : (endTs - startTs) ~/ 60;
    if (minutes <= 0) minutes = (endTs - startTs) ~/ 60;
    final activity = '${item['category'] ?? item['key'] ?? payload['sport_type'] ?? 'workout'}';
    final workoutId = '${item['sid'] ?? ''}_${item['key'] ?? 'workout'}_'
        '${item['time'] ?? startTs}';
    return MiWorkout(
      workoutId: workoutId,
      activityType: activity,
      startAt: DateTime.fromMillisecondsSinceEpoch(startTs * 1000),
      endAt: DateTime.fromMillisecondsSinceEpoch(endTs * 1000),
      durationMinutes: minutes,
      distanceM: _asDouble(payload['distance']),
      caloriesKcal:
          _asDouble(payload['calories'] ?? payload['total_cal']),
      avgHeartRate: _asInt(payload['avg_hrm']),
      maxHeartRate: _asInt(payload['max_hrm']),
      steps: _asInt(payload['steps'] ?? payload['total_steps']),
    );
  }

  /// 加密请求 + 解密响应，失败抛 [MiApiException]。
  Future<Map<String, dynamic>> _request(
      MiSession session, String path, Map<String, dynamic> payload) async {
    final data = jsonEncode(payload);
    final nonce = genNonce();
    final signedNonce = genSignedNonce(session.ssecurity, nonce);
    final form = <String, String>{'data': data};
    form['rc4_hash__'] = genSignature('POST', path, form, signedNonce);
    final encrypted = <String, String>{
      for (final e in form.entries)
        e.key: base64.encode(rc4Crypt(signedNonce, utf8.encode(e.value))),
    };
    encrypted['signature'] =
        genSignature('POST', path, encrypted, signedNonce);
    // _nonce 不参与签名，服务端据此还原 signedNonce（mi_fitness_cloud.py:336-337）。
    encrypted['_nonce'] = base64.encode(nonce);
    final body = Uri(queryParameters: encrypted).query;
    final resp = await _http.post(
      Uri.parse('https://hlth.io.mi.com$path'),
      headers: {
        'Cookie': session.cookies,
        'Content-Type': 'application/x-www-form-urlencoded',
      },
      body: body,
    );
    if (resp.status == 401 || resp.status == 403) {
      throw const MiAuthException('云端会话失效，请重新绑定');
    }
    if (resp.status != 200) {
      throw MiApiException('云端返回 HTTP ${resp.status}');
    }
    Map<String, dynamic> json;
    try {
      final plain = utf8.decode(
          rc4Crypt(signedNonce, base64.decode(resp.body.trim())));
      json = jsonDecode(plain) as Map<String, dynamic>;
    } catch (_) {
      throw const MiApiException('云端响应解密失败');
    }
    final code = _asInt(json['code']);
    if (code != 0) {
      throw MiApiException('${json['message'] ?? '未知错误'}', code: code);
    }
    final result = json['result'];
    return result is Map ? Map<String, dynamic>.from(result) : <String, dynamic>{};
  }

  static String _localDateOf(DateTime t) {
    final d = t.toLocal();
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  static int? _asInt(dynamic v) => v is num ? v.toInt() : int.tryParse('${v ?? ''}');

  static double? _asDouble(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
}


class _MinuteSlice {
  const _MinuteSlice({required this.steps, required this.distanceM});
  final int steps;
  final double distanceM;
}
