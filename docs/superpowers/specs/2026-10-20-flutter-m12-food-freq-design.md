# M12 食物频次（吃过次数）设计档

- 日期：2026-10-20
- 分支：`feat/flutter-m12-food-freq`（基点 `main` = M11 合并后的 `b1750d9`）
- 老大原话：「好像没生效过，你可以优化一下，在食物库记录我吃过这个菜多少次」
- 裁决：计数口径＝**全部历史**（2026-10-20 三选一决策卡选定，非推荐项）；旧包 `食光Flutter-v2.7.1.apk` 按 M11 裁决留在仓库。

## §0 为什么做

M11 的 T5 已把「常吃排序」的初始化从 30 路并发压到 6 路，但**往返次数仍是 30**
（逐日 `GET /diet/records?date=`）。按 M9 §0 的实测方程（往返次数 × 约 400ms），
那次冷启动仍要 ~30 次网关往返。M12 把它压成 **1 次**，同时把「吃过多少次」这个
老大要的数字放到食物库里可见。

连带后果（已向老大报备）：常吃排序的窗口从「近 30 天」改为「全史」。
当年定 30 天窗口的唯一理由是「要发 30 次请求」，该前提被一次往返消掉；
若日后要「最近常吃的排前面」，另加时间衰减，不回头改窗口。

## §1 云函数：`GET /diet/records/freq`

位置 `HealthyDiet/cloudfunctions/api-diet/index.js`（路由块紧接 `/diet/records` GET 之后）。
响应：

```json
{ "counts": { "米饭": 12 }, "scanned": 87, "complete": true }
```

- `counts`：按 `name.trim()` 聚合的全史次数；空名/非字符串丢弃（与客户端旧聚合口径一致）。
- `scanned`：实际扫过的记录条数（排查用）。
- `complete`：翻页收集是否走到短页（`false` = 被 `maxPages` 截断，`counts` 只是下界）。
  **不静默少算**——这是 M11「绿了但真机不工作」教训的直接应用。

实现分层：

| 文件 | 职责 | 可测性 |
|---|---|---|
| `api-diet/freq.js`（新） | `countNames` / `collectAll` 纯逻辑 | `node --test tests/records-freq.test.js` 4 条 |
| `index.js` 路由块 | 把 `fetchPage` 接到 `sg_records` 查询 | 本地不可测（见 §4） |

**没用 aggregate**：全仓云函数零 `aggregate(` 实迹，`@cloudbase/node-sdk ^3.7.0`
的聚合 API 无法在本地验证（函数目录未装依赖、无真实库），而
`where({uid}).orderBy('createdAt','asc').skip(s).limit(l).get()` 与
`/report/month`（`index.js:514`）同族的调用形态已在生产跑通。
单次 `limit(1000)`、`maxPages=20`（上限 2 万条），越界由 `complete:false` 自报。

**对 H5 的影响**：新路径独立（`/diet/records` 的 GET/POST/DELETE 分支一字未动），
H5 的 `js/api.js:71-73` 不调它；`main` 顶层 try/catch（`index.js:628`）保证新分支
异常只回 500 给调用方，不波及其他路由。

## §2 客户端

- `HealthApi.getFoodFreq()`（`lib/data/health_api.dart`）→ `_client.call('/diet/records/freq')`。
- `FoodFreqNotifier.ensureLoaded()`（`lib/features/record/food_freq.dart`）：
  1 次请求 → `parseFoodFreqCounts` 校验 → 落盘 → 打标记。
  - 响应缺 `counts`／非对象 → 抛 `FormatException` 走失败支：**不落标记、不把空表当全史**。
  - 网络失败 → `_started` 复位，本会话可重试，state 保持空（列表按云端原序）。
  - `complete=false` → 计数照用并落标记（重复查询只会得到同样的下界）。
- prefs 键升 v2：`sg_food_freq_counts_v2_<uid>` / `sg_food_freq_init_v2_<uid>`。
  v1 全局键、v1 分账号键**读到即删**——v1 标记若被当成「已初始化」，老用户会永远
  停在 30 天计数上看不到全史数。
- 删除的旧机制：`kFreqInitDays` / `kFreqInitConcurrency` / `_runLimited` /
  `recentIsoDates` / `aggregateFreqFromRecords`（全仓仅本文件使用，已 grep 确认）。
- 三处展示（同一份 `foodFreqProvider`，`EatenCountBadge` 只在 >0 时渲染）：
  1. 我的食物库·自定义行 → 名字右侧徽标「吃过 N 次」；
  2. 我的食物库·内置行 → 同上；
  3. 记一笔搜索结果行 → **并入 meta 单行文本**（`蛋类 · 1 个约 50g · 吃过 2 次`）。
     原因：搜索结果行右侧被 kcal + 动作按钮占满，360dp 下名字列只剩 ~82px，
     独立徽标实测溢出 32px（测试抓到）；单 `Text` + ellipsis 恒不溢出。
  食物库管理弹层开层时补一次 `ensureLoaded()`（搜索弹层原本就有）。

## §3 判据（本批实跑）

| 闸 | 结果 |
|---|---|
| `node --test`（H5 全量，含新增 4 条 freq 纯逻辑） | **98 pass / 0 fail**（基线 94） |
| `npm run lint` | 0 error（18 warning 全为既有） |
| `node --check index.js && node --check freq.js` | 通过 |
| `dart analyze` | No issues found |
| `flutter test`（全量） | 见收官记录（基线 540） |
| 新增 Dart：`test/food_freq_test.dart` 重写 14 条 | 绿 |
| 新增 Dart：`test/food_eaten_count_test.dart` 4 条（三面徽标 + 320dp 溢出压力档） | 绿 |

