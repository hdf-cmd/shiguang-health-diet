# M6 日常功能追平（运动/喝水/建议卡/提醒卡）设计文档

日期：2026-09-26 ｜ 里程碑：M6（Flutter 重写第 6 站）｜ 前置：M1-M5 已合入推送（origin/main=`0089c43`，Flutter 2.3.0+20300）

## 背景与裁定记录

M5 真机验收期老大点名两笔账：①「我的」页提醒卡太占位（截图点名，选**方案 A：测试按钮收进弹层**）；②「运动板块没了、建议卡片没了，原版 H5 很多功能都没了」→ 全量差距盘点后拍板 **M6=核心四件**：运动打卡全家桶、喝水打卡+目标、首页每日建议卡、提醒卡压缩。食物库管理页/目标体重编辑/常吃排序回填（T9-②）/问候头/日期导航等进 M7 池。

**云函数红线恢复原样**：M5 方案 b 的一次性改云函数授权已用毕，M6 全程 api-diet 零改动——所需路由云端全部现成（js/api.js：exercises GET `/diet/exercises?date=`、addExercise POST 同径、deleteExercise DELETE `/diet/exercises/:id`、waterGoal PUT `/user/water-goal`、addWater POST `/diet/water`）。

## 目标与验收判据

1. 运动打卡闭环：记运动（含次数型俯卧撑/跳绳按体重×系数）→ 当日列表/删除 → **首页餐盘环额度=目标+运动真实联动**（plate_ring exerciseKcal 恒 0 的口子补上）→ 身体参数卡「今日运动」行；
2. 喝水闭环：首页水卡（进度+＋一杯+撤销）+「我的」喝水目标编辑（200ml 整数倍归一）；
3. 首页每日建议卡：domain/advice.dart（已逐字移植、现零引用）接 UI，触发规则与文案含 R2 死分支逐字保留；
4. 提醒卡压成一行（标题+副文案+开关+设置箭头），测试钮进弹层「诊断」区；
5. 门禁：`dart analyze lib test` 0、`flutter test` 全绿、H5 `node --test` 零 diff、`check:version` 过；版本 **2.4.0+20400**；每任务模拟器目检（R4，视觉可创新、数据行为 bug-for-bug）；互通抽查 uitest01 双端互见（Flutter 记运动→H5 反查，H5 记水→Flutter 反映）。

## 现状事实（设计依据，均已核）

- **domain 就绪**：`exercise.dart`（exerciseKcalOf/EXERCISE_LIB/次数型 repUnitCutoffMs/isRepRecord/exerciseAmountLabel 全移植）、`advice.dart`（建议引擎逐字，含 >110 死分支）、`deficit.dart`。
- **data 缺口**：HealthApi 无 exercises 三法、无 waterGoal（addWater 已有 health_api.dart:83）。
- **UI 缺口**：首页无运动卡/水卡/建议卡（home_screen 仅盘子环+三餐）；记录页无运动区；「我的」无喝水目标；plate_ring.dart:76 exerciseKcal 恒 0；body_profile_card 缺今日运动行（M5-T6 登记口子）。
- **H5 权威源**：运动卡 index.html:133-137+记运动弹层 :416-433、app.js loadExercises/addExercise 流（~:1739-1830）；水卡 html:111-131、app.js:409 区；goal-sheet html:295-308、app.js:488 区（WATER_GOAL_MIN/MAX、200 对齐）；建议卡 html:106-109、app.js renderAdvice :348 区；remind-card html:227-237。
- **id 口径警示（M5 教训）**：`/diet/exercises` 的 GET 返回 id 与 DELETE 所需 id 是否同轨，计划期第一步先核云函数源码（cf_ 前缀双轨坑先例）。
- 提醒卡现状：profile_screen.dart `_remindCard()`（~:515）标题+副文案+开关+两通栏测试钮；`_reminderBusy` 重入门禁、toast 文案族（「提醒已开启…」「测试通知已发，看通知栏」等）零改动继承。

