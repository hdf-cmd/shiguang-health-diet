// ShiguangFlutter/lib/app/auth_state.dart
// 登录门控状态机 + 认证依赖的组合根 provider。
// 行为对照 H5：js/app.js:1970-1976（init：!HealthAPI.isLoggedIn() → showLogin，
// 否则直接进主界面）、js/app.js:1904-1912（提交：register 模式先注册再登录，
// 成功即切主界面，异常统一进错误行）。

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../data/auth_api.dart';
import '../data/token_store.dart';
// 终审 I1：登出/换号失效全部账号数据 provider，需引用各 feature 的 provider。
// app→features 的单向依赖本就存在（root_container.dart 同层同法拼装），
// home_controller ↔ auth_state 的文件级环 Dart 合法且此前已成立。
import '../features/exercise/exercise_controller.dart' show exercisesProvider;
import '../features/home/home_controller.dart' show recordsProvider, summaryProvider;
import '../features/profile/profile_providers.dart' show profileProvider;
import '../features/profile/profile_screen.dart' show profileWeightProvider;
import '../features/record/food_freq.dart' show foodFreqProvider;
import '../features/report/report_controller.dart'
    show monthReportProvider, weekReportProvider, weightTrendProvider;

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

  /// 终审 I1：登出/换号 = H5 `location.reload()` 的等价物——组合根 container
  /// 终身存活，只置 anon 不清内存态，跨账号缓存会串：
  /// - keepAlive 源（profileWeightProvider/foodFreqProvider）不随 Shell 卸载
  ///   而 dispose，换号后 ProfileScreen 用旧账号体重播种输入位，误点保存即把
  ///   A 的体重写进 B 的 /user/weight；
  /// - autoDispose 家族源（summary/records/周月报/趋势）在用户仍停留于 Shell
  ///   页面时点登出（UI 监听未卸）同样穿过切页存活。
  /// 故登出与登录成功两处都显式失效全部；后者另覆盖「会话过期 forceAnon →
  /// 不经 signOut 直接换号登录」路径。family 不带参 invalidate 即整族失效
  /// （安装源 riverpod-3.4.3 provider_container.dart:1156-1167
  /// `case Family():` 遍历 listFamily 逐个 invalidateSelf，已读源核实）。
  /// 边界说明：foodFreqProvider 失效只清内存计数；prefs 里的持久计数下次
  /// ensureLoaded 仍会读回（init 标记未清）——按终查处方只失效 provider，
  /// 持久面不动（M4 冻结面）。healthApi/apiClient 为无状态通道，无需失效。
  void _invalidateAccountScopedCaches() {
    ref
      ..invalidate(profileProvider) // M5-T5：昵称/头像/签名同属账号级缓存
      ..invalidate(profileWeightProvider)
      ..invalidate(summaryProvider) // family：整族失效
      ..invalidate(recordsProvider) // family：整族失效
      ..invalidate(exercisesProvider) // M6-T3/M7-T2：运动记录 family（Notifier
      // +autoDispose）整族失效；在体监听（Shell 未卸）即刻重取新账号真值
      ..invalidate(weekReportProvider)
      ..invalidate(monthReportProvider)
      ..invalidate(weightTrendProvider)
      ..invalidate(foodFreqProvider);
  }

  /// 启动门控：经 AuthApi.isLoggedIn() 读一次 TokenStore
  /// （即 `store.read() != null`，与 H5 `!!_loadToken()` 同判定）。
  Future<void> bootstrap() async {
    final authed = await ref.read(authApiProvider).isLoggedIn();
    state = authed ? AuthStatus.authed : AuthStatus.anon;
  }

  /// I1：ApiClient 会话过期清 token 后调用，跳过 bootstrap 直接回登录页
  void forceAnon() => state = AuthStatus.anon;

  /// 退出登录（H5 js/app.js:1168：`HealthAPI.logout(); location.reload()`；
  /// logout = _clearToken，js/api.js:312——清本地 token 后整页重载，由启动
  /// 门控落回登录页）。Flutter 侧同语义两步：清 TokenStore + 置 anon，
  /// AuthGate 据此切回 LoginScreen，无需 reload。
  Future<void> signOut() async {
    await ref.read(tokenStoreProvider).clear();
    state = AuthStatus.anon;
    _invalidateAccountScopedCaches();
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
    // 换号兜底：forceAnon（会话过期）路径不经过 signOut，注册/登录成功后
    // 旧账号缓存同样必须全清——先失效（token 已由 loginByUsername 落库，
    // 在途监听重取即新账号数据），再置 authed 切 Shell。
    _invalidateAccountScopedCaches();
    state = AuthStatus.authed;
  }
}

final authStateProvider =
    NotifierProvider<AuthNotifier, AuthStatus>(AuthNotifier.new);
