# M6 日常功能追平 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Flutter 端补齐 H5 核心日常四件：运动打卡全家桶（记运动/列表/删除/额度联动）、喝水打卡+目标编辑、首页每日建议卡、提醒卡压缩（方案 A）。

**Architecture:** 延续 M1-M5 分层。运动/喝水的「乐观更新+失败回滚」照 record_controller.dart 的 `_syncDay` 先例做 Notifier 层（exercise_controller / water 走 summaryProvider 局部覆盖）；首页额度接线补上 plate_ring 预留的 exerciseKcal 口子；建议卡是纯接线（domain/advice.dart 已逐字移植）。云函数与 H5 零改动（红线恢复原样）。

**Tech Stack:** Flutter 3.47.5 / Dart 3.13.4 / Riverpod 3.4.3（无新依赖）。

**Spec:** `docs/superpowers/specs/2026-09-26-flutter-m6-daily-features-design.md`（本计划依据，执行时两份都读）

## Global Constraints

- **云函数 api-diet 与 H5 js 一行不改**（硬约束；M5 方案 b 的一次性授权已用毕）。所需路由全部现成：GET/POST `/diet/exercises`、DELETE `/diet/exercises/:id`、PUT `/user/water-goal`、POST `/diet/water`（js/api.js:65-77）。
- 数据行为 bug-for-bug 对齐 H5（toast/文案/校验闸/请求体逐字，权威源行号在各任务 Files 里给足）；视觉与布局 R4 授权自主（每任务模拟器目检，偏离处报告登记「差异+理由」）。
- 分层铁律：`lib/domain/` 不 import package:flutter；widget 测试显式 `import 'package:flutter/material.dart';` 且挂 `shiguangTheme()` 真主题（M5-T5 教训）。
- 命令：每条 Bash 前置 `export PATH="$PATH:/c/flutter/bin"; export PUB_HOSTED_URL=https://pub.flutter-io.cn; export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`；只用 `dart analyze lib test`（永不 flutter analyze）；判定看真实 exit code，禁管道吞码；release 构建走 ASCII 沙盒（坑⑫）。
- adb 在 `$LOCALAPPDATA/Android/Sdk/platform-tools/adb.exe`；绝不 kill-server；截图像素复核（Read 缓存可能骗人，T4 教训）。
- 主题债：FilledButton 进 Row 非 flex 位仍建议 Expanded/通栏（theme 已 Size(0,52)，但观感自主裁）。
- 互通红线：真实 uid/凭证零入文件；测试只用 uitest01/u_test 系。
- 版本：任务内不动；T8 统一升 **2.4.0+20400**。H5 线 1.4.0 不动，`node --test` 须 77/77 零 diff。
- 提交信息中文带 `M6-T<N>`；每任务一提交；合入/推送等老大令。

## 现状锚点（已核实事实）

