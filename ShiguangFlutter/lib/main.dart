// ShiguangFlutter/lib/main.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'app/auth_state.dart';
import 'app/root_container.dart';
import 'app/shell.dart';
import 'app/theme.dart';
import 'data/swr_cache.dart' show swrCacheProvider;
import 'features/auth/login_screen.dart';
import 'features/band_sync/mi_auto_sync.dart' show startMiAutoSync;

Future<void> main() async {
  // M5-T8 结转 C：绑定必须先于任何插件面。flutter_local_notifications 22.3.1
  // 的 FlutterLocalNotificationsPlugin() **构造期**即 setMethodCallHandler
  // （platform_channel.dart:589 断言 _binaryMessenger!=null||binding!=null），
  // 而 bootstrapReminders 的 port 构造跑在 runApp 之前 → debug 冷启动必现
  // 'bootstrapReminders failed: Failed assertion'（logcat 实测复现）。
  // ensureInitialized 是官方前置；release 无 debugBindingType 断言故静默，
  // 但时序错误真实存在，一处修复。
  WidgetsFlutterBinding.ensureInitialized();
  // 组合根：真实依赖的拼装收在 app/root_container.dart 的工厂里（M4-T1）。
  // 不传参 = 生产链路（SecureTokenStore → ApiClient → AuthApi/HealthApi +
  // PrefsFoodFreqStore + 过期回调接 forceAnon）；测试注入桩后调同一个工厂，
  // 于是端到端用例验的就是生产装配本身（M3「手抄同构」地债已清）。
  final container = buildRootContainer();
  // M4-T6 提醒启动自愈（对齐 H5 MainActivity:105 ensureWaterSchedule）：
  // init→sync(on: enabled())，fire-and-forget——内部已 try/catch，不挡启动。
  // 测试环境不走 main()，插件面天然零波及（调度动作单测用 FakePort）。
  bootstrapReminders(container);
  // M17：手环云同步自动接线（已绑定时冷启动/回前台静默同步，失败不打扰）。
  startMiAutoSync(container);
  // M11-T3：冷启动磁盘播种——必须在这里、runApp 之前 await。
  // 放 AuthGate.bootstrap 里有两个实测后果：① widget 测试的 pumpAndSettle 不驱动
  // 真实平台通道 IO，登录态用例整批停在 splash（auth_expiry 实测）；② 首帧已经
  // 画过一次骨架再改数，等于没省到。放这儿：一次 prefs 读（毫秒级）换首帧直显。
  await container.read(swrCacheProvider).hydrate();
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
