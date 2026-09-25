# Flutter M4 平台能力（秤同步+提醒）Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 在 ShiguangFlutter/ 交付体脂秤 BLE 同步（flutter_blue_plus，B1 协议纯 Dart 移植）与三餐/喝水系统提醒（flutter_local_notifications），并收掉 M3 终审遗留的三件地基活；验收=真机站秤→锁定→秒存 + 提醒到点（老大上手）。

**Architecture:** 三层：`domain/scale_protocol.dart` + `domain/reminders.dart`（纯 Dart 零插件依赖，真机报文做测试向量，purity 守卫覆盖）→ `features/scale/`（ScaleTransport 抽象 + flutter_blue_plus 薄实现，编排可注入 fake 单测）+ `features/notifications/`（插件调度薄层，规则全在 domain）→ "我的"页承载体重卡与提醒开关（替换 M1 占位）。

**Tech Stack:** flutter_blue_plus（锁版本进 pubspec.lock）、flutter_local_notifications、permission_handler（运行时权限）；沿用 Riverpod 3 / dio / shared_preferences。

**Spec:** `docs/superpowers/specs/2026-09-25-flutter-rewrite-design.md`（M4 行：flutter_blue_plus 秤同步、flutter_local_notifications 三餐/喝水提醒、两位小数体重；已知降级：Android 16 灵动岛/常驻进度卡 M4 不做，普通通知）

**协议权威源（逐字移植对象）:** `HealthyDiet/app/src/main/java/com/healthydiet/app/ScaleSync.kt`（帧编解码/握手/解析/过滤/错误文案）、`Notify.kt`（提醒时刻/文案/喝水种子算法/开关持久化）。实现者必须先读这两个文件对应行段，与本计划冲突处以 Kotlin 源码为准并在报告登记。

## Global Constraints

- **云函数 api-diet 一行不改**；体重写云端必须走同一 `POST /user/weight`（body `{weightKg, date}`，两位小数全链路 v1.3.0 已支持）。
- **domain 纯净铁律**：`lib/domain/**` 禁止 import flutter/插件（purity_test 守卫在线）。
- **M4 明确不做**（spec 降级令）：灵动岛特效、喝水常驻进度卡（WaterProgress）——提醒一律普通通知；要特效是 M5 选修 Kotlin 子插件。通知点击行为=打开 App（Flutter 无喝水打卡页，深链目标不存在，登记待办池）。
- **随机源裁定 R3**：H5 喝水槽位用 `java.util.Random(seed)`，Dart 无法逐位复现也**无需**逐位复现——通知时刻不是数据契约；移植的是**分布规则**（16h 切 8 段、段内随机、±5 分钟 guard band、日期种子确定性），随机源用 Dart `math.Random(seed)`。测试断窗口/分层/guard/同日确定性，不断具体分钟值。
- 依赖锁版本：`flutter pub add` 后 pubspec.lock 进 git（M1 裁定）；插件 API **以 .pub-cache 安装源为准核对**（读 `~/.pub-cache/hosted/pub.flutter-io.cn/<pkg>-<ver>/lib` 或 `flutter pub deps` 定位），禁止照博客/记忆写 API——M2 立过此规（flutter_test 不导出 material 教训）。
- 工具链：每条 Bash `export PATH="$PATH:/c/flutter/bin"`；**分析用 `dart analyze`（flutter analyze 中文路径崩）**；build 判成败 `> log 2>&1; echo exit=$?`；UI 测试文件显式 `import 'package:flutter/material.dart';`。
- 权限清单（AndroidManifest + 运行时）：`BLUETOOTH_SCAN`（neverForLocation）、`BLUETOOTH_CONNECT`（API31+）；API≤30 走 legacy `BLUETOOTH`/`BLUETOOTH_ADMIN`+`ACCESS_FINE_LOCATION`；`POST_NOTIFICATIONS`（33+）；`SCHEDULE_EXACT_ALARM`（喝水闹钟，用 `AndroidScheduleMode.inexactAllowWhileIdle` 则免，M4 取不敏感面：**全部用 inexact**，接受提醒分钟级漂移）。参照 `HealthyDiet/app/src/main/AndroidManifest.xml:4-12`。
- 版本线：M4 收官 `pubspec.yaml` 升 `2.2.0+20200`；H5 栈本里程碑**零改动**（秤/通知是 Flutter 侧新能力，H5 已有）。
- 真机验收=老大手机（模拟器无 BLE）；通知链模拟器可验（时间注入+测试按钮）。测试账号 uitest01/Test1234!@；真实 uid/凭证不得进 fixture。
- 错误文案逐字移植 ScaleSync.kt（:67-71 无蓝牙/未开、:83-85 扫描超时"未发现体脂秤，请靠近并站上秤"、:93-95 连接失败、:130 订阅失败、:143-145 读取超时"等待秤读数超时"——**以现读源码为准**，实现者抄原文）。

