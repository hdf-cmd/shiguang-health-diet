# M11 设计——请求往返数削减批（搜索本地化 + 写后乐观 + 磁盘缓存）

日期：2026-10-19 ｜ 里程碑：M11 ｜ 版本目标：本批不动 pubspec 版本号（发布批再升）｜ 分支：待老大指令
提出：老大反馈「每次加载数据都很慢，搜索东西出来得也很慢」。范围裁定（AskUserQuestion 已选）：**纯客户端，不动云函数**；症状定位勾选＝冷启动进首页 / 记完一笔后刷新·我的页 / 打开搜索·打字出结果。

## 0. 诊断基线（事实，全部当场可读）

**量具复用 M9 §0 实测**：网关短连单程 ~400ms 是地板（`/foods/builtin` 0.44-0.56s、`/foods/custom` 0.43s、`/diary/summary` 0.38-0.43s），冷热差 <0.15s，**云函数不是瓶颈**。故本批根因方程＝**往返次数 × 400ms**，不是"某次请求慢"。
调查初稿曾把「云函数冷启动/并发扩容」列为候选，被 M9 实测否掉，此处按事实更正。

逐症状往返数账（行号实锤）：

| 场景 | 现状往返 | 实锤位置 |
|---|---|---|
| 打开搜索弹层 | 1（空词全量）+ **30 并发**（常吃 30 天回填） | search_sheet.dart:61/70-77 → food_freq.dart:181-188，kFreqInitDays=30 |
| 打字 3 个词 | 3（每词 1 次 HTTPS，服务端内再串 2 趟 DB） | search_sheet.dart:88-93 → health_api.dart:134 → api_client.dart:150；index.js:54+68 |
| 记一笔 / 删一笔 | 1 POST + **2 次重拉**，且整卡回骨架 | record_controller.dart:93-98（写后 `swrInvalidate` 删键）→ home_controller.dart:46-49（`cached==null` 走 loading） |
| 冷启动进首页 | 4（summary/records/exercises/profile），无一命中 | home_screen.dart:129/207/210/215；swr_cache.dart 注释自述「不做磁盘持久化」 |
| 我的页代谢卡 | 12 并发（6 天 ×2 接口），当日 prefs 命中则 0 | profile_providers.dart:199-212，缓存钉 :165 |

**R4 偏差取证（本批最重要的发现）**：记一笔/删一笔 Flutter 走「等回包 → 删键 → 骨架 400ms」，而 H5 一直是**乐观更新**——`js/app.js:663`「乐观更新：立即入列表+环，不等网络（反馈8）；失败回滚」、`:563-571` 乐观删除并本地减算 summary、`:577-581` 失败放回。M9 的「写后删键」是为防「回访播种写前旧数」（M9 spec §1 失效矩阵），副作用是把写路径打回了「白屏等网络」。**故 T2 不是加新行为，是把 H5 既有行为还原，性能与还原度同向**。

## 1. T1——搜索本地化（打字零往返）

**形态**：唯一数据源仍是云端搜索路由的空词形态（`/foods/search?keyword=''` 返回全部内置 35 条全字段 + 自定义 ≤20 条，index.js:57-93），开层拉一次进缓存；打字改由**端上过滤**，不再发请求。

- 缓存键 `foods.full`（SWR + T3 磁盘）；`searchProvider` 改为：命中 `foods.full` → 同步过滤返回；未命中 → 走现行网络首拉（首访仍 ~400ms，属预期）。
- 端上过滤逐字复刻 index.js:57-93 的**筛选条件**（不复制数据副本，故无 foods.js↔Dart 漂移风险）：内置 `f.name.contains(kw)`（区分大小写，bug-for-bug）+ `!f.meals || f.meals.contains(meal)` + `hidden` 已在服务端剔除（随全量结果自然带上）；自定义 `name` 大小写不敏感字面匹配 + `meal && fm.length && !fm.contains(meal)` 跳过；结果序＝内置在前、自定义在后，再叠 `sortFoodByFreq` 稳定降序（现成函数，food_freq.dart:22-37）。
- **≥20 条自定义的截断守卫**：空词全量的自定义受服务端 `limit(20)` 约束，本地过滤无从覆盖第 21 条以后。判据＝返回项中 `id` 以 `cf_` 开头者恰为 20 → 视为「可能被截断」，打字改回落现行云端逐词搜索（不新增请求、不复刻映射逻辑）。老大当前 16 条自定义，守卫暂不触发，登记为已知边界。
- 不搬内置库进 Dart（避免副本漂移）；不改服务端。
- CancelToken/在途取消：T1 后打字零请求，本项自然消解；仅守卫分支仍无取消，登记不处理（YAGNI）。

