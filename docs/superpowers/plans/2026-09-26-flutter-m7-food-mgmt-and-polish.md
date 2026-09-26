# 食光 Flutter M7（食物库管理+日期导航+乐观体验+卫生批）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 把 H5 存量功能（日期导航/食物库管理/目标体重编辑/实际缺口）与乐观体验（运动 temp 行/水卡跨日）补齐进 Flutter 端，并清掉 M6 终审卫生债，交付 2.5.0+20500。

**Architecture:** 新增共享日期状态 `plateDateProvider` 作首页/记录页唯一日期源；运动链从「函数式 FutureProvider+await」升级为「AsyncNotifier.family+乐观 temp」；水卡以 per-date override family 根治跨日遮蔽；食物库管理/目标体重为「我的」页两弹层，全部走既有云路由（零云改动）。

**Tech Stack:** Flutter 3.47.5 / Dart 3.13.4 / flutter_riverpod 3.4.3（AsyncNotifierProvider.family）/ Dio / SharedPreferences；H5 契约 fixture 双端锁。

**Spec:** `docs/superpowers/specs/2026-09-26-flutter-m7-food-mgmt-and-polish-design.md`（本计划逐条论证于它，先读 spec 再读本计划）

## Global Constraints

- 行为权威源=H5 `js/app.js`（行号以 spec 实读为准）；**数据行为 bug-for-bug 逐字对齐**，文案含标点/空格/en-dash 逐字；视觉层按 R4 长期令可创新，每批 UI 改动收官前模拟器目检。
- **红线：`HealthyDiet/cloudfunctions/` 与 `js/`、`index.html` 零改动**（唯一例外：contract fixture `contract/fixtures/diet-core.json` 双端账本可加条目）。
- 静态分析只用 `dart analyze lib test`（flutter analyze 中文路径必崩）；构建/测试判定看真实 exit code，禁管道吞码；每条 shell 前置 `export PATH="$PATH:/c/flutter/bin"; export PUB_HOSTED_URL=https://pub.flutter-io.cn; FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn`（后者 export）。
- widget 测试必须挂 `shiguangTheme()` 真主题；首页/我的页卡高基线断言改动时**重钉基线并同步注释**（profile_reminders_test:171 警示）。
- 版本方案：`2.5.0+20500`（build=major*10000+minor*100+patch）；release 构建走 ASCII 沙盒 `C:\sg-rel-build`（中文路径 gen_snapshot 必挂，见 skill flutter-windows-cn-path-playbook），产物拷回、密钥副本用后即删。
- 每任务结束：`dart analyze lib test` 0 issues + `flutter test` 全绿 + 单独 commit（中文 conventional 消息，风格照 `git log --oneline -5`）。
- 「约消耗」字样**不存在于运动列表渲染**（实读 app.js:1740-1754 统一 `-${kcal} kcal`）——凡简报/注释出现该词按实源纠正。

## 文件结构（本计划触碰面）

```
ShiguangFlutter/lib/
  features/home/home_controller.dart      # T1 plateDateProvider；T3 waterOverrideProvider
  features/home/home_screen.dart          # T1 plate-head+问候头+五卡日期接线；T3 水卡消费点
  features/home/advice_card.dart          # T1 日期源切换；T8 ??55 收口
  features/home/water_card.dart           # T3 override family 化
  features/home/plate_ring.dart           # 不动（已是实例参数）
  features/exercise/exercise_controller.dart  # T2 Notifier 化重写
  features/exercise/exercise_sheet.dart   # T2 保存链改接 notifier
  features/record/record_screen.dart      # T6 7 天行
  features/profile/profile_screen.dart    # T4 食物库入口卡；T5 目标体重入口
  features/profile/food_lib_sheet.dart    # T4 新建：管理弹层（双 tab）
  features/profile/goal_edit_sheet.dart   # T5 新建：目标体重弹层
  features/profile/body_profile_card.dart # T5 setGoal 双 try 拆分；T7 代谢卡缺口消费点
  features/profile/profile_providers.dart # T7 actualDeficitProvider；T8 foodFreq 分账号
  domain/deficit.dart                     # 不动（算法已移植完）
  domain/food_freq.dart → features/record/food_freq.dart 实际路径为准  # T8 prefs 键分账号
  data/health_api.dart                    # T4 四方法；T5 setGoal 可选键签名
  data/api_client.dart                    # 不动
ShiguangFlutter/test/                     # 各批对应测试文件 + stub_health_api.dart 补桩
contract/fixtures/diet-core.json          # T4 路由锁条目
```