**文件结构总览：**

| 动作 | 文件 | 职责 |
|---|---|---|
| Create | `ShiguangFlutter/lib/domain/scale_protocol.dart` | 帧编解码/解析/emit 过滤（纯） |
| Create | `ShiguangFlutter/lib/domain/reminders.dart` | 三餐槽位表+喝水种子分层随机（纯） |
| Create | `ShiguangFlutter/lib/features/scale/scale_service.dart` | 编排状态机（依赖 ScaleTransport 抽象） |
| Create | `ShiguangFlutter/lib/features/scale/blue_plus_transport.dart` | flutter_blue_plus 薄实现（唯一 import 插件处） |
| Create | `ShiguangFlutter/lib/features/profile/profile_screen.dart` | 我的页：体重卡+提醒开关+测试按钮 |
| Create | `ShiguangFlutter/lib/features/notifications/reminder_scheduler.dart` | flutter_local_notifications 调度薄层 |
| Create | `ShiguangFlutter/lib/app/root_container.dart` | buildRootContainer 工厂（T1，main 与测试共用组合根） |
| Modify | `ShiguangFlutter/lib/main.dart`、`app/shell.dart`（我的 tab 接线）、`pubspec.yaml`、`android/app/src/main/AndroidManifest.xml` |
| Modify | `ShiguangFlutter/test/auth_expiry_test.dart`（改用工厂，删手抄同构） |
| Test | `test/domain/scale_protocol_test.dart`、`test/domain/reminders_test.dart`、`test/scale_service_test.dart`、`test/profile_screen_test.dart`、`test/harness.dart`（T1 共享测试地基） |

---

### Task 1: 地基收口——buildRootContainer 工厂 + Riverpod retry 策略 + 测试 harness（M3 终审遗留三件）

**Files:**
- Create: `ShiguangFlutter/lib/app/root_container.dart`
- Create: `ShiguangFlutter/test/harness.dart`
- Modify: `ShiguangFlutter/lib/main.dart`（组合根改调工厂）
- Modify: `ShiguangFlutter/test/auth_expiry_test.dart`（删 `_expiryContainer` 手抄，改工厂+注入桩）
- Modify: `ShiguangFlutter/test/data/health_api_report_test.dart`、`test/data/contract_test.dart`（RecordingAdapter 收敛到 harness）
- Modify: `ShiguangFlutter/test/weight_trend_test.dart`、`test/report_screen_test.dart`（setSurfaceSize 收敛到 harness helper）

**Interfaces:**
- Produces: `ProviderContainer buildRootContainer({TokenStore? tokenStore, Dio? dio, void Function()? onSessionExpired})`——未传参用真实链路（SecureTokenStore+默认 Dio），传参即测试桩；**`retry: (_, _) => null`**（对齐 H5"失败一次+手动重试"语义，M3 终审 Important-3）。`test/harness.dart` 出 `class RecordingAdapter extends HttpClientAdapter`（可配置路由→响应/错误+计数）与 `Future<void> useBigSurface(WidgetTester t, {double w, double h})`（内部 addTearDown 复位）。
- Consumes: 现 main.dart 的全部 override 语义（tokenStore/apiClient/authApi/healthApi/foodFreqStore）。