**测试钉**：①开层拉一次全量后连打 5 词网络计数＝0；②内置区分大小写、自定义不区分（bug-for-bug 断言）；③餐次过滤与云端同集合（用 contract/fixtures/diet-core.json 的 searchFoods 样本作对照尺）；④`cf_` 20 条守卫触发回落；⑤常吃排序仍生效且平局保序。

## 2. T2——写后乐观（还原 H5 语义）

- `addRecord`：POST 发出前先把 temp 记录插入 `records.<date>` 缓存、并把 kcal/protein/carb/fat 加进 `summary.<date>`（`Summary` 六字段不可变，重构造即可，target/water 不动），立即重绘；回包成功后 invalidate **provider 但不删缓存键**（→ 播种旧值即刻显、后台对账覆盖），失败则移除 temp 并减回 + 现行 toast 文案。temp 字段形态逐字对齐 `js/app.js:664-670`。
- `deleteRecord`：同 H5 `:563-571` 乐观移除+减算，成功后台对账，失败放回+加算（`:577-581`）。
- `_syncDay` 去 `swrInvalidate`（record_controller.dart:94-95），保留 provider invalidate；M9 失效矩阵中「记餐/删餐」两行据此改记（防旧数由「乐观写覆盖了缓存」保证，不再靠删键）。
- 在途钮禁用（`_inFlight`）与「请稍候…」文案保持不变——乐观态只改数据呈现，不改防连点。
- 运动/喝水/体重的既有乐观路径不动（M7/M9 已定式）。

**测试钉**：①记一笔在 `await` 前列表已含该项且环已加算（用受控 Completer 卡住网络证明"未回包已重绘"）；②失败回滚后终态等于记前；③成功后后台对账把终态拉平；④删一笔同上三面；⑤既有 record_sheet / home 测试的「写后刷新」断言按新时序改记（不得靠放宽判据变绿）。

## 3. T3——磁盘缓存（冷启动秒显）

- `SwrCache` 增磁盘后层（SharedPreferences，键 `sg_swr_disk_v1`，JSON）：只持久化四个族——`records.<date>`/`summary.<date>`（近 7 天）/`foods.full`/`weightTrend`。其余（profile/exercise/报告）不落盘。
- 读序：内存 → 磁盘 → 网络；写序：内存同步 + 磁盘节流写（合并 300ms 内的多次写）。冷启动首次访问即播种「上次终态」，网络回包覆盖 → 首页由「4×400ms 骨架」变「0ms 旧数 + 后台刷新」。
- 失效：沿用 M9 失效矩阵，删内存键时同步删磁盘键；`auth_state` 换号/登出的 `swrCache.clear()` 补磁盘清理（防串号）。
- TTL 不做（M9 §5 裁定沿用：跨启动新鲜度靠后台刷新，不靠过期）。
- **呈现时序差异登记（需老大知情）**：冷启动会先显上一次的数据（可能隔夜），≤400ms 内跳新数。这与 M9 已批的「切日期先显旧数」同一口径，但**跨进程**是新增面。

**测试钉**：①冷启动首帧即 AsyncData(旧) 不发骨架；②回包覆盖且回写；③写路径删除磁盘键；④换号清磁盘；⑤磁盘 JSON 损坏即弃不炸。

## 4. T4——token 读内存化

`api_client.dart:101` 每请求一次 `FlutterSecureStorage.read`（Android Keystore，数十 ms 级）→ 首次读后驻内存，`write/clear` 同步更新内存镜像，续期路径（:111-115）改读内存。收益：单页 4 请求＝4 次读→1 次；30 并发回填＝30 次→1 次。单 isolate 内无并发一致性问题。

