// ShiguangFlutter/test/food_eaten_count_test.dart
// M12-④：食物库显示「吃过 N 次」。三处行尾徽标共用同一份全史计数
// （foodFreqProvider）：我的食物库·自定义 / 我的食物库·内置 / 记一笔搜索。
// 徽标只在 >0 时出现（0 次是噪声：内置库几百道菜全挂「吃过 0 次」没意义）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/theme.dart' show shiguangTheme;
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider;
import 'package:shiguang_flutter/features/profile/food_lib_sheet.dart';
import 'package:shiguang_flutter/features/record/food_freq.dart';
import 'package:shiguang_flutter/features/record/search_sheet.dart';

import 'harness.dart';
import 'stubs/stub_health_api.dart';

void main() {
  testWidgets('我的食物库·自定义：开层即拉一次频次，「米饭」显示吃过 12 次',
      (tester) async {
    final api = StubHealthApi(
      libCustomFoods: [
        {'id': 'c1', 'name': '米饭', 'kcal': 230, 'grams': 200},
        {'id': 'c2', 'name': '新菜', 'kcal': 100},
      ],
      libBuiltins: const [],
    )..foodFreqCounts = {'米饭': 12};
    final store = _MemStore();

    await _pumpLib(tester, api, store);

    expect(api.foodFreqCalls, 1, reason: '开层拉全史计数只发一次');
    expect(find.text('吃过 12 次'), findsOneWidget);
    // 0 次的菜不挂徽标（无「吃过 0 次」）
    expect(find.textContaining('吃过 0 次'), findsNothing);
  });

  testWidgets('我的食物库·内置 tab：同一份计数，切 tab 不重复请求', (tester) async {
    final api = StubHealthApi(
      libCustomFoods: const [],
      libBuiltins: [
        {'id': 'b1', 'name': '纯牛奶', 'meta': '奶类 · 1 盒 250ml', 'kcal': 175, 'hidden': false},
        {'id': 'b2', 'name': '白米饭', 'meta': '主食 · 200g', 'kcal': 230, 'hidden': false},
      ],
    )..foodFreqCounts = {'纯牛奶': 3};
    final store = _MemStore();

    await _pumpLib(tester, api, store);
    await tester.tap(find.byKey(libSegKey('builtin')));
    await tester.pumpAndSettle();

    expect(find.text('吃过 3 次'), findsOneWidget);
    expect(find.textContaining('吃过 0 次'), findsNothing);
    expect(api.foodFreqCalls, 1, reason: '切 tab 复用已落盘的计数，不再请求');
  });

  testWidgets('记一笔搜索：结果行带吃过次数', (tester) async {
    final api = StubHealthApi(foods: [
      {'id': 'f1', 'name': '鸡蛋', 'meta': '蛋类 · 1 个约 50g', 'kcal': 78, 'emoji': '🥚'},
      {'id': 'f2', 'name': '西瓜', 'meta': '水果 · 100g', 'kcal': 30, 'emoji': '🍉'},
    ])..foodFreqCounts = {'鸡蛋': 2};
    final store = _MemStore();

    await tester.pumpWidget(ProviderScope(
      overrides: [
        healthApiProvider.overrideWithValue(api),
        foodFreqStoreProvider.overrideWithValue(store),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SearchSheet(date: '2026-09-25', meal: 'lunch')),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('吃过 2 次'), findsOneWidget);
    expect(find.textContaining('吃过 0 次'), findsNothing);
  });

  testWidgets('搜索行：次数在 meta 之前且只渲染一行 meta（真机曾双行+次数被省略号吃掉）',
      (tester) async {
    final api = StubHealthApi(foods: [
      {
        'id': 'f1',
        'name': '纯牛奶',
        'meta': '奶类 · 1 盒 250ml',
        'kcal': 175,
        'emoji': '🥛',
      },
    ])..foodFreqCounts = {'纯牛奶': 42};

    await tester.pumpWidget(ProviderScope(
      overrides: [
        healthApiProvider.overrideWithValue(api),
        foodFreqStoreProvider.overrideWithValue(_MemStore()),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SearchSheet(date: '2026-09-25', meal: 'lunch')),
      ),
    ));
    await tester.pumpAndSettle();

    // 只有一行 meta（曾因漏删旧 Text 渲染成两行）
    expect(find.textContaining('奶类'), findsOneWidget);
    // 次数必须在行首：跟在 meta 后面会被窄列省略号吃掉（真机只见「吃过…」）
    final metaText =
        tester.widgetList<Text>(find.textContaining('奶类')).single.data!;
    expect(metaText.startsWith('吃过 42 次'), isTrue,
        reason: '实际渲染：$metaText');
  });

  testWidgets('窄屏 + 超长菜名：次数并入 meta 单行后不溢出（320dp 压力档）',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    final api = StubHealthApi(foods: [
      {
        'id': 'f1',
        'name': '超级无敌豪华双拼鸡胸肉盖饭加蛋加肠',
        'meta': '主食 · 超大份 500g',
        'kcal': 888,
        'emoji': '🍱',
      },
    ])..foodFreqCounts = {'超级无敌豪华双拼鸡胸肉盖饭加蛋加肠': 128};

    await tester.pumpWidget(ProviderScope(
      overrides: [
        healthApiProvider.overrideWithValue(api),
        foodFreqStoreProvider.overrideWithValue(_MemStore()),
      ],
      child: const MaterialApp(
        home: Scaffold(body: SearchSheet(date: '2026-09-25', meal: 'lunch')),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('吃过 128 次'), findsOneWidget);
    expect(tester.takeException(), isNull, reason: '搜索行不得 RenderFlex overflow');
  });
}

// ─── 地基 ──────────────────────────────────────────────────

class _MemStore implements FoodFreqStore {
  bool initialized = false;
  Map<String, int>? counts;
  int initQueries = 0;

  @override
  Future<bool> isInitialized(String uid) async {
    initQueries++;
    return initialized;
  }

  @override
  Future<void> markInitialized(String uid) async => initialized = true;

  @override
  Future<Map<String, int>> loadCounts(String uid) async => counts ?? {};

  @override
  Future<void> saveCounts(String uid, Map<String, int> next) async =>
      counts = Map.of(next);
}

class _Host extends ConsumerStatefulWidget {
  const _Host();

  @override
  ConsumerState<_Host> createState() => _HostState();
}

class _HostState extends ConsumerState<_Host> {
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => openFoodLibSheet(context, ref),
            child: const Text('open-lib'),
          ),
        ),
      );
}

Future<void> _pumpLib(
    WidgetTester tester, StubHealthApi api, _MemStore store) async {
  await useBigSurface(tester);
  final container = ProviderContainer(
    overrides: [
      healthApiProvider.overrideWithValue(api),
      foodFreqStoreProvider.overrideWithValue(store),
    ],
    retry: (_, _) => null,
  );
  addTearDown(container.dispose);
  await tester.pumpWidget(UncontrolledProviderScope(
    container: container,
    child: MaterialApp(theme: shiguangTheme(), home: const _Host()),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open-lib'));
  await tester.pumpAndSettle();
}