- [ ] **Step 1:** 读 `lib/main.dart` 现组合根与 `test/auth_expiry_test.dart` 的 `_expiryContainer`，把 container 拼装搬进 `root_container.dart` 工厂：参数化 tokenStore/dio/onSessionExpired，内部 `ProviderContainer(overrides: [...默认链路由实参兜底...], retry: (_, _) => null)`。auth_expiry_test 的 foodFreqStoreProvider 桩经参数注入。
- [ ] **Step 2:** 迁移 `RecordingAdapter` 与 `setSurfaceSize` 用法进 `test/harness.dart`，两处测试改 import；跑 `flutter test test/auth_expiry_test.dart test/data/ test/report_screen_test.dart test/weight_trend_test.dart` 全绿（行为零变，纯搬家）。
- [ ] **Step 3:** 新增 `test/root_container_test.dart`：工厂注入桩 dio（RecordingAdapter 恒回 500）→ `container.read(summaryProvider(todayIso()).future)` 抛 ApiException 后断 `adapter.requests.length == 1`（**不自动重试**，锁住 M3 终审 Important-3 的 retry:null 语义）；再断未传参时 apiClientProvider/healthApiProvider 可解析（真实链路拼装不炸）。
- [ ] **Step 4:** 全量 `flutter test`（基线 216 不回退）+ `dart analyze lib test` 0；提交 `refactor: M3终审地基收口——buildRootContainer工厂(含retry:null)、测试harness收敛`。

---

### Task 2: domain/scale_protocol.dart——B1 协议纯 Dart 移植（真机报文做测试向量）

**Files:**
- Create: `ShiguangFlutter/lib/domain/scale_protocol.dart`
- Test: `ShiguangFlutter/test/domain/scale_protocol_test.dart`

**Interfaces:**
- Produces（Task 3 消费，签名精确）:
  - `const int kScaleFrameLen = 20`；`const int kWireLive = 0x51`（`kWireOldStore = 0x54` 仅注释登记忽略）
  - `int frameCrc(List<int> f)` = `sum(f[2..18]) & 0x1F`
  - `List<int> buildFrame(int cmd, int wireType, List<int> body)`（20 字节，AF/45 头，f[2]=cmd，body 落 f[3..]，f[18]=wireType，f[19]=crc）
  - `List<int> time4LE(int epochSeconds)`（秒→4 字节小端）
  - `List<int> handshakeFrames(int epochSeconds)` → 3 帧（0x16/0x5F 校时 + 两条 0x04/0x62 SYNC_BODY_1/2）
  - `ScaleFrame? parseScaleFrame(List<int> b)` → null=非法帧（长度/头/crc/非 0x51 全 null）；否则 `{double kgRaw, bool locked}`（kgRaw=(le32(b[2..5]) & 0x3FFFF)/1000.0，locked=bit31）
  - `ScaleEmit? filterReading(ScaleFrame f, {double? lastKg})` → `null` 丢弃（round 两位小数后不在 2.0–300.0）；否则 `{double kg, bool locked, bool changed}`（changed=非 locked 且 ≠lastKg）
- 逐字移植对象：`ScaleSync.kt:212-244`（parse/emit）、`:247-256`（MASK/SYNC_BODY_1/2 常量）、`:258-289`（buildFrame/time4/crc/be32/swap32）。**先读源码再写**；SYNC_BODY 两帧 15 字节数组照抄（含 0xAF 0xB6 0x17 0x1D / 0xB4 0xC6 0x1B 0x56 / 0xA5 0xF8 0x11 / 0xB4 0xC6 0x1B 0x1D 等字面量）。

- [ ] **Step 1: 写失败测试**（测试向量=按 Kotlin 规则手构的"真机形状"帧 + 两个已知实测值）：