## 5. T5——常吃回填不再放大成 30 并发

- 并发限流 ≤6（信号量），避免与搜索/首页请求抢连接与带宽。
- 标记条件放宽：`failures == 0` → **只要有任一日聚合成功即 `markInitialized`**（food_freq.dart:196）。理由：现条件在弱网下永不落标记，导致**每次冷启动重复 30 请求**——这是「每次都慢」的直接机制。差异登记：个别日失败则该日不计入频次（频次只影响排序，非数据正确性面）。
- T1 落地后频次与搜索解耦：计数迟到只做一次重排，不挡结果。

## 6. T6——结果图磁盘缓存

`pubspec.yaml` 加 `cached_network_image`；`food_thumb.dart:45-48` 的 `Image.network` 换 `CachedNetworkImage`（`data:` → `Image.memory` 支不动）。现状＝内置 35 条全带 https、一次搜索最多 ~55 行同时拉图且无磁盘缓存。代价：APK 体积增约 1-2 MB（现 v2.7.1=19.48 MB），登记供老大裁决；不选则本项划掉。

## 7. 不做清单（边界）

- **不动 `api-diet`**（老大裁定 + M9 §5 同裁定；该函数 H5 共用）。
- 不加云端批量/聚合路由（首页压成 1 次往返要动共用函数，越界）。
- 内置库不在 Dart 侧建数据副本。
- 我的页 12 并发保持原样：当日 prefs 命中已零请求，且 6 天窗口跨两个自然周，无法复用 `/report/week`（该路由只回 kcal 数组、不含 exKcal，index.js:493-502）。
- H5 线零改动。

## 8. 门禁、验收与前置

- 四门禁：`dart analyze` / `flutter test` / H5 `node --test` / `check:version`。基线 511 绿（M10 台账）。
- 新增「往返数账」验收表：搜索打字 5 词 5→0、开层 31→1、记一笔呈现 400ms 骨架→0ms、冷启动首页 4 请求骨架→0ms 播种、频次回填 30→≤6 且仅一次会话成本。
- 真机目检四面（老大勾选的症状位）：冷启动进首页、打开搜索打字、记一笔/删一笔、我的页；互通抽查（云端数据面零改动，但乐观写的终态须与 H5 对账一致）。
- **前置阻塞**：M10 工作区未提交（`login_screen.dart`/`main.dart`/`report_screen_test.dart` 已改 + `m10_gate_transition_test.dart` 未跟踪 + M10 spec）。M11 文件面与 M10 不重叠，但 `pubspec.yaml`(T6) 与全量回归交叉。**建议老大先按双分支流程落地 M11 之前的 M10，再开 M11 分支**；若要并行，T6 先摘除、pubspec 不动。

## 9. 执行台账（2026-10-19，M11 首批）

**前置处置（老大裁决「M10 直接丢弃」）**：整批已存 `.mimosa/m10-abandoned-2026-10-19/`（`m10-full.diff` 8279B + 未跟踪测试 6435B + M10 spec 9662B，字节当场回读），随后 `git checkout` 掉 `main.dart`/`login_screen.dart` 并删除 `m10_gate_transition_test.dart`。**唯一保留件＝`report_screen_test.dart` 的 11 行时间炸弹修复**（老大二次裁定「保留这个测试修复」）——该改动与动效无关，写死 `week-bar-fill-2` 每逢周三（`weekTodayIndex==2`）必撞今天柱的 LinearGradient 支，丢掉会让 M11 的 flutter test 门禁在 10-21 周三无端变红。

**完成格**：T4 → T5 → T1 → T2 → T6（T3 见 §10，未做）。执行顺序相对原计划调整：T1 提前于 T3，因 T3 的落盘白名单要含 T1 新键 `foods.full.<meal>`。

**门禁数字（当场跑）**：`dart analyze lib test` → No issues found；`flutter test` → **528 绿**（基线 507，+21）；H5 `npm test` → 94 绿；`npm run check:version` → 1.4.0 一致。**pubspec 版本号本批未动**（沿 M10 口径，发布批再升）。

