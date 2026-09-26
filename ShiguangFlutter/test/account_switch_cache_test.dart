// ShiguangFlutter/test/account_switch_cache_test.dart
// M4 终审 I1：登出/换号必须失效全部账号数据缓存。
// H5 登出 = HealthAPI.logout() + location.reload()（清全部内存态）；Flutter 侧
// 组合根 container 终身存活，只置 anon 不够——keepAlive 的 profileWeightProvider
// 与仍在监听（Shell 未卸）的 summary/weekReport 缓存会带着旧账号数据穿过
// signOut→重登，ProfileScreen 用 A 的体重播种输入位，误点保存即把 A 写进 B 的
// /user/weight。本用例按终审处方复现：账号 A 填热缓存 → signOut → 换号重登
// （桩换 B 数据）→ 断全部重读都发新请求拿 B 值，而不是 A 残留。
//
// 零网络：buildRootContainer（生产组合根）+ RecordingAdapter 按 envelope.path
// 分路；换号 = 用例中途改写 routes。
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/auth_state.dart';
import 'package:shiguang_flutter/app/root_container.dart';
import 'package:shiguang_flutter/data/token_store.dart';
import 'package:shiguang_flutter/domain/dates.dart' show todayIso;
import 'package:shiguang_flutter/features/exercise/exercise_controller.dart'
    show exerciseKcalProvider, exercisesProvider;
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show summaryProvider;
import 'package:shiguang_flutter/features/profile/profile_screen.dart'
    show profileWeightProvider;
import 'package:shiguang_flutter/features/record/food_freq.dart'
    show FoodFreqStore, foodFreqProvider;
import 'package:shiguang_flutter/features/report/report_controller.dart'
    show weekReportProvider;

import 'harness.dart' show RecordingAdapter, StubResponse;

/// 内存常吃计数桩：isInitialized 恒 false（不触云端 30 天初始化），
/// record() 只写内存 + saveCounts，验证 provider 失效后状态回空。
class _MemFreqStore implements FoodFreqStore {
  final Map<String, int> counts = {};
  @override
  Future<Map<String, int>> loadCounts() async => counts;
  @override
  Future<void> saveCounts(Map<String, int> c) async {}
  @override
  Future<bool> isInitialized() async => false;
  @override
  Future<void> markInitialized() async {}
}

/// 账号数据剧本：体重/日汇总/周报/运动记录四个路由的返回体，按账号切换。
/// M6-T3：运动卡上线后登出清单含 exercisesProvider（family 整族）。
Map<String, StubResponse> routesFor({
  required double weightKg,
  required num kcal,
  required num weekTarget,
  required String exercisesJson,
}) =>
    {
      '/user/body-metrics': (
        status: 200,
        text: '{"ok":true,"weightKg":$weightKg}'
      ),
      '/diet/summary': (
        status: 200,
        text: '{"ok":true,"kcal":$kcal,"target":1679,"carb":0,"protein":0,"fat":0,"water":0}'
      ),
      '/diet/exercises': (
        status: 200,
        text: exercisesJson // 契约 responseShape=array（contract diet-core.json）
      ),
      '/report/week': (
        status: 200,
        text:
            '{"ok":true,"days":["一","二","三","四","五","六","日"],"kcal":[1200,0,0,0,0,0,0],"target":$weekTarget,"rates":{"carb":50,"protein":50,"fat":50}}'
      ),
      // 登录成功回显（AuthApi.loginByUsername 读 data.token 写 store）
      '/auth/login': (
        status: 200,
        text:
            '{"ok":true,"token":{"accessToken":"tok-b","refreshToken":"rt-b","expiresIn":7200}}'
      ),
    };

Future<InMemoryTokenStore> signedInStore() async {
  final store = InMemoryTokenStore();
  await store.write(TokenData({
    'accessToken': 'tok-a',
    'refreshToken': 'rt-a',
    'expiresIn': 7200,
    'savedAt': 1000,
  }));
  return store;
}

