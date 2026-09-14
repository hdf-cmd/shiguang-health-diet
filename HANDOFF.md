# 食光 · 健康饮食 App —— 项目交接文档

> ⚠️ **本文档已过期（2026-09-14）**：仅保留作早期前端设计稿参考。最新唯一事实来源见 `交接文档-给下一个模型.md`（含项目迁移路径、云函数现状、食物库体系、代谢引擎、坑清单等）。文中 FatSecret/USDA/Mock 为主等描述均已失效。

> 交接日期：2026-09-13
> 当前状态：**高保真界面原型已完成并实测通过**，数据层为 Mock，接口层预留完毕，可直接进入真实后端对接或继续扩展功能。

---

## 1. 项目是什么

「食光」（谐音"时光"）——面向 25–40 岁都市用户的健康饮食记录 App。核心场景：**快速记一餐 + 看今日营养缺口**。口号：把每一餐，记成时光。

技术形态：**纯静态原型（HTML/CSS/原生 JS）**，无构建依赖，浏览器直接打开即可运行。数据层与界面完全解耦，换真实后端时页面代码零改动。

## 2. 如何运行

| 方式 | 操作 |
|---|---|
| 直接打开 | 双击 `index.html`（无任何构建/跨域依赖） |
| 本地服务器 | `python -m http.server 8765` → 访问 `http://localhost:8765` |

桌面端展示为 390×844 手机壳 + 左侧设计速览；窗口宽 ≤760px 自动切换为全屏移动端布局。

## 3. 目录结构

```
健康饮食app/
├── index.html              # 入口：四个界面 + 两个弹层 + 底部导航
├── css/
│   ├── design-tokens.css   # 设计令牌（唯一事实来源，换主题只改这里）
│   ├── components.css      # 12 个通用组件
│   └── screens.css         # 界面级组件 + 手机壳/响应式
├── js/
│   ├── api.js              # ★ 预留接口层（Mock 适配器 + 路由表）
│   └── app.js              # 界面渲染与交互（只通过 HealthAPI.* 取数）
├── docs/
│   ├── DESIGN.md           # 设计规范（色彩/字体/签名组件/动效/文案）
│   ├── COMPONENTS.md       # 组件清单 + 预留挂载点对照表
│   └── API.md              # 接口清单/数据结构/后端接入三步
└── HANDOFF.md              # 本文档
```

## 4. 设计体系速览（详见 docs/DESIGN.md）

- **色彩语义（全 App 统一，看色即知营养）**：
  - 抹茶绿 `#3D7A4F` = 主操作/热量进度；谷物黄 `#E5A33C` = 碳水；浆果红 `#C75B4B` = 蛋白质；深海蓝 `#5E8FA8` = 脂肪/饮水；南瓜橙 `#D9662B` = 热量提醒（仅接近/超标时出现）
- **字体**：Fraunces（有机衬线，仅数字/大标题）+ Noto Sans SC（正文），CDN 加载、离线自动回退系统字体
- **签名组件「营养餐盘环」**：外环=热量进度（超标变橙），内环=三大营养素配比，中心=剩余 kcal（Fraunces 大数字）。SVG `stroke-dasharray` 驱动，记录变化即时重算
- 动效遵循 `prefers-reduced-motion`；焦点可见样式已处理

## 5. 四个界面与核心交互（均已实测）

| 界面 | 内容 | 已验证交互 |
|---|---|---|
| 首页 | 餐盘环 + 营养条 + 餐次快捷记录 + 今日推荐 + 喝水打卡 | 点餐次→记一笔弹层→加食物→热量环/营养条实时更新；点水杯累加 |
| 记录 | 近 7 天日期选择、三餐分组列表（小计/删除/空状态）、搜索、拍照入口 | 搜索食物、添加、删除记录；空状态引导文案 |
| 报告 | 周热量柱状图（目标线/超标橙/今日强调）、达标率卡、建议卡、体重趋势 | 周/月分段（月档置灰预留） |
| 我的 | 目标横幅、身体数据三格、菜单列表（社区/商城置灰） | 头像跳转、预留入口 Toast 提示 |

