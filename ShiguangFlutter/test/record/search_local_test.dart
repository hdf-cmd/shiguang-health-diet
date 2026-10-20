// ShiguangFlutter/test/record/search_local_test.dart
// M11-T1 钉：搜索改「按餐次拉一份空词全量 + 端上过滤」，打字零往返。
//
// 判据权威源＝云函数 HealthyDiet/cloudfunctions/api-diet/index.js:57-93：
//   内置 `f.name.includes(kw)`（区分大小写，:60）；自定义 RegExp options:"i"
//   （不区分，:66）+ `limit(20)`（:68）；餐次维在两支里都**服务端**完成，
//   且搜索结果元素不带 meals（:81-92 手工拼装）——故端上只按关键词过滤，
//   餐次维由「每个餐次各取一份空词快照」承载。
// 下方 _CloudSemanticsStub 是 index.js 的逐行转写（独立于 Dart 实现的尺子），
// 与被测端上过滤互为对照，二者不一致即红。
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/data/api_client.dart' show ApiException;
import 'package:shiguang_flutter/data/health_api.dart';
import 'package:shiguang_flutter/data/swr_cache.dart';
import 'package:shiguang_flutter/features/record/food_freq.dart';
import 'package:shiguang_flutter/features/record/food_search_local.dart';
import 'package:shiguang_flutter/features/record/record_controller.dart';

