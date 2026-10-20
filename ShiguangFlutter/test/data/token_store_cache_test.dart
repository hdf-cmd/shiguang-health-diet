// ShiguangFlutter/test/data/token_store_cache_test.dart
// M11-T4 钉：SecureTokenStore 的内存镜像。
// 根因：ApiClient 每个请求都 `_store.read()`（api_client.dart:101），而生产实现
// 直打 FlutterSecureStorage（Android Keystore，数十 ms 级）；首页 4 请求＝4 次读，
// 常吃回填 30 并发＝30 次读。本组用例把「一次启动只读一次盘」钉成契约。
import 'dart:convert';

import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/data/token_store.dart';

/// 计数替身：只覆盖 SecureTokenStore 实际用到的 read/write/delete 三法，
/// 落盘内容靠 [value] 驱动，[failRead] 模拟平台通道异常。
class _CountingStorage extends FlutterSecureStorage {
  int readCalls = 0;
  int writeCalls = 0;
  int deleteCalls = 0;
  String? value;
  bool failRead = false;

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
    readCalls++;
    if (failRead) throw PlatformException(code: 'test-read-fail');
    return value;
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
    writeCalls++;
    this.value = value;
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
    deleteCalls++;
    value = null;
  }
}

TokenData _tok(String accessToken) => TokenData({
      'accessToken': accessToken,
      'refreshToken': 'refresh-1',
      'expiresIn': 7200,
      'savedAt': 1700000000000,
    });

void main() {
  test('①首读打盘一次，二读走内存镜像且返回同一实例', () async {
    final storage = _CountingStorage()
      ..value = jsonEncode(_tok('A').raw);
    final store = SecureTokenStore(storage);

    final first = await store.read();
    final second = await store.read();

    expect(first, isNotNull);
    expect(first!.accessToken, 'A');
    expect(second, same(first)); // 镜像命中：不重建对象
    expect(storage.readCalls, 1);
  });

  test('②未加载时 5 路并发读只打一次盘（single-flight）', () async {
    final storage = _CountingStorage()..value = jsonEncode(_tok('A').raw);
    final store = SecureTokenStore(storage);

    final results = await Future.wait([
      for (var i = 0; i < 5; i++) store.read(),
    ]);

    expect(storage.readCalls, 1);
    expect(results.every((r) => identical(r, results.first)), isTrue);
  });

  test('③write 后镜像即时可见，且后续读不回盘', () async {
    final storage = _CountingStorage()..value = jsonEncode(_tok('A').raw);
    final store = SecureTokenStore(storage);
    await store.read(); // 先建立镜像（旧值 A）

    await store.write(_tok('B'));

    expect(storage.writeCalls, 1);
    final after = await store.read();
    expect(after!.accessToken, 'B');
    expect(storage.readCalls, 1); // 写之后仍然一次都没多读
  });

  test('④clear 后读到 null，不得回落旧镜像（登出必须真清）', () async {
    final storage = _CountingStorage()..value = jsonEncode(_tok('A').raw);
    final store = SecureTokenStore(storage);
    await store.read();

    await store.clear();

    expect(storage.deleteCalls, 1);
    expect(await store.read(), isNull);
    expect(storage.readCalls, 1);
  });

  test('⑤平台读异常按「无 token」返回 null，且不缓存失败（下次再打盘）', () async {
    final storage = _CountingStorage()..failRead = true;
    final store = SecureTokenStore(storage);

    expect(await store.read(), isNull);
    expect(await store.read(), isNull);
    expect(storage.readCalls, 2); // 失败不钉死，保留重试（现行为语义）

    // 盘恢复后应立即读到真值，而非被缓存的 null 遮住
    storage.failRead = false;
    storage.value = jsonEncode(_tok('A').raw);
    expect((await store.read())!.accessToken, 'A');
  });

  test('⑥非法 JSON 视为无 token（js/api.js:28-30 语义不回归）', () async {
    final storage = _CountingStorage()..value = '{not json';
    final store = SecureTokenStore(storage);

    expect(await store.read(), isNull);
  });
}
