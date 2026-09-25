/* ============================================================
 * 食光 · 界面交互逻辑（ES Module 入口）
 * 纯领域逻辑 → js/logic.js；全局状态 → js/state.js；数据接口 → js/api.js。
 * 本文件集中：渲染 / 事件 / 启动编排（DOM 副作用仅此一处）。
 * ============================================================ */
import {
  MEAL_NAMES, MEAL_IMG,
  WATER_CUP_ML, WATER_GOAL_MIN, WATER_GOAL_MAX,
  ACTIVITY, BODY_DEFAULT, EXERCISE_LIB,
  localIso, todayIso, dateLabelOf,
  macroGoals, computeMetabolism, exerciseKcalOf, portionMacros, avgDeficitFromRows,
  exerciseAmountLabel, isRepRecord,
  buildAdvice, makeAdviceCtx,
} from './logic.js';
import { state, updateState, isViewingToday } from './state.js';
import { HealthAPI } from './api.js';
import { APP_VERSION } from './version.js';

const $  = sel => document.querySelector(sel);
const $$ = sel => [...document.querySelectorAll(sel)];

/* APK/WebView 环境：系统已提供状态栏，隐藏原型手机壳的模拟状态栏（桌面浏览器保留） */
if (/\bwv\b/.test(navigator.userAgent)) {
  const sb = $('.statusbar');
  if (sb) sb.style.display = 'none';
}

/* ---------- 轻提示 ---------- */
let toastTimer;
function toast(msg) {
  const el = $('#toast');
  el.textContent = msg;
  el.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove('show'), 1800);
}

/* ---------- 确认弹层 ---------- */
let confirmResolve = null;
function showConfirm(title, desc) {
  return new Promise(resolve => {
    confirmResolve = resolve;
    $('#confirm-title').textContent = title || '确认删除';
    $('#confirm-desc').textContent = desc || '删除后无法恢复，确定要删除吗？';
    $('#confirm-mask').classList.add('show');
    $('#confirm-sheet').classList.add('show');
  });
}
function closeConfirm(result) {
  $('#confirm-mask').classList.remove('show');
  $('#confirm-sheet').classList.remove('show');
  if (confirmResolve) {
    confirmResolve(result);
    confirmResolve = null;
  }
}
$('#confirm-ok').addEventListener('click', () => closeConfirm(true));
$('#confirm-cancel').addEventListener('click', () => closeConfirm(false));
$('#confirm-mask').addEventListener('click', () => closeConfirm(false));

/* ---------- 底部导航 ---------- */
const SCREEN_ORDER = ['home', 'record', 'report', 'profile'];
const currentScreenName = () => {
  if ($('#screen-login').classList.contains('show')) return 'login';
  return mainSwiper ? SCREEN_ORDER[mainSwiper.activeIndex] : 'home';
};
/* 触感反馈：关键操作轻微震动（WebView 支持 navigator.vibrate） */
function buzz(ms) { try { if (navigator.vibrate) navigator.vibrate(ms); } catch (e) { /* 忽略 */ } }
/* TabBar 滑动指示：glide 胶囊跟随 active tab（弹簧曲线） */
function updateTabGlide() {
  const bar = $('.tabbar');
  const glide = $('.tab-glide');
  const active = bar && bar.querySelector('.tab.active');
  if (!glide || !active || !active.offsetWidth) return;
  glide.style.width = active.offsetWidth + 'px';
  glide.style.transform = `translateX(${active.offsetLeft}px)`;   // glide 与 offsetLeft 同原点（padding-box），不再减 padding
}
window.addEventListener('resize', updateTabGlide);
/* 切屏后的 chrome 同步：tab/glide/操作栏/周报拉取 */
function syncChrome(name) {
  $$('.tab').forEach(t => t.classList.toggle('active', t.dataset.screen === name));
  updateTabGlide();
  $('.add-row').classList.toggle('show', name === 'record');   // 记录页才显示底部操作栏
  setTabbarHidden(false);   // 切屏时复位：导航栏重新出现
  buzz(8);
  if (name === 'report') loadReportPage();   // 每次进入报告页都拉最新周报
}
/* ---------- 底部导航栏滚动显隐（反馈2）：上滑隐藏、下滑/到底出现，平滑过渡 ---------- */
let _tabbarHidden = false;
function setTabbarHidden(hidden) {
  if (_tabbarHidden === hidden) return;
  _tabbarHidden = hidden;
  const bar = $('.tabbar');
  const row = $('.add-row');
  if (bar) bar.classList.toggle('tabbar-hidden', hidden);
  if (row) row.classList.toggle('add-row-hidden', hidden);   // 记录页操作栏联动
}
/* 绑定 BScroll 滚动方向监听：dy<0（内容上移=手指上滑）隐藏，dy>0 或触底出现 */
function bindTabbarScroll(bs) {
  let lastY = 0, acc = 0;
  const THRESHOLD = 8;   // 累计位移阈值，防轻微抖动误触发
  bs.on('scroll', pos => {
    const y = pos.y;                 // BScroll 中 y 为负值，越往下滚 y 越小
    const dy = y - lastY;            // dy<0 = 继续往下滚（手指上滑）
    lastY = y;
    // 触底/触顶判断：maxScrollY 为可滚最小 y（负值）
    const maxScrollY = bs.maxScrollY || 0;
    const atBottom = y <= maxScrollY + 4;
    const atTop = y >= -4;
    if (atBottom || atTop) { acc = 0; setTabbarHidden(false); return; }   // 顶/底始终显示
    acc += dy;
    if (acc < -THRESHOLD) { setTabbarHidden(true); acc = 0; }       // 上滑累计 → 隐藏
    else if (acc > THRESHOLD) { setTabbarHidden(false); acc = 0; }  // 下滑累计 → 出现
  });
  bs.on('scrollEnd', () => { acc = 0; });
}
function switchScreen(name) {
  if (!HealthAPI.isLoggedIn() && name !== 'login') return;   // 未登录门控：只能停留登录页
  if (name === 'login') { showLogin(); return; }
  const idx = SCREEN_ORDER.indexOf(name);
  if (mainSwiper) {
    if (mainSwiper.activeIndex !== idx) mainSwiper.slideTo(idx);   // slideChange 里 syncChrome
    else syncChrome(name);
  } else {
    syncChrome(name);
  }
}
$$('.tab').forEach(t => t.addEventListener('click', () => switchScreen(t.dataset.screen)));

/* ---------- 主界面交互引擎：Swiper 跟手切屏 + BetterScroll 惯性滚动（开源集成） ---------- */
let mainSwiper = null;
const bsMap = new Map();
/* 每个 slide 内容包一层 .screen-content 供 BScroll 作 wrapper/content */
function wrapScreenContent(s) {
  if (s.querySelector(':scope > .screen-content')) return;
  const c = document.createElement('div');
  c.className = 'screen-content';
  while (s.firstChild) c.appendChild(s.firstChild);
  s.appendChild(c);
}
function initScreenScroll(s) {
  wrapScreenContent(s);
  // UMD 命名空间：BetterScroll.default 即 BScroll 构造器（已注册全部插件）
  const Ctor = window.BetterScroll && (window.BetterScroll.default || window.BetterScroll.createBScroll);
  if (!Ctor) { s.firstElementChild.style.overflowY = 'auto'; return; }
  const pull = s.id === 'screen-home' || s.id === 'screen-record';
  const bs = new Ctor(s, {
    click: true,               // 由 BScroll 合成 click：按钮内 span 子元素被 preventDefault 时原生 click 会吞，合成可达
    preventDefaultException: { tagName: /^(INPUT|TEXTAREA|SELECT|BUTTON|A|LABEL)$/ },
    bounce: true,              // 边缘回弹 rubber-band
    momentum: true,            // 惯性滚动
    pullDownRefresh: pull ? { threshold: 64, stop: 44 } : false,
  });
  if (pull) {
    bs.on('pullingDown', async () => {
      try {
        if (s.id === 'screen-home') await Promise.all([refreshToday(), loadExercises()]);
        else await Promise.all([refreshToday(), loadRecordPage(), loadExercises()]);
        toast('已刷新');
      } finally { bs.finishPullDown(); }
    });
  }
  bindTabbarScroll(bs);   // 滚动方向联动底部导航栏显隐（反馈2）
  // 内容高度变化（渲染/展开）→ 防抖 refresh
  let t = 0;
  new MutationObserver(() => { clearTimeout(t); t = setTimeout(() => bs.refresh(), 90); })
    .observe(s.firstElementChild, { childList: true, subtree: true, characterData: true });
  // 拖拽后抑制误点 + 同目标 400ms 内去重（防 native+synthetic 双触发）
  let suppress = false, px = 0, py = 0, lastClick = { t: 0, el: null };
  s.addEventListener('pointerdown', e => { px = e.clientX; py = e.clientY; }, { passive: true });
  s.addEventListener('pointerup', e => {
    if (Math.abs(e.clientX - px) > 12 || Math.abs(e.clientY - py) > 12) {
      suppress = true;
      setTimeout(() => { suppress = false; }, 60);
    }
  }, { passive: true });
  s.addEventListener('click', e => {
    const now = Date.now();
    if (suppress) { e.stopPropagation(); e.preventDefault(); suppress = false; return; }
    if (lastClick.el === e.target && now - lastClick.t < 400) { e.stopPropagation(); e.preventDefault(); }
    lastClick = { t: now, el: e.target };
  }, true);
  bsMap.set(s.id, bs);
}
function initMainSwiper() {
  $$('.screens .screen').forEach(initScreenScroll);
  if (typeof Swiper === 'undefined') return;
  mainSwiper = new Swiper('.screens', {
    speed: 340,
    spaceBetween: 10,
    resistanceRatio: 0.55,
    noSwipingSelector: '.plate-card, .meal-scroll, input, textarea',   // 卡片区/输入区起滑不切屏
    on: {
      slideChange() { syncChrome(SCREEN_ORDER[this.activeIndex]); },
    },
  });
}

/* ---------- 餐盘卡日期导航：右滑/‹ 看历史，左滑/› 回今天（反馈6） ---------- */
/* 日期工具（localIso/todayIso/dateLabelOf）已移至 logic.js，此处直接 import */
function renderPlateDate() {
  const el = $('#plate-date');
  if (!el) return;
  const t = todayIso();
  const yd = new Date(); yd.setDate(yd.getDate() - 1);
  const yIso = localIso(yd);
  const d = new Date(state.date + 'T00:00:00');
  const weeks = ['日', '一', '二', '三', '四', '五', '六'];
  el.innerHTML = state.date === t ? '今天<small>· 右滑看历史</small>'
    : state.date === yIso ? `昨天<small>${d.getMonth() + 1}/${d.getDate()}</small>`
    : `${d.getMonth() + 1}月${d.getDate()}日<small>周${weeks[d.getDay()]}</small>`;
  const next = $('#plate-next');
  if (next) next.style.visibility = state.date === t ? 'hidden' : 'visible';
}
async function shiftDate(delta) {
  const d = new Date(state.date + 'T00:00:00');
  d.setDate(d.getDate() + delta);
  const next = localIso(d);
  if (next > todayIso()) { toast('已经到今天了'); return; }
  state.date = next;
  renderPlateDate();
  renderDateRow();
  await Promise.all([refreshToday(), loadExercises(), loadRecordPage()]);   // 并行拉取（反馈8）
}
$('#plate-prev').addEventListener('click', () => shiftDate(-1));
$('#plate-next').addEventListener('click', () => shiftDate(1));
/* 卡内滑动通道（触摸+鼠标）：右滑=更早，左滑=更近；与整屏滑动互斥（swipeArmOk 已排除 .plate-card） */
(function bindPlateSwipe() {
  const card = $('.plate-card');
  if (window.AlloyFinger) {
    new AlloyFinger(card, {
      swipe: evt => {
        const dir = String(evt.direction || '').toLowerCase();
        if (dir !== 'left' && dir !== 'right') return;   // 竖向滑动不翻日期
        shiftDate(dir === 'left' ? 1 : -1);   // 左滑→更近一天，右滑→更早一天
      },
    });
  } else {
    let x0 = 0, y0 = 0, x1 = 0, y1 = 0, armed = false;
    const evalSwipe = () => {
      const dx = x1 - x0, dy = y1 - y0;
      if (Math.abs(dx) < 50 || Math.abs(dx) < Math.abs(dy) * 1.5) return;
      shiftDate(dx > 0 ? -1 : 1);
    };
    card.addEventListener('touchstart', e => { armed = true; x0 = x1 = e.touches[0].clientX; y0 = y1 = e.touches[0].clientY; }, { passive: true });
    card.addEventListener('touchmove', e => { if (armed) { x1 = e.touches[0].clientX; y1 = e.touches[0].clientY; } }, { passive: true });
    card.addEventListener('touchend', () => { if (armed) { armed = false; evalSwipe(); } }, { passive: true });
  }
  /* 鼠标拖拽通道（桌面预览） */
  let mx0 = 0, mx1 = 0, marmed = false;
  card.addEventListener('mousedown', e => { marmed = true; mx0 = mx1 = e.clientX; });
  card.addEventListener('mousemove', e => { if (marmed) mx1 = e.clientX; });
  card.addEventListener('mouseup', () => {
    if (!marmed) return;
    marmed = false;
    const dx = mx1 - mx0;
    if (Math.abs(dx) >= 50) shiftDate(dx > 0 ? -1 : 1);
  });
})();

async function loadReportPage() {
  const [report, trend] = await Promise.all([
    HealthAPI.getWeekReport(), HealthAPI.getWeightTrend(),
  ]);
  renderWeekReport(report);
  renderWeightTrend(trend);
}

