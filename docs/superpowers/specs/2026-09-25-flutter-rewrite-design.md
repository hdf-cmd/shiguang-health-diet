# 食光 Flutter 重写 · 设计文档

> 日期：2026-09-25 ｜ 状态：已与老大逐节确认
> 决策记录：路线 A（Flutter 全量重写客户端）；痛点=滑动/滚动手感；动机=体验+学 Flutter；
> 形态=App 与 H5 双栈并存共用 api-diet；H5 **不冻结**（老大 2026-09-25 拍板）；包体积不设限；
> 目录名 `ShiguangFlutter/`（授权代取）；里程碑按学习曲线排（M1-M5）。

## 1. 总体架构与工程布局

- 现有仓库根新增 `ShiguangFlutter/`，不建新仓库（交接文档/云函数/门禁同处一地，双栈契约不失忆）。
- H5 栈（`index.html` + `js/` + `css/` + `HealthyDiet/` WebView 壳）零改动，按 1.x 继续发版。
- Flutter 3.x stable + Dart 3，单 package，不上 melos 多包。
- 分层（按可测试性切）：

```
ShiguangFlutter/lib/
  domain/     纯 Dart 业务逻辑（从 js/logic.js 移植），禁止 import flutter
  data/       dio HTTP 客户端（api-diet 网关）+ shared_preferences 本地缓存
  features/   auth / home / record / report / profile / scale 六个功能目录
  app/        路由、ThemeData（design-tokens.css 移植）、启动
```

- `domain/` 不依赖 Flutter 是硬规矩：代谢公式、建议引擎、份量换算全部 `dart test` 直测。
- 后端复用：api-diet 一行不改。dio 打同一网关
  `https://cloud1-d6g4x9h9m507b429c.api.tcloudbasegateway.com/v1/functions/api-diet`，
  登录走同款 `/auth/v1/token`。食物库由云端下发（searchFoods），Flutter 端不移植食物数据。
- 状态管理：Riverpod（社区事实标准、编译期安全、与纯 domain 层最搭）。
- 版本单一来源仍是根 `package.json`；`check:version` 扩检 `ShiguangFlutter/pubspec.yaml`。
  **H5 线 1.x，Flutter 线 2.x**（Flutter 首发 = 2.0.0）。

## 2. 移植清单

### domain 层（每个函数连单测一起搬，40 条测试是验收标准）

| JS 源（js/logic.js） | Dart 落点 | 内容 |
|---|---|---|
| `computeMetabolism` | `domain/metabolism.dart` | BMR/TDEE/建议摄入 + 系统派生热量目标防呆规则 |
| `macroGoals` / `portionMacros` | `domain/macros.dart` | 三大营养素目标 + per100 克数换算 |
| `exerciseKcalOf` + `EXERCISE_LIB`/`ACTIVITY` | `domain/exercise.dart` | 运动库常量 |
| `buildAdvice` + `ADVICE_RULES` + `makeAdviceCtx` + `buildPeriodAdvice` | `domain/advice.dart` | 每日建议 + 周/月报规则引擎 |
| `avgDeficitFromRows` / ETA | `domain/deficit.dart` | 实际缺口与预计达标日期 |
| `localIso/todayIso` | `domain/dates.dart` | 日期工具；测试注入 Clock，不吃系统时区（模拟器 UTC 教训） |

### 秤协议（ScaleSync.kt → Dart）

- `domain/scale/b1_protocol.dart`：20 字节帧编解码、CRC5（sum(2..18)&0x1F）、swap32 体重解码、
  "0x54 连接即推旧存档必须忽略"规则。测试向量用真机抓包的十六进制报文（交接文档 §16.3）。
- `features/scale/`：flutter_blue_plus 连接编排，状态机照搬 v1.3.1 简化版（0x51 锁定即存，无 commit 流程）。

### 明确不移植 / 不碰

- Swiper/BetterScroll（Flutter 原生滚动取代——本次改写动机）、AssetServer、`sg_debug` 门控
  （Flutter 诊断页改 debug 构建可见）。
- api-diet 云函数、CloudBase 数据库结构、H5 全栈：双栈契约 = 云端不动。

## 3. 里程碑（学习曲线 × 体验达成）

