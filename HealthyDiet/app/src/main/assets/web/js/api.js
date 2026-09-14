/* ============================================================
 * 食光 · 数据接口层（功能预留接口）
 * ------------------------------------------------------------
 * 设计约定：
 *   1. 页面（app.js）【只】通过 HealthAPI 的方法取数，绝不直接
 *      操作 Mock 数据 —— 这样换真实后端时页面代码零改动。
 *   2. 所有方法返回 Promise，与真实 HTTP 请求同构。
 *   3. 接入真实后端时，只需：
 *        a. 把 USE_MOCK 改为 false，并填写 API_BASE；
 *        b. 在 ROUTES 中核对每个接口的路径与参数。
 *      方法名、入参、返回结构保持不变。
 *   4. 标注【预留】的方法：界面暂未调用或入口置灰，
 *      后端就绪后打开即可，UI 已留好挂载点。
 * ============================================================ */

const USE_MOCK = false;             // 已接入真实后端（腾讯云 CloudBase）
const API_BASE  = 'https://cloud1-d6g4x9h9m507b429c.api.tcloudbasegateway.com/v1/functions/api-diet';

/* 客户端公开凭证（Publishable Key，可匿名调用注册/登录云函数） */
const PUBLISHABLE_KEY = 'eyJhbGciOiJSUzI1NiIsImtpZCI6IjlkMWRjMzFlLWI0ZDAtNDQ4Yi1hNzZmLWIwY2M2M2Q4MTQ5OCJ9.eyJpc3MiOiJodHRwczovL2Nsb3VkMS1kNmc0eDloOW01MDdiNDI5Yy5hcC1zaGFuZ2hhaS50Y2ItYXBpLnRlbmNlbnRjbG91ZGFwaS5jb20iLCJzdWIiOiJhbm9uIiwiYXVkIjoiY2xvdWQxLWQ2ZzR4OWg5bTUwN2I0MjljIiwiZXhwIjo0MDkyOTU3MDc0LCJpYXQiOjE3ODkyNzM4NzQsIm5vbmNlIjoieURIazNvS0FUcUdWbElUUFZ6d2VzdyIsImF0X2hhc2giOiJ5REhrM29LQVRxR1ZsSVRQVnp3ZXN3IiwibmFtZSI6IkFub255bW91cyIsInNjb3BlIjoiYW5vbnltb3VzIiwicHJvamVjdF9pZCI6ImNsb3VkMS1kNmc0eDloOW01MDdiNDI5YyIsIm1ldGEiOnsicGxhdGZvcm0iOiJQdWJsaXNoYWJsZUtleSJ9LCJ1c2VyX3R5cGUiOiIiLCJjbGllbnRfdHlwZSI6ImNsaWVudF91c2VyIiwiaXNfc3lzdGVtX2FkbWluIjpmYWxzZX0.fjfcG-D1b9n7gZ7BtQTcwB82EwxlxzDx2ULaJ-S2ONWX04D2-WQfjR060QNprSsG3CR-agmO-ACSAv7gckCLCF01WcoQONKGKRlRRG8qvVpPTtHOM3lSn5VbJK9_Mhhm1Ex8YqPFxl_7XrLv4iFR-4dycOrImsuYTjfcf4NFCPzzFe5sed1cs-aoXvlIXNMvoJPXhT9mHh8XHoIuWGJJf6upi0rLc130Qm-u7lFZxuwX-_ikhyyYFtP0Wy9cC3E9UsHi6bn3lIYbbs07RtRYNyz6XOjr6nPZ2GJhPd75YGdvdy9mhGoNVtxW8zUlIo8q00EAltlEvtVjhWDc70D-rw';

/* ============================================================
 * 登录态管理（localStorage 持久化）
 * ============================================================ */
const TOKEN_KEY = 'sg_token';
const GW_BASE = 'https://cloud1-d6g4x9h9m507b429c.api.tcloudbasegateway.com';

function _loadToken() {
  try { return JSON.parse(localStorage.getItem(TOKEN_KEY)) || null; } catch (e) { return null; }
}
function _saveToken(t) { localStorage.setItem(TOKEN_KEY, JSON.stringify(t)); }
function _clearToken() { localStorage.removeItem(TOKEN_KEY); }