- **domain 就绪**：`exercise.dart`（`exerciseKcalOf(Exercise, num, num?)`、`exerciseAmountLabel(Exercise)→(String,String)`、`isRepRecord({required String key, required int createdAt})`、`repUnitCutoffMs`）；`constants.dart`（`exerciseLib` :85、`waterCupMl=200`/`waterGoalMin=800`/`waterGoalMax=3000` :25-27）；`advice.dart`（`makeAdviceCtx({required Summary summary, num exerciseKcal=0, List<Map> records=const[], required bool isToday, num weightKg=55, num waterGoalMl=1600})→AdviceCtx`、`buildAdvice(AdviceCtx)→List<(String,String)>` 最多 3 条）。
- **data 缺口**：HealthApi 无 exercises 三法/无 setWaterGoal；`addWater(int delta,[String? date])` 现成（health_api.dart:65）。
- **云函数行为**（index.js:343-372，已读）：GET 返回 `[{id:_id,key,name,emoji,amount,unit,kcal}]`——**无 createdAt**（H5 次数型记录刷新后 isRepRecord 退化按分钟显示，属 H5 既有行为，Flutter 同样退化并注释登记，禁改云）；POST 校验 `!kcal→{ok:false,message:"消耗热量无效"}`、unit 白名单 `km|min`（rep 落 min）；DELETE 按裸 `_id`（无前缀双轨坑）。
- **H5 权威源**：运动卡+弹层 app.js:1739-1856（列表行 `-{kcal} kcal`、空态「今天还没运动，点下方「记运动」」、chips 选择重置数量 km→5/rep→10/时长→20、步进 ±0.5|5 下限 step 上限 km100/rep2000/min300、保存「已记录{名} · 消耗 {kcal} kcal」/失败回滚「记录失败：+msg」、删除确认「确认删除/删除后无法恢复，确定要删除这条运动吗？」→「已删除运动记录」/「删除失败：+msg」、乐观更新+回滚全链）；水卡 app.js:409-466（标题「喝水打卡」/「喝水 · 日期」、hint「已喝 N 杯 · 每杯 200ml」/达成「目标已达成 🎉」、undo 仅 water>0 可见、drinkOneCup 达上限 toast「目标 {goal}ml 已达成，明天继续」、+杯 toast「+200ml · 已喝 {n*200}ml」、撤销 toast「已退回一杯 · 剩 {n*200}ml」、失败回滚「同步失败：+msg」）；goal-sheet app.js:470-493（±200 步进、边界 toast「最大 3000ml」/「最小 800ml」、保存 setWaterGoal→「喝水目标已设为 {ml}ml」）；renderRing app.js:297-310（budget=target+ex、note 双支「额度 {budget} = 基准 {target} + 运动 {ex} kcal」/「基准目标 {target} kcal · 记运动后额度自动上调」）；renderDailyAdvice app.js:348-362。
- **Flutter 接线点**：`plate_ring.dart`（`PlateRing.exerciseKcal` 静态 0，:13-14 注释预留；`ringSweep/ringProgressColor` 收 budget 参数已就绪）；`home_screen.dart:104`（`target + PlateRing.exerciseKcal`）；`home_controller.dart`（healthApiProvider/todayProvider/summaryProvider family autoDispose）；`record_controller.dart:92-95`（`_syncDay` invalidate records+summary 先例）；`profile_screen.dart` `_remindCard()`（压缩对象）；`body_profile_card.dart`（renderMetab 等价卡，补今日运动行）；`auth_state.dart:64`（登出失效清单，新 provider 要入列）。
- **StubHealthApi**（test/stubs/stub_health_api.dart）：M5 已按云语义修桩，本里程碑补 exercises/waterGoal 桩方法。

---

### Task 1: HealthApi 运动+喝水目标路由 + 契约双端锁

**Files:**
- Modify: `ShiguangFlutter/lib/data/health_api.dart`（饮食记录段后加运动段）
- Modify: `contract/fixtures/diet-core.json`（routes 追加 4 条）
- Modify: `ShiguangFlutter/test/data/contract_test.dart`（invoke switch 加 4 case）
- Modify: `ShiguangFlutter/test/stubs/stub_health_api.dart`（补桩，语义对齐 index.js:343-372）
- Test: 契约测试驱动（无独立新文件）

**Interfaces:**
- Produces（T2-T5 消费，签名逐字）：
  - `Future<List<dynamic>> getExercises(String date)` → GET `/diet/exercises` params `{date}`（数组→callValue）；
  - `Future<Map<String, dynamic>> addExercise(Map<String, dynamic> record)` → POST 同径，record 原样进 body；
  - `Future<Map<String, dynamic>> deleteExercise(String id)` → DELETE `/diet/exercises/:id` params `{id}`；
  - `Future<Map<String, dynamic>> setWaterGoal(num waterGoalMl)` → PUT `/user/water-goal` body `{'waterGoalMl': ml}`。

- [ ] **Step 1: 先核云函数返回形状再写 fixture**

`grep -n "water-goal" HealthyDiet/cloudfunctions/api-diet/index.js` 读 PUT 分支 return 形状（H5 app.js:489 解构 `{waterGoalMl}`，以云实返为准）；exercises 三路由形状按已读 index.js:343-372。fixture 四条（形状对齐既有条目；responseFields 以实返为准）：

