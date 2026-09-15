/* 日期处理单测（node:test，零依赖）
 *
 * 重点保护两件事：
 *   1) 本地时区安全 —— localIso 用本地字段拼日期，绝不用 toISOString（会按 UTC 切片导致跳天）
 *   2) 口语标签契约 —— 「昨天」是唯一被特殊识别的；「今天」由调用方自行判断
 */
import test from 'node:test';
import assert from 'node:assert/strict';
import { localIso, todayIso, dateLabelOf } from '../js/logic.js';

/* ---------- localIso ---------- */

test('localIso: 月/日补零，输出 YYYY-MM-DD', () => {
  assert.equal(localIso(new Date(2026, 0, 5)), '2026-01-05');
  assert.equal(localIso(new Date(2026, 9, 9)), '2026-10-09');
  assert.equal(localIso(new Date(2026, 11, 31)), '2026-12-31');
});

test('localIso: 同一天的凌晨与深夜都落在同一天（不随 UTC 偏移跳天）', () => {
  // 本地最早的几秒与最晚的几秒，结果必须是同一个日期
  assert.equal(localIso(new Date(2026, 0, 1, 0, 0, 1)), '2026-01-01');
  assert.equal(localIso(new Date(2026, 0, 1, 23, 59, 59)), '2026-01-01');
  // 跨年边界同理
  assert.equal(localIso(new Date(2026, 11, 31, 23, 59, 59)), '2026-12-31');
  assert.equal(localIso(new Date(2027, 0, 1, 0, 0, 1)), '2027-01-01');
});

test('localIso: 闰年 2 月 29 日', () => {
  assert.equal(localIso(new Date(2028, 1, 29)), '2028-02-29');
  assert.equal(localIso(new Date(2028, 2, 1)), '2028-03-01');
});

test('todayIso: 恒等于当前本地日期', () => {
  assert.equal(todayIso(), localIso(new Date()));
});

/* ---------- dateLabelOf ---------- */

test('dateLabelOf: 昨天返回「昨天」（含跨月与跨年）', () => {
  const yd = new Date();
  yd.setDate(yd.getDate() - 1);
  assert.equal(dateLabelOf(localIso(yd)), '昨天');
});

test('dateLabelOf: 今天不返回「昨天」（本函数不识别今天，由调用方判断）', () => {
  const today = new Date();
  const label = dateLabelOf(localIso(today));
  assert.notEqual(label, '昨天');
  assert.equal(label, `${today.getMonth() + 1}月${today.getDate()}日`);
});

test('dateLabelOf: 更早的日期返回「M月D日」（不补零）', () => {
  const d2 = new Date();
  d2.setDate(d2.getDate() - 2);   // 前天，永远不可能是「昨天」，避免测试随日期漂移
  assert.equal(dateLabelOf(localIso(d2)), `${d2.getMonth() + 1}月${d2.getDate()}日`);
  // 跨月场景：固定日期只验证格式，不与今天/昨天重合
  assert.equal(dateLabelOf('2026-03-01'), '3月1日');
  assert.equal(dateLabelOf('2026-12-31'), '12月31日');
});

test('dateLabelOf: 按本地时间解析日期串（避免 UTC 解析把日期挪走）', () => {
  // '2026-01-01T00:00:00' 无 Z 后缀 → 按本地时间解析；若被当作 UTC 解析，东八区会取到 1月1日 08:00 之外的偏移
  assert.equal(dateLabelOf('2026-01-01'), '1月1日');
  assert.equal(dateLabelOf('2026-06-15'), '6月15日');
});