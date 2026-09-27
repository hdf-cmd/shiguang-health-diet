// ShiguangFlutter/test/swr_summary_test.dart
// M9-A1：summary SWR 语义三面钉——①首访 loading→data 且回写缓存；
// ②重开先 data(旧缓存) 后台刷新到 data(新)；③失败有缓存不炸 error。
import 'dart:async' show Completer;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/theme.dart' show shiguangTheme;
import 'package:shiguang_flutter/data/api_client.dart' show ApiException;
import 'package:shiguang_flutter/data/swr_cache.dart';
import 'package:shiguang_flutter/features/home/home_controller.dart';
import 'package:shiguang_flutter/features/home/home_screen.dart';

import 'harness.dart' show useBigSurface;
import 'stubs/stub_health_api.dart';

Future<ProviderContainer> boot(WidgetTester tester, StubHealthApi api) async {
  await useBigSurface(tester);
  final container = ProviderContainer(
    overrides: [healthApiProvider.overrideWithValue(api)],
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: shiguangTheme(), home: const HomeScreen()),
  ));
  return container;
}

void main() {
  final date = DateTime.now().toIso8601String().substring(0, 10);

  testWidgets('①首访：loading 骨架→data，缓存回写 summary.<date>', (tester) async {
    // 勘正（偏离 brief 逐字稿）：原稿 summaryGate:null 下桩即回，单 pump 后
    // 骨架帧已被数据帧覆盖（plate_ring_test 加载期用例的既有定式=挂 gate
    // 观测未回包窗口），骨架断言非确定。改挂 Completer 闸钉死首访 loading。
    final gate = Completer<void>();
    final api = StubHealthApi(
        summary: StubHealthApi.summaryMap(target: 1679), summaryGate: gate);
    final c = await boot(tester, api);
    await tester.pump(); // 首帧：未回包
    expect(find.byKey(const ValueKey('plate-ring-skeleton')), findsOneWidget);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.textContaining('已摄入 0 kcal'), findsOneWidget);
    expect(c.read(swrCacheProvider).read<Object>('summary.$date'), isNotNull);
  });

  testWidgets('②重开播种：缓存在场先显旧数，回包后跳新数（≤后台刷新）', (tester) async {
    final api = StubHealthApi(summary: StubHealthApi.summaryMap(target: 1679));
    final c = await boot(tester, api);
    await tester.pumpAndSettle(); // 首访完成，缓存=target 1679
    // 换云端值后卸载重建首页语境（模拟 autoDispose 回访）：
    api.summary = StubHealthApi.summaryMap(target: 2000);
    final date2 = date;
    // 直接重建 provider 流：invalidate 使 autoDispose 重挂
    c.invalidate(summaryProvider(date2));
    // 新 build 同步播种：首帧即有数据（无骨架帧）
    final v = c.listen(summaryProvider(date2), (_, _) {}).read();
    expect(v.hasValue, isTrue); // 播种命中（旧值）
    expect((v.value! as dynamic).target, 1679);
    await tester.pumpAndSettle(); // 后台刷新完成
    expect(c.read(summaryProvider(date2)).value!.target, 2000); // 新值落地
  });

  testWidgets('③失败有缓存：静默保旧不炸 error 卡', (tester) async {
    final api = StubHealthApi(summary: StubHealthApi.summaryMap(target: 1679));
    final c = await boot(tester, api);
    await tester.pumpAndSettle();
    api.summaryError = ApiException('登录已过期，请重新登录');
    c.invalidate(summaryProvider(date));
    await tester.pumpAndSettle();
    expect(c.read(summaryProvider(date)).hasValue, isTrue); // 仍是数据
    expect(c.read(summaryProvider(date)).hasError, isFalse);
    expect(find.text('登录已过期，请重新登录'), findsNothing); // UI 无 error 卡
  });
}
