# Flutter M3 报告图表与动效 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 ShiguangFlutter/ 上交付报告页（周/月柱状图+达标统计+期间建议+体重趋势线）与首页营养餐盘环动画，并核销 M2 终审 I1（会话过期回登录）——验收标准 = 真机手感对比 v1.3.1 **体验反超 H5**（老大上手不满意不算过）。

**Architecture:** 延续 M2 分层：domain 纯 Dart（报告解析/日均/建议引擎，可脱离 flutter 单测）→ data（HealthApi 增 3 个只读方法，契约 fixture 双端共用）→ features（柱状图=widget+Tween，趋势线/餐盘环=纯几何函数+CustomPainter）。I1 在 data 层加会话过期回调、app 层接线 authState。

**Tech Stack:** Flutter 3.47.5 / Dart 3.13.4、flutter_riverpod（family/autoDispose 沿用 M2 模式）、CustomPainter + TweenAnimationBuilder。**不引入 fl_chart**（见 Global Constraints 裁定 R1）。

**Spec:** `docs/superpowers/specs/2026-09-25-flutter-rewrite-design.md`（M3 行：热量环进度动画、柱状图点击浮出数值、体重趋势线、PageView 滑切 Tab——最后一项 M1 已有，纳入演示验收）

**上游账本（必读）:** `.superpowers/sdd/2026-09-25-flutter-m2-network-domain/progress.md` —— 终审 I1 定义与 4 条缓办 Minor 在此。本计划认领：I1（Task 1）、首页加载/空态（Task 7）、记录取整口径（Task 8）、契约测试局限（Task 2 维持现状并登记）；**addWater UTC 兜底不认领**（当前无调用方，属潜伏，留账本）。

---

## Global Constraints

- **云函数 api-diet 一行不改**（硬约束）。所有请求走单入口信封：POST `https://cloud1-d6g4x9h9m507b429c.api.tcloudbasegateway.com/v1/functions/api-diet`，body `{path, method, params, body||{}}`，`Bearer = accessToken 否则 PUBLISHABLE_KEY`。M3 三个新路由均为**只读 GET**（信封内 method 字段为 'GET'）。
- 报告路由与响应形状（逐字抄自 `HealthyDiet/cloudfunctions/api-diet/index.js:462-546`，实现者须读源核对）：
  - `/report/week` GET `params:{offset}` → `{days:["一"…"日"], kcal:int[7], target:int, rates:{carb,protein,fat}}`；`rates = Math.min(100, Math.round(日均/目标*100))`，目标 = `dailyKcal×50/25/25÷(4/4/9)` 取整。
  - `/report/month` GET `params:{offset}` → `{weeks:["W1"…], kcal:[各周记录日均], target, days:int(有记录天数), total:int, rates:{…}, isWeek:false}`。
  - `/report/weight-trend` GET `params:{}` → 有日志取最近 7 条 `{points:[kg], labels:["M.D"…]}`；无日志返回 7 个重复当前体重+labels。`bodyFat/muscle` 字段存在但**忽略**（v1.3.1 起体成分整体下线，别再引入）。
- **裁定 R1（偏离 spec 选型表，老大过目）**：spec 技术选型写"fl_chart+CustomPainter"，但 M3 里程碑行本身写 CustomPainter；两张图几何简单（7 柱、单折线），纯函数+CustomPainter 可逐点单测、少一个依赖 → **M3 全程不用 fl_chart**。
- **裁定 R2（bug-for-bug 兼容）**：云端 rates 封顶 100 ⇒ H5 `buildPeriodAdvice` 的 `carb>110`/`fat>110` 分支在真实数据下永不触发。移植**逐字保留**这些规则（双栈行为一致优先），不许"顺手修正"。
- 首页餐盘环预算 = `target + exerciseKcal`；**运动打卡不在 M3**（H5 的 `/diet/exercises` 未移植），Flutter 侧 `exerciseKcal` 恒传 0 并在代码注释登记"M4+ 接运动打卡后启用"。板块日期切换（‹ ›）、喝水卡、"我的"页同样不在 M3 范围。
- domain 纯净铁律：`lib/domain/**` 禁止 import flutter（purity_test 守卫已在线）。
- 工具链（每台机器命令必带）：`export PATH="$PATH:/c/flutter/bin"`；**分析用 `dart analyze`（flutter analyze 在中文路径崩溃）**；`flutter test` 可直接跑；`flutter_test` 不导出 material——测试文件须显式 `import 'package:flutter/material.dart';`。
- 契约 fixture 红线：真实 uid `u_7f88ac7026f0ab562f1e0f75` 与真实凭证不得进入任何 fixture/测试；样本一律脱敏（`u_test`/`rec_test_*`）。
- 版本：M3 收官时 `ShiguangFlutter/pubspec.yaml` 升 `2.1.0+20100`（build=major*10000+minor*100+patch，check:version 门禁会算）。
- CSS 唯一事实源：所有颜色/圆角/时长以 `css/design-tokens.css`、`css/screens.css` 现值为准，Flutter 侧只允许引用 `lib/app/theme.dart` Tokens（缺的令牌在 T4 补）。