**喝水打卡（当前版本）**：每杯 200ml；右侧 200ml 水杯为打卡按钮，杯内水位=今日进度；目标可点开底部弹层自定义（200ml 步进，800–3000ml）；支持「撤销上一杯」；刻度格数随目标自适应。

**添加食物弹层**：搜索食物库（200ms 防抖）→ 点添加 → 写入当日餐次 → 全首页联动刷新。Esc/遮罩/✕ 均可关闭。

## 6. 接口层（接后端必读，详见 docs/API.md）

**核心约定**：页面只调用 `HealthAPI.*`，所有方法返回 Promise；Mock 与真实 HTTP 同构。

**接后端三步**：
1. `js/api.js` 顶部 `USE_MOCK` 改为 `false`，填写 `API_BASE`
2. 核对 `ROUTES` 路由表路径/方法/参数
3. 响应字段若有出入，只在 `realRequest()` 做一层映射，业务方法签名不变

**接口状态一览**：

| 状态 | 接口 |
|---|---|
| ✅ Mock 已通 | `getDailySummary` `getMealRecords` `addFoodRecord` `deleteFoodRecord` `addWater` `searchFoods` `getRecommendMeals` `getWeekReport` `getWeightTrend` `getProfile` `setWaterGoal` |
| ✅ 已接 UI | `setGoal`（目标编辑弹层）、`updateAvatar`（头像上传） |
| ✅ 已定义未接 UI | `updateProfile` `getFoodDetail` |
| 🔶 已预留（UI 挂载点就位） | `loginByPhone` `sendSmsCode`（登录页未做）、`recognizeFood`（拍照识别，需相机能力）、`getMonthReport`（报告页"月"档）、`getRecipeDetail`（食谱详情）、`getCommunityFeed` / `getMarketGoods`（我的页置灰入口） |

**核心数据结构**（完整版见 API.md）：`dailySummary {kcal, target, carb, protein, fat, water}`；`foodRecord {id, meal, name, portion, kcal, emoji}`；`meal ∈ breakfast|lunch|dinner|snack`；喝水以"杯"存储（每杯 200ml），目标为 ml。

## 7. 已知约定与注意事项

1. **Mock 数据不持久**：刷新页面即重置（内存 DB）。水量默认 3 杯、当日记录 5 条均为演示数据。
2. **安全约束**：登录/鉴权接入时，密钥一律走环境变量或密钥服务，源码/示例/测试不得出现可用凭据字面量。
3. **布局陷阱（已修复，勿回退）**：
   - 手机壳用 `overflow: clip`（不是 `hidden`，防止程序化滚动打乱内屏）；
   - 居中用 `margin: auto`（不是 `align-items:center`，防止矮视口下顶部不可滚动）；
   - 进度条 `.fill` 必须保留 `display:block`（span 默认 inline 宽高无效）。
4. **样式纪律**：颜色/字号/圆角只允许引用 `design-tokens.css` 变量，组件内不写死色值。
5. 营养素目标量为前端按供能比估算（碳 50% / 蛋白 25% / 脂 25%），后端就绪后应以接口下发为准。

## 8. 建议的下一步（按优先级）

1. **登录体系**：`loginByPhone`/`sendSmsCode` 已预留，做登录页 + token 存储 + 请求头注入（在 `realRequest()` 统一加）。
2. **拍照识别**：`recognizeFood` 接口已就位，接入相机/相册能力（Web 可用 `<input type="file" capture>`，小程序用 `wx.chooseMedia`）。
3. **月报**：报告页"月"分段已留位，实现 `getMonthReport` 后取消 disabled。
4. **目标编辑**：「我的」页编辑目标接 `setGoal`，与喝水目标弹层复用同一套 Sheet/步进器组件。
5. **数据持久化**：若继续用纯前端演示，可把 Mock 换成 localStorage 适配器（在 `mockRequest` 外再包一层即可）。
6. **社区/商城**：入口已置灰，属独立业务模块，建议单独立项。

---

*本文档与代码同步维护；改接口时务必同步 docs/API.md 的路由表与状态列。*

