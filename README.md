# 食光 · 健康饮食 App

把每一餐，记成时光。核心闭环：**记三餐 → 算热量 → 看趋势**。

- **界面**：纯静态 HTML/CSS/ES Module JS（无构建），见本目录 `index.html` + `js/` + `css/`
- **后端**：腾讯云 CloudBase（环境 `cloud1-d6g4x9h9m507b429c`）——用户名密码登录 + 云数据库 + 食物库，全部收口在单入口云函数 `api-diet`
- **APK**：`食光-debug.apk`（Kotlin WebView 壳，页面内置于 assets，经内嵌本地服务 `http://127.0.0.1:8765` 加载以通过网关 CORS，数据走云端）

## 已实现功能（真实后端）

| 模块 | 说明 |
|------|------|
| 账号 | 用户名 + 密码注册/登录（scrypt 加盐，ticket 换标准登录态），多设备云端同步 |
| 今日 | 营养餐盘环（热量进度 + 三大营养素配比）、餐盘卡日期导航、每日建议卡、餐次快捷记录、喝水打卡、今日运动 |
| 记录 | 近 7 天日期切换、三餐分组列表、左滑删除（二次确认）、食物搜索（按餐次过滤）、自定义食物（份量 + 克/毫升单位 + 餐次归类 + 三素 + 照片）、食物库管理（自定义可删、内置可移除/恢复、点餐次标签改归类） |
| 报告 | 周/月热量柱状图（目标线）、营养素达标率、规则建议引擎、体重趋势 + 每日体重记录 |
| 我的 | 资料与头像、身体档案、代谢与减脂计划（Mifflin-St Jeor）、目标派生、消息提醒开关 |
| 手势 | AlloyFinger：整屏滑动切页、餐盘日期滑动、长按/左滑删除；抽屉跟手拖拽 |
| 通知 | 原生层：三餐定点提醒 + 喝水每日随机 8 次（AlarmManager + 开机自恢复） |

## 食物库体系

搜索只走 **内置库（35 条用户常菜，带图 + 权威宏量）→ 用户自定义库**；外部 API（FatSecret/USDA）已全部移除（IP 白名单与稳定性问题，见交接文档 §7）。每条内置食物含餐次归属（早餐/正餐/零食，搜索按餐次过滤；分类原则：饮料归零食、面包归早餐/零食）、配图、蛋白质/碳水/脂肪真实值，多数带 `per100` 供「按份量加」换算。自定义食物同样支持份量单位（克/毫升）与餐次归类。

## 使用

- **手机**：安装 `食光-debug.apk`（允许未知来源安装），注册账号即可使用
- **电脑浏览器**：`python -m http.server 8765` 后访问 `http://localhost:8765`（或双击 index.html 看界面，但 file:// 下会被 CORS 拦截，需经 localhost 访问才能连真实后端）
  - ⚠️ 浏览器预览时**食物图片不显示**：图片只在 `HealthyDiet/app/src/main/assets/web/img/`（APK 内路径），仓库根目录没有 `img/`。这是已知取舍，待整改（见待办 1）

## 工程位置

| 内容 | 路径 |
|------|------|
| 前端源码 | 本目录（`js/app.js` 入口，`js/logic.js` 领域逻辑，`js/state.js` 状态，`js/api.js` 接口层；`USE_MOCK=true` 可离线演示） |
| Android 壳工程 + 云函数 | `HealthyDiet/`（2026-09-14 已迁入本工作区，不再是 `C:\Desktop\HealthyDiet`） |
| 云函数源码 | `HealthyDiet/cloudfunctions/api-diet/`（`index.js` 路由 + `data/foods.js` 食物数据） |
| 前端 assets 副本 | `HealthyDiet/app/src/main/assets/web/`（构建时 `preBuild` 自动同步 index.html/css/js；**img 需手动放**） |
| 单元测试 | `tests/`（`npm test`，node:test 零依赖，18 个用例） |
| 交接文档 | `交接文档-给下一个模型.md`（**唯一事实来源**）；`HANDOFF.md` 为早期稿，已过期 |

## 常用命令

```bash
npm test                 # 单元测试
npm run sync:assets      # 手动同步前端 → assets（构建时也会自动跑）
cd HealthyDiet && gradlew.bat assembleDebug   # 出 APK（app/build/outputs/apk/debug/）
```

## 待办

1. **图片单一事实来源整改**：把 `img/` 纳入仓库根目录并加入 `scripts/sync-web-assets.mjs` 的 TARGETS，解决浏览器预览图片 404 + 图片只能在 assets 里维护的问题
2. 拍照识别食物（接口 `/foods/recognize` 已保留，记录页入口待重加）
3. 前端热更新（云存储 + 版本号拉取，免重装 APK）
4. 发布签名（release keystore）上架准备
5. 真机手感回访（滑动阈值、长按删除发现性）；首页滚动位置偶发停底观察项