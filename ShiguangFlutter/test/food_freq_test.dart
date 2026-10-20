// ShiguangFlutter/test/food_freq_test.dart
// 「常吃排序」单测：纯排序/历史聚合/初始化流程/记一笔续算。
// 需求（老大 2026-09-25 拍板方案 B）：近 30 天云端记录初始化频次 + App 内
// 每记一笔 +1；食物列表按频次稳定降序（常吃在前，同频次/无频次保持云端原序）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiguang_flutter/data/api_client.dart';
import 'package:shiguang_flutter/data/health_api.dart';
import 'package:shiguang_flutter/domain/dates.dart';
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

  group('aggregateFreqFromRecords', () {
    test('跨日按菜名累计（H5 记的历史同名合并）', () {
      final byDate = {
        '2026-09-24': [
          {'name': '米饭', 'kcal': 230},
          {'name': '鸡蛋', 'kcal': 78},
        ],
        '2026-09-25': [
          {'name': '米饭', 'kcal': 230},
          {'name': '牛奶', 'kcal': 175},
        ],
      };
      expect(aggregateFreqFromRecords(byDate), {'米饭': 2, '鸡蛋': 1, '牛奶': 1});
    });

    test('无名/空名记录不计入', () {
      final byDate = {
        '2026-09-25': [
          {'name': ''},
          {'kcal': 10},
          {'name': '鸡胸'},
        ],
      };
      expect(aggregateFreqFromRecords(byDate), {'鸡胸': 1});
    });
  });

  group('recentIsoDates', () {
    test('含今天往前 N 天，逐日 ISO（本地日）', () {
      final dates = recentIsoDates(DateTime(2026, 9, 25, 12), 3);
      expect(dates, ['2026-09-25', '2026-09-24', '2026-09-23']);
    });
  });

  /* ---------- M7-T8（T4 池）：prefs 键分账号，旧全局键读到即删不迁移 ---------- */

  group('PrefsFoodFreqStore 分账号键', () {
    test('旧全局键（counts/init）读到即删；新键 sg_food_freq_counts_<uid> 读写，账号间不互读',
        () async {
      SharedPreferences.setMockInitialValues({
        'sg_food_freq_counts': '{"旧菜":3}',
        'sg_food_freq_init_v1': true,
      });
      final store = PrefsFoodFreqStore();
      // 旧键内容不迁移（ensureLoaded 30 天回填可重建，迁移属 YAGNI）：
      // 新 uid 档初读必为「未初始化 + 空计数」
      expect(await store.isInitialized('u1'), isFalse);
      expect(await store.loadCounts('u1'), isEmpty);
      var p = await SharedPreferences.getInstance();
      expect(p.containsKey('sg_food_freq_counts'), isFalse); // 旧 counts 键已删
      expect(p.containsKey('sg_food_freq_init_v1'), isFalse); // 旧 init 键已删
      await store.saveCounts('u1', {'米饭': 2});
      await store.markInitialized('u1');
      p = await SharedPreferences.getInstance();
      expect(p.getString('sg_food_freq_counts_u1'), '{"米饭":2}');
      expect(p.getBool('sg_food_freq_init_v1_u1'), isTrue);
      expect(await store.loadCounts('u2'), isEmpty); // 他账号不互读
      expect(await store.isInitialized('u2'), isFalse);
    });

    test('端到端 ensureLoaded：uid 由 profile id 解析，落新键逐字（anon 档兜底面另测）',
        () async {
      SharedPreferences.setMockInitialValues({});
      final api = _RecordsByDate(records: [
        {'name': '米饭'}
      ]);
      final c = ProviderContainer(overrides: [
        foodFreqStoreProvider.overrideWithValue(PrefsFoodFreqStore()),
        healthApiProvider.overrideWithValue(api),
        todayProvider.overrideWithValue(localIso(DateTime(2026, 9, 25, 12))),
      ]);
      addTearDown(c.dispose);
      await c.read(foodFreqProvider.notifier).ensureLoaded();
      final p = await SharedPreferences.getInstance();
      // _RecordsByDate.getProfile().id='u_freq' ≙ profile['id'] 解析链
      expect(p.getString('sg_food_freq_counts_u_freq'), contains('米饭'));
      expect(p.getBool('sg_food_freq_init_v1_u_freq'), isTrue);
    });
  });

  group('FoodFreqNotifier.ensureLoaded（首次初始化，方案 B）', () {
    test('未初始化：拉满 30 天记录聚合落盘并打标记，计数进 state', () async {
      final store = _MemoryStore();
      final api = _RecordsByDate(
        records: [
          {'name': '米饭'},
          {'name': '鸡蛋'}
        ],
      );
      final c = _container(store: store, api: api);
      await c.read(foodFreqProvider.notifier).ensureLoaded();
      expect(c.read(foodFreqProvider), {'米饭': 30, '鸡蛋': 30});
      expect(await store.isInitialized('u_freq'), isTrue);
      expect(await store.loadCounts('u_freq'), {'米饭': 30, '鸡蛋': 30});
      expect(api.datesFetched.length, 30);
    });

    test('已初始化：不再发任何网络请求，直接回放落盘计数', () async {
      final store = _MemoryStore(
          initialized: true, counts: {'牛奶': 7});
      final api = _RecordsByDate(records: [
        {'name': '米饭'}
      ]);
      final c = _container(store: store, api: api);
      await c.read(foodFreqProvider.notifier).ensureLoaded();
      expect(c.read(foodFreqProvider), {'牛奶': 7});
      expect(api.datesFetched, isEmpty);
    });

    test('部分日期失败：成功日聚合可用**并照常打标记**（M11-T5 裁决改钉）', () async {
      // 旧钉（M7 时代）要求 failures==0 才落标记，后果是弱网下标记永不落盘
      // → 每次冷启动重放 30 请求（老大 10-19 反馈「每次都慢」的直接机制）。
      // M11-T5 裁决：有任一日聚合成功即标记；差异登记＝个别失败日不计入频次
      // （只影响排序，不影响任何数据正确性面）。
      final store = _MemoryStore();
      final api = _RecordsByDate(
        records: [
          {'name': '鸡胸'}
        ],
        failDates: {'2026-09-25'}, // 今天失败（30 天窗口首日）
      );
      final c = _container(store: store, api: api, now: DateTime(2026, 9, 25, 12));
      await c.read(foodFreqProvider.notifier).ensureLoaded();
      expect(c.read(foodFreqProvider), {'鸡胸': 29});
      expect(await store.isInitialized('u_freq'), isTrue);

      // 标记落盘即根治「每次冷启重放」：换一个 Notifier（≙ 冷启动重开弹层）
      // 且用**全新 api 桩**——二次开层必须一条记录请求都不发，直接回放 29 次。
      final api2 = _RecordsByDate(records: const []);
      final c2 = _container(store: store, api: api2);
      await c2.read(foodFreqProvider.notifier).ensureLoaded();
      expect(c2.read(foodFreqProvider), {'鸡胸': 29});
      expect(api2.datesFetched, isEmpty);
      expect(api.datesFetched.length, 30); // 首跑逐日发起（含失败那天）
    });

    test('回填并发峰值受限（≤6 且确为并发，不退回串行）', () async {
      final store = _MemoryStore();
      final api = _RecordsByDate(records: [
        {'name': '米饭'}
      ]);
      final c = _container(store: store, api: api);
      await c.read(foodFreqProvider.notifier).ensureLoaded();
      expect(api.datesFetched.length, 30); // 窗口未被限流吞掉
      expect(api.peak, lessThanOrEqualTo(kFreqInitConcurrency));
      expect(api.peak, greaterThan(1)); // 反「串行化」伪绿：峰值必须 >1
    });

    test('全部失败：state 保持空（列表原序），不落标记且允许本会话重试', () async {
      final store = _MemoryStore();
      final api = _RecordsByDate(
        records: [
          {'name': '米饭'}
        ],
        failAll: true,
      );
      final c = _container(store: store, api: api);
      await c.read(foodFreqProvider.notifier).ensureLoaded();
      expect(c.read(foodFreqProvider), isEmpty);
      expect(await store.isInitialized('u_freq'), isFalse);
      // 下次开弹层可再试（_started 已复位）
      api.failAll = false;
      await c.read(foodFreqProvider.notifier).ensureLoaded();
      expect(c.read(foodFreqProvider), {'米饭': 30});
    });
  });

  group('记一笔续算 + 搜索排序接线', () {
    test('addRecord 成功 → 同名 +1 并落盘；失败不计数', () async {
      final store = _MemoryStore(initialized: true, counts: {'米饭': 2});
      final api = _RecordsByDate(records: const []);
      final c = _container(store: store, api: api);
      await c.read(foodFreqProvider.notifier).ensureLoaded(); // 回放 {'米饭':2}
      await c.read(recordControllerProvider).addRecord(
          '2026-09-25', {'name': '米饭', 'kcal': 230}, pendingKey: 'r1');
      expect(c.read(foodFreqProvider), {'米饭': 3});
      expect(await store.loadCounts('u_freq'), {'米饭': 3});
    });

    test('addRecord 失败 → 计数不变', () async {
      final store = _MemoryStore(initialized: true, counts: {'米饭': 2});
      final api = _RecordsByDate(records: const [])..addFails = true;
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
      final api = _RecordsByDate(records: const [])
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

    testWidgets('端到端：开弹层触发历史初始化，常吃（云端近30天）置顶渲染', (tester) async {
      final store = _MemoryStore(); // 未初始化 → 弹层应触发 30 天拉取
      final api = _RecordsByDate(
        records: [
          {'name': '米饭'}
        ],
      )
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
      await tester.pumpAndSettle(); // postFrame ensureLoaded → 30 日聚合 → 自动重排
      expect(await store.isInitialized('u_freq'), isTrue);
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
  required _RecordsByDate api,
  DateTime? now,
}) {
  final c = ProviderContainer(overrides: [
    foodFreqStoreProvider.overrideWithValue(store),
    healthApiProvider.overrideWithValue(api),
    if (now != null) todayProvider.overrideWithValue(localIso(now)),
  ]);
  addTearDown(c.dispose);
  return c;
}

class _MemoryStore implements FoodFreqStore {
  _MemoryStore({this.initialized = false, this._counts});
  bool initialized;
  Map<String, int>? _counts;
  // M7-T8 分账号键：桩不分桶（uid 形参收下即符合接口），账号隔离语义由
  // 下方 PrefsFoodFreqStore 真桩用例钉。
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

/// 日期敏感的 HealthApi 桩：getMealRecords 按日返回（可指定失败日），
/// searchFoods 返回可编程列表；其余成员 noSuchMethod 兜底（同 StubHealthApi 套路）。
class _RecordsByDate implements HealthApi {
  _RecordsByDate({required this.records, this.failDates = const {}, this.failAll = false});
  final List<Map<String, dynamic>> records;
  final Set<String> failDates;
  bool failAll;
  final List<String> datesFetched = [];
  List<Map<String, dynamic>> searchResult = const [];
  bool addFails = false;

  /// 并发探针：getMealRecords 内挂 1ms 真实让出，记录同时在途峰值。
  /// 限流实现若退化成串行，peak==1 即被「峰值>1」钉抓出；限流失效，
  /// peak==30 被「≤kFreqInitConcurrency」钉抓出。
  int active = 0;
  int peak = 0;

  @override
  Future<List<dynamic>> getMealRecords(String date) async {
    datesFetched.add(date);
    active++;
    if (active > peak) peak = active;
    await Future<void>.delayed(const Duration(milliseconds: 1));
    active--;
    if (failAll || failDates.contains(date)) {
      throw ApiException('网络异常');
    }
    return records;
  }

  @override
  Future<List<dynamic>> searchFoods(String keyword, [String? meal]) async =>
      searchResult;

  @override
  Future<Map<String, dynamic>> addFoodRecord(Map<String, dynamic> record) async {
    if (addFails) throw ApiException('添加失败');
    return {'ok': true};
  }

  /// M7-T8 分账号键：FoodFreqNotifier._resolveUid 读 profile['id']（此桩给
  /// 稳定 uid；缺该方法时 noSuchMethod 抛错走 anon 兜底支，两用例档都覆盖）
  @override
  Future<Map<String, dynamic>> getProfile() async =>
      {'id': 'u_freq', 'nickname': ''};

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('${invocation.memberName} 未桩');
}
