// ShiguangFlutter/lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/auth_state.dart';
import 'app/shell.dart';
import 'app/theme.dart';
import 'data/api_client.dart';
import 'data/auth_api.dart';
import 'data/health_api.dart';
import 'data/token_store.dart';
import 'features/auth/login_screen.dart';
import 'features/home/home_controller.dart' show healthApiProvider;

void main() {
  // 组合根：真实依赖只在这里拼装一次（SecureTokenStore → ApiClient → AuthApi/HealthApi），
  // 经 ProviderContainer.overrides 注入；不造全局单例，测试在各自 scope
  // 里 override 成桩（见 test/auth_flow_test.dart）。
  // I1 断环：回调引用 container，container 的 overrides 又引用 apiClient，
  // 用 late final 先声明 container、构造 ApiClient 时只捕获其闭包、随后回填。
  late final ProviderContainer container;
  final tokenStore = SecureTokenStore();
  final apiClient = ApiClient(
    tokenStore: tokenStore,
    // 401 续期失败清 token → 门控直接置 anon 回登录页（forceAnon 幂等，
    // 并发过期请求各触发一次无碍）
    onSessionExpired: () =>
        container.read(authStateProvider.notifier).forceAnon(),
  );
  final authApi = AuthApi(apiClient, tokenStore);
  // 同构锚（终审 Minor-5）：这段 container 拼装与 test/auth_expiry_test.dart
  // 的 `_expiryContainer` 是**手抄同构**（同一 late-final 断环 + 四个 override）。
  // 改此处（增删 override、换回调签名）必同步改那里，否则会话过期用例验证的
  // 就不是生产组合根。M4 计划把 buildRootContainer 工厂化根治，本注释是过渡保险。
  container = ProviderContainer(
    overrides: [
      tokenStoreProvider.overrideWithValue(tokenStore),
      apiClientProvider.overrideWithValue(apiClient),
      authApiProvider.overrideWithValue(authApi),
      healthApiProvider.overrideWithValue(HealthApi(apiClient)),
    ],
  );
  runApp(UncontrolledProviderScope(
    container: container,
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
                    fontSize: Tokens.textHero,
                    fontWeight: FontWeight.w800,
                    color: Tokens.primaryDeep)),
            SizedBox(height: Tokens.sp2),
            Text('把每一餐，记成时光',
                style: TextStyle(fontSize: Tokens.textSm, color: Tokens.ink2)),
          ]),
        ),
      );
}
