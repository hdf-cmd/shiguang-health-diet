// ShiguangFlutter/lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/auth_state.dart';
import 'app/shell.dart';
import 'app/theme.dart';
import 'data/api_client.dart';
import 'data/auth_api.dart';
import 'data/token_store.dart';
import 'features/auth/login_screen.dart';

void main() {
  // 组合根：真实依赖只在这里拼装一次（SecureTokenStore → ApiClient → AuthApi），
  // 经 ProviderScope.overrides 注入；不造全局单例，测试在各自 ProviderScope
  // 里 override 成桩（见 test/auth_flow_test.dart）。
  final tokenStore = SecureTokenStore();
  final apiClient = ApiClient(tokenStore: tokenStore);
  final authApi = AuthApi(apiClient, tokenStore);
  runApp(ProviderScope(
    overrides: [
      tokenStoreProvider.overrideWithValue(tokenStore),
      apiClientProvider.overrideWithValue(apiClient),
      authApiProvider.overrideWithValue(authApi),
    ],
    child: const ShiguangApp(),
  ));
}

class ShiguangApp extends StatelessWidget {
  const ShiguangApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: '食光',
        theme: shiguangTheme(),
        home: const AuthGate(),
      );
}

/// 启动门控。行为对照 H5 js/app.js:1970-1976 的 init：
/// 有 token 直接主界面，无 token 锁登录页；登录成功回调后置 authed 切 Shell
/// （对照 js/app.js:1910-1912 提交成功后隐藏登录页进主界面）。
/// unknown（splash）是 Flutter 侧新增：secure storage 异步读，
/// web 的同步判定在移动端不存在，不加会闪错页。
class AuthGate extends ConsumerStatefulWidget {
  const AuthGate({super.key});
  @override
  ConsumerState<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends ConsumerState<AuthGate> {
  @override
  void initState() {
    super.initState();
    // bootstrap 会改 state，不能在 build 期读 provider → 放 postFrame。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(authStateProvider.notifier).bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(authStateProvider);
    return switch (status) {
      AuthStatus.unknown => const _Splash(),
      AuthStatus.authed => const Shell(),
      AuthStatus.anon => LoginScreen(
          onSubmit: (username, password, isRegister) => ref
              .read(authStateProvider.notifier)
              .submit(
                  username: username,
                  password: password,
                  isRegister: isRegister),
        ),
    };
  }
}

/// 门控等待页：纯静态（不放无限动画，保证 widget 测试可 settle）。
class _Splash extends StatelessWidget {
  const _Splash();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: const [
            Text('食光',
                style: TextStyle(
                    fontSize: 40,
                    fontWeight: FontWeight.w800,
                    color: Tokens.primaryDeep)),
            SizedBox(height: Tokens.sp2),
            Text('把每一餐，记成时光',
                style: TextStyle(fontSize: Tokens.textSm, color: Tokens.ink2)),
          ]),
        ),
      );
}
