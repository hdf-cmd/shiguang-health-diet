# CloudBase 工单材料：api-diet 文档库读写视图分歧（sg_exercises 幽灵写入）

- 环境 ID：`cloud1-d6g4x9h9m507b429c`（上海）
- 涉及资源：云函数 `api-diet`（$DEFAULT→$LATEST 单版本，无流量分流，已核）、文档型数据库集合 `sg_exercises`
- 客户端：Android（模拟器 API 36 / 真机 realme），HTTPS 网关
  `https://cloud1-d6g4x9h9m507b429c.api.tcloudbasegateway.com/v1/functions/api-diet`
- 复现账号 uid：`u_uitest01`（测试账号）
- 紧急度：环境 2026-10-01 到期，需在到期前定位；此问题影响该集合全部写路径

## 一句话现象

同一环境、同一函数路由（`/diet/exercises`）、同一登录态下：**App 客户端写入的记录，App 自己经同一 GET 路由能读回，但管理端（控制台/MCP/CLI）与另一 HTTP 短连接客户端（Python urllib）在表中都查不到该文档（总条数不变）**；且部分此类写入在 CLS 库访问日志留有 `InsertDocument 200` 记录，表内却无对应文档、也无任何 `DeleteDocument`。

## 时间线（2026-09-26，北京时间）

| 时刻 | 动作 | 客户端 | 结果 |
|---|---|---|---|
| 14:25:53 | POST /diet/exercises（跑步5km） | App（release v2.4.0） | CLS `InsertDocument 200`，reqId `327d5f1d-1699-478f-879a-93111e3837eb-1a0dc644175_1`，host `169.254.0.131`；**表内无此文档** |
| 14:40:18 | POST（跑步7km） | App | `InsertDocument 200` reqId `bb5708e1-0964-42aa-af07-afad77c244d3-1a0dc7174f2_b`，host `169.254.0.132`；**表内无** |
| 14:40:31 | POST（跑步7km） | App | `InsertDocument 200` reqId `b392f88b-a13b-4268-9563-b1125648fb01-1a0dc71a790_c`，host `169.254.0.131`；**表内无** |
| 14:54:04 | POST（PYVIS 探针） | Python 短连接 | `InsertDocument 200`；表内可见 ✓（后被管理端删除） |
| 15:12:07/18 | POST ×2（PYVIS2/3） | Python 短连接 | 表内可见 ✓ `_id 964fbcc86ab77047042e354c593aec43` / `92994ce06ab7705201dc51b46c5ddf28`，**且 App 侧 GET 也能读到这两条**（Python→App 方向同步正常） |
| 15:18:16 | App 冷启动 GET | App | 网关日志 4 条 Dart 请求（如 reqId `82377f0a-6caf-42fa-a93f-2ee71e4a0b80`），返回与表一致（2 条） |
| 15:21 起 | App 保存运动 ×5 | App（release 及从源码新构建的 debug 包均复现） | App 提示成功且**后续 GET 回读到含幽灵行的列表**（最多 5 行）；表恒 27 条、Python GET 恒 2 条 |
| 15:34-15:36 | App 冷启动 GET | App | 实际发生（UI 回显真实云端数据），**但网关/库访问日志缺失该时段 Dart 请求**（CLS 采集丢失佐证） |
| 15:52 | App 删除一条幽灵行 | App | App 视图合计 1311→966；**表 total 恒 27 不变**，无 DeleteDocument 落表 |

## 已排除项（对照实验，均可复现）

