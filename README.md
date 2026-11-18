# 食光 · 健康饮食 App

**当前维护版本：v2.16.1（Flutter 2.x）** ｜ 1.x H5 壳停更在 v1.4.0 ｜ 变更历史见 [CHANGELOG.md](CHANGELOG.md)

把每一餐，记成时光。核心闭环：**记三餐 → 算热量 → 看趋势**。

- **2.x Flutter 线（当前维护）**：工程在 `ShiguangFlutter/`，Flutter 原生壳；APK 为 `食光Flutter-v2.16.1.apk`；数据走腾讯云 CloudBase（环境 `cloud1-d6g4x9h9m507b429c`）单入口云函数 `api-diet`。
- **1.x H5 线（已停更）**：纯静态 HTML/CSS/ES Module JS（无构建），见本目录 `index.html` + `js/` + `css/`；APK 为 `食光-v1.4.0.apk`（Kotlin WebView 壳）。

## Flutter 2.x（当前维护）

| 模块 | 说明 |
|------|------|
| 核心闭环 | 登录/注册、今日餐盘、饮食记录、报告、我的；与 1.x 功能对齐 |
| 条形码扫码 | 商品条码扫描（EAN-8/13、UPC-A、GTIN-14）；命中顺序：用户自定义绑定 → OFF 营养缓存 → OFF 实时 → apizero 国产商品身份（名称/品牌/规格）。身份缓存 30 天；未收录时可拍包装营养成分表或手动添加，保存后条码绑定到自定义食物，下次扫码直接命中 |
| 描述一餐 | 一句话描述吃了什么；模型只抽食物名/份量与份量词，营养来自内置库/自定义库；每项返回 top-3 候选可切换；库内无命中才按菜名估算并标「AI 估算」 |
| 营养表识别 | 未收录商品可拍包装背面营养成分表，视觉模型读每 100g/ml 的热量/蛋白/碳水/脂肪，预填自定义食物表单，用户核对后保存并绑定条码 |
| AI 识菜 | 拍照识别；识别失败可输入菜名 + 克数按菜名估算；支持自带 Key（DeepSeek / 通义千问 / Kimi / 智谱 / 豆包），未配置时回退内置通道 |
| AI 饮食助手 | 默认 DeepSeek 主通道、扣子备用（扣子额度类错误后熔断 10 分钟，`ASSISTANT_PRIMARY=coze` 可切回扣子优先）；入口为 64dp 圆形 3D 头像「小光」（默认左下、底部 AI 字标、可拖拽并吸附左右边缘）；点按打开 **62% 底部半屏聊天**，收起即结束本次会话；可参考今日饮食摘要；助手回复支持系统 TTS 朗读 |
| 手环数据同步 | 绑定小米账号后自动从云端同步：每日活动（步数/距离/全天活动热量）驱动 **TDEE = BMR + 实测活动**、额度与预计时间；单次运动（跑步/骑行/游泳等）去重后自动导入运动记录。打开 App 自动同步（会话缓存复用，401 才重登；窗口 7–30 天动态扩展）；首页步数卡展示所选日步数/距离/活动热量与最近 7 天迷你柱。Health Connect 通道实测国行不写入，已弃用 |
| 通知/体重 | 三餐与喝水提醒、BLE 体脂秤体重同步（仅体重）等 |

质量门禁：云端 `node --test tests` 202 项、Flutter `flutter test` 675 项、`dart analyze lib test` 全绿。

### AI 饮食助手配置

- 云函数路由：`POST /ai/coze-chat`，入参 `{message, date?, conversationId?, useTodaySummary?, history?}`，出参 `{ok, reply, conversationId, channel?}`。
- **通道顺序（2.15.3 起）**：默认 DeepSeek 主通道（`DEEPSEEK_API_KEY`），扣子（`COZE_BOT_ID` / `COZE_PAT`）只作备用。扣子免费版 API 是**累计 500 次**，用完后每次先等扣子失败再无谓多付一次往返；现在扣子报额度类错误后进程内熔断 10 分钟，期间直接走 DeepSeek。需要改回扣子优先时设云函数环境变量 `ASSISTANT_PRIMARY=coze`。
- **多轮上下文**：DeepSeek 没有服务端会话，客户端每轮带最近 8 条 `history`（单条云端再截 200 字）；扣子仍用 `conversationId`。返回 `channel` 标明本次走哪条通道。
- 今日摘要取数从「6 次串行往返」压成「4 个并行查询 + 本地求和」，云端实测 54–102ms（原 200–290ms）。
- 2026-11-17 实测（云函数内部计时，不含移动网络）：无摘要 0.8–1.4s，带今日摘要 1.8–2.0s；升级前同链路 7–8s（扣子在线时）/ 报「额度已用完」（扣子额度耗尽后兜底 import 缺陷）。真机 RMX5010 + 2.15.3：冷请求 2.50s、热请求 2.21s（含冷启动 1.39s 与上下文取数）。
- 聊天只做文字多轮 + 回复朗读，不做语音输入/免手循环。

## 1.x H5 线（已停更）

### 已实现功能（真实后端）