**文件结构总览（先定后拆）：**

| 动作 | 文件 | 职责 |
|---|---|---|
| Modify | `ShiguangFlutter/lib/data/api_client.dart` | 增 `onSessionExpired` 回调（I1） |
| Modify | `ShiguangFlutter/lib/app/auth_state.dart` | 增 `forceAnon()`（I1） |
| Modify | `ShiguangFlutter/lib/main.dart` | 组合根接线回调→authState（I1） |
| Modify | `ShiguangFlutter/lib/data/health_api.dart` | +getWeekReport/getMonthReport/getWeightTrend |
| Modify | `contract/fixtures/diet-core.json`、`tests/contract.test.js`、`ShiguangFlutter/test/data/contract_test.dart` | +3 只读路由双端契约 |
| Create | `ShiguangFlutter/lib/domain/report.dart` | 报告解析模型+avgRecorded+periodAdvice（纯） |
| Test | `ShiguangFlutter/test/domain/report_test.dart` | 上者的全部单测 |
| Create | `ShiguangFlutter/lib/features/report/report_controller.dart` | range 状态+三个 FutureProvider |
| Create | `ShiguangFlutter/lib/features/report/report_screen.dart` | 报告页骨架（segmented/卡片/错误重试） |
| Create | `ShiguangFlutter/lib/features/report/week_chart.dart` | 柱状图 widget（动画+点击气泡） |
| Create | `ShiguangFlutter/lib/features/report/weight_trend.dart` | 趋势几何纯函数+CustomPainter |
| Create | `ShiguangFlutter/lib/features/home/plate_ring.dart` | 餐盘环 CustomPainter+数字滚动 |
| Modify | `ShiguangFlutter/lib/features/home/home_screen.dart` | 换掉 CircularIndicator 占位；加载/空态区分（终审 Minor M1） |
| Modify | `ShiguangFlutter/lib/app/shell.dart` | 报告 tab 占位→ReportScreen |
| Modify | `ShiguangFlutter/lib/features/record/record_screen.dart` | 餐次合计取整口径（终审 Minor M2） |
| Modify | `ShiguangFlutter/lib/app/theme.dart` | 缺的令牌（nutrient 色已有，补图表用色） |
| Test | `ShiguangFlutter/test/report_screen_test.dart`、`test/weight_trend_test.dart`、`test/plate_ring_test.dart`、`test/auth_expiry_test.dart` | 各任务 UI/几何测试 |

---

### Task 1: I1——会话过期自动回登录（终审 Important，M3 首位）

**Files:**
- Modify: `ShiguangFlutter/lib/data/api_client.dart`（401 终判处，现约 :108 附近"清 token + 抛登录已过期"）
- Modify: `ShiguangFlutter/lib/app/auth_state.dart`
- Modify: `ShiguangFlutter/lib/main.dart`
- Test: `ShiguangFlutter/test/auth_expiry_test.dart`（新建）、`ShiguangFlutter/test/data/api_client_test.dart`（追加）

**Interfaces:**
- Consumes: `ApiClient`（M2 T5 产物，`_inFlight` 单飞续期）、`authStateProvider`（`AuthStatus{unknown,authed,anon}`）
- Produces: `ApiClient({…, void Function()? onSessionExpired})`；`AuthStateNotifier.forceAnon()`。Task 7/8 不依赖本任务。

- [ ] **Step 1: 写失败测试（api_client 层）** — 在 `test/data/api_client_test.dart` 追加（沿用该文件现有 stub Dio/tokenStore 模式）：