/* 月报：按周聚合柱状 + 月统计 */
async function loadMonthReport() {
  const r = await HealthAPI.getMonthReport();
  const recorded = r.kcal.filter(v => v > 0);
  const avg = Math.round(recorded.reduce((a, b) => a + b, 0) / (recorded.length || 1));
  renderWeekReport({ ...r, labels: r.weeks, avgText: `月均 ${avg} kcal · 记 ${r.days} 天` });
}
/* 报告页 周/月 切换 */
$$('.page-head .segmented button').forEach(b => b.addEventListener('click', () => {
  if (b.disabled) return;
  $$('.page-head .segmented button').forEach(x => x.classList.toggle('active', x === b));
  if (b.dataset.range === 'month') loadMonthReport();
  else loadReportPage();
}));

/* ============================================================
 * 首页
 * ============================================================ */
function renderGreeting(nickname) {
  const h = new Date().getHours();
  const greet = h < 6 ? '夜深了' : h < 11 ? '早上好' : h < 14 ? '中午好' : h < 18 ? '下午好' : '晚上好';
  $('#home-greeting').textContent = nickname ? `${greet}，${nickname}` : greet;
  const d = new Date();
  const weeks = ['日', '一', '二', '三', '四', '五', '六'];
  $('#home-date').textContent = `${d.getMonth() + 1}月${d.getDate()}日 · 星期${weeks[d.getDay()]}`;
}

/* 签名组件：营养餐盘环 —— 外环热量进度，内环三大营养素配比 */
function renderRing() {
  const s = state.summary;
  const ex = state.exerciseKcal || 0;
  const budget = s.target + ex;   // 今日额度 = 基准目标 + 运动消耗
  const remain = Math.max(0, budget - s.kcal);
  // 反馈4：首页“今日额度”与“我的·今日建议摄入”同源，均含运动消耗，两页不再对不上
  $('#ring-target').textContent = budget;
  $('#ring-eaten').textContent = s.kcal;
  $('#ring-exercise').textContent = ex;
  const note = $('#ring-note');
  if (note) note.textContent = ex > 0
    ? `额度 ${budget} = 基准 ${s.target} + 运动 ${ex} kcal`
    : `基准目标 ${s.target} kcal · 记运动后额度自动上调`;
  // 营养素口径标注：目标只按“基准”算（运动额度不加成），否则“还能吃 X kcal”与脂肪超标会看着自相矛盾
  const nnote = $('#nutrient-note');
  if (nnote) nnote.textContent = `营养素目标 = 基准 ${s.target} × 供能比 50%/25%/25% ÷ (4/4/9) kcal，不含运动额度；热量额度含运动，两者基数不同`;

  const C_OUT = 2 * Math.PI * 78, C_IN = 2 * Math.PI * 62;
  const pct = Math.min(1, s.kcal / budget);
  const ringEl = $('#ring-kcal');
  const off = C_OUT * (1 - pct);
  if (window.anime && window.anime.animate) {
    try { window.anime.animate(ringEl, { strokeDashoffset: off, duration: 600, ease: 'outCubic' }); }
    catch (e) { ringEl.style.strokeDashoffset = off; }
  } else {
    ringEl.style.strokeDashoffset = off;
  }
  ringEl.style.stroke = s.kcal > budget ? 'var(--warn)' : 'var(--primary)';
  animateNum($('#ring-num'), remain);

  const totals = s.carb + s.protein + s.fat || 1;
  const segs = [
    ['carb', s.carb / totals],
    ['protein', s.protein / totals],
    ['fat', s.fat / totals],
  ];
  let offset = 0;
  segs.forEach(([key, ratio]) => {
    const el = $(`#ring-${key}`);
    el.style.strokeDasharray = `${C_IN * ratio} ${C_IN}`;
    el.style.strokeDashoffset = -offset;
    offset += C_IN * ratio;
  });

  renderNutrientBars('#home-nutrients', s);
  renderDailyAdvice();
  // 反馈3：今日摄入/运动变化 → 实时重算实际日均缺口并同步代谢卡达标时间（仅看今天时）
  if (state.date === todayIso()) { recomputeActualDeficitLive(); renderMetab(); }
}

/* 每日建议：规则表引擎（logic.js ADVICE_RULES/buildAdvice），最多 3 条；新增建议只需加一条规则 */
function renderDailyAdvice() {
  const s = state.summary;
  const el = $('#home-advice');
  if (!s || !el) return;
  const ctx = makeAdviceCtx({
    summary: s,
    exerciseKcal: state.exerciseKcal || 0,
    records: state.records,
    isToday: state.date === todayIso(),
    weightKg: (state.body && state.body.weightKg) || 55,
    waterGoalMl: state.waterGoalMl,
  });
  const tips = buildAdvice(ctx);
  el.innerHTML = tips.map(([e, t]) => `<li><span class="ai">${e}</span><span>${t}</span></li>`).join('');
}

/* 营养素进度条（首页/报告共用）：目标量由 logic.macroGoals 统一估算 */
function renderNutrientBars(sel, s) {
  const g = macroGoals(s.target);
  const items = [
    ['carb',    '碳水',   s.carb,    g.carb],
    ['protein', '蛋白质', s.protein, g.protein],
    ['fat',     '脂肪',   s.fat,     g.fat],
  ];
  $(sel).innerHTML = items.map(([key, name, val, goal]) => `
    <div class="row">
      <span class="name">${name}</span>
      <span class="track"><span class="fill ${key}" style="width:${Math.min(100, val / goal * 100)}%"></span></span>
      <span class="val">${val}/${goal}g</span>
    </div>`).join('');
}

/* 数字滚动动画（anime.js，开源集成）：环中心数字平滑过渡 */
function animateNum(el, to) {
  const from = Number(el.textContent) || 0;
  if (from === to || !window.anime || !window.anime.animate) { el.textContent = to; return; }
  const proxy = { v: from };
  try {
    window.anime.animate(proxy, { v: to, duration: 500, ease: 'outCubic', onUpdate: () => { el.textContent = Math.round(proxy.v); } });
  } catch (e) { el.textContent = to; }
}

/* 列表增删过渡（AutoAnimate，开源集成）：记录/运动列表增删自动补位移动画 */
function initAutoAnimate() {
  if (!window.autoAnimate) return;
  ['#record-lists', '#exercise-list'].forEach(sel => {
    const el = $(sel);
    if (el) window.autoAnimate(el, { duration: 220 });
  });
  window.__aaBound = true;
}
if (document.readyState === 'complete') initAutoAnimate();
else window.addEventListener('load', initAutoAnimate);

/* 滚动穿透防治（mobile-web-best-practice）：任一弹层打开时锁背景滚动 */
new MutationObserver(() => {
  const anyOpen = $$('.sheet').some(s => s.classList.contains('show'));
  document.body.classList.toggle('lock-scroll', anyOpen);
}).observe(document.documentElement, { subtree: true, attributes: true, attributeFilter: ['class'] });

/* 喝水打卡：杯容量/目标范围常量已移至 logic.js，此处直接 import */
function renderWater() {
  const n = state.summary.water;
  const goal = state.waterGoalMl;
  const wt = $('#water-title');
  if (wt) wt.textContent = state.date === todayIso() ? '喝水打卡' : `喝水 · ${dateLabelOf(state.date)}`;
  const ml = n * WATER_CUP_ML;
  const reached = ml >= goal;
  const pct = Math.min(100, ml / goal * 100);
  animateNum($('#water-ml'), ml);   // anime.js 数字滚动
  $('#water-goal-ml').textContent = goal;
  $('#water-fill').style.width = pct + '%';
  $('#water-cup-level').style.height = pct + '%';
  const seg = 100 / (goal / WATER_CUP_ML);
  $('#water-ticks').style.background =
    `repeating-linear-gradient(90deg, transparent 0, transparent calc(${seg}% - 2px), var(--surface) calc(${seg}% - 2px), var(--surface) ${seg}%)`;
  $('#water-hint').innerHTML = reached ? '目标已达成 🎉' : `已喝 ${n} 杯 · 每杯 ${WATER_CUP_ML}ml`;
  $('#water-undo').style.visibility = n > 0 ? 'visible' : 'hidden';
  // 同步「喝水进度」常驻通知（Android 16 上以灵动岛样式呈现；旧机型/桌面端无此接口则跳过）
  if (state.date === todayIso() && remindAvail()) {
    try { window.SGNative.updateWaterProgress(n, Math.round(goal / WATER_CUP_ML)); } catch (e) { /* 接口不存在时忽略 */ }
  }
}

async function drinkOneCup() {
  if (state.summary.water * WATER_CUP_ML >= state.waterGoalMl) {
    toast(`目标 ${state.waterGoalMl}ml 已达成，明天继续`);
    return;
  }
  const prev = state.summary.water;
  state.summary.water = prev + 1;   // 乐观更新：界面立即响应，云端后台同步（反馈8）
  renderWater();
  buzz(6);
  toast(`+${WATER_CUP_ML}ml · 已喝 ${state.summary.water * WATER_CUP_ML}ml`);
  try {
    const { water } = await HealthAPI.addWater(1, state.date);
    state.summary.water = water;
    renderWater();
  } catch (e) {
    state.summary.water = prev;
    renderWater();
    toast('同步失败：' + (e.message || '网络异常'));
  }
}
$('#water-cup').addEventListener('click', drinkOneCup);

$('#water-undo').addEventListener('click', async () => {
  if (state.summary.water <= 0) return;
  const prev = state.summary.water;
  state.summary.water = prev - 1;
  renderWater();
  toast(`已退回一杯 · 剩 ${state.summary.water * WATER_CUP_ML}ml`);
  try {
    const { water } = await HealthAPI.addWater(-1, state.date);
    state.summary.water = water;
    renderWater();
  } catch (e) {
    state.summary.water = prev;
    renderWater();
    toast('同步失败：' + (e.message || '网络异常'));
  }
});

/* 喝水目标设置：底部弹层 + 200ml 步进器 */
function openGoalSheet() {
  $('#water-goal-val').value = state.waterGoalMl;
  $('#sheet-mask').classList.add('show');
  $('#goal-sheet').classList.add('show');
}
function bumpGoal(dir) {
  const cur = Number($('#water-goal-val').value);
  const next = Math.min(WATER_GOAL_MAX, Math.max(WATER_GOAL_MIN, cur + dir * WATER_CUP_ML));
  $('#water-goal-val').value = next;
  if (next === cur) toast(dir > 0 ? '最大 3000ml' : '最小 800ml');
}
$('#water-goal-edit').addEventListener('click', openGoalSheet);
$('#water-goal-dec').addEventListener('click', () => bumpGoal(-1));
$('#water-goal-inc').addEventListener('click', () => bumpGoal(1));
$('#water-goal-save').addEventListener('click', async () => {
  const ml = Number($('#water-goal-val').value);
  const { waterGoalMl } = await HealthAPI.setWaterGoal(ml);
  state.waterGoalMl = waterGoalMl;
  closeSheet();
  renderWater();
  toast(`喝水目标已设为 ${waterGoalMl}ml`);
});

/* ============================================================
 * 记录页
 * ============================================================ */
function renderDateRow() {
  const weeks = ['日', '一', '二', '三', '四', '五', '六'];
  const today = new Date();
  $('#date-row').innerHTML = Array.from({ length: 7 }, (_, i) => {
    const d = new Date(today);
    d.setDate(d.getDate() - (6 - i));
    const iso = localIso(d);
    return `<button class="chip ${iso === state.date ? 'active' : ''}" data-date="${iso}">
      ${i === 6 ? '今天' : `${d.getMonth() + 1}/${d.getDate()}`}</button>`;
  }).join('');
}
$('#date-row').addEventListener('click', async e => {
  const chip = e.target.closest('.chip');
  if (!chip) return;
  state.date = chip.dataset.date;
  renderDateRow();
  renderPlateDate();
  await Promise.all([refreshToday(), loadRecordPage(), loadExercises()]);   // 并行拉取，切换更快
});

function renderRecordLists() {
  const byMeal = { breakfast: [], lunch: [], dinner: [], snack: [] };
  state.records.forEach(r => byMeal[r.meal]?.push(r));
  /* 全天无记录：统一空态（替代四个重复的空卡片，减少视觉噪音） */
  if (!state.records.length) {
    $('#record-lists').innerHTML = `
      <div class="day-empty">
        <div class="art">🍽️</div>
        <p class="t">这一天还没有记录</p>
        <p class="s">点下方「记一笔」记下第一餐，开始追踪热量</p>
      </div>`;
    return;
  }
  $('#record-lists').innerHTML = Object.entries(byMeal).map(([meal, list]) => {
    const sum = list.reduce((a, r) => a + r.kcal, 0);
    if (!list.length) {
      /* 空餐组：一行细提示，点一下即为该餐次记一笔 */
      return `
      <section class="meal-section meal-section-empty">
        <div class="sec-head"><span class="sec-emoji"><img src="${MEAL_IMG[meal]}" alt=""></span>${MEAL_NAMES[meal]}<span class="sum">未记录</span></div>
        <button class="meal-empty" data-meal-add="${meal}">＋ 加一份</button>
      </section>`;
    }
    return `
    <section class="meal-section">
      <div class="sec-head"><span class="sec-emoji"><img src="${MEAL_IMG[meal]}" alt=""></span>${MEAL_NAMES[meal]}<span class="sum">${sum} kcal</span></div>
      ${list.map(r => `
        <div class="food-item">
          <span class="thumb">${r.image ? `<img class="thumb-img" src="${r.image}" alt="">` : r.emoji}</span>
          <span class="info">
            <span class="name">${r.name}</span>
            <span class="meta" style="display:block">${r.portion}</span>
          </span>
          <span class="kcal">${r.kcal}<small> kcal</small></span>
          <button class="del" data-del="${r.id}" aria-label="删除${r.name}">✕</button>
        </div>`).join('')}
    </section>`;
  }).join('');
}