void main() {
  // A 账号一条 100kcal 运动记录；B 账号清空（数组响应，契约 exercises 形状）
  const kExA =
      '[{"id":"x1","key":"run","name":"跑步","emoji":"🏃","amount":1,"unit":"min","kcal":100}]';
  const kExB = '[]';

  test('登出→换号重登：profileWeight/summary/weekReport/exercises/foodFreq 全部失效，重读发新请求拿新账号值',
      () async {
    final store = await signedInStore();
    final freqStore = _MemFreqStore();
    final adapter = RecordingAdapter(
        routes: routesFor(
            weightKg: 66.6,
            kcal: 1200,
            weekTarget: 1679,
            exercisesJson: kExA));
    final container = buildRootContainer(
      tokenStore: store,
      dio: Dio()..httpClientAdapter = adapter,
      foodFreqStore: freqStore,
    );
    addTearDown(container.dispose);
    final date = todayIso();

    // 阶段 0：bootstrap 门控 → authed（token 已在 store）
    await container.read(authStateProvider.notifier).bootstrap();
    expect(container.read(authStateProvider), AuthStatus.authed);

    // 阶段 1：账号 A 填热缓存。summary/weekReport 挂 active 监听——模拟
    // 用户仍停在 Shell 上（autoDispose 元素有人监听才会穿过登出活着）。
    expect(await container.read(profileWeightProvider.future), 66.6);
    final summarySub = container.listen(summaryProvider(date), (_, _) {});
    addTearDown(summarySub.close);
    expect((await container.read(summaryProvider(date).future)).kcal, 1200);
    final weekSub = container.listen(weekReportProvider, (_, _) {});
    addTearDown(weekSub.close);
    expect((await container.read(weekReportProvider.future)).target, 1679);
    final exSub = container.listen(exercisesProvider(date), (_, _) {});
    addTearDown(exSub.close);
    expect(await container.read(exercisesProvider(date).future), hasLength(1));
    expect(container.read(exerciseKcalProvider(date)), 100);
    await container.read(foodFreqProvider.notifier).record('苹果');
    expect(container.read(foodFreqProvider), {'苹果': 1});
    expect(adapter.countOf('/user/body-metrics'), 1);

    // 阶段 2：登出（H5 logout 等价：清 token + anon）
    await container.read(authStateProvider.notifier).signOut();
    expect(container.read(authStateProvider), AuthStatus.anon);
    expect(await store.read(), isNull);

    // 阶段 3：换号重登（B 剧本：体重 88.8 / kcal 500 / 周报 target 2000）。
    // 会话过期直登路径不经过 signOut，也靠 submit 成功后的失效兜底——
    // 本阶段 signOut 已失效一次，此处断言的是「登录后的重读必须是 B 数据」。
    adapter.routes.addAll(routesFor(
        weightKg: 88.8,
        kcal: 500,
        weekTarget: 2000,
        exercisesJson: kExB));
    await container.read(authStateProvider.notifier).submit(
        username: 'b', password: 'Test1234!@', isRegister: false);
    expect(container.read(authStateProvider), AuthStatus.authed);
    expect((await store.read())!.accessToken, 'tok-b');

    // 断言：旧账号缓存全部失效——重读触发新请求，值是 B 的。
    // I1 修复前此处 RED：profileWeightProvider keepAlive 返回 A 的 66.6
    // 且不发第二次请求；仍被监听的 summary/weekReport 停留在 A 的 1200/1679。
    expect(await container.read(profileWeightProvider.future), 88.8);
    expect(adapter.countOf('/user/body-metrics'), 2); // 真的重发了请求
    expect((await container.read(summaryProvider(date).future)).kcal, 500);
    expect((await container.read(weekReportProvider.future)).target, 2000);
    // M6-T3/M7-T2：运动记录 family 整族失效——重取不带 A 的 x1。计数不锁死：
    // exercisesProvider 现为 autoDispose AsyncNotifier.family，本用例有在体
    // 监听（exSub），invalidate 即刻重建重发（登出一次+换号一次=共 3 发）；
    // 断「>1 必重发 + 值回 B 空列表」即可证缓存不残留。
    expect(await container.read(exercisesProvider(date).future), isEmpty);
    expect(container.read(exerciseKcalProvider(date)), 0);
    expect(adapter.countOf('/diet/exercises'), greaterThan(1));
    // 常吃计数：provider 回空（内存态随登出清空；prefs 面按终审处方不动）
    expect(container.read(foodFreqProvider), isEmpty);
  });

  test('会话过期→直接换号登录（不经过 signOut）：submit 成功后同样不带 A 残留',
      () async {
    final store = await signedInStore();
    final adapter = RecordingAdapter(
        routes: routesFor(
            weightKg: 66.6,
            kcal: 1200,
            weekTarget: 1679,
            exercisesJson: kExA));
    final container = buildRootContainer(
      tokenStore: store,
      dio: Dio()..httpClientAdapter = adapter,
      foodFreqStore: _MemFreqStore(),
    );
    addTearDown(container.dispose);

    await container.read(authStateProvider.notifier).bootstrap();
    expect(await container.read(profileWeightProvider.future), 66.6);
    await container.read(foodFreqProvider.notifier).record('苹果');

    // forceAnon（ApiClient 401 终判的生产回调）→ 不 signOut 直接重登 B
    container.read(authStateProvider.notifier).forceAnon();
    adapter.routes.addAll(routesFor(
        weightKg: 88.8,
        kcal: 500,
        weekTarget: 2000,
        exercisesJson: kExB));
    await container.read(authStateProvider.notifier).submit(
        username: 'b', password: 'Test1234!@', isRegister: false);

    expect(await container.read(profileWeightProvider.future), 88.8);
    expect(adapter.countOf('/user/body-metrics'), 2);
    expect(container.read(foodFreqProvider), isEmpty);
  });
}
