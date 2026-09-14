# 食光 · 功能预留接口说明（API.md)

数据层在 `js/api.js`，页面唯一的数据入口是全局对象 **`HealthAPI`**。页面代码不接触 Mock 数据，因此接入真实后端时**页面代码零改动**。

## 接入真实后端的三步

1. `js/api.js` 顶部把 `USE_MOCK` 改为 `false`，并填写 `API_BASE`（如 `https://api.shiguang.app/v1`）；
2. 核对 `ROUTES` 路由表中每个接口的路径、方法、参数是否与后端一致；
3. 若响应结构有出入，只需在 `realRequest()` 里做一层字段映射，业务方法签名不变。

所有方法返回 `Promise`，错误统一 reject（调用方可用 try/catch 或 toast 呈现）。

## 接口清单

### 用户模块

| 方法 | 路由 | 说明 | 状态 |
|---|---|---|---|
| `getProfile()` | `GET /user/profile` | 用户资料（昵称/签名/目标/身体数据） | ✅ Mock 已通 |
| `updateProfile(data)` | `PUT /user/profile` | 修改资料 | ✅ 已定义 |
| `setGoal(goal)` | `PUT /user/goal` | 设置每日热量/目标体重，「编辑目标」按钮待接 | 🔶 已预留 |
| `setWaterGoal(waterGoalMl)` | `PUT /user/water-goal` | 设置喝水目标（ml，200 的整数倍，800–3000），喝水卡「修改目标」已接 Mock | ✅ Mock 已通 |
| `loginByPhone(phone, code)` | `POST /auth/login` | 手机号验证码登录，登录页未做 | 🔶 已预留 |
| `sendSmsCode(phone)` | `POST /auth/sms-code` | 发送验证码 | 🔶 已预留 |

### 饮食记录模块

| 方法 | 路由 | 说明 | 状态 |
|---|---|---|---|
| `getDailySummary(date)` | `GET /diet/summary?date=` | 当日总热量+三大营养素+饮水 | ✅ Mock 已通 |
| `getMealRecords(date)` | `GET /diet/records?date=` | 当日三餐明细 | ✅ Mock 已通 |
| `addFoodRecord(record)` | `POST /diet/records` | 新增记录 `{date, meal, name, portion, kcal, emoji}` | ✅ Mock 已通 |
| `deleteFoodRecord(id)` | `DELETE /diet/records/:id` | 删除记录 | ✅ Mock 已通 |
| `addWater(delta)` | `POST /diet/water` | 记饮水，`delta` 为杯数（每杯 200ml），仅支持累加，上限 8 杯（1600ml） | ✅ Mock 已通 |

### 食物库模块

| 方法 | 路由 | 说明 | 状态 |
|---|---|---|---|
| `searchFoods(keyword)` | `GET /foods/search?keyword=` | 食物搜索（空关键词返回热门） | ✅ Mock 已通 |
| `getFoodDetail(id)` | `GET /foods/:id` | 食物营养详情 | ✅ 已定义 |
| `recognizeFood(imageFile)` | `POST /foods/recognize` | 拍照识别食物，需接入相机/相册能力 | 🔶 已预留 |

### 推荐与报告模块

| 方法 | 路由 | 说明 | 状态 |
|---|---|---|---|
| `getRecommendMeals()` | `GET /recommend/meals` | 今日推荐餐食 | ✅ Mock 已通 |
| `getRecipeDetail(id)` | `GET /recommend/recipes/:id` | 食谱详情页 | 🔶 已预留 |
| `getWeekReport(offset)` | `GET /report/week?offset=` | 周报（热量序列+达标率） | ✅ Mock 已通 |
| `getMonthReport(offset)` | `GET /report/month?offset=` | 月报，报告页"月"档位已置灰等待 | 🔶 已预留 |
| `getWeightTrend()` | `GET /report/weight-trend` | 体重趋势 | ✅ Mock 已通 |

### 预留业务模块（入口在「我的」页置灰）

| 方法 | 路由 | 说明 |
|---|---|---|
| `getCommunityFeed()` | `GET /community/feed` | 食光社区动态 |
| `getMarketGoods()` | `GET /market/goods` | 轻食商城 |

## 数据结构约定（核心）

```js
// dailySummary
{ kcal: 988, target: 1800, carb: 132, protein: 46, fat: 28, water: 3 }  // 单位 kcal / g / 杯

// foodRecord
{ id: 'r_01', meal: 'breakfast', name: '燕麦牛奶粥', portion: '1 碗 · 约 300g', kcal: 245, emoji: '🥣' }
// meal ∈ 'breakfast' | 'lunch' | 'dinner' | 'snack'

// weekReport
{ days: ['一','二',...], kcal: [1720, 1688, 0, ...], target: 1800,
  rates: { carb: 86, protein: 72, fat: 64 } }   // 0 表示当日未记录

// 预留凭据约束：登录/鉴权接入时，密钥一律走环境变量或密钥服务，
// 源码、示例、测试均不得出现可用凭据字面量。
```
