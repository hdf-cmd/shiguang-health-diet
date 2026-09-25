// ShiguangFlutter/lib/data/auth_api.dart
// 认证接口。契约唯一权威源：js/api.js:286-312
// （isLoggedIn=!!_loadToken、registerByUsername/loginByUsername 恒用
// PUBLISHABLE_KEY 裸发单入口请求、不走 401 续期；错误映射
// `!resp.ok || data.ok===false → message||'注册失败/登录失败'`；
// login 成功 `_saveToken({...data.token, savedAt: Date.now()})`）。

import 'api_client.dart';
import 'token_store.dart';

class AuthApi {
  AuthApi(this._client, this._store);

  final ApiClient _client;
  final TokenStore _store;

  /// 是否已登录（js/api.js:287 `!!_loadToken()`）
  Future<bool> isLoggedIn() async => await _store.read() != null;

  /// 注册（js/api.js:289-298）：成功不写 token，可直接再调 login。
  Future<void> registerByUsername(String username, String password) async {
    final resp = await _client.postPublishable('/auth/register', {
      'username': username,
      'password': password,
    });
    _ensureOk(resp, '注册失败');
  }

  /// 登录（js/api.js:300-310）：成功后把 data.token 加 savedAt 写入存储。
  Future<TokenData> loginByUsername(String username, String password) async {
    final resp = await _client.postPublishable('/auth/login', {
      'username': username,
      'password': password,
    });
    _ensureOk(resp, '登录失败');
    final token = resp.data['token'];
    // 对齐 js `{...data.token, savedAt}`：token 缺失时 spread 为空对象，
    // 仍原样透传其它字段（服务端登录成功必返 token，不做过度防御）
    final raw = token is Map
        ? Map<String, dynamic>.from(token)
        : <String, dynamic>{};
    raw['savedAt'] = DateTime.now().millisecondsSinceEpoch;
    final saved = TokenData(raw);
    await _store.write(saved);
    return saved;
  }

  /// 退出（js/api.js:312 `_clearToken()`）
  Future<void> logout() => _store.clear();

  /// js/api.js:296/307：`!resp.ok || data.ok === false` →
  /// throw new Error(data.message || 兜底文案)。resp.ok 即 2xx。
  void _ensureOk(RawResponse resp, String fallback) {
    final ok = resp.status >= 200 && resp.status < 300;
    if (!ok || resp.data['ok'] == false) {
      final m = resp.data['message'];
      final s = m is String ? m : (m == null ? '' : '$m');
      throw ApiException(s.isEmpty ? fallback : s);
    }
  }
}
