# 食光 Flutter 重写 · M2（状态与网络：真实登录 + 记三餐闭环）实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Flutter 端接上真实 api-diet 后端：domain 层纯逻辑完成移植（H5 40 条测试翻成 Dart）、dio 客户端与登录态落地、主界面真实数据渲染、记三餐全流程可用——验收标准是 uitest01 在手机记一顿饭，浏览器 H5 端立刻可见。

**Architecture:** 延续 M1 分层：`domain/`（纯 Dart，零 flutter import）← `data/`（TokenStore + ApiClient + HealthAPI 方法）← `features/`（Riverpod Notifier 驱动的页面）。契约防漂移：`contract/fixtures/` 一份 fixture 两端共测。

**Tech Stack:** Flutter 3.47.5 / Dart 3.13.4、dio、riverpod、flutter_secure_storage、shared_preferences（本地档案缓存）、flutter_test + mocktail（HTTP 层桩测）。

**Spec:** `docs/superpowers/specs/2026-09-25-flutter-rewrite-design.md`（§2 移植清单、§4 数据流、M2 定义见 §3）；M1 计划已执行完毕（HEAD c22e938）。

## Global Constraints

- 工程 `ShiguangFlutter/`，直接在 main 上开 `feat/flutter-m2` 分支执行；H5 栈与 api-diet 云函数零改动（双栈契约=云端不动）。
- `domain/` 禁止 import flutter（用 `test/domain_purity_test.dart` 守：扫 lib/domain 下所有 .dart 无 'package:flutter'）。
- 环境实测沿用 M1：每条 Bash `export PATH="$PATH:/c/flutter/bin"`；`flutter test` 直跑；分析用 `dart analyze`；gradle 已配腾讯镜像+overridePathCheck。
- 网关与认证事实（抄自 js/api.js，逐字）：
  - API_BASE=`https://cloud1-d6g4x9h9m507b429c.api.tcloudbasegateway.com/v1/functions/api-diet`；GW_BASE 去掉 `/v1/functions/api-diet`。
  - 业务请求统一 `POST API_BASE`，headers `Content-Type: application/json` + `Authorization: Bearer <token>`，body=`{path, method, params, body}`；超时 15s。
  - 无登录态用 PUBLISHABLE_KEY（js/api.js:22 那个长串，逐字复制进 Dart 常量）作 Bearer；登录/注册也走同格式，path=`/auth/login` `/auth/register`。
  - 登录成功返回 `data.token`（accessToken/refreshToken/expiresIn）；401 且有 refreshToken → `/auth/v1/token` grant_type=refresh_token 单飞续期重试一次；再 401 → 清 token 报"登录已过期，请重新登录"。
  - 非 200 或 `data.ok==false` → 抛 `data.message`。
- 路由表按 js/api.js `ROUTES`（30-80 行）逐字移植，M2 只实现用到的方法，其余不预铺（YAGNI）。
- 提交信息中文 `type: 描述`；pubspec.lock 若因加依赖变更随任务提交；禁止 push（老大统一令）。
- 测试绿的标准：`flutter test` 全绿 + `dart analyze` 零 issue；H5 侧 `npm test` 保持 40/40。

## 移植对照（Task 1-4 共用）

源：`js/logic.js`（全 216 行）与 `tests/logic.test.js`（36 条，全部翻成 Dart，期望值逐字照抄，不许"顺手改语义"）。返回结构：JS 对象 → Dart class/Map 由任务内指定；纯函数不改签名。

---

### Task 1: domain 常量与日期工具

**Files:**
- Create: `lib/domain/constants.dart`（MEAL_ORDER/MEAL_NAMES/WATER_CUP_ML/WATER_GOAL_MIN/MAX/KCAL_PER_KG/BODY_DEFAULT/ACTIVITY/EXERCISE_LIB）
- Create: `lib/domain/dates.dart`（localIso/todayIso/dateLabelOf；todayIso 接受可注入 DateTime）
- Test: `test/domain/constants_test.dart`、`test/domain/dates_test.dart`

**Interfaces:** Produces `const mealOrder=['breakfast','lunch','dinner','snack']`、`Map mealNames`、`ExerciseLib` 列表（unit/perKgKm/met 字段名与 JS 一致）、`String localIso(DateTime)`。

- [ ] Step1 从 tests/logic.test.js 找出涉及常量/日期的用例翻成 Dart，跑红
- [ ] Step2 按 js/logic.js:10-56 逐字移植，跑绿
- [ ] Step3 `dart analyze` 零 issue；commit "feat: domain 常量与日期工具移植（可注入时钟）"