```dart
List<int> liveFrame(double kg, {bool locked = false}) {
  final flags = ((kg * 1000).round() & 0x3FFFF) | (locked ? 0x80000000 : 0);
  final f = List<int>.filled(20, 0);
  f[0] = 0xAF; f[1] = 0x45;
  f[2] = flags & 0xFF; f[3] = (flags >> 8) & 0xFF; f[4] = (flags >> 16) & 0xFF; f[5] = (flags >> 24) & 0xFF; // le32
  f[18] = 0x51;
  var sum = 0; for (var i = 2; i <= 18; i++) { sum += f[i]; }
  f[19] = sum & 0x1F;
  return f;
}
```
断言：`parseScaleFrame(liveFrame(66.66))!.kgRaw == 66.66`、locked 位、0x54 存档帧→null、坏 crc→null、坏帧头→null、长度≠20→null；`filterReading`：2.0–300.0 过滤、round 两位（66.666→66.67）、locked 直通 changed=true、非 locked 同值 changed=false；`handshakeFrames(1780000000)` 三帧的 f[2]/f[18]/校时字节小端 `d8 01 0b 6a`、f[19]=各自 crc；`buildFrame` 空 body 越界不崩（body 最长 15）。
- [ ] **Step 2:** 跑 RED（编译错）。
- [ ] **Step 3:** 实现（文件头注释标权威源 ScaleSync.kt 行号；**不 import 任何插件**，purity 守卫自动覆盖）。
- [ ] **Step 4:** `flutter test test/domain/` 绿（purity 无红）；全量 216+新增不回退；提交 `feat: B1秤协议纯Dart移植——帧编解码/0x51过滤/0x54忽略/握手校时，真机形状测试向量`。

---

### Task 3: ScaleService 编排层（Transport 抽象 + flutter_blue_plus 薄实现 + 权限）

**Files:**
- Modify: `ShiguangFlutter/pubspec.yaml`（`flutter pub add flutter_blue_plus permission_handler`，锁版本进 lock）
- Modify: `ShiguangFlutter/android/app/src/main/AndroidManifest.xml`（权限清单，见 Global Constraints）
- Create: `ShiguangFlutter/lib/features/scale/scale_service.dart`
- Create: `ShiguangFlutter/lib/features/scale/blue_plus_transport.dart`
- Test: `ShiguangFlutter/test/scale_service_test.dart`

**Interfaces:**
- Consumes: Task 2 全部协议函数。
- Produces:
  - `abstract class ScaleTransport { Stream<List<int>> notifications(); Future<TransportSession?> scanAndConnect({required String namePrefix, required Duration timeout}); }`（`TransportSession` 含 `writeFrame(List<int>)`、`close()`）
  - `class ScaleService { Stream<ScaleReading> get readings; Future<ScaleOutcome> start(); Future<void> cancel(); }`，`ScaleReading{double kg, bool stable}`、`ScaleOutcome{String status /* 'ok'|'scan-timeout'|'connect-fail'|'read-timeout'|'no-bluetooth'|'permission-denied' */, double? kg}`
  - Provider：`scaleServiceProvider = Provider<ScaleService>((ref) => ScaleService(BluePlusTransport()))`（测试 override 成 FakeTransport 构造的实例）；`scaleReadingsProvider = StreamProvider<ScaleReading>((ref) => ref.watch(scaleServiceProvider).readings)`（Task 4 的 live 预览 listen 这个）
- 编排规则逐字移植 ScaleSync.kt：扫描过滤 `name.startsWith('AFU-')`；连接后先订阅全部 NOTIFY/INDICATE 特征、写特征取 `af000002` 前缀否则退化任一可写；订阅成功→`handshakeFrames(nowSeconds)` 逐帧写；通知流→`parseScaleFrame`→`filterReading`（维护 lastKg）→`readings.add`；locked→`finish('ok')` 且 `lockedSent` 防重；扫描超时 30s、读数超时 90s；**0x54 忽略**（协议层已挡）。错误文案在 UI 层映射（Task 4），本层只出 status 码。