```json
{
  "route": "exercises", "dartMethod": "getExercises", "jsMethod": "getExercises",
  "path": "/diet/exercises", "httpMethod": "GET", "readOnly": true,
  "requestSample": { "params": { "date": "2026-09-26" } },
  "responseShape": "array", "responseFields": ["id", "key", "name", "emoji", "amount", "unit", "kcal"],
  "responseSample": [ { "id": "rec_test_x1", "key": "run", "name": "跑步", "emoji": "🏃", "amount": 5, "unit": "km", "kcal": 181 } ]
},
{
  "route": "addExercise", "dartMethod": "addExercise", "jsMethod": "addExercise",
  "path": "/diet/exercises", "httpMethod": "POST", "readOnly": false,
  "requestSample": { "body": { "date": "2026-09-26", "key": "pushup", "name": "俯卧撑", "emoji": "💪", "amount": 10, "unit": "min", "kcal": 12 } },
  "responseShape": "object", "responseFields": ["ok", "id", "uid", "date", "key", "name", "emoji", "amount", "unit", "kcal", "createdAt"]
},
{
  "route": "deleteExercise", "dartMethod": "deleteExercise", "jsMethod": "deleteExercise",
  "path": "/diet/exercises/:id", "httpMethod": "DELETE", "readOnly": false,
  "requestSample": { "params": { "id": "rec_test_x1" } },
  "responseShape": "object", "responseFields": ["ok"]
},
{
  "route": "setWaterGoal", "dartMethod": "setWaterGoal", "jsMethod": "setWaterGoal",
  "path": "/user/water-goal", "httpMethod": "PUT", "readOnly": false,
  "requestSample": { "body": { "waterGoalMl": 1600 } },
  "responseShape": "object", "responseFields": ["waterGoalMl"]
}
```

（`responseFields`/`responseShape` 逐条对照云源码 return 修正——M5-T2 教训：addExercise 云实返 `{ok:true, id, ...doc}` 平铺含 createdAt；不符改 fixture 不改云。）

- [ ] **Step 2: contract_test.dart 加 case（RED：编译错）**

```dart
      case 'getExercises':
        return api.getExercises(p['date'] as String);
      case 'addExercise':
        return api.addExercise(Map<String, dynamic>.from(b));
      case 'deleteExercise':
        return api.deleteExercise(p['id'] as String);
      case 'setWaterGoal':
        return api.setWaterGoal(b['waterGoalMl'] as num);
```

（getExercises 返回 Future<List> 与 switch 的 `Future<void>` 返回型不合——实现为 `await api.getExercises(...); return;` 形态，参照既有 getMealRecords case 的写法，执行时对齐现码。）

- [ ] **Step 3: HealthApi 实现**

```dart
  /* ---------- 运动（M6-T1；路由 js/api.js:75-77） ---------- */

  /// 某日运动记录（js/api.js:352 getExercises；响应数组 → callValue。
  /// 注意：云端不回 createdAt（index.js:347-350），次数型记录刷新后 isRepRecord
  /// 判别退化按分钟显示——H5 同病，bug-for-bug 保留，禁改云）
  Future<List<dynamic>> getExercises(String date) async {
    final data = await _client.callValue('/diet/exercises',
        params: <String, dynamic>{'date': date});
    return data is List ? data : const <dynamic>[];
  }

  /// 新增运动记录（js/app.js:1820 调用面：{date,key,name,emoji,amount,unit,kcal}）
  Future<Map<String, dynamic>> addExercise(Map<String, dynamic> record) =>
      _client.call('/diet/exercises', method: 'POST', body: record);

  /// 删除运动记录（js/api.js:354 deleteExercise：DELETE /diet/exercises/:id）
  Future<Map<String, dynamic>> deleteExercise(String id) =>
      _client.call('/diet/exercises/:id',
          method: 'DELETE', params: <String, dynamic>{'id': id});

  /// 喝水目标（js/api.js:279 setWaterGoal：body {waterGoalMl}，云端归一 200 倍数）
  Future<Map<String, dynamic>> setWaterGoal(num waterGoalMl) =>
      _client.call('/user/water-goal',
          method: 'PUT', body: <String, dynamic>{'waterGoalMl': waterGoalMl});
```

- [ ] **Step 4: StubHealthApi 补桩**

构造参数追加可配列表/记录桩：`exercisesByDate`（Map<String,List<Map>>）、`addExerciseError`/`deleteExerciseError`/`setWaterGoalError`（Object?），行为对齐云语义（add 校验 kcal>0 否则 throw ApiException(code:'ok-false')——**注意云端返回 `{ok:false,message}` 而非 HTTP 错**，桩返回该 Map 由调用层判 ok；setWaterGoal 回 `{'waterGoalMl': (ml/200).round()*200}` 对齐云归一）。桩细节执行时对 index.js 复核。

- [ ] **Step 5: 双端契约测试 + 全量回归 + 提交**

`flutter test test/data/contract_test.dart`（新 4 条绿）；`cd . && node --test tests/contract.test.js`（H5 侧若泛化循环自动覆盖则零改动，报数核对）；`dart analyze lib test` 0；`flutter test` 全量绿。