### Task 2: domain 代谢与宏量

**Files:**
- Create: `lib/domain/metabolism.dart`（computeMetabolism、macroGoals）
- Create: `lib/domain/models.dart`（Body/Summary 等共享数据类，字段名与云函数返回一致：kcal/target/carb/protein/fat/water、heightCm/weightKg/bmi/age/gender/activity/deficit）
- Test: `test/domain/metabolism_test.dart`

**Interfaces:** Consumes Task1 常量；Produces `MetabResult computeMetabolism(Body b, double? targetWeight, Map? actualInfo)`、`MacroGoals macroGoals(num targetKcal)`（carb/protein/fat，50/25/25 供能比）。

- [ ] Step1 移植 tests/logic.test.js 中 computeMetabolism/macroGoals 全部用例（期望值逐字）→ 红
- [ ] Step2 按 js/logic.js:73-134 移植 → 绿；commit "feat: domain 代谢引擎与宏量目标移植"

### Task 3: domain 运动/份量/缺口

**Files:**
- Create: `lib/domain/exercise.dart`（exerciseKcalOf）、`lib/domain/portion.dart`（portionMacros）、`lib/domain/deficit.dart`（avgDeficitFromRows）
- Test: `test/domain/exercise_test.dart`、`test/domain/portion_test.dart`、`test/domain/deficit_test.dart`

- [ ] Step1 移植对应用例 → 红
- [ ] Step2 按 js/logic.js:118-150 移植 → 绿；commit "feat: domain 运动消耗/份量换算/实际缺口移植"

### Task 4: domain 建议引擎

**Files:**
- Create: `lib/domain/advice.dart`（AdviceRule 列表、buildAdvice、makeAdviceCtx）
- Test: `test/domain/advice_test.dart`

**Interfaces:** Produces `List<(String,String)> buildAdvice(AdviceCtx ctx)`（Dart 用 record 或二元素 List 对齐 JS `[emoji, text]`）、`AdviceCtx makeAdviceCtx({...})`（参数与 JS 同名；comp 参数已随体成分下线，不要带回来）。

