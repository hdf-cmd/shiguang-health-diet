/* ============================================================
 * 食光 · 全局状态（ES Module）+ 集中更新入口
 * ------------------------------------------------------------
 * 反馈7：收敛散落的 state.xxx = ... 直接 mutate。统一走 updateState()，
 * 便于追踪变更、做乐观更新回滚、以及未来接入持久化/调试工具。
 * updateState(patch | mutator) 同步修改并返回 state；调用方负责触发渲染。
 * ============================================================ */
import { localIso, todayIso } from './logic.js';

export const state = {
  date: localIso(new Date()),
  summary: null, records: [], mealChosen: 'lunch',
  waterGoalMl: 1600,
  profileData: null,
  body: null,
  metab: null,
  exercises: [], exerciseKcal: 0,
  exerciseChosen: 'run', exerciseAmount: 5,
  sheetKeyword: '',
  actualDeficit: null,   // 反馈3：近 7 天实际日均缺口缓存 { avgDeficit, days, tdee }
  comp: null,            // 二期：体成分趋势聚合 { bfLatest, bfDelta, msDelta }（秤同步数据，缺则 null）
};

/* 变更日志（环形缓冲，便于调试/回溯；不参与渲染） */
const CHANGE_LOG = [];
const LOG_MAX = 50;

/**
 * 集中更新入口。
 * @param {object|function} patchOrFn 对象=浅合并到 state；函数=接收 state 直接细粒度修改（用于嵌套字段如 summary.kcal）。
 * @param {string} [tag] 变更来源标签（如 'exercise.add'），记入 CHANGE_LOG。
 * @returns {typeof state} 更新后的 state（同一引用，渲染层按需重绘）。
 */
export function updateState(patchOrFn, tag) {
  if (typeof patchOrFn === 'function') patchOrFn(state);
  else Object.assign(state, patchOrFn);
  CHANGE_LOG.push({ tag: tag || 'update', t: Date.now() });
  if (CHANGE_LOG.length > LOG_MAX) CHANGE_LOG.shift();
  return state;
}

/* 只读快照（调试/测试用） */
export const getState = () => state;
export const getChangeLog = () => CHANGE_LOG.slice();

/* 便捷判定 */
export const isViewingToday = () => state.date === todayIso();
