// ShiguangFlutter/lib/app/root_container.dart
// 组合根工厂（M4-T1，M3 终审 Important-3 + 同构锚遗留收口）。
//
// 为什么存在：M1-M3 期间「真实依赖怎么拼」这件事只写在 main() 里，
// 会话过期端到端用例（test/auth_expiry_test.dart）为了验证同一条回路，
// 只能手抄一份同构 container（代码里留了「改一处必改另一处」的告警注释）。
// 手抄同构是地债：生产组合根改了（加 override / 换回调），测试验的就不再
// 是生产装配。本文件把拼装收敛成唯一入口，main() 与测试调同一个函数，
// 差异只在参数：
//   - 不传参 = 真实链路（SecureTokenStore + 默认 Dio + PrefsFoodFreqStore +
//     过期回调接 authState.forceAnon），main() 走这条；
//   - 传参 = 测试桩，端到端用例注入内存 TokenStore 与假 dio，零网络。
//
// 行为对照 H5：web 侧没有 ProviderContainer，依赖装配等价物是
// js/app.js 顶部一次性 new/取模块引用（HealthAPI 单例 + js/api.js 自带
// token 读写）。重试语义对齐 H5 —— js/api.js:239-265 的 realRequest 失败
// 就抛，只由界面「重试」按钮人工再发一次，故本工厂显式关掉 Riverpod 3
// 的自动退避重试（见下方 retry 注释）。
//
// 分层约束：本文件是**唯一**允许把 data 层具体实现（SecureTokenStore /
// PrefsFoodFreqStore）与 UI 状态（authStateProvider）缝在一起的地方；
// features/* 只依赖 provider，不 import 具体实现。

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/api_client.dart';
import '../data/auth_api.dart';
import '../data/health_api.dart';
import '../data/token_store.dart';
import '../features/home/home_controller.dart' show healthApiProvider;
import '../features/notifications/reminder_scheduler.dart';
import '../features/record/food_freq.dart';
import 'auth_state.dart';

/// 拼装组合根容器。参数全部可缺省，缺省即生产链路。
///
/// [tokenStore] / [dio] / [foodFreqStore]：注入替身，测试用。
/// [onSessionExpired]：非空则**替换**默认的 forceAnon 接线（用例需要在回调
/// 里挂计数钩子时用）；此时默认接线不再执行——传参语义是"我知道我在改装配"。
///
/// 调用方负责 `dispose()`（测试里 `addTearDown(container.dispose)`）。
ProviderContainer buildRootContainer({
  TokenStore? tokenStore,
  Dio? dio,
  void Function()? onSessionExpired,
  FoodFreqStore? foodFreqStore,
}) {
  // I1 断环（原 main.dart 的 late final 技巧，随拼装一并搬来）：
  // ApiClient 的过期回调要读 container，而 container 的 overrides 又要引用
  // apiClient → 先声明 late final、构造回调时只捕获闭包、随后回填。
  late final ProviderContainer container;
  final store = tokenStore ?? SecureTokenStore();
  final apiClient = ApiClient(
    tokenStore: store,
    dio: dio, // null → ApiClient 内部 defaultDio()（15s 三超时）
    onSessionExpired: () {
      final injected = onSessionExpired;
      if (injected != null) {
        injected();
        return;
      }
      // 401 续期失败清 token → 门控直接置 anon 回登录页（forceAnon 幂等，
      // 并发过期请求各触发一次无碍）。对照 H5：js/api.js 清 token 后由
      // 调用方错误分支引导回登录，行为一致，只是 Flutter 侧要主动换页。
      container.read(authStateProvider.notifier).forceAnon();
    },
  );
  container = ProviderContainer(
    overrides: [
      tokenStoreProvider.overrideWithValue(store),
      apiClientProvider.overrideWithValue(apiClient),
      authApiProvider.overrideWithValue(AuthApi(apiClient, store)),
      healthApiProvider.overrideWithValue(HealthApi(apiClient)),
      foodFreqStoreProvider.overrideWithValue(
          foodFreqStore ?? PrefsFoodFreqStore()),
    ],
    // M3 终审 Important-3：Riverpod 3 的容器级默认是指数退避自动重试
    // （element.dart:772 `origin.retry ?? container.retry ?? defaultRetry`，
    // 200ms 起、最多 10 次）。H5 语义是"失败一次 + 手动重试"（js/api.js
    // 失败即抛，界面「重试」按钮再发一次），自动重试既与 H5 不一致，也会
    // 让错误态用例的请求次数不确定。故传一个恒返回 null 的策略 = 明确不重试。
    // （注：ProviderContainer 构造里 `retry ?? parent?.retry`，只有传函数
    // 才能盖住 defaultRetry；传 null 等于不改默认。）
    retry: (_, _) => null,
  );
  return container;
}

/// 启动提醒自愈（M4-T6，对齐 H5 MainActivity:105 ensureWaterSchedule 的
/// "启动即补排"点）：init（渠道/权限，幂等）→ 按持久化开关重排
/// 三餐每日 + 当日剩余喝水。喝水不做多天链式（M4 降级面，见
/// reminder_scheduler.dart 文件头），启动重排即自愈。
///
/// 失败**静默容忍**（debugPrint）：通知链路坏不能挡 App 启动，
/// 下次启动再来；对齐 H5 Notify.post 捕 SecurityException 的静默语义。
/// main() 里 fire-and-forget 调用；widget 测试不启动它，天然跳过。
Future<void> bootstrapReminders(ProviderContainer container) async {
  try {
    final scheduler = container.read(reminderSchedulerProvider);
    await scheduler.init();
    await scheduler.sync(on: await scheduler.enabled());
  } catch (e) {
    debugPrint('bootstrapReminders failed: $e');
  }
}
