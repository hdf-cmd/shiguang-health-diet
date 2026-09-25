// ShiguangFlutter/test/root_container_test.dart
// M4-T1：组合根工厂的地基用例。两件事必须钉住：
//  ① retry 策略 = 不自动重试（M3 终审 Important-3，对齐 H5「失败一次 +
//     手动重试」：js/api.js:239-265 失败即抛，界面「重试」按钮再发一次）。
//     Riverpod 3 容器级默认是 200ms 起指数退避最多 10 次（element.dart:772），
//     不显式关掉的话"请求次数确定"这件事永远立不住，错误态用例只能靠
//     定步 pump 绕时钟。本用例让 provider 存活并**真的推进时钟**，
//     若哪天有人删掉 retry: (_, _) => null，这里必然红。
//  ② 真实链路（全默认参数）拼装不炸：SecureTokenStore / PrefsFoodFreqStore /
//     defaultDio 都只是构造对象，构造期不碰平台通道、不发请求，
//     故"能 read 出正确类型"可单测；实际网络与存储读写留真机冒烟。
//  ③ 注入 onSessionExpired 时**替换**默认 forceAnon 接线（参数语义契约，
//     auth_expiry_test 的计数钩子依赖它）。
// 零网络：dio 恒 500 / 恒 401 桩走 test/harness.dart 的 RecordingAdapter。
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/auth_state.dart';
import 'package:shiguang_flutter/app/root_container.dart';
import 'package:shiguang_flutter/data/api_client.dart';
import 'package:shiguang_flutter/data/auth_api.dart';
import 'package:shiguang_flutter/data/health_api.dart';
import 'package:shiguang_flutter/data/token_store.dart';
import 'package:shiguang_flutter/domain/dates.dart';
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider, summaryProvider;
import 'package:shiguang_flutter/features/record/food_freq.dart';

import 'harness.dart';

Future<TokenStore> _signedInStore() async {
  final store = InMemoryTokenStore();
  await store.write(TokenData({
    'accessToken': 'at-root',
    'refreshToken': 'rt-root',
    'expiresIn': 7200,
    'savedAt': 1,
  }));
  return store;
}

void main() {
  test('服务端 500 → summaryProvider 抛 ApiException，且**不自动重试**（恒 1 次请求）',
      () async {
    final adapter = RecordingAdapter(
        status: 500, responseText: '{"message":"服务开小差了，稍后再试"}');
    final container = buildRootContainer(
      tokenStore: await _signedInStore(),
      dio: Dio()..httpClientAdapter = adapter,
    );
    addTearDown(container.dispose);

    final provider = summaryProvider(todayIso());
    // listen 而非只 read：autoDispose 元素若没人监听会被回收，
    // "是否还会再发请求"就无从谈起。有监听 = provider 存活，退避重试才会跑。
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);

    await expectLater(
        container.read(provider.future),
        throwsA(isA<ApiException>().having(
            (e) => e.message, 'message', '服务开小差了，稍后再试')));
    expect(adapter.requestCount, 1, reason: '首次请求恰好一次');

    // 真的推进时钟越过默认退避窗口（200ms → 400ms → …）：
    // 删掉工厂里的 retry: (_, _) => null 后，这里会看到 3 次以上请求。
    await Future<void>.delayed(const Duration(milliseconds: 900));
    expect(adapter.requestCount, 1, reason: '失败后不得自动重试（H5 手动重试语义）');
    expect(container.read(provider).hasError, isTrue);
  });

  test('全默认参数（真实链路）拼装可解析：不读存储、不发请求', () {
    final container = buildRootContainer();
    addTearDown(container.dispose);

    expect(container.read(tokenStoreProvider), isA<SecureTokenStore>());
    expect(container.read(apiClientProvider), isA<ApiClient>());
    expect(container.read(authApiProvider), isA<AuthApi>());
    expect(container.read(healthApiProvider), isA<HealthApi>());
    expect(container.read(foodFreqStoreProvider), isA<PrefsFoodFreqStore>());
    // 组合根工厂的 retry 策略本身可断言（不依赖内部实现细节即可锁语义）
    expect(container.retry, isNotNull);
    expect(container.retry!(0, ApiException('boom')), isNull);
  });

  test('注入 onSessionExpired → 替换默认 forceAnon 接线（门控不被推动）',
      () async {
    var expiredCalls = 0;
    final adapter = RecordingAdapter(status: 401, responseText: '{}');
    final container = buildRootContainer(
      tokenStore: await _signedInStore(),
      dio: Dio()..httpClientAdapter = adapter,
      onSessionExpired: () => expiredCalls++,
    );
    addTearDown(container.dispose);

    await expectLater(container.read(summaryProvider(todayIso()).future),
        throwsA(isA<ApiException>()));
    expect(expiredCalls, 1);
    // 默认接线（forceAnon）未被执行：门控仍停在 unknown，而非 anon
    expect(container.read(authStateProvider), AuthStatus.unknown);
  });
}