async function deleteRecordById(id) {
  if ($('#confirm-sheet').classList.contains('show')) return;   // 防长按+click 双触发
  const confirmed = await showConfirm('确认删除', '删除后无法恢复，确定要删除这条记录吗？');
  if (!confirmed) return;
  const rec = state.records.find(r => r.id === id);
  if (rec) {   // 乐观删除：立即移除，失败放回
    state.records = state.records.filter(r => r.id !== id);
    state.summary.kcal -= rec.kcal || 0;
    state.summary.protein -= rec.protein || 0;
    state.summary.carb -= rec.carb || 0;
    state.summary.fat -= rec.fat || 0;
    renderRing();
    renderRecordLists();
  }
  toast('已删除记录');
  HealthAPI.deleteFoodRecord(id).then(async () => {
    await Promise.all([refreshToday(), loadRecordPage()]);
  }).catch(err => {
    if (rec) {
      state.records.push(rec);
      state.summary.kcal += rec.kcal || 0;
      state.summary.protein += rec.protein || 0;
      state.summary.carb += rec.carb || 0;
      state.summary.fat += rec.fat || 0;
      renderRing();
      renderRecordLists();
    }
    toast('删除失败：' + (err.message || '网络异常'));
  });
}
$('#record-lists').addEventListener('click', e => {
  const mealAdd = e.target.closest('[data-meal-add]');
  if (mealAdd) { openSheet(mealAdd.dataset.mealAdd); return; }   // 空餐组：直接为该餐次记一笔
  const btn = e.target.closest('[data-del]');
  if (btn) deleteRecordById(btn.dataset.del);
});

async function loadRecordPage() {
  state.records = await HealthAPI.getMealRecords(state.date);
  renderRecordLists();
}

/* ============================================================
 * 添加食物弹层
 * ============================================================ */
/* 按当前时间智能默认餐次 */
function defaultMeal() {
  const h = new Date().getHours();
  if (h < 10) return 'breakfast';
  if (h < 15) return 'lunch';
  if (h < 21) return 'dinner';
  return 'snack';
}
function setMeal(meal) {
  state.mealChosen = meal;
  $$('#meal-seg button').forEach(b => b.classList.toggle('active', b.dataset.meal === meal));
  $('#sheet-title').textContent = `记一笔 · ${MEAL_NAMES[meal]}`;
}
function openSheet(meal) {
  setMeal(meal || defaultMeal());
  $('#sheet-search').value = '';
  fillSheetResults('');
  $('#sheet-mask').classList.add('show');
  $('#add-sheet').classList.add('show');
}
function closeSheet() {
  $('#sheet-mask').classList.remove('show');
  $('#add-sheet').classList.remove('show');
  $('#goal-sheet').classList.remove('show');
}

async function fillSheetResults(keyword) {
  state.sheetKeyword = keyword;
  // 显示 loading 状态
  $('#sheet-results').innerHTML = '<div class="empty"><div class="art">⏳</div><p>搜索中...</p></div>';
  try {
    const foods = await HealthAPI.searchFoods(keyword, state.mealChosen);
    $('#sheet-results').innerHTML = foods.length ? foods.map(f => `
      <div class="food-item">
        <span class="thumb">${f.image ? `<img class="thumb-img" src="${f.image}" alt="">` : f.emoji}</span>
        <span class="info">
          <span class="name">${f.name}</span>
          <span class="meta" style="display:block">${f.meta}</span>
        </span>
        <span class="kcal">${f.kcal}<small> kcal</small></span>
        <button class="btn btn-soft" style="padding:8px 14px" data-add='${JSON.stringify(f)}'>${f.per100 ? (f.unit === 'ml' ? '按毫升加' : '按克加') : '添加'}</button>
      </div>`).join('')
    : `<div class="empty"><div class="art">🔍</div><p>没找到「${keyword}」<br>换个说法，或添加自定义食物</p>
       <button class="btn btn-soft" id="cf-open" style="margin-top:var(--sp-3)">＋ 自定义食物</button></div>`;
  } catch (e) {
    // 请求失败不再永久停在 loading，给错误态 + 重试入口
    $('#sheet-results').innerHTML = `<div class="empty"><div class="art">⚠️</div><p>搜索失败：${e.message || '网络异常'}</p>
      <button class="btn btn-soft" id="sheet-retry" style="margin-top:var(--sp-3)">重试</button></div>`;
  }
}

$('#sheet-results').addEventListener('click', async e => {
  const retry = e.target.closest('#sheet-retry');
  if (retry) { fillSheetResults(state.sheetKeyword || ''); return; }
  const cfopen = e.target.closest('#cf-open');
  if (cfopen) { openCustomFoodSheet(); return; }
  const btn = e.target.closest('[data-add]');
  if (!btn || btn.disabled) return;
  const f = JSON.parse(btn.dataset.add);
  if (f.per100) { openPortionSheet(f); return; }   // 克数可自定义食物走份量弹层
  // 乐观更新：立即入列表+环，不等网络（反馈8）；失败回滚
  const temp = {
    id: 'tmp_' + Date.now(), meal: state.mealChosen,
    name: f.name, portion: f.meta, kcal: f.kcal, emoji: f.emoji, image: f.image || '',
    protein: f.protein || 0, carb: f.carb || 0, fat: f.fat || 0,
  };
  state.records.push(temp);
  state.summary.kcal += temp.kcal;
  state.summary.protein += temp.protein;
  state.summary.carb += temp.carb;
  state.summary.fat += temp.fat;
  renderRing();
  renderRecordLists();
  buzz(10);
  toast(`已添加 ${f.name} · 可继续添加`);
  btn.disabled = true;
  HealthAPI.addFoodRecord({
    date: state.date, meal: state.mealChosen,
    name: f.name, portion: f.meta, kcal: f.kcal, emoji: f.emoji,
    protein: f.protein, carb: f.carb, fat: f.fat, image: f.image,
  }).then(async () => {
    await Promise.all([refreshToday(), loadRecordPage()]);   // 静默对账云端
  }).catch(err => {
    state.records = state.records.filter(r => r.id !== temp.id);
    state.summary.kcal -= temp.kcal;
    state.summary.protein -= temp.protein;
    state.summary.carb -= temp.carb;
    state.summary.fat -= temp.fat;
    renderRing();
    renderRecordLists();
    toast('添加失败：' + (err.message || '网络异常'));
  }).finally(() => { btn.disabled = false; });
});

let searchTimer;
$('#sheet-search').addEventListener('input', e => {
  clearTimeout(searchTimer);
  searchTimer = setTimeout(() => fillSheetResults(e.target.value), 200);
});
$('#sheet-close').addEventListener('click', closeSheet);
$('#sheet-done').addEventListener('click', closeSheet);
$('#sheet-mask').addEventListener('click', closeSheet);
document.addEventListener('keydown', e => { if (e.key === 'Escape') closeSheet(); });

/* 首页餐次快捷入口已移除（换为每日建议卡），记录入口在记录页「记一笔」 */
$('#btn-add-food').addEventListener('click', () => openSheet());
$('#meal-seg').addEventListener('click', e => {
  const b = e.target.closest('button'); if (!b) return;
  setMeal(b.dataset.meal);
  fillSheetResults(state.sheetKeyword || '');   // 按新餐次重新过滤结果
});

/* ---------- 份量弹层：per100 食物按份量换算营养（米饭等）；自定义饮品按 ml ---------- */
let portionFood = null;
let portionUnit = 'g';   // 当前弹层份量单位，取自食物 unit（无则克）
/* portionMacros 已移至 logic.js，此处直接 import */
function openPortionSheet(f) {
  portionFood = f;
  portionUnit = cfUnitOf(f);
  $('#portion-title').textContent = `${f.name} · 自定义份量`;
  $('#portion-g-val').value = f.baseG || 100;
  $('#portion-unit').textContent = portionUnit;
  $('#portion-hint').textContent = `点数字可直接输入${portionUnit === 'ml' ? '毫升数' : '克数'}，营养按每 100${portionUnit} 换算`;
  updatePortionPreview();
  $('#portion-mask').classList.add('show');
  $('#portion-sheet').classList.add('show');
}
function closePortionSheet() {
  $('#portion-mask').classList.remove('show');
  $('#portion-sheet').classList.remove('show');
}
function updatePortionPreview() {
  const f = portionFood; if (!f) return;
  const g = Number($('#portion-g-val').value) || 0;
  const r = portionMacros(f, g);
  $('#portion-preview').innerHTML = `${g}${portionUnit} ≈ <b>${r.kcal}</b> kcal · 蛋白 ${r.protein}g / 碳水 ${r.carb}g / 脂肪 ${r.fat}g`;
}
$('#portion-g-dec').addEventListener('click', () => { bumpBodyVal('#portion-g-val', -10, 10, 2000); updatePortionPreview(); });
$('#portion-g-inc').addEventListener('click', () => { bumpBodyVal('#portion-g-val', 10, 10, 2000); updatePortionPreview(); });
bindStepperNorm('#portion-g-val', 10, 2000, 0);
$('#portion-g-val').addEventListener('input', updatePortionPreview);
$('#portion-g-val').addEventListener('change', updatePortionPreview);
$('#portion-close').addEventListener('click', closePortionSheet);
$('#portion-mask').addEventListener('click', closePortionSheet);
$('#portion-save').addEventListener('click', () => {
  const f = portionFood; if (!f) return;
  const g = Number($('#portion-g-val').value) || 0;
  if (g < 10) { toast(`请输入${portionUnit === 'ml' ? '毫升数' : '克数'}`); return; }
  const r = portionMacros(f, g);
  const temp = {
    id: 'tmp_' + Date.now(), meal: state.mealChosen,
    name: f.name, portion: `${g}${portionUnit}`, kcal: r.kcal, emoji: f.emoji, image: f.image || '',
    protein: r.protein, carb: r.carb, fat: r.fat,
  };
  state.records.push(temp);   // 乐观更新
  state.summary.kcal += r.kcal;
  state.summary.protein += r.protein;
  state.summary.carb += r.carb;
  state.summary.fat += r.fat;
  renderRing();
  renderRecordLists();
  closePortionSheet();
  toast(`已添加 ${f.name} ${g}${portionUnit} · 可继续添加`);
  HealthAPI.addFoodRecord({
    date: state.date, meal: state.mealChosen,
    name: f.name, portion: `${g}${portionUnit}`, kcal: r.kcal, emoji: f.emoji,
    protein: r.protein, carb: r.carb, fat: r.fat, image: f.image,
  }).then(async () => {
    await Promise.all([refreshToday(), loadRecordPage()]);
  }).catch(err => {
    state.records = state.records.filter(x => x.id !== temp.id);
    state.summary.kcal -= r.kcal;
    state.summary.protein -= r.protein;
    state.summary.carb -= r.carb;
    state.summary.fat -= r.fat;
    renderRing();
    renderRecordLists();
    toast('添加失败：' + (err.message || '网络异常'));
  });
});

/* 拍照识别入口已按需求移除（接口 recognizeFood 仍保留在 api.js，将来要用再接） */

/* ============================================================
 * 报告页
 * ============================================================ */
function renderWeekReport(r) {
  const labels = r.labels || r.days;
  const max = Math.max(...r.kcal, r.target) * 1.1;
  // 动态定位"今天"：getDay() 返回 0=日,1=一,...,6=六，转换为数组索引 0=一,...,6=日；月视图不高亮
  const todayIdx = new Date().getDay();
  const todayIdxInWeek = r.isWeek === false ? -1 : (todayIdx === 0 ? 6 : todayIdx - 1);
  $('#week-chart').innerHTML =
    `<div class="target-line" style="bottom:${r.target / max * 100}%"><span>目标 ${r.target}</span></div>` +
    r.kcal.map((kcal, i) => `
      <div class="col ${i === todayIdxInWeek ? 'today' : ''} ${kcal > r.target ? 'over' : ''}">
        <button type="button" class="bar" style="height:${Math.max(4, kcal / max * 100)}%"><span class="bar-val">${kcal > 0 ? kcal + ' kcal' : '未记录'}</span></button>
        <span class="lbl">${i === todayIdxInWeek ? '今天' : labels[i]}</span>
      </div>`).join('');

  const recorded = r.kcal.filter(v => v > 0);
  const avg = Math.round(recorded.reduce((a, b) => a + b, 0) / (recorded.length || 1));
  $('#report-avg').textContent = r.avgText || `日均 ${avg} kcal`;

  $('#report-stats').innerHTML = [
    ['carb', '碳水达标', r.rates.carb], ['protein', '蛋白达标', r.rates.protein], ['fat', '脂肪控制', r.rates.fat],
  ].map(([key, label, rate]) => `
    <div class="stat-card">
      <p class="label">${label}</p>
      <p class="num">${rate}<small> %</small></p>
      <span class="track" style="display:block;height:6px;border-radius:99px;background:var(--surface-soft);margin-top:8px">
        <span class="fill ${key}" style="display:block;height:100%;border-radius:99px;width:${rate}%;background:var(--nut-${key})"></span>
      </span>
    </div>`).join('');

  $('#report-advice').textContent = buildPeriodAdvice(r, avg);
  $('#advice-title').textContent = r.isWeek === false ? '本月建议' : '本周建议';
}

/* 点击柱状图某根柱子 → 柱顶浮出该日/该周热量；再点同一根收起，点别的切换。
 * 事件委托绑在静态容器上，innerHTML 重渲染不受影响。 */
$('#week-chart').addEventListener('click', e => {
  const col = e.target.closest('.col');
  if (!col) return;
  const wasOn = col.classList.contains('val-on');
  $('#week-chart').querySelectorAll('.col.val-on').forEach(c => c.classList.remove('val-on'));
  if (!wasOn) col.classList.add('val-on');
});

/* 多维规则建议引擎（周/月报）：按达标率+热量组合生成，最多 3 条拼接。
 * 与每日建议（logic.buildAdvice）区分，改名避免与 import 同名冲突。 */