- [ ] **Step 1:** `flutter pub add flutter_blue_plus permission_handler`；**读安装源 API**（`.pub-cache` 里 flutter_blue_plus 的 scan/startNotify/Characteristic.setNotifyValue 真实签名）后才写 transport；`BluePlusTransport` 是唯一 import 插件的文件，逻辑压到最薄（无单测，真机验收）。
- [ ] **Step 2:** 写失败测试（FakeTransport 注入）：AFU- 帧序列（3×非锁定渐进值→locked）→ readings 依次 `(60.1,false)(60.5,false)(66.66,true)`、start() 返回 `ok/66.66`；重复 locked 只发一次；同值非锁定只发一次；0x54 帧与坏 crc 帧被忽略；scanAndConnect 返回 null→`scan-timeout`；握手三帧被写出（FakeTransport 记录 writes，比对 Task 2 buildFrame 输出）。
- [ ] **Step 3:** 实现 ScaleService（状态机：idle→scanning→handshake→streaming→done；cancel 幂等；超时 Timer 全部可注入 Duration 参数，测试传毫秒级）。
- [ ] **Step 4:** 测试绿 + 全量不回退 + analyze 0；提交 `feat: 秤同步编排层——ScaleTransport抽象+flutter_blue_plus实现+权限清单，locked秒完非锁定去重`。

---

### Task 4: "我的"页体重卡——当前体重/手动输入两位小数/从体脂秤同步秒存

**Files:**
- Create: `ShiguangFlutter/lib/features/profile/profile_screen.dart`
- Modify: `ShiguangFlutter/lib/app/shell.dart`（我的 tab：占位→ProfileScreen）
- Modify: `ShiguangFlutter/lib/app/auth_state.dart`（登出方法 `signOut()`：清 token+置 anon——体重卡旁"退出登录"需要，H5 我的页有登出入口，读 js/app.js 现文案逐字）
- Test: `ShiguangFlutter/test/profile_screen_test.dart`

**Interfaces:**
- Consumes: `HealthApi.logWeight`（M2 已有）、`getBodyMetrics`/`getProfile`（weightKg 现值）、Task 3 `scaleServiceProvider`、`summaryProvider`。
- Produces: `ProfileScreen`（ConsumerWidget）；`profileWeightProvider = FutureProvider<double?>`（读 body-metrics 的 weightKg）。

- [ ] **Step 1:** 读 H5 我的页体重区（index.html:468-476 + app.js:927-956 手动步进 ±0.5/输入/保存校验 20–300/秤按钮）取布局与文案；写失败测试：渲染"当前体重 X.XX kg"（桩 body-metrics 66.66）、手动 stepper 0.5 步进与两位小数、保存→`logWeight` 收到 `(66.16, todayIso())` 且 toast 文案逐字（抄 H5）、20–300 外不提交、"从体脂秤同步"点击→override 的 FakeScaleService 推 `(60.5,false)(66.66,true)` → 预览 Text 先 60.5 后 locked 自动保存（logWeight 收到 66.66）+状态"已记录"、start() 返回 scan-timeout→错误文案（映射表：`'scan-timeout'→'未发现体脂秤，请靠近并站上秤'` 等，**逐字抄 ScaleSync.kt/JS 侧现文案**，读源码定）。
- [ ] **Step 2:** 实现（秤进行中：按钮禁用+状态行；cancel 时机=弹层关闭/页面 dispose；`ref.listen(scaleReadingsProvider)` 预览不落库，locked 才 saveWeight——与 H5 `SG_onScaleWeight(kg,stable)` 直存语义一致但**只有 stable 存**，读 app.js:953-956 核对：H5 是 stable 才 saveWeightKg，非 stable 仅预览，照此）。
- [ ] **Step 3:** 测试绿 + 全量 + analyze；提交 `feat: 我的页体重卡——当前体重/±0.5步进两位小数手动输入/秤同步live预览locked秒存`。

---

### Task 5: domain/reminders.dart——三餐槽位 + 喝水日期种子分层随机（纯）

**Files:**
- Create: `ShiguangFlutter/lib/domain/reminders.dart`
- Test: `ShiguangFlutter/test/domain/reminders_test.dart`

