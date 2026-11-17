import test from 'node:test';
import assert from 'node:assert/strict';
import { handleBarcodeLookup } from '../HealthyDiet/cloudfunctions/api-diet/services/barcode_route.js';

const BARCODE = '4006381333931';
const FOOD = {
  id: 'off_' + BARCODE, name: '测试牛奶', kcal: 64, unit: 'ml', baseG: 250,
  per100: { kcal: 64, protein: 3.3, carb: 4.8, fat: 3.6 },
};

function makeDeps(overrides = {}) {
  const updates = [];
  const base = {
    db: {
      collection: () => ({
        where: () => ({
          limit: () => ({ get: async () => ({ data: [] }) }),
        }),
      }),
    },
    profiles: {
      where: () => ({
        update: async patch => { updates.push(patch); },
      }),
    },
    getOrCreateProfile: async () => ({}),
    today: () => '2026-11-16',
    dailyLimit: 100,
    fetchOffProduct: async () => ({ ok: true, found: true, food: FOOD }),
    readOffCache: async () => null,
    writeOffCache: async () => {},
    fetchIdentity: async () => ({ found: false, reason: 'not_found' }),
    writeIdentityCache: async () => {},
    now: () => 1000,
  };
  return { deps: { ...base, ...overrides }, updates };
}

test('条码路由：格式非法直接拒绝', async () => {
  const { deps } = makeDeps();
  const r = await handleBarcodeLookup({ ...deps, uid: 'u1', code: '123' });
  assert.equal(r.ok, false);
  assert.equal(r.message, '条码格式不正确');
});

test('条码路由：用户自定义绑定优先于缓存与 OFF', async () => {
  const { deps } = makeDeps({
    db: {
      collection: () => ({
        where: () => ({
          limit: () => ({
            get: async () => ({ data: [{ _id: 'cf1', name: '我的牛奶', kcal: 100, grams: 200, unit: 'ml', barcode: BARCODE }] }),
          }),
        }),
      }),
    },
    fetchOffProduct: async () => { throw new Error('should not fetch'); },
  });
  const r = await handleBarcodeLookup({ ...deps, uid: 'u1', code: BARCODE });
  assert.equal(r.ok, true);
  assert.equal(r.source, 'custom');
  assert.equal(r.food.name, '我的牛奶');
  assert.equal(r.food.per100.kcal, 50);
});

test('条码路由：新鲜缓存命中不扣配额', async () => {
  const { deps, updates } = makeDeps({
    readOffCache: async () => ({ food: FOOD, updatedAt: 900 }),
  });
  const r = await handleBarcodeLookup({ ...deps, uid: 'u1', code: BARCODE });
  assert.equal(r.source, 'cache');
  assert.equal(updates.length, 0);
});

test('条码路由：实时命中写缓存并扣一次配额', async () => {
  let cached = null;
  const { deps, updates } = makeDeps({
    writeOffCache: async (code, food) => { cached = { code, food }; },
  });
  const r = await handleBarcodeLookup({ ...deps, uid: 'u1', code: BARCODE });
  assert.equal(r.source, 'off');
  assert.equal(r.quota.used, 1);
  assert.equal(updates.length, 1);
  assert.equal(cached.code, BARCODE);
});

test('条码路由：OFF 未收录返回正常业务结果', async () => {
  const { deps } = makeDeps({
    fetchOffProduct: async () => ({ ok: false, found: false, reason: 'not_found' }),
  });
  const r = await handleBarcodeLookup({ ...deps, uid: 'u1', code: BARCODE });
  assert.equal(r.ok, true);
  assert.equal(r.found, false);
  assert.equal(r.reason, 'not_found');
});

test('条码路由：网络失败无缓存时报服务不可用，有旧缓存时返回 stale', async () => {
  const { deps } = makeDeps({
    fetchOffProduct: async () => ({ ok: false, found: false, reason: 'network' }),
  });
  const noCache = await handleBarcodeLookup({ ...deps, uid: 'u1', code: BARCODE });
  assert.equal(noCache.ok, true);
  assert.equal(noCache.found, false);
  assert.match(noCache.message, /条码服务/);

  const { deps: withCache } = makeDeps({
    fetchOffProduct: async () => ({ ok: false, found: false, reason: 'network' }),
    readOffCache: async () => ({ food: FOOD, updatedAt: 0 }),
  });
  const stale = await handleBarcodeLookup({ ...withCache, uid: 'u1', code: BARCODE });
  assert.equal(stale.ok, true);
  assert.equal(stale.stale, true);
  assert.equal(stale.food.name, '测试牛奶');
});

test('条码路由：OFF 未收录时查国内条码库拿商品身份', async () => {
  let cachedIdentity = null;
  const { deps } = makeDeps({
    fetchOffProduct: async () => ({ ok: false, found: false, reason: 'not_found' }),
    fetchIdentity: async () => ({
      found: true,
      identity: { name: '君乐宝纯牛奶', brand: '君乐宝', spec: '250毫升' },
    }),
    writeIdentityCache: async (code, identity) => { cachedIdentity = { code, identity }; },
  });
  const r = await handleBarcodeLookup({ ...deps, uid: 'u1', code: BARCODE });
  assert.equal(r.ok, true);
  assert.equal(r.source, 'cn-name');
  assert.equal(r.product.name, '君乐宝纯牛奶');
  assert.equal(cachedIdentity.identity.spec, '250毫升');
});

test('条码路由：国内条码库身份缓存命中不再请求', async () => {
  let fetched = false;
  const { deps } = makeDeps({
    readOffCache: async () => ({
      identity: { name: '君乐宝纯牛奶', brand: '君乐宝', spec: '250毫升' },
      identityAt: 900,
    }),
    fetchIdentity: async () => { fetched = true; return { found: false, reason: 'not_found' }; },
  });
  const r = await handleBarcodeLookup({ ...deps, uid: 'u1', code: BARCODE });
  assert.equal(r.source, 'cn-name');
  assert.equal(r.product.name, '君乐宝纯牛奶');
  assert.equal(fetched, false);
});

test('条码路由：OFF 与国内库都未命中返回 found=false', async () => {
  const { deps } = makeDeps({
    fetchOffProduct: async () => ({ ok: false, found: false, reason: 'not_found' }),
  });
  const r = await handleBarcodeLookup({ ...deps, uid: 'u1', code: BARCODE });
  assert.equal(r.ok, true);
  assert.equal(r.found, false);
  assert.match(r.message, /条码未收录/);
});

test('条码路由：配额耗尽不再请求 OFF', async () => {
  let fetched = false;
  const { deps } = makeDeps({
    getOrCreateProfile: async () => ({ barcodeDate: '2026-11-16', barcodeCount: 100 }),
    fetchOffProduct: async () => { fetched = true; return { ok: true, found: true, food: FOOD }; },
  });
  const r = await handleBarcodeLookup({ ...deps, uid: 'u1', code: BARCODE });
  assert.equal(r.ok, false);
  assert.match(r.message, /今日条码查询次数已用完/);
  assert.equal(fetched, false);
});