---

### Task T1: 首页日期状态机 + plate-head ‹› + 问候头

**Files:**
- Modify: `ShiguangFlutter/lib/features/home/home_controller.dart`（+plateDateProvider）
- Modify: `ShiguangFlutter/lib/features/home/home_screen.dart`（plate-head 行、五卡日期源、问候头）
- Test: `ShiguangFlutter/test/home_plate_date_test.dart`（新建）、既有 `home_screen_test.dart`/`advice_card_test.dart`/`home_exercise_test.dart` 消费点跟改

**Interfaces:**
- Produces：`plateDateProvider: StateProvider<String>`（初值 `todayIso()`）；`String plateDateLabelOf(String date)`（三态文案）；`Future<void> shiftPlateDate(WidgetRef ref, int dir, void Function(String) toast)`。T3/T6 消费 `plateDateProvider`。
- Consumes：`todayIso()`（domain/dates.dart）、`dateLabelOf`。

- [ ] **Step 1: 写失败测试（三态文案+未来闸+› 隐藏）**

```dart
// home_plate_date_test.dart 关键断言（挂 shiguangTheme + healthApiProvider override 桩）：
// ① 初值今天：胶囊文本 '今天' 且含 '· 右滑看历史'；› 按钮 Visibility.hidden（保位）
// ② 点 ‹ 一次：文本 '昨天' 含 M/D 小字；summaryProvider(昨天) 被请求（桩 date 序列断言）
// ③ 点 › 回今天；再点 ›（已在今天）：toast「已经到今天了」且日期不变、零请求
// ④ 往前 8 天：文本 'M月D日' + '周X'（weeks 表逐字）
```

- [ ] **Step 2: 跑红** `flutter test test/home_plate_date_test.dart` → 编译失败（provider 不存在）即预期。

- [ ] **Step 3: 实现**

home_controller.dart 追加：

```dart
/// 首页/记录页共享日期（≙ H5 state.date，app.js:215-224）。初值=今天；
/// 跨午夜不自愈 ≙ H5 仅交互时重算 todayIso()（同款行为，登记不修）。
final plateDateProvider = StateProvider<String>((ref) => todayIso());
```

home_screen.dart：plate-head 行 = `Row[TextButton('‹'), 胶囊(Text+small), AnimatedOpacity/Visibility(›)]`；`_onShift(dir)` ≙ shiftDate：`next > todayIso()` → toast「已经到今天了」return；否则 `ref.read(plateDateProvider.notifier).state = next` + `ref.invalidate(summaryProvider(date))` 族（各 family provider 随 watch 自动重取，**不手动并行拉取**）。问候头：`renderGreeting` ≙ :287-294 五档逐字 + `nickname ? '$greet，$nickname' : greet`，下挂 `M月D日 · 星期X`（恒 `DateTime.now()`，**不 watch plateDateProvider**）。

- [ ] **Step 4: 五卡日期源切换**：`final date = ref.watch(plateDateProvider);` 替换 home_screen 内 `todayProvider` 消费点（环/水/运动/建议/三餐卡构造参数）；卡题「今日运动」vs「运动 · {dateLabel}」两支已在（:554-556），核对其吃 plate 日期。

- [ ] **Step 5: 跑绿 + 全量** `dart analyze lib test` && `flutter test`（既有卡高基线若变，重钉并更新注释——预期首页变高 +问候头）。

- [ ] **Step 6: 模拟器目检（R4）**：`flutter run -d emulator-5554` 或装 debug 包，‹› 走 3 天截图核文案/隐藏态/问候头。

- [ ] **Step 7: Commit** `feat: M7-T1 首页日期状态机+plate-head ‹› 导航+问候头（未来闸/三态文案逐字 H5）`

---

### Task T2: 运动 ExercisesNotifier 化 + 乐观 temp 行（R4 差异 #1/#2 退役批）

**Files:**
- Modify: `ShiguangFlutter/lib/features/exercise/exercise_controller.dart`（重写为 Notifier）
- Modify: `ShiguangFlutter/lib/features/exercise/exercise_sheet.dart`（保存链改接）
- Modify: `ShiguangFlutter/lib/features/home/home_screen.dart`（删除链改接 notifier.remove）
- Test: `exercise_sheet_test.dart`/`home_exercise_test.dart`/`account_switch_cache_test.dart` 迁移 + 新 temp 行为钉