**Interfaces:**
- Produces:
  - `const mealSlots = [(8, 0, 101, '早餐提醒', '吃早餐了吗？点开记一笔，牛奶面包肉包都在食物库'), (12, 0, 102, '午餐提醒', '记录午餐，看看今天的热量缺口还剩多少'), (18, 30, 103, '晚餐提醒', '记录晚餐，收个尾看看今日营养达标情况')]`（**逐字抄 Notify.kt:76-78**，含 id）
  - `List<String> waterTexts`（Notify.kt:82-88 五条逐字）
  - `List<(int, int)> waterSlots(DateTime day)`：`key = year*1000 + dayOfYear`；`rnd = Random(key*1000003)`；`stratum = (24*60 - 8*60) ~/ 8 = 120`；`m = 480 + i*120 + 5 + rnd.nextInt(110)`；返回 `(m~/60, m%60)` 8 项——**规则逐字 Notify.kt:151-159，随机源换 Dart（裁定 R3）**
  - `List<(int,int)> waterPlanFrom(DateTime now, {bool Function((int h,int m)) isFuture})`：当天剩余槽位，全过则滚次日（Notify.kt:160-170 语义）
- Consumes: 无。

- [ ] **Step 1:** 写失败测试：waterSlots 确定性（同 day 两次调用逐位相等）、8 项、每项 ∈ [8:00,24:00)、第 i 项落在 `[480+120i+5, 480+120i+115]` 分层带内、不同日产出不同序列；waterPlanFrom 23:59 起点→全滚次日 8 项、07:00 起点→8 项全留；mealSlots 文案与 Notify.kt 逐字（测试里硬编码期望字符串——从 Kotlin 抄，双源核对）。
- [ ] **Step 2:** RED → 实现 → `flutter test test/domain/` 绿；提交 `feat: 提醒规则纯函数——三餐槽位表+喝水日期种子分层随机（R3裁定：分布保真随机源换Dart）`。

---

### Task 6: ReminderScheduler——flutter_local_notifications 接线（渠道/三餐重复/喝水链式/开关持久化）

**Files:**
- Modify: `ShiguangFlutter/pubspec.yaml`（`flutter pub add flutter_local_notifications`）
- Modify: `ShiguangFlutter/android/app/src/main/AndroidManifest.xml`（RECEIVER_EXPORTED for scheduled notifications，读插件 README 的 Android 13+ 必配项）
- Create: `ShiguangFlutter/lib/features/notifications/reminder_scheduler.dart`
- Modify: `ShiguangFlutter/lib/main.dart`（启动初始化 + `ensureScheduled()` 自愈点，对齐 H5 MainActivity:105）
- Test: `ShiguangFlutter/test/reminder_scheduler_test.dart`（可测部分：开关持久化读写、槽位→通知请求映射经注入的 PluginPort 断言，不 mock 插件本体）

**Interfaces:**
- Consumes: Task 5 全部；`SharedPreferences`。
- Produces:
  - `class ReminderScheduler { Future<void> init(); Future<void> sync({required bool on}); Future<bool> enabled(); Future<void> testMeal(); Future<void> testWater(); }`
  - 语义：`on=true`→三餐 `matchDateTimeComponents: DateTimeComponents.time` 每日重复（inexact 面：`AndroidScheduleMode.inexactAllowWhileIdle`）+ 喝水 `waterPlanFrom(now)` 一次性链（每条 callback 后无——**链式次日改由 init()/sync() 时重排**：App 启动即自愈，等价 H5 BootReceiver 链的降级面，登记为 M4 已知限制：多天不打开 App 则喝水提醒只排当天）；`on=false`→cancelAll（保留 id 段 101-103/200-207）。
  - 开关存储键 `sg_reminders_on`（H5 是 `sg_prefs/reminders_on`，Flutter 侧 SharedPreferences 本就独立文件，键名对齐语义即可，注释登记）。
  - 渠道：`sg_reminder`/「饮食提醒」/IMPORTANCE_HIGH（=PluginImportance.max）/描述逐字 Notify.kt:29-30。