## 范围拆解（四件 → 计划任务切法预告）

### ① 运动打卡全家桶
- HealthApi 补 `getExercises(date)`（数组→callValue）/`addExercise(record)`/`deleteExercise(id)`，契约 fixture 三条双端锁；
- 记录页运动区：当日列表（名/数量串形 exerciseAmountLabel/kcal/删除确认）+「＋ 记运动」弹层（运动库 chips→数量步进（默认值/上下限/步长按 EXERCISE_LIB）→预览 kcal 实时）；提交体逐字 H5（key/name/amount/unit/kcal/date/createdAt，次数型 unit 落 'min' 占位+key/createdAt 划线判别的既有 domain 语义）；
- 首页：运动卡（今日运动合计+快捷入口）+餐盘环额度接线（budget=target+ex，ex 来自当日 exercises 合计，与 H5 renderRing 同源）；
- 身体参数卡补「今日运动」行（renderMetab ex 分支激活，公式注记「今日运动记录累计」逐字）。

### ② 喝水
- 首页水卡：`water/目标杯` 进度点（水目标=profile.goal.waterMl，杯=200ml 常量口径照 H5）、「＋ 喝一杯」（addWater delta，date=H5 同 TODAY 口径）、「撤销」分支照 H5；成功刷新 summary/water；
- 「我的」页喝水目标编辑（goal-sheet 等价）：滑杆/步进 200 对齐、上下限闸、`PUT /user/water-goal`、toast 逐字；profileProvider 失效联动。

### ③ 首页建议卡
- summary+目标就绪时渲染 advice.dart 输出（条数/排序/文案逐字，>110 死分支保留）；空态/加载态照 H5 卡位；
- 全库 grep advice 零引用 → 接线即闭环，无 domain 改动。

### ④ 提醒卡压缩（方案 A）
- 卡面一行化：标题+副文案+开关+「设置」箭头；箭头弹层=开关说明+两测试钮「诊断」区；
- 行为零改动：setEnabled/testMeal/testWater、重入门禁、toast 文案族原样；测试改断言新布局路径。

## 测试面

- 每任务 TDD；运动：契约三路由、次数型/时长型/距离型 kcal 预览样本、删除确认流、环额度联动（ex>0 分支首次真实覆盖）；喝水：200 对齐闸、撤销、目标 PUT body 键逐字；建议卡：domain 既有样本直出 UI 断言；提醒卡：既有 profile_reminders_test 迁移到新路径；
- 互通：Flutter 记运动→curl GET /diet/exercises 反查→H5 报告页可见（数据面 curl 必做，H5 渲染面能核则核）；
- 模拟器目检每任务（R4）；收官 release 包重打（ASCII 沙盒配方，同版本 2.4.0 首发）。

## 风险登记

1. exercises DELETE id 口径双轨风险（cf_ 先例）——计划 T0 先核云源码，若 GET 带前缀则 Flutter 侧剥前缀并登记（不改云）；
2. 首页信息密度上升（环+建议+运动+水+三餐）：滚动/卡距目检重点，R4 授权调版式；
3. 喝水「撤销」H5 语义（delta 负数 or 删记录）以 app.js 现码为准，计划期核；
4. 建议卡与 H5 双端渲染条件差异（H5 依赖 state.summary+body 就绪时序）——Flutter 用 provider 组合，触发不一致时以「同日同数据同文案」为验收准绳。

## 非目标（M7 池）

食物库管理页、目标体重编辑 sheet、常吃排序回填 Flutter（T9-②）、问候头、餐盘日期导航、记录页 7 天行、今日未打卡弹层、actualDeficit 移植、setGoal 失败文案收口、头像拍照源、失焦归一裁定、跨账号 foodFreq prefs。H5 侧零改动（运动/喝水双端规则：老大已定「Flutter 先行、H5 等通知」）。
