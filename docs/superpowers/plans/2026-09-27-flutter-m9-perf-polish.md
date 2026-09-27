# M9 性能 SWR 缓存 + Flutter 质感批 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 消灭「每次重开白屏 400ms」的慢感（会话级 SWR：先显缓存、后台刷新），并以五个 Flutter 原生质感组件（按压回弹/错峰入场/环插值/弹层 handle/toast 曲线）完成 v2.7.0 升级。

**Architecture:** 新增 `lib/data/swr_cache.dart` 会话级内存缓存，summary/records 由 FutureProvider 转 AsyncNotifier.family 播种模式、exercises/weightTrend 在既有 Notifier 内接缓存；写路径在既有 invalidate 点同步 remove 缓存键。质感组件全部落 `lib/features/common/`，业务侧只做包裹不改数据语义。

**Tech Stack:** Flutter 3.47.5 / Dart 3.13.4 / Riverpod 3.4.3（Notifier 类形态，坑表见 spec 与本计划各任务注）

**Spec:** `docs/superpowers/specs/2026-09-27-flutter-m9-perf-polish-design.md`

## Global Constraints

- 数据行为 bug-for-bug 对齐 H5（R4 铁律）；**呈现时序**分叉仅限 spec §1 已批的 SWR 播种面。
- 静态分析只准 `dart analyze lib test`（flutter analyze 中文路径崩）；测试 `flutter test` 输出重定向文件判 exit code，禁管道吞码。
- 每条 Bash 前置：`export PATH="$PATH:/c/flutter/bin"; export PUB_HOSTED_URL=https://pub.flutter-io.cn; export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`。
- widget 测试必挂 `shiguangTheme()`；3.47 起 flutter_test 不导出 material，测试文件显式 import。
- release 构建只走 ASCII 沙盒 `C:\sg-rel-build`；版本 `2.7.0+20700`（build=major*10000+minor*100+patch）。
- 文案逐字面不动（本批零文案改动，B4 收口不得改标题文本）；新组件注释标 ≙ 出处或 R4 自主位。
- 缓存仅会话级内存；**不落磁盘、不缓存搜索、不动云函数**（spec §5 不做清单）。

## 文件结构（本批创建/修改）

| 文件 | 责任 |
|---|---|
| 创建 `lib/data/swr_cache.dart` | SwrCache 键值层 + swrCacheProvider + remove 辅助 |
| 创建 `lib/features/common/skeleton.dart` | SkeletonBar 公共骨架条 |
| 创建 `lib/features/common/pressable.dart` | PressableScale 按压反馈 |
| 创建 `lib/features/common/stagger.dart` | Stagger 错峰入场（只播一次） |
| 创建 `lib/features/common/sheet.dart` | showShiguangSheet 弹层样板收口（handle+标题+✕） |
| 改 `lib/features/home/home_controller.dart` | summary/records → SwrNotifier |
| 改 `lib/features/exercise/exercise_controller.dart` | exercises 播种 + _reload 失败 remove |
| 改 `lib/features/report/report_controller.dart` | weightTrend 播种 |
| 改 `lib/app/auth_state.dart` | 换号波次清 SwrCache |
| 改 `lib/features/record/record_controller.dart` `record_screen.dart` `home_screen.dart` `weight_log_card.dart` `report_screen.dart` `body_profile_card.dart` | 既有 invalidate 点补 remove 键 |
| 改 `lib/features/profile/food_lib_sheet.dart` | 会话缓存+并行预取+骨架 |
| 改 `lib/features/home/plate_ring.dart` | 中心数从上一值插值 |
| 改 `lib/app/theme.dart` | toast 进出场曲线 |
| 改 10 处 showModalBottomSheet 宿主 | B4 收口（Task 8） |

---

### Task 1: SwrCache 地基（键值层+provider+单测）

**Files:**
- Create: `ShiguangFlutter/lib/data/swr_cache.dart`
- Test: `ShiguangFlutter/test/swr_cache_test.dart`

**Interfaces:**
- Consumes: 无（纯新文件）
- Produces: `SwrCache`（read/write/invalidate/invalidatePrefix/clear）、`swrCacheProvider = Provider<SwrCache>`、顶层辅助 `void swrInvalidate(Ref ref, String key)`（remove 键，供写路径调用，Task 2-4 消费）

- [ ] **Step 1: 写失败单测**

