// ShiguangFlutter/test/food_freq_test.dart
// 「常吃排序 + 吃过次数」单测（M12 改钉）：初始化从「逐日 30 请求」改为
// 「/diet/records/freq 一次全史计数」；prefs 键升 v2（v1 的 30 天计数作废）。
// 老大 2026-10-20 裁决：计数口径＝全部历史（不是近 30 天）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiguang_flutter/data/api_client.dart';
import 'package:shiguang_flutter/data/health_api.dart';
import 'package:shiguang_flutter/features/record/food_freq.dart';
import 'package:shiguang_flutter/features/record/record_controller.dart';
import 'package:shiguang_flutter/features/record/search_sheet.dart';

void main() {
  group('sortFoodByFreq', () {
    Map<String, dynamic> f(String name) => {'name': name};
    List<Map<String, dynamic>> L(List<String> names) => names.map(f).toList();

    test('频次高者在前，同频次与零频次保持原相对顺序（稳定）', () {
      final out = sortFoodByFreq(
        L(['米饭', '鸡蛋', '牛奶', '鸡胸', '蛋白粉']),
        {'鸡蛋': 3, '鸡胸': 3, '米饭': 5},
      );
      expect(out.map((e) => e['name']),
          ['米饭', '鸡蛋', '鸡胸', '牛奶', '蛋白粉']);
    });

    test('计数表为空 → 原序返回（初始化未完成时不重排）', () {
      final out = sortFoodByFreq(L(['a', 'b', 'c']), const {});
      expect(out.map((e) => e['name']), ['a', 'b', 'c']);
    });

    test('缺 name 字段的条目按零频次垫底且保序', () {
      final out = sortFoodByFreq(
          [
            {'name': '牛奶'},
            {'id': 'no-name-1'},
            {'name': '米饭'},
            {'id': 'no-name-2'}
          ],
          {'米饭': 9});
      expect(out.map((e) => e['name'] ?? e['id']), ['米饭', '牛奶', 'no-name-1', 'no-name-2']);
    });
  });

  /* ---------- M12：prefs 键升 v2，v1（30 天窗口）计数读到即清 ---------- */

  group('PrefsFoodFreqStore 分账号键 v2', () {
    test('v1 全局键与 v1 分账号键读到即删；v2 键读写，账号间不互读', () async {
      SharedPreferences.setMockInitialValues({
        'sg_food_freq_counts': '{"旧菜":3}',
        'sg_food_freq_init_v1': true,
        'sg_food_freq_counts_u1': '{"30天菜":7}', // v1 分账号计数（窗口语义已作废）
        'sg_food_freq_init_v1_u1': true,
      });
      final store = PrefsFoodFreqStore();
      // v1 标记不得冒充已初始化——否则老用户永远看不到全史数
      expect(await store.isInitialized('u1'), isFalse);
      expect(await store.loadCounts('u1'), isEmpty);
      var p = await SharedPreferences.getInstance();
      expect(p.containsKey('sg_food_freq_counts'), isFalse);
      expect(p.containsKey('sg_food_freq_init_v1'), isFalse);
      expect(p.containsKey('sg_food_freq_counts_u1'), isFalse);
      expect(p.containsKey('sg_food_freq_init_v1_u1'), isFalse);

      await store.saveCounts('u1', {'米饭': 12});
      await store.markInitialized('u1');
      p = await SharedPreferences.getInstance();
      expect(p.getString('sg_food_freq_counts_v2_u1'), '{"米饭":12}');
      expect(p.getBool('sg_food_freq_init_v2_u1'), isTrue);
      expect(await store.loadCounts('u2'), isEmpty); // 他账号不互读
      expect(await store.isInitialized('u2'), isFalse);
    });

    test('端到端 ensureLoaded：uid 由 profile id 解析，落 v2 键逐字', () async {
      SharedPreferences.setMockInitialValues({});
      final api = _FreqApi(counts: {'米饭': 4});
      final c = ProviderContainer(overrides: [
        foodFreqStoreProvider.overrideWithValue(PrefsFoodFreqStore()),
        healthApiProvider.overrideWithValue(api),
      ]);
      addTearDown(c.dispose);
      await c.read(foodFreqProvider.notifier).ensureLoaded();
      final p = await SharedPreferences.getInstance();
      expect(p.getString('sg_food_freq_counts_v2_u_freq'), '{"米饭":4}');
      expect(p.getBool('sg_food_freq_init_v2_u_freq'), isTrue);
    });
  });

  group('FoodFreqNotifier.ensureLoaded（M12：一次全史计数）', () {
    test('未初始化：只发 1 次 freq 请求，逐日记录请求一条都不发', () async {
      final store = _MemoryStore();
      final api = _FreqApi(counts: {'米饭': 30, '鸡蛋': 7});
      final c = _container(store: store, api: api);
      await c.read(foodFreqProvider.notifier).ensureLoaded();
      expect(c.read(foodFreqProvider), {'米饭': 30, '鸡蛋': 7});
      expect(await store.isInitialized('u_freq'), isTrue);
      expect(await store.loadCounts('u_freq'), {'米饭': 30, '鸡蛋': 7});
      expect(api.freqCalls, 1);
      expect(api.mealCalls, isEmpty, reason: '逐日回填已整体移除（30 请求→1）');
    });

    test('已初始化：不再发任何网络请求，直接回放落盘计数', () async {
      final store = _MemoryStore(initialized: true, counts: {'牛奶': 7});
      final api = _FreqApi(counts: {'米饭': 1});
      final c = _container(store: store, api: api);
      await c.read(foodFreqProvider.notifier).ensureLoaded();
      expect(c.read(foodFreqProvider), {'牛奶': 7});
      expect(api.freqCalls, 0);
    });

    test('complete=false（服务端翻页截断）：计数照用并落标记，不每冷启重放',
        () async {
      final store = _MemoryStore();
      final api = _FreqApi(counts: {'米饭': 900}, complete: false);
      final c = _container(store: store, api: api);
      await c.read(foodFreqProvider.notifier).ensureLoaded();
      expect(c.read(foodFreqProvider), {'米饭': 900});
      expect(await store.isInitialized('u_freq'), isTrue);
    });

    test('响应缺 counts 字段：按失败处理，不落标记也不把空表当全史', () async {
      final store = _MemoryStore();
      final api = _FreqApi(counts: null);
      final c = _container(store: store, api: api);
      await c.read(foodFreqProvider.notifier).ensureLoaded();
      expect(c.read(foodFreqProvider), isEmpty);
      expect(await store.isInitialized('u_freq'), isFalse);
      // 下次开弹层可再试（_started 已复位）
      api.counts = {'米饭': 2};
      await c.read(foodFreqProvider.notifier).ensureLoaded();
      expect(c.read(foodFreqProvider), {'米饭': 2});
    });

    test('网络失败：state 保持空（列表原序），不落标记且允许本会话重试', () async {
      final store = _MemoryStore();
      final api = _FreqApi(counts: {'米饭': 3})..fail = true;
      final c = _container(store: store, api: api);
      await c.read(foodFreqProvider.notifier).ensureLoaded();
      expect(c.read(foodFreqProvider), isEmpty);
      expect(await store.isInitialized('u_freq'), isFalse);
      api.fail = false;
      await c.read(foodFreqProvider.notifier).ensureLoaded();
      expect(c.read(foodFreqProvider), {'米饭': 3});
    });
  });

  group('记一笔续算 + 搜索排序接线', () {
    test('addRecord 成功 → 同名 +1 并落盘；失败不计数', () async {
      final store = _MemoryStore(initialized: true, counts: {'米饭': 2});
      final api = _FreqApi(counts: const {});
      final c = _container(store: store, api: api);
      await c.read(foodFreqProvider.notifier).ensureLoaded(); // 回放 {'米饭':2}
      await c.read(recordControllerProvider).addRecord(
          '2026-09-25', {'name': '米饭', 'kcal': 230}, pendingKey: 'r1');
      expect(c.read(foodFreqProvider), {'米饭': 3});
      expect(await store.loadCounts('u_freq'), {'米饭': 3});
    });

    test('addRecord 失败 → 计数不变', () async {
      final store = _MemoryStore(initialized: true, counts: {'米饭': 2});
      final api = _FreqApi(counts: const {})..addFails = true;
      final c = _container(store: store, api: api);
      await c.read(foodFreqProvider.notifier).ensureLoaded();
      await expectLater(
          c.read(recordControllerProvider).addRecord(
              '2026-09-25', {'name': '米饭', 'kcal': 230}, pendingKey: 'r1'),
          throwsA(isA<ApiException>()));
      expect(c.read(foodFreqProvider), {'米饭': 2});
    });

    test('searchProvider 结果按频次稳定降序（常吃在前，无名者保云端原序）', () async {
      final store = _MemoryStore(
          initialized: true, counts: {'鸡蛋': 4, '面包': 4, '牛奶': 1});
      final api = _FreqApi(counts: const {})
        ..searchResult = [
          {'name': '牛奶'},
          {'name': '米饭'},
          {'name': '鸡蛋'},
          {'name': '面包'},
        ];
      final c = _container(store: store, api: api);
      await c.read(foodFreqProvider.notifier).ensureLoaded();
      final out = await c.read(searchProvider((keyword: '', meal: 'lunch')).future);
      expect(out.map((e) => e['name']), ['鸡蛋', '面包', '牛奶', '米饭']);
    });

    testWidgets('端到端：开弹层触发一次全史计数，常吃置顶渲染', (tester) async {
      final store = _MemoryStore(); // 未初始化 → 弹层应触发 1 次 freq 请求
      final api = _FreqApi(counts: {'米饭': 5})
        ..searchResult = [
          {'name': '鸡蛋', 'meta': '蛋类 · 1 个约 50g', 'kcal': 78, 'emoji': '🥚'},
          {'name': '米饭', 'meta': '主食 · 200g', 'kcal': 230, 'emoji': '🍚'},
        ];
      await tester.pumpWidget(ProviderScope(
        overrides: [
          healthApiProvider.overrideWithValue(api),
          foodFreqStoreProvider.overrideWithValue(store),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: SearchSheet(date: '2026-09-25', meal: 'lunch'),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(await store.isInitialized('u_freq'), isTrue);
      expect(api.freqCalls, 1);
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? '')
          .toList();
      expect(texts.indexOf('米饭'), greaterThan(-1));
      expect(texts.indexOf('米饭'), lessThan(texts.indexOf('鸡蛋')));
    });
  });
}

// ─── 测试地基 ───────────────────────────────────────────────

ProviderContainer _container({
  required _MemoryStore store,
  required _FreqApi api,
}) {
  final c = ProviderContainer(overrides: [
    foodFreqStoreProvider.overrideWithValue(store),
    healthApiProvider.overrideWithValue(api),
  ]);
  addTearDown(c.dispose);
  return c;
}

class _MemoryStore implements FoodFreqStore {
  _MemoryStore({this.initialized = false, this._counts});
  bool initialized;
  Map<String, int>? _counts;
  // 桩不分桶（uid 形参收下即符合接口），账号隔离语义由 PrefsFoodFreqStore 真桩用例钉。
  @override
  Future<bool> isInitialized(String uid) async => initialized;
  @override
  Future<void> markInitialized(String uid) async => initialized = true;
  @override
  Future<Map<String, int>> loadCounts(String uid) async => _counts ?? {};
  @override
  Future<void> saveCounts(String uid, Map<String, int> counts) async =>
      _counts = Map.of(counts);
}

/// HealthApi 桩：getFoodFreq 返回可编程计数（null=响应缺 counts 字段），
/// getMealRecords 只作「逐日回填已移除」的反证探针；其余成员 noSuchMethod 兜底。
class _FreqApi implements HealthApi {
  _FreqApi({this.counts, this.complete = true});
  Map<String, int>? counts;
  bool complete;
  bool fail = false;
  bool addFails = false;
  int freqCalls = 0;
  final List<String> mealCalls = [];
  List<Map<String, dynamic>> searchResult = const [];

  @override
  Future<Map<String, dynamic>> getFoodFreq() async {
    freqCalls++;
    if (fail) throw ApiException('网络异常');
    return {
      if (counts != null) 'counts': counts,
      'scanned': counts?.values.fold<int>(0, (a, b) => a + b) ?? 0,
      'complete': complete,
    };
  }

  @override
  Future<List<dynamic>> getMealRecords(String date) async {
    mealCalls.add(date);
    return const [];
  }

  @override
  Future<List<dynamic>> searchFoods(String keyword, [String? meal]) async =>
      searchResult;

  @override
  Future<Map<String, dynamic>> addFoodRecord(Map<String, dynamic> record) async {
    if (addFails) throw ApiException('添加失败');
    return {'ok': true};
  }

  @override
  Future<Map<String, dynamic>> getProfile() async =>
      {'id': 'u_freq', 'nickname': ''};

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} 未桩');
}