**Interfaces:**
- Produces：`exercisesProvider: AsyncNotifierProvider.family<ExercisesNotifier, List<Map<String, dynamic>>, String>`；`ExercisesNotifier.add(Exercise lib, num amount, num kcal, void Function(String) toast)`、`ExercisesNotifier.remove(Map<String,dynamic> rec, void Function(String) toast)`；`exerciseKcalProvider`（签名不变，fold 含 temp）。
- Consumes：T1 无（date 由调用方传）。保留顶层 `addExerciseRecord/deleteExerciseRecord` 兼容壳（内部转调 notifier，测试改动面最小）。

- [ ] **Step 1: 写失败测试（temp 行为四钉）**

```dart
// ① 保存即态：gate 挂住 addExercise → 点保存后列表已含新行（kcal 客户端值）、
//    合计已涨、toast「已记录跑步 · 消耗 345 kcal」已弹、层已关（全部零等待）
// ② 成功回包：gate 放行 → notifier 重取（桩可让回包后列表含真 id 行），temp 被真值替换
// ③ 失败回滚：addExerciseError → temp 摘除、合计扣回、toast「记录失败：boom」
// ④ rep 型 temp：key=pushup 保存 → temp 行含 createdAt(now) → isRepRecord 生效
//    显示「10 次」；重取后（云无 createdAt）回退「10 分钟」——H5 同款退化钉死
```

- [ ] **Step 2: 跑红**（行为不符）。

- [ ] **Step 3: 重写 exercise_controller.dart**

```dart
class ExercisesNotifier extends FamilyAsyncNotifier<List<Map<String, dynamic>>, String> {
  @override
  Future<List<Map<String, dynamic>>> build(String date) async {
    final list = await ref.watch(healthApiProvider).getExercises(date);
    return list.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(growable: false);
  }

  /// ≙ app.js:1807-1830：temp 即插（:1813 逐字段，id='tmpx_<ms>'、createdAt=now）
  /// → 合计含 temp → 即弹 toast（:1818，不等回包）→ await → 成功重取/失败摘+扣+「记录失败：」
  Future<void> add(Exercise lib, num amount, num kcal, void Function(String) toast) async {
    final temp = <String, dynamic>{'id': 'tmpx_${DateTime.now().millisecondsSinceEpoch}',
      'key': lib.key, 'name': lib.name, 'emoji': lib.emoji,
      'amount': amount, 'unit': lib.unit, 'kcal': kcal, 'createdAt': DateTime.now().millisecondsSinceEpoch};
    final prev = state.valueOrNull ?? const <Map<String, dynamic>>[];
    state = AsyncData([...prev, temp]);                       // ≙ :1814 push
    toast('已记录${lib.name} · 消耗 $kcal kcal');              // :1818 即弹
    try {
      await ref.read(healthApiProvider).addExercise({...temp, 'date': arg});
      state = AsyncData(await ref.read(exercisesProvider(arg).future)); // ≙ loadExercises()
    } catch (e) {
      state = AsyncData(prev);                                // :1826 摘 temp
      toast('记录失败：${jsOr(e is ApiException ? e.message : '', '网络异常')}'); // :1828
    }
  }
  // remove ≙ deleteExerciseById :1831-1852：乐观删+扣 → await → 失败回插+「删除失败：msg」
}
final exercisesProvider = AsyncNotifierProvider.family<ExercisesNotifier, List<Map<String, dynamic>>, String>(ExercisesNotifier.new);
```

`exerciseKcalProvider` 保持 fold（temp 天然计入 ≙ `s.exerciseKcal += kcal` :1814）。顶层 `addExerciseRecord/deleteExerciseRecord` 转调 notifier（签名不变）。**R4 差异表 #1/#2 在本批头注登记退役。**

- [ ] **Step 4: 迁移既有测试**（await 时序断言改「即态」；invalidate 计数断言改 notifier 语义）。

- [ ] **Step 5: 全量绿 + 目检 + Commit** `feat: M7-T2 运动链 Notifier 化+乐观 temp 行（保存即显即弹，R4 差异#1#2 退役）`

---

### Task T3: 水卡 per-date override（跨日遮蔽债根治）

**Files:**
- Modify: `home_controller.dart`（+`waterOverrideProvider` family）、`water_card.dart`、`goal_sheet.dart`（invalidate 点）
- Test: `water_card_test.dart` 新增跨日钉