```dart
// ShiguangFlutter/test/swr_cache_test.dart
// M9-A1：SwrCache 会话级键值层单测（纯 Dart，无 Flutter 依赖）。
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/data/swr_cache.dart';

void main() {
  test('write/read 类型命中；异型读视为 miss', () {
    final c = SwrCache();
    c.write('k', 42);
    expect(c.read<int>('k'), 42);
    expect(c.read<String>('k'), isNull); // 类型不符=miss，不 ClassCast
    expect(c.read<int>('nope'), isNull);
  });
  test('invalidate 单键；invalidatePrefix 收族；clear 全清', () {
    final c = SwrCache()
      ..write('summary.2026-09-27', 1)
      ..write('summary.2026-09-26', 2)
      ..write('records.2026-09-27', 3);
    c.invalidate('records.2026-09-27');
    expect(c.read<int>('records.2026-09-27'), isNull);
    c.invalidatePrefix('summary.');
    expect(c.read<int>('summary.2026-09-27'), isNull);
    c.write('a', 1);
    c.clear();
    expect(c.read<int>('a'), isNull);
  });
}
```

- [ ] **Step 2: 跑测确认失败**

Run: `flutter test test/swr_cache_test.dart > ../.mimosa/m9-t1-red.log 2>&1; echo exit=$?`
Expected: exit≠0，`swr_cache.dart` 不存在编译失败。

- [ ] **Step 3: 实现**

```dart
// ShiguangFlutter/lib/data/swr_cache.dart
// M9-A1（spec §1）：会话级 SWR 内存缓存。生命周期=ProviderContainer=一次启动
// 进程；不做磁盘持久化（spec §5 YAGNI——跨启动新鲜度优先，重开 App 重拉一次
// 400ms 属可接受地板）。换号/登出经 auth_state 波次 clear() 全清。
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SwrCache {
  final Map<String, Object?> _store = <String, Object?>{};

  /// 类型命中才返回——异型键视为 miss（防键冲突时 ClassCastException）。
  T? read<T>(String key) {
    final v = _store[key];
    return v is T ? v : null;
  }

  void write(String key, Object? value) => _store[key] = value;
  void invalidate(String key) => _store.remove(key);
  void invalidatePrefix(String prefix) =>
      _store.removeWhere((k, _) => k.startsWith(prefix));
  void clear() => _store.clear();
}

final swrCacheProvider = Provider<SwrCache>((ref) => SwrCache());

/// 写路径统一辅助：在既有 ref.invalidate(provider) 旁并排调用——
/// provider 重建播种时不再吃到写前旧数（spec §1 规则：读播种、写删键）。
void swrInvalidate(Ref ref, String key) =>
    ref.read(swrCacheProvider).invalidate(key);
```

- [ ] **Step 4: 跑测确认通过**

Run: `flutter test test/swr_cache_test.dart > ../.mimosa/m9-t1-green.log 2>&1; echo exit=$?` → exit=0

- [ ] **Step 5: 门禁+提交**

`dart analyze lib test` → No issues found；
`git add ShiguangFlutter/lib/data/swr_cache.dart ShiguangFlutter/test/swr_cache_test.dart && git commit -m "feat: M9-T1 SwrCache 会话级键值层（类型命中读/前缀失效/换号全清钩子，spec §1）"`

---

### Task 2: summary/records SWR 化（FutureProvider→SwrNotifier.family）

**Files:**
- Modify: `ShiguangFlutter/lib/features/home/home_controller.dart:26-44`（summaryProvider/recordsProvider 定义）
- Modify: `ShiguangFlutter/lib/features/record/record_controller.dart:93-94`、`record_screen.dart:269`、`home_screen.dart:168`、`body_profile_card.dart:134`（写/重试路径补删键）
- Test: `ShiguangFlutter/test/swr_summary_test.dart`（新）；既有 `home_screen_test.dart`/`record_flow_test.dart` 回归

**Interfaces:**
- Consumes: Task 1 `SwrCache`/`swrCacheProvider`/`swrInvalidate`
- Produces: `summaryProvider`/`recordsProvider` 对外签名不变（`AsyncValue<Summary>`/`AsyncValue<List<Map<String,dynamic>>>`，family String date，autoDispose）；新公共基类 `SwrFamilyNotifier<T, Arg>`（Task 3 复用）

- [ ] **Step 1: 写失败测试**

