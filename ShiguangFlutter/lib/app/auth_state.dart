// ShiguangFlutter/lib/app/auth_state.dart
// 登录门控状态机 + 认证依赖的组合根 provider。
// 行为对照 H5：js/app.js:1970-1976（init：!HealthAPI.isLoggedIn() → showLogin，
// 否则直接进主界面）、js/app.js:1904-1912（提交：register 模式先注册再登录，
// 成功即切主界面，异常统一进错误行）。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../data/auth_api.dart';
import '../data/token_store.dart';

/// 门控三态：
/// - unknown：TokenStore 读取尚未完成。H5 没有此态（web 同步读 localStorage，
///   init 一行判完）；Flutter 侧 flutter_secure_storage 是异步平台通道，
///   必须多一个中间态，避免把"还没读到"误判成"没登录"闪错页。
/// - authed：有 token / 登录成功（H5：隐藏登录页 + 恢复 tabbar）。
/// - anon：无 token（H5 showLogin()：整体锁定登录页）。
enum AuthStatus { unknown, authed, anon }

// —— 组合根三件套：默认值即真实链路（SecureTokenStore → ApiClient → AuthApi），
// main() 仍显式构造并经 ProviderScope.overrides 注入（依赖关系一目了然）；
// 测试只 override authApiProvider 即可全链路换桩。全部 per-container 惰性构造，
// 无全局单例。

final tokenStoreProvider =
    Provider<TokenStore>((ref) => SecureTokenStore());

final apiClientProvider = Provider<ApiClient>(
    (ref) => ApiClient(tokenStore: ref.watch(tokenStoreProvider)));

final authApiProvider = Provider<AuthApi>((ref) =>
    AuthApi(ref.watch(apiClientProvider), ref.watch(tokenStoreProvider)));

class AuthNotifier extends Notifier<AuthStatus> {
  @override
  AuthStatus build() => AuthStatus.unknown;

  /// 启动门控：经 AuthApi.isLoggedIn() 读一次 TokenStore
  /// （即 `store.read() != null`，与 H5 `!!_loadToken()` 同判定）。
  Future<void> bootstrap() async {
    final authed = await ref.read(authApiProvider).isLoggedIn();
    state = authed ? AuthStatus.authed : AuthStatus.anon;
  }

  /// 登录/注册提交（H5 js/app.js:1905-1907 对齐：注册模式 register 成功后
  /// 立即 login；两步任一异常都原样上抛，由 LoginScreen 落错误行）。
  /// 成功后写状态由调用方无需关心——这里置 authed 使门控切 Shell。
  Future<void> submit({
    required String username,
    required String password,
    required bool isRegister,
  }) async {
    final auth = ref.read(authApiProvider);
    if (isRegister) await auth.registerByUsername(username, password);
    await auth.loginByUsername(username, password);
    state = AuthStatus.authed;
  }
}

final authStateProvider =
    NotifierProvider<AuthNotifier, AuthStatus>(AuthNotifier.new);
