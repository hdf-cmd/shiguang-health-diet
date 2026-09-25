// ShiguangFlutter/test/profile_screen_test.dart
// M4 Task 4：「我的」页体重卡 + 秤同步 + 退出登录。
// 行为权威源 H5：index.html:459-482（记体重区结构/按钮文案逐字）、
// js/app.js:910/927-929（初始值=当前体重、stepper ±0.5 边界 20–300 两位小数）、
// js/app.js:930-949（saveWeightKg 校验 20–300 → logWeight(w, todayIso()) →
// toast「已记录 X kg · 趋势已更新」）、js/app.js:953-956（SG_onScaleWeight：
// 读数写进输入位、仅 stable 落库）、js/app.js:1168（退出登录=清 token 回登录）。
// 秤终态文案逐字抄 HealthyDiet/.../ScaleSync.kt :83/:85/:71/:130 与
// MainActivity.kt:52；'ok'/'cancelled' 静默（Kotlin finish :241 只转发非 ok，
// T3 账本 M5）。测试地基：harness.useBigSurface + scale_fakes.FakeTransport。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/auth_state.dart';
import 'package:shiguang_flutter/data/token_store.dart';
import 'package:shiguang_flutter/domain/dates.dart' show todayIso;
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider;
import 'package:shiguang_flutter/features/profile/profile_screen.dart'
    show ProfileScreen;
import 'package:shiguang_flutter/features/scale/scale_service.dart';

import 'harness.dart';
import 'scale_fakes.dart';
import 'stubs/stub_health_api.dart';

/// 每次测试现造；start 后由用例填 bodyMetrics 等配置。
StubHealthApi newApi() => StubHealthApi(
      bodyMetrics: const <String, dynamic>{'weightKg': 66.66},
    );

ScaleService fastScale(FakeTransport t) => ScaleService(
      t,
      scanTimeout: const Duration(milliseconds: 300),
      readTimeout: const Duration(milliseconds: 1500),
    );

/// 组合根桩：healthApi/tokenStore/scaleService 全替换，零网络零插件。
/// 返回 container 供登出用例直接读 authStateProvider。
ProviderContainer profileContainer({
  required StubHealthApi api,
  ScaleService? scale,
  TokenStore? store,
}) {
  final container = ProviderContainer(
    overrides: [
      healthApiProvider.overrideWithValue(api),
      tokenStoreProvider.overrideWithValue(store ?? InMemoryTokenStore()),
      scaleServiceProvider
          .overrideWithValue(scale ?? fastScale(FakeTransport())),
    ],
    // 对齐 buildRootContainer：H5 语义失败不自动重试（root_container.dart:84）
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  return container;
}

Future<ProviderContainer> pumpProfile(
  WidgetTester tester,
  StubHealthApi api, {
  ScaleService? scale,
  TokenStore? store,
}) async {
  await useBigSurface(tester);
  final container =
      profileContainer(api: api, scale: scale, store: store);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: const MaterialApp(home: ProfileScreen()),
  ));
  await tester.pumpAndSettle();
  return container;
}

/// 取当前体重输入框的实时文本（±0.5 步进/秤 live 预览都写在这）。
String kgOf(WidgetTester tester) =>
    tester.widget<TextField>(find.byType(TextField)).controller!.text;

