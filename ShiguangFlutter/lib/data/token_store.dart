// ShiguangFlutter/lib/data/token_store.dart
// 登录态存储。契约唯一权威源：js/api.js:25-32（TOKEN_KEY='sg_token'、
// _loadToken 解析失败返回 null、_saveToken 存 JSON、_clearToken 删除）。
//
// 分层说明：flutter_secure_storage 依赖平台通道，纯 Dart 单测（flutter test
// 跑在 Dart VM）里不可用。故此处定义为「接口 TokenStore + 内存实现
// InMemoryTokenStore（测试注入用）+ 平台薄壳 SecureTokenStore（真机用，
// 不参与单测）」。TokenData 保留原始 map（对齐 js 的 {...data.token, savedAt}
// 任意字段透传），常用字段以 getter 暴露。

import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// 存储键，逐字对齐 js/api.js:25 的 TOKEN_KEY。
const String kTokenKey = 'sg_token';

/// 登录态数据：raw 即写入存储的 JSON 对象（含 accessToken/refreshToken/
/// expiresIn/savedAt 及服务端 token 的其它字段）。
class TokenData {
  TokenData(this.raw);

  final Map<String, dynamic> raw;

  String? get accessToken => raw['accessToken'] as String?;
  String? get refreshToken => raw['refreshToken'] as String?;

  /// 有效期秒数；缺失按 js/api.js:54 的兜底 7200。
  int get expiresIn {
    final v = raw['expiresIn'];
    return v is num ? v.toInt() : 7200;
  }

  /// 保存时刻（毫秒时间戳），对齐 js 的 Date.now()。
  int get savedAt {
    final v = raw['savedAt'];
    return v is num ? v.toInt() : 0;
  }

  /// 对齐 js `{...t, accessToken:…, refreshToken:…, expiresIn:…, savedAt:…}` 的合并写回。
  TokenData copyWith({
    String? accessToken,
    String? refreshToken,
    int? expiresIn,
    int? savedAt,
  }) {
    return TokenData({
      ...raw,
      'accessToken': ?accessToken,
      'refreshToken': ?refreshToken,
      'expiresIn': ?expiresIn,
      'savedAt': ?savedAt,
    });
  }
}

/// 存储接口：三个方法一一对应 js 的 _loadToken/_saveToken/_clearToken。
abstract class TokenStore {
  /// 读不到或解析失败 → null（对齐 js/api.js:28-30 的 try/catch）。
  Future<TokenData?> read();
  Future<void> write(TokenData token);
  Future<void> clear();
}

/// 内存实现：单测注入（flutter_secure_storage 在纯 Dart 测试无平台通道）。
class InMemoryTokenStore implements TokenStore {
  TokenData? _data;

  @override
  Future<TokenData?> read() async => _data;

  @override
  Future<void> write(TokenData token) async {
    // 与 js 的 JSON 往返同构：深拷贝一层，避免调用方后续改 raw 影响存储
    _data = TokenData(Map<String, dynamic>.from(token.raw));
  }

  @override
  Future<void> clear() async {
    _data = null;
  }
}

/// 平台实现薄壳（真机/桌面用）：flutter_secure_storage 持久化 JSON 字符串，
/// 键 kTokenKey；**M11-T4 起带内存镜像**，一次启动只打一次盘。
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  /// 内存镜像。为什么要它：Android Keystore 读是数十 ms 级平台通道，而
  /// ApiClient 每个请求都 read 一次（api_client.dart:101），常吃回填更是
  /// 一次性 30 路并发（food_freq.dart:181）——同一份 token 被读 30 遍。
  /// App 单 isolate，且本键只有本类会写，故镜像不会与盘不一致；写/清一律
  /// **等盘成功后再改镜像**（抛异常时镜像保持旧值，不制造假登录态）。
  TokenData? _mirror;
  bool _loaded = false;

  /// 并发首读去重：30 路同时进来只打一次盘。
  Future<TokenData?>? _inflight;

  @override
  Future<TokenData?> read() {
    if (_loaded) return Future.value(_mirror);
    return (_inflight ??= _readOnce())
        .whenComplete(() => _inflight = null);
  }

  Future<TokenData?> _readOnce() async {
    try {
      final s = await _storage.read(key: kTokenKey);
      if (s == null) {
        _mirror = null;
        _loaded = true;
        return null;
      }
      final decoded = jsonDecode(s);
      // 对齐 js：非法 JSON / 非对象 → 视为无 token
      if (decoded is! Map) {
        _mirror = null;
        _loaded = true;
        return null;
      }
      final data = TokenData(Map<String, dynamic>.from(decoded));
      _mirror = data;
      _loaded = true;
      return data;
    } catch (_) {
      // 平台异常不置 _loaded：下次读再打盘（失败不钉死整会话）
      return null;
    }
  }

  @override
  Future<void> write(TokenData token) async {
    await _storage.write(key: kTokenKey, value: jsonEncode(token.raw));
    _mirror = token;
    _loaded = true;
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: kTokenKey);
    _mirror = null;
    _loaded = true;
  }
}