```dart
// ShiguangFlutter/test/swr_summary_test.dart
// M9-A1：summary SWR 语义三面钉——①首访 loading→data 且回写缓存；
// ②重开先 data(旧缓存) 后台刷新到 data(新)；③失败有缓存不炸 error。
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
    final api = StubHealthApi(
        summary: StubHealthApi.summaryMap(target: 1679), summaryGate: null);
    final c = await boot(tester, api);
    await tester.pump(); // 首帧：未回包
    expect(find.byKey(const ValueKey('plate-ring-skeleton')), findsOneWidget);
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
    c.read(swrCacheProvider).write('summary.$date2',
        c.read(swrCacheProvider).read<Object>('summary.$date2')); // 保旧
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
```

- [ ] **Step 2: 跑测确认失败**（②③红：现 provider 无播种/失败即 error）

Run: `flutter test test/swr_summary_test.dart > ../.mimosa/m9-t2-red.log 2>&1; echo exit=$?`

- [ ] **Step 3: 实现 SwrFamilyNotifier + 转换两 provider**

`home_controller.dart` 中 summaryProvider/recordsProvider 定义替换为：

```dart
/// M9-A1（spec §1）：SWR 播种基类——build 命中缓存时**同步**先置
/// AsyncData(cached)（首帧即有数据，白屏 400ms→0ms），继续 await 网络，
/// 成功覆盖+回写、失败保旧静默（呈现时序分叉=老大 09-27 知情批准）。
/// Riverpod 3.4.3 坑沿用：family 用构造参 N.new；build 内 watch 全前置。
abstract class SwrFamilyNotifier<T extends Object, Arg>
    extends FamilyAsyncNotifier<T, Arg> {
  String cacheKey(Arg arg);
  Future<T> fetch(Arg arg);

  @override
  Future<T> build(Arg arg) async {
    final cache = ref.read(swrCacheProvider);
    final key = cacheKey(arg);
    final cached = cache.read<T>(key);
    if (cached == null) {
      final fresh = await fetch(arg); // 首访：现行 loading→data
      cache.write(key, fresh);
      return fresh;
    }
    state = AsyncData<T>(cached); // 播种（build 返回值稍后覆盖，无竞态）
    try {
      final fresh = await fetch(arg);
      cache.write(key, fresh);
      return fresh;
    } catch (_) {
      return cached; // 失败有缓存：静默保旧（spec §1 差异登记）
    }
  }
}

final summaryProvider = AsyncNotifierProvider.autoDispose
    .family<SummaryNotifier, Summary, String>(SummaryNotifier.new);

class SummaryNotifier extends SwrFamilyNotifier<Summary, String> {
  @override
  String cacheKey(String date) => 'summary.$date';
  @override
  Future<Summary> fetch(String date) async {
    final m = await ref.watch(healthApiProvider).getDailySummary(date);
    return Summary.fromMap(m);
  }
}

final recordsProvider = AsyncNotifierProvider.autoDispose
    .family<RecordsNotifier, List<Map<String, dynamic>>, String>(
        RecordsNotifier.new);

class RecordsNotifier extends SwrFamilyNotifier<List<Map<String, dynamic>>, String> {
  @override
  String cacheKey(String date) => 'records.$date';
  @override
  Future<List<Map<String, dynamic>>> fetch(String date) async {
    final list = await ref.watch(healthApiProvider).getMealRecords(date);
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(growable: false);
  }
}
```

（`Summary.fromMap`/行映射按现文件 :26-44 原样搬入 fetch——映射逻辑零改动，只换壳。若原实现有私有辅助函数保持原位可被 fetch 调用。）

- [ ] **Step 4: 写路径删键（读播种、写删键）**

`record_controller.dart:93-94`（addRecord/deleteRecord 成功链）改为：

```dart
    swrInvalidate(_ref, 'records.$date'); // M9：写后删键，防回访播种写前旧数
    swrInvalidate(_ref, 'summary.$date');
    _ref.invalidate(recordsProvider(date));
    _ref.invalidate(summaryProvider(date));
```

`record_screen.dart:269` 与 `home_screen.dart:168`（error 重试钮）：invalidate 前各加一行 `swrInvalidate(ref, 'records.$date');` / `swrInvalidate(ref, 'summary.$date');`（重试必须绕开旧缓存——虽然失败有缓存时不炸 error 卡，重试语义=强制网络）。
`body_profile_card.dart:134`（setGoal 后整族失效）：`ref.read(swrCacheProvider).invalidatePrefix('summary.');` 后再 `ref.invalidate(summaryProvider);`。

- [ ] **Step 5: 全量回归**