```dart
test('续期失败清 token 时触发 onSessionExpired（且只触发一次）', () async {
  var fired = 0;
  // 构造：token 存在但 refresh 返回 401、业务请求返回 401 → 终判过期
  final c = ApiClient(store: storeWithToken(), dio: dio401Always(),
      onSessionExpired: () => fired++);
  await expectLater(c.call('/diet/summary', 'GET', params: {'date': '2026-09-25'}),
      throwsA(isA<ApiException>().having((e) => e.message, 'message', '登录已过期，请重新登录')));
  expect(fired, 1);
  expect(await store.read(), isNull); // token 已清
});
```

- [ ] **Step 2: 跑测试确认失败** — Run: `cd ShiguangFlutter && flutter test test/data/api_client_test.dart` → Expected: FAIL（构造参数不存在，编译错即算红）。
- [ ] **Step 3: 实现 api_client** — 构造函数增可选 `this.onSessionExpired`（字段 `final void Function()? onSessionExpired;`）。在**续期失败/无 refreshToken → 清 token 并抛"登录已过期，请重新登录"**的那一处（读现码定位，全文件应只有这一处清 token+抛该文案）紧挨 clear 之后 `onSessionExpired?.call();`。并发多个 401 都汇到同一单飞失败路径，各触发一次可接受（forceAnon 幂等），但**同一请求只触发一次**（不在别处重复 call）。
- [ ] **Step 4: auth_state 增 forceAnon** — `AuthStateNotifier` 加：

```dart
/// I1：ApiClient 会话过期清 token 后调用，跳过 bootstrap 直接回登录页
void forceAnon() => state = AuthStatus.anon;
```

- [ ] **Step 5: main.dart 接线** — 组合根现在是 `ProviderScope(overrides:[…])` 内联构造 ApiClient。改为先建 container 再回填（`late final` 断环）：

```dart
late final ProviderContainer container;
final apiClient = ApiClient(
  tokenStore: tokenStore,
  onSessionExpired: () => container.read(authStateProvider.notifier).forceAnon(),
);
container = ProviderContainer(overrides: [ /* 现有 overrides 原样，apiClientProvider 用上面实例 */ ]);
```

若现码 ApiClient 构造在 overrides 列表字面量内部，把它提到 container 之前即可；不改其它 override 语义。
- [ ] **Step 6: 写失败测试（widget 层）** — `test/auth_expiry_test.dart`：

```dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/auth_state.dart';
import 'package:shiguang_flutter/app/shell.dart';
// stub：自建 ApiClient（tokenStore=内存有 token、dio 恒 401 且 refresh 恒 401），
// overrides: apiClientProvider → 该实例；authStateProvider → 恒 authed（模拟"已登录在 Shell 内"）。
// 动作：进 Shell 首页触发 summary 请求（stub 必过期）→ await pumpAndSettle。
// 断言：find.byType(LoginScreen) 存在、Shell 不存在；authStateProvider == AuthStatus.anon。
```

（实现者注：LoginScreen 类名/独有文案以 `lib/features/auth/login_screen.dart` 现码为准，断言选登录页**唯一**控件，避免 find.text 歧义——M1 计划评审立过此规；`test/stubs/` 已有内存 TokenStore 桩可复用。）
- [ ] **Step 7: 跑全部相关测试确认绿** — Run: `cd ShiguangFlutter && flutter test test/data/api_client_test.dart test/auth_expiry_test.dart` → PASS。
- [ ] **Step 8: analyze + 提交**

```bash
cd ShiguangFlutter && dart analyze lib test   # 0 issue
git add ShiguangFlutter && git commit -m "fix: I1 会话过期自动回登录——ApiClient 过期回调接 authState（M2 终审 Important 核销）"
```

---

### Task 2: 报告数据层——HealthApi 三只读方法 + 契约 fixture 双端加路由

**Files:**
- Modify: `ShiguangFlutter/lib/data/health_api.dart`
- Modify: `contract/fixtures/diet-core.json`、`tests/contract.test.js`、`ShiguangFlutter/test/data/contract_test.dart`
- Test: 上述两个契约测试文件即载体

