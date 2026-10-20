// ShiguangFlutter/test/data/ai_provider_store_test.dart
// M14-T3：自带 Key 安全存储的契约。
// 参考 token_store_cache_test.dart：flutter_secure_storage 依赖平台通道，纯
// Dart 测试不可用，用 FlutterSecureStorage 内存子类替身驱动落盘内容。
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/data/ai_provider_store.dart';

/// 内存替身：只覆盖 SecureAiProviderStore 用到的 read/write/delete。
/// [failRead] 模拟平台通道异常（Keystore 解锁失败等）。
class _MemStorage extends FlutterSecureStorage {
  final Map<String, String> _values = {};
  bool failRead = false;

  void seed(String key, String value) => _values[key] = value;

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (failRead) throw PlatformException(code: 'test-read-fail');
    return _values[key];
  }

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    _values.remove(key);
  }
}

void main() {
  test('save→load 往返；clear 后为空', () async {
    final s = _MemStorage();
    final store = SecureAiProviderStore(storage: s);
    await store.save(const AiProviderConfig(
        enabled: true, id: 'deepseek', model: 'deepseek-flash', key: 'sk-12345678'));
    final c = await store.load();
    expect(c!.enabled, isTrue);
    expect(c.id, 'deepseek');
    expect(c.key, 'sk-12345678');
    await store.clear();
    expect(await store.load(), isNull);
  });

  test('坏 JSON / 缺字段 → null（按未配置处理）', () async {
    final s = _MemStorage()..seed('sg_ai_provider_v1', '{broken');
    expect(await SecureAiProviderStore(storage: s).load(), isNull);
    s.seed('sg_ai_provider_v1', '{"enabled":true}');
    expect(await SecureAiProviderStore(storage: s).load(), isNull);
  });

  test('isUsable：开关关 / 三项任一为空都不可用', () {
    expect(
        const AiProviderConfig(enabled: true, id: 'deepseek', model: 'm', key: 'k')
            .isUsable,
        isTrue);
    expect(
        const AiProviderConfig(enabled: false, id: 'deepseek', model: 'm', key: 'k')
            .isUsable,
        isFalse);
    expect(const AiProviderConfig(enabled: true, id: '', model: 'm', key: 'k')
        .isUsable, isFalse);
    expect(const AiProviderConfig(enabled: true, id: 'deepseek', model: '', key: 'k')
        .isUsable, isFalse);
    expect(const AiProviderConfig(enabled: true, id: 'deepseek', model: 'm', key: '')
        .isUsable, isFalse);
  });

  test('读盘异常 → null（按未配置处理，不打断识菜）', () async {
    final s = _MemStorage()..failRead = true;
    expect(await SecureAiProviderStore(storage: s).load(), isNull);
  });
}
