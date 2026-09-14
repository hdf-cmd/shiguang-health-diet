/* ============================================================
 * 食光 · 界面交互逻辑
 * 所有数据均通过 HealthAPI（js/api.js）获取，页面不做直接存储。
 * ============================================================ */

const $  = sel => document.querySelector(sel);
const $$ = sel => [...document.querySelectorAll(sel)];

/* APK/WebView 环境：系统已提供状态栏，隐藏原型手机壳的模拟状态栏（桌面浏览器保留） */
if (/\bwv\b/.test(navigator.userAgent)) {
  const sb = $('.statusbar');
  if (sb) sb.style.display = 'none';
}

const MEAL_NAMES = { breakfast: '早餐', lunch: '午餐', dinner: '晚餐', snack: '零食' };
const MEAL_EMOJI = { breakfast: '🌅', lunch: '🍚', dinner: '🌙', snack: '🍎' };
const state = {
  date: localIso(new Date()),
  summary: null, records: [], mealChosen: 'lunch',
  waterGoalMl: 1600,
  profileData: null,
  exercises: [], exerciseKcal: 0,
  exerciseChosen: 'run', exerciseAmount: 5,
  sheetKeyword: '',
};

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
  buzz(8);
  if (name === 'report') loadReportPage();   // 每次进入报告页都拉最新周报
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
/* 按本地日期组件切片：toISOString 在 UTC+X 时区凌晨会回退一天，导致日期跳双天 */
function localIso(d) {
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
const todayIso = () => localIso(new Date());
/* 日期口语标签：今天/昨天/M月D日（喝水/运动卡标题共用） */
function dateLabelOf(iso) {
  const yd = new Date(); yd.setDate(yd.getDate() - 1);
  if (iso === localIso(yd)) return '昨天';
  const d = new Date(iso + 'T00:00:00');
  return `${d.getMonth() + 1}月${d.getDate()}日`;
}
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
  const budget = s.target + ex;   // 今日额度 = 目标 + 运动消耗
  const remain = Math.max(0, budget - s.kcal);
  $('#ring-target').textContent = s.target;
  $('#ring-eaten').textContent = s.kcal;
  $('#ring-exercise').textContent = ex;

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
}

/* 每日建议：按今日记录实时生成的规则引擎（热量/宏量/喝水/时段），最多 3 条 */
function renderDailyAdvice() {
  const s = state.summary;
  const el = $('#home-advice');
  if (!s || !el) return;
  const ex = state.exerciseKcal || 0;
  const budget = s.target + ex;
  const remain = budget - s.kcal;
  const goals = {
    carb: Math.round(s.target * .5 / 4),
    protein: Math.round(s.target * .25 / 4),
    fat: Math.round(s.target * .25 / 9),
  };
  const isToday = state.date === todayIso();
  const w = (state.body && state.body.weightKg) || 55;
  const tips = [];
  if (s.kcal === 0) {
    tips.push(['📝', isToday ? '今天还没记录，去「记录」页点「记一笔」开始第一餐吧' : '这一天还没有记录，可在记录页切换日期查看']);
  } else {
    if (remain > 0) {
      tips.push(['🍽️', `还能吃 ${remain} kcal${goals.protein - s.protein > 10 ? '，优先补蛋白：蛋、豆制品、鱼虾' : '，主食、蔬菜、蛋白均衡搭配'}`]);
    } else {
      const walk = exerciseKcalOf(EXERCISE_LIB[1], 2.5, w);
      tips.push(['⚠️', `已超今日额度 ${-remain} kcal，快走 30 分钟约消耗 ${walk} kcal，或明天稍减主食`]);
    }
    const pGap = goals.protein - s.protein;
    if (pGap >= 15) tips.push(['🥚', `蛋白质还差 ${pGap}g，下一餐加一份蛋、豆制品或鱼虾`]);
    if (s.fat > goals.fat) tips.push(['🍳', `脂肪已达目标 ${Math.round(s.fat / goals.fat * 100)}%，剩余餐次选蒸煮、白切等少油做法`]);
    const cGap = goals.carb - s.carb;
    if (cGap >= 40) tips.push(['🍚', `主食还差 ${cGap}g 碳水，不吃主食易乏力，保留适量谷物`]);
  }
  const wml = (s.water || 0) * WATER_CUP_ML;
  if (isToday && wml < state.waterGoalMl) tips.push(['💧', `喝水 ${wml}/${state.waterGoalMl}ml，记得少量多次补水`]);
  if (tips.length === 1 && s.kcal > 0) tips.push(['✅', '三大营养素都在合理区间，保持这个节奏']);
  el.innerHTML = tips.slice(0, 3).map(([e, t]) => `<li><span class="ai">${e}</span><span>${t}</span></li>`).join('');
}