void main() {
  /* ---------- ① 当前体重渲染 ---------- */

  testWidgets('①当前体重：桩 body-metrics 66.66 → 卡上「66.66 kg」，输入位播种 66.66',
      (tester) async {
    final api = newApi();
    await pumpProfile(tester, api);

    expect(find.text('66.66 kg'), findsOneWidget); // 卡上当前体重（JS 数字串形）
    expect(kgOf(tester), '66.66'); // 输入位播种（toStringAsFixed(2)）
    expect(find.text('⚖️ 从体脂秤同步（光脚站上秤）'),
        findsOneWidget); // index.html:474 逐字
    expect(find.text('退出登录'), findsOneWidget); // index.html:456 逐字
  });

  /* ---------- ② 手动 ±0.5 两位小数（js/app.js:927-929） ---------- */

  testWidgets('②stepper −/+ 各走 0.5 且恒两位小数；下界 20 钳制', (tester) async {
    await pumpProfile(tester, newApi());

    await tester.tap(find.text('−')); // 66.66 → 66.16（简报指定值）
    await tester.pump();
    expect(kgOf(tester), '66.16');

    await tester.tap(find.text('＋')); // 66.16 → 66.66
    await tester.pump();
    expect(kgOf(tester), '66.66');

    await tester.enterText(find.byType(TextField), '20.10');
    await tester.tap(find.text('−')); // 20.10-0.5 越界 → 钳到 20.00
    await tester.pump();
    expect(kgOf(tester), '20.00');
  });

  /* ---------- ③ 保存 → logWeight + toast 逐字（js/app.js:930-944） ---------- */

  testWidgets('③保存：logWeight 收到 (66.16, todayIso())，toast「已记录 66.16 kg · 趋势已更新」',
      (tester) async {
    final api = newApi();
    await pumpProfile(tester, api);

    await tester.tap(find.text('−'));
    await tester.pump();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(api.weightLogs, hasLength(1));
    expect(api.weightLogs.single.kg, 66.16);
    expect(api.weightLogs.single.date, todayIso());
    expect(find.textContaining('已记录 66.16 kg · 趋势已更新'),
        findsOneWidget); // app.js:944 逐字
  });

  testWidgets('③b 20–300 之外不提交：输 350 → toast「请输入有效体重」，不发 logWeight',
      (tester) async {
    final api = newApi();
    await pumpProfile(tester, api);

    await tester.enterText(find.byType(TextField), '350');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(api.weightLogs, isEmpty); // app.js:931 校验先于请求
    expect(find.text('请输入有效体重'), findsOneWidget); // 逐字
  });

  /* ---------- ④ 秤同步：live 预览 + locked 秒存（app.js:953-956） ---------- */

  testWidgets('④同步：非锁定 60.5 只进预览；locked 66.66 自动 logWeight + 已记录 toast',
      (tester) async {
    final t = FakeTransport();
    final api = newApi();
    await pumpProfile(tester, api, scale: fastScale(t));

    await tester.tap(find.text('⚖️ 从体脂秤同步（光脚站上秤）'));
    await tester.pump();
    // 进行中：状态行（ScaleSync.kt:98 逐字）+ 取消按钮 + 同步按钮禁用
    expect(find.text('正在寻找体脂秤…（请光脚站上秤）'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);

    t.emit(liveFrame(60.5));
    await tester.pump();
    await tester.pump();
    expect(kgOf(tester), '60.5'); // JS 数字串形（H5 直接 input.value = kg）
    expect(api.weightLogs, isEmpty); // 非 stable 仅预览不落库

    t.emit(liveFrame(66.66, locked: true));
    await tester.pumpAndSettle();
    expect(api.weightLogs, hasLength(1)); // stable 才存（秒存语义）
    expect(api.weightLogs.single.kg, 66.66);
    expect(api.weightLogs.single.date, todayIso());
    expect(find.textContaining('已记录 66.66 kg · 趋势已更新'), findsOneWidget);
    expect(find.text('取消'), findsNothing); // 会话结束
    expect(find.text('正在寻找体脂秤…（请光脚站上秤）'), findsNothing);
  });

  /* ---------- ⑤ 终态文案映射 ---------- */

  testWidgets('⑤scan-timeout → ScaleSync.kt:85 逐字文案，同步态解除可重试',
      (tester) async {
    final t = FakeTransport(scanReturnsSession: false);
    await pumpProfile(tester, newApi(), scale: fastScale(t));

    await tester.tap(find.text('⚖️ 从体脂秤同步（光脚站上秤）'));
    await tester.pumpAndSettle();

    expect(find.text('30 秒没找到秤：请光脚站上秤再点一次'), findsOneWidget);
    expect(find.text('取消'), findsNothing);
  });

  testWidgets('⑤b cancelled 静默（T3 账本 M5）：点取消后无错误文案、扫描协作终结',
      (tester) async {
    final t = FakeTransport(gateScans: true);
    await pumpProfile(tester, newApi(), scale: fastScale(t));

    await tester.tap(find.text('⚖️ 从体脂秤同步（光脚站上秤）'));
    await tester.pump();
    expect(find.text('取消'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('取消'), findsNothing);
    expect(find.text('正在寻找体脂秤…（请光脚站上秤）'), findsNothing);
    expect(find.textContaining('没找到秤'), findsNothing); // cancelled 不出错误
    expect(t.scanAborts, 1); // 死区修复生效：取消协作终结在途扫描
    expect(t.scanAndConnectCalls, 1);

    // 立即重试应真发起第二次扫描（T3 遗留死区在 UI 侧的验收面）
    await tester.tap(find.text('⚖️ 从体脂秤同步（光脚站上秤）'));
    await tester.pump();
    expect(t.scanAndConnectCalls, 2);
  });

  /* ---------- ⑥ 退出登录 ---------- */

  testWidgets('⑥退出登录：清 token（H5 _clearToken）+ 门控置 anon 回登录页',
      (tester) async {
    final store = InMemoryTokenStore();
    await store.write(TokenData({'accessToken': 't', 'refreshToken': 'r'}));
    final container =
        await pumpProfile(tester, newApi(), store: store);

    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();

    expect(await store.read(), isNull); // 等价 H5 logout=HealthAPI.logout
    expect(container.read(authStateProvider),
        AuthStatus.anon); // AuthGate 据此切回 LoginScreen
  });
}