function buildPeriodAdvice(r, avgKcal) {
  const tips = [];
  if (r.rates.protein < 80) tips.push(`蛋白质达标率 ${r.rates.protein}%，偏低，每餐加一份鱼、虾、蛋或豆制品`);
  if (r.rates.carb > 110) tips.push(`碳水达目标 ${r.rates.carb}%，偏高，主食可换粗粮或减两成`);
  else if (r.rates.carb < 60) tips.push(`碳水达标率 ${r.rates.carb}%，偏低，主食不足易乏力，保留适量谷物`);
  if (r.rates.fat > 110) tips.push(`脂肪达目标 ${r.rates.fat}%，偏高，少油炸、多蒸煮拌`);
  if (avgKcal > r.target) tips.push(`日均 ${avgKcal} kcal 超目标 ${r.target} kcal，想控重每日减 ${avgKcal - r.target} kcal 左右`);
  else if (avgKcal > 0 && avgKcal < r.target * 0.7) tips.push(`日均 ${avgKcal} kcal 明显低于目标，长期吃太少会掉代谢，适当吃够`);
  if (!tips.length) tips.push('三餐节奏稳定，营养素都在合理区间，继续保持，把运动打卡也安排上');
  return tips.slice(0, 3).join('；') + '。';
}

function renderWeightTrend(w) {
  // 空数据保护
  if (!w.points || w.points.length === 0) {
    $('#weight-svg').innerHTML = '<text x="50%" y="50%" text-anchor="middle" fill="var(--ink-3)" font-size="13">暂无体重数据</text>';
    $('#weight-delta').textContent = '';
    return;
  }
  const raw = w.points;
  const labels = w.labels || [];
  const single = raw.length === 1;   // 只有一天数据时画居中单点：复制成两端两点会看成"两天持平"
  const pts0 = single ? [raw[0]] : raw;
  const n = pts0.length;

  /* 值域：数据范围外扩，且保证最小可视跨度 1kg（避免微波动被放大成"过山车"），刻度对齐 0.5 */
  let hi = Math.max(...pts0), lo = Math.min(...pts0);
  if (hi - lo < 1) { const c = (hi + lo) / 2; hi = c + 0.5; lo = c - 0.5; }
  hi = Math.ceil(hi * 2) / 2; lo = Math.floor(lo * 2) / 2;

  /* 坐标系：左侧 36px 放刻度文字，底部 24px 放日期 */
  const X0 = 44, X1 = 306, Y0 = 16, Y1 = 104;   // X1 右端留 14px 给末点日期（居中半宽约 12px）；X0 与刻度文字偏移共同决定首点数值的左侧间距
  const xOf = i => (n === 1 ? (X0 + X1) / 2 : X0 + i * (X1 - X0) / (n - 1));
  const yOf = v => Y1 - (v - lo) / (hi - lo) * (Y1 - Y0);

  /* Y 轴：4 条网格线 + 刻度值 */
  const step = (hi - lo) / 3;
  let grid = '';
  for (let i = 0; i < 4; i++) {
    const v = hi - step * i, y = yOf(v);
    grid += `<line x1="${X0}" y1="${y.toFixed(1)}" x2="${X1}" y2="${y.toFixed(1)}" stroke="var(--line)" stroke-width="0.7"${i === 3 ? '' : ' stroke-dasharray="3 4"'}/>` +
            `<text x="${X0 - 10}" y="${(y + 3).toFixed(1)}" text-anchor="end" font-size="9" fill="var(--ink-3)">${v.toFixed(1)}</text>`;
  }

  const pts = pts0.map((v, i) => [xOf(i), yOf(v)]);
  const path = pts.map(([x, y], i) => `${i ? 'L' : 'M'}${x.toFixed(1)} ${y.toFixed(1)}`).join(' ');
  const area = `${path} L${pts[n - 1][0].toFixed(1)} ${Y1} L${pts[0][0].toFixed(1)} ${Y1} Z`;

  /* 数据点：圆点 + 上方数值；末点高亮。首尾点数值改锚点，避免与 Y 轴刻度/右边界重叠 */
  const dots = pts.map(([x, y], i) => {
    const last = i === n - 1;
    const v = raw[Math.min(i, raw.length - 1)];
    const anchor = i === 0 && !single ? 'start' : last && !single ? 'end' : 'middle';
    const tx = i === 0 && !single ? x - 1 : last && !single ? x + 1 : x;
    return `<circle cx="${x.toFixed(1)}" cy="${y.toFixed(1)}" r="${last ? 4.2 : 3}" fill="${last ? 'var(--primary)' : '#fff'}" stroke="var(--primary)" stroke-width="1.8"/>` +
           `<text x="${tx.toFixed(1)}" y="${(y - 8).toFixed(1)}" text-anchor="${anchor}" font-size="9.5" font-weight="600" fill="${last ? 'var(--primary-deep)' : 'var(--ink-2)'}">${v.toFixed(2)}</text>`;
  }).join('');

  /* X 轴：日期（与数据点一一对应；单点态只有 1 个日期） */
  const xLabels = pts.map(([x], i) => labels[i]
    ? `<text x="${x.toFixed(1)}" y="${Y1 + 16}" text-anchor="middle" font-size="9.5" font-weight="500" fill="var(--ink-2)">${labels[i]}</text>` : '').join('');

  $('#weight-svg').innerHTML = `
    <path d="${area}" fill="var(--primary)" opacity="0.08"/>
    ${grid}
    <path d="${path}" fill="none" stroke="var(--primary)" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>
    ${dots}
    ${xLabels}`;

  const delta = (raw.at(-1) - raw[0]).toFixed(2);
  $('#weight-delta').textContent = `当前 ${raw.at(-1)} kg · 本周 ${delta > 0 ? '+' : ''}${delta} kg`;
  $('#weight-delta').style.color = delta <= 0 ? 'var(--primary)' : 'var(--warn)';
}

/* ---------- 每日体重日志：趋势卡入口 + 弹层（反馈5） ---------- */
function openWeightLogSheet() {
  $('#weight-log-val').value = (state.body && state.body.weightKg) || 55;
  const inApk = scaleAvail();
  $('#btn-scale-sync').style.display = inApk ? '' : 'none';
  // 诊断三件套收敛：仅 sg_debug=1 时露出（浏览器控制台 localStorage.setItem('sg_debug','1') 开启）
  const dbg = inApk && typeof window.SGNative.debugScale === 'function' && localStorage.getItem('sg_debug') === '1';
  $('#btn-scale-debug').style.display = dbg ? '' : 'none';
  $('#btn-scale-probe').style.display = dbg && typeof window.SGNative.probeScale === 'function' ? '' : 'none';
  $('#weight-log-mask').classList.add('show');
  $('#weight-log-sheet').classList.add('show');
}
function closeWeightLogSheet() {
  $('#weight-log-mask').classList.remove('show');
  $('#weight-log-sheet').classList.remove('show');
}
$('#btn-log-weight').addEventListener('click', openWeightLogSheet);
$('#weight-log-close').addEventListener('click', closeWeightLogSheet);
$('#weight-log-mask').addEventListener('click', closeWeightLogSheet);
$('#weight-log-dec').addEventListener('click', () => bumpBodyVal('#weight-log-val', -0.5, 20, 300, 2));
$('#weight-log-inc').addEventListener('click', () => bumpBodyVal('#weight-log-val', 0.5, 20, 300, 2));
bindStepperNorm('#weight-log-val', 20, 300, 2);
async function saveWeightKg(w) {
  if (!w || w < 20 || w > 300) { toast('请输入有效体重'); return; }
  try {
    const r = await HealthAPI.logWeight(w, todayIso());
    if (state.body) {
      state.body.weightKg = r.weightKg;
      state.body.bmi = +(r.weightKg / Math.pow(state.body.heightCm / 100, 2)).toFixed(1);
      saveBodyLocal(currentUid(), state.body);
      renderBodyCard();
      renderMetab();
    }
    closeWeightLogSheet();
    renderWeightTrend(await HealthAPI.getWeightTrend());
    await syncTarget();   // 体重变 → BMR/建议摄入重算并同步云端
    toast(`已记录 ${r.weightKg} kg · 趋势已更新`);
  } catch (e) {
    toast('保存失败：' + (e.message || '网络异常'));
  }
}
$('#weight-log-save').addEventListener('click', () => saveWeightKg(Number($('#weight-log-val').value)));

/* ---------- 体脂秤同步：SGNative.startScale → SG_onScaleWeight/Status（v1.2.0，仅 APK 内生效） ---------- */
const scaleAvail = () => remindAvail() && typeof window.SGNative.startScale === 'function';
window.SG_onScaleWeight = (kg, stable) => {
  $('#weight-log-val').value = kg;
  if (stable) saveWeightKg(kg);
};
window.SG_onScaleStatus = msg => toast(msg);
window.SG_onScaleDebug = text => {
  const el = $('#scale-debug-out');
  el.style.display = 'block';
  el.textContent = text;
};
$('#btn-scale-sync').addEventListener('click', () => {
  if (!window.SGNative.startScale()) toast('无法启动蓝牙同步');
});
$('#btn-scale-debug').addEventListener('click', () => {
  $('#scale-debug-out').textContent = '扫描中…请光脚站上秤保持 12 秒';
  $('#scale-debug-out').style.display = 'block';
  if (!window.SGNative.debugScale()) toast('无法启动诊断扫描');
});
window.SG_onScaleProbe = line => {
  const el = $('#scale-debug-out');
  el.style.display = 'block';
  el.textContent = (el.textContent === '探测日志：' ? '' : el.textContent + '\n') + line;
  el.scrollTop = el.scrollHeight;
};
$('#btn-scale-probe').addEventListener('click', () => {
  $('#scale-debug-out').textContent = '探测日志：';
  $('#scale-debug-out').style.display = 'block';
  $('#btn-scale-copy').style.display = '';
  if (!window.SGNative.probeScale()) toast('无法启动连接探测');
});
$('#btn-scale-copy').addEventListener('click', async () => {
  const text = $('#scale-debug-out').textContent;
  try {
    await navigator.clipboard.writeText(text);
    toast('日志已复制，粘贴发我即可');
  } catch (e) {
    const ta = document.createElement('textarea');
    ta.value = text;
    document.body.appendChild(ta);
    ta.select();
    document.execCommand('copy');
    ta.remove();
    toast('日志已复制（兼容模式）');
  }
});

/* 报告页"月"档位：接口 getMonthReport 已预留，UI 置灰占位 */

/* ============================================================
 * 我的
 * ============================================================ */
function renderProfile(p) {
  $('#profile-name').textContent = p.nickname;
  $('#profile-signature').textContent = p.signature;
  const avatarEls = [$('.profile-head .avatar'), $('#home-avatar')];
  if (p.avatarData) {
    avatarEls.forEach(el => {
      el.textContent = '';
      const img = document.createElement('img');
      img.src = p.avatarData;
      el.appendChild(img);
    });
  } else {
    avatarEls.forEach(el => {
      el.innerHTML = '';
      el.textContent = p.avatarText || p.nickname.slice(0, 1);
    });
  }
  $('#goal-kcal').innerHTML = `${p.goal.dailyKcal} <small>kcal</small>`;
  $('#goal-weight').innerHTML = `${p.goal.targetWeight} <small>kg</small>`;
  state.profileData = p;
  const cloudTs = Number(p.bodyUpdatedAt) || 0;
  state.body = effectiveBody(p.body, p.id, cloudTs);
  if (loadBodyTs(p.id) < cloudTs) saveBodyLocal(p.id, state.body, cloudTs);   // 云端更新 → 刷新本地缓存
  renderBodyCard();
  renderMetab();
  updatePeAvatar(p);
}
$('#btn-edit-goal').addEventListener('click', openGoalEditSheet);
$('#home-avatar').addEventListener('click', () => switchScreen('profile'));

/* ---------- 系统通知提醒：原生桥接 SGNative（仅 APK 内生效；桌面端存偏好） ---------- */
const remindAvail = () => typeof window.SGNative !== 'undefined';
function renderRemindSwitch() {
  const sw = $('#remind-switch');
  if (!sw) return;
  const on = remindAvail() ? window.SGNative.remindersEnabled() : localStorage.getItem('sg_remind_on') === '1';
  sw.classList.toggle('on', on);
  sw.setAttribute('aria-checked', on ? 'true' : 'false');
}
$('#remind-switch').addEventListener('click', () => {
  const on = !$('#remind-switch').classList.contains('on');
  if (remindAvail()) window.SGNative.setReminders(on);
  else localStorage.setItem('sg_remind_on', on ? '1' : '0');
  renderRemindSwitch();
  toast(on ? '提醒已开启：每天定点弹系统通知' : '提醒已关闭');
});
$('#remind-test').addEventListener('click', () => {
  if (remindAvail()) { window.SGNative.testNotify(); toast('测试通知已发，看通知栏'); }
  else toast('系统通知仅 App 安装包内支持');
});
$('#remind-water-test').addEventListener('click', () => {
  if (!remindAvail()) { toast('灵动岛提醒仅 App 安装包内支持'); return; }
  // 走的是和真实到点同一条链路（同一张常驻卡、同文案、同样响铃），只是立刻发
  const ok = window.SGNative.testWaterReminder();
  toast(ok ? '已发出：看状态栏胶囊 / 通知栏' : '先把上面的提醒开关打开');
});
renderRemindSwitch();

/* 点击常驻卡/胶囊 → 回首页并定位到喝水卡（原生在页面加载完成或 onNewIntent 时调用） */
window.SG_GOTO_WATER = function () {
  let tries = 0;
  const jump = () => {
    const card = document.querySelector('#screen-home .water-card');
    const bs = bsMap.get('screen-home');
    // 冷启动时登录态与滚动实例可能还没就绪，短暂重试
    if (!HealthAPI.isLoggedIn() || !card || !bs) {
      if (++tries < 20) setTimeout(jump, 250);
      return;
    }
    switchScreen('home');
    bs.refresh();
    bs.scrollToElement(card, 320, 0, -16);   // 留一点上边距，别顶到卡片
    card.classList.add('flash');
    setTimeout(() => card.classList.remove('flash'), 1700);
  };
  jump();
};

