// ShiguangFlutter/lib/data/api_client.dart
// 网络层单入口客户端。契约唯一权威源：js/api.js:16-17（API_BASE）、26
// （GW_BASE）、20（PUBLISHABLE_KEY）、34-56（_refreshToken/_doRefreshToken
// 单飞续期）、239-265（realRequest：envelope/Bearer/15s 超时/401 重试/错误映射）。
// Dart 侧与 js 逐分支等价；偏差点在方法注释里逐条标明。

import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import 'token_store.dart';

/// 业务层统一异常：message 语义与 js 抛出的 Error(message) 一致。
class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => 'ApiException: $message';
}

/// 单入口请求的低层返回：HTTP 状态码 + 响应 JSON（解析失败按空对象，
/// 对齐 js/api.js:251 的 `resp.json().catch(() => ({}))`）。
typedef RawResponse = ({int status, Map<String, dynamic> data});

class ApiClient {
  ApiClient({required TokenStore tokenStore, Dio? dio})
      : _store = tokenStore,
        _dio = dio ?? defaultDio();

  /// 云函数单入口（js/api.js:17）
  static const String apiBase =
      'https://cloud1-d6g4x9h9m507b429c.api.tcloudbasegateway.com/v1/functions/api-diet';

  /// 网关根（js/api.js:26），续期走 $gwBase/auth/v1/token
  static const String gwBase =
      'https://cloud1-d6g4x9h9m507b429c.api.tcloudbasegateway.com';

  /// 匿名公开凭证（js/api.js:20 PUBLISHABLE_KEY，exp=4092957074 即 2099 年前有效）
  static const String publishableKey =
      'eyJhbGciOiJSUzI1NiIsImtpZCI6IjlkMWRjMzFlLWI0ZDAtNDQ4Yi1hNzZmLWIwY2M2M2Q4MTQ5OCJ9.eyJpc3MiOiJodHRwczovL2Nsb3VkMS1kNmc0eDloOW01MDdiNDI5Yy5hcC1zaGFuZ2hhaS50Y2ItYXBpLnRlbmNlbnRjbG91ZGFwaS5jb20iLCJzdWIiOiJhbm9uIiwiYXVkIjoiY2xvdWQxLWQ2ZzR4OWg5bTUwN2I0MjljIiwiZXhwIjo0MDkyOTU3MDc0LCJpYXQiOjE3ODkyNzM4NzQsIm5vbmNlIjoieURIazNvS0FUcUdWbElUUFZ6d2VzdyIsImF0X2hhc2giOiJ5REhrM29LQVRxR1ZsSVRQVnp3ZXN3IiwibmFtZSI6IkFub255bW91cyIsInNjb3BlIjoiYW5vbnltb3VzIiwicHJvamVjdF9pZCI6ImNsb3VkMS1kNmc0eDloOW01MDdiNDI5YyIsIm1ldGEiOnsicGxhdGZvcm0iOiJQdWJsaXNoYWJsZUtleSJ9LCJ1c2VyX3R5cGUiOiIiLCJjbGllbnRfdHlwZSI6ImNsaWVudF91c2VyIiwiaXNfc3lzdGVtX2FkbWluIjpmYWxzZX0.fjfcG-D1b9n7gZ7BtQTcwB82EwxlxzDx2ULaJ-S2ONWX04D2-WQfjR060QNprSsG3CR-agmO-ACSAv7gckCLCF01WcoQONKGKRlRRG8qvVpPTtHOM3lSn5VbJK9_Mhhm1Ex8YqPFxl_7XrLv4iFR-4dycOrImsuYTjfcf4NFCPzzFe5sed1cs-aoXvlIXNMvoJPXhT9mHh8XHoIuWGJJf6upi0rLc130Qm-u7lFZxuwX-_ikhyyYFtP0Wy9cC3E9UsHi6bn3lIYbbs07RtRYNyz6XOjr6nPZ2GJhPd75YGdvdy9mhGoNVtxW8zUlIo8q00EAltlEvtVjhWDc70D-rw';