**Interfaces:**
- Consumes: `ApiClient.call(path, method, {params})`（返回 Map）与 `callValue`（返回原始结构，M2 T6 产物）
- Produces（Task 3/4/6 消费，签名精确）:
  - `Future<Map<String, dynamic>> getWeekReport({int offset = 0})`
  - `Future<Map<String, dynamic>> getMonthReport({int offset = 0})`
  - `Future<Map<String, dynamic>> getWeightTrend()`

- [ ] **Step 1: fixture 增 3 条只读路由** — 读 `contract/fixtures/diet-core.json` 现有条目格式，追加（样本值从云函数返回代码**归纳**，与现有条目一致不实测写路由；GET 只读路由允许照现有 `/diet/summary` 条目的脱敏样本风格手写）：`/report/week`（days/kcal[7]/target/rates 三键）、`/report/month`（weeks/kcal/target/days/total/rates/isWeek:false）、`/report/weight-trend`（points/labels）。响应样本不含 uid。
- [ ] **Step 2: H5 契约测试加断言** — `tests/contract.test.js` 的 ROUTES 表加 3 条（method:'GET'，断言字段集与 fixture 一致）。Run: `node --test tests/contract.test.js` → 先红（fixture 未对齐时）后绿。
- [ ] **Step 3: Dart 契约测试加断言** — `test/data/contract_test.dart` 对应路由表加 3 条（沿用现有"fixture 自洽 + 请求侧对齐"两级断言；登记已知局限：核不了云端 schema 变更——终审 Minor M3，维持现状即可）。Run: `cd ShiguangFlutter && flutter test test/data/contract_test.dart` → PASS。
- [ ] **Step 4: 写失败测试（health_api）** — 新建或追加 `test/data/health_api_report_test.dart`：stub Dio 断言发出的信封 `{path:'/report/week', method:'GET', params:{offset:1}, body:{}}`；三方法各一条 + offset 缺省 0 一条。
- [ ] **Step 5: 实现三方法**（对齐 health_api.dart 现有方法的调用风格）：

```dart
/// GET /report/week —— 本周（周一起）7 天柱状 + 达标率。offset 往回推周数。
Future<Map<String, dynamic>> getWeekReport({int offset = 0}) =>
    Map<String, dynamic>.from(await _api.call('/report/week', 'GET', params: {'offset': offset}));
// getMonthReport 同型（'/report/month'）；getWeightTrend → _api.call('/report/weight-trend', 'GET', params: {})
```

（若 `call` 对非 Map 响应抛错/需要 `callValue`，以 M2 实际实现为准——这三条响应都是对象，`call` 即可。）
- [ ] **Step 6: 跑测试 + analyze + 提交**

```bash
cd ShiguangFlutter && flutter test && dart analyze lib test
git add . && git commit -m "feat: 报告数据层——getWeekReport/getMonthReport/getWeightTrend + 契约 fixture 双端加 3 只读路由"
```

---

### Task 3: domain——报告模型/日均/期间建议（纯 Dart，逐字移植）

**Files:**
- Create: `ShiguangFlutter/lib/domain/report.dart`
- Test: `ShiguangFlutter/test/domain/report_test.dart`

**Interfaces:**
- Consumes: `jsRound`（`lib/domain/js_compat.dart`，Math.round 等价）
- Produces（Task 4/5 消费）:

```dart
class ReportData {            // 周/月统一模型
  final List<String> labels;  // 周: days["一"…"日"]；月: weeks["W1"…]
  final List<int> kcal;
  final int target;
  final int carbRate, proteinRate, fatRate;
  final bool isWeek;          // 月报 false
  final int recordedDays;     // 月报 days；周报= kcal 中 >0 计数
  final int total;            // 月报 total；周报= kcal.fold(sum)
  final String? avgText;      // 月报注入"月均 X kcal · 记 N 天"；周报 null
}
ReportData parseWeekReport(Map<String, dynamic> m);
ReportData parseMonthReport(Map<String, dynamic> m);
int avgRecorded(List<int> kcal);                       // 日均：只算 >0 天，分母 ||1，jsRound
String periodAdvice(ReportData r, int avgKcal);        // 5 规则 top3 '；'拼+'。'
int weekTodayIndex(DateTime now);                      // 周一=0…周日=6（getDay 换算）
```