```bash
git add contract/fixtures/diet-core.json ShiguangFlutter/lib/data/health_api.dart ShiguangFlutter/test/data/contract_test.dart ShiguangFlutter/test/stubs/stub_health_api.dart
git commit -m "feat: M6-T1 HealthApi 补运动三路由+setWaterGoal——契约 fixture 四条双端锁定（云 GET 无 createdAt 退化显示 bug-for-bug 登记）"
```

---

### Task 2: 运动控制器 + 记运动弹层

**Files:**
- Create: `ShiguangFlutter/lib/features/exercise/exercise_controller.dart`
- Create: `ShiguangFlutter/lib/features/exercise/exercise_sheet.dart`
- Test: `ShiguangFlutter/test/exercise_sheet_test.dart`

**Interfaces:**
- Consumes: T1 三方法、domain `exerciseLib/exerciseKcalOf/exerciseAmountLabel`、`profileProvider`（体重）。
- Produces（T3 消费）：
  - `final exercisesProvider = FutureProvider.family<List<Map<String, dynamic>>, String>((ref, date) => ...)`（getExercises 原样 Map 列表）；
  - `final exerciseKcalProvider = Provider.family<int, String>((ref, date) => ref.watch(exercisesProvider(date)).maybeWhen(data: (l) => l.fold<int>(0, (a, r) => a + ((r['kcal'] as num?)?.toInt() ?? 0)), orElse: () => 0));`
  - `Future<void> addExerciseRecord(WidgetRef ref, String date, Exercise lib, num amount, void Function(String) toast)`（乐观+回滚，内部 invalidate exercisesProvider(date)+summaryProvider(date)）；
  - `Future<void> deleteExerciseRecord(WidgetRef ref, String date, Map<String, dynamic> rec, void Function(String) toast)`；
  - `Future<void> openExerciseSheet(BuildContext context, WidgetRef ref, {required String date})`。

- [ ] **Step 1: 失败测试**（挂 shiguangTheme + profileContainer 样板，healthApiProvider 注 Stub）

必测链（文案逐字 H5）：
①chips 选择重置数量：默认跑步（exerciseLib 首项）；点俯卧撑（rep）→ 数量框=10；点跳绳→10；点跑步→5；点时长型→20；
②步进：km 型 ±0.5（下限 0.5）、rep/min 型 ±5（下限 5）；顶格 toast「已到上限」（km 100/rep 2000/min 300 到界）——**H5 到界无 toast（Math.min 静默），逐字对齐 H5：静默**，此条断「顶格再点数字不动、无 toast」；
③预览：`预计消耗 {exerciseKcalOf(lib,amount,体重)} kcal`（跑步 5km@66.66kg 样本值直比，体重取 profileProvider.body.weightKg ?? 55）；
④保存：kcal==0 → toast「请先设置运动量」不发请求；正常保存 → 弹层关、stub 收到 addExercise body 逐键 `{date,key,name,emoji,amount,unit,kcal}`（**unit 直传 lib.unit：rep 落 'rep' 还是 'min'？H5 :1821 传 `unit: lib.unit`，云 index.js:362 `body.unit === "km" ? "km" : "min"` 把 rep 归 min——Flutter 同传 lib.unit 由云归一，断请求体 unit:'rep'**）、toast「已记录俯卧撑 · 消耗 12 kcal」；
⑤失败回滚：addExerciseError → toast「记录失败：boom」，exercisesProvider 重取后列表不含 temp；
⑥删除：确认框（「确认删除」「删除后无法恢复，确定要删除这条运动吗？」）→ 确认 → 乐观移除 + deleteExercise(id) + toast「已删除运动记录」；取消 → 零请求；deleteExerciseError → 「删除失败：boom」+列表回插。

- [ ] **Step 2: exercise_controller.dart**

