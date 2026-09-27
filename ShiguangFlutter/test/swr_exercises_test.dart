// ShiguangFlutter/test/swr_exercises_test.dart
// M9-A1：①exercises 重开播种（缓存先显+后台刷新）；②首取回写缓存、失败不存脏
// （首访失败仍抛现行口径 + _reload 失败清键——防「降级空列表」被缓存成旧真值的
// 脏源）；③weightTrend 首访回写、失败有缓存保旧。
// 与 brief 逐字稿的偏离（按现状适配令）：桩面用本仓既有命名
// exercisesByDate/exerciseError/weightTrendMap（brief 的 exercises/exercisesError/
// trendMap 不存在，仅按既有样式补 exerciseMap 工厂）；brief Step1 测试里
// 「await 首访失败不抛」与其 Step3 注「首访失败仍抛由既有 error 支处理（现行
// 口径）」互斥，按现行口径落 throwsA 钉 + 断键不写；播种/保旧观测用裸 container
// + 事件循环泵（桩取数全走微任务，Future.delayed(zero) 即完成一轮）。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/data/api_client.dart' show ApiException;
import 'package:shiguang_flutter/data/swr_cache.dart';
import 'package:shiguang_flutter/features/exercise/exercise_controller.dart'
    show exercisesProvider;
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider;
import 'package:shiguang_flutter/features/report/report_controller.dart'
    show weightTrendProvider;

import 'stubs/stub_health_api.dart';

/// 让出整圈事件循环：桩 fetch 无定时器、纯微任务链，一轮 delayed 即回落地。
Future<void> flushLoop() => Future<void>.delayed(Duration.zero);

List<Map<String, dynamic>> rows(ProviderContainer c, String key) =>
    c.read(swrCacheProvider).read<List<Map<String, dynamic>>>(key)!;

void main() {
  final date = DateTime.now().toIso8601String().substring(0, 10);

  test('①exercises 重开播种：新元素首帧即显缓存旧值，后台刷新换新', () async {
    final api = StubHealthApi(exercisesByDate: {
      date: [StubHealthApi.exerciseMap(id: 'e1', name: '跑步', kcal: 300)],
    });
    final c = ProviderContainer(
      overrides: [healthApiProvider.overrideWithValue(api)],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    await c.read(exercisesProvider(date).future); // 首访 loading→data+回写
    expect(rows(c, 'exercises.$date'), hasLength(1));

    // 云端多一条（_fetchAll 经 _mapRows 出拷贝，缓存旧值不受 stub 列表 mutate 影响）
    api.exercisesByDate![date]!
        .add(StubHealthApi.exerciseMap(id: 'e2', name: '骑行', kcal: 500));

    // invalidate + 重挂监听 = 重开语境（无在体监听时元素已弃）：首帧同步播种旧值
    c.invalidate(exercisesProvider(date));
    final sub = c.listen(exercisesProvider(date), (_, _) {});
    addTearDown(sub.close);
    final v0 = sub.read();
    expect(v0.hasValue, isTrue); // 无 loading 帧（播种命中）
    expect(v0.value, hasLength(1)); // 显的是缓存旧值 e1
    await flushLoop(); // 后台刷新完成
    expect(c.read(exercisesProvider(date)).value, hasLength(2));
    expect(rows(c, 'exercises.$date'), hasLength(2)); // 缓存随刷新回写
  });

  test('②首取回写；首访失败仍抛不存脏；_reload 失败清键防脏源', () async {
    final api = StubHealthApi(exercisesByDate: {
      date: [StubHealthApi.exerciseMap(id: 'e1', name: '跑步', kcal: 300)],
    });
    final c = ProviderContainer(
      overrides: [healthApiProvider.overrideWithValue(api)],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    await c.read(exercisesProvider(date).future);
    expect(c.read(swrCacheProvider).read<Object>('exercises.$date'), isNotNull);

    // 首访失败（无缓存语境）：现行口径=抛出落既有 error 支（Step3 注），
    // 钉「降级值不回写缓存」——brief 逐字稿的「不抛」与其 Step3 互斥，见头注。
    final api2 = StubHealthApi(exerciseError: ApiException('boom'));
    final c2 = ProviderContainer(
      overrides: [healthApiProvider.overrideWithValue(api2)],
      retry: (_, _) => null,
    );
    addTearDown(c2.dispose);
    await expectLater(
        c2.read(exercisesProvider(date).future), throwsA(isA<ApiException>()));
    expect(c2.read(swrCacheProvider).read<Object>('exercises.$date'), isNull);

    // _reload 失败（add/remove 后云真值重取，≙ :1732 catch→[] 降级）：
    // 降级空列表必须连带清键——否则旧真值 [e1] 留着下次播种即脏源。
    final sub = c.listen(exercisesProvider(date), (_, _) {});
    addTearDown(sub.close);
    await flushLoop(); // 元素重建（上轮 invalidate 后首次挂监听）回稳态
    api.exerciseError = ApiException('boom'); // GET 坏，DELETE 仍好
    final rec = c.read(exercisesProvider(date)).value!.single;
    await c.read(exercisesProvider(date).notifier).remove(rec, (_) {});
    expect(c.read(exercisesProvider(date)).value, isEmpty); // :1732 降级空
    expect(c.read(swrCacheProvider).read<Object>('exercises.$date'), isNull);
  });

  test('③weightTrend 首访回写、失败有缓存保旧不炸 error', () async {
    final api = StubHealthApi(weightTrend: StubHealthApi.weightTrendMap());
    final c = ProviderContainer(
      overrides: [healthApiProvider.overrideWithValue(api)],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    final sub = c.listen(weightTrendProvider, (_, _) {});
    addTearDown(sub.close);
    final t = await c.read(weightTrendProvider.future);
    expect(t.points, isNotEmpty);
    expect(c.read(swrCacheProvider).read<Object>('weightTrend'), isNotNull);

    // 失败+有缓存：静默保旧（≙ SwrFamily build catch 支）
    api.weightTrendError = ApiException('boom');
    c.invalidate(weightTrendProvider);
    await flushLoop();
    final v = c.read(weightTrendProvider);
    expect(v.hasError, isFalse);
    expect(v.value, same(t)); // 旧真值原样保留
    expect(api.trendCalls, 2); // 确实重发过请求
  });
}