- [ ] **Step 1: 写失败测试** — `test/domain/report_test.dart` 至少覆盖：
  - `avgRecorded([0,100,200]) == 150`、`avgRecorded([]) == 0`（分母 1）、`avgRecorded([75]) == 75`；小数和用 jsRound（如 `[100,101]`→101? 不——201/2=100.5→Math.round→**101**，锁定 js_compat 行为）。
  - `periodAdvice`：蛋白<80 触发、碳水 60-110 之间不触发、碳水<60 触发、脂肪>110 **在 rates≤100 的真实数据下不可达**（构造 110 边界样本各一条，登记 R2）、日均超目标/低于 0.7×目标、全不触发→兜底句、超 3 条截断且以"。"结尾。
  - `parseWeekReport`：fixture 样本进、字段全对；`parseMonthReport`：isWeek=false、avgText 由调用方拼（parse 不生成）——月均文案生成放 Task 5 控制器（保持 parse 纯映射）。
  - `weekTodayIndex`：周一 0、周日 6（用 `DateTime(2026,9,21)` 周一起算验证）。
- [ ] **Step 2: 跑测试确认失败** — `cd ShiguangFlutter && flutter test test/domain/report_test.dart`（编译错即红）。
- [ ] **Step 3: 实现** — periodAdvice 逐字移植 `js/app.js:833-843`（文案含数字插值必须逐字一致，如 `蛋白质达标率 ${r.proteinRate}%，偏低，每餐加一份鱼、虾、蛋或豆制品`）；规则顺序不得调换（top3 截断依赖顺序）。parse 函数注意云端 kcal/rates 可能为 num（json 数字），统一 `.round()` 前先过 jsRound 语义（整数直取即可，样本无小数）。
- [ ] **Step 4: 跑测试确认绿 + purity 守卫自动覆盖** — `flutter test test/domain/` 全绿（purity_test 扫 domain 目录，report.dart 不得 import flutter）。
- [ ] **Step 5: 提交** — `git commit -m "feat: domain 报告层——parse/日均/periodAdvice 逐字移植（R2 bug-for-bug 保留 >110 死分支）"`

---

### Task 4: 报告页骨架 + 周柱状图（入场动画 + 点击气泡）

**Files:**
- Create: `ShiguangFlutter/lib/features/report/report_controller.dart`、`report_screen.dart`、`week_chart.dart`
- Modify: `ShiguangFlutter/lib/app/shell.dart`（报告 tab：`PlaceholderScreen('报告（M2 接入）')` → `const ReportScreen()`）
- Modify: `ShiguangFlutter/lib/app/theme.dart`（如缺图表色令牌再补，不新增硬编码）
- Test: `ShiguangFlutter/test/report_screen_test.dart`

**Interfaces:**
- Consumes: `healthApiProvider`（定义在 `lib/features/home/home_controller.dart`，main/测试 override——报告侧直接 `ref.watch` 它）、Task 3 `ReportData/parseWeekReport/avgRecorded/periodAdvice/weekTodayIndex`
- Produces: `reportRangeProvider`（`StateProvider<ReportRange>`，enum{week,month}）、`weekReportProvider`/`monthReportProvider`（`FutureProvider.autoDispose<ReportData>`）、`weightTrendProvider`（本任务先建 week/month 两个，Task 6 加 trend）、`WeekBarChart` widget。

- [ ] **Step 1: 写失败测试** — `test/report_screen_test.dart`（override healthApiProvider 为 stub，样本=fixture 周数据）：
  - 渲染出 7 根柱 + 标题"今日盘子"式页头文案"健康报告"（读 index.html:149-155 取实际页头/segmented 文案逐字）。
  - `find.text('日均 ${avgRecorded(kcal)} kcal')` 出现（`#report-avg` 等价，app.js:804）。
  - 今天柱：`weekTodayIndex` 对应列标签显示"今天"（app.js:799）。
  - 点击第 i 根柱 → 出现气泡 `'${kcal[i]} kcal'`（或"未记录"）；再点同柱 → 消失；点另一柱 → 前者消失后者现（互斥，app.js:823-829）。
  - 超目标柱（kcal>target）与正常柱颜色不同（按 Color 断言：over=Tokens.warn 系，读 css `.col.over .bar` 现值定，screens.css:407-435）。
  - 错误态：stub 抛 ApiException → 显示错误行+重试按钮（沿用首页 M2 模式 `ref.invalidate`）。
- [ ] **Step 2: 跑测试确认失败**。
- [ ] **Step 3: 实现 controller**：

