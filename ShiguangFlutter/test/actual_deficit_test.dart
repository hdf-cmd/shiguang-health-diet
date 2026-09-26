// ShiguangFlutter/test/actual_deficit_test.dart
// M7-T7 actualDeficitProvider 单测：近 6 天历史拉取 + 今日实时并入 + prefs 缓存。
// 行为权威源 js/app.js（行号实读）：
// - fetchDeficitHistory(:1520-1541)：昨起 6 天（i=1..6，**不含今天**）逐日
//   getDailySummary+getExercises 并发；单日失败 `.catch(()=>null/[])` 跳过；
//   无记录日（`!s || !(s.kcal>0)`）不入 rows；rows=[{date,intake:s.kcal,
//   exKcal:该日运动合计}]；cache={date:todayIso(), tdee, history}。
//   tdee=computeMetabolism(state.body, goal.targetWeight).tdee（:1522-1523，
//   profileData 在场时 tw 直取 goal.targetWeight，缺 goal ≙ undefined→当前体重支）。
// - refreshActualDeficit(:1552-1564)：prefs 命中且 cache.date==today → 零历史
//   请求直接用缓存；跨日重拉并写回（≙ saveActualDeficitCache）。
// - computeAvgDeficit(:1543-1550)：今日行仅 `(state.summary&&state.summary.kcal)||0`
//   >0 才并入，exKcal=state.exerciseKcal||0；均值委托 avgDeficitFromRows
//   （<2 天 null，≙ H5 闸），tdee 取 cache.tdee（当日不随档案编辑重算——H5
//   同款staleness，bug-for-bug）。
// - 缓存键 ACTUAL_DEFICIT_PREFIX+（uid||'anon'）（:1511-1512）；uid≙
//   currentUid()=profileData.id||''（:1479）。
// 日期桩：todayProvider override 固定 2026-09-20，历史序列确定性可断。
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shiguang_flutter/data/api_client.dart' show ApiException;
import 'package:shiguang_flutter/domain/deficit.dart' show avgDeficitFromRows;
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider, summaryProvider, todayProvider;
import 'package:shiguang_flutter/features/profile/profile_providers.dart'
    show
        ActualDeficitStore,
        PrefsActualDeficitStore,
        actualDeficitKeyFor,
        actualDeficitProvider,
        actualDeficitStoreProvider;

import 'stubs/stub_health_api.dart';

const today = '2026-09-20';

/// 昨起回退 i 天（≙ app.js:1526 setDate(getDate()-i)，日历日）
String back(int i) => '2026-09-${20 - i}'; // 9 月区间内直减，无跨月

/// body{168,66.66,30,female,moderate,500} + goal tw55 → tdee=2179
/// （与 body_profile_card_test ② 同源：bmr 1406 × 1.55 = 2179）
Map<String, dynamic> testProfile() => <String, dynamic>{
      'id': 'u_test',
      'nickname': '小满',
      'avatarText': '满',
      'avatarData': null,
      'signature': 's',
      'goal': {'dailyKcal': 1679, 'targetWeight': 55, 'waterMl': 1600},
      'body': {
        'heightCm': 168, 'weightKg': 66.66, 'bmi': 23.6, 'age': 30,
        'gender': 'female', 'activity': 'moderate', 'deficit': 500,
      },
      'bodyUpdatedAt': 0,
    };

/// 内存缓存桩（≙ localStorage 语义，键=uid 原样，prefs 键名另有钉⑤专测）
class FakeStore implements ActualDeficitStore {
  final Map<String, Map<String, dynamic>> saved =
      <String, Map<String, dynamic>>{};

  @override
  Future<Map<String, dynamic>?> load(String uid) async => saved[uid];

  @override
  Future<void> save(String uid, Map<String, dynamic> value) async =>
      saved[uid] = value;
}

ProviderContainer make(StubHealthApi api, ActualDeficitStore store) {
  final container = ProviderContainer(
    overrides: [
      healthApiProvider.overrideWithValue(api),
      actualDeficitStoreProvider.overrideWithValue(store),
      todayProvider.overrideWithValue(today),
    ],
    retry: (_, _) => null,
  );
  // riverpod 3 语义：无监听者的 keepAlive AsyncNotifier 在 build 重入时挂起
  // 续体（read(.future) 不算监听，diag 实测 3s 不推进）。生产侧消费点
  // （代谢卡 ConsumerWidget）天然是监听者；测试补一枚常驻监听对齐真实形态。
  container.listen(actualDeficitProvider, (_, _) {});
  addTearDown(container.dispose);
  return container;
}

