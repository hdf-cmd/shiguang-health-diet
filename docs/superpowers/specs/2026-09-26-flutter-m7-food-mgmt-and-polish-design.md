# 食光 Flutter M7 设计：日期导航+食物库管理+目标体重+乐观体验+卫生批

日期：2026-09-26 ｜ 分支基线：main=599d05b（M6 已合已推）｜ 版本目标：2.5.0+20500
行为权威源：H5 `js/app.js`（行号均为本文撰写时实读）；数据行为 bug-for-bug 对齐，视觉层按 R4 长期令可创新。

## 1. 背景与范围决策

M6 收官后功能差距剩余件+两期终审挂账。老大 2026-09-26 拍板：**A 功能补齐 + B 状态与体验债 + C 工程卫生，单里程碑全收（9 批），自底向上切序**；D 第三方登录继续挂账（卡资质不卡代码，场景题未答）。

**范围侦察修正两个旧假设（本文以实读为准）**：
- 「常吃排序回填 Flutter」是伪需求——H5 从未实现（js/ 全目录无 foodFreq），Flutter food_freq.dart 已有全套。仅剩「prefs 不分账号」债，归 T8。
- 运动 temp 行**无任何特殊显示**（app.js:1740-1754 渲染统一 `-${kcal} kcal`，temp 行仅 id=`tmpx_<ts>`+自带 createdAt）；成功 toast **保存即弹不等回包**（:1818）。M6 登记的 R4 差异 #1（无瞬显）/#2（toast 迟一往返）在 T2 退役。

**非目标（本轮明确不做）**：今日未打卡提醒弹层（与本地通知重叠，老大裁定裁掉）；报告页「＋记今日体重」（M6 差距清单即有意不做）；第三方登录；**任何云函数/H5 源改动**（红线，M6 恢复原状）；「右滑看历史」手势（shell 横滑切 Tab 冲突风险，只做 ‹ › 按钮，差异登记 R4）。

## 2. 任务分解（9 批，依赖序）

| # | 任务 | 依赖 |
|---|---|---|
| T1 | 首页日期状态机 + plate-head ‹› 导航 + 问候头 | 地基 |
| T2 | 运动 exercisesProvider Notifier 化 + 乐观 temp 行 | 无 |
| T3 | 水卡 AsyncNotifier.family 化（_waterOverride 跨日债根治） | T1 |
| T4 | 我的食物库管理弹层（双 tab） | 无 |
| T5 | 目标体重编辑弹层 + setGoal 失败文案收口 | 无 |
| T6 | 记录页 7 天日期行 | T1 |
| T7 | actualDeficit 近 7 天实际缺口接线 | 无 |
| T8 | C 卫生批（终审 Minor 六条+杂项） | 无 |
| T9 | 收官：2.5.0+20500 四门禁+沙盒 release+R4 目检+真机验收单 | 全部 |

## 3. 状态层设计

### 3.1 plateDateProvider（T1/T3/T6 共享地基）
- `StateProvider<String>`，≙ H5 `state.date`，初值 `todayIso()`；放 home_controller.dart。
- `shiftDate(dir)` ≙ app.js:215-224：`next > todayIso()` → toast「已经到今天了」零变更；往过去无下限。成功后并行刷新 ≙ :221-223（各 provider invalidate 天然并行）。
- 首页五卡（环/水/运动/建议/三餐）从 `todayProvider` 改 watch `plateDateProvider`；`summaryProvider/exercisesProvider` 已是 family(date) 直接吃透。
- 跨午夜不自愈：H5 today 仅交互时重算，Flutter 不加午夜定时器（同款行为，注释登记）。
- 记录页与首页共享同一日期源（H5 全局 state.date 原生行为，照抄不隔离）。

### 3.2 ExercisesNotifier（T2）
- `FutureProvider.family` → `NotifierProvider.family<ExercisesNotifier, List<Map>, String>`（工程首个 Notifier 类形态；水卡 T3 复用同款）。
- 保存链逐字 app.js:1807-1830：本地算 kcal → **即插 temp 行**（`{id:'tmpx_<ms>', key,name,emoji,amount,unit,kcal,createdAt:now}`）→ `exerciseKcal` 合计含 temp → 环/代谢卡即时联动 → **即弹**「已记录{名} · 消耗 {kcal} kcal」+ 关层 → await addExercise → 成功 `loadExercises()` 重取真值替换；失败摘 temp+扣合计+「记录失败：msg||网络异常」。
- 删除链 ≙ deleteExerciseById：确认→乐观删行+扣合计→await→失败回插+「删除失败：msg」。
- temp 行 rep 型带 createdAt → isRepRecord 对 temp **生效**（显示「N 次」），刷新后回退分钟档——H5 同款退化，测试钉死。
- 消费端迁移：home_exercise_test/exercise_sheet_test/account_switch_cache_test 等 ~30 例改 override Notifier（T2 工作量主项）。