TDD 留痕：每条新判据都先见红（freq 模块缺失 → `countNames/collectAll is not a function`；
Dart 侧旧实现下 `freqCalls=0`、v1 标记冒充已初始化、徽标文本不存在、320dp 溢出 72px）。

## §4 未验证项 / 部署闸（**已于 2026-10-20 部署并真机验收**）

**云函数路由的 db 查询本地跑不起来**：`api-diet/` 无 `node_modules`（`require('@cloudbase/node-sdk')` 即失败），
H5 测试全走 `setUseMock(true)`，仓库对云函数是**零测试覆盖**。所以
`skip/limit/orderBy` 这 3 行只有部署后才能真验。

**已部署**（老大 10-20 授权；MCP 设备码登录 → `manageFunctions updateFunctionCode`，
RequestId `f3c9f6cf-4e36-4304-b709-3886069ad569`）：

| 验收项 | 结果 |
|---|---|
| 函数冷启动/路由完好 | `POST /auth/login` 探针返回业务错误「用户名或密码错误」（非 500）⇒ 部署包含 `freq.js` 且路由表正常 |
| 老路由不回归 | App 真机登录态下首页/记录/我的全部正常出数；H5 未接新路由，老分支零改动 |
| 新路由真机可用 | `/diet/records/freq` 被 App 调通，六道菜次数与云端逐条相等（见 §5） |

回滚：用 `b1750d9` 的 `index.js` 重部署（本批之前的生产版本）。

## §5 真机目检记录（2026-10-20，RMX5010 / Android 16，APK 2.7.3+22703）

出包：ASCII 沙盒 `C:\sg-rel-build`，带 `pubspec.lock`（`shared_preferences 2.5.5 / android 2.4.28`，
与仓库锁逐字一致——M11 §15 的坑已堵）；`BUILD_EXIT=0`；arm64 分片 **19,769,404 B**，
md5 `b6b582ec30b081cdeb04f838d15616c2`，验签 SHA-256 `cc7e2dd9…00cc4f0` 与 v2.7.1 同一把 keystore；
`adb install -r` 覆盖安装（保留数据，顺带验 v1→v2 prefs 迁移）。

对账基准：`sg_records` 中该账号（`u_7f88ac…`）的全史计数，用 MCP 只读查询逐条取。

| 界面 | 显示 | 云端全史 | 结论 |
|---|---|---|---|
| 食物库·自定义 | 鸡胸肉 1 / 苦瓜炒蛋 3 / 蒜薹鸡块 3 / 冬瓜炒肉 8 | 1 / 3 / 3 / 8 | ✅ |
| 食物库·内置 | 纯牛奶 25 / 库迪面包 8 / 煮鸡蛋 11 / 肉包 7 | 25 / 8 / 11 / 7 | ✅ |
| 记一笔搜索 | 纯牛奶「吃过 25 次」、煮鸡蛋 11、库迪面包 8…按次数降序 | 25 / 11 / 8 | ✅ |
| 窗口口径判别 | 纯牛奶显示 **25**（全史），非 19（近 30 天） | 25 vs 19 | ✅ 全史 |
| v1 键迁移 | 覆盖安装后首开即显示全史数 | — | ✅ v1 标记未冒充已初始化 |

**真机抓出并修掉的两个缺陷（单测没覆盖到，已补判据）**：
1. 搜索行的旧 meta `Text` 没删干净 ⇒ 每行渲染**两行 meta**。
2. 次数跟在 meta 后面，被窄列省略号吃成「吃过…」⇒ 数字看不见。
   改为 **次数放在 meta 前**（`吃过 N 次 · 奶类 · 1 盒 250ml`），先舍 meta 尾巴。
   回归钉：`test/food_eaten_count_test.dart` 新增「单行 meta + 次数在行首」一条，
   已用「回滚生产文件」验证会变红（回滚后 3 条挂）。

**未目检项**：M11 目检单里的「打字出结果」「记一笔」「删一笔」三条**未跑**——
adb 无法输入中文，且写入会产生真实饮食记录。这三条仍归老大有空自验（新包已含 M11 全部改动）。

## §6 行为差异登记（老大知情口径）

1. 常吃排序窗口 **近 30 天 → 全部历史**（理由见 §0；已当面报备）。
2. 老用户本地的 v1 计数作废，升级后首开食物库/搜索弹层重拉一次（1 次请求）。
3. 搜索行的次数是 meta 文本的一部分，窄屏/长 meta 时可能被省略号截掉——
   数据仍在，食物库管理弹层里可看全。
4. `complete=false`（>2 万条记录）时显示的是下界；当前数据量远未触及。
5. 「删除记录不回减」只在本会话内成立：App 内 `record()` 只加不减（沿用老大
   「吃过是事实」的口径），但云函数下次全量重算时，**已删除的记录不再计入**。
   即同一道菜删光记录后重装/换号，徽标会回落到 0——这是云端只有现存记录、
   没有「吃过的历史」这一事实的直接结果；要真正不复减，得另建事件表，本批不做。

## §7 没做的

- H5 未接入该路由（H5 没有「吃过次数」界面），因此 `contract/fixtures/diet-core.json`
  未收录——fixture 的语义是「双栈都存在的客户端方法」，单边收录会让 H5 契约测试红。
  Dart 侧路由路径由 `test/food_eaten_count_test.dart` 经真实调用链钉住。
- 云函数路由本身无单测（环境限制见 §4），验收依赖部署后真调用。
- 未做「时间衰减排序」「按餐次频次」——老大未提，YAGNI。