### 9.1 判据变更清单（推翻既有钉，逐条留痕）

| 钉 | 旧判据 | 新判据 | 依据 |
|---|---|---|---|
| `food_freq_test` 部分日期失败 | `failures==0` 才落 init 标记 | 有任一日聚合成功即落标记 | 弱网下标记永不落盘 ⇒ 每次冷启重放 30 请求（T5） |
| `record_flow_test` M9终审I-1钉① | 写后 `records.<date>`/`summary.<date>` 两键**归 null** | 两键**保留**，但终态不得含写前旧数 | T2 乐观写取代删键；不变量（不得播种旧数）由「乐观写 + 提交后 stamp/重建对账」共同保证 |
| `record_flow_test` ② | `lastSearchKeyword=='鸡'`（逐词打云端） | 请求数=1 且 `lastSearchKeyword==''`；另加「米饭被滤掉」正向断言 | T1 端上过滤。per100 的「按克加」正向覆盖移交 ③/③b（本处删除不构成减覆盖） |
| `custom_food_sheet_test` 空结果区入库 | 「以当前关键词重查」 | 「清快照重取」+ **入库后结果区搜得到该条**（新增更强的终态断言） | T1；H5 `app.js:1251` 逐词、Flutter 空词快照后本地过滤，两支终态同集（截断由守卫兜） |
| `search_sheet._addFood` toast 时序 | 等回包成功才响 | 乐观位之后立即响（失败再补「添加失败」） | 还原 H5 `app.js:677`；同键在途丢弃支由 `isInFlight` 预检拦（≙ H5 btn.disabled） |

### 9.2 本批新发现的两个缺陷（都不是"慢"，是"错"）

1. **🔴 迟到回包把乐观值盖回去＝删掉的行闪一下又回来约一个往返**。根因：M9 SWR 的「先播种 + 后台刷新」中，那次刷新在**服务端提交之前**发起，拿到的是提交前的合法读数——代次判据也判不出来。处置：`SwrCache.hold/release/stamp` 三件套 + `RecordController._holdDay`（乐观位时挂起）/`_reconcileDay`（finally 里解挂+stamp+重建）。反证钉＝`optimistic_write_test ④`（摘掉 hold 即红）。
2. **🔴 Riverpod 3.4.3：AsyncNotifier 的 build 抛错时其 `.future` 永不 settle**（有监听者也一样；只有 AsyncValue 正常落 AsyncError）。实测四型（无监听/有监听/autoDispose 中转/重复读）全挂，容器 dispose 时才冒成 `StateError`。生产影响：若 `SearchNotifier` 改为「另立 provider 再 `await .future`」，断网会让弹层永久停在「搜索中…」而不是既有契约的「搜索失败：msg」+「重试」。处置：快照在 `fetch` 内部取（不跨 provider await），并把 ⑥ 号钉的断言形态固定为读 AsyncValue。**登记为框架级坑，后续任何 `.future` await 都要绕。**

### 9.3 与 M9 文档的口径冲突（须回写 M9 spec 或本 spec 为准）

M9 spec §1 失效矩阵把「记餐/删餐 → 删 summary/records 键」列为验收基线，M11-T2 已按上表推翻；M9 §5 不做清单里「磁盘持久化缓存（会话级足够）」与「搜索关键词缓存（本就要求实时）」两条也被本批分别推翻（T3 待做 / T1 已做）。以本 spec 为准。

## 10. T3 执行记录（10-19 续：老大裁定「保守版 a——登录即清盘」）

**形态**：新文件 `lib/data/swr_disk.dart`。单 blob 存 SharedPreferences（键 `sg_swr_disk_v1`，`{owner, entries}`），冷启动一次读盘灌满内存（不做每键一条，避免启动期 N 次平台通道）。