/** 用 refresh_token 静默续期（CloudBase 登录认证 v2）。
 *  single-flight：并发 401 共享同一次续期，避免 refresh_token 轮换互踩导致启动时批量失败 */
let _refreshInflight = null;
function _refreshToken() {
  if (!_refreshInflight) {
    _refreshInflight = _doRefreshToken().finally(() => { _refreshInflight = null; });
  }
  return _refreshInflight;
}
async function _doRefreshToken() {
  const t = _loadToken();
  if (!t || !t.refreshToken) return false;
  const resp = await fetch(`${GW_BASE}/auth/v1/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ grant_type: 'refresh_token', refresh_token: t.refreshToken }),
  });
  if (!resp.ok) return false;
  const data = await resp.json();
  if (!data.access_token) return false;
  _saveToken({ ...t, accessToken: data.access_token, refreshToken: data.refresh_token || t.refreshToken, expiresIn: data.expires_in || 7200, savedAt: Date.now() });
  return true;
}

/* 接口路由表：与后端约定的路径，前端调用时统一从这里取 */
const ROUTES = {
  login:            '/auth/login',               // POST 手机号+验证码
  smsCode:          '/auth/sms-code',             // POST 发送验证码
  profile:          '/user/profile',              // GET  用户资料
  updateProfile:    '/user/profile',              // PUT  修改资料
  setGoal:          '/user/goal',                 // PUT  每日目标（热量/体重）
  waterGoal:        '/user/water-goal',           // PUT 喝水目标（ml，200 的整数倍）
  logWeight:        '/user/weight',               // POST 记每日体重（按天 upsert）
  avatar:           '/user/avatar',               // PUT  上传头像（dataURL）
  bodyMetrics:      '/user/body-metrics',         // GET  身高体重 BMI

  dailySummary:     '/diet/summary',              // GET  某日总热量+营养素（?date=YYYY-MM-DD）
  mealRecords:      '/diet/records',              // GET  某日三餐记录（?date=）
  addFoodRecord:    '/diet/records',              // POST 新增一条饮食记录
  deleteFoodRecord: '/diet/records/:id',          // DELETE 删除记录
  addWater:         '/diet/water',                // POST 记一杯水
  exercises:        '/diet/exercises',            // GET  某日运动记录（?date=）
  addExercise:      '/diet/exercises',            // POST 新增运动记录
  deleteExercise:   '/diet/exercises/:id',        // DELETE 删除运动记录

  searchFoods:      '/foods/search',              // GET  食物搜索（?keyword=）
  addCustomFood:    '/foods/custom',              // POST 添加自定义食物（名称+热量）
  foodDetail:       '/foods/:id',                 // GET  食物营养详情
  recognizeFood:    '/foods/recognize',           // POST 拍照识别【预留：multipart 图片】

  recommendMeals:   '/recommend/meals',           // GET  今日推荐餐食
  recipeDetail:     '/recommend/recipes/:id',     // GET  食谱详情【预留】

  weekReport:       '/report/week',               // GET  周报（?offset=0 本周）
  monthReport:      '/report/month',              // GET  月报【预留】
  weightTrend:      '/report/weight-trend',       // GET  体重趋势

  communityFeed:    '/community/feed',            // GET  社区动态【预留】
  marketGoods:      '/market/goods',              // GET  轻食商城【预留】
};

/* ============================================================
 * 以下为 Mock 实现。USE_MOCK=false 时走 request() 真实请求。
 * ============================================================ */

const _now = () => new Date();
const _isoDate = d => d.toISOString().slice(0, 10);
const TODAY = _isoDate(_now());

function _delay(data, ms = 260) {
  return new Promise(res => setTimeout(() => res(structuredClone(data)), ms));
}

/* —— Mock 数据库 —— */
const DB = {
  profile: {
    id: 'u_001', nickname: '小满', avatarText: '满',
    signature: '把每一餐，记成时光',
    goal: { dailyKcal: 1800, targetWeight: 55, waterMl: 1600 },
    body: { heightCm: 165, weightKg: 57.2, bmi: 21.0 },
  },
  summaryByDate: {
    [TODAY]: { kcal: 988, target: 1800, carb: 132, protein: 46, fat: 28, water: 3 },
  },
  recordsByDate: {
    [TODAY]: [
      { id: 'r_01', meal: 'breakfast', name: '燕麦牛奶粥', portion: '1 碗 · 约 300g', kcal: 245, emoji: '🥣' },
      { id: 'r_02', meal: 'breakfast', name: '水煮蛋', portion: '1 个 · 约 50g', kcal: 78, emoji: '🥚' },
      { id: 'r_03', meal: 'lunch', name: '香煎鸡胸藜麦饭', portion: '1 份 · 约 350g', kcal: 430, emoji: '🍗' },
      { id: 'r_04', meal: 'lunch', name: '白灼西兰花', portion: '半份 · 约 120g', kcal: 55, emoji: '🥦' },
      { id: 'r_05', meal: 'snack', name: '希腊酸奶', portion: '1 杯 · 约 150g', kcal: 180, emoji: '🥛' },
    ],
  },
  foods: [
    { id: 'f_01', name: '全麦吐司', meta: '面包谷物 · 1 片约 35g', kcal: 92, emoji: '🍞' },
    { id: 'f_02', name: '牛油果', meta: '水果 · 半个约 100g', kcal: 160, emoji: '🥑' },
    { id: 'f_03', name: '清蒸三文鱼', meta: '水产 · 1 块约 120g', kcal: 208, emoji: '🐟' },
    { id: 'f_04', name: '糙米饭', meta: '主食 · 1 碗约 150g', kcal: 174, emoji: '🍚' },
    { id: 'f_05', name: '凉拌豆腐', meta: '豆制品 · 1 份约 150g', kcal: 96, emoji: '🧊' },
    { id: 'f_06', name: '蓝莓', meta: '水果 · 1 小盒约 125g', kcal: 71, emoji: '🫐' },
    { id: 'f_07', name: '烤红薯', meta: '主食 · 1 个约 200g', kcal: 198, emoji: '🍠' },
    { id: 'f_08', name: '无糖豆浆', meta: '饮品 · 1 杯约 250ml', kcal: 70, emoji: '🥛' },
  ],
  recommendations: [
    { id: 'm_01', name: '牛油果鸡蛋全麦堡', kcal: 368, tag: '早餐 · 10 分钟', emoji: '🥑', macros: { carb: 34, protein: 18, fat: 19 } },
    { id: 'm_02', name: '茄汁虾仁烩糙饭', kcal: 412, tag: '晚餐 · 高蛋白', emoji: '🍤', macros: { carb: 46, protein: 32, fat: 10 } },
  ],
  exercisesByDate: {
    [TODAY]: [
      { id: 'x_01', key: 'run', name: '跑步', emoji: '🏃', amount: 5, unit: 'km', kcal: 285 },
    ],
  },
  weekReport: {
    days: ['一', '二', '三', '四', '五', '六', '日'],
    kcal: [1720, 1688, 0, 1856, 1745, 0, 988],   // 0 = 未记录
    target: 1800,
    rates: { carb: 86, protein: 72, fat: 64 },   // 营养素达标率 %
  },
  weightTrend: {
    points: [57.8, 57.6, 57.9, 57.5, 57.4, 57.6, 57.2],
    labels: ['9.7', '9.8', '9.9', '9.10', '9.11', '9.12', '今天'],
  },
};

/* Mock 专用记录 id */
let _recordSeq = 100;
const MOCK_WATER_CUP_ML = 200;   // 每杯毫升数（仅 Mock 内部用；避免与 app.js 全局常量重名冲突）

function mockRequest(routeKey, { method = 'GET', params = {}, body = null } = {}) {
  switch (routeKey) {
    case 'profile':      return _delay(DB.profile);
    case 'setGoal':      return _delay({ ok: true });
    case 'waterGoal': {
      DB.profile.goal.waterMl = body.waterGoalMl;
      return _delay({ waterGoalMl: body.waterGoalMl }, 120);
    }
    case 'logWeight': return _delay({ ok: true, weightKg: body.weightKg, date: body.date, patch: { weightKg: body.weightKg } }, 120);
    case 'dailySummary': return _delay(DB.summaryByDate[params.date] || { kcal: 0, target: 1800, carb: 0, protein: 0, fat: 0, water: 0 });
    case 'mealRecords':  return _delay(DB.recordsByDate[params.date] || []);
    case 'addFoodRecord': {
      const rec = { id: `r_${_recordSeq++}`, ...body };
      (DB.recordsByDate[body.date] ||= []).push(rec);
      const s = DB.summaryByDate[body.date] ||= { kcal: 0, target: 1800, carb: 0, protein: 0, fat: 0, water: 0 };
      s.kcal += body.kcal;
      return _delay(rec, 120);
    }
    case 'deleteFoodRecord': {
      for (const date in DB.recordsByDate) {
        const i = DB.recordsByDate[date].findIndex(r => r.id === params.id);
        if (i > -1) {
          const [rm] = DB.recordsByDate[date].splice(i, 1);
          const s = DB.summaryByDate[date];
          if (s) s.kcal = Math.max(0, s.kcal - rm.kcal);
        }
      }
      return _delay({ ok: true }, 120);
    }
    case 'addWater': {
      const s = DB.summaryByDate[body.date || TODAY] ||= { kcal: 0, target: 1800, carb: 0, protein: 0, fat: 0, water: 0 };
      if (body.delta < 0 && s.water > 0) s.water += body.delta;
      if (body.delta > 0) {
        const maxCups = Math.ceil(DB.profile.goal.waterMl / MOCK_WATER_CUP_ML);
        s.water = Math.min(maxCups, s.water + body.delta);
      }
      return _delay({ water: s.water }, 120);
    }
    case 'exercises':     return _delay(DB.exercisesByDate[params.date] || []);
    case 'addExercise': {
      const rec = { id: `x_${_recordSeq++}`, ...body };
      (DB.exercisesByDate[body.date] ||= []).push(rec);
      return _delay(rec, 120);
    }
    case 'deleteExercise': {
      for (const date in DB.exercisesByDate) {
        const i = DB.exercisesByDate[date].findIndex(r => r.id === params.id);
        if (i > -1) DB.exercisesByDate[date].splice(i, 1);
      }
      return _delay({ ok: true }, 120);
    }
    case 'searchFoods': {
      const kw = (params.keyword || '').trim();
      const all = DB.foods.concat(DB.customFoods || []);
      const hits = all.filter(f =>
        (!kw || f.name.includes(kw)) &&
        (!params.meal || !f.meals || f.meals.includes(params.meal)));
      return _delay(hits, 160);
    }
    case 'addCustomFood': {
      const rec = { id: `cf_${_recordSeq++}`, emoji: '🍽️', ...body };
      (DB.customFoods ||= []).push(rec);
      return _delay(rec, 120);
    }
    case 'recommendMeals': return _delay(DB.recommendations);
    case 'weekReport':     return _delay(DB.weekReport);
    case 'weightTrend':    return _delay(DB.weightTrend);
    default:
      return Promise.reject(new Error(`Mock 未实现接口: ${routeKey}`));
  }
}

/* 真实请求：后端为单入口云函数，body 携带 路径/方法/参数/载荷 */
async function realRequest(routeKey, { method = 'GET', params = {}, body = null } = {}) {
  let path = ROUTES[routeKey];
  Object.entries(params).forEach(([k, v]) => { path = path.replace(`:${k}`, encodeURIComponent(v)); });
  const t = _loadToken();
  const doFetch = async bearer => {
    const resp = await fetch(API_BASE, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${bearer}` },
      body: JSON.stringify({ path, method, params, body: body || {} }),
      signal: AbortSignal.timeout(15000),   // 15s 超时，避免无限 loading
    });
    const data = await resp.json().catch(() => ({}));
    return { status: resp.status, data };
  };

  let { status, data } = await doFetch(t ? t.accessToken : PUBLISHABLE_KEY);

  // 登录态过期：静默续期一次后重试
  if (status === 401 && t && (await _refreshToken())) {
    ({ status, data } = await doFetch(_loadToken().accessToken));
  }
  if (status === 401) { _clearToken(); throw new Error('登录已过期，请重新登录'); }
  if (status !== 200) throw new Error(data.message || `请求失败(${status})`);
  if (data && data.ok === false) throw new Error(data.message || '操作失败');
  return data;
}

