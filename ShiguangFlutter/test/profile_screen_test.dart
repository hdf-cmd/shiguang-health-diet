// ShiguangFlutter/test/profile_screen_test.dart
// M4 Task 4：「我的」页（体重卡+退出登录）。M8-①（09-27 真机反馈）：
// 体重卡整卡迁往报告页——①-⑤b 用例组原样迁移至 weight_log_card_test.dart
// （断言零弱化），本文件收缩为「我的」页残面：退出登录（js/app.js:1168：
// HealthAPI.logout = _clearToken，js/api.js:312 + 回登录；Flutter 侧
// signOut 清 token + 置 anon，AuthGate 切 LoginScreen）。
// 测试地基：harness.useBigSurface。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/auth_state.dart';
import 'package:shiguang_flutter/data/token_store.dart';
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider;
import 'package:shiguang_flutter/features/notifications/reminder_scheduler.dart'
    show reminderSchedulerProvider;
import 'package:shiguang_flutter/features/profile/profile_screen.dart'
    show ProfileScreen;

import 'harness.dart';
import 'stubs/stub_health_api.dart';

Future<ProviderContainer> pumpProfile(
  WidgetTester tester,
  StubHealthApi api, {
  TokenStore? store,
}) async {
  await useBigSurface(tester);
  final container = ProviderContainer(
    overrides: [
      healthApiProvider.overrideWithValue(api),
      tokenStoreProvider.overrideWithValue(store ?? InMemoryTokenStore()),
      // T8 缓办 B：initState 的 enabled() 走 no-op，不再真触 SharedPreferences
      // 抛 MissingPluginException 后被 catchError 静默吞（走确定路径）。
      reminderSchedulerProvider.overrideWithValue(NoopReminderScheduler()),
    ],
    // 对齐 buildRootContainer：H5 语义失败不自动重试（root_container.dart:84）
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: ProfileScreen()),
  ));
  await tester.pumpAndSettle();
  return container;
}

void main() {
  /* ---------- ⑥ 退出登录 ---------- */

  testWidgets('⑥退出登录：清 token（H5 _clearToken）+ 门控置 anon 回登录页',
      (tester) async {
    final store = InMemoryTokenStore();
    await store.write(TokenData({'accessToken': 't', 'refreshToken': 'r'}));
    final container =
        await pumpProfile(tester, StubHealthApi(), store: store);

    expect(find.text('退出登录'), findsOneWidget); // index.html:456 逐字

    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();

    expect(await store.read(), isNull); // 等价 H5 logout=HealthAPI.logout
    expect(container.read(authStateProvider),
        AuthStatus.anon); // AuthGate 据此切回 LoginScreen
  });
}