1. **非客户端代码问题**：同一异常由两个独立二进制复现——沙盒构建的 release x86_64 包、以及当日从仓库 HEAD 现源码构建的 debug 包；读写均为标准 Dio(HTTP/2 keep-alive) POST 信封，无任何本地缓存/合并逻辑（源码可提供）。
2. **非云函数代码问题**：`api-diet` 为无状态单入口，exercises 三路由仅做 `db.collection('sg_exercises')` 的 add/where(uid,date).get/doc(id).remove；`CodeInfo` 与仓库一致；`$DEFAULT`→`$LATEST` 无灰度分流（getFunctionAlias 已核）。
3. **非网络劫持/代理**：模拟器 `http_proxy=null`、无 hosts 改写、DNS 解析与公网一致（81.69.138.235 / 81.69.216.233）。
4. **非权限/环境错绑**：网关访问日志显示 App 请求 `env_id=cloud1-d6g4x9h9m507b429c`、`userId=u_uitest01`、`statusCode=200`；Python 与 App 使用同一 URL、同一账号 token。
5. **方向不对称**：Python→表→App 读取正常；App→写入仅 App 自身可读。指向 App 长连接粘住的执行路径（实例或 `169.254.0.131/132` 某库代理节点）存在一份**未与主表收敛的写视图**。

## 请平台方核查

1. `sg_exercises` 所在文档库实例是否存在多节点读写不一致 / 复制中断（写节点 accept 后不回主表）？
2. `api-diet` 近期实例池里是否有实例连接了异常的数据库代理（14:25/14:40 三笔 `InsertDocument 200` 的落点）？
3. CLS 网关/库访问日志在 15:33-15:45 时段对 Dart UA 请求存在丢失，请一并核查采集链路。
4. 若为平台侧故障：该集合历史上是否还有其它"成功回执但丢写"的窗口（可拉 `sg_exercises`/`sg_records`/`sg_water` 全量比对）。

## 复现步骤（平台方可自跑）

1. 注册/使用任一账号，经网关 `POST /auth/login` 取 token；
2. 用**带 keep-alive 的长连接**（Dart/Java HttpClient/`curl --http2` 复用连接）`POST /diet/exercises`，body `{date, key, name, emoji, amount, unit, kcal}`；
3. 同连接 `GET /diet/exercises?date=...` → 可见新行；
4. 控制台/CLI 查 `sg_exercises`（`uid`+`date` 过滤或 total 计数）→ 无该文档。
   （短连接 Python urllib 走同路由写入则两侧一致，可作为对照组。）

## 附件清单（本机路径，可随时提供）

- 证据截图：`C:\Desktop\健康饮食app\.mimosa\m6t7\`（re-01~08、dbg-00~08 系列，含幽灵行列表、删除前后合计、表 total 不变）
- 复现包：仓库根 `食光Flutter-v2.4.0.apk`（arm64 release）及当日 debug 包（模拟器可现场复现）
- 前端源码：`ShiguangFlutter/lib/features/exercise/`、`lib/data/api_client.dart`
- 云函数源码：`HealthyDiet/cloudfunctions/api-diet/index.js:343-375`
- 内部排查台账：`.superpowers/sdd/2026-09-26-flutter-m6-daily-features/progress.md`（Task 7 P0 复查两段）

## 善后备注（提单后执行，勿提前）

- 对照探针 `PYVIS2跑步`/`PYVIS3跑步` 两条（_id 见上表）**保留作平台方核验锚点**，工单结案后由我方删除。
- App 侧幽灵行仅存在于其异常视图，主表无残留，无需数据清理。

## 真机复测补充（2026-09-27，v2.5.0 正式包）

- 环境：真机 RMX5010（Android 15，arm64），`食光Flutter-v2.5.0.apk`（release 签名），账号「春夏秋冬又一春」（uid=u_7f88ac7026f0ab562f1e0f75），CST 时区。
- 操作：app 内记运动「跑步 5km · 345 kcal」→ 保存即显后**立即**用 MCP `readNoSqlDatabaseContent` 直查 `sg_exercises`（uid+date=2026-09-27）→ **正常落库**（requestId 81b84a3b-7272-4d0c-b365-51030b07b896，_id 92994ce06ab85cf701f494277b6028a2）；app 内删除后反查 → **云端零残留**（requestId ff874832-137c-4bb7-87c1-ec4ad3812f49）。
- 结论修正：视图分歧**未在真机+release 语境复现**，迄今全部复现样本出自模拟器（Android 16 API 36 系统镜像）+debug/正式包混合语境。写视图粘滞疑与模拟器出网路径（NAT/virtualhost）或特定长连接实例相关，请平台方在网关访问日志中按上述 requestId 与 09-26 样本对照 UA/源 IP/实例落点。