---

## 9. 【2026-09-13 更新】真实后端已接入（登录 + 全部核心接口）

前端已按第 6 节的三步接入真实后端：`js/api.js` 中 `USE_MOCK=false`。Mock 实现保留在代码里，改回 `true` 即可离线演示。

### 后端架构（腾讯云 CloudBase，环境 `cloud1-d6g4x9h9m507b429c`）

- **单入口云函数 `api-diet`**：实现 ROUTES 全部核心接口（`/auth/*`、`/user/*`、`/diet/*`、`/foods/search`、`/report/week`、`/report/weight-trend` 等），前端 `realRequest()` 以 `{path, method, params, body}` 一次 POST 派发，`Authorization: Bearer <token>`。
- **认证**：用户名 + 密码（`registerByUsername` / `loginByUsername`）。密码 scrypt 加盐存于 `app_users` 集合；登录成功由云函数签发自定义登录 ticket 并换取标准 access_token（2 小时）/refresh_token（30 天）返回。前端把 token 存 localStorage，401 时用 refresh_token 静默续期一次。
- **数据隔离**：用户 uid 由网关校验 token 后写入调用上下文，云函数端 `auth.getUserInfo()` 获取，所有业务集合按 uid 过滤。
- **数据集合**（均为仅管理端可写，客户端只能经云函数访问）：`app_users`（账号）、`sg_profiles`（资料/目标，首次访问自动建默认档）、`sg_records`（饮食记录，营养素按供能比碳50/蛋白25/脂25 估算）、`sg_water`（饮水按杯）、`sg_weights`（体重记录）、`custom_foods`（自定义食物）。
- **食物搜索**：`/foods/search` 服务端代理 FatSecret（Client ID/Secret 在函数环境变量中配置后自动启用）；未配置时回落到内置 15 条常见食物库 + 用户自定义库。

### 代码位置