Run: `flutter test > ../.mimosa/m9-t2-full.log 2>&1; echo exit=$?`
Expected: 全绿。**重点**：home_screen_test error 态用例——桩无缓存首访失败仍走 error 卡（③只护有缓存面），若红按「首访失败=error、回访失败=静默」口径核对实现而非弱化断言。

- [ ] **Step 6: 提交**

`git commit -m "feat: M9-T2 summary/records SWR 播种（SwrFamilyNotifier 基类+写路径删键，白屏400ms→0ms，spec §1 失效矩阵行1-2）"`

---

### Task 3: exercises/weightTrend SWR + 换号全清

**Files:**
- Modify: `ShiguangFlutter/lib/features/exercise/exercise_controller.dart:55-80`（_reload/build 播种）
- Modify: `ShiguangFlutter/lib/features/report/report_controller.dart:38-50`（weightTrendProvider）
- Modify: `ShiguangFlutter/lib/app/auth_state.dart:60-90`（失效波次）
- Test: `ShiguangFlutter/test/swr_exercises_test.dart`（新）+ `account_switch_cache_test.dart` 补面

**Interfaces:**
- Consumes: Task 2 `SwrFamilyNotifier`（home_controller.dart 导出）
- Produces: `exercisesProvider`/`weightTrendProvider` 对外签名不变；auth 波次新增 `swrCacheProvider` 清理步骤

- [ ] **Step 1: 失败测试**

```dart
// ShiguangFlutter/test/swr_exercises_test.dart
// M9-A1：①exercises 重开播种（缓存先显+后台刷新）；②_reload 失败清键
// （防「降级空列表」被缓存成旧真值的脏源）；③weightTrend 播种。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/theme.dart' show shiguangTheme;
import 'package:shiguang_flutter/data/swr_cache.dart';
import 'package:shiguang_flutter/features/exercise/exercise_controller.dart';
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider;
import 'package:shiguang_flutter/features/report/report_controller.dart'
    show weightTrendProvider;

import 'stubs/stub_health_api.dart';

void main() {
  final date = DateTime.now().toIso8601String().substring(0, 10);

  test('②exercises 首取回写缓存；失败降级清键不存脏', () async {
    final api = StubHealthApi(exercises: [StubHealthApi.exerciseMap(id: 'e1', name: '跑步', kcal: 300)]);
    final c = ProviderContainer(
      overrides: [healthApiProvider.overrideWithValue(api)],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    await c.read(exercisesProvider(date).future);
    expect(c.read(swrCacheProvider).read<Object>('exercises.$date'), isNotNull);

    final api2 = StubHealthApi(exercisesError: Exception('boom'));
    final c2 = ProviderContainer(
      overrides: [healthApiProvider.overrideWithValue(api2)],
      retry: (_, _) => null,
    );
    addTearDown(c2.dispose);
    await c2.read(exercisesProvider(date).future); // 降级空列表不抛（H5 :1732 口径）
    expect(c2.read(swrCacheProvider).read<Object>('exercises.$date'), isNull); // 空降级不写缓存
  });

  test('③weightTrend 首访回写、失败有缓存保旧', () async {
    final api = StubHealthApi(weightTrend: StubHealthApi.trendMap());
    final c = ProviderContainer(
      overrides: [healthApiProvider.overrideWithValue(api)],
      retry: (_, _) => null,
    );
    addTearDown(c.dispose);
    final t = await c.read(weightTrendProvider.future);
    expect(c.read(swrCacheProvider).read<Object>('weightTrend'), isNotNull);
    expect(t.points, isNotEmpty);
  });
}
```

（`StubHealthApi.exerciseMap/trendMap/exercisesError` 若无现成构造器，按 stub 文件既有工厂样式补——fixture 形状对齐 contract。）

- [ ] **Step 2: 跑测确认失败**

- [ ] **Step 3: exercises 播种（ExercisesNotifier 内改，保留乐观 temp 全链）**

`exercise_controller.dart` build 头部（现 :50-57 区域）：

```dart
  @override
  Future<List<Map<String, dynamic>>> build() async {
    final api = ref.watch(healthApiProvider);
    final cache = ref.read(swrCacheProvider);
    const key = 'exercises.'; // 实键 'exercises.$date'
    final cached = cache.read<List<Map<String, dynamic>>>('exercises.$date');
    if (cached != null) {
      state = AsyncData(cached); // M9 播种
      try {
        final fresh = await _fetchAll(api);
        cache.write('exercises.$date', fresh);
        return fresh;
      } catch (_) {
        return cached; // 失败保旧（≙ :1732 降级但保缓存真值）
      }
    }
    return _fetchAll(api); // 首访：成功回写；失败仍抛由既有 error 支处理（现行口径）
  }
```

