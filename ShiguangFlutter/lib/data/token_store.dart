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

/// 平台实现薄壳（真机/桌面用，不在单测覆盖内）：
/// flutter_secure_storage 持久化 JSON 字符串，键 kTokenKey。
class SecureTokenStore implements TokenStore {
  SecureTokenStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<TokenData?> read() async {
    try {
      final s = await _storage.read(key: kTokenKey);
      if (s == null) return null;
      final decoded = jsonDecode(s);
      // 对齐 js：非法 JSON / 非对象 → 视为无 token
      if (decoded is! Map) return null;
      return TokenData(Map<String, dynamic>.from(decoded));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> write(TokenData token) async {
    await _storage.write(key: kTokenKey, value: jsonEncode(token.raw));
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: kTokenKey);
  }
}