```dart
enum ReportRange { week, month }
final reportRangeProvider = StateProvider<ReportRange>((_) => ReportRange.week);
final weekReportProvider = FutureProvider.autoDispose<ReportData>((ref) async =>
    parseWeekReport(await ref.watch(healthApiProvider).getWeekReport()));
```

- [ ] **Step 4: 实现 WeekBarChart** — 关键几何逐字对齐 app.js:788-800：`max = (kcal.reduce(max) > target ? kcal.reduce(max) : target) * 1.1`；柱高 `h = (kcal / max * 100).clamp(4, 100)`%（**min 4 是 H5 现值**）；目标虚线 `bottom = target / max * 100`%。结构：`SizedBox(height: 140)`（screens.css:407）内 `Stack[目标线 Positioned, Row(7×Expanded 列)]`；每列 = `Column[气泡区, 柱(Align bottom, AnimatedFractionallySizedBox 或 TweenAnimationBuilder 700ms Curves.easeOut——对齐 css `transition: height .7s var(--ease-out)`), 标签]`。柱 `InkWell/GestureDetector` 上报 `onTap(i)`，选中态由父级 `ValueNotifier<int?> _valOn` 持有（互斥+再点收起）。柱圆角 `7 7 3 3`（screens.css:414-417），max-width 22 逻辑像素换算：外层列居中 `ConstrainedBox(maxWidth: 22)`。今天柱渐变+阴影按 css 现值（429-431），色全部走 Tokens。
- [ ] **Step 5: 实现 ReportScreen（周视图部分）** — 页头 + segmented（周/月按钮先只接 week，month 点击 Task 5 接）+ 热量卡（标题行含 `#report-avg` 文本）+ WeekBarChart。**本任务不做统计卡/建议卡/月视图**（下一步）。
- [ ] **Step 6: shell.dart 接线 + 跑测试确认绿**（动画测试注意 `pumpAndSettle` 会等 700ms 柱动画，widget 断言放 settle 之后）。
- [ ] **Step 7: analyze + 提交** — `git commit -m "feat: 报告页骨架+周柱状图——700ms 入场动画、目标虚线、点击互斥气泡（逐字对齐 app.js:788-829）"`

---

### Task 5: 月视图切换 + 达标统计卡 + 期间建议卡

**Files:**
- Modify: `ShiguangFlutter/lib/features/report/report_screen.dart`、`report_controller.dart`
- Test: `ShiguangFlutter/test/report_screen_test.dart`（追加）

**Interfaces:**
- Consumes: Task 2 `getMonthReport`、Task 3 `parseMonthReport/avgRecorded/periodAdvice`、Task 4 `WeekBarChart`（月视图复用，labels=weeks、todayIndex=-1）
- Produces: `monthAvgText(ReportData)`（`月均 X kcal · 记 N 天`，app.js:273 逐字）；月/周 segmented 完整可用。

- [ ] **Step 1: 写失败测试** — 追加：切"月"→ 柱标签变 W1..、无"今天"高亮（todayIndex=-1）、标题行显示 `月均 … kcal · 记 … 天`；建议卡标题"本周建议"↔"本月建议"随 range 切换（app.js:818）；统计卡三张：碳水达标/蛋白达标/脂肪控制 + `${rate}%` + 进度条宽 rate%（app.js:806-815，色 Tokens.nutCarb/nutProtein/nutFat，轨 surfaceSoft）。
- [ ] **Step 2: 跑测试确认失败**。
- [ ] **Step 3: 实现** — controller 加 `monthReportProvider`；screen 的 watch 按 `reportRangeProvider` 分派；`monthAvgText(r) => '月均 ${avgRecorded(r.kcal)} kcal · 记 ${r.recordedDays} 天'`（注意：月均按**周日均数组**算，与 H5 loadMonthReport 同口径——r.kcal 已是各周日均）；统计卡/建议卡按测试断言实现；建议正文 `periodAdvice(data, avgRecorded(data.kcal))`。
- [ ] **Step 4: 跑测试确认绿 + 提交** — `git commit -m "feat: 报告页月视图+达标统计卡+期间建议卡（月均口径=周日均数组，对齐 H5）"`

---

### Task 6: 体重趋势线（纯几何函数 + CustomPainter）