/* ============================================================
 * 头像上传：选图 → canvas 压缩 → 上传 → 刷新
 * ============================================================ */
const AVATAR_MAX = 256;   // 压缩边长
function compressAvatar(file) {
  return new Promise((resolve, reject) => {
    const img = new Image();
    const url = URL.createObjectURL(file);
    img.onload = () => {
      const scale = Math.min(1, AVATAR_MAX / Math.max(img.width, img.height));
      const w = Math.round(img.width * scale), h = Math.round(img.height * scale);
      const canvas = document.createElement('canvas');
      canvas.width = w; canvas.height = h;
      canvas.getContext('2d').drawImage(img, 0, 0, w, h);
      URL.revokeObjectURL(url);
      // 优先 jpeg（体积小），webp 其次；png 保留透明
      const type = file.type === 'image/png' ? 'image/png' : 'image/jpeg';
      resolve(canvas.toDataURL(type, 0.82));
    };
    img.onerror = reject;
    img.src = url;
  });
}
async function handleAvatarPick(file) {
  if (!file) return;
  if (!/^image\/(png|jpe?g|webp)$/.test(file.type)) { toast('请选择图片文件'); return; }
  if (file.size > 5 * 1024 * 1024) { toast('图片太大，请选 5MB 以内的'); return; }
  try {
    const dataUrl = await compressAvatar(file);
    if (dataUrl.length > 280000) { toast('图片仍过大，请换一张'); return; }
    await HealthAPI.updateAvatar(dataUrl);
    toast('头像已更新');
    const p = await HealthAPI.getProfile();
    renderProfile(p);
  } catch (e) {
    toast('头像上传失败：' + (e.message || '网络异常'));
  }
}
$('#avatar-input').addEventListener('change', e => {
  handleAvatarPick(e.target.files[0]);
  e.target.value = '';
});

/* ---------- 编辑资料弹层：改名/换头像/退出登录 ---------- */
function updatePeAvatar(p) {
  const el = $('#pe-avatar'); if (!el) return;
  el.innerHTML = '';
  if (p.avatarData) {
    const img = document.createElement('img');
    img.src = p.avatarData;
    el.appendChild(img);
  } else {
    el.textContent = p.avatarText || (p.nickname || '').slice(0, 1) || '食';
  }
}
function openProfileEdit() {
  const p = state.profileData; if (!p) return;
  $('#pe-nickname').value = p.nickname || '';
  $('#pe-signature').value = p.signature || '';
  updatePeAvatar(p);
  $('#pe-mask').classList.add('show');
  $('#pe-sheet').classList.add('show');
}
function closeProfileEdit() {
  $('#pe-mask').classList.remove('show');
  $('#pe-sheet').classList.remove('show');
}
$('#profile-head').addEventListener('click', openProfileEdit);
$('#pe-close').addEventListener('click', closeProfileEdit);
$('#pe-mask').addEventListener('click', closeProfileEdit);
$('#pe-change-avatar').addEventListener('click', () => $('#avatar-input').click());
$('#pe-save').addEventListener('click', async () => {
  const nickname = $('#pe-nickname').value.trim();
  const signature = $('#pe-signature').value.trim();
  if (!nickname) { toast('昵称不能为空'); return; }
  try {
    await HealthAPI.updateProfile({ nickname, signature });
    const p = await HealthAPI.getProfile();
    state.profileData = p;
    renderProfile(p);
    closeProfileEdit();
    toast('资料已保存');
  } catch (e) {
    toast('保存失败：' + (e.message || '网络异常'));
  }
});
$('#pe-logout').addEventListener('click', () => { HealthAPI.logout(); location.reload(); });

/* ---------- 自定义食物：名称+份量(单位)+餐次+三素+图片入库，可选记入本餐 ---------- */
let cfImageData = '';   // 压缩后的 dataURL，空串=无图
let cfKcalManual = false;   // 用户手改热量后，不再被三素自动计算覆盖
let cfUnit = 'g';       // 份量单位：g（克）| ml（毫升）
let cfMeal = 'lunch';   // 餐次类别：breakfast=早餐 / lunch=正餐(午+晚) / snack=零食
/* 表单三档类别 → 内置 meals 语义（搜索按 meals 过滤；无 meals 的旧数据视为全餐次可见） */
const CF_MEAL_MAP = { breakfast: ['breakfast'], lunch: ['lunch', 'dinner'], snack: ['snack'] };
/* 反查类别（管理列表高亮用），未归类返回空串 */
function cfMealKind(meals) {
  if (!Array.isArray(meals) || !meals.length) return '';
  const s = meals.join(',');
  if (s === 'breakfast') return 'breakfast';
  if (s === 'snack') return 'snack';
  if (meals.indexOf('lunch') > -1 || meals.indexOf('dinner') > -1) return 'lunch';
  return '';
}
function cfUnitOf(f) { return f && f.unit === 'ml' ? 'ml' : 'g'; }
function setCfUnit(u) {
  cfUnit = u === 'ml' ? 'ml' : 'g';
  $$('#cf-unit button').forEach(b => b.classList.toggle('active', b.dataset.unit === cfUnit));
}
function setCfMeal(m) {
  cfMeal = CF_MEAL_MAP[m] ? m : 'lunch';
  $$('#cf-meal button').forEach(b => b.classList.toggle('active', b.dataset.meal === cfMeal));
}
function cfAutoKcal() {
  if (cfKcalManual) return;
  const p = Number($('#cf-protein').value) || 0;
  const c = Number($('#cf-carb').value) || 0;
  const f = Number($('#cf-fat').value) || 0;
  if (!p && !c && !f) return;   // 三素未填时不动热量（允许只按包装标签填热量）
  $('#cf-kcal').value = Math.round(p * 4 + c * 4 + f * 9);
}
function renderCfPreview() {
  const el = $('#cf-img-preview');
  el.innerHTML = cfImageData ? `<img src="${cfImageData}" alt="">` : '🍽️';
}
function openCustomFoodSheet(fromLib) {
  $('#cf-name').value = state.sheetKeyword || '';
  $('#cf-grams').value = '';
  $('#cf-protein').value = '';
  $('#cf-carb').value = '';
  $('#cf-fat').value = '';
  $('#cf-kcal').value = '';
  cfKcalManual = false;
  cfImageData = '';
  setCfUnit('g');   // 单位默认克
  // 餐次默认跟随当前记一笔的餐次（午餐/晚餐都归「正餐」档）
  setCfMeal(state.mealChosen === 'breakfast' ? 'breakfast' : state.mealChosen === 'snack' ? 'snack' : 'lunch');
  renderCfPreview();
  $('#cf-save-add').textContent = fromLib ? '存入食物库' : `保存并记入${MEAL_NAMES[state.mealChosen] || '本餐'}`;
  $('#cf-save-only').style.display = fromLib ? 'none' : '';   // 从食物库进入只剩入库主按钮
  $('#cf-mask').classList.add('show');
  $('#cf-sheet').classList.add('show');
}
function closeCustomFoodSheet() {
  $('#cf-mask').classList.remove('show');
  $('#cf-sheet').classList.remove('show');
}
async function saveCustomFood(andAdd) {
  const name = $('#cf-name').value.trim();
  const kcal = Number($('#cf-kcal').value);
  const grams = Number($('#cf-grams').value) || 0;
  const protein = Number($('#cf-protein').value) || 0;
  const carb = Number($('#cf-carb').value) || 0;
  const fat = Number($('#cf-fat').value) || 0;
  const portion = grams ? `${grams}${cfUnit}` : '1 份';
  const meals = CF_MEAL_MAP[cfMeal] || [];
  if (!name) { toast('请填写食物名称'); return; }
  if (!kcal || kcal <= 0) { toast('请填热量，或先填三大营养素自动算'); return; }
  try {
    await HealthAPI.addCustomFood({ name, kcal, grams, unit: cfUnit, meals, protein, carb, fat, portion, image: cfImageData });
    closeCustomFoodSheet();
    if (andAdd) {
      await HealthAPI.addFoodRecord({ date: state.date, meal: state.mealChosen, name, portion, kcal, emoji: '🍽️', image: cfImageData, protein, carb, fat });
      closeSheet();
      await refreshToday();
      await loadRecordPage();
      toast(`已记入${MEAL_NAMES[state.mealChosen]} · ${name}`);
    } else {
      toast('已存入食物库，搜索可用');
      fillSheetResults(state.sheetKeyword || '');
    }
  } catch (e) {
    toast('保存失败：' + (e.message || '网络异常'));
  }
}
$('#cf-img-pick').addEventListener('click', () => $('#cf-img-input').click());
$('#cf-img-input').addEventListener('change', async e => {
  const file = e.target.files[0];
  e.target.value = '';
  if (!file) return;
  if (!/^image\/(png|jpe?g|webp)$/.test(file.type)) { toast('请选择图片文件'); return; }
  if (file.size > 5 * 1024 * 1024) { toast('图片太大，请选 5MB 以内的'); return; }
  try {
    const dataUrl = await compressAvatar(file);   // 复用头像压缩链路（200px 级 jpeg/png）
    if (dataUrl.length > 280000) { toast('图片仍过大，请换一张'); return; }
    cfImageData = dataUrl;
    renderCfPreview();
  } catch (err) {
    toast('图片处理失败');
  }
});
$('#cf-close').addEventListener('click', closeCustomFoodSheet);
$('#cf-mask').addEventListener('click', closeCustomFoodSheet);
$('#sheet-cf-open').addEventListener('click', () => openCustomFoodSheet());   // 记一笔弹层常驻入口
$('#cf-save-add').addEventListener('click', () => saveCustomFood(true));
$('#cf-save-only').addEventListener('click', () => saveCustomFood(false));
/* 三素输入 → 自动算热量；用户手改热量后不再覆盖 */
['#cf-protein', '#cf-carb', '#cf-fat'].forEach(sel => {
  $(sel).addEventListener('input', cfAutoKcal);
  $(sel).addEventListener('change', cfAutoKcal);
});
$('#cf-kcal').addEventListener('input', () => { cfKcalManual = true; });
/* 份量单位（克/毫升）与餐次类别（早/正餐/零食）选择 */
$('#cf-unit').addEventListener('click', e => { const b = e.target.closest('button[data-unit]'); if (b) setCfUnit(b.dataset.unit); });
$('#cf-meal').addEventListener('click', e => { const b = e.target.closest('button[data-meal]'); if (b) setCfMeal(b.dataset.meal); });

/* ---------- 我的食物库：自定义食物管理 + 内置常菜移除/恢复 ---------- */
let libTab = 'custom';
let libBuiltinCache = null;   // 内置库（含 hidden 标记）缓存