`_fetchAll` 成功侧包一层回写：新增 `Future<List<...>> _fetch(String date)` 已是成员——统一在 build 两条成功路径后 `cache.write`；`_reload()`（:73-79，add/remove 后的云真值重取）成功写缓存、**catch 支 `cache.invalidate('exercises.$date')`**（降级空列表不得覆盖/留存脏源）。`add`/`remove` 乐观链零改动。

- [ ] **Step 4: weightTrend 播种**

`report_controller.dart` weightTrendProvider 转 `AsyncNotifierProvider.autoDispose<WeightTrendNotifier, WeightTrendData>`（类形态非 family，键 `weightTrend`，build 体同 SwrFamily 模式；对外 `weightTrendProvider` 引用名不变，report_screen/weight_log_card 消费点零改动）。

- [ ] **Step 5: 换号全清**

`auth_state.dart` `_invalidateAccountScopedCaches` 波次链头部加：

```dart
    ref.read(swrCacheProvider).clear(); // M9：会话缓存换号必全清（跨号脏源）
```

`account_switch_cache_test.dart` 补一面钉：A 号读 summary 后换 B 号，B 首访必须走网络（`swrCache.read('summary.<date>')` 为 null）。

- [ ] **Step 6: 全量回归+提交**

`flutter test` 全绿 → `git commit -m "feat: M9-T3 exercises/weightTrend 播种+换号全清（失效矩阵行3/5+auth 波次，_reload 失败清键防脏源）"`

---

### Task 4: 食物库弹层——会话缓存+并行预取+骨架（A1/A2/A3）

**Files:**
- Create: `ShiguangFlutter/lib/features/common/skeleton.dart`
- Modify: `ShiguangFlutter/lib/features/profile/food_lib_sheet.dart:195-243`（_render 重写）+ 写路径删键（add/delete/setMeals 后）
- Test: `ShiguangFlutter/test/food_lib_sheet_test.dart` 补两面钉

**Interfaces:**
- Consumes: Task 1 SwrCache；键 `foods.custom`/`foods.builtin`
- Produces: `SkeletonBar({width, height})` 公共骨架条（Task 6 复用）

- [ ] **Step 1: SkeletonBar**

```dart
// ShiguangFlutter/lib/features/common/skeleton.dart
// M9-A2：公共骨架灰条（首页 _MealSkeletonRow 观感的通用化；纯静态不排
// 持续帧——pumpAndSettle 不死等，报告页 T4 骨架同路线）。
import 'package:flutter/material.dart';
import '../../app/theme.dart';

class SkeletonBar extends StatelessWidget {
  const SkeletonBar({super.key, this.width = double.infinity, this.height = 14});
  final double width;
  final double height;
  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: height,
        child: const DecoratedBox(
          decoration: BoxDecoration(
            color: Tokens.surfaceSoft,
            borderRadius: BorderRadius.all(Radius.circular(Tokens.radiusSm)),
          ),
        ),
      );
}
```

- [ ] **Step 2: 失败测试（food_lib_sheet_test 补，桩计数用该文件既有 StubHealthApi 实例直读 customListCalls/builtinCalls——若无计数属性则按 stub 样式补 `int customListCalls = 0;` 埋点）**

```dart
  testWidgets('M9：重开弹层缓存直显无「加载中」骨架；并行预取双列表', (tester) async {
    final api = StubHealthApi(customFoods: [StubHealthApi.customFoodMap(id: 'cf1', name: '妈妈牌红烧肉')],
        builtinFoods: StubHealthApi.builtinList()); // 35 条契约形状
    final c = ProviderContainer(overrides: [healthApiProvider.overrideWithValue(api)], retry: (_, _) => null);
    addTearDown(c.dispose);
    // 首开：骨架在场→数据渲染；两列表各拉 1 次（并行预取）
    // 开/关层沿用该文件既有定式：pump 宿主按钮页 → tap「食物库」→ 层内 ✕ pop
    // （见 food_lib_sheet_test.dart:93-94 宿主构造），不新造 openSheet 辅助。
    await tester.tap(find.text('食物库'));
    await tester.pump(); // 首开单帧：未回包→骨架在场
    expect(find.byKey(const ValueKey('lib-skeleton')), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.textContaining('自定义 1 条'), findsOneWidget);
    await tester.tap(find.text('内置常菜')); await tester.pumpAndSettle();
    expect(find.textContaining('内置 35 条'), findsOneWidget);
    expect(api.customListCalls, 1);
    expect(api.builtinCalls, 1);
    // 关层再开：缓存命中——首帧无骨架、零新请求
    await tester.tap(find.bySemanticsLabel('关闭').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('食物库'));
    await tester.pump(); // 仅一帧：若走网络必有骨架
    expect(find.byKey(const ValueKey('lib-skeleton')), findsNothing);
    expect(find.textContaining('自定义 1 条'), findsOneWidget);
    expect(api.customListCalls, 1); // 未重拉（后台刷新在二开首轮也命中缓存短路：
                                     // foods.* 键无 TTL，写路径才失效——spec §1 表列口径）
  });
```

