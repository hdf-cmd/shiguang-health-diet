# 食光 · 健康饮食 App

把每一餐，记成时光。核心闭环：**记三餐 → 算热量 → 看趋势**。

- **界面**：前端高保真原型（纯静态 HTML/CSS/JS，见本目录 `index.html` + `js/` + `css/`），浏览器直接打开可看（Mock 模式）
- **后端**：腾讯云 CloudBase（环境 `cloud1-d6g4x9h9m507b429c`）——用户名密码登录 + 云数据库 + FatSecret 食物搜索代理，全部收口在单入口云函数 `api-diet`
- **APK**：`食光-debug.apk`（Kotlin WebView 壳，页面内置于 assets，经内嵌本地服务 `http://127.0.0.1:8765` 加载以通过网关 CORS，数据走云端）

## 已实现功能（真实后端）

| 模块 | 说明 |
|------|------|
| 账号 | 用户名 + 密码注册/登录（scrypt 加盐，ticket 换标准登录态），多设备云端同步 |
| 今日 | 营养餐盘环（热量进度 + 三大营养素配比）、餐次快捷记录、今日推荐、喝水打卡 |
| 记录 | 近 7 天日期切换、三餐分组列表、删除、食物搜索（内置食物库兜底 / FatSecret） |
| 报告 | 周热量柱状图（目标线）、营养素达标率、本周建议、体重趋势 |
| 我的 | 资料、热量/体重目标、喝水目标设置、退出登录 |

## 使用

- **手机**：安装 `食光-debug.apk`（允许未知来源安装），注册账号即可使用
- **电脑浏览器**：`python -m http.server 8765` 后访问 `http://localhost:8765`（或双击 index.html 看界面，但 file:// 下会被 CORS 拦截，需经 localhost 访问才能连真实后端）

## 工程位置

| 内容 | 路径 |
|------|------|
| 前端原型 + 接口层 | 本目录（`js/api.js` 为页面唯一数据入口，USE_MOCK=true 可离线演示） |
| 云函数源码 | `C:\Desktop\HealthyDiet\cloudfunctions\`（api-diet 单入口；auth-diet 为早期版本） |
| Android 壳工程 | `C:\Desktop\HealthyDiet`（`gradlew.bat assembleDebug` 出 APK） |
| 交接文档 | `HANDOFF.md`（含后端架构、已验证范围、已知限制） |

## 待办

1. **FatSecret Key**：老大在 https://platform.fatsecret.com 注册后，把 Client ID/Secret 配到云函数 `api-diet` 的环境变量（控制台 → 云函数 → api-diet → 环境变量），食物搜索自动升级为全量库（当前用内置 15 条兜底）
2. 系统镜像下载完成后做模拟器实机回归（本机网络下载 Google 镜像较慢）
3. 拍照识别 / 月报 / 目标编辑等预留位（UI 挂载点已就位）
