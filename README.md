# 食光 · 健康饮食 App

**当前维护版本：v2.11.0（Flutter 2.x）** ｜ 1.x H5 壳停更在 v1.4.0 ｜ 变更历史见 [CHANGELOG.md](CHANGELOG.md)

把每一餐，记成时光。核心闭环：**记三餐 → 算热量 → 看趋势**。

- **2.x Flutter 线（当前维护）**：工程在 `ShiguangFlutter/`，Flutter 原生壳；APK 为 `食光Flutter-v2.11.0.apk`；数据走腾讯云 CloudBase（环境 `cloud1-d6g4x9h9m507b429c`）单入口云函数 `api-diet`。
- **1.x H5 线（已停更）**：纯静态 HTML/CSS/ES Module JS（无构建），见本目录 `index.html` + `js/` + `css/`；APK 为 `食光-v1.4.0.apk`（Kotlin WebView 壳）。

## Flutter 2.x（当前维护）

| 模块 | 说明 |
|------|------|
| 核心闭环 | 登录/注册、今日餐盘、饮食记录、报告、我的；与 1.x 功能对齐 |
| AI 识菜 | 拍照识别；识别失败可输入菜名 + 克数按菜名估算；支持自带 Key（DeepSeek / 通义千问 / Kimi / 智谱 / 豆包），未配置时回退内置通道 |
| AI 饮食助手 | 扣子智能体；入口为 64dp 圆形 3D 头像「小光」（默认左下、底部 AI 字标、可拖拽并吸附左右边缘）；点按打开 **62% 底部半屏聊天**，收起即结束本次会话；可参考今日饮食摘要；助手回复支持系统 TTS 朗读 |
| 通知/体重 | 三餐与喝水提醒、BLE 体脂秤体重同步（仅体重）等 |

### AI 饮食助手配置

- 云函数路由：`POST /ai/coze-chat`，入参 `{message, date?, conversationId?, useTodaySummary?}`，出参 `{ok, reply, conversationId}`。
- 环境变量：`COZE_BOT_ID`、`COZE_PAT` 只存 CloudBase 云函数环境变量，客户端不接触；PAT 按扣子控制台有效期轮换。
- 扣子免费版 API 为**累计 100 条**；当前实测首字约 2.6s、整段约 7–8s，端到端流式 / 更快的模型仍在评估。
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

搜索只走 **内置库（35 条用户常菜，带图 + 权威宏量）→ 用户自定义库**；外部 API（FatSecret/USDA）已全部移除（IP 白名单与稳定性问题，见交接文档 §7）。每条内置食物含餐次归属（早餐/正餐/零食，搜索按餐次过滤；分类原则：饮料归零食、面包归早餐/零食）、配图、蛋白质/碳水/脂肪真实值，多数带 `per100` 供「按份量加」换算。自定义食物同样支持份量单位（克/毫升）与餐次归类。

## 使用

- **手机（当前维护线）**：安装 `食光Flutter-v2.11.0.apk`（允许未知来源安装），注册账号即可使用。
- **手机（1.x H5，停更）**：安装 `食光-v1.4.0.apk`。
- **电脑浏览器（1.x H5）**：`python -m http.server 8765` 后访问 `http://localhost:8765`；`file://` 下会被 CORS 拦截，需经 localhost 访问才能连真实后端。

## 工程位置

| 内容 | 路径 |
|------|------|
| Flutter 工程（当前维护） | `ShiguangFlutter/`（`lib/app` 外壳/主题，`lib/features` 页面，`lib/data` 接口层，`test/` 全量测试） |
| 云函数源码 | `HealthyDiet/cloudfunctions/api-diet/`（`index.js` 路由 + `ai.js` 识菜 + `coze.js` 饮食助手 + `data/foods.js`） |
| Node 测试 | `tests/`（`node:test`，零依赖） |
| 1.x H5 前端 | 本目录（`js/app.js` 入口，`js/logic.js` 领域逻辑，`js/state.js` 状态，`js/api.js` 接口层） |
| H5 前端 assets 副本 | `HealthyDiet/app/src/main/assets/web/`（构建时 `preBuild` 自动同步） |
| 交接文档 | `交接文档-给下一个模型.md`（**唯一事实来源**） |

## 常用命令

```bash
# Flutter（当前维护）
cd ShiguangFlutter
flutter test
flutter build apk --release --split-per-abi

# Node / 云函数测试
node --test tests/*.test.js

# 1.x H5（停更）
npm test
npm run lint
npm run check:version
cd HealthyDiet && gradlew.bat assembleRelease
```

> 本机工作区路径含中文，Flutter release 构建若报 `app.dill` 读取失败，按 `docs/superpowers/plans` 里的 ASCII 沙盒流程构建。

## 版本管理

- **Flutter 2.x**：版本号在 `ShiguangFlutter/pubspec.yaml` 的 `version`（当前 `2.11.0+21100`），同一版本的变更写入 `CHANGELOG.md`。
- **1.x H5**：版本号唯一来源是 `package.json` 的 `version`，`js/version.js` 手写同步，CI 用 `npm run check:version` 拦截漂移。

## 签名

release 包用本地密钥库签名，凭据放 `HealthyDiet/keystore.properties`（已入 `.gitignore`，**严禁入库**）：

- 密钥库：`HealthyDiet/keystore/shiguang-release.jks`（alias `shiguang`，RSA 2048，有效期 10000 天）
- ⚠️ **密钥库与密码一旦丢失，将无法再更新已安装的 App**（只能卸载重装），请异地备份
- 凭据文件缺失时构建仍可进行，但产出未签名包（便于他人 clone 后编译）

## 待办

1. **图片单一事实来源整改**：把 H5 `img/` 纳入仓库根目录并加入 `scripts/sync-web-assets.mjs` 的 TARGETS，解决浏览器预览图片 404 + 图片只能在 assets 里维护的问题
2. **AI 饮食助手延迟**：首字约 2.6s、整段约 7–8s；评估端到端流式 / 更快模型
3. 前端热更新（H5；云存储 + 版本号拉取，免重装 APK）
4. 真机手感回访（滑动阈值、长按删除发现性）；首页滚动位置偶发停底观察项

## 许可证

[MIT](LICENSE) © 2026 hdf-cmd