function openFoodLib() {
  libTab = 'custom';
  $$('#lib-seg button').forEach(b => b.classList.toggle('active', b.dataset.lib === 'custom'));
  $('#lib-mask').classList.add('show');
  $('#lib-sheet').classList.add('show');
  renderLibList();
}
function closeFoodLib() {
  $('#lib-mask').classList.remove('show');
  $('#lib-sheet').classList.remove('show');
}
async function renderLibList() {
  const box = $('#lib-list');
  box.innerHTML = '<div class="empty"><div class="art"></div><p>加载中…</p></div>';
  try {
    if (libTab === 'custom') {
      const list = await HealthAPI.listCustomFoods();
      const subEl = $('#foodlib-sub'); if (subEl) subEl.textContent = `自定义 ${list.length} 条 · 点餐次标签可改归类`;
      box.innerHTML = list.length ? list.map(f => `
        <div class="food-item">
          <span class="thumb">${f.image ? `<img class="thumb-img" src="${f.image}" alt="">` : (f.emoji || '🍽️')}</span>
          <span class="info">
            <span class="name">${f.name}</span>
            <span class="meta" style="display:block">${f.grams ? f.grams + cfUnitOf(f) + ' · ' : ''}${f.kcal} kcal · 蛋白 ${f.protein}g / 碳水 ${f.carb}g / 脂肪 ${f.fat}g</span>
            <span class="cf-lib-meals">${['breakfast', 'lunch', 'snack'].map(v => `<button class="cf-meal-chip ${cfMealKind(f.meals) === v ? 'active' : ''}" data-set-cf-meal="${v}" data-cf-id="${f.id}">${v === 'breakfast' ? '早餐' : v === 'lunch' ? '正餐' : '零食'}</button>`).join('')}</span>
          </span>
          <span class="lib-item-actions"><button class="lib-act danger" data-del-cf="${f.id}">删除</button></span>
        </div>`).join('')
        : `<div class="empty"><div class="art">🍽️</div><p>还没有自定义食物<br>点下方按钮添加你的常吃菜</p></div>`;
    } else {
      const list = libBuiltinCache || (libBuiltinCache = await HealthAPI.getBuiltinFoods());
      const hiddenCount = list.filter(f => f.hidden).length;
      const subEl2 = $('#foodlib-sub'); if (subEl2) subEl2.textContent = `内置 ${list.length} 条 · 已移除 ${hiddenCount}`;
      box.innerHTML = list.map(f => `
        <div class="food-item ${f.hidden ? 'lib-item-removed' : ''}">
          <span class="thumb">${f.image ? `<img class="thumb-img" src="${f.image}" alt="">` : f.emoji}</span>
          <span class="info">
            <span class="name">${f.name}</span>
            <span class="meta" style="display:block">${f.meta} · ${f.kcal} kcal</span>
          </span>
          <span class="lib-item-actions">
            <button class="lib-act ${f.hidden ? 'restore' : 'danger'}" data-toggle-builtin="${f.id}">${f.hidden ? '恢复' : '移除'}</button>
          </span>
        </div>`).join('');
    }
  } catch (e) {
    box.innerHTML = `<div class="empty"><div class="art">⚠️</div><p>加载失败：${e.message || '网络异常'}</p>
      <button class="btn btn-soft" id="lib-retry" style="margin-top:var(--sp-3)">重试</button></div>`;
  }
}
const foodlibOpenBtn = $('#foodlib-open');   // 我的页入口（已移至记录页，保留兼容）
if (foodlibOpenBtn) foodlibOpenBtn.addEventListener('click', openFoodLib);
$('#btn-foodlib').addEventListener('click', openFoodLib);   // 记录页：与「记一笔」并排
$('#lib-close').addEventListener('click', closeFoodLib);
$('#lib-mask').addEventListener('click', closeFoodLib);
$('#lib-add').addEventListener('click', () => { closeFoodLib(); openCustomFoodSheet(true); });
$('#lib-seg').addEventListener('click', e => {
  const b = e.target.closest('button'); if (!b) return;
  libTab = b.dataset.lib;
  $$('#lib-seg button').forEach(x => x.classList.toggle('active', x === b));
  renderLibList();
});
$('#lib-list').addEventListener('click', async e => {
  if (e.target.closest('#lib-retry')) { renderLibList(); return; }
  const mealChip = e.target.closest('[data-set-cf-meal]');
  if (mealChip) {
    const kind = mealChip.dataset.setCfMeal;
    mealChip.disabled = true;
    try {
      await HealthAPI.setCustomFoodMeals(mealChip.dataset.cfId, CF_MEAL_MAP[kind] || []);
      toast(`已归到${kind === 'breakfast' ? '早餐' : kind === 'snack' ? '零食' : '正餐'} · 搜索时只在对应餐次出现`);
      renderLibList();
    } catch (err) { toast('设置失败：' + (err.message || '网络异常')); mealChip.disabled = false; }
    return;
  }
  const del = e.target.closest('[data-del-cf]');
  if (del) {
    const ok = await showConfirm('删除自定义食物', '删除后不可恢复；已记录的饮食不受影响。');
    if (!ok) return;
    del.disabled = true;
    try {
      await HealthAPI.deleteCustomFood(del.dataset.delCf);
      toast('已删除');
      renderLibList();
    } catch (err) { toast('删除失败：' + (err.message || '网络异常')); del.disabled = false; }
    return;
  }
  const tog = e.target.closest('[data-toggle-builtin]');
  if (tog) {
    const id = tog.dataset.toggleBuiltin;
    const list = libBuiltinCache || [];
    const item = list.find(f => f.id === id);
    if (!item) return;
    const ids = list.filter(f => f.hidden).map(f => f.id);
    if (item.hidden) {
      const i = ids.indexOf(id); if (i > -1) ids.splice(i, 1);
    } else if (ids.indexOf(id) === -1) ids.push(id);
    tog.disabled = true;
    try {
      await HealthAPI.setHiddenFoods(ids);
      item.hidden = !item.hidden;
      renderLibList();
      toast(item.hidden ? `已移除「${item.name}」` : `已恢复「${item.name}」`);
    } catch (err) { toast('操作失败：' + (err.message || '网络异常')); tog.disabled = false; }
    return;
  }
});

/* ============================================================
 * 今日未打卡提醒（当日无任何记录时打开 App 弹一次）
 * ============================================================ */
let checkinShown = false;
function maybeShowCheckin() {
  if (checkinShown || !state.summary) return;
  const s = state.summary;
  // 有记录（热量>0 或喝了水）或不是今天，不打扰
  if (s.kcal > 0 || s.water > 0) return;
  if (state.date !== todayIso()) return;
  checkinShown = true;
  $('#checkin-mask').classList.add('show');
  $('#checkin-sheet').classList.add('show');
}
function closeCheckin() {
  $('#checkin-mask').classList.remove('show');
  $('#checkin-sheet').classList.remove('show');
}
$('#checkin-go').addEventListener('click', () => { closeCheckin(); switchScreen('record'); });
$('#checkin-later').addEventListener('click', closeCheckin);
$('#checkin-mask').addEventListener('click', closeCheckin);

/* ============================================================
 * 目标编辑弹层
 * ============================================================ */
const WEIGHT_STEP = 0.5, WEIGHT_MIN = 30, WEIGHT_MAX = 150;

function openGoalEditSheet() {
  const profile = state.profileData;
  $('#weight-goal-val').value = profile?.goal?.targetWeight || 55;
  $('#goal-edit-mask').classList.add('show');
  $('#goal-edit-sheet').classList.add('show');
}
function closeGoalEditSheet() {
  $('#goal-edit-mask').classList.remove('show');
  $('#goal-edit-sheet').classList.remove('show');
}
$('#goal-edit-close').addEventListener('click', closeGoalEditSheet);
$('#goal-edit-mask').addEventListener('click', closeGoalEditSheet);

$('#weight-goal-dec').addEventListener('click', () => {
  const cur = Number($('#weight-goal-val').value);
  const next = Math.max(WEIGHT_MIN, +(cur - WEIGHT_STEP).toFixed(1));
  $('#weight-goal-val').value = next;
  if (next === cur) toast(`最小 ${WEIGHT_MIN} kg`);
});
$('#weight-goal-inc').addEventListener('click', () => {
  const cur = Number($('#weight-goal-val').value);
  const next = Math.min(WEIGHT_MAX, +(cur + WEIGHT_STEP).toFixed(1));
  $('#weight-goal-val').value = next;
  if (next === cur) toast(`最大 ${WEIGHT_MAX} kg`);
});

$('#goal-edit-save').addEventListener('click', async () => {
  const targetWeight = Number($('#weight-goal-val').value);
  try {
    await HealthAPI.setGoal({ targetWeight });
    if (state.profileData) state.profileData.goal.targetWeight = targetWeight;
    $('#goal-weight').innerHTML = `${targetWeight} <small>kg</small>`;
    renderMetab();   // 达标时间依赖目标体重
    closeGoalEditSheet();
    toast('目标体重已更新');
  } catch (e) {
    toast('保存失败：' + (e.message || '网络异常'));
  }
});

/* ============================================================
 * 身体档案 + 代谢计算（BMR/TDEE/建议摄入/达标时间）
 * ------------------------------------------------------------
 * 公式与常量（ACTIVITY/KCAL_PER_KG/BODY_DEFAULT/computeMetabolism）已移至 logic.js，
 * 本文件只保留 localStorage 缓存与渲染/保存副作用。
 * ============================================================ */

/* 身体档案本地缓存：按 uid 隔离（同设备换账号不串），带时间戳与云端比"谁新用谁" */
const BODY_LOCAL_PREFIX = 'sg_body_';        // 值键：sg_body_<uid>；时间戳键：sg_body_ts_<uid>
const BODY_LOCAL_LEGACY = 'sg_body_local';   // 旧版单键（无 uid），首次读取时迁移给当前账号
function bodyLocalKey(uid) { return BODY_LOCAL_PREFIX + (uid || 'anon'); }
function bodyTsKey(uid) { return BODY_LOCAL_PREFIX + 'ts_' + (uid || 'anon'); }
function currentUid() { return (state.profileData && state.profileData.id) || ''; }
function loadBodyLocal(uid) {
  try {
    const k = bodyLocalKey(uid);
    let raw = localStorage.getItem(k);
    if (!raw && uid) {   // 旧版单键迁移：设备上通常只有一个使用者，归属当前登录账号
      const legacy = localStorage.getItem(BODY_LOCAL_LEGACY);
      if (legacy) { localStorage.setItem(k, legacy); localStorage.removeItem(BODY_LOCAL_LEGACY); raw = legacy; }
    }
    return raw ? (JSON.parse(raw) || {}) : {};
  } catch (e) { return {}; }
}
function loadBodyTs(uid) { return Number(localStorage.getItem(bodyTsKey(uid))) || 0; }
function saveBodyLocal(uid, b, ts) {
  localStorage.setItem(bodyLocalKey(uid), JSON.stringify(b));
  localStorage.setItem(bodyTsKey(uid), String(ts || Date.now()));
}
/* 本地有值且不旧于云端才用它：离线改的档案不被云端旧值盖掉，云端更新后又能覆盖本地旧值 */
function effectiveBody(cloudBody, uid, cloudTs) {
  const local = loadBodyLocal(uid);
  const useLocal = Object.keys(local).length > 0 && loadBodyTs(uid) >= (Number(cloudTs) || 0);
  return Object.assign({}, BODY_DEFAULT, cloudBody || {}, useLocal ? local : {});
}

/* computeMetabolism 已移至 logic.js（纯函数，可单测），此处直接 import */

/* ============================================================
 * 反馈3：达标时间按“实际缺口”每日更新
 * ------------------------------------------------------------
 * 预设缺口只是建议；真实减重速度取决于每天实际摄入/运动。
 * 缓存“过去 6 天”的摄入/运动（每天早上重拉一次），今天的数据用内存 state 实时算，
 * 实际日均缺口 = mean(TDEE + 运动 − 摄入)，仅统计有记录的日子（≥2 天才生效）。 */
const ACTUAL_DEFICIT_PREFIX = 'sg_actual_deficit_';
function actualDeficitKey(uid) { return ACTUAL_DEFICIT_PREFIX + (uid || 'anon'); }
function loadActualDeficitCache(uid) {
  try { return JSON.parse(localStorage.getItem(actualDeficitKey(uid))) || null; } catch (e) { return null; }
}
function saveActualDeficitCache(uid, v) {
  try { localStorage.setItem(actualDeficitKey(uid), JSON.stringify(v)); } catch (e) { /* 忽略 */ }
}
/* 拉取过去 6 天（昨天..6 天前）的摄入/运动，缓存为历史基准 */
async function fetchDeficitHistory() {
  const b = state.body; if (!b) return null;
  const tw = state.profileData ? state.profileData.goal.targetWeight : 55;
  const tdee = computeMetabolism(b, tw).tdee;
  const dates = [];
  for (let i = 1; i <= 6; i++) {   // 不含今天（今天用 state 实时算）
    const d = new Date(); d.setDate(d.getDate() - i);
    dates.push(localIso(d));
  }
  const [sums, exs] = await Promise.all([
    Promise.all(dates.map(dt => HealthAPI.getDailySummary(dt).catch(() => null))),
    Promise.all(dates.map(dt => HealthAPI.getExercises(dt).catch(() => []))),
  ]);
  const history = [];
  for (let i = 0; i < dates.length; i++) {
    const s = sums[i];
    if (!s || !(s.kcal > 0)) continue;   // 未记录的日子不计入
    const exKcal = (exs[i] || []).reduce((a, r) => a + (r.kcal || 0), 0);
    history.push({ date: dates[i], intake: s.kcal, exKcal });
  }
  return { date: todayIso(), tdee, history };
}
/* 合并历史 + 今天实时数据，算实际日均缺口；纯均值计算委托 logic.avgDeficitFromRows */
function computeAvgDeficit(cache) {
  if (!cache || !cache.history) return null;
  const rows = cache.history.slice();
  // 今天：用内存 state 实时值（记录/运动一变就跟着变）
  const todayIntake = (state.summary && state.summary.kcal) || 0;
  if (todayIntake > 0) rows.push({ date: todayIso(), intake: todayIntake, exKcal: state.exerciseKcal || 0 });
  return avgDeficitFromRows(cache.tdee, rows);
}
/* 每天早上首次加载重拉历史并缓存；force=true 跳过日期检查 */
async function refreshActualDeficit(force) {
  const uid = currentUid();
  const today = todayIso();
  let cache = loadActualDeficitCache(uid);
  if (force || !cache || cache.date !== today) {
    try {
      const fresh = await fetchDeficitHistory();
      if (fresh) { cache = fresh; saveActualDeficitCache(uid, cache); }
    } catch (e) { /* 网络异常时沿用旧缓存 */ }
  }
  state.actualDeficit = computeAvgDeficit(cache);
  return state.actualDeficit;
}
/* 今天记录/运动变化后：不重拉历史，仅用缓存 + 实时 state 重算均值（轻量、即时） */
function recomputeActualDeficitLive() {
  const cache = loadActualDeficitCache(currentUid());
  state.actualDeficit = computeAvgDeficit(cache);
}

function renderBodyCard() {
  const b = state.body; if (!b) return;
  $('#body-height').innerHTML = `${b.heightCm}<small> cm</small>`;
  $('#body-weight').innerHTML = `${b.weightKg}<small> kg</small>`;
  $('#body-bmi').textContent = Number(b.bmi).toFixed(1);
  $('#body-age').innerHTML = `${b.age}<small> 岁</small>`;
  $('#body-gender').textContent = b.gender === 'male' ? '男' : '女';
  $('#body-activity').textContent = (ACTIVITY[b.activity] || ACTIVITY.light).label;
}

