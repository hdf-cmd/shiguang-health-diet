import test from 'node:test';
import assert from 'node:assert/strict';
import { handleNutritionLabel } from '../HealthyDiet/cloudfunctions/api-diet/services/label_route.js';

const DAY = '2026-11-17';
const IMAGE = 'data:image/jpeg;base64,AAAA';

function makeDeps(overrides = {}) {
  const updates = [];
  const base = {
    profiles: {
      where: () => ({ update: async patch => { updates.push(patch); } }),
    },
    getOrCreateProfile: async () => ({ aiScanDate: DAY, aiScanCount: 0 }),
    today: () => DAY,
    dailyLimit: 50,
    resolveAiChannels: () => ({
      channels: [{
        apiKey: 'k', target: { url: 'https://example', model: 'm' },
        logTag: 'TEST', isCustom: false,
      }],
      customError: '', message: '',
    }),
    callChat: async () => ({
      status: 200,
      text: '{"ok":true,"name":"安慕希酸奶","brand":"伊利","unit":"g","servingGrams":200,"per100":{"kcal":89,"protein":3.1,"carb":12,"fat":3.1}}',
    }),
    parseModelJson: text => {
      try { return JSON.parse(text); } catch (_) { return null; }
    },
    builtinKey: 'k',
    now: () => 1000,
  };
  return { deps: { ...base, ...overrides }, updates };
}

test('营养表路由：成功返回结构，内置通道扣一次配额', async () => {
  const { deps, updates } = makeDeps();
  const r = await handleNutritionLabel({ ...deps, uid: 'u1', body: { image: IMAGE } });
  assert.equal(r.ok, true);
  assert.equal(r.name, '安慕希酸奶');
  assert.equal(r.servingGrams, 200);
  assert.deepEqual(r.per100, { kcal: 89, protein: 3.1, carb: 12, fat: 3.1 });
  assert.equal(r.quota.used, 1);
  assert.equal(updates.length, 1);
});

test('营养表路由：自带 Key 成功不扣内置配额', async () => {
  const { deps, updates } = makeDeps({
    resolveAiChannels: () => ({
      channels: [{
        apiKey: 'k', target: { url: 'https://example', model: 'm' },
        logTag: 'CUSTOM', isCustom: true,
      }],
      customError: '', message: '',
    }),
  });
  const r = await handleNutritionLabel({ ...deps, uid: 'u1', body: { image: IMAGE } });
  assert.equal(r.ok, true);
  assert.equal(r.quota, undefined);
  assert.equal(updates.length, 0);
});

test('营养表路由：图片格式不对直接拒绝', async () => {
  const { deps } = makeDeps();
  const r = await handleNutritionLabel({ ...deps, uid: 'u1', body: { image: 'not-an-image' } });
  assert.equal(r.ok, false);
  assert.match(r.message, /图片格式/);
});

test('营养表路由：模型两次读不出返回可行动文案', async () => {
  const { deps } = makeDeps({
    callChat: async () => ({ status: 200, text: '{"ok":false}' }),
  });
  const r = await handleNutritionLabel({ ...deps, uid: 'u1', body: { image: IMAGE } });
  assert.equal(r.ok, false);
  assert.match(r.message, /没读出来/);
});

test('营养表路由：网络失败返回超时文案', async () => {
  const { deps } = makeDeps({
    callChat: async () => ({ status: 0, text: null }),
  });
  const r = await handleNutritionLabel({ ...deps, uid: 'u1', body: { image: IMAGE } });
  assert.equal(r.ok, false);
  assert.match(r.message, /连接超时/);
});

test('营养表路由：配额耗尽不再调模型', async () => {
  let called = false;
  const { deps } = makeDeps({
    getOrCreateProfile: async () => ({ aiScanDate: DAY, aiScanCount: 50 }),
    callChat: async () => { called = true; return { status: 200, text: '{}' }; },
  });
  const r = await handleNutritionLabel({ ...deps, uid: 'u1', body: { image: IMAGE } });
  assert.equal(r.ok, false);
  assert.equal(called, false);
});