**owner 生命周期**（保守版的全部要义）：
- `login/register` 成功 → 经 `_invalidateAccountScopedCaches → SwrCache.clear → disk.wipe`（清 entries + owner）；
- `profileProvider` 首次解析出 `p['id']` → `bindOwner(uid)`（**不 await**，旁路绝不拖挂 profile 链）；uid 变化即先清盘再绑；
- owner 未绑定期间 `writeEntries` 直接丢弃 ⇒ 没确认账号之前一个字节都不落；
- `bootstrap` 无改动，播种点在 **main() 里 runApp 之前**（见下坑②）。

**白名单**：`records.<date>` / `summary.<date>`（近 7 天，超窗落盘时剪枝）+ `foods.full.<meal>`（T1 新键）。profile/exercises/周月报/weightTrend **不落盘**——`WeightTrend` 无 toMap、报告页不在老大勾选的症状位，本批按最小可用收口（原 §3 写的 weightTrend 一项据此**划掉**，登记为差异）。
**编解码按键前缀驱动**，值自带类型标记不需要；`summary.*` 必须还原成 `Summary` 对象（`read<T>` 的类型闸认运行型不认 Map，否则冷启动白播一次空）。

**🔴 本轮新踩并修掉的三个真问题**
1. **磁盘 IO 放错层会把启动门控整条拖挂**：早先 `hydrate()` 挂在 `AuthGate.bootstrap` 里 `await`，实测 `auth_expiry_test` 两用例「Shell 永不出现」——widget 测试的 `pumpAndSettle` 不驱动真实平台通道 IO，`SharedPreferences.getInstance()` 的响应永远不落地。改到 `main()` 里 runApp **之前** await（同时省掉「首帧先画骨架再改数」）。
2. **盘层必须"拿不到盘就当没盘"**：`_prefs` 现返回 `SharedPreferences?`，异常吞掉且**不缓存 rejected future**（下次仍有机会）；`wipe/_write` 拿不到盘即静默返回。落盘是缓存旁路，无资格让主流程失败。
3. **🔴 绑定前发生的写入被静默丢弃 ⇒ 冷启动永远播不出数据（只有真机能发现）**。v2.7.2 首装后在 RMX5010 上实测：`am force-stop` → `am start -W`（TotalTime 194ms）→ **730ms 处截图仍是骨架**（环心"加载中"、右侧"今日额度 — kcal"）。根因是时序而非编码：owner 只在 profile 回包时绑定，而首页 summary/records 常在**那之前**就回包写入，`writeEntries` 未绑定即 `return` 把快照丢掉，绑定之后又没有任何补写触发点 ⇒ 盘上永远空。这条 13 条钉**一条都没抓到**，因为每条钉都单独测「绑定后写」或「未绑定不写」，没人测「未绑定写 → 绑定 → 落盘」这条跨阶段时序。
   修法：`writeEntries` 未绑定时**照样留存 `_pending` 快照**只是不落盘（且只有真要写才清 `_pending`）；`SwrCache` 的 `_syncDisk` 升为公开 `syncDisk()`；`profileProvider` 在 `bindOwner(uid)` 完成回调里补一次 `syncDisk()`（带 `ref.mounted` 闸，且整条链 `unawaited`——旁路不拖 profile）。换号安全性由「login 先 `clear()`（含 wipe 与清 `_pending`）→ 重取新账号数据 → 才绑定」这一既有顺序保证，另加钉⑮守住「绑定新 owner 不得把上一账号的在途快照写下去」。

**钉**：`test/data/swr_disk_test.dart` 15 条——①已绑定即播种且 Summary 还原成对象 ②未绑定不播 ③换号清盘（A 数据必消失，重新构造 disk 只读盘验落盘面）④同 uid 重复绑定不清盘 ⑤白名单外不落盘 ⑥超 7 天窗剪枝 ⑦blob 损坏静默视为空 ⑧删键同步落盘 ⑨clear 连盘清 ⑩无 disk 退化纯内存 ⑪未绑定期 flush 不产生盘内容 ⑫**生产装配真带盘**（`buildRootContainer(swrDisk:)` 的 cache.disk 与 swrDiskProvider 同实例——漏接则 T3 整批白做）⑬`SwrCache.clear→disk.wipe` 这一环 **⑭🔴 绑定前写入须在绑定后补落盘（真机缺陷复现钉）⑮换号绑定不得把上一账号在途快照写进新 owner**。