| 里程碑 | 学习点 | 交付物 | 验收 |
|---|---|---|---|
| **M1 布局与主题**（约 1 周） | Widget 布局树、Theme、资源 | 登录/注册页、四 Tab 骨架（胶囊 tabbar）、首页卡片静态版、design-tokens→ThemeData | 模拟器与 H5 逐屏对眼满意；format/analyze 零告警；不接网络 |
| **M2 状态与网络**（1-2 周） | async/Future、Riverpod、dio 拦截器 | `data/api_client.dart`（token 拦截器照抄 js/api.js 行为）、真实登录闭环、记三餐全链路、domain 移植 + 40 条测试翻 Dart 全绿 | uitest01 记一顿饭，H5 浏览器端立刻可见（双栈互通实锤） |
| **M3 图表与动效**（约 1 周） | CustomPainter、动画、PageView | 热量环（进度动画）、柱状图点击浮出数值、体重趋势线、PageView 滑切 Tab | 真机手感对比 v1.3.1，**体验自此反超 H5**；老大上手不满意不算过 |
| **M4 平台能力**（1-2 周） | 插件、权限、Platform Channel | flutter_blue_plus 秤同步、flutter_local_notifications 三餐/喝水提醒、两位小数体重 | 真机站秤→锁定→秒存；提醒到点 |
| **M5 收尾发布**（约 3 天） | 签名、CI | release 签名（复用 keystore）、`食光-flutter-v2.0.0.apk`、check:version 扩检 pubspec、CI 加 flutter job、README/交接文档双栈说明 | 门禁全绿 + 真机全链路 |

总计 4-6 周（每天 1-2 小时估算）。每个里程碑结束都是能跑能玩的版本。

M4 已知降级：Android 16 灵动岛特效（WaterProgress 常驻通知）flutter_local_notifications 做不到，
M4 先普通通知；要特效则 M5 选修写 ~100 行 Kotlin 子插件（顺带学 Platform Channel 深水区）。

## 4. 数据流与双栈一致性

- 登录态：Flutter 存 `flutter_secure_storage`（Android Keystore）；token 过期/刷新行为与 js/api.js 一致；
  同用户两端登录互不挤占（服务端无会话绑定）。
- 单向数据流：UI 事件 → Riverpod Notifier → ApiClient → api-diet → JSON → provider → 重绘。
  **禁止 widget 直接改共享状态**（对应 H5 的 updateState() 收敛思路）。
- 离线策略：**不做**本地库/离线队列（H5 三年无此需求；断网 = 失败 toast + 保留输入）。
- 防契约漂移（H5 不冻结 ⇒ 此项升级为必做）：
  1. `contract/fixtures/*.json` 一份契约 fixture 放仓库根 `contract/`，H5 `tests/` 与
     `ShiguangFlutter/test/contract/` 各写用例读同一份 fixture——api-diet 改字段必有一边红；
  2. 云函数改动 SOP：改 api-diet → 部署 → **跑两端契约测试** → 再谈发版（写进交接文档）；
  3. 版本一致性门禁：package.json / js/version.js / README / pubspec.yaml 四处齐检。
- 错误处理：dio 拦截器统一网关错误→人话文案；domain 纯函数不抛业务异常，返回 null/带内标记
  （与 logic.js 风格一致，移植不改测试语义）。

## 5. 测试策略

1. **domain 单测**（主力）：40 条移植 + b1_protocol 报文断言，`dart test` 毫秒级，CI 必过。
2. **契约测试**：见 §4，双栈共享 fixture。
3. **widget 测试**：只测热量环数值、柱状图点击浮出、记一笔表单校验三处。不给全页面补截图测试（YAGNI）。
4. **真机验收**：M2/M3/M4 各一次，老大上手；模拟器只当日常开发机。

## 6. 风险与对策

| 风险 | 影响 | 对策 |
|---|---|---|
| 包体积 ~20MB | 老大已明示不设限 | 不处理；需要时 `--split-per-abi` |
| 双栈同时演进维护成本 | 每个功能可能要做两遍 | 老大拍板不冻结；靠契约测试兜底，且约定"新特性先 Flutter 后按需回填 H5" |
| flutter_blue_plus API 破坏性变更 | 秤链路返工 | 锁版本进 pubspec.lock；协议层纯 Dart 独立可测 |
| Riverpod 学习曲线（M2 最陡） | 卡 2-3 天 | 先用最笨用法跑通再重构，里程碑目标是"能玩"不是"优雅" |
| Clash 未开则 push 阻塞（现有流程依赖） | 提交滞留本地 | 沿用现行 SOP：推送前先扫历史 + rev-list 确认 |

## 7. 首发后 H5 与 Flutter 的功能回填规则

- 新交互/新页面：Flutter 先行，H5 仅在老大点名时回填。
- 修 bug：两边各自修（代码独立），契约类 bug 通过 fixture 同步暴露。
- 秤、提醒、记录等所有写云端的字段：必须走同一 api-diet 路由，禁止 Flutter 侧另开接口。