function renderMetab() {
  const b = state.body; if (!b) return;
  const tw = state.profileData ? state.profileData.goal.targetWeight : 55;
  const m = computeMetabolism(b, tw, state.actualDeficit);   // 反馈3：传入近 7 天实际缺口
  state.metab = m;
  const ex = state.exerciseKcal || 0;
  $('#metab-bmr').innerHTML = `${m.bmr}<small> kcal</small>`;
  $('#metab-tdee').innerHTML = `${m.tdee + ex}<small> kcal</small>`;
  $('#metab-exercise').innerHTML = `${ex}<small> kcal</small>`;
  // 今日建议摄入 = 基准目标 + 今日运动（与首页环额度同源）；基准目标同步云端不随运动波动
  $('#metab-suggest').innerHTML = `${m.suggest + ex}<small> kcal</small>`;
  // 每日缺口：有足够历史时显示“实际日均缺口”，否则显示预设缺口
  $('#metab-deficit').innerHTML = `${m.effDeficit}<small> kcal</small>`;
  // 公式标注：每个数字下方写出它的算法——本卡同屏存在“含运动/不含运动/历史均值”三套口径，
  // 标注后可直接对照，不必反推（营养与展示口径说明见下方 nutrient-note）
  const af = (ACTIVITY[b.activity] || ACTIVITY.light).f;
  const setF = (id, t) => { const el = $(id); if (el) el.textContent = t; };
  setF('#metab-bmr-f', `10×${b.weightKg}+6.25×${b.heightCm}−5×${b.age}${b.gender === 'male' ? '+5' : '−161'}`);
  setF('#metab-tdee-f', `BMR×系数${af}${ex > 0 ? `＋今日运动${ex}` : ''}`);
  setF('#metab-suggest-f', `消耗${m.tdee}−缺口${m.realDeficit}${ex > 0 ? `＋运动${ex}` : ''}`);
  setF('#metab-deficit-f', m.useActual ? `近${state.actualDeficit.days}天均值(消耗−摄入)` : `预设缺口 ${m.realDeficit}`);
  setF('#metab-exercise-f', '今日运动记录累计');
  $('#metab-note').textContent = m.useActual
    ? `缺口为近 ${state.actualDeficit.days} 天实际日均 · 预设 ${m.realDeficit}`
    : (ex > 0 ? `含今日运动 ${ex} kcal · 基准 ${m.suggest}` : `基准目标 ${m.suggest} kcal`);
  $('#metab-eta').innerHTML =
    `<span style="display:block">${m.etaText}</span>` +
    `<span style="display:block;margin-top:4px;opacity:.85">${m.rangeText}</span>`;
}

/* ---------- 身体档案编辑弹层 ---------- */
function openBodySheet() {
  const b = state.body; if (!b) return;
  $('#height-val').value = b.heightCm;
  $('#weight-val').value = b.weightKg;
  $('#age-val').value = b.age;
  $$('#gender-seg button').forEach(x => x.classList.toggle('active', x.dataset.gender === b.gender));
  $$('#activity-chips .chip').forEach(x => x.classList.toggle('active', x.dataset.activity === b.activity));
  $$('#deficit-seg button').forEach(x => x.classList.toggle('active', Number(x.dataset.deficit) === Number(b.deficit)));
  $('#body-mask').classList.add('show');
  $('#body-sheet').classList.add('show');
}
function closeBodySheet() {
  $('#body-mask').classList.remove('show');
  $('#body-sheet').classList.remove('show');
}
function bumpBodyVal(sel, delta, min, max, fixed) {
  const el = $(sel);
  const cur = Number(el.value);
  let next = Math.min(max, Math.max(min, cur + delta));
  if (fixed != null) next = +next.toFixed(fixed);
  el.value = next;
  if (next === cur) toast(delta > 0 ? '已到上限' : '已到下限');
}
/* 直接输入归一化：失焦/回车时收拢到合法范围并定小数位（反馈7：体重可输 78.3） */
function bindStepperNorm(sel, min, max, fixed, after) {
  const el = $(sel);
  const norm = () => {
    let v = parseFloat(el.value);
    if (isNaN(v)) v = min;
    v = Math.min(max, Math.max(min, v));
    v = fixed != null ? +v.toFixed(fixed) : Math.round(v);
    el.value = v;
    if (after) after(v);
  };
  el.addEventListener('change', norm);
  el.addEventListener('blur', norm);
}
bindStepperNorm('#height-val', 100, 250, 0);
bindStepperNorm('#weight-val', 30, 200, 2);
bindStepperNorm('#age-val', 10, 100, 0);
bindStepperNorm('#weight-goal-val', WEIGHT_MIN, WEIGHT_MAX, 1);
bindStepperNorm('#water-goal-val', WATER_GOAL_MIN, WATER_GOAL_MAX, null, v => {
  $('#water-goal-val').value = Math.round(v / WATER_CUP_ML) * WATER_CUP_ML;   // 喝水目标对齐 200ml 整数倍
});
bindStepperNorm('#exercise-amount-val', 0.5, 300, 1, () => updateExercisePreview());
$('#exercise-amount-val').addEventListener('input', updateExercisePreview);
$('#body-card').addEventListener('click', openBodySheet);
$('#body-sheet-close').addEventListener('click', closeBodySheet);
$('#body-mask').addEventListener('click', closeBodySheet);
$('#height-dec').addEventListener('click', () => bumpBodyVal('#height-val', -1, 100, 250));
$('#height-inc').addEventListener('click', () => bumpBodyVal('#height-val', 1, 100, 250));
$('#weight-dec').addEventListener('click', () => bumpBodyVal('#weight-val', -0.5, 30, 200, 1));
$('#weight-inc').addEventListener('click', () => bumpBodyVal('#weight-val', 0.5, 30, 200, 1));
$('#age-dec').addEventListener('click', () => bumpBodyVal('#age-val', -1, 10, 100));
$('#age-inc').addEventListener('click', () => bumpBodyVal('#age-val', 1, 10, 100));
$('#gender-seg').addEventListener('click', e => {
  const b = e.target.closest('button'); if (!b) return;
  $$('#gender-seg button').forEach(x => x.classList.toggle('active', x === b));
});
$('#activity-chips').addEventListener('click', e => {
  const c = e.target.closest('.chip'); if (!c) return;
  $$('#activity-chips .chip').forEach(x => x.classList.toggle('active', x === c));
});
$('#deficit-seg').addEventListener('click', e => {
  const b = e.target.closest('button'); if (!b) return;
  $$('#deficit-seg button').forEach(x => x.classList.toggle('active', x === b));
});

$('#body-save').addEventListener('click', async () => {
  const g = $('#gender-seg .active'), a = $('#activity-chips .chip.active'), d = $('#deficit-seg .active');
  const b = {
    heightCm: Number($('#height-val').value),
    weightKg: Number($('#weight-val').value),
    age: Number($('#age-val').value),
    gender: g ? g.dataset.gender : 'female',
    activity: a ? a.dataset.activity : 'light',
    deficit: d ? Number(d.dataset.deficit) : 500,
  };
  b.bmi = +(b.weightKg / Math.pow(b.heightCm / 100, 2)).toFixed(1);
  state.body = b;
  saveBodyLocal(currentUid(), b);
  renderBodyCard();
  renderMetab();
  closeBodySheet();
  try {
    await HealthAPI.updateProfile(b);
    await syncTarget();
    toast('身体档案已保存');
  } catch (e) {
    toast('已本地保存：' + (e.message || '网络异常'));
  }
});

/* 每日热量目标 = 系统建议值：档案/缺口/登录就绪时自动同步云端，用户无需手填 */
async function syncTarget() {
  if (!state.body || !state.summary) return;
  const tw = state.profileData ? state.profileData.goal.targetWeight : 55;
  const suggest = computeMetabolism(state.body, tw).suggest;
  if (state.summary.target === suggest) return;
  state.summary.target = suggest;
  renderRing();
  $('#goal-kcal').innerHTML = `${suggest} <small>kcal</small>`;
  try {
    await HealthAPI.setGoal({ dailyKcal: suggest, targetWeight: tw });
    if (state.profileData) state.profileData.goal.dailyKcal = suggest;
  } catch (e) { /* 云端同步失败本地已生效，下次加载再同步 */ }
}

/* ============================================================
 * 今日运动：刻意运动单独记录，消耗计入当日报销额度
 * ------------------------------------------------------------
 * 运动库与消耗公式（EXERCISE_LIB/exerciseKcalOf）已移至 logic.js，此处直接 import。
 * ============================================================ */
const currentLib = () => EXERCISE_LIB.find(l => l.key === state.exerciseChosen) || EXERCISE_LIB[0];

async function loadExercises() {
  try {
    state.exercises = await HealthAPI.getExercises(state.date);
  } catch (e) {
    state.exercises = [];   // 后端/集合未就绪时降级为空，不阻断主流程
  }
  state.exerciseKcal = state.exercises.reduce((a, r) => a + (r.kcal || 0), 0);
  renderExerciseList();
  renderRing();
  renderMetab();
}

function renderExerciseList() {
  const et = $('#exercise-title');
  if (et) et.textContent = state.date === todayIso() ? '今日运动' : `运动 · ${dateLabelOf(state.date)}`;
  $('#exercise-total').textContent = `消耗 ${state.exerciseKcal} kcal`;
  $('#exercise-list').innerHTML = state.exercises.length ? state.exercises.map(r => `
    <div class="food-item">
      <span class="thumb">${r.emoji}</span>
      <span class="info">
        <span class="name">${r.name}</span>
        <span class="meta" style="display:block">${isRepRecord(r) ? r.amount + ' ' + (EXERCISE_LIB.find(l => l.key === r.key).repUnit) : r.amount + (r.unit === 'km' ? ' km' : ' 分钟')}</span>
      </span>
      <span class="kcal">-${r.kcal}<small> kcal</small></span>
      <button class="del" data-xdel="${r.id}" aria-label="删除${r.name}">✕</button>
    </div>`).join('')
  : '<p class="empty">今天还没运动，点下方「记运动」</p>';
}

/* ---------- 运动记录弹层 ---------- */
function fillExerciseChips() {
  $('#exercise-chips').innerHTML = EXERCISE_LIB.map(l =>
    `<button class="ex-chip ${l.key === state.exerciseChosen ? 'active' : ''}" data-xkey="${l.key}"><span class="emoji">${l.emoji}</span><span class="ex-name">${l.name}</span></button>`).join('');
}
function updateExercisePreview() {
  const lib = currentLib();
  const lab = exerciseAmountLabel(lib);
  $('#exercise-amount-label').textContent = lab.name;
  $('#exercise-amount-unit').textContent = lab.unit;
  const w = state.body ? state.body.weightKg : 55;
  $('#exercise-kcal-preview').innerHTML =
    `预计消耗 <b>${exerciseKcalOf(lib, Number($('#exercise-amount-val').value), w)}</b> kcal`;
}
function openExerciseSheet() {
  fillExerciseChips();
  $('#exercise-amount-val').value = state.exerciseAmount;
  updateExercisePreview();
  $('#exercise-mask').classList.add('show');
  $('#exercise-sheet').classList.add('show');
}
function closeExerciseSheet() {
  $('#exercise-mask').classList.remove('show');
  $('#exercise-sheet').classList.remove('show');
}
$('#btn-add-exercise').addEventListener('click', openExerciseSheet);
$('#exercise-sheet-close').addEventListener('click', closeExerciseSheet);
$('#exercise-mask').addEventListener('click', closeExerciseSheet);
$('#exercise-chips').addEventListener('click', e => {
  const c = e.target.closest('[data-xkey]'); if (!c) return;
  state.exerciseChosen = c.dataset.xkey;
  state.exerciseAmount = currentLib().unit === 'km' ? 5 : currentLib().unit === 'rep' ? 10 : 20;
  fillExerciseChips();
  $('#exercise-amount-val').value = state.exerciseAmount;
  updateExercisePreview();
});
$('#exercise-amount-dec').addEventListener('click', () => {
  const lib = currentLib();
  const step = lib.unit === 'km' ? 0.5 : 5;
  state.exerciseAmount = Math.max(step, +((Number($('#exercise-amount-val').value) || step) - step).toFixed(1));
  $('#exercise-amount-val').value = state.exerciseAmount;
  updateExercisePreview();
});
$('#exercise-amount-inc').addEventListener('click', () => {
  const lib = currentLib();
  const step = lib.unit === 'km' ? 0.5 : 5;
  const max = lib.unit === 'km' ? 100 : lib.unit === 'rep' ? 2000 : 300;
  state.exerciseAmount = Math.min(max, +((Number($('#exercise-amount-val').value) || 0) + step).toFixed(1));
  $('#exercise-amount-val').value = state.exerciseAmount;
  updateExercisePreview();
});
$('#exercise-save').addEventListener('click', async () => {
  const lib = currentLib();
  state.exerciseAmount = Number($('#exercise-amount-val').value) || state.exerciseAmount;   // 以输入框为准
  const w = state.body ? state.body.weightKg : 55;
  const kcal = exerciseKcalOf(lib, state.exerciseAmount, w);
  if (!kcal) { toast('请先设置运动量'); return; }
  const temp = { id: 'tmpx_' + Date.now(), key: lib.key, name: lib.name, emoji: lib.emoji, amount: state.exerciseAmount, unit: lib.unit, kcal, createdAt: Date.now() };
  updateState(s => { s.exercises.push(temp); s.exerciseKcal += kcal; }, 'exercise.add');   // 乐观更新（反馈8）
  renderExerciseList();
  renderRing();
  renderMetab();
  closeExerciseSheet();
  toast(`已记录${lib.name} · 消耗 ${kcal} kcal`);
  HealthAPI.addExercise({
    date: state.date, key: lib.key, name: lib.name, emoji: lib.emoji,
    amount: state.exerciseAmount, unit: lib.unit, kcal,
  }).then(() => loadExercises()).catch(err => {
    updateState(s => { s.exercises = s.exercises.filter(r => r.id !== temp.id); s.exerciseKcal -= kcal; }, 'exercise.add.rollback');
    renderExerciseList();
    renderRing();
    renderMetab();
    toast('记录失败：' + (err.message || '网络异常'));
  });
});
async function deleteExerciseById(id) {
  if ($('#confirm-sheet').classList.contains('show')) return;   // 防长按+click 双触发
  const ok = await showConfirm('确认删除', '删除后无法恢复，确定要删除这条运动吗？');
  if (!ok) return;
  const rec = state.exercises.find(r => r.id === id);
  if (rec) {   // 乐观删除
    updateState(s => { s.exercises = s.exercises.filter(r => r.id !== id); s.exerciseKcal -= rec.kcal || 0; }, 'exercise.del');
    renderExerciseList();
    renderRing();
    renderMetab();
  }
  toast('已删除运动记录');
  HealthAPI.deleteExercise(id).then(() => loadExercises()).catch(err => {
    if (rec) {
      updateState(s => { s.exercises.push(rec); s.exerciseKcal += rec.kcal || 0; }, 'exercise.del.rollback');
      renderExerciseList();
      renderRing();
      renderMetab();
    }
    toast('删除失败：' + (err.message || '网络异常'));
  });
}
$('#exercise-list').addEventListener('click', e => {
  const btn = e.target.closest('[data-xdel]');
  if (btn) deleteExerciseById(btn.dataset.xdel);
});
/* 长按记录/运动项：震动反馈 + 上下文菜单（原为直接删除） */
if (window.AlloyFinger) {
  new AlloyFinger($('#record-lists'), {
    longTap: evt => {
      const item = evt.target.closest('.food-item');          // 长按整项任意位置即可（不要求按在删除按钮上）
      const b = item && item.querySelector('[data-del]');
      if (!b) return;
      buzz(22);
      const p = (evt.touches && evt.touches[0]) || evt;
      showCtxMenu(p.clientX || 180, p.clientY || 420, () => deleteRecordById(b.dataset.del));
    },
  });
  new AlloyFinger($('#exercise-list'), {
    longTap: evt => {
      const item = evt.target.closest('.food-item');
      const b = item && item.querySelector('[data-xdel]');
      if (!b) return;
      buzz(22);
      const p = (evt.touches && evt.touches[0]) || evt;
      showCtxMenu(p.clientX || 180, p.clientY || 420, () => deleteExerciseById(b.dataset.xdel));
    },
  });
}