**门禁终数（10-19 当场跑）**：`dart analyze lib test` → No issues found；`flutter test` → **541 绿**（基线 507，+34）；H5 `npm test` → 94 绿；`check:version` → 1.4.0 一致。

**未做（真机侧）**：APK 未重打、真机目检未跑。老大勾选的四个动作（冷启动进首页 / 打开搜索打字 / 记一笔·删一笔 / 我的页）都要在新包上目检一遍才算收官；本批全部结论都是**结构账（往返次数）+ 单测**，没有设备实测。

## 11. T3 账号隔离的三档候选与裁决留痕（老大 10-19 拍 a）

前提事实：`SwrCache.read<T>` 在 lib 内 15 处**同步**调用，且缓存值是 Dart 对象（`Summary`/`WeightTrend`），故落盘需白名单+编解码、且须在首帧之前灌回内存才不改签名。真阻塞＝**冷启动首帧之前确认不了账号**：prefs 里的 `sg_food_freq_counts_<uid>` 只证明"本机最后一次用过谁"，不证明"当前 token 属于谁"，而 M9-T3 已把「A 号键留着 ⇒ B 号首帧显 A 数」钉成跨号脏源（`auth_state.dart:67-92`）。

- **(a) 登录即清盘 + owner 绑定**——**已采纳**。泄漏窗 0（换号必清），不依赖任何未核实假设；代价如实登记：同账号「杀进程再开」的首帧仍要等 profile 到手才开始积累落盘，第一轮冷启动不白播。
- **(b) 解 accessToken 的 JWT `sub` 作槽名**——**未采纳**。0 请求即可确认账号、冷启动首帧直接播种，但前提是网关发的 accessToken 是 JWT，**本机无凭据登录取证**，把功能建在未核实的厂商行为上不划算。留作下一批候选（若老大能给一次抓包/真机日志即可翻案）。
- **(c) T3 整块推下批**——**未采纳**（老大裁定要磁盘缓存）。

## 12. 真机目检单（v2.7.2+20702，装完照这五条走）

**出包事实（2026-10-19 21:35 当场核）**：ASCII 沙盒 `C:\sg-rel-build` 构建，`BUILD_EXIT=0`，三分片 arm64 19.0MB / armeabi-v7a 16.6MB / x86_64 20.4MB。入库件 `食光Flutter-v2.7.2.apk`＝arm64 分片，**19,900,728 字节**，md5 `306ff4a3120f9cd3c11f491eeaf813e3`（与沙盒原件 md5 全等，当场回读）。验签 SHA-256 `cc7e2dd99ff97e72c7c7edb5888aa04d36e8fa9c99bdec375fd83429700cc4f0`，与已入库 v2.7.1 **同一把 keystore**（DN `CN=Shiguang, OU=App, O=Shiguang`）。
**体积实测修正**：相对 v2.7.1（19,484,795B）只 **+416KB**，不是 T6 立项时估的 1~2MB——`--split-per-abi` 下 cached_network_image 与其插件面只进各自分片，估高了。旧包 v2.7.1 **暂不删**，目检通过后再按惯例替换 + `git rm`。

安装：`adb install -r 食光Flutter-v2.7.2.apk`（arm64 分片；先 `adb devices` 确认在列，掉线就重插 USB 并确认手机上允许调试）。

| # | 动作 | 期望 | 若不成立说明 |
|---|---|---|---|
| 1 | 杀掉 App 重开 → 进首页 | 第 1 次：仍走网络（登录首轮没有盘数据，属预期）；**再杀再开第 2 次应直接显上一次的数据**，无骨架 | 第 2 次还白骨架＝磁盘播种没生效（查 owner 是否绑定 / prefs 键 `sg_swr_disk_v1`） |
| 2 | 记一笔 → 打开搜索 → 连打 5 个字 | 每键即出结果，不再"打字→转圈→出结果"；切「早餐/午餐/晚餐/零食」各开一次只各拉一次 | 仍半拍才出＝快照没命中或守卫误触发回落云端 |
| 3 | 搜到食物 → 点「添加」 | 环和列表**立刻**变，toast 立即响；随后数字不回落、不加第二遍 | 数字闪回＝乐观位被在途回包覆盖（hold 失效） |
| 4 | 长按一条记录 → 删除 | 该行立即消失、环立即减算；**不许出现"消失又冒回来"**；删完切日期再切回来仍是删后状态 | 冒回来＝同 #3 |
| 5 | 开飞行模式 → 记一笔 | 先乐观落位，随后 toast「添加失败：…」并回滚；搜索弹层若之前打开过则仍可打字出结果（见 §13 差异①） | 不报错或永久转圈＝失败路径没走通 |