- [ ] **Step 1:** `flutter pub add flutter_local_notifications`；**读安装源 API**（zonedSchedule 参数面、AndroidNotificationDetails 构造）后写 PluginPort 抽象（`abstract class NotificationPort { Future<void> show(...); Future<void> periodDaily(...); Future<void> at(...); Future<void> cancelAll(); }`）+ 真实实现 + FakePort（测试记录调用）。
- [ ] **Step 2:** 写失败测试：sync(on:true)→FakePort 收到 3 条 periodDaily（时刻/标题/正文=id 101-103 与 Task 5 表一致）+ 8 条 at（时刻=waterPlanFrom 输出）；sync(on:false)→cancelAll；enabled 读写 SharedPreferences 往返；testWater 走 waterTexts 轮询取一（对齐 Notify.kt:95 测试文案语义）。
- [ ] **Step 3:** 实现 + init（含 POST_NOTIFICATIONS 请求经 permission_handler，Android 13+）；main 启动 `ref.read(reminderSchedulerProvider).then((s)=>s.init().then((_)=>s.sync(on: await s.enabled())))` 收进一个 `bootstrapReminders(container)` 函数（root_container.dart 旁，测试可跳过）。
- [ ] **Step 4:** 全量绿 + analyze 0 + `flutter build apk --debug` exit 0（插件编译面验证，Android 14 RECEIVER_EXPORTED 坑在这暴露）；提交 `feat: 提醒调度接线——渠道/三餐每日重复/喝水当日链式(启动自愈)/开关持久化，全inexact`。

---

### Task 7: 我的页提醒开关区 + 通知点击打开 App

**Files:**
- Modify: `ShiguangFlutter/lib/features/profile/profile_screen.dart`
- Test: `ShiguangFlutter/test/profile_screen_test.dart`（追加）

**Interfaces:**
- Consumes: Task 6 ReminderScheduler、Task 4 ProfileScreen。
- Produces: 我的页"消息提醒"卡：总开关 Switch + 「测试餐点提醒」「测试喝水提醒」按钮（文案逐字抄 H5 设置区，读 app.js:1043-1059 与 index.html 对应区）；通知 tap 行为=打开 App（无深链，Global Constraints 已裁）。

- [ ] **Step 1:** 写失败测试：开关渲染自 enabled 初值、切换→scheduler.sync 收到新值且持久化、测试按钮→testMeal/testWater 各触发一次、失败 toast 路径。
- [ ] **Step 2:** 实现（开关切换用现有 setState/AsyncValue 惯例；通知点击回调在 scheduler init 里 `onDidReceiveNotificationResponse` 设 no-op 仅打开——对齐"打开 App"语义）。
- [ ] **Step 3:** 全量绿 + analyze；提交 `feat: 我的页提醒开关与测试按钮；通知点击打开App（M4降级面：无深链）`。

---

### Task 8: 收官——版本 2.2.0、全量门禁、真机验收 runbook

**Files:**
- Modify: `ShiguangFlutter/pubspec.yaml`（`2.2.0+20200`）

- [ ] **Step 1:** 版本升档 + `npm run check:version` exit 0。
- [ ] **Step 2:** 全量：`flutter test`（基线 216+M4 新增全绿）、`dart analyze lib test` 0、H5 `node --test`（应零 diff 仍全绿）、check:version。
- [ ] **Step 3:** `flutter build apk --debug` exit 0 → 装机 → 模拟器冒烟：我的页体重手动输入 66.66 保存→云端反查 `/user/profile` 或 body-metrics 读到 66.66（互通铁律：写走同一路由）；提醒开关开→`adb shell cmd notification list` 或到点观察（测试按钮即时可验）；**秤链路模拟器不可验（无 BLE），列入真机 runbook**：老大手机装 debug 包→站秤→预览数字跳动→locked 秒存→"我的"页/H5 报告页体重趋势可见。
- [ ] **Step 4:** 提交 `build: M4 收官——pubspec 2.2.0+20200（双栈门禁绿）`。

---

## 验收（M4 收官判据，写进终审 brief）

1. 门禁全绿（flutter test / analyze / H5 零 diff / check:version）。
2. 真机（老大手机）：站秤→锁定→秒存，体重两位小数落云端且 H5 侧可见（同一 /user/weight 路由铁律）；提醒到点弹横幅、开关持久化。
3. 协议层测试向量全绿（0x54 忽略、crc、locked 位、范围过滤）。
4. 账本登记：R3 随机源裁定、喝水"仅排当天"降级面、通知无深链、inexact 漂移面。