/* 营养素进度条（首页/报告共用）：目标量按 50/25/3 常规供能比估算 */
function renderNutrientBars(sel, s) {
  const items = [
    ['carb',    '碳水',   s.carb,    Math.round(s.target * .5 / 4)],
    ['protein', '蛋白质', s.protein, Math.round(s.target * .25 / 4)],
    ['fat',     '脂肪',   s.fat,     Math.round(s.target * .25 / 9)],
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

/* 喝水打卡：每杯 200ml；点水杯累加，目标可在 800–3000ml 自定义 */
const WATER_CUP_ML = 200;
const WATER_GOAL_MIN = 800, WATER_GOAL_MAX = 3000;

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
  $('#water-hint').innerHTML = reached ? '目标已达成 🎉' : `已喝 ${n} 杯<br><span class="wh-sub">每杯 200ml</span>`;
  $('#water-undo').style.visibility = n > 0 ? 'visible' : 'hidden';
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
  $('#record-lists').innerHTML = Object.entries(byMeal).map(([meal, list]) => {
    const sum = list.reduce((a, r) => a + r.kcal, 0);
    return `
    <section class="meal-section">
      <div class="sec-head"><span class="sec-emoji">${MEAL_EMOJI[meal]}</span>${MEAL_NAMES[meal]}<span class="sum">${sum} kcal</span></div>
      ${list.length ? list.map(r => `
        <div class="food-item">
          <span class="thumb">${r.image ? `<img class="thumb-img" src="${r.image}" alt="">` : r.emoji}</span>
          <span class="info">
            <span class="name">${r.name}</span>
            <span class="meta" style="display:block">${r.portion}</span>
          </span>
          <span class="kcal">${r.kcal}<small> kcal</small></span>
          <button class="del" data-del="${r.id}" aria-label="删除${r.name}">✕</button>
        </div>`).join('')
      : '<p class="empty" style="padding:16px 0">这一餐还没记录，点下方「记一笔」</p>'}
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
        <button class="btn btn-soft" style="padding:8px 14px" data-add='${JSON.stringify(f)}'>${f.per100 ? '按克加' : '添加'}</button>
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

/* ---------- 克数份量弹层：per100 食物按克数换算营养（米饭等） ---------- */
let portionFood = null;
function portionMacros(f, g) {
  const p = f.per100, k = g / 100;
  return {
    kcal: Math.round(p.kcal * k),
    protein: +(p.protein * k).toFixed(1),
    carb: +(p.carb * k).toFixed(1),
    fat: +(p.fat * k).toFixed(1),
  };
}
function openPortionSheet(f) {
  portionFood = f;
  $('#portion-title').textContent = `${f.name} · 自定义份量`;
  $('#portion-g-val').value = f.baseG || 100;
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
  $('#portion-preview').innerHTML = `${g}g ≈ <b>${r.kcal}</b> kcal · 蛋白 ${r.protein}g / 碳水 ${r.carb}g / 脂肪 ${r.fat}g`;
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
  if (g < 10) { toast('请输入克数'); return; }
  const r = portionMacros(f, g);
  const temp = {
    id: 'tmp_' + Date.now(), meal: state.mealChosen,
    name: f.name, portion: `${g}g`, kcal: r.kcal, emoji: f.emoji, image: f.image || '',
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
  toast(`已添加 ${f.name} ${g}g · 可继续添加`);
  HealthAPI.addFoodRecord({
    date: state.date, meal: state.mealChosen,
    name: f.name, portion: `${g}g`, kcal: r.kcal, emoji: f.emoji,
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
        <div class="bar" style="height:${Math.max(4, kcal / max * 100)}%"></div>
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

  $('#report-advice').textContent = buildAdvice(r, avg);
  $('#advice-title').textContent = r.isWeek === false ? '本月建议' : '本周建议';
}

/* 多维规则建议引擎：按达标率+热量组合生成，最多 3 条拼接 */
function buildAdvice(r, avgKcal) {
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
  const points = w.points.length === 1 ? [w.points[0], w.points[0]] : w.points;   // 单点复制成两点画线，防除零
  const min = Math.min(...points) - .4, max = Math.max(...points) + .4;
  const pts = points.map((v, i) =>
    [20 + i * (280 / (points.length - 1)), 80 - (v - min) / (max - min) * 64]);
  const path = pts.map(([x, y], i) => `${i ? 'L' : 'M'}${x.toFixed(1)} ${y.toFixed(1)}`).join(' ');
  $('#weight-svg').innerHTML = `
    <path d="${path}" fill="none" stroke="var(--primary)" stroke-width="2.5" stroke-linecap="round"/>
    ${pts.map(([x, y], i) => `<circle cx="${x}" cy="${y}" r="${i === pts.length - 1 ? 5 : 3.5}"
      fill="${i === pts.length - 1 ? 'var(--primary)' : '#fff'}" stroke="var(--primary)" stroke-width="2"/>`).join('')}`;
  const delta = (points.at(-1) - points[0]).toFixed(1);
  $('#weight-delta').textContent = `当前 ${points.at(-1)} kg · 本周 ${delta > 0 ? '+' : ''}${delta} kg`;
  $('#weight-delta').style.color = delta <= 0 ? 'var(--primary)' : 'var(--warn)';
}

/* ---------- 每日体重日志：趋势卡入口 + 弹层（反馈5） ---------- */
function openWeightLogSheet() {
  $('#weight-log-val').value = (state.body && state.body.weightKg) || 55;
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
$('#weight-log-dec').addEventListener('click', () => bumpBodyVal('#weight-log-val', -0.5, 20, 300, 1));
$('#weight-log-inc').addEventListener('click', () => bumpBodyVal('#weight-log-val', 0.5, 20, 300, 1));
bindStepperNorm('#weight-log-val', 20, 300, 1);
$('#weight-log-save').addEventListener('click', async () => {
  const w = Number($('#weight-log-val').value);
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
renderRemindSwitch();

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

/* ---------- 自定义食物：名称+热量+图片入库，可选记入本餐 ---------- */
let cfImageData = '';   // 压缩后的 dataURL，空串=无图
let cfKcalManual = false;   // 用户手改热量后，不再被三素自动计算覆盖
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
  renderCfPreview();
  $('#cf-save-add').style.display = fromLib ? 'none' : '';   // 从食物库进入只入库、不记餐
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
  const portion = grams ? `${grams}g` : '1 份';
  if (!name) { toast('请填写食物名称'); return; }
  if (!kcal || kcal <= 0) { toast('请填热量，或先填三大营养素自动算'); return; }
  try {
    await HealthAPI.addCustomFood({ name, kcal, grams, protein, carb, fat, portion, image: cfImageData });
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
      $('#foodlib-sub').textContent = `自定义 ${list.length} 条 · 可删除`;
      box.innerHTML = list.length ? list.map(f => `
        <div class="food-item">
          <span class="thumb">${f.image ? `<img class="thumb-img" src="${f.image}" alt="">` : (f.emoji || '🍽️')}</span>
          <span class="info">
            <span class="name">${f.name}</span>
            <span class="meta" style="display:block">${f.grams ? f.grams + 'g · ' : ''}蛋白 ${f.protein}g / 碳水 ${f.carb}g / 脂肪 ${f.fat}g</span>
          </span>
          <span class="kcal">${f.kcal}<small> kcal</small></span>
          <span class="lib-item-actions"><button class="lib-act danger" data-del-cf="${f.id}">删除</button></span>
        </div>`).join('')
        : `<div class="empty"><div class="art">🍽️</div><p>还没有自定义食物<br>点下方按钮添加你的常吃菜</p></div>`;
    } else {
      const list = libBuiltinCache || (libBuiltinCache = await HealthAPI.getBuiltinFoods());
      const hiddenCount = list.filter(f => f.hidden).length;
      $('#foodlib-sub').textContent = `内置 ${list.length} 条 · 已移除 ${hiddenCount}`;
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
$('#foodlib-open').addEventListener('click', openFoodLib);
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
 * 公式：Mifflin-St Jeor
 *   BMR 男 = 10W + 6.25H − 5A + 5；女 = 10W + 6.25H − 5A − 161
 *   TDEE = BMR × 活动系数；建议摄入 = max(TDEE − 缺口, 安全下限, BMR)
 *   达标时间 = (当前−目标)kg × 7700 kcal ÷ 实际每日缺口
 * ============================================================ */
const ACTIVITY = {
  sedentary: { f: 1.2,   label: '久坐' },
  light:     { f: 1.375, label: '轻度' },
  moderate:  { f: 1.55,  label: '中度' },
  active:    { f: 1.725, label: '重度' },
  extreme:   { f: 1.9,   label: '极大' },
};
const KCAL_PER_KG = 7700;   // 减 1kg 体脂约需缺口
const BODY_DEFAULT = { heightCm: 165, weightKg: 55, bmi: 20.2, age: 28, gender: 'female', activity: 'light', deficit: 500 };

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

function computeMetabolism(b, targetWeight) {
  const W = b.weightKg, H = b.heightCm, A = b.age;
  const bmr = Math.round(10 * W + 6.25 * H - 5 * A + (b.gender === 'male' ? 5 : -161));
  const f = (ACTIVITY[b.activity] || ACTIVITY.light).f;
  const tdee = Math.round(bmr * f);
  const floor = b.gender === 'male' ? 1500 : 1200;
  const suggest = Math.max(tdee - b.deficit, floor, bmr);
  const realDeficit = tdee - suggest;
  const bmi = +(W / Math.pow(H / 100, 2)).toFixed(1);
  const need = +(W - (targetWeight || W)).toFixed(1);
  let etaText;
  if (need <= 0) etaText = '已达标或目标不低于当前体重，维持当前摄入即可';
  else if (realDeficit <= 0) etaText = '当前摄入无缺口，无法减重，请提高缺口档位';
  else {
    const days = Math.ceil(need * KCAL_PER_KG / realDeficit);
    const weeks = Math.ceil(days / 7);
    const d = new Date(Date.now() + days * 86400000);
    const months = Math.round(days / 30.44);
    const span = months >= 12 ? `约 ${Math.floor(months / 12)} 年 ${months % 12} 个月` : `约 ${months} 个月`;
    etaText = `预计 ${weeks} 周（${span} · ${d.getFullYear()}年${d.getMonth() + 1}月${d.getDate()}日）减到 ${targetWeight}kg`;
    if (realDeficit * 7 / KCAL_PER_KG > 1) etaText += ' · 减重偏快，建议降为温和缺口';
  }
  const lo = (18.5 * Math.pow(H / 100, 2)).toFixed(1), hi = (23.9 * Math.pow(H / 100, 2)).toFixed(1);
  return { bmr, tdee, suggest, realDeficit, bmi, etaText, rangeText: `合理体重区间 ${lo}–${hi} kg（BMI 18.5–23.9）` };
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
  const m = computeMetabolism(b, tw);
  state.metab = m;
  const ex = state.exerciseKcal || 0;
  $('#metab-bmr').innerHTML = `${m.bmr}<small> kcal</small>`;
  $('#metab-tdee').innerHTML = `${m.tdee + ex}<small> kcal</small>`;
  $('#metab-exercise').innerHTML = `${ex}<small> kcal</small>`;
  // 今日建议摄入 = 基准目标 + 今日运动（与首页环额度同源）；基准目标同步云端不随运动波动
  $('#metab-suggest').innerHTML = `${m.suggest + ex}<small> kcal</small>`;
  $('#metab-deficit').innerHTML = `${m.realDeficit}<small> kcal</small>`;
  $('#metab-note').textContent = ex > 0
    ? `含今日运动 ${ex} kcal · 基准 ${m.suggest}`
    : `基准目标 ${m.suggest} kcal`;
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
bindStepperNorm('#weight-val', 30, 200, 1);
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
 * 距离型 kcal = 系数 × 体重kg × 距离km；
 * 时长型 kcal = MET × 3.5 × 体重kg / 200 × 分钟
 * ============================================================ */
const EXERCISE_LIB = [
  { key: 'run',      name: '跑步',     emoji: '🏃', unit: 'km',  perKgKm: 1.036 },
  { key: 'walk',     name: '快走',     emoji: '🚶', unit: 'km',  perKgKm: 0.5 },
  { key: 'cycle',    name: '骑行',     emoji: '🚴', unit: 'km',  perKgKm: 0.35 },
  { key: 'swim',     name: '游泳',     emoji: '🏊', unit: 'min', met: 8 },
  { key: 'pushup',   name: '俯卧撑',   emoji: '💪', unit: 'min', met: 8 },
  { key: 'strength', name: '力量训练', emoji: '🏋️', unit: 'min', met: 5 },
  { key: 'yoga',     name: '瑜伽',     emoji: '🧘', unit: 'min', met: 2.5 },
  { key: 'rope',     name: '跳绳',     emoji: '🤸', unit: 'min', met: 11 },
  { key: 'hiit',     name: 'HIIT',     emoji: '🔥', unit: 'min', met: 8 },
  { key: 'ball',     name: '球类',     emoji: '🏀', unit: 'min', met: 7 },
];
function exerciseKcalOf(lib, amount, weightKg) {
  const w = weightKg || 55;
  return lib.unit === 'km'
    ? Math.round(lib.perKgKm * w * amount)
    : Math.round(lib.met * 3.5 * w / 200 * amount);
}
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
        <span class="meta" style="display:block">${r.amount}${r.unit === 'km' ? ' km' : ' 分钟'}</span>
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
  $('#exercise-amount-label').textContent = lib.unit === 'km' ? '距离' : '时长';
  $('#exercise-amount-unit').textContent = lib.unit === 'km' ? 'km' : '分钟';
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
  state.exerciseAmount = currentLib().unit === 'km' ? 5 : 20;
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
  const max = lib.unit === 'km' ? 100 : 300;
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
  const temp = { id: 'tmpx_' + Date.now(), key: lib.key, name: lib.name, emoji: lib.emoji, amount: state.exerciseAmount, unit: lib.unit, kcal };
  state.exercises.push(temp);   // 乐观更新（反馈8）
  state.exerciseKcal += kcal;
  renderExerciseList();
  renderRing();
  renderMetab();
  closeExerciseSheet();
  toast(`已记录${lib.name} · 消耗 ${kcal} kcal`);
  HealthAPI.addExercise({
    date: state.date, key: lib.key, name: lib.name, emoji: lib.emoji,
    amount: state.exerciseAmount, unit: lib.unit, kcal,
  }).then(() => loadExercises()).catch(err => {
    state.exercises = state.exercises.filter(r => r.id !== temp.id);
    state.exerciseKcal -= kcal;
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
    state.exercises = state.exercises.filter(r => r.id !== id);
    state.exerciseKcal -= rec.kcal || 0;
    renderExerciseList();
    renderRing();
    renderMetab();
  }
  toast('已删除运动记录');
  HealthAPI.deleteExercise(id).then(() => loadExercises()).catch(err => {
    if (rec) {
      state.exercises.push(rec);
      state.exerciseKcal += rec.kcal || 0;
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
/* 长按删除记录/运动（AlloyFinger longTap，开源集成） */
if (window.AlloyFinger) {
  new AlloyFinger($('#record-lists'), {
    longTap: evt => { const b = evt.target.closest('[data-del]'); if (b) deleteRecordById(b.dataset.del); },
  });
  new AlloyFinger($('#exercise-list'), {
    longTap: evt => { const b = evt.target.closest('[data-xdel]'); if (b) deleteExerciseById(b.dataset.xdel); },
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
  renderDateRow();
  renderPlateDate();
  await bootToday();   // 并行拉取+退避重试，首屏快且不怕冷启动（反馈8）
  await loadMainBundleSafe();
})();