另加两条老规矩：进「我的」页看代谢卡与体重（本批未动，回归确认）；报告页周报/月报（未动，回归确认）。

## 13. 行为差异登记（相对 H5，本批新增）

① **搜索结果可离线打字**：快照已在端上后，打字不再依赖网络——H5 每次打字都要打云端，断网即"搜索失败"。方向是变好，但严格说与 H5 不同形。
② **冷启动首帧可能显上一次的数据**（跨进程播种，最坏隔夜），≤一个往返内被云端真值覆盖。M9 只批过会话内，这是新增面。
③ **常吃频次回填在弱网下可能少算个别日**（部分成功即落"已初始化"标记，不再每次冷启重放 30 请求）。只影响列表排序，不影响任何数据正确性面。
④ **toast 时序**：「已添加 X · 可继续添加」在请求发出时即响（H5 同款），失败再补「添加失败」；旧 Flutter 实现是回包后才响。
⑤ **自定义食物 ≥20 条时**搜索自动回落云端逐词（守卫 `foodLibraryLooksTruncated`），此时打字恢复"每词一次请求"的旧表现——宁慢不漏。老大当前 16 条，守卫不触发。

## 14. 真机取证结论与 T3 摘批（2026-10-19 22:17，RMX5010 / Android 16）

**取证方法**：`am force-stop` → `am start -W` → 730-920ms 处 `screencap`。Flutter 的 `uiautomator dump` 拿不到文本节点（自绘），故判"骨架还是数据"只能看截图。

| 轮次 | 包 | 早帧观测 |
|---|---|---|
| 1 | v2.7.2 build#1（T3 原版） | 环心"加载中"、右侧"今日额度 — kcal"＝**骨架** |
| 2 | v2.7.2 build#2（含 syncDisk 补写修正） | 同前，仍骨架 ⇒ 修正方向对但没命中根因 |
| 3 | build#4（print 全边界打点） | logcat 给出确定答案（见下） |

**根因定位到"哪一层"，但尚未定位到"为什么"**：
```
M11DISK readBlob: prefs 不可用（平台通道拿不到）      ← main() 里 hydrate 时
M11DISK profile 到手 disk=有 p[id]=u_7f88ac7026f0...   ← profile 正常解析出 uid
M11DISK _write: prefs 为 null，丢弃                    ← 启动 1.6s 后仍不可用
M11DISK _flushNow: 落盘 keys=[summary.2026-10-19] → 紧接着 _write: prefs 为 null
```
即：**`SharedPreferences.getInstance()` 在这个 release 包里持续抛异常**，owner 绑定与快照落盘的逻辑本身都跑到了（`writeEntries`/`_flushNow` 都被正确调用），只是每次拿不到 prefs 句柄。所以 §10 那两处修正（未绑定留存快照、绑定后 syncDisk 补写）方向正确但被这个更底层的失败遮蔽。

**顺带否掉的两条我自己的错误推断**：① 曾判"hydrate 放错层导致"——挪到 main() 是必要的（widget 测试证据成立），但不是本现象的根因；② 曾判"绑定前写入被丢"——确实是个真缺陷并已修，但修完早帧仍是骨架。两轮都是在没观测的情况下猜，白搭两次构建。

**连带疑点（优先级高于冷启动）**：常吃排序（M7-T8 `PrefsFoodFreqStore`）与缺口历史缓存（`ActualDeficitStore`）用的是同一个 SharedPreferences。老大对本批的追问回答是「**常吃排序好像从来没生效过**」——与该失败同向。若成立，则这不是 T3 一家的事，而是**三个功能共用的一条持久层在 release 真机上一直是静默降级**（`ensureLoaded` 的 `.catchError` 与 `addRecord` 的 `try/catch` 把异常吞成了"按云端原序显示"）。