**Files:**
- Create: `ShiguangFlutter/lib/features/report/weight_trend.dart`
- Modify: `report_screen.dart`（体重卡）、`report_controller.dart`（`weightTrendProvider`）
- Modify: `health_api.dart` 已在 Task 2 备好 `getWeightTrend`
- Test: `ShiguangFlutter/test/weight_trend_test.dart`

**Interfaces:**
- Consumes: Task 2 `getWeightTrend`（`{points:[num], labels:[String]}`）
- Produces: `TrendLayout computeTrendLayout(List<double> points)`（纯函数，返回 min/max/各点坐标/网格），`WeightTrendChart` widget，delta 文案函数 `weightDeltaText(List<double> points)`（"当前 X kg · 本周 ±d"，降绿升 warn——app.js:902-904）。

- [ ] **Step 1: 写失败测试（几何）** — 先读 `js/app.js:845-905` 逐行核对常数，断言：绘图区 X0=44,X1=306,Y0=16,Y1=104；值域外扩、**最小跨度 1kg**、0.5 对齐取整（`points=[70,70.2]` → 跨度必须 ≥1 且边界是 0.5 的倍数）；单点特判（画水平单点不除零）；空数据走占位分支（widget 测试断"暂无体重数据"文案，读 app.js:847-851 实际文案逐字）；4 条网格线等分；末点高亮 r=4.2。
- [ ] **Step 2: 跑测试确认失败**。
- [ ] **Step 3: 实现 computeTrendLayout** — 纯 Dart（可 import dart:ui 的 Offset；不在 domain 目录，purity 无关）。X 均分 `(X1-X0)/(n-1)`（n==1 时置 X0+半宽）；Y 线性映射翻转。
- [ ] **Step 4: 实现 WeightTrendChart（CustomPainter）** — 网格（末条实线其余 dash [3,4]，`drawLine`+`PathEffect` 不可用则 `Canvas.drawDashedLine` 手写或 `strokeDash` 用 `Path` 分段——**用 flutter 内置：`Paint` 无 dash，网格虚线用短 Path 循环画，或统一实线并把差异登记为偏差**，以 H5 视觉为准优先手写 dash）、折线 Path、面积 Path（闭合到底边，`color.withValues(alpha:.08)`——注意 M1 评审立过 withValues 版本坑，3.47 可用）、圆点（末点 4.2 实心 primary，其余 3 primarySoft 描边）、点上方数值文本（`TextPainter`，0.1 小数位）、底部日期 labels。整体 `AspectRatio(320/132)` 保持 H5 viewBox 比例。
- [ ] **Step 5: delta 行 + 接线** — `weightDeltaText`：当前=末点（1 位小数），±d=末点-首点（正号显式，升色 warn/降色 primary）；体重卡标题行右侧"记体重"按钮**本里程碑不做写入口**（logWeight 已有 API，UI 入口归"我的"页里程碑），按钮先不渲染并登记。
- [ ] **Step 6: 跑测试确认绿 + 提交** — `git commit -m "feat: 体重趋势线——computeTrendLayout 纯几何+CustomPainter（网格/面积/末点高亮/delta 降绿升橙）"`

---

### Task 7: 首页营养餐盘环（双环 CustomPainter + 进度/数字动画）+ 加载/空态区分

**Files:**
- Create: `ShiguangFlutter/lib/features/home/plate_ring.dart`
- Modify: `ShiguangFlutter/lib/features/home/home_screen.dart`（替换 `CircularIndicator` 占位 :104 附近；**并修终审 Minor M1**：加载中显式 loading 指示，仅"加载完成且无记录"才显 0/未记录，home_screen.dart:71-74）
- Test: `ShiguangFlutter/test/plate_ring_test.dart`

**Interfaces:**
- Consumes: `summaryProvider(date)` family（M2 T8 产物，`home_controller.dart`；date 用现码 `todayProvider`）、Tokens
- Produces: `PlateRing({required int kcal, required int target, required int carb, required int protein, required int fat})`；纯计算 `double ringSweep(int kcal, int budget)`、`List<double> macroFractions(int c,int p,int f)`（放同文件顶部，可脱离 widget 测）。