### 3.3 WaterNotifier（T3）
- 水卡 `_waterOverride` 单值 → `AsyncNotifier.family(date)`：乐观 +1/-1 活在 per-date Notifier；切日期天然复位；summary invalidate 后 override 不再遮蔽真值（M6 债①根治）。行为文案零变更（M6 逐字面保持）。

### 3.4 actualDeficit（T7）
- 历史拉取 ≙ fetchDeficitHistory（app.js:1521+）：昨天起 6 天，逐日 `getDailySummary`+`getExercises` 并行（**复用现有路由，不新增云函数**）；TDEE 按 `computeMetabolism(body, targetWeight)`；今日实时态并入。
- 均值算法复用已移植 `domain/deficit.dart`（≥2 天生效闸，logic.js:162 同构）。
- 缓存 prefs 键逐字 `sg_actual_deficit_<uid>`（≙ localStorage 键，跨栈对齐）；代谢卡消费点接「我的」页 `#metab-deficit` 位（index.html:220）：文案 `近N天均值(消耗−摄入)`（:1601）+ note（:1604）；重算时机 ≙ renderRing :344（invalidate 驱动）。
- 失败面：历史拉取单日失败按 null 跳过（H5 `.catch(() => null)` 同款）。

## 4. UI 设计

### 4.1 plate-head + 问候头（T1）
- 卡头行：`‹ [日期胶囊] ›`；胶囊三态逐字（renderPlateDate :208-211）：今天=`今天<small>· 右滑看历史</small>`、昨天=`昨天<small>M/D</small>`、其余=`M月D日<small>周X</small>`；`date==今天` 时 › `visibility:hidden`（保位，≙ :213）。‹ 恒在。
- 问候头 ≙ renderGreeting :287-294：五档 `h<6 夜深了 / <11 早上好 / <14 中午好 / <18 下午好 / else 晚上好`，有昵称拼 `${greet}，${nickname}`；下挂 `M月D日 · 星期X` 行；**恒用系统时钟、不随 ‹› 变、不随 rebuild 之外的时点变**（H5 仅 loadMainBundle 调用一次，Flutter 挂 profile 数据流即可，档位刷新时机差异登记 R4）。
- 版式（胶囊/箭头视觉）R4 自定，收官目检定稿。

### 4.2 食物库管理弹层（T4）
- 入口：「我的」页「食物库」soft 钮（≙ index.html:249 `#btn-foodlib`），位置与提醒卡同族排布（R4 定）。
- 弹层「我的食物库」+ seg 双 tab（默认自定义）；副文案逐字：自定义 tab `自定义 N 条 · 点餐次标签可改归类`、内置 tab `内置 N 条 · 已移除 M`。
- 自定义行：FoodThumb+名称/热量 + 餐次标签组（每行并排 kind 钮，点按=置为该归类并 `setCustomFoodMeals` 提交，≙ :1355-1365；toast `已归到早餐/零食/正餐 · 搜索时只在对应餐次出现`——**午/晚都算「正餐」文案**，CF_MEAL_MAP 三态逐字）+ ✕ 删除（确认「删除自定义食物」/「删除后不可恢复；已记录的饮食不受影响。」→ toast「已删除」）。
- 内置行：名称 + 钮文案 `移除/恢复` 二态；toast `已移除「名」/已恢复「名」`；提交 `setHiddenFoods(全量 ids)`（≙ :1385-1391 全量语义）。
- 加载失败空态：`⚠️ 加载失败：msg||网络异常`（:1338 族）。
- id 语义：管理列表=裸 `_id`（侦察证实 cf_ 前缀只在搜索结果 id，前端从不剥用）；仍钉一条回归测试锁死「管理页不经前缀剥除路径」。