- [ ] **Step 3: _render 重写**

要点：①打开即 `Future.wait([_loadCustom(), _loadBuiltin()])` 双路（各自走 `SwrCache.read` 命中则**不发请求**直接渲染，未命中拉+回写）；②`_loading` 初值=缓存未命中才 true；③骨架区：3 行 `SkeletonBar(height: 64)` 卡形（key `lib-skeleton`）替换「加载中…」文本；④写操作成功链（addCustomFood 回读、deleteCustomFood、setCustomFoodMeals）在既有刷新点前 `ref.read(swrCacheProvider).invalidate('foods.custom')`；⑤删弹层内 `_builtinCache` State 字段（会话缓存取代）。

- [ ] **Step 4: 全量回归+提交**

`git commit -m "feat: M9-T4 食物库会话缓存+并行预取+骨架条（重开 0ms 直显；_builtinCache 升为 SwrCache，A1/A2/A3 合流）"`

---

### Task 5: PressableScale + Stagger 组件（B1/B2 地基）

**Files:**
- Create: `ShiguangFlutter/lib/features/common/pressable.dart`
- Create: `ShiguangFlutter/lib/features/common/stagger.dart`
- Test: `ShiguangFlutter/test/pressable_stagger_test.dart`

**Interfaces:**
- Produces: `PressableScale({onTap, child})`、`Stagger({index, child})`（Task 6 消费）

- [ ] **Step 1: 实现 pressable.dart**

```dart
// ShiguangFlutter/lib/features/common/pressable.dart
// M9-B1（R4 视觉自主位）：按压微缩回弹——按下 120ms 收至 0.975，
// 松手 260ms elasticOut 回弹。只包无内部手势的容器位（spec §7 风险条）；
// 行内钮（✕/删除）保持自身手势不叠。
import 'package:flutter/material.dart';

class PressableScale extends StatefulWidget {
  const PressableScale({super.key, required this.onTap, required this.child});
  final VoidCallback? onTap;
  final Widget child;
  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _down = false;
  void _set(bool v) { if (mounted && _down != v) setState(() => _down = v); }
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTapDown: (_) => _set(true),
        onTapUp: (_) => _set(false),
        onTapCancel: () => _set(false),
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedScale(
          scale: _down ? 0.975 : 1.0,
          duration: Duration(milliseconds: _down ? 120 : 260),
          curve: _down ? Curves.easeOut : Curves.easeOutBack,
          child: widget.child,
        ),
      );
}
```

- [ ] **Step 2: 实现 stagger.dart**

```dart
// ShiguangFlutter/lib/features/common/stagger.dart
// M9-B2：错峰入场——首 build 播 translateY(14)+fade 220ms easeOutCubic，
// delay 40ms×index。**只播一次**（State 布尔；数据刷新/切日期 rebuild 不
// 重播，防回访骚扰；页面重建=新 State 重播属预期，spec §4 B6 亦由此达成）。
import 'package:flutter/material.dart';

class Stagger extends StatefulWidget {
  const Stagger({super.key, required this.index, required this.child});
  final int index;
  final Widget child;
  @override
  State<Stagger> createState() => _StaggerState();
}

class _StaggerState extends State<Stagger> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
  bool _played = false;
  late final Animation<double> _fade =
      CurvedAnimation(parent: _c, curve: Curves.easeOutCubic);
  late final Animation<Offset> _slide = Tween<Offset>(
          begin: const Offset(0, 0.06), end: Offset.zero)
      .animate(CurvedAnimation(parent: _c, curve: Curves.easeOutCubic));

  @override
  void initState() {
    super.initState();
    _played = true; // 本实例只自动播一次；rebuild 不再触发
    Future.delayed(Duration(milliseconds: 40 * widget.index), () {
      if (mounted) _c.forward();
    });
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
        opacity: _fade,
        child: SlideTransition(position: _slide, child: widget.child),
      );
}
```

