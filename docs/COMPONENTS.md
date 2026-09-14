# 食光 · 组件清单（COMPONENTS.md）

组件样式集中在 `css/components.css`（通用件）与 `css/screens.css`（界面级组件）。所有颜色/字号/圆角只引用 `design-tokens.css` 变量。

## 通用组件（components.css）

| # | 组件 | 类名 | 说明 |
|---|---|---|---|
| 01 | 按钮 Button | `.btn` `.btn-primary/-soft/-ghost/-danger` `.btn-block` `.btn-icon` | 主/浅/描边/危险四态，图标按钮 40px 圆形 |
| 02 | 标签 Chip / Tag | `.chip` `.tag` `.tag-warn` `.tag-muted` | Chip 用于筛选与餐次选择（可 active），Tag 用于卡片角标 |
| 03 | 卡片 Card | `.card` `.card-title` | 基础容器，标题行右侧可挂「更多 ›」 |
| 04 | 搜索栏 SearchBar | `.searchbar` | 圆角胶囊，右侧可挂相机图标按钮 |
| 05 | 营养素进度条 NutrientBar | `.nutrient-bar` | 三行（碳水/蛋白/脂肪），颜色语义全局统一 |
| 06 | 食物列表项 FoodListItem | `.food-item` | emoji 缩略图 + 名称/规格 + kcal，记录页可追加删除钮 |
| 07 | 空状态 EmptyState | `.empty` | emoji 插画 + 行动引导文案 |
| 08 | 轻提示 Toast | `.toast` | 底部悬浮 1.8s 自动消失，全局唯一实例 |
| 09 | 底部弹层 Sheet | `.sheet` `.sheet-mask` | 添加食物弹层，Esc/遮罩可关 |
| 10 | 分段控件 Segmented | `.segmented` | 周/月切换，未开放档位 disabled 置灰 |
| 11 | 统计卡 StatCard | `.stat-card` | 标签 + 大数字，可内嵌进度条 |
| 12 | 图标基线 | `.icon` | 统一 22px 线性图标容器 |

## 界面级组件（screens.css）

| 组件 | 位置 | 说明 |
|---|---|---|
| **营养餐盘环 PlateRing** | 首页 | 签名组件。外环=热量进度，内环=三大营养素配比，中心=剩余 kcal。JS 按 `stroke-dasharray` 重算 |
| 底部导航 TabBar | 全局 | 4 个 Tab（首页/记录/报告/我的），毛玻璃背景，图标+文字 |
| 餐次快捷入口 | 首页 | 早餐/午餐/晚餐/加餐 4 个 Chip，点击直开添加弹层 |
| 喝水打卡 WaterCard | 首页 | 每杯 200ml；右侧 200ml 水杯为打卡按钮，杯内水位即今日进度，点杯累加；进度条 8+ 格刻度随目标自适应；「目标 xxx ml」可点，弹底部面板步进器自定义（800–3000ml，走 `setWaterGoal` 接口）；支持「撤销上一杯」 |
| 日期选择行 DateRow | 记录页 | 近 7 天横向 Chip，默认今天 |
| 餐次分组列表 | 记录页 | 按三餐分组，小计 kcal，支持删除单项，空状态给引导 |
| 周热量柱状图 WeekChart | 报告页 | 7 根 CSS 柱 + 虚线目标线；超标柱变橙、今日柱加主色 |
| 营养达标率卡组 | 报告页 | 三张 StatCard，内嵌营养素色进度条 |
| 本周建议卡 | 报告页 | 浅绿底，文案由达标率数据驱动 |
| 体重趋势图 | 报告页 | SVG 折线 + 端点强调，头部显示本周变化 |
| 目标横幅 GoalBanner | 我的 | 渐变绿底，热量/体重目标 + 编辑按钮 |
| 身体数据格 BodyGrid | 我的 | 身高/体重/BMI 三格 StatCard |
| 菜单列表 MenuList | 我的 | 图标 + 文案 + 箭头；预留模块挂「敬请期待」Tag |
| 手机壳 PhoneFrame | 展示层 | 390×844 机型壳 + 状态栏，桌面端居中展示、移动端自动全屏 |

## 预留挂载点（UI 已就位，等待能力/后端）

| 挂载点 | 当前行为 | 预留接口（js/api.js） |
|---|---|---|
| 记录页相机图标 & 拍照识别按钮 | Toast 提示"即将上线" | `recognizeFood(imageFile)` |
| 报告页"月"分段 | disabled 置灰 | `getMonthReport(offset)` |
| 我的页·食光社区 / 轻食商城 | 「敬请期待」Tag | `getCommunityFeed()` / `getMarketGoods()` |
| 我的页·编辑目标 / 退出登录 | Toast 提示 | `setGoal(goal)` / `loginByPhone()` `sendSmsCode()` |
| 首页·换一换 / 推荐卡点击 | Toast 提示 | `getRecipeDetail(id)` |