| 内容 | 路径 |
|---|---|
| 云函数源码（api-diet / auth-diet） | `C:\Desktop\HealthyDiet\cloudfunctions\` |
| Android WebView 壳工程（打包 APK） | `C:\Desktop\HealthyDiet`（Kotlin 壳，前端页面内置于 `app/src/main/assets/web/`） |
| 已编译 APK | `C:\Desktop\健康饮食app\食光-debug.apk` |

### 已验证

- 云函数端到端（curl/python）：注册→登录→记一笔→汇总→删除→喝水→周报→资料→体重趋势 ✅
- 浏览器端到端（Playwright）：登录门控→注册/登录→记一笔（餐盘环实时联动）→记录页→报告页实时刷新 ✅
- **Android 模拟器实测（2026-09-13）**：AVD 重建（原 AVD 误指向 android-28）后 APK 安装启动正常，WebView 加载内嵌页面 ✅；经 CDP（WebView 远程调试）实测：注册→自动登录→首页（目标 1800）→搜索"酸奶"过滤 1 条→添加后餐盘环 92→272 联动→报告页日均实时更新→我的页昵称 ✅

### 环境备注（本机 Windows）

- 模拟器加速正常（WHPX）；**首次装 AVD 踩坑**：`avdmanager create avd` 不接受 `--sdk_root` 参数（会报错）、旧 AVD 的 `config.ini` 可能误指旧 API 级镜像导致启动卡死（`adb` 一直 offline），重建并核对 `image.sysdir` 即可
- dl.google.com 直连被限速严重（单连接 ~70KB/s），走系统代理（本机 127.0.0.1:7897）后 ~4.5MB/s；curl 需 `-x` 显式挂代理，不会自动读系统代理
- WebView CDP 调试：`adb forward tcp:9222 localabstract:webview_devtools_remote_<pid>`，连接时需 `suppress_origin=True`（Chromium 拒绝非 devtools Origin）；Playwright `connect_over_cdp` 的 browser 级操作不被 WebView 支持，需手写 page 级 CDP

### 已知限制 / 下一步

1. **FatSecret Key 已配置但白名单待补齐**：凭证已填（环境变量 FATSECRET_CLIENT_ID/SECRET），但 FatSecret 免费版有 IP 白名单限制（最多 15 个 IP），云函数出口是**动态 IP 池**（实测出现过：43.142.145.137、124.221.175、106.54.187.4、49.235.20.86、182.254.244.91），需把这些全部加入 FatSecret 后台白名单才能稳定命中；未命中时自动回落内置 15 条食物库，App 不受影响。
2. **静态托管默认域名**（`*.tcloudbaseapp.com`）大陆浏览器访问会触发腾讯"风险提醒"拦截页（未备案域名），故 APK 采用**本地内置页面 + 远程 API** 方案，不依赖该域名；后续绑自定义域名后可再启用托管热更新。
3. token 过期静默续期只重试一次，refresh_token 失效需重新登录。
4. 记录页"拍照识别"、报告页"月"档、社区/商城仍为预留位（接口已在云函数路由表外预留扩展）。
5. WebView 加载带 `?v=时间戳` 参数 + 启动 clearCache，前端迭代后重装 APK 不会吃到旧缓存。
6. **单元测试**：核心逻辑（营养素计算、日期处理）无测试覆盖，建议后续补充。
7. **离线缓存**：可加 Service Worker 支持断网访问。

### 【2026-09-13 第二轮】新功能：自定义头像 + 今日未打卡弹窗

- **自定义头像**：我的页/首页头像可点击 → 系统相册选图（WebView `onShowFileChooser` + `ACTION_GET_CONTENT`，支持多图选择结果）→ 前端 canvas 压缩到 256px JPEG → `PUT /user/avatar`（dataURL，≤280KB 校验）→ 存 `sg_profiles.avatarData` → `GET /user/profile` 返回 `avatarData` 供渲染。头像数据直接存数据库（免云存储 URL 过期问题）。
- **今日未打卡弹窗**：当天 kcal=0 且水=0 时进首页弹「今天还没打卡」提醒层，按钮「去记录」跳记录页 /「稍后再说」关闭（关闭后当日不再弹）。判定在 `refreshToday()` 里，`maybeShowCheckin()`。
- 接口：`PUT /user/avatar`（云函数 handle 新增），前端 `HealthAPI.updateAvatar(dataUrl)`。
- 已在模拟器 CDP 实测通过：注册新用户 → 弹窗弹出 → 关闭 → 上传头像 → 我的页/首页头像同步显示图片 ✅

### 【2026-09-13 第三轮】Bug 修复 + 体验优化

- **周报"今天"定位修复**：原来硬编码 `i === 6`（周日位置），现根据 `new Date().getDay()` 动态计算，周一打开 App "今天"显示在周一列
- **喝水杯数上限脱钩**：Mock 原硬编码 `Math.min(8, ...)`，但目标可设到 3000ml（15 杯）→ 改为按目标杯数动态计算上限
- **体重趋势空数据保护**：`w.points` 为空数组时 `Math.min(...[])` 返回 Infinity 导致 SVG 渲染崩溃 → 添加空数据兜底提示"暂无体重数据"
- **删除记录二次确认**：点 ✕ 直接删除改为弹出确认弹窗"删除后无法恢复，确定要删除吗？"，防止误操作
- **目标编辑 UI 接入**：「我的」页「编辑」按钮原来只弹 toast → 现接入完整步进器弹层，可编辑每日热量目标（1200–3000 kcal，步进 100）和目标体重（30–150 kg，步进 0.5），调用 `HealthAPI.setGoal()`
- **搜索 loading 状态**：添加食物弹层搜索时显示"搜索中..."loading 状态，网络慢时不再看到空白
- **登录后平滑过渡**：注册/登录成功后不再 `location.reload()`，改为直接刷新主界面数据 + 切换到首页，体验更流畅
- **移动端安全区域适配**：底部导航栏添加 `env(safe-area-inset-bottom)` 适配 iOS 刘海屏/底部 Home Indicator

**改动文件**：`js/app.js`、`js/api.js`、`index.html`、`css/screens.css`
**已通过语法检查**：`node -e "new Function(...)"` 验证通过
