import test from 'node:test';
import assert from 'node:assert/strict';
import { handleMealParse } from '../HealthyDiet/cloudfunctions/api-diet/services/meal_parse_route.js';

const DAY = '2026-11-17';

function makeDeps(overrides = {}) {
  const updates = [];
  let profiles = { aiScanDate: DAY, aiScanCount: 0, hiddenFoods: [] };
  const base = {
    profiles: {
      where: () => ({ update: async patch => { updates.push(patch); } }),
    },
    getOrCreateProfile: async () => profiles,
    today: () => DAY,
    dailyLimit: 50,
    resolveAiChannels: () => ({
      channels: [{
        apiKey: 'k', target: { url: 'https://example', model: 'm' },
        logTag: 'TEST', isCustom: false,
      }],
      customError: '', message: '',
    }),
    callChat: async () => ({ status: 200, text: '{"items":[{"query":"米饭"}]}' }),
    parseModelJson: text => {
      try { return JSON.parse(text); } catch (_) { return null; }
    },
    searchFoods: async query => ([
      { name: '鸡蛋羹', kcal: 65, unit: 'g', baseG: 160, per100: { kcal: 50, protein: 3.8, carb: 1.2, fat: 3.1 } },
      { name: '鸡蛋', kcal: 78, unit: 'g', baseG: 50, per100: { kcal: 156, protein: 14, carb: 2, fat: 10 } },
      { name: '米饭', kcal: 174, unit: 'g', baseG: 200, per100: { kcal: 116, protein: 2.6, carb: 25.9, fat: 0.3 } },
      { name: '米饭（大份）', kcal: 300, unit: 'g', baseG: 300, per100: { kcal: 100, protein: 2.6, carb: 25.9, fat: 0.3 } },
    ]),
    builtinKey: 'k',
    now: () => 1000,
  };
  const deps = { ...base, ...overrides };
  return { deps, updates, setProfile: p => { profiles = p; } };
}

test('描述路由：成功返回 match 与 top-3 候选，内置通道扣一次配额', async () => {
  const { deps, updates } = makeDeps({
    callChat: async () => ({
      status: 200,
      text: '{"items":[{"query":"米饭","quantity":1,"unit":"serving","portion":"bowl"}]}',
    }),
  });
  const r = await handleMealParse({ ...deps, uid: 'u1', body: { text: '一碗米饭', meal: 'lunch' } });
  assert.equal(r.ok, true);
  assert.equal(r.channel, 'deepseek');
  assert.equal(r.quota.used, 1);
  assert.equal(updates.length, 1);
  assert.equal(r.items.length, 1);
  assert.equal(r.items[0].match.name, '米饭');
  assert.equal(r.items[0].matches.length, 3);
  assert.equal(r.items[0].matches[0].name, '米饭');
});

test('描述路由：精确同名候选排第一', async () => {
  const { deps } = makeDeps({
    callChat: async () => ({ status: 200, text: '{"items":[{"query":"鸡蛋"}]}' }),
  });
  const r = await handleMealParse({ ...deps, uid: 'u1', body: { text: '鸡蛋' } });
  assert.equal(r.ok, true);
  assert.equal(r.items[0].match.name, '鸡蛋');
  assert.deepEqual(r.items[0].matches.map(m => m.name), ['鸡蛋', '鸡蛋羹', '米饭']);
});

test('描述路由：自带 Key 成功不计内置配额', async () => {
  const { deps, updates } = makeDeps({
    resolveAiChannels: () => ({
      channels: [{
        apiKey: 'k', target: { url: 'https://example', model: 'm' },
        logTag: 'CUSTOM', isCustom: true,
      }],
      customError: '', message: '',
    }),
  });
  const r = await handleMealParse({ ...deps, uid: 'u1', body: { text: '米饭' } });
  assert.equal(r.ok, true);
  assert.equal(r.channel, 'custom');
  assert.equal(r.quota, undefined);
  assert.equal(updates.length, 0);
});

test('描述路由：模型两次返回非法 JSON → 明确失败', async () => {
  const { deps } = makeDeps({
    callChat: async () => ({ status: 200, text: '这不是 JSON' }),
  });
  const r = await handleMealParse({ ...deps, uid: 'u1', body: { text: '米饭' } });
  assert.equal(r.ok, false);
  assert.match(r.message, /没解析出来/);
});

test('描述路由：网络超时返回可重试文案', async () => {
  const { deps } = makeDeps({
    callChat: async () => ({ status: 0, text: null }),
  });
  const r = await handleMealParse({ ...deps, uid: 'u1', body: { text: '米饭' } });
  assert.equal(r.ok, false);
  assert.match(r.message, /连接超时/);
});

test('描述路由：没有可用通道直接返回配置提示', async () => {
  const { deps } = makeDeps({
    resolveAiChannels: () => ({ channels: [], customError: '', message: '识别服务未配置' }),
  });
  const r = await handleMealParse({ ...deps, uid: 'u1', body: { text: '米饭' } });
  assert.equal(r.ok, false);
  assert.equal(r.message, '识别服务未配置');
});

test('描述路由：模型返回空数组是有效答案', async () => {
  const { deps } = makeDeps({
    callChat: async () => ({ status: 200, text: '{"items":[]}' }),
  });
  const r = await handleMealParse({ ...deps, uid: 'u1', body: { text: '今天没吃东西' } });
  assert.equal(r.ok, true);
  assert.deepEqual(r.items, []);
});

test('描述路由：原文没有单位时丢掉模型凭空补的 g', async () => {
  const { deps } = makeDeps({
    callChat: async () => ({
      status: 200,
      text: '{"items":[{"query":"安慕希酸奶","quantity":1,"unit":"g"}]}',
    }),
  });
  const r = await handleMealParse({ ...deps, uid: 'u1', body: { text: '一盒安慕希酸奶' } });
  assert.equal(r.ok, true);
  assert.equal(r.items[0].unit, null);
  assert.equal(r.items[0].quantity, 1);
});

test('描述路由：原文明确写了单位时保留', async () => {
  const { deps } = makeDeps({
    callChat: async () => ({
      status: 200,
      text: '{"items":[{"query":"米饭","quantity":100,"unit":"g"}]}',
    }),
  });
  const r = await handleMealParse({ ...deps, uid: 'u1', body: { text: '100g 米饭' } });
  assert.equal(r.items[0].unit, 'g');
});

test('描述路由：模型把「一瓶」当数量时用原文 200g 校正', async () => {
  const { deps } = makeDeps({
    callChat: async () => ({
      status: 200,
      text: '{"items":[{"query":"安慕希酸奶","quantity":1,"unit":"g"},{"query":"肉包","quantity":1},{"query":"红糖馒头","quantity":1}]}',
    }),
  });
  const r = await handleMealParse({
    ...deps,
    uid: 'u1',
    body: { text: '早餐一瓶200g安慕希酸奶，1个肉包，一个红糖馒头' },
  });
  assert.equal(r.ok, true);
  assert.equal(r.items[0].query, '安慕希酸奶');
  assert.equal(r.items[0].quantity, 200);
  assert.equal(r.items[0].unit, 'g');
});

test('描述路由：文本过短不调用模型', async () => {
  let called = false;
  const { deps } = makeDeps({ callChat: async () => { called = true; return { status: 200, text: '{}' }; } });
  const r = await handleMealParse({ ...deps, uid: 'u1', body: { text: '米' } });
  assert.equal(r.ok, false);
  assert.match(r.message, /多写一点/);
  assert.equal(called, false);
});