**Interfaces:**
- Produces：`waterOverrideProvider: NotifierProvider.family<WaterOverride, int?, String>`（null=无本地态跟 summary；≙ spec §3.3 精化为轻量 per-date 壳——根治点=隔离+成功回包清 null，Ruling 记计划）
- Consumes：T1 `plateDateProvider`（水卡 date 改 watch 它）。

- [ ] **Step 1: 写失败测试**：今天喝一杯（override=1 杯）→ ‹ 切昨天 → 水卡显昨天 summary（**无 override 泄漏**）→ › 回今天 → 显 override 态；再证「他处 invalidate summaryProvider 后 override 不遮蔽真值」= 撤销/成功回包路径清 null。
- [ ] **Step 2: 跑红。**
- [ ] **Step 3: 实现**：`class WaterOverride extends FamilyNotifier<int?, String> { int? build(String date) => null; void bump(int delta) => state = (state ?? 0) + delta; void clear() => state = null; }`；water_card 的 `_waterOverride` 字段删除改 watch/read 该 provider（date=plate 日期）；成功回包 `clear()`、失败 `clear()`（回滚跟 summary ≙ 现语义不变）。**文案与交互零变更**（M6 逐字面保持，函数体 diff 仅状态搬家）。
- [ ] **Step 4: 全量绿 + Commit** `fix: M7-T3 水卡乐观态 per-date 化——_waterOverride 跨日遮蔽债根治（行为零变更）`

---

### Task T4: 我的食物库管理弹层

**Files:**
- Create: `ShiguangFlutter/lib/features/profile/food_lib_sheet.dart`
- Modify: `data/health_api.dart`（+4 方法）、`profile_screen.dart`（入口钮）、`test/stubs/stub_health_api.dart`（+4 桩）、`contract/fixtures/diet-core.json`（+4 路由锁）
- Test: `food_lib_sheet_test.dart`（新建）

**Interfaces:**
- Produces：`listCustomFoods() → List`、`setCustomFoodMeals(String id, List<String> meals) → Map`、`deleteCustomFood(String id) → Map`、`setHiddenFoods(List<String> ids) → Map`；`openFoodLibSheet(BuildContext)`。
- Consumes：`FoodThumb`、`confirmDeleteExercise` 同族 confirm（新增通用 `confirmSheet` 或复用 record 删餐 confirm 样式，**实现者按现场取最已有件**）。

- [ ] **Step 1: 契约先行**——实读 `index.js:268-341` 后向 fixture 加 4 条（GET/PUT/DELETE `/foods/custom[/:id]`、PUT `/foods/hidden` 回 `{ok,ids}`），双端跑：`node --test "tests/*.test.js"`（H5 侧动态生成自动跟）+ `flutter test test/data/contract_test.dart`。桩四件按云实语义（meals 白名单、裸 id、hidden 全量替换）。
- [ ] **Step 2: 写失败测试（弹层行为十钉）**——双 tab 默认自定义；副文案 `自定义 N 条 · 点餐次标签可改归类` / `内置 N 条 · 已移除 M`；归类点按→`setCustomFoodMeals`+toast `已归到早餐/零食/正餐 · 搜索时只在对应餐次出现`（**lunch/dinner 都走「正餐」文案**，CF_MEAL_MAP 三态实读 :1355-1365）；删除确认「删除自定义食物/删除后不可恢复；已记录的饮食不受影响。」→「已删除」；内置钮 移除⇄恢复 + `已移除「名」/已恢复「名」` + setHiddenFoods 全量 ids 断言；加载失败空态 `⚠️ 加载失败：boom`；**回归钉：管理链路 id 恒裸值（桩断言 bodies 不含 cf_）**。
- [ ] **Step 3: 跑红。**
- [ ] **Step 4: 实现** food_lib_sheet.dart（showModalBottomSheet 大层：head「我的食物库」+✕、seg 双钮、sub 行、列表 ListView）；入口=「我的」页「食物库」soft 钮（≙ index.html:249，位置提醒卡后，R4 定稿）。
- [ ] **Step 5: 全量绿 + 目检（双 tab/弹层/确认框截图）+ Commit** `feat: M7-T4 我的食物库管理弹层——自定义归类/删除+内置移除恢复，4 路由双端锁`

---