void main() {
  final builtin = <Map<String, dynamic>>[
    {'id': 'u_01', 'name': '纯牛奶', 'kcal': 175, 'meals': ['breakfast', 'snack']},
    {'id': 'u_06', 'name': '米饭', 'kcal': 174, 'meals': ['lunch', 'dinner']},
    // 大小写敏感靶：内置走 includes（区分），故 'bar' 不该命中
    {'id': 'u_90', 'name': '能量Bar', 'kcal': 100, 'meals': ['lunch']},
    {'id': 'u_91', 'name': '可乐', 'kcal': 215, 'meals': ['snack']},
  ];
  final customs = <Map<String, dynamic>>[
    // 自定义靶：RegExp options:"i"（不区分），故 'bar' 应命中
    {'id': 'cf_x1', 'name': '酸奶Bar', 'kcal': 90},
    {'id': 'cf_x2', 'name': '蛋炒饭', 'kcal': 300},
  ];

  ProviderContainer mkContainer(
      _CloudSemanticsStub api, {Map<String, int> counts = const {}}) {
    final c = ProviderContainer(overrides: [
      healthApiProvider.overrideWithValue(api),
      foodFreqStoreProvider.overrideWithValue(MemoryStore(counts)),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Future<List<Map<String, dynamic>>> doSearch(
          ProviderContainer c, String kw, String meal) =>
      c.read(searchProvider((keyword: kw, meal: meal)).future);

  test('①开层首拉一次空词全量后，连打 5 个词零网络请求', () async {
    final api = _CloudSemanticsStub(builtin, customs);
    final c = mkContainer(api);

    await doSearch(c, '', 'lunch'); // 开层：建快照
    final callsAfterOpen = api.calls.length;
    expect(callsAfterOpen, 1);
    expect(api.calls.first.keyword, ''); // 快照恒为空词形态

    for (final kw in ['米', '米饭', '牛', 'Bar', 'bar']) {
      final out = await doSearch(c, kw, 'lunch');
      expect(out, isNotNull);
    }
    expect(api.calls.length, 1); // 打字期间一条都没多发
  });

  test('②关键词命中集与云端逐行转写一致（含大小写两支）', () async {
    final api = _CloudSemanticsStub(builtin, customs);
    final c = mkContainer(api);
    await doSearch(c, '', 'lunch'); // 快照：meal=lunch → 可乐(snack) 不在快照内

    for (final kw in ['米', '奶', 'Bar', 'bar', '炒饭', '不存在词']) {
      final local = await doSearch(c, kw, 'lunch');
      // 快照已按 lunch 过滤过，故对照尺也取同一 meal 维
      final cloud = await api.searchFoods(kw, 'lunch');
      expect(local.map((e) => e['id']),
          cloud.map((e) => (e as Map)['id']),
          reason: '关键词「$kw」端上结果必须等于云端');
    }
  });

  test('③内置区分大小写、自定义不区分（bug-for-bug ≙ index.js:60 vs :66）', () async {
    final api = _CloudSemanticsStub(builtin, customs);
    final c = mkContainer(api);
    await doSearch(c, '', 'lunch');

    final upper = await doSearch(c, 'Bar', 'lunch');
    final lower = await doSearch(c, 'bar', 'lunch');
    expect(upper.map((e) => e['name']), containsAll(['能量Bar', '酸奶Bar']));
    // 小写 bar：内置「能量Bar」不含小写 bar → 只剩自定义「酸奶Bar」
    expect(lower.map((e) => e['name']), ['酸奶Bar']);
  });

  test('④切餐次各取一份快照（餐次维由快照承载，打字仍零请求）', () async {
    final api = _CloudSemanticsStub(builtin, customs);
    final c = mkContainer(api);

    final snack = await doSearch(c, '', 'snack');
    expect(snack.map((e) => e['name']), containsAll(['纯牛奶', '可乐']));
    final lunch = await doSearch(c, '', 'lunch');
    expect(lunch.map((e) => e['name']), isNot(contains('可乐')));
    expect(api.calls.map((e) => e.meal), ['snack', 'lunch']);

    final before = api.calls.length;
    expect((await doSearch(c, '牛', 'snack')).length, 1);
    expect(api.calls.length, before); // 同餐次再打字 → 零新增
  });

  test('⑤自定义恰满 20 条（limit(20) 截断信号）→ 打字回落云端逐词', () async {
    final manyCustoms = [
      for (var i = 0; i < 25; i++) {'id': 'cf_$i', 'name': '自造$i号'},
    ];
    final api = _CloudSemanticsStub(builtin, manyCustoms);
    final c = mkContainer(api);

    await doSearch(c, '', 'lunch'); // 空词快照：cf_ 项被截到 20
    final before = api.calls.length;
    final out = await doSearch(c, '自造21号', 'lunch');
    expect(api.calls.length, greaterThan(before)); // 必须回云端，否则静默搜不到
    expect(out.map((e) => e['name']), ['自造21号']); // 第 21 条仍可搜到
  });

  test('⑥快照拉取失败 → AsyncValue 落 error，UI「搜索失败」分支可达', () async {
    final api = _CloudSemanticsStub(builtin, customs)..fail = true;
    final c = mkContainer(api);
    // 🔴 断言走 AsyncValue 而非 `.future`：Riverpod 3.4.3 实测——AsyncNotifier
    // 的 build 抛错时 `.future` 永不 settle（有无人监听都一样），只有 AsyncValue
    // 正常落 AsyncError。UI 侧 `ref.watch(searchProvider(q))` 吃的正是
    // AsyncValue（search_sheet.dart:213-223「搜索失败：msg」+「重试」），
    // 故此写法与生产同形；若哪天 .future 也能 settle，说明上游修了行为。
    final q = (keyword: '', meal: 'lunch');
    final sub = c.listen(searchProvider(q), (_, _) {});
    await Future<void>.delayed(Duration.zero);
    final v = c.read(searchProvider(q));
    expect(v.hasError, isTrue);
    expect(v.error, isA<ApiException>());
    sub.close();
  });

  test('⑦常吃频次参与重排（本地过滤后仍走 sortFoodByFreq）', () async {
    final api = _CloudSemanticsStub(builtin, customs);
    final c = mkContainer(api, counts: {'米饭': 9});
    await c.read(foodFreqProvider.notifier).ensureLoaded();

    final out = await doSearch(c, '', 'lunch');
    expect(out.first['name'], '米饭');
    expect(api.calls.length, 1); // 频次来源不额外发搜索请求
  });

  test('⑧库变更失效面：清 foods.full.* 与 search.* 后重建快照', () async {
    final api = _CloudSemanticsStub(builtin, customs);
    final c = mkContainer(api);
    await doSearch(c, '米', 'lunch');
    expect(c.read(swrCacheProvider).read<List<Map<String, dynamic>>>(
        foodsFullCacheKey('lunch')), isNotNull);

    // 生产路径走 record_controller.invalidateFoodLibrary(WidgetRef)；测试侧
    // ProviderContainer 非 WidgetRef，故展开同一套两步（漏一步即回归）。
    clearFoodLibraryCache(c.read(swrCacheProvider));
    c.invalidate(searchProvider);
    expect(c.read(swrCacheProvider)
        .read<List<Map<String, dynamic>>>(foodsFullCacheKey('lunch')), isNull);

    await doSearch(c, '米', 'lunch');
    expect(api.calls.length, 2); // 重新拉了一份快照
  });
}

/// index.js:57-93 的逐行转写（对照尺）。calls 记录每次「云端请求」的入参。
class _CloudSemanticsStub implements HealthApi {
  _CloudSemanticsStub(this.builtin, this.customs);

  final List<Map<String, dynamic>> builtin;
  final List<Map<String, dynamic>> customs;
  final List<({String keyword, String? meal})> calls = [];
  bool fail = false;

  @override
  Future<List<dynamic>> searchFoods(String keyword, [String? meal]) async {
    calls.add((keyword: keyword, meal: meal));
    if (fail) throw ApiException('网络异常');
    final kw = (keyword).trim();
    final results = <Map<String, dynamic>>[];
    for (final f in builtin) {
      final fm = (f['meals'] as List?)?.cast<String>() ?? const <String>[];
      if (kw.isNotEmpty && !f['name'].toString().contains(kw)) continue;
      if (meal != null && fm.isNotEmpty && !fm.contains(meal)) continue;
      results.add(Map<String, dynamic>.from(f));
    }
    final esc = RegExp.escape(kw);
    var taken = 0;
    for (final c in customs) {
      if (taken >= 20) break; // index.js:68 limit(20)
      final name = c['name'].toString();
      if (kw.isNotEmpty &&
          !RegExp(esc, caseSensitive: false).hasMatch(name)) {
        continue;
      }
      results.add({'id': c['id'], 'name': name, 'kcal': c['kcal']});
      taken++;
    }
    return results;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} 未桩');
}

class MemoryStore implements FoodFreqStore {
  MemoryStore(this._counts);
  final Map<String, int> _counts;
  @override
  Future<bool> isInitialized(String uid) async => true;
  @override
  Future<void> markInitialized(String uid) async {}
  @override
  Future<Map<String, int>> loadCounts(String uid) async => _counts;
  @override
  Future<void> saveCounts(String uid, Map<String, int> counts) async {}
}