- [ ] **Step 3: 测试钉（pressable_stagger_test.dart 全文核心）**

```dart
void main() {
  testWidgets('Stagger：首帧未播 opacity≈0，settle 后=1；同 tree 二次 pump 不重播', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Stagger(index: 0, child: Text('x')))));
    final op = () => tester
        .widget<FadeTransition>(find.descendant(
            of: find.byType(Stagger), matching: find.byType(FadeTransition)))
        .opacity.value;
    expect(op(), lessThan(0.5)); // 入场前
    await tester.pumpAndSettle();
    expect(op(), 1.0);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Stagger(index: 0, child: Text('y'))))); // rebuild 同位
    await tester.pump();
    expect(op(), 1.0); // 不重播（State 复用，_played 生效）
  });
  testWidgets('PressableScale：按下 scale=0.975，松手 settle 回 1.0', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(home: Scaffold(
        body: PressableScale(onTap: () => taps++, child: const SizedBox(width: 100, height: 50)))));
    final center = tester.getCenter(find.byType(SizedBox).first);
    final g = tester.startGesture(center);
    await tester.pump(const Duration(milliseconds: 150));
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale).first).scale, 0.975);
    await g.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale).first).scale, 1.0);
  });
}
```

- [ ] **Step 4: 全量回归+提交** `feat: M9-T5 PressableScale/Stagger 质感双件（只播一次语义钉死，spec §4 B1/B2）`

---

### Task 6: B1/B2 接线——首页/报告页/食物库行

**Files:**
- Modify: `home_screen.dart`（四卡外层 Stagger+盘子卡 PressableScale 不含横滑区嵌套——盘子卡本体不包，避免与 _PlateSwipeZone 手势竞争，只包建议/水/运动卡容器）
- Modify: `report_screen.dart`（卡序 Stagger）
- Modify: `food_lib_sheet.dart`（列表行前 8 行 Stagger + 行 PressableScale）
- Test: 既有页面测试回归（Stagger 初帧 opacity=0 会破 find——**测试兼容设计**：Stagger 用 `AnimateOnce` 语义 + 测试 harness 统一 `pumpAndSettle`；find.text 不受 opacity 影响，仅 hitTest 在动画中可点性——settle 后一致，不弱化断言）

- [ ] Step 1 首页：`children:` 列表各卡包 `Stagger(index: n)`；建议/水/运动卡容器再包 `PressableScale(onTap: null→卡无 tap 则跳过)`——**无 onTap 的卡不包 Pressable**（YAGNI），只包可点位：记一笔/记运动/喝水 200ml 钮已有 Material 反馈，B1 实际增量=食物库行与弹层主钮。范围收敛：B1 只接 food_lib 行 + 记录页餐次 chip。
- [ ] Step 2 报告页卡序 Stagger。
- [ ] Step 3 全量回归（红→查 Stagger 与既有 reveal()/settle 定式兼容）。
- [ ] Step 4 提交 `feat: M9-T6 错峰入场+按压反馈接线（首页/报告卡序、食物库行、餐次 chip）`

---

### Task 7: B3 环中心数从上一值插值

**Files:**
- Modify: `ShiguangFlutter/lib/features/home/plate_ring.dart:112-135`
- Test: `plate_ring_test.dart` 补钉

- [ ] Step 1 失败测试：`pumpWidget(remain=967)` settle → 改 `remain=500` 单帧 pump → 中心数文本应介于 500-967 之间（非瞬跳 500、非从 0 起）；settle 后=500。
- [ ] Step 2 实现：`_PlateRingState` 记 `_prevNum`（didUpdateWidget 更新为旧 end）；`IntTween(begin: _prevNum, end: remain)`；首帧 `_prevNum=0`（H5 静态初值 0 口径不变）。环弧 sweep 同法 begin=上一 sweep。
- [ ] Step 3 回归+提交 `feat: M9-T7 餐盘环数值/扫弧从上一值插值（切日/记餐跳变不再从 0 重扫）`

---

### Task 8: B4 showShiguangSheet 收口 10 处弹层

**Files:**
- Create: `ShiguangFlutter/lib/features/common/sheet.dart`
- Modify: exercise_sheet/goal_sheet/food_lib_sheet/goal_edit_sheet/profile_edit_sheet/custom_food_sheet/portion_sheet/search_sheet/body_profile_card(记体重弹层位)/profile_screen(提醒设置) 各 showModalBottomSheet 调用点
- Test: 各弹层既有测试文件逐一跑