### Task T5: 目标体重编辑弹层 + setGoal 双 try 收口

**Files:**
- Create: `ShiguangFlutter/lib/features/profile/goal_edit_sheet.dart`
- Modify: `data/health_api.dart`（setGoal 改可选键签名）、`body_profile_card.dart`（saveBodyProfile 拆两 try）、`profile_screen.dart`（入口「点击修改」）
- Test: `goal_edit_sheet_test.dart`（新建）、`body_profile_card_test.dart`（文案分流断言）

**Interfaces:**
- Produces：`HealthApi.setGoal({num? dailyKcal, num? targetWeight})`（null 键剥离 ≙ js 序列化语义；现调用点同步改具名）；`openGoalEditSheet(BuildContext, WidgetRef)`。
- Consumes：`profileProvider`、`jsNumber`（输入解析 ≙ Number() 全串，M6 终审 I1 口径）、`jsOr`。

- [ ] **Step 1: 写失败测试**——预填 `profile.goal.targetWeight ?? 55`；±0.5 `+(x∓0.5).toFixed(1)`；顶格 `最小 30 kg`/`最大 150 kg` toast 值不动；hint 逐字 `体重范围 30–150 kg · 点数字可直接输入 · 热量目标由系统按档案自动计算`；保存→`setGoal(targetWeight: x)` 单键 body 断言→invalidate profileProvider→关层→toast「目标体重已更新」；失败「保存失败：boom」层不关；**收口钉**：saveBodyProfile 中 updateProfile 成功+setGoal 抛错 → toast 含「目标同步失败」非「保存失败」。
- [ ] **Step 2: 跑红 → 实现（弹层结构抄 goal_sheet.dart 同族：stepper+输入+保存通栏）→ 全量绿。**
- [ ] **Step 3: 目检 + Commit** `feat: M7-T5 目标体重编辑弹层（±0.5 闸 30-150 逐字）+ setGoal 失败文案收口（双 try 分流）`

---

### Task T6: 记录页 7 天日期行

**Files:**
- Modify: `record_screen.dart`（顶部 chip 行 + 列表 date 源）
- Test: `record_flow_test.dart` 追加

**Interfaces:**
- Consumes：`plateDateProvider`（T1）、`dateLabelOf`。

- [ ] **Step 1: 写失败测试**——7 chip（今天往前、末位「今天」，≙ :498-508）；点击第 3 个 → `plateDateProvider` 值=对应日期、`recordsProvider(date)` 请求断言；**共享日期回归钉**：记录页选日后 pump 回首页 tab，餐盘停同一天（H5 全局 state.date 行为）；选中态高亮唯一。
- [ ] **Step 2: 跑红 → 实现（横向 ListView/Row+Wrap 按现场宽度，chip 视觉 R4）→ 全量绿 → 目检 → Commit** `feat: M7-T6 记录页 7 天日期行（与首页共享 plateDateProvider，H5 全局日期行为照抄）`

---

### Task T7: actualDeficit 近 7 天实际缺口接线

**Files:**
- Modify: `profile_providers.dart`（+actualDeficitProvider）、`body_profile_card.dart`（代谢卡消费点，删「恒 null 降级」注记）
- Test: `body_profile_card_test.dart` 追加 + 新建 provider 单测

**Interfaces:**
- Produces：`actualDeficitProvider: AsyncNotifier<Map<String, Object>?>`（值 ≙ deficit.dart 的 `{avgDeficit, days, tdee}` 或 null）；prefs 键 `sg_actual_deficit_<uid>`（逐字 ≙ H5 localStorage，跨栈对齐）。
- Consumes：`getDailySummary(date)`/`getExercises(date)`（已有）、`computeMetabolism`（domain 已移植，实读核函数名）、`profileProvider`。

- [ ] **Step 1: 写失败测试**——6 天历史逐日双请求（桩 bodies 断言日期序列=昨..-6，**不含今天**）；单日失败 `.catch(()=>null)` 跳过不整体挂；`≥2 天` 闸（1 天有记录→null 走预设缺口）；今日实时行并入（≙ :1520-1549 实读结构）；缓存命中先显旧值再后台刷新、写回 prefs；代谢卡文案 `近N天均值(消耗−摄入)`（:1601 逐字）+ note（:1604）。
- [ ] **Step 2: 跑红 → 实现 → 全量绿。**
- [ ] **Step 3: Commit** `feat: M7-T7 actualDeficit 接线——6 天历史+今日实时、prefs 缓存跨栈对齐、代谢卡缺口脱敏降级`

