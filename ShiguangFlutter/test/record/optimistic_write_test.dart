// ShiguangFlutter/test/record/optimistic_write_test.dart
// M11-T2 钉：记一笔 / 删一笔的**乐观落位**——还原 H5 既有行为，不是新行为。
// 权威源 js/app.js:663-694「乐观更新：立即入列表+环，不等网络（反馈8）；失败回滚」
// 与 :558-587「乐观删除：立即移除，失败放回」。
// M9 的「写后删键」（record_controller.dart:94-95）本意是防回访播种写前旧数，
// 副作用是把写路径打回「等 400ms 回包 + 整卡骨架」，比 H5 还慢 —— 本批改回。
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/data/api_client.dart' show ApiException;
import 'package:shiguang_flutter/domain/models.dart' show Summary;
import 'package:shiguang_flutter/data/swr_cache.dart';
import 'package:shiguang_flutter/features/record/food_freq.dart';
import 'package:shiguang_flutter/features/record/record_controller.dart';

import '../stubs/stub_health_api.dart';

const _date = '2026-10-19';

void main() {
  final egg = <String, dynamic>{
    'date': _date,
    'meal': 'lunch',
    'name': '鸡蛋',
    'portion': '禽蛋 · 1 个约 50g',
    'kcal': 72,
    'emoji': '🥚',
    'protein': 7,
    'carb': 1,
    'fat': 5,
    'image': '',
  };
  final rice = <String, dynamic>{
    'id': 'rec_rice',
    'meal': 'lunch',
    'name': '米饭',
    'portion': '200g',
    'kcal': 232,
    'emoji': '🍚',
    'protein': 5.2,
    'carb': 51.8,
    'fat': 0.6,
    'image': '',
  };

  ProviderContainer mk(StubHealthApi api) {
    final c = ProviderContainer(overrides: [
      healthApiProvider.overrideWithValue(api),
      foodFreqStoreProvider.overrideWithValue(_FreqStore()),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  /// 建立当日 records/summary 的当前态（首访 loading→data）。
  Future<void> seed(ProviderContainer c) async {
    await c.read(recordsProvider(_date).future);
    await c.read(summaryProvider(_date).future);
  }

  List<Map<String, dynamic>> rows(ProviderContainer c) =>
      c.read(recordsProvider(_date)).value ?? const [];

  test('①回包前新条目已在列表、环已加算（≙ H5 :669-675 不等网络）', () async {
    final api = StubHealthApi(
      records: [rice],
      summary: StubHealthApi.summaryMap(
          kcal: 232, protein: 5.2, carb: 51.8, fat: 0.6),
    )..addGate = Completer<void>();
    final c = mk(api);
    await seed(c);
    expect(rows(c).length, 1);

    final pending = c
        .read(recordControllerProvider)
        .addRecord(_date, egg, pendingKey: 'u_egg');

    // 乐观位：仍在途（gate 未开），界面数据已到位
    expect(rows(c).length, 2, reason: '未回包就必须已入列表');
    expect(rows(c).last['name'], '鸡蛋');
    expect(rows(c).last['id'], startsWith('tmp_')); // ≙ H5 :665 'tmp_'+Date.now()
    final s = c.read(summaryProvider(_date)).value!;
    expect([s.kcal, s.protein, s.carb, s.fat], [304, 12.2, 52.8, 5.6]);

    api.addGate!.complete();
    expect(await pending, isTrue);
  });

  test('②失败即回滚：条目移除、环减回、异常照实上抛、不计数（≙ H5 :685-693）',
      () async {
    final api = StubHealthApi(
      records: [rice],
      summary: StubHealthApi.summaryMap(
          kcal: 232, protein: 5.2, carb: 51.8, fat: 0.6),
    )
      ..addGate = Completer<void>()
      ..addError = ApiException('服务器繁忙');
    final c = mk(api);
    await seed(c);

    final pending = c
        .read(recordControllerProvider)
        .addRecord(_date, egg, pendingKey: 'u_egg');
    expect(rows(c).length, 2); // 先乐观
    api.addGate!.complete();

    await expectLater(pending, throwsA(isA<ApiException>()));
    expect(rows(c).length, 1); // 后回滚
    expect(rows(c).single['name'], '米饭');
    expect(c.read(summaryProvider(_date)).value!.kcal, 232);
    expect(c.read(foodFreqProvider), isEmpty); // 失败不计数（既有口径保持）
  });

  test('③成功走后台对账，且**不再删键**（M9 删键＝回访白屏 400ms 的根）', () async {
    final api = StubHealthApi(
        records: [rice], summary: StubHealthApi.summaryMap(kcal: 232));
    final c = mk(api);
    await seed(c);
    // 生产里首页/记录页恒在 watch 这两个 provider；无监听者时 autoDispose
    // 元素被 invalidate 后不会立即重建，对账请求也就不会发——故这里挂监听者，
    // 与真机同形。
    final sub = c.listen(recordsProvider(_date), (_, _) {});
    addTearDown(sub.close);
    final callsBefore = api.recordsCalls;

    await c
        .read(recordControllerProvider)
        .addRecord(_date, egg, pendingKey: 'u_egg');
    // invalidate 后的重建落在微任务里，让队列走一遍再核对账是否真发（量具时序，
    // 非产品行为）。
    await Future<void>.delayed(Duration.zero);

    expect(api.recordsCalls, greaterThan(callsBefore)); // 确实重取对账
    final cache = c.read(swrCacheProvider);
    expect(
      cache.read<List<Map<String, dynamic>>>('records.$_date'),
      isNotNull,
      reason: '写后保留键：重访当日必须先播种再刷新，而非落骨架',
    );
    expect(cache.read<Summary>('summary.$_date'), isNotNull);
  });

  test('④删一笔：未回包即移除并减算（≙ H5 :563-571 乐观删除）', () async {
    final api = StubHealthApi(
      records: [rice, {...egg, 'id': 'rec_egg'}],
      summary: StubHealthApi.summaryMap(
          kcal: 304, protein: 12.2, carb: 52.8, fat: 5.6),
    )..deleteGate = Completer<void>();
    final c = mk(api);
    await seed(c);
    expect(rows(c).length, 2);

    final pending =
        c.read(recordControllerProvider).deleteRecord(_date, 'rec_egg');

    expect(rows(c).length, 1, reason: '未回包就必须已移除');
    expect(rows(c).single['name'], '米饭');
    expect(c.read(summaryProvider(_date)).value!.kcal, 232);

    api.deleteGate!.complete();
    await pending;
    await Future<void>.delayed(Duration.zero); // 让「提交前发起」的那次刷新先落定
    // 🔴 反「闪回」钉：删一笔提交前发起的后台刷新，服务端此刻仍留着该行（合法
    // 读数，代次判据判不出来），若不挂起就会把乐观值盖回去——表现为删掉的行
    // 闪一下又回来约一个往返。见 SwrCache.hold / RecordController._holdDay。
    expect(rows(c).map((e) => e['name']).toList(), ['米饭']);
  });

  test('⑤删除失败放回原位并加算复原', () async {
    final api = StubHealthApi(
      records: [rice, {...egg, 'id': 'rec_egg'}],
      summary: StubHealthApi.summaryMap(kcal: 304),
    )
      ..deleteGate = Completer<void>()
      ..deleteError = ApiException('网络异常');
    final c = mk(api);
    await seed(c);

    final pending =
        c.read(recordControllerProvider).deleteRecord(_date, 'rec_egg');
    expect(rows(c).length, 1);
    api.deleteGate!.complete();

    await expectLater(pending, throwsA(isA<ApiException>()));
    expect(rows(c).map((e) => e['name']), ['米饭', '鸡蛋']); // 放回原位
    expect(c.read(summaryProvider(_date)).value!.kcal, 304);
  });

  test('⑥target/water 不因加减一笔而漂移（H5 :670-673 只动四项）', () async {
    final api = StubHealthApi(
        records: [rice],
        summary: StubHealthApi.summaryMap(
            kcal: 232, target: 1679, water: 3))
      ..addGate = Completer<void>();
    final c = mk(api);
    await seed(c);

    final pending = c
        .read(recordControllerProvider)
        .addRecord(_date, egg, pendingKey: 'u_egg');
    final s = c.read(summaryProvider(_date)).value!;
    expect([s.target, s.water], [1679, 3]);
    api.addGate!.complete();
    await pending;
  });
}

/// 频次持久层替身：恒已初始化，只观测写没写。
class _FreqStore implements FoodFreqStore {
  Map<String, int> saved = {};
  @override
  Future<bool> isInitialized(String uid) async => true;
  @override
  Future<void> markInitialized(String uid) async {}
  @override
  Future<Map<String, int>> loadCounts(String uid) async => saved;
  @override
  Future<void> saveCounts(String uid, Map<String, int> counts) async =>
      saved = Map.of(counts);
}