- [ ] **Step 1: 写失败测试（纯计算）** — `ringSweep`：pct=min(1, kcal/budget)，budget=target+0（运动额度 M3 恒 0，代码注释登记）；kcal=0→0、超预算→1 且色=warn（色判断 `kcal > budget`，app.js:323）；`macroFractions`：和归一、全 0 时分母按 1（app.js:326 `|| 1`）。
- [ ] **Step 2: 跑测试确认失败**。
- [ ] **Step 3: 实现 PlateRing** — 168×168（screens.css:151）CustomPaint：外环底轨 line 色 r=78 w=7；进度弧 `drawArc`，起止角 -π/2 起（SVG rotate(-90) 等价），扫角 = pct×2π，`strokeCap: round`，动画 `TweenAnimationBuilder<double>(duration 600ms, curve Curves.easeOutCubic)`（anime.js outCubic 等价）；内环底轨 surfaceSoft r=62 w=15，三段弧按 macroFractions 顺排（carb→protein→fat，色 nutCarb/nutProtein/nutFat，app.js:326-338 顺序不得换）；中心 `TweenAnimationBuilder<int>` 数字滚动 500ms 显 `max(0, budget-kcal)`，单位行"还可摄入 kcal"（index.html:92-94 逐字）。
- [ ] **Step 4: home_screen 接线 + 加载态** — 卡内左环右明细布局按 index.html:75-105 结构（环+aside：额度/已摄入/运动 0 三行，文案 app.js:306-308 的 ex==0 分支：`基准目标 ${target} kcal · 记运动后额度自动上调`）；`AsyncValue.when` 的 loading 分支改为显 `CircularProgressIndicator(strokeWidth:3)` 占环位，error 分支沿用 M2 重试行。
- [ ] **Step 5: 跑测试确认绿 + 全量回归 + 提交** — `flutter test && dart analyze lib test`；`git commit -m "feat: 首页营养餐盘环——双环 CustomPainter+600ms 进度/500ms 数字滚动；首页加载/空态区分（终审 Minor 核销）"`

---

### Task 8: 收尾——记录页取整口径、版本号、全量门禁与真机演示包

**Files:**
- Modify: `ShiguangFlutter/lib/features/record/record_screen.dart:239` 附近（餐次合计 `'$sum kcal'` → 与行内 `_n()` 同口径取整，终审 Minor M2）
- Modify: `ShiguangFlutter/pubspec.yaml`（`version: 2.1.0+20100`）
- Test: 全量回归（不新增用例，修一处既有断言若受取整影响）

- [ ] **Step 1: 修取整口径** — 合计行改 `_n(sum)`（读现码确认 `_n` 语义=整数化显示），跑 `flutter test test/record_flow_test.dart` 绿。
- [ ] **Step 2: 版本 + 双栈门禁** — pubspec 升 `2.1.0+20100`；Run: `npm run check:version`（门禁会验 build 号公式）→ PASS；`node --test tests/`（H5 全量）→ 绿。
- [ ] **Step 3: Flutter 全量** — `cd ShiguangFlutter && flutter test`（预期 M2 106 + M3 新增 ≈ 140+ 全绿）、`dart analyze lib test` 0 issue。
- [ ] **Step 4: 出 debug 包并装模拟器冒烟**（演示前置，非验收）：`flutter build apk --debug`（首 build 拉 NDK 慢属正常；**勿接管道判成败，用 `; echo exit=$?**`），`adb install -r`，过一遍：登录→环动画→切报告（柱入场+点柱气泡）→切月→趋势线→记一笔回首页环+78。发现手感问题**当场记录到账本**，不在收尾任务里顺手改。
- [ ] **Step 5: 提交** — `git commit -m "build: M3 收官——记录合计取整口径统一、pubspec 2.1.0+20100（双栈门禁绿）"`

---

## 验收（M3 收官判据，写进终审 brief）

1. 全部门禁绿：flutter test / dart analyze / node --test / check:version。
2. 真机（或模拟器先行、老大手机复验）手感对比 v1.3.1 H5：**柱状图点击气泡、PageView 滑切、环动画**三处老大上手，不满意不算过（spec §M3 原文）。
3. 互通不回退：M2 互通验收链路重跑一遍（Flutter 记餐→H5 契约路由反查）。
4. 账本：`.superpowers/sdd/2026-09-25-flutter-m3-report-charts-motion/progress.md` 记录 R1/R2 裁定执行证据 + Task 4/6 若出现的视觉偏差登记。