---

### Task T8: C 卫生批（终审 Minor 清账）

**Files / 逐项:**
1. `advice_card.dart`：`?? 55` → falsy 口径 `(w is num && w != 0) ? w : 55`（≙ `||55`，终审 Minor-2 销账）。
2. `home_screen.dart:114`：建议卡不渲染时 `SizedBox(sp3)` 空档——间距移入卡体条件构造（Minor-3）。
3. `stub_health_api.dart`：amount 非 num 宽容度、kcal 上界对齐云（T1 deferred 销账）+ fixture `$comment` 追 M7 说明。
4. `home_screen_test.dart`：裸 `MaterialApp` 改挂 `shiguangTheme()`（终审复核点名面）。
5. `scale_service.dart` :224/:282 孤儿 close。
6. `food_freq.dart`：prefs 键分账号 `sg_food_freq_counts_<uid>`——**不迁移旧键**（ensureLoaded 30 天回填机制可重建，迁移属 YAGNI；注销旧键+注释登记）。
7. `_metaOf` repUnit 兜底（Minor-4）：**不改码**，注释改「书面销账：H5 该位 TypeError，生产不可达，保留防御」。

- [ ] **Step 1:** 每项先补/改对应断言再改码（1/3/6 各 1 例）。
- [ ] **Step 2:** `dart analyze` + `flutter test` 全绿（卡高基线若动重钉）。
- [ ] **Step 3:** Commit `fix: M7-T8 卫生批——终审 Minor 清账（??55 收口/空档/sp3 卡体/桩宽容度/真主题/孤儿 close/freq 分账号）`

---

### Task T9: 收官——2.5.0 四门禁+正式包+目检链+真机验收单

- [ ] **Step 1:** `pubspec.yaml` → `2.5.0+20500`；`npm run check:version` 双验。
- [ ] **Step 2:** 四门禁：`dart analyze lib test` 0 / `flutter test` 全绿报数 / `node --test "tests/*.test.js"` 全绿（fixture 新增条数计入）/ check:version 过。
- [ ] **Step 3:** ASCII 沙盒 release：拷 `ShiguangFlutter`+key 材料 → `C:\sg-rel-build` → `flutter build apk --release --split-per-abi` → arm64 产物拷回更名 `食光Flutter-v2.5.0.apk` 入库、v2.4.0 出库（`git rm`）；`apksigner verify` CN=Shiguang；**沙盒（含密钥副本）用后即删并验证不存在**。
- [ ] **Step 4:** 模拟器 x86_64 全链目检（R4）：日期导航/问候头/记运动 temp/水卡跨日/食物库双 tab/目标体重弹层/7 天行/代谢卡缺口——逐屏截图 `.mimosa/m7t9/`。
- [ ] **Step 5:** 真机验收单 `task-9-report.md`：卸 debug→装 v2.5.0 arm64→上述上手项+M6 遗留运动异常复测项（工单进展核信）+秤通知回归。
- [ ] **Step 6:** 清理调试产物、台账/progress.md 归集、Commit `build: M7 收官——2.5.0+20500 四门禁绿，食光Flutter-v2.5.0 正式包入库`

---

## Self-Review 记录（撰写时三查）

1. **Spec 覆盖**：§3.1→T1/T3/T6；§3.2→T2；§3.3→T3；§3.4→T7；§4.1-4.4→T1/T4/T5/T6；§5→T4/T5 契约步；§6→各批头注+T8；§7→Global Constraints+T9；§8 验收 7 条↔T1-T9 一一对上。无缺口。
2. **占位符**：无 TBD；「实现者按现场取最已有件」（T4 confirm）与「实读核函数名」（T7 computeMetabolism）为**指路实读**非占位——执行时以读码补全，符合本仓简报纪律。
3. **类型一致性**：`plateDateProvider`(T1)↔T3/T6 消费同名；`setGoal({num? dailyKcal, num? targetWeight})`(T5) 与 M5 既有调用点 `setGoal(suggest, target)` 位置参**不兼容——T5 Step2 必须跟改 M5-T6 调用点**（已在 T5 Files 列 body_profile_card）；`jsOr/jsNumber` 为 M6 已入库符号；`ExercisesNotifier.add` 参数含 kcal（kcal 计算留 sheet/兼容壳，≙ M6 现结构）。