```dart
// ShiguangFlutter/lib/features/exercise/exercise_controller.dart
// 运动记录读写控制器（M6-T2）。乐观更新+失败回滚模式对齐 record_controller
// 的 _syncDay 先例；行为权威源 js/app.js:1781-1852（chips 重置/步进/保存/删除）。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/constants.dart' show Exercise;
import '../../domain/exercise.dart' show exerciseKcalOf;
import '../home/home_controller.dart'
    show healthApiProvider, summaryProvider;

final exercisesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, date) async {
  final list = await ref.watch(healthApiProvider).getExercises(date);
  return list.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
});

/// 某日运动合计（H5 state.exerciseKcal，app.js:1733 reduce 同构）
final exerciseKcalProvider = Provider.family<int, String>((ref, date) =>
    ref.watch(exercisesProvider(date)).maybeWhen(
          data: (l) => l.fold<int>(
              0, (a, r) => a + ((r['kcal'] as num?)?.toInt() ?? 0)),
          orElse: () => 0,
        ));

void _syncDay(ProviderRef ref, String date) {
  ref.invalidate(exercisesProvider(date));
  ref.invalidate(summaryProvider(date));
}
```

（add/delete 两个顶层 async 函数按 Interfaces 签名实现：temp 行入列 → `ref.listen`-free 的 `container.read(exercisesProvider(date).future)` 竞态麻烦——**采用 H5 同构的「写成功后统一 invalidate，失败也 invalidate」简化**：保存即 `await addExercise(...)`，成功 invalidate + toast 成功文案；ApiException/网络错 invalidate + toast「记录失败：+msg」。观感差异（无本地瞬显 temp 行）登记 R4 面，invalidate 后网络往返 <300ms 可接受；若终审认为必须乐观，M7 补 Notifier 重构。）

- [ ] **Step 3: exercise_sheet.dart**

showModalBottomSheet；结构：标题「记运动」+关闭 ✕；chips Wrap（exerciseLib 全量，emoji+名，选中态主色描边）；数量行（−/数字框/＋，步进与下限按 lib.unit 分支：km ±0.5 下限 0.5 上限 100，rep ±5 下限 5 上限 2000，min ±5 下限 5 上限 300——H5 :1796-1806 逐支）；预览行（updateExercisePreview 逐字「预计消耗 N kcal」，label 行「距离|数量|时长」+单位后缀）；保存通栏钮。数字框 `FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))`（M5-T7 定式）。chips 点击重置 amount（km→5/rep→10/其余→20，app.js:1786 逐字）。体重源 `ref.watch(profileProvider)` 的 `body.weightKg`，缺省 55。

- [ ] **Step 4: 回归 + 目检 + 提交**

全量 test/analyze；模拟器目检弹层（chips 换行、步进、预览刷新）；提交：

```bash
git add ShiguangFlutter/lib/features/exercise ShiguangFlutter/test/exercise_sheet_test.dart
git commit -m "feat: M6-T2 运动控制器+记运动弹层——chips 重置/三型步进/预览/删除确认逐字 H5（乐观简化为 invalidate 即刷新，差异登记）"
```

---

### Task 3: 首页运动卡 + 餐盘环额度接线 + 身体卡今日运动行

**Files:**
- Modify: `ShiguangFlutter/lib/features/home/home_screen.dart`（三餐区后插运动卡；:104 budget 接线）
- Modify: `ShiguangFlutter/lib/features/home/plate_ring.dart`（静态 exerciseKcal → 实例参数，默认 0）
- Modify: `ShiguangFlutter/lib/features/profile/body_profile_card.dart`（补「今日运动」行）
- Modify: `ShiguangFlutter/lib/app/auth_state.dart`（登出失效清单加 exercisesProvider）
- Test: `ShiguangFlutter/test/home_exercise_test.dart`

**Interfaces:**
- Consumes: T2 `exercisesProvider/exerciseKcalProvider/openExerciseSheet`、domain `isRepRecord/exerciseAmountLabel`。
- Produces: `HomeExerciseCard({required String date})`（首页内联组件即可，不另立文件归属）。

- [ ] **Step 1: 失败测试**

①空态：exercisesByDate 空 → 卡题「今日运动」、副行「消耗 0 kcal」、文案「今天还没运动，点下方「记运动」」、按钮「＋ 记运动」；
②列表行：样本 `[{id:'x1',key:'run',name:'跑步',emoji:'🏃',amount:5,unit:'km',kcal:181},{id:'x2',key:'pushup',name:'俯卧撑',emoji:'💪',amount:10,unit:'min',kcal:12}]` → 行显「5 km」「10 分钟」（x2 无 createdAt → isRepRecord false → 按分钟，**退化行为有测试钉死**）、kcal 前缀「-181 kcal」；合计「消耗 193 kcal」；
③环接线：summary target=1679 + ex=193 → 环中心/额度行显示 1872，note「额度 1872 = 基准 1679 + 运动 193 kcal」（逐字 app.js:307）；ex=0 时 note 回落「基准目标 1679 kcal · 记运动后额度自动上调」；
④身体卡：今日运动行存在且数字=当日合计（profile 页挂 exercisesProvider 同 date）。