function request(routeKey, options) {
  return USE_MOCK ? mockRequest(routeKey, options) : realRequest(routeKey, options);
}

/* ============================================================
 * 对外接口：页面唯一的数据入口
 * ============================================================ */
const HealthAPI = {
  /* ---------- 用户 ---------- */
  getProfile: () => request('profile'),
  updateProfile: data => request('updateProfile', { method: 'PUT', body: data }),
  setGoal: goal => request('setGoal', { method: 'PUT', body: goal }),
  /** 上传头像：dataURL 图片（png/jpeg/webp，压缩后通常 <100KB） */
  updateAvatar: dataUrl => request('avatar', { method: 'PUT', body: { data: dataUrl } }),
  /** 设置喝水目标（ml，200 的整数倍，800–3000） */
  setWaterGoal: waterGoalMl => request('waterGoal', { method: 'PUT', body: { waterGoalMl } }),
  /** 记录每日体重（kg，一位小数；同一天重复记为覆盖） */
  logWeight: (weightKg, date) => request('logWeight', { method: 'POST', body: { weightKg, date } }),

  /* ---------- 认证（用户名 + 密码） ---------- */
  isLoggedIn: () => !!_loadToken(),
  /** 注册；成功后可直接调用 loginByUsername */
  registerByUsername: async (username, password) => {
    const resp = await fetch(API_BASE, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${PUBLISHABLE_KEY}` },
      body: JSON.stringify({ path: '/auth/register', method: 'POST', params: {}, body: { username, password } }),
    });
    const data = await resp.json();
    if (!resp.ok || data.ok === false) throw new Error(data.message || '注册失败');
    return data;
  },
  /** 登录：服务端签发 ticket 并换取完整登录态 */
  loginByUsername: async (username, password) => {
    const resp = await fetch(API_BASE, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${PUBLISHABLE_KEY}` },
      body: JSON.stringify({ path: '/auth/login', method: 'POST', params: {}, body: { username, password } }),
    });
    const data = await resp.json();
    if (!resp.ok || data.ok === false) throw new Error(data.message || '登录失败');
    _saveToken({ ...data.token, savedAt: Date.now() });
    return data.token;
  },
  /** 退出登录 */
  logout: () => _clearToken(),

  /** 【预留】手机号+验证码登录（后端未接入短信通道） */
  loginByPhone: (phone, smsCode) => request('login', { method: 'POST', body: { phone, smsCode } }),
  /** 【预留】发送验证码 */
  sendSmsCode: phone => request('smsCode', { method: 'POST', body: { phone } }),

  /* ---------- 饮食记录 ---------- */
  getDailySummary: date => request('dailySummary', { params: { date } }),
  getMealRecords: date => request('mealRecords', { params: { date } }),
  addFoodRecord: record => request('addFoodRecord', { method: 'POST', body: record }),
  deleteFoodRecord: id => request('deleteFoodRecord', { method: 'DELETE', params: { id } }),
  addWater: (delta, date) => request('addWater', { method: 'POST', body: { date: date || TODAY, delta } }),
  getExercises: date => request('exercises', { params: { date } }),
  addExercise: rec => request('addExercise', { method: 'POST', body: rec }),
  deleteExercise: id => request('deleteExercise', { method: 'DELETE', params: { id } }),

  /* ---------- 食物库 ---------- */
  searchFoods: (keyword, meal) => request('searchFoods', { params: { keyword, meal } }),
  addCustomFood: food => request('addCustomFood', { method: 'POST', body: food }),
  getFoodDetail: id => request('foodDetail', { params: { id } }),
  /** 【预留】拍照识别食物，相机/相册入口已在记录页预留挂载点 */
  recognizeFood: imageFile => request('recognizeFood', { method: 'POST', body: { image: imageFile } }),

  /* ---------- 推荐 ---------- */
  getRecommendMeals: () => request('recommendMeals'),
  /** 【预留】食谱详情页 */
  getRecipeDetail: id => request('recipeDetail', { params: { id } }),

  /* ---------- 报告 ---------- */
  getWeekReport: (offset = 0) => request('weekReport', { params: { offset } }),
  /** 【预留】月报，报告页分段控件已留"月"档位 */
  getMonthReport: (offset = 0) => request('monthReport', { params: { offset } }),
  getWeightTrend: () => request('weightTrend'),

  /* ---------- 预留业务模块 ---------- */
  /** 【预留】社区动态，「我的」页入口置灰，后端就绪后开放 */
  getCommunityFeed: () => request('communityFeed'),
  /** 【预留】轻食商城，「我的」页入口置灰 */
  getMarketGoods: () => request('marketGoods'),
};