| 模块 | 说明 |
|------|------|
| 账号 | 用户名 + 密码注册/登录（scrypt 加盐，ticket 换标准登录态），多设备云端同步 |
| 今日 | 营养餐盘环（热量进度 + 三大营养素配比）、餐盘卡日期导航、每日建议卡、餐次快捷记录、喝水打卡、今日运动 |
| 记录 | 近 7 天日期切换、三餐分组列表、左滑删除（二次确认）、食物搜索（按餐次过滤）、自定义食物（份量 + 克/毫升单位 + 餐次归类 + 三素 + 照片）、食物库管理（自定义可删、内置可移除/恢复、点餐次标签改归类） |
| 报告 | 周/月热量柱状图（目标线）、营养素达标率、规则建议引擎、体重趋势 + 每日体重记录 |
| 我的 | 资料与头像、身体档案、代谢与减脂计划（Mifflin-St Jeor）、目标派生、消息提醒开关 |
| 手势 | AlloyFinger：整屏滑动切页、餐盘日期滑动、长按/左滑删除；抽屉跟手拖拽 |
| 通知 | 原生层：三餐定点提醒 + 喝水每日随机 8 次（AlarmManager + 开机自恢复） |

### 食物库体系

搜索只走 **内置库（36 条用户常菜，带图 + 权威宏量）→ 用户自定义库**；外部食物搜索 API（FatSecret/USDA）已全部移除（IP 白名单与稳定性问题，见交接文档 §7）。条形码查询额外接 Open Food Facts（营养数据）与用户自定义绑定；国产商品未收录时先查 apizero 商品身份（名称/品牌/规格，30 天缓存），营养仍靠拍营养表或手动填写。每条内置食物含餐次归属（早餐/正餐/零食，搜索按餐次过滤；分类原则：饮料归零食、面包归早餐/零食）、配图、蛋白质/碳水/脂肪真实值，多数带 `per100` 供「按份量加」换算。自定义食物同样支持份量单位（克/毫升）与餐次归类。

## 使用

- **手机（当前维护线）**：安装 `食光Flutter-v2.15.5.apk`（允许未知来源安装），注册账号即可使用。
- **手机（1.x H5，停更）**：安装 `食光-v1.4.0.apk`。
- **电脑浏览器（1.x H5）**：`python -m http.server 8765` 后访问 `http://localhost:8765`；`file://` 下会被 CORS 拦截，需经 localhost 访问才能连真实后端。

## 工程位置

| 内容 | 路径 |
|------|------|
| Flutter 工程（当前维护） | `ShiguangFlutter/`（`lib/app` 外壳/主题，`lib/features` 页面，`lib/data` 接口层，`test/` 全量测试） |
| 云函数源码 | `HealthyDiet/cloudfunctions/api-diet/`（`index.js` 路由 + `ai.js` 识菜/估算 + `ai_meal.js` 描述一餐 + `ai_label.js` 营养表 + `barcode.js` 条码 + `services/assistant_route.js` 助手通道 + `services/` 路由体 + `coze.js` 扣子客户端 + `data/foods.js`） |
| Node 测试 | `tests/`（`node:test`，零依赖） |
| 1.x H5 前端 | 本目录（`js/app.js` 入口，`js/logic.js` 领域逻辑，`js/state.js` 状态，`js/api.js` 接口层） |
| H5 前端 assets 副本 | `HealthyDiet/app/src/main/assets/web/`（构建时 `preBuild` 自动同步） |
| 交接文档 | `交接文档-给下一个模型.md`（**唯一事实来源**） |

## 常用命令

```bash
# Flutter（当前维护）
cd ShiguangFlutter
dart analyze lib
flutter test
flutter build apk --release

# Node / 云函数测试
node --test tests/*.test.js

# 1.x H5（停更）
npm test
npm run lint
npm run check:version
cd HealthyDiet && gradlew.bat assembleRelease
```

> 本机工作区路径含中文，Flutter release 构建若报 `app.dill` 读取失败，按 [AGENTS.md](AGENTS.md) 的 ASCII 沙盒流程构建：复制 `android/`、`lib/`、`assets/`、`pubspec.yaml`、**`pubspec.lock`**、`analysis_options.yaml` 到 ASCII 目录后构建，避免插件版本漂移。

## 版本管理

- **Flutter 2.x**：版本号在 `ShiguangFlutter/pubspec.yaml` 的 `version`（当前 `2.16.1+23113`），同一版本的变更写入 `CHANGELOG.md`。
- **1.x H5**：版本号唯一来源是 `package.json` 的 `version`，`js/version.js` 手写同步，CI 用 `npm run check:version` 拦截漂移。

## 签名

release 包用本地密钥库签名，凭据放 `ShiguangFlutter/android/key.properties`（已入 `.gitignore`，**严禁入库**）：

- 密钥库：`ShiguangFlutter/android/shiguang-flutter-release.jks`（alias `shiguang-flutter`，RSA 2048）
- ⚠️ **密钥库与密码一旦丢失，将无法再更新已安装的 App**（只能卸载重装），请异地备份
- 凭据文件缺失时构建仍可进行，但产出未签名包（便于他人 clone 后编译）

## 待办

1. **iOS 相机权限与打包**：当前只有 Android 线；iOS 未配 `NSCameraUsageDescription`，也未打包
2. **AI 助手端到端流式**：当前非流式（整段 1.8–2.0s），评估 CloudBase 侧 SSE 与客户端流式解析，把首字压到 1s 内
3. **小光入口吸附范围**：头像可拖到页面顶部压住标题（如实测「记录」页），需限制在标题栏以下、TabBar 以上
4. **真机手感回访**（滑动阈值、长按删除发现性）；首页滚动位置偶发停底观察项
5. **营养表低光/反光**：已有拍摄预览与 confidence 兜底，仍待更多实拍样本验证

## 许可证

[MIT](LICENSE) © 2026 hdf-cmd