- [ ] **Step 2: 实现**

plate_ring.dart：`static const exerciseKcal = 0` 删除，改构造参数 `this.exerciseKcal = 0`，budget 计算 `target + exerciseKcal`；home_screen :104 与 PlateRing 构造点同步接线（watch exerciseKcalProvider(date)）。运动卡版式 R4 自主（对齐既有卡样式：Tokens.surface 圆角阴影，行结构复用 _recordTile 观感）。body_profile_card 的 renderMetab 区补「今日运动 {ex} kcal」行 + TDEE 行公式注记含 `＋今日运动{ex}`（ex>0 时，app.js:1599 逐字；ex=0 静默同 H5）——body 卡需 watch exerciseKcalProvider(todayProvider)。auth_state `_invalidateAccountScopedCaches` 加 `ref.invalidate(exercisesProvider)`（family 整族，M4 语义）。

- [ ] **Step 3: 回归 + 目检 + 提交**

```bash
git add ShiguangFlutter/lib/features/home ShiguangFlutter/lib/features/profile/body_profile_card.dart ShiguangFlutter/lib/app/auth_state.dart ShiguangFlutter/test/home_exercise_test.dart
git commit -m "feat: M6-T3 首页运动卡+餐盘环额度真实联动+身体卡今日运动行——plate_ring 恒 0 口子闭环"
```

---

### Task 4: 首页喝水卡

**Files:**
- Create: `ShiguangFlutter/lib/features/home/water_card.dart`
- Modify: `ShiguangFlutter/lib/features/home/home_screen.dart`（餐盘环/建议卡位下插水卡；顺序对齐 H5：环→建议→水→运动→三餐，执行时对 index.html:104-137 复核）
- Test: `ShiguangFlutter/test/water_card_test.dart`

**Interfaces:**
- Consumes: `HealthApi.addWater`（现成）、`profileProvider`（goal.waterMl，缺省 1600）、summaryProvider（water 杯数）。
- Produces: `WaterCard({required String date, required void Function() onEditGoal})`（onEditGoal 由 home 接 T5 弹层；T5 未落地前 home 传空函数占位——**同里程碑内 T5 紧随，不留死按钮：T4 提交时 onEditGoal 先接 SnackBar 占位「待 T5」不允许，直接 T4+T5 合并提交？**不——T4 内先渲染 goal 行但点击暂开最简内置步进弹层（复用 T5 组件前置声明），T5 再替换成完整 goal-sheet。**裁定：T4 与 T5 合并为一个任务**（水卡+目标弹层同一交互面，拆开必留接线债）。本任务改名为「喝水闭环」。

- [ ] **Step 1: 失败测试**

①渲染：summary.water=3、goal=1600 → 标题「喝水打卡」、ml 显示 600、hint「已喝 3 杯 · 每杯 200ml」、进度 37.5%、撤销钮可见；water=0 → 撤销隐藏；water=8(1600ml) → hint「目标已达成 🎉」；
②喝一杯：点杯 → 乐观 +1、addWater(1,date) 被调、回 `{water:4}` 后显示 4 杯、toast「+200ml · 已喝 800ml」；已达上限（8 杯）再点 → toast「目标 1600ml 已达成，明天继续」且零请求；失败（addError）→ 回滚 + toast「同步失败：boom」；
③撤销：点撤销 → addWater(-1,date)、toast「已退回一杯 · 剩 400ml」（以回包 water 为准）；
④目标弹层：开层预填 1600；＋ → 1800；连点到 3000 再点 → 值不动 toast「最大 3000ml」；− 到 800 再点 → toast「最小 800ml」；保存 → setWaterGoal(2000) → toast「喝水目标已设为 2000ml」、profileProvider invalidate（goal 行刷新）。

- [ ] **Step 2: water_card.dart + goal_sheet.dart**

