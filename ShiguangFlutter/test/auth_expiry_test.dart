// ShiguangFlutter/test/auth_expiry_test.dart
// M3 Task 1 / I1：会话过期自动回登录（终审 Important 核销）。
// 端到端回路：Shell 内真实 ApiClient 收到 401 → 续期失败清 token →
// onSessionExpired 回调 → authStateProvider.forceAnon() → 门控切回 LoginScreen。
// 零网络：dio 注入「业务恒 401、续期端点恒 400」桩（可门控挂起），
// TokenStore 用内存实现。断环接线与 main.dart 组合根完全同构。
import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/auth_state.dart';
import 'package:shiguang_flutter/app/shell.dart';
import 'package:shiguang_flutter/data/api_client.dart';
import 'package:shiguang_flutter/data/auth_api.dart';
import 'package:shiguang_flutter/data/health_api.dart';
import 'package:shiguang_flutter/features/record/food_freq.dart';
import 'package:shiguang_flutter/data/token_store.dart';
import 'package:shiguang_flutter/features/auth/login_screen.dart';
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider;
import 'package:shiguang_flutter/main.dart';

/// 恒过期适配器：业务入口 401、续期端点 400（invalid_grant）→
/// ApiClient 走「清 token + 抛登录已过期 + onSessionExpired」终判处。
/// gate 非空 → 业务响应先 await 它（用于让 Shell 停留可观测）。
class _AlwaysExpiredAdapter implements HttpClientAdapter {
  int apiCalls = 0;
  int refreshCalls = 0;
  Completer<void>? gate;

  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    if (options.uri.toString() == '${ApiClient.gwBase}/auth/v1/token') {
      refreshCalls++;
      return ResponseBody.fromString(jsonEncode({'error': 'invalid_grant'}),
          400,
          headers: {'content-type': ['application/json; charset=utf-8']});
    }
    apiCalls++;
    final g = gate;
    if (g != null) await g.future;
    return ResponseBody.fromString('{}', 401,
        headers: {'content-type': ['application/json; charset=utf-8']});
  }

  @override
  void close({bool force = false}) {}
}

/// 与 main.dart 组合根同构的 late final 断环接线：
/// 过期回调 → container.read(authStateProvider.notifier).forceAnon()。
/// 计数钩子用于断言回调确被触发（forceAnon 幂等，并发请求各触发一次）。
(ProviderContainer, int Function()) _expiryContainer(
    InMemoryTokenStore store, _AlwaysExpiredAdapter adapter) {
  var expiredCalls = 0;
  late final ProviderContainer container;
  final apiClient = ApiClient(
    tokenStore: store,
    dio: Dio()..httpClientAdapter = adapter,
    onSessionExpired: () {
      container.read(authStateProvider.notifier).forceAnon();
      expiredCalls++;
    },
  );
  container = ProviderContainer(overrides: [
    tokenStoreProvider.overrideWithValue(store),
    apiClientProvider.overrideWithValue(apiClient),
    authApiProvider.overrideWithValue(AuthApi(apiClient, store)),
    healthApiProvider.overrideWithValue(HealthApi(apiClient)),
    // 同构锚：与 main.dart 的 foodFreqStoreProvider override 保持一致
    // （本用例不触记录弹层，内存空桩即可）
    foodFreqStoreProvider.overrideWithValue(_NoopFoodFreqStore()),
  ]);
  return (container, () => expiredCalls);
}

class _NoopFoodFreqStore implements FoodFreqStore {
  @override
  Future<Map<String, int>> loadCounts() async => {};
  @override
  Future<void> saveCounts(Map<String, int> counts) async {}
  @override
  Future<bool> isInitialized() async => true;
  @override
  Future<void> markInitialized() async {}
}

/// "已登录"本地态：access/refresh token 俱在，但云端视角已失效。
Future<InMemoryTokenStore> signedInExpiredStore() async {
  final store = InMemoryTokenStore();
  await store.write(TokenData({
    'accessToken': 'expired-at',
    'refreshToken': 'expired-rt',
    'expiresIn': 7200,
    'savedAt': 1000,
  }));
  return store;
}

void main() {
  testWidgets(
      'Shell 内请求遇会话过期 → onSessionExpired → forceAnon → 自动弹回登录页',
      (tester) async {
    final store = await signedInExpiredStore();
    final adapter = _AlwaysExpiredAdapter()..gate = Completer<void>();
    final (container, expiredCalls) = _expiryContainer(store, adapter);
    addTearDown(container.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const ShiguangApp(),
    ));
    await tester.pumpAndSettle();

    // 阶段 1：bootstrap 读到 token → authed → 进 Shell；
    // 首页 summary/records 请求已被 gate 挂起，用户停留在 Shell。
    expect(find.byType(Shell), findsOneWidget);
    expect(find.text('今日盘子'), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(container.read(authStateProvider), AuthStatus.authed);

    // 阶段 2：放行 → 业务 401 → 续期端点 400 → 清 token + 过期回调
    adapter.gate!.complete();
    await tester.pumpAndSettle();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(Shell), findsNothing);
    expect(container.read(authStateProvider), AuthStatus.anon);
    expect(await store.read(), isNull); // token 确已被清
    expect(expiredCalls(), greaterThanOrEqualTo(1)); // 回调回路打通
    expect(adapter.refreshCalls, 1); // 单飞：两请求共享同一次续期

    // 登录页唯一文案锚点（H5 对齐 hint；不用歧义的「登录」二字，M1 评审立规）
    expect(find.text('用户名（中文/字母/数字/下划线）'), findsOneWidget);
    expect(find.text('把每一餐，记成时光'), findsOneWidget);
  });

  testWidgets('未过期路径（请求 200）不回调，用户留在 Shell', (tester) async {
    final store = await signedInExpiredStore();
    // 与 main.dart 同构的 late final 断环，但 dio 桩恒 200：
    // 验证"误弹回登录 / 误清 token"不会发生（回调只在终判处触发）。
    late final ProviderContainer okContainer;
    final api = ApiClient(
      tokenStore: store,
      dio: Dio()..httpClientAdapter = _Stub200Adapter(),
      onSessionExpired: () =>
          okContainer.read(authStateProvider.notifier).forceAnon(),
    );
    okContainer = ProviderContainer(overrides: [
      tokenStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(api),
      authApiProvider.overrideWithValue(AuthApi(api, store)),
      healthApiProvider.overrideWithValue(HealthApi(api)),
    ]);
    addTearDown(okContainer.dispose);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: okContainer,
      child: const ShiguangApp(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(Shell), findsOneWidget);
    expect(find.byType(LoginScreen), findsNothing);
    expect(okContainer.read(authStateProvider), AuthStatus.authed);
    expect(await store.read(), isNotNull); // token 未被误清
  });
}

/// 正常路径替身：一切请求恒 200 + ok:true，会话永不过期。
class _Stub200Adapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(RequestOptions options,
      Stream<List<int>>? requestStream, Future<void>? cancelFuture) async {
    return ResponseBody.fromString(jsonEncode({'ok': true}), 200,
        headers: {'content-type': ['application/json; charset=utf-8']});
  }

  @override
  void close({bool force = false}) {}
}