StubHealthApi apiWith({
  Map<String, Map<String, dynamic>>? summaryByDate,
  Map<String, List<Map<String, dynamic>>>? exercisesByDate,
  Map<String, ApiException>? summaryErrorByDate,
  Map<String, ApiException>? exerciseErrorByDate,
}) =>
    StubHealthApi(
      profile: testProfile(),
      summaryByDate: summaryByDate,
      exercisesByDate: exercisesByDate,
      summaryErrorByDate: summaryErrorByDate,
      exerciseErrorByDate: exerciseErrorByDate,
    );

Future<Map<String, Object>?> read(ProviderContainer c) =>
    c.read(actualDeficitProvider.future);

void main() {
  /* ---------- ① 历史日期序列：昨..-6，不含今天（简报钉①） ---------- */

  test('①6 天双请求日期序列=昨..-6 不含今天；今日仅 watch 侧各 1 次', () async {
    final api = apiWith();
    final c = make(api, FakeStore());
    expect(await read(c), isNull); // 桩默认 summary kcal=0 → rows 空 → null

    final hist = api.summaryDates.where((d) => d != today).toList();
    expect(hist, [back(1), back(2), back(3), back(4), back(5), back(6)]);
    final exHist = api.exerciseDates.where((d) => d != today).toList();
    expect(exHist, [back(1), back(2), back(3), back(4), back(5), back(6)]);
    // 今日各 1 次：summaryProvider(today)/exerciseKcalProvider(today) 实时 watch
    expect(api.summaryDates.where((d) => d == today), hasLength(1));
    expect(api.exerciseDates.where((d) => d == today), hasLength(1));
  });

  /* ---------- ② 单日失败跳过不整体挂（.catch(()=>null/[]) 同款） ---------- */

  test('②d3 summary 失败跳过、d2 exercises 失败按 0：两有效日照常出均值',
      () async {
    final api = apiWith(
      summaryByDate: {
        back(1): StubHealthApi.summaryMap(kcal: 1800),
        back(2): StubHealthApi.summaryMap(kcal: 2000),
        back(3): StubHealthApi.summaryMap(kcal: 1500), // 该日必抛 → 不入 rows
      },
      exercisesByDate: {
        back(1): <Map<String, dynamic>>[{'kcal': 200}],
      },
      summaryErrorByDate: {back(3): ApiException('boom')},
      exerciseErrorByDate: {back(2): ApiException('boom')},
    );
    final v = await read(make(api, FakeStore()));
    // rows=[{1800,200},{2000,0}]，tdee2179 → (579+179)/2=379
    expect(v, {'avgDeficit': 379, 'days': 2, 'tdee': 2179});
  });

  /* ---------- ③ <2 天有效 → null（走预设缺口支） ---------- */

  test('③仅 1 天有记录 → null（≥2 天闸）', () async {
    final api = apiWith(summaryByDate: {
      back(1): StubHealthApi.summaryMap(kcal: 1800),
    });
    expect(await read(make(api, FakeStore())), isNull);
  });

  /* ---------- ④ ≥2 天 → 与 domain/deficit.dart 逐拍相等 ---------- */

  test('④≥2 天：值=avgDeficitFromRows(tdee, history) 域函数直比', () async {
    final api = apiWith(
      summaryByDate: {
        back(1): StubHealthApi.summaryMap(kcal: 1800),
        back(2): StubHealthApi.summaryMap(kcal: 2000),
        back(4): StubHealthApi.summaryMap(kcal: 1900),
      },
      exercisesByDate: {
        back(1): <Map<String, dynamic>>[
          {'kcal': 200},
          {'kcal': 50},
        ], // 该日合计 250（reduce 同构）
      },
    );
    final v = await read(make(api, FakeStore()));
    expect(
        v,
        avgDeficitFromRows(2179, [
          {'intake': 1800, 'exKcal': 250},
          {'intake': 2000, 'exKcal': 0},
          {'intake': 1900, 'exKcal': 0},
        ]));
    expect(v!['days'], 3);
  });

  /* ---------- ⑤ prefs 缓存键逐字 sg_actual_deficit_<uid>（写/命中） ---------- */

  test('⑤a 键名逐字：uid=u_test 写入 sg_actual_deficit_u_test；空 uid 落 anon',
      () async {
    SharedPreferences.setMockInitialValues({});
    final store = PrefsActualDeficitStore();
    expect(actualDeficitKeyFor('u_test'), 'sg_actual_deficit_u_test');
    expect(actualDeficitKeyFor(''), 'sg_actual_deficit_anon'); // ≙ uid||'anon'

    final api = apiWith(summaryByDate: {
      back(1): StubHealthApi.summaryMap(kcal: 1800),
      back(2): StubHealthApi.summaryMap(kcal: 2000),
    });
    final c = make(api, store);
    await read(c);
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('sg_actual_deficit_u_test');
    expect(raw, isNotNull);
    final cache = Map<String, dynamic>.from(jsonDecode(raw!) as Map);
    expect(cache['date'], today);
    expect(cache['tdee'], 2179);
    expect(cache['history'], [
      {'date': back(1), 'intake': 1800, 'exKcal': 0},
      {'date': back(2), 'intake': 2000, 'exKcal': 0},
    ]);
  });

  test('⑤b 当日缓存命中 → 零历史请求；跨日缓存 → 重拉并写回 date=today',
      () async {
    // 命中：seed 一份 date==today 的缓存
    final hit = FakeStore()
      ..saved['u_test'] = {
        'date': today,
        'tdee': 2179,
        'history': [
          {'date': back(1), 'intake': 1800, 'exKcal': 200},
          {'date': back(2), 'intake': 2000, 'exKcal': 0},
        ],
      };
    final api1 = apiWith();
    final v1 = await read(make(api1, hit));
    expect(v1, {'avgDeficit': 379, 'days': 2, 'tdee': 2179});
    // 历史零请求：summary/exercise 只被今日 watch 各打 1 次
    expect(api1.summaryDates, [today]);
    expect(api1.exerciseDates, [today]);

    // 跨日：seed date=昨天 → 重拉 6 天并写回 date=today（≙ cache.date!==today 支）
    final stale = FakeStore()
      ..saved['u_test'] = {
        'date': back(1),
        'tdee': 9999,
        'history': <Object?>[],
      };
    final api2 = apiWith(summaryByDate: {
      back(1): StubHealthApi.summaryMap(kcal: 1800),
      back(2): StubHealthApi.summaryMap(kcal: 2000),
    });
    final v2 = await read(make(api2, stale));
    // rows=[{1800,0},{2000,0}] → (379+179)/2=279；tdee 用新缓存的 2179 非 9999
    expect(v2, {'avgDeficit': 279, 'days': 2, 'tdee': 2179});
    expect(stale.saved['u_test']!['date'], today);
    expect(api2.summaryDates.where((d) => d != today), hasLength(6));
  });

  /* ---------- ⑥ 今日实时行并入（≙ computeAvgDeficit :1543-1550） ---------- */

  test('⑥今日 kcal>0：行 {intake:summary.kcal, exKcal:今日运动合计} 并入均值',
      () async {
    final store = FakeStore()
      ..saved['u_test'] = {
        'date': today, // 命中缓存，历史 rows 由 seed 给
        'tdee': 2179,
        'history': [
          {'date': back(1), 'intake': 1700, 'exKcal': 100},
        ],
      };
    final api = apiWith(
      summaryByDate: {
        today: StubHealthApi.summaryMap(kcal: 1600),
      },
      exercisesByDate: {
        today: <Map<String, dynamic>>[
          {'kcal': 100},
          {'kcal': 50},
        ],
      },
    );
    final v = await read(make(api, store));
    // rows=[{1700,100},{1600,150}] → (579+729)/2=654
    expect(v, {'avgDeficit': 654, 'days': 2, 'tdee': 2179});
  });

  test('⑥b 今日 kcal=0 → 不入行（≙ (state.summary&&…) || 0 闸），仅 1 天 → null',
      () async {
    final store = FakeStore()
      ..saved['u_test'] = {
        'date': today,
        'tdee': 2179,
        'history': [
          {'date': back(1), 'intake': 1700, 'exKcal': 100},
        ],
      };
    final api = apiWith(exercisesByDate: {
      today: <Map<String, dynamic>>[
        {'kcal': 100},
      ], // 有运动没进食 → H5 仍不入行
    });
    expect(await read(make(api, store)), isNull);
  });

  test('⑥c 今日实时值变化（记录链 invalidate summary）→ 均值跟随重算',
      () async {
    final store = FakeStore()
      ..saved['u_test'] = {
        'date': today,
        'tdee': 2179,
        'history': [
          {'date': back(1), 'intake': 1700, 'exKcal': 100},
        ],
      };
    final api = apiWith(summaryByDate: {
      today: StubHealthApi.summaryMap(kcal: 1600),
    });
    final c = make(api, store);
    // rows=[{1700,100},{1600,0}] → (579+579)/2=579
    expect(await read(c), {'avgDeficit': 579, 'days': 2, 'tdee': 2179});
    // 记一笔后今日 summary 变化（≙ renderRing:344 recompute 触发面：
    // 记录链 invalidate summaryProvider → 本 provider watch 重跑）
    api.summaryByDate![today] = StubHealthApi.summaryMap(kcal: 1000);
    c.invalidate(summaryProvider(c.read(todayProvider)));
    // rows=[{1700,100},{1000,0}] → (579+1179)/2=879
    expect(await read(c), {'avgDeficit': 879, 'days': 2, 'tdee': 2179});
    // 缓存 date==today → 全程零历史重拉（重算只走缓存+实时值，轻量）
    expect(api.summaryDates.where((d) => d != today), isEmpty);
    expect(api.exerciseDates.where((d) => d != today), isEmpty);
  });
}