**摘批裁定（老大 10-19 选）**：v2.7.2 定稿＝本批 5 项（T1/T2/T4/T5/T6）＋T3 代码保留但不生效（不崩、不拖慢、无副作用）。装机包 md5 `2900c4dc477ea1e9b3b4f315863d559c`（19,900,728B）；诊断 print 已从源码全部撤除，且经与装机那次构建逐行 diff 确认**剩余差异仅为注释与打点**，语义一致。终数：`dart analyze` 0、`flutter test` **543 绿**、H5 94 绿。

**M12 四步已建任务**：① 拿 prefs 异常原文 → ② 修持久层（顺带复活常吃排序与缺口历史）→ ③ 加区间查询路由 → ④ 用 B 路做"吃过多少次"展示。

## 15. 🔴 §14 的结论作废：根因是**我的构建流程**，不是代码（2026-10-19 22:56 复测翻案）

**真正根因**：ASCII 沙盒拼装时我**漏拷 `pubspec.lock`**（只拷了 `android lib pubspec.yaml analysis_options.yaml`），`flutter pub get` 于是无锁自由解析：

| | shared_preferences | shared_preferences_android |
|---|---|---|
| 仓库锁定（v2.7.1 用了一年，正常） | 2.5.5 | **2.4.28** |
| 我沙盒无锁解析（build#1–#5） | 2.5.6 | **2.5.0** |

错配版本在 Pigeon 桥上签名不一致，运行时炸出：
```
PlatformException: java.lang.NoSuchMethodError: no non-static method
 "Lio/flutter/plugins/sharedpreferences/SharedPreferencesApiRegistrar;
  .getAll(String, List, Continuation)"
```
同步与异步两个 API 全挂 ⇒ 整个 prefs 层静默失效 ⇒ 磁盘播种播不出数据。**代码一行没错。**

**复测证据（带 lock 重打，同一台 RMX5010）**：
- `M11PREFS` 诊断行命中数 **0**（该 print 只在 catch 分支）⇒ prefs 恢复正常。
- 真冷启动（`pidof` 确认进程已死 → `am start -W` TotalTime 158ms）→ **T0+718ms 截图已显出**「今日额度 1968 kcal／已摄入 1862 kcal／外环三段齐全」。修之前同一时刻是环心"加载中"＋右侧"— kcal"。
- 截图里环中心数 72 是 M9-B3 count-up 动画的中间帧（终值 106），非数据不一致。

**连带撤回两条误判**：
1. §14 说"常吃排序与缺口历史可能一起静默降级"——**不成立**，那是 prefs 假象的延伸推论。
2. 我把"代谢卡首屏显示预设缺口 500"当成 prefs 失败的旁证——**误读**：那只是 12 请求历史回包之前的正常中间态，滚动后同一张卡已变成"缺口为近 6 天实际日均 · 1113 kcal"。教训：**拿 UI 中间态当证据，和拿 mock 单测当交付证据是同一类错**。

**方法论账（这批最贵的一课）**：连续两轮"修代码"（留存快照 + syncDisk 补写、把 hydrate 从 bootstrap 挪到 main）都发生在**没有先核对"这个 APK 到底是不是仓库这套依赖打出来的"**之前。正确顺序应是：**怀疑代码前，先证明产物与仓库一致**（对 `pubspec.lock`、对版本解析结果）。五次构建、约一小时，本可以用一次 `grep version pubspec.lock` 省掉。

**交付影响**：先前入库的 `食光Flutter-v2.7.2.apk`（md5 `2900c4dc…`）是**无锁产物，依赖版本与仓库不符，只能算探针**，须由带 lock 的构建（build#7）替换。§14 里"T3 摘出本批"的裁定随之作废——**本批按 6 项全生效收**，M12 只保留 ③ 区间查询路由与 ④ "吃过多少次"展示两件事。