/* ============================================================
 * 登录 / 注册（未登录时整体门控，登录后进入主界面）
 * ============================================================ */
function showLogin() {
  $('#screen-login').classList.add('show');
  $$('.tab').forEach(t => t.classList.remove('active'));
  $('.tabbar').style.display = 'none';   // 未登录隐藏底部导航，锁定登录页
  $('.add-row').classList.remove('show');
}
let authMode = 'login';
$$('[data-auth]').forEach(b => b.addEventListener('click', () => {
  authMode = b.dataset.auth;
  $$('[data-auth]').forEach(x => x.classList.toggle('active', x === b));
  $('#auth-submit').textContent = authMode === 'login' ? '登录' : '注册并进入';
  $('#auth-error').classList.remove('show');
}));
$('#auth-submit').addEventListener('click', async () => {
  const btn = $('#auth-submit');
  const username = $('#auth-username').value.trim();
  const password = $('#auth-password').value;
  const err = $('#auth-error');
  err.classList.remove('show');
  btn.disabled = true;
  btn.textContent = '请稍候…';
  try {
    if (authMode === 'register') await HealthAPI.registerByUsername(username, password);
    await HealthAPI.loginByUsername(username, password);
    // 平滑过渡：隐藏登录页，加载主界面数据
    $('#screen-login').classList.remove('show');
    $('.tabbar').style.display = '';
    requestAnimationFrame(updateTabGlide);
    if (mainSwiper) mainSwiper.slideTo(0, 0);
    syncChrome('home');
    renderGreeting();
    renderDateRow();
    renderPlateDate();
    await bootToday();
    await loadMainBundleSafe();
  } catch (e) {
    err.textContent = e.message || '操作失败';
    err.classList.add('show');
    btn.disabled = false;
    btn.textContent = authMode === 'login' ? '登录' : '注册并进入';
  }
});
$('#auth-password').addEventListener('keydown', e => { if (e.key === 'Enter') $('#auth-submit').click(); });

/* ============================================================
 * 初始化
 * ============================================================ */
async function refreshToday() {
  state.summary = await HealthAPI.getDailySummary(state.date);
  renderRing();
  renderWater();
  maybeShowCheckin();
}

/* 登录后主数据包：周报/体重趋势/资料；token 过期并发续期竞争可能偶发失败 → 失败自动重试一次 */
async function loadMainBundle() {
  const [report, trend, profile] = await Promise.all([
    HealthAPI.getWeekReport(), HealthAPI.getWeightTrend(), HealthAPI.getProfile(),
  ]);
  renderWeekReport(report);
  renderWeightTrend(trend);
  renderProfile(profile);
  state.profileData = profile;
  renderGreeting(profile.nickname);
  state.waterGoalMl = profile.goal.waterMl || 1600;
  renderWater();
  await syncTarget();
  // 反馈3：每天早上首次加载重拉近 6 天历史，算实际日均缺口后重渲染代谢卡（达标时间随之更新）
  await refreshActualDeficit();
  renderMetab();
}
/* 通用重试：云函数冷启动/弱网偶发失败时退避重试（反馈8：交互不能因偶发失败卡死） */
async function withRetry(fn, times = 3, delay = 2000) {
  for (let i = 0; i < times; i++) {
    try { return await fn(); } catch (e) {
      if (i === times - 1) throw e;
      await new Promise(r => setTimeout(r, delay * (i + 1)));
    }
  }
}
const bootToday = () => withRetry(() =>
  Promise.all([refreshToday(), loadExercises(), loadRecordPage()]), 3, 2000)
  .catch(e => { window.__bootErr = 'today: ' + (e && e.message || e); });
function loadMainBundleSafe() {
  return withRetry(loadMainBundle, 3, 2500)
    .catch(e => { window.__bootErr = 'bundle: ' + (e && e.message || e); });
}

(async function init() {
  initMainSwiper();
  if (!HealthAPI.isLoggedIn()) { showLogin(); return; }   // 未登录：仅显示登录页
  $('#screen-login').classList.remove('show');
  $('.tabbar').style.display = '';
  requestAnimationFrame(updateTabGlide);
  syncChrome('home');
  renderGreeting();
  const verEl = $('#app-version');
  if (verEl) verEl.textContent = `食光 v${APP_VERSION}`;
  renderDateRow();
  renderPlateDate();
  await bootToday();   // 并行拉取+退避重试，首屏快且不怕冷启动（反馈8）
  await loadMainBundleSafe();
})();

/* ============================================================
 * 手势增强（纯交互层：不改静态布局与设计令牌）
 *   A 底部抽屉 跟手拖拽 + 距离/速度判定关闭
 *   B 记录/运动项 左滑触发删除（位移跟手，松手判定）
 *   C 滚动动效 标题随滚动收缩淡出
 *   D 长按 震动反馈 + 上下文菜单（showCtxMenu 见长按绑定处）
 * ============================================================ */
let ctxMenuAction = null;
function showCtxMenu(x, y, action) {
  const m = $('#ctx-menu');
  if (!m) return;
  ctxMenuAction = action;
  m.classList.add('show');
  const phone = $('.phone');
  const pr = phone ? phone.getBoundingClientRect() : { left: 0, top: 0, width: window.innerWidth, height: window.innerHeight };
  const w = m.offsetWidth || 170, h = m.offsetHeight || 58;
  m.style.left = Math.max(8, Math.min(x - pr.left, pr.width - w - 10)) + 'px';
  m.style.top = Math.max(8, Math.min(y - pr.top, pr.height - h - 10)) + 'px';
}
function hideCtxMenu() {
  const m = $('#ctx-menu');
  if (m) m.classList.remove('show');
  ctxMenuAction = null;
}
$('#ctx-menu').addEventListener('click', e => {
  const isDelete = !!e.target.closest('[data-ctx="delete"]');
  const act = ctxMenuAction;
  hideCtxMenu();
  if (isDelete && act) act();
});
document.addEventListener('touchstart', e => { if (!e.target.closest('#ctx-menu')) hideCtxMenu(); }, { passive: true });
document.addEventListener('mousedown', e => { if (!e.target.closest('#ctx-menu')) hideCtxMenu(); });

(function initGestures() {
  const ptY = e => (e.touches && e.touches[0] ? e.touches[0].clientY : e.clientY);
  const ptX = e => (e.touches && e.touches[0] ? e.touches[0].clientX : e.clientX);

  /* ---------- A. 底部抽屉：跟手拖拽 + 距离/速度判定关闭 ---------- */
  const CLOSE_DIST = 110, CLOSE_VEL = 0.5;   // 关闭阈值：位移 px / 速度 px·ms⁻¹
  let dSheet = null, dY0 = 0, dDy = 0, dT0 = 0, dOn = false;

  function drawerDown(e) {
    const s = e.target.closest('.sheet.show');
    if (!s) return;
    if (e.target.closest('input, textarea, button, .segmented, .goal-stepper, .swiper, .bs-wrapper, #ctx-menu')) return;
    let sc = null;                            // 找到真正的滚动容器：已滚动则让位
    for (let el = e.target; el && el !== document.body; el = el.parentElement) {
      if (el.scrollHeight > el.clientHeight + 2) { sc = el; break; }
    }
    if (sc && sc.scrollTop > 2) return;
    dSheet = s; dY0 = ptY(e); dDy = 0; dT0 = Date.now(); dOn = true;
    s.style.transition = 'none';
  }
  function drawerMove(e) {
    if (!dOn) return;
    dDy = Math.max(0, ptY(e) - dY0);
    if (!dDy) return;
    dSheet.style.transform = `translateY(${dDy}px)`;
    if (e.cancelable) e.preventDefault();
  }
  function drawerUp() {
    if (!dOn) return;
    dOn = false;
    const s = dSheet, dy = dDy, v = dy / Math.max(1, Date.now() - dT0);
    dSheet = null; dDy = 0;
    if (!s) return;
    s.style.transition = ''; s.style.transform = '';
    if (dy > CLOSE_DIST || v > CLOSE_VEL) {
      const mask = s.previousElementSibling;   // 复用各弹层既有的关闭逻辑（含副作用）
      if (mask && mask.classList.contains('sheet-mask')) mask.click();
      else s.classList.remove('show');
      buzz(8);
    }
  }

  /* ---------- B. 左滑：记录/运动项位移跟手，松手判定删除 ---------- */
  const SWIPE_DIST = 64;
  let swEl = null, swX0 = 0, swY0 = 0, swDx = 0, swOn = false;

  function swipeDown(e) {
    const item = e.target.closest('#record-lists .food-item, #exercise-list .food-item');
    if (!item) return;
    swEl = item; swX0 = ptX(e); swY0 = ptY(e); swDx = 0; swOn = true;
    item.style.transition = 'none';
  }
  function swipeMove(e) {
    if (!swOn || !swEl) return;
    const dx = ptX(e) - swX0, dy = ptY(e) - swY0;
    if (dx > 0) { swDx = 0; swEl.style.transform = ''; return; }
    if (Math.abs(dx) < Math.abs(dy) * 1.2) return;            // 纵向为主：让位给页面滚动
    swDx = Math.max(-120, dx);
    swEl.style.transform = `translateX(${swDx}px)`;
    if (Math.abs(swDx) > 16) {
      e.stopPropagation();                                    // 阻断切屏手势（列表项上左滑=删除）
      if (e.cancelable) e.preventDefault();
    }
  }
  function swipeUp() {
    if (!swOn) return;
    swOn = false;
    const el = swEl, dx = swDx;
    swEl = null; swDx = 0;
    if (!el) return;
    el.style.transition = ''; el.style.transform = '';
    if (dx <= -SWIPE_DIST) {
      buzz(18);
      const b = el.querySelector('[data-del], [data-xdel]');
      if (b) {
        if (b.dataset.del) deleteRecordById(b.dataset.del);
        else if (b.dataset.xdel) deleteExerciseById(b.dataset.xdel);
      }
    }
  }

  /* ---------- C. 滚动动效：标题随滚动收缩淡出（不改变静态布局） ---------- */
  if (typeof bsMap !== 'undefined') {
    bsMap.forEach((bs, id) => {
      const screen = document.getElementById(id);
      const head = screen && screen.querySelector('.page-head, .home-head');
      if (!head) return;
      head.style.transformOrigin = 'left top';
      head.style.willChange = 'transform, opacity';
      bs.on('scroll', () => {
        const t = Math.min(1, Math.abs(bs.y) / 56);
        head.style.transform = `translateY(${(-t * 8).toFixed(2)}px) scale(${(1 - t * 0.22).toFixed(3)})`;
        head.style.opacity = (1 - t * 0.72).toFixed(3);
      });
    });
  }

  /* ---------- 绑定：抽屉走 window；左滑走元素（才能阻断切屏手势） ---------- */
  window.addEventListener('touchstart', drawerDown, { passive: true });
  window.addEventListener('touchmove', drawerMove, { passive: false });
  window.addEventListener('touchend', drawerUp);
  window.addEventListener('touchcancel', drawerUp);
  window.addEventListener('mousedown', drawerDown);
  window.addEventListener('mousemove', drawerMove);
  window.addEventListener('mouseup', drawerUp);

  ['#record-lists', '#exercise-list'].forEach(sel => {
    const el = $(sel);
    if (!el) return;
    el.addEventListener('touchstart', swipeDown, { passive: true });
    el.addEventListener('touchmove', swipeMove, { passive: false });
    el.addEventListener('touchend', swipeUp);
    el.addEventListener('touchcancel', swipeUp);
    window.addEventListener('mousemove', swipeMove);
    window.addEventListener('mouseup', swipeUp);
    el.addEventListener('mousedown', swipeDown);
  });
})();

/* ---------- 调试/测试句柄：ES module 无全局变量，显式暴露少量入口供控制台与自动化验证 ---------- */
window.__sg = {
  state, updateState, HealthAPI,
  logic: { computeMetabolism, exerciseKcalOf, portionMacros, macroGoals, avgDeficitFromRows, buildAdvice, makeAdviceCtx, EXERCISE_LIB, ACTIVITY },
  render: { renderRing, renderMetab, renderDailyAdvice, renderWater, renderExerciseList, renderRecordLists },
  switchScreen, setTabbarHidden,
};