水卡结构对齐 H5 water-widget：杯图标（点击区 Semantics「喝一杯」）、ml 大数字+goal 行（「/ {goal} ml」+「设置」箭头开 goal-sheet）、进度条（`LinearProgressIndicator` 或自定义 Stack，刻度线 R4 自主）、hint、撤销 TextButton（visibility 按 water>0）。**数字口径全部 `summary.water * waterCupMl`**，goal=`(profileProvider.data['goal']['waterMl'] as num?) ?? 1600`。乐观更新模式：本地 `int _waterOverride` 态（null=跟 provider），成功后跟回包——与 H5 同构（app.js:432-437）。goal-sheet：±200 步进（bumpGoal 逐支，含边界 toast 逐字）、保存 `setWaterGoal` → `ref.invalidate(profileProvider)` → toast。date 非今日时标题「喝水 · {dateLabel}」（dates.dart 有 dateLabelOf 则复用，无则同口径实现并登记）。

- [ ] **Step 3: 回归 + 目检 + 提交**

```bash
git add ShiguangFlutter/lib/features/home/water_card.dart ShiguangFlutter/lib/features/home/goal_sheet.dart ShiguangFlutter/lib/features/home/home_screen.dart ShiguangFlutter/test/water_card_test.dart
git commit -m "feat: M6-T4 喝水闭环——水卡乐观喝一杯/撤销+目标 goal-sheet 200 步进，文案逐字 H5"
```

---

### Task 5: 首页每日建议卡

**Files:**
- Create: `ShiguangFlutter/lib/features/home/advice_card.dart`
- Modify: `ShiguangFlutter/lib/features/home/home_screen.dart`（环下插建议卡）
- Test: `ShiguangFlutter/test/advice_card_test.dart`

**Interfaces:**
- Consumes: `advice.dart makeAdviceCtx/buildAdvice`、summaryProvider、recordsProvider、exerciseKcalProvider（T3）、profileProvider（weightKg/waterGoalMl）。
- Produces: `AdviceCard({required String date})`。

- [ ] **Step 1: 失败测试**

①样本直出：构造 summary{target:1679,kcal:200,protein:5,carb:30,fat:10,water:1} + records 仅早餐 → 渲染 1-3 条 li，每条 icon+文案，内容与 `buildAdvice(makeAdviceCtx(同参))` 纯函数期望逐字一致（UI 断言取 buildAdvice 输出动态比对，另钉一条已知样本「蛋白质…偏低」出现）；②就绪态：summary loading → 卡位骨架/隐藏（对齐 H5 `if (!s) return` 不渲染）；③>110 死分支回归：kcal=1.11*budget 样本 → 不出现「超标」类文案（R2 死分支保留断言）。

- [ ] **Step 2: advice_card.dart**

```dart
// ShiguangFlutter/lib/features/home/advice_card.dart
// 首页每日建议卡（M6-T5）。行为权威源 js/app.js:348-362 renderDailyAdvice：
// ctx 六入参同源装配，buildAdvice 最多 3 条 [emoji, 文案]。
// domain/advice.dart 已逐字移植（含 R2 >110 死分支），本文件纯接线。
```

watch 五源装配 `makeAdviceCtx(summary: s, exerciseKcal: ex, records: records, isToday: date == todayIso(), weightKg: 体重 ?? 55, waterGoalMl: goal)`；渲染卡（标题「今日建议」——对 index.html:106-109 复核标题文案）+ Column li 行。

- [ ] **Step 3: 回归 + 目检 + 提交**

```bash
git add ShiguangFlutter/lib/features/home/advice_card.dart ShiguangFlutter/lib/features/home/home_screen.dart ShiguangFlutter/test/advice_card_test.dart
git commit -m "feat: M6-T5 首页每日建议卡接线——advice.dart 零引用债清偿，R2 死分支回归钉"
```

---

### Task 6: 提醒卡压缩（方案 A）

**Files:**
- Modify: `ShiguangFlutter/lib/features/profile/profile_screen.dart`（_remindCard 一行化 + 新增设置弹层）
- Test: `ShiguangFlutter/test/profile_reminders_test.dart`（迁移到新路径）+ profile_screen_test 相应断言

**Interfaces:**
- Consumes/Produces: 行为零变更——`_setReminders/_testMealReminder/_testWaterReminder/_reminderBusy` 原样；新函数 `Future<void> _openReminderSettings()`（弹层含说明+两测试钮「诊断」区）。

- [ ] **Step 1: 改测试先红**

断言：①卡面无「发一条测试通知」「发一条喝水到点提醒（测试）」文本、卡高显著收窄（find 卡 Rect 高度 < 旧值一半，用既有 geometry 断言式样）；②卡面有「设置」入口（icon/箭头，Semantics label「提醒设置」）→ 点开弹层两测试钮在、点击行为与文案断言迁移至弹层路径；③开关直拨行为断言不动（setEnabled 链、重入门禁、连拨单发）。