- [ ] Step1 移植 tests/logic.test.js 的 buildAdvice 全部用例 → 红
- [ ] Step2 按 js/logic.js:152-216 移植规则表（文案逐字，含 emoji）→ 绿
- [ ] Step3 补 `test/domain/purity_test.dart`：遍历 lib/domain/*.dart 断言不含 'package:flutter'；commit "feat: domain 建议规则引擎移植 + 分层纯净性守卫"

### Task 5: data 层——TokenStore + ApiClient

**Files:**
- Modify: `pubspec.yaml`（加 dio、flutter_secure_storage、riverpod）
- Create: `lib/data/token_store.dart`（secure storage 存 accessToken/refreshToken/expiresIn/savedAt，键 `sg_token`）
- Create: `lib/data/api_client.dart`（`Future<Map> call(String path, {String method, Map params, Map body})`：单入口 body 格式、Bearer 规则、15s 超时、401 单飞续期重试、错误映射为 `ApiException(message)`）
- Create: `lib/data/auth_api.dart`（registerByUsername/loginByUsername/logout/isLoggedIn）
- Test: `test/data/api_client_test.dart`（注入 HttpClientAdapter 桩：断言 body 结构、Bearer 选择、401→refresh→重试一次、refresh 失败→清 token、`ok:false`→抛 message）

**Interfaces:** Produces `ApiClient(Riverpod ProviderScope 外单例或 provider)`；`AuthApi.login` 成功写 TokenStore。消费 Global Constraints 的认证事实。

- [ ] Step1 写 api_client_test（用 mocktail 桩 adapter，期望值来自上方契约）→ 红
- [ ] Step2 实现三文件 → 绿；commit "feat: data 层 TokenStore 与 ApiClient（401 单飞续期，契约对齐 js/api.js）"

### Task 6: data 层——HealthAPI 业务方法 + 契约 fixture

**Files:**
- Create: `lib/data/health_api.dart`（M2 所需方法：getProfile/getDailySummary/getMealRecords/addFoodRecord/deleteFoodRecord/addWater/searchFoods/getBuiltinFoods/logWeight/getBodyMetrics）
- Create: `contract/fixtures/diet-core.json`（仓库根 contract/：路由名、请求体样例、期望响应字段清单——从云函数真实响应手工采一份）
- Create: `test/data/contract_test.dart`（读 fixture 断言 health_api.dart 方法与字段一致）
- Modify: `tests/`（H5 侧）新增 `tests/contract.test.js` 读同一 fixture 断言 js/api.js 路由表一致
- Test: 上述即测试

- [ ] Step1 建 fixture（对 uitest01 跑一次真实响应采集，只读调用）
- [ ] Step2 Dart 与 H5 两侧契约测试先红（方法未建）
- [ ] Step3 实现 health_api.dart → 两侧绿；H5 `npm test` 41/41；commit "feat: HealthAPI 业务方法 + 双栈契约 fixture（一份契约两端测）"

### Task 7: 登录门控与真实登录

**Files:**
- Modify: `lib/features/auth/login_screen.dart`（onSubmit 接 AuthApi；错误行显示真实 message；注册模式复用）
- Modify: `lib/main.dart`（启动读 TokenStore：有→Shell，无→LoginScreen；登录成功回调切 Shell）
- Create: `lib/app/auth_state.dart`（riverpod StateProvider：unknown/authed/anon）
- Test: `test/auth_flow_test.dart`（mock AuthApi：登录成功→Shell 可见；失败→错误行文案）

- [ ] Step1 写测试 → 红
- [ ] Step2 实现 → 绿；commit "feat: 真实登录闭环——启动门控 + 登录/注册接 AuthApi"

### Task 8: 首页接真实数据

**Files:**
- Create: `lib/features/home/home_controller.dart`（riverpod：todaySummaryProvider(date)/profileProvider；日期沿用 M1 state.date 语义=今日）
- Modify: `lib/features/home/home_static_screen.dart` → 重命名 `home_screen.dart`（环中心数字=summary.kcal、"已摄入/目标"行、三餐行显示真实记录名与 kcal、"未记录"空态保留；1975 改 profile 派生 target——同时清掉 M1 终审 I1 里 home 的硬编码）
- Test: `test/home_screen_test.dart`（桩 HealthAPI：有记录渲染名/kcal，401 前 error 态显示重试）

- [ ] Step1 测试 → 红；Step2 实现 → 绿
- [ ] Step2.5 顺手清 M1 终审 I1 余项：theme.dart 增 `Tokens.shadowCard/shadowFloat`（值=0x141C2418/0x421C2418 双层阴影照 design-tokens.css），shell/login/home 三处裸色值改引 Tokens；fontSize:40 归入 Tokens.textHero
- [ ] commit "feat: 首页接今日汇总与三餐真实数据 + 阴影/字号令牌收敛（清 M1-I1）"

### Task 9: 记录页全流程

**Files:**
- Create: `lib/features/record/record_screen.dart`（餐次分段 + 已记列表(删) + "加菜"入口）、`lib/features/record/search_sheet.dart`（关键词搜食物→点选→按餐次记入；per100 食物弹份量 sheet）、`lib/features/record/portion_sheet.dart`（克数滑杆+实时宏量预览，逻辑=portionMacros）、`lib/features/record/record_controller.dart`
- Test: `test/record_flow_test.dart`（桩：搜索→加米饭 200g→列表出现→删除→空态；per100 换算数值断言）

- [ ] Step1 测试 → 红
- [ ] Step2 实现（交互对齐 H5：记录页餐次 tab、搜索弹层、份量弹层"按克加"）→ 绿
- [ ] Step3 Shell 里 record 占位换成 RecordScreen；commit "feat: 记录页全流程——搜索/按克加/删除，接真实云后端"

### Task 10: M2 收尾回归

- [ ] Step1 全量门禁：`flutter test` 全绿、`dart analyze` 零 issue、`npm test`（H5 41/41）、`npm run check:version`
- [ ] Step2 `flutter build apk --debug` 出包，装模拟器：真实登录 uitest01 → 首页显示云端今日 → 记一笔"米饭 200g" → 浏览器打开 H5 版登录 uitest01 确认同一条记录可见（双栈互通实锤，截图留证）
- [ ] Step3 报告 + commit（若有零散修复）；M2 演示过审后按老大指令合 main

## M2 DoD

1. domain 移植完成且 H5 的 36 条逻辑用例在 Dart 侧全数等价通过（对不上数的用例逐条列原因）；
2. 真机/模拟器：uitest01 登录 → 首页真实数据 → 记一顿饭 → H5 端立即可见；
3. 双栈契约 fixture 建立且两侧测试引用；
4. 分层守卫（domain 纯净性测试）绿；M1 遗留 PageController dispose、登录门控接线完成；
5. H5 栈与云函数零改动。