- [ ] Step 1 helper：

```dart
// ShiguangFlutter/lib/features/common/sheet.dart
// M9-B4：弹层样板收口（10 处 showModalBottomSheet 的 shape/背景/标题行+✕
// 复制收敛；顶部 drag handle；isScrollControlled+最大高 78%）。
// ✕ 钮结构与标题文本逐字保留——既有测试选择器零破坏是收口底线。
Future<T?> showShiguangSheet<T>(
    BuildContext context, {required String title, required Widget child}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Tokens.surface,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Tokens.radiusSheet))),
    builder: (ctx) => ConstrainedBox(
      constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.78),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: const EdgeInsets.only(top: Tokens.sp2, bottom: Tokens.sp1),
              width: 28, height: 4,
              decoration: BoxDecoration(
                  color: Tokens.surfaceSoft,
                  borderRadius: BorderRadius.circular(2)), // drag handle
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  Tokens.sp5, Tokens.sp2, Tokens.sp5, 0),
              child: Row(children: [
                Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: Tokens.textLg,
                            fontWeight: FontWeight.w800,
                            color: Tokens.ink))),
                Semantics(
                  label: '关闭', button: true,
                  child: GestureDetector(
                    onTap: () => Navigator.of(ctx).pop(),
                    child: const Padding(
                      padding: EdgeInsets.all(Tokens.sp1),
                      child: Text('✕',
                          style: TextStyle(
                              fontSize: Tokens.textMd, color: Tokens.ink3)),
                    ),
                  )),
              ]),
            ),
            Flexible(child: child),
          ],
        ),
      ),
    ),
  );
}
```

- [ ] Step 2 逐弹层迁移（一次一个、跑该弹层测试文件再下一个；弹层内自带标题行的删除本地副本；返回语义/pop 值不动；键盘避让位 portion/custom_food 表单弹层保留 viewInsets 包裹）。**迁移顺序**：reminder 设置 → goal_edit → goal_sheet → exercise → food_lib → profile_edit → portion → search → custom_food → body_profile 记体重。
- [ ] Step 3 全量回归+提交 `feat: M9-T8 弹层样板收口 showShiguangSheet（10 处 handle 化，✕/标题哨兵零破坏逐层跑测）`

---

### Task 9: B5 toast 曲线 + 版本 2.7.0+20700 + 四门禁

- [ ] Step 1 `theme.dart` snackBarTheme 补 `enterAnimationCurve: Curves.easeOutBack, exitAnimationCurve: Curves.easeInCubic`（主题实位仅曲线——scale/slide 型动画需 35 调用点 helper 化，登记后续池不做，spec §4 B5）。
- [ ] Step 2 `pubspec.yaml` → `2.7.0+20700`。
- [ ] Step 3 四门禁全跑（analyze/flutter test 重定向判码/H5 node --test/check:version），任何红先修后走。
- [ ] Step 4 提交 `feat: M9-T9 toast 曲线微过冲 + 版本 2.7.0+20700 四门禁绿`

---

### Task 10: 沙盒 release 重打 + 真机目检单 + 收官

- [ ] Step 1 ASCII 沙盒构建（拷 ShiguangFlutter 含 key.properties+jks → pub get → `flutter build apk --release --split-per-abi` → 裸 exit code 判定）；arm64 拷回 `食光Flutter-v2.7.0.apk`，v2.6.0 `git rm`；apksigner 验签基线 `cc7e2d…00cc4f0`；沙盒即删。
- [ ] Step 2 真机 `install -r` 升级；目检单：①食物库二开 0ms 直显（录屏对比）②记餐→回首页旧数闪现≤400ms 后新数（SWR 语义验收）③切日期播种跳变④环插值⑤弹层 handle+下拉关闭⑥toast 曲线⑦首页/报告错峰入场⑧按压反馈⑨骨架（会话首访）。
- [ ] Step 3 `build:` 收官提交 + 真机验收报告（.mimosa/m9-real/ 帧号全录）。

---

## 验收基线（终审对照）

1. 失效矩阵（spec §1 表）逐行有测试钉或目检帧。
2. 换号清缓存、写后删键两面必钉（脏数据是 SWR 唯一实质风险面）。
3. 10 弹层收口后各弹层测试文件全绿无删改断言。
4. 文案零改动；H5 线零改动。
