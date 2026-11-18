// ShiguangFlutter/lib/features/band_sync/mi_credentials_store.dart
// 小米账号凭据存储：userId + passToken 只进系统加密存储（flutter_secure_storage），
// 不进 SharedPreferences / 日志 / 仓库。
// passToken 每次云端登录都会被轮换，save() 必须在每次登录后调用。
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../data/mi_cloud_client.dart' show MiSession;

class MiCredentials {
  const MiCredentials({required this.userId, required this.passToken});
  final String userId;
  final String passToken;
}

abstract class MiCredentialStore {
  Future<MiCredentials?> load();
  Future<void> save(MiCredentials credentials);
  Future<void> clear();
}

class SecureMiCredentialStore implements MiCredentialStore {
  SecureMiCredentialStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _userKey = 'sg_mi_user_id';
  static const _passKey = 'sg_mi_pass_token';

  final FlutterSecureStorage _storage;

  @override
  Future<MiCredentials?> load() async {
    final user = await _storage.read(key: _userKey);
    final pass = await _storage.read(key: _passKey);
    if (user == null || user.isEmpty || pass == null || pass.isEmpty) {
      return null;
    }
    return MiCredentials(userId: user, passToken: pass);
  }

  @override
  Future<void> save(MiCredentials credentials) async {
    await _storage.write(key: _userKey, value: credentials.userId);
    await _storage.write(key: _passKey, value: credentials.passToken);
  }

  @override
  Future<void> clear() async {
    await _storage.delete(key: _userKey);
    await _storage.delete(key: _passKey);
  }
}

final miCredentialStoreProvider = Provider<MiCredentialStore>(
  (ref) => SecureMiCredentialStore(),
);


/// 登录会话缓存（ssecurity/cookies）：避免每次同步都重新登录轮换 passToken。
/// 401/403 时由同步服务丢弃并重登；不设 TTL。
class MiSessionStore {
  MiSessionStore([FlutterSecureStorage? storage])
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'sg_mi_session';

  final FlutterSecureStorage _storage;

  Future<MiSession?> load() async {
    final raw = await _storage.read(key: _key);
    if (raw == null || raw.isEmpty) return null;
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      return MiSession(
        userId: '${m['u']}',
        passToken: '${m['p']}',
        ssecurity: base64.decode('${m['s']}'),
        cookies: '${m['c']}',
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(MiSession session) async {
    await _storage.write(
        key: _key,
        value: jsonEncode({
          'u': session.userId,
          'p': session.passToken,
          's': base64.encode(session.ssecurity),
          'c': session.cookies,
        }));
  }

  Future<void> clear() async => _storage.delete(key: _key);
}

final miSessionStoreProvider =
    Provider<MiSessionStore>((ref) => MiSessionStore());