  /// 未注入 Dio 时使用的默认实例：三超时恒 15s。
  /// 对齐 js/api.js:249 的 AbortSignal.timeout(15000)。
  /// 提为 @visibleForTesting 静态工厂，使「注入 Dio 路径无超时保证」
  /// 这一契约缺口可被单测显式断言（评审 T5 Important）。
  @visibleForTesting
  static Dio defaultDio() {
    return Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 15),
    ));
  }

  final TokenStore _store;
  final Dio _dio;

  /// single-flight：并发 401 共享同一次续期（对齐 js/api.js:36-42 的
  /// _refreshInflight，避免 refresh_token 轮换互踩）。
  Future<bool>? _refreshInflight;

  /// 业务请求入口。path 为路由表里的路径模板（可含 :param），
  /// params 既用于替换 :param（encodeURIComponent 语义），也原样进 envelope。
  /// 返回响应 JSON；一切业务/HTTP 错误统一抛 [ApiException]。
  Future<Map<String, dynamic>> call(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? params,
    Map<String, dynamic>? body,
  }) async {
    final effParams = params ?? const <String, dynamic>{};
    final filledPath = _fillPathParams(path, effParams);
    final t = await _store.read();

    // js/api.js:255：有 token 用 accessToken，否则用 PUBLISHABLE_KEY。
    // 偏差说明：js 里 token 存在但 accessToken 为 undefined 会发
    // "Bearer undefined"；实际登录成功必写 accessToken（js/api.js:308），
    // 该分支不可能出现，故此处 null 直接回落 PK。
    var resp = await _doFetch(filledPath, method, effParams, body,
        t?.accessToken ?? publishableKey);

    // js/api.js:258-260：401 且本地有 token → 静默续期一次，成功则用新 token 重试一次
    if (resp.status == 401 && t != null && await _refreshToken()) {
      final t2 = await _store.read();
      resp = await _doFetch(filledPath, method, effParams, body,
          t2?.accessToken ?? publishableKey);
    }
    // js/api.js:261：仍 401（含无 token 从未进续期的情形）→ 清 token 抛固定文案
    if (resp.status == 401) {
      await _store.clear();
      throw ApiException('登录已过期，请重新登录');
    }
    // js/api.js:262：非 200 → data.message || `请求失败(${status})`
    if (resp.status != 200) {
      throw ApiException(_fallbackMessage(resp.data, '请求失败(${resp.status})'));
    }
    // js/api.js:263：200 但 ok:false → data.message || '操作失败'
    if (resp.data['ok'] == false) {
      throw ApiException(_fallbackMessage(resp.data, '操作失败'));
    }
    return resp.data;
  }

  /// 低层直发：envelope 恒用 PUBLISHABLE_KEY，不做 401 续期
  /// （供 AuthApi 的 login/register 用，对齐 js/api.js:290-308 的裸 fetch）。
  Future<RawResponse> postPublishable(
      String path, Map<String, dynamic> body) async {
    return _doFetch(path, 'POST', const {}, body, publishableKey);
  }

  /// js/api.js:244-253 的 doFetch：POST API_BASE，body 为
  /// {path, method, params, body: body||{}}，头 Content-Type json + Bearer。
  Future<RawResponse> _doFetch(String path, String method,
      Map<String, dynamic> params, Map<String, dynamic>? body, String bearer) async {
    final resp = await _dio.post<String>(
      apiBase,
      data: <String, dynamic>{
        'path': path,
        'method': method,
        'params': params,
        'body': body ?? <String, dynamic>{},
      },
      options: Options(
        contentType: 'application/json',
        responseType: ResponseType.plain,
        headers: {'Authorization': 'Bearer $bearer'},
        // 状态码判定全部由本类按 js 分支自行处理（validateStatus 全放行）
        validateStatus: (_) => true,
      ),
    );
    return (status: resp.statusCode ?? 0, data: _decodeJsonObject(resp.data));
  }

  /// single-flight 包装（js/api.js:37-42）：并发调用共享同一个 Future，
  /// 完成后清掉槽位（等价 .finally(() => _refreshInflight = null)）。
  Future<bool> _refreshToken() {
    final inflight = _refreshInflight;
    if (inflight != null) return inflight;
    final future =
        _doRefreshToken().whenComplete(() => _refreshInflight = null);
    _refreshInflight = future;
    return future;
  }

  /// js/api.js:43-56 的 _doRefreshToken。
  /// 偏差说明：js 里 refresh_token 缺失返回 false、响应 JSON 非法会抛
  /// SyntaxError 冒泡；此处 JSON 非法同样冒泡（保持冒泡语义），仅
  /// access_token 缺失/为空按 falsy 返回 false。
  Future<bool> _doRefreshToken() async {
    final t = await _store.read();
    final rt = t?.refreshToken;
    if (t == null || rt == null || rt.isEmpty) return false; // !t.refreshToken
    final resp = await _dio.post<String>(
      '$gwBase/auth/v1/token',
      data: {'grant_type': 'refresh_token', 'refresh_token': rt},
      options: Options(
        contentType: 'application/json',
        responseType: ResponseType.plain,
        validateStatus: (_) => true,
      ),
    );
    if (resp.statusCode == null ||
        resp.statusCode! < 200 ||
        resp.statusCode! > 299) {
      return false; // !resp.ok
    }
    final data = _decodeStrict(resp.data);
    final accessToken = data['access_token'];
    if (accessToken is! String || accessToken.isEmpty) return false;
    final newRt = data['refresh_token'];
    final expiresIn = data['expires_in'];
    await _store.write(t.copyWith(
      accessToken: accessToken,
      // refresh_token || 旧值（js/api.js:54）
      refreshToken: (newRt is String && newRt.isNotEmpty) ? newRt : rt,
      expiresIn: (expiresIn is num && expiresIn.toInt() != 0)
          ? expiresIn.toInt()
          : 7200, // expires_in || 7200
      savedAt: DateTime.now().millisecondsSinceEpoch,
    ));
    return true;
  }

  /// :param 替换（js/api.js:242：逐 key `path.replace(':k', encodeURIComponent(v))`，
  /// 每 key 只替换首次出现；Dart 用 replaceFirst 对齐）。
  String _fillPathParams(String path, Map<String, dynamic> params) {
    var p = path;
    params.forEach((k, v) {
      p = p.replaceFirst(':$k', Uri.encodeComponent('$v'));
    });
    return p;
  }

  /// 宽松解码：null/非法/非对象 → {}（对齐 js `resp.json().catch(() => ({}))`
  /// 后 `data.message` 恒取不到值的行为）。
  Map<String, dynamic> _decodeJsonObject(String? raw) {
    try {
      final decoded = jsonDecode(raw ?? '');
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      // fallthrough
    }
    return <String, dynamic>{};
  }

  /// 严格解码（续期用）：非法 JSON 抛异常冒泡，对齐 js 不 catch 的行为。
  Map<String, dynamic> _decodeStrict(String? raw) {
    final decoded = jsonDecode(raw ?? '');
    if (decoded is! Map) {
      throw const FormatException('refresh response is not a JSON object');
    }
    return Map<String, dynamic>.from(decoded);
  }

  /// js 的 `data.message || fallback` 的 falsy 语义：
  /// null / 空串（及 '0' 之外的字符串化空值）→ fallback。
  String _fallbackMessage(Map<String, dynamic> data, String fallback) {
    final m = data['message'];
    if (m == null) return fallback;
    final s = m is String ? m : '$m';
    return s.isEmpty ? fallback : s;
  }
}