### 4.3 目标体重编辑弹层（T5）
- 入口：代谢卡目标体重行「点击修改」（≙ `#btn-edit-goal`）。
- 弹层逐字 ≙ index.html:335-351 + app.js:1427-1465：标题「编辑目标体重」；±0.5 步进（`+(x±0.5).toFixed(1)`，闸 30-150，顶格值不动+toast `最小 30 kg`/`最大 150 kg`）；hint `体重范围 30–150 kg · 点数字可直接输入 · 热量目标由系统按档案自动计算`（en-dash 逐字）；钮「保存目标」。
- 保存链：`PUT /user/goal {targetWeight}` → 本地 profile 回写 → 目标行+代谢卡（达标 ETA）刷新 → 关层 → toast「目标体重已更新」；失败「保存失败：msg||网络异常」层不关。
- **setGoal 文案收口（M5 旧账）**：身体档案保存链 updateProfile 与 setGoal 拆两个 try——setGoal 失败说「目标同步失败：msg」不再冒充资料失败；`setGoalError` 桩补断言。

### 4.4 记录页 7 天行（T6）
- 顶部 chip 行 ≙ renderDateRow :498-516：今天往前 7 天、末位文案「今天」；点击置 `plateDateProvider` 并刷新（无未来闸）；选中态高亮；列表随日期。chip 视觉 R4。

## 5. 契约与红线

- **云函数零改动**（红线）。T4 四方法走既有路由：`GET /foods/custom`、`PUT /foods/custom/:id`（meals）、`DELETE /foods/custom/:id`、`PUT /foods/hidden`；T7 复用 `GET /diet/summary?date`+`GET /diet/exercises?date`。
- health_api.dart 补：`listCustomFoods / setCustomFoodMeals(id, meals) / deleteCustomFood(id) / setHiddenFoods(ids)`；getDailySummary/getExercises 已有 date 入参直接复用。
- fixture 双端锁：新增上述路由响应形状（listCustomFoods 平铺 15 键、setHiddenFoods 回 `{ok,ids}`、PUT custom/:id 回包形状按 index.js 实读）；H5 contract.test.js 动态生成自动跟。
- stub_health_api.dart 补四桩（语义按云实读：hidden 全量替换、meals 白名单、删除裸 id）。

## 6. 错误处理与 R4 差异登记

- 乐观链失败回滚（temp 摘除/水卡回退/删除回插）全部逐字 H5；toast 族口径统一 `jsOr(msg,'网络异常')`。
- 预期 R4 登记面：①› 隐藏用保位（同 H5 visibility）；②问候头档位刷新时机；③无右滑手势（按钮等价）；④管理弹层/7 天行/胶囊视觉创新；⑤记录页与首页日期共享的 UI 反馈时序。

## 7. 测试与门禁

- 每批 TDD；widget 测试挂 `shiguangTheme()` 真主题；首页/我的页卡高基线**预期变动需重钉**（改卡警示已在测试注释，T1/T4/T5 三批各自重钉）。
- 关键回归钉：temp 行 rep 显示生效→刷新退化；日期共享（记录页点 3 天前→首页停同天）；未来闸 toast；归类 toast 午/晚→「正餐」；hidden 全量提交；setGoal 双 try 文案分流；deficit ≥2 天闸+单日失败跳过。
- 门禁四道：`dart analyze lib test` 0、`flutter test` 全绿报数、`npm test`（H5 零 diff 除 fixture 新增）、`npm run check:version`；收官沙盒 release（ASCII 路径）+ arm64 入库 + 模拟器全链目检（R4）+ 真机验收单（含 M6 遗留运动异常真机复测项+工单跟进）。

## 8. 验收标准

1. 首页可 ‹ 往前翻任意日期/› 回今天（未来闸 toast），五卡数据随日期；问候头五档正确。
2. 记运动保存即显 temp 行+环/代谢即时联动+toast 即弹；失败回滚；与 H5 时序一致。
3. 水卡切日期显示正确（跨日遮蔽债消失）；记录页 7 天行可用且与首页共享日期。
4. 食物库管理：自定义改归类/删除、内置移除/恢复全链路互通 H5（同一份云端数据）。
5. 目标体重独立可编辑，代谢卡/达标 ETA 联动；身体档案保存链失败文案不再失真。
6. 代谢卡显示近 7 天实际缺口（≥2 天生效），缓存命中/失效行为对齐 H5。
7. 终审 Minor 六条清零或书面销账；2.5.0 四门禁绿+正式包入库+真机验收单交付。