- [ ] **Step 2: 实现**

卡体：Row[Expanded(Column[标题,副文案]), 设置 IconButton, Switch]；弹层：showModalBottomSheet 列「开启后每天定点弹系统通知」说明 + 分隔线 + 「诊断」小标题 + 两通栏钮（原 handler 直连）。FilledButton 通栏合规（theme 已有限值）。

- [ ] **Step 3: 回归 + 目检 + 提交**

```bash
git add ShiguangFlutter/lib/features/profile/profile_screen.dart ShiguangFlutter/test/profile_reminders_test.dart ShiguangFlutter/test/profile_screen_test.dart
git commit -m "refactor: M6-T6 提醒卡压缩方案A——卡面一行化，测试钮收进设置弹层诊断区，行为零变更"
```

---

### Task 7: 收官——版本、四门禁、release 重打、互通与全链目检

**Files:**
- Modify: `ShiguangFlutter/pubspec.yaml`（`2.4.0+20400`）
- Create: 仓库根 `食光Flutter-v2.4.0.apk`（arm64 release，随 release 入库；v2.3.0 包出库替换——`git rm 食光Flutter-v2.3.0.apk`，历史仍有）
- Create: `.superpowers/sdd/2026-09-26-flutter-m6-daily-features/task-7-report.md`（git-ignore）

- [ ] **Step 1: 版本升档 + 四道门禁**（analyze 0 / flutter test 全量报数 / node --test 77/77 零 diff / check:version 2*10000+4*100+0=20400）

- [ ] **Step 2: ASCII 沙盒 release 构建**（配方照 M5-T8：整拷 ShiguangFlutter+key 材料 → `flutter build apk --release --split-per-abi` → arm64 拷回改名 → apksigner CN=Shiguang + md5 双侧一致 → 删沙盒验证不存在）

- [ ] **Step 3: 模拟器全链目检（R4 收口）**：x86_64 release 装 emulator → uitest01 登录 → 首页五区（环含额度=目标+运动实测：记一条跑步 5km 后环数字刷新）→ 记运动/删除全流程 → 喝水+1/撤销/目标步进 → 建议卡渲染 → 我的页提醒卡一行化+弹层测试钮。截图像素复核留档 `.mimosa/`。

- [ ] **Step 4: 互通抽查（数据面必做）**：Flutter 记运动 → curl GET `/diet/exercises?date=` 反查逐字段（uitest01）→ （H5 渲染面能核则核，核不动登记）；H5 页面记一杯水 → Flutter 水卡刷新可见（addWater 同路由）。测试数据清理（运动记录删净，复 GET 空）。

- [ ] **Step 5: task-7-report.md**（R4 差异清单、各任务登记面：乐观简化/createdAt 退化显示/dateLabel、门禁原始输出、真机单：卸 debug→装 arm64→四功能上手）+ 全量门禁复跑零回归 + 提交：

```bash
git add ShiguangFlutter/pubspec.yaml ShiguangFlutter/pubspec.lock 食光Flutter-v2.4.0.apk
git rm 食光Flutter-v2.3.0.apk
git commit -m "build: M6 收官——2.4.0+20400 四门禁绿，食光Flutter-v2.4.0 正式包替换入库（arm64 release 签名）"
```

合入 main/推送不在本计划内——等老大单字令。

---

## Self-Review 结论

1. **Spec 覆盖**：四件→T2/T3（运动全家桶+环+身体卡）、T4（喝水+目标）、T5（建议卡）、T6（提醒卡压缩）、T1（契约地基）、T7（收官：版本/门禁/重包/互通/目检）——spec 验收 5 条逐条有归属；非目标零越界（无管理页/目标体重/常吃回填动作进本计划）。
2. **占位扫描**：无 TBD；两处执行期核对项均给了「先 grep 云源码再定 fixture」的明确程序（M5-T2 配方），非占位。
3. **类型一致**：`exercisesProvider/exerciseKcalProvider/addExerciseRecord/deleteExerciseRecord/openExerciseSheet`（T2 定义→T3 消费）、`WaterCard(onEditGoal)/AdviceCard(date)`、`PlateRing(exerciseKcal 实例参数)`（T3 改→home 传参）逐字对合；T4 内 goal-sheet 与 water 卡同任务闭环（拆分债已在 Interfaces 裁定合并）。
