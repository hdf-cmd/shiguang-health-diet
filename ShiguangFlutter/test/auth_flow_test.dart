// ShiguangFlutter/test/auth_flow_test.dart
// M2 Task 7：真实登录闭环（启动门控 + 登录/注册接 AuthApi）。
// 全部走桩 AuthApi，不打云端；真实组合根在 main()（本文件不触碰 SecureTokenStore）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/auth_state.dart';
import 'package:shiguang_flutter/data/api_client.dart';
import 'package:shiguang_flutter/data/auth_api.dart';
import 'package:shiguang_flutter/data/token_store.dart';
import 'package:shiguang_flutter/features/home/home_controller.dart' show healthApiProvider;
import 'package:shiguang_flutter/main.dart';

import 'stubs/stub_health_api.dart';

/// 桩 AuthApi：四场景全靠构造参数控制，零网络。
/// implements 而非 extends——AuthApi 的具体构造需要 ApiClient，桩不需要。
class StubAuthApi implements AuthApi {
  StubAuthApi({this.loggedIn = false, this.loginError, this.registerError});

  bool loggedIn;
  final ApiException? loginError;
  final ApiException? registerError;
  String? lastLoginUsername;
  String? lastRegisterUsername;

  @override
  Future<bool> isLoggedIn() async => loggedIn;

  @override
  Future<void> registerByUsername(String username, String password) async {
    if (registerError != null) throw registerError!;
    lastRegisterUsername = username;
  }

  @override
  Future<TokenData> loginByUsername(String username, String password) async {
    if (loginError != null) throw loginError!;
    lastLoginUsername = username;
    loggedIn = true; // 真实实现写 token 后 isLoggedIn 恒 true，桩同构
    return TokenData({'accessToken': 'stub-access', 'savedAt': 0});
  }

  @override
  Future<void> logout() async {
    loggedIn = false;
  }
}

Widget harness(StubAuthApi api) => ProviderScope(
      overrides: [
        authApiProvider.overrideWithValue(api),
        // T8 起 Shell 首 tab 是真实数据 HomeScreen：healthApi 一并桩掉，
        // 认证用例绝不触碰 SecureTokenStore/网络路径（空数据 = 三餐"未记录"）
        healthApiProvider.overrideWithValue(StubHealthApi()),
      ],
      child: const ShiguangApp(),
    );

const kUserHint = '用户名（中文/字母/数字/下划线）';

Future<void> fillCredentials(WidgetTester tester,
    {String username = 'xiaoshi', String password = 'Test1234!@'}) async {
  await tester.enterText(find.byType(TextField).first, username);
  await tester.enterText(find.byType(TextField).last, password);
}

void main() {
  testWidgets('启动门控：TokenStore 有 token → 直接进 Shell（见"今日盘子"）',
      (tester) async {
    final api = StubAuthApi(loggedIn: true);
    await tester.pumpWidget(harness(api));
    await tester.pumpAndSettle();
    expect(find.text('今日盘子'), findsOneWidget);
    expect(find.text(kUserHint), findsNothing);
  });

  testWidgets('启动门控：无 token → LoginScreen（不见"今日盘子"）', (tester) async {
    final api = StubAuthApi(loggedIn: false);
    await tester.pumpWidget(harness(api));
    await tester.pumpAndSettle();
    expect(find.text(kUserHint), findsOneWidget);
    expect(find.text('今日盘子'), findsNothing);
  });

  testWidgets('登录成功 → 切到 Shell', (tester) async {
    final api = StubAuthApi();
    await tester.pumpWidget(harness(api));
    await tester.pumpAndSettle();
    await fillCredentials(tester);
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    expect(api.lastLoginUsername, 'xiaoshi');
    expect(find.text('今日盘子'), findsOneWidget);
  });

  testWidgets('登录失败（ApiException）→ 错误行显示真实文案，按钮恢复',
      (tester) async {
    final api = StubAuthApi(loginError: ApiException('用户名或密码错误'));
    await tester.pumpWidget(harness(api));
    await tester.pumpAndSettle();
    await fillCredentials(tester);
    await tester.tap(find.widgetWithText(FilledButton, '登录'));
    await tester.pumpAndSettle();
    expect(find.text('用户名或密码错误'), findsOneWidget);
    expect(find.text('今日盘子'), findsNothing);
    // H5 对齐：失败后按钮恢复可点（文案回到"登录"）
    expect(find.widgetWithText(FilledButton, '登录'), findsOneWidget);
  });

  testWidgets('注册模式复用：注册+登录串联成功后进 Shell（H5 register→login 行为）',
      (tester) async {
    final api = StubAuthApi();
    await tester.pumpWidget(harness(api));
    await tester.pumpAndSettle();
    await tester.tap(find.text('注册')); // 模式切换标签
    await tester.pump();
    await fillCredentials(tester, username: 'xiaoqu');
    await tester.tap(find.widgetWithText(FilledButton, '注册并进入'));
    await tester.pumpAndSettle();
    expect(api.lastRegisterUsername, 'xiaoqu');
    expect(api.lastLoginUsername, 'xiaoqu');
    expect(find.text('今日盘子'), findsOneWidget);
  });
}
