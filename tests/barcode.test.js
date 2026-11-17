import test from 'node:test';
import assert from 'node:assert/strict';
import barcode from '../HealthyDiet/cloudfunctions/api-diet/barcode.js';

test('normalizeBarcode：合法 EAN-13 / EAN-8 / UPC-A 通过', () => {
  assert.equal(barcode.normalizeBarcode('4006381333931'), '4006381333931');
  assert.equal(barcode.normalizeBarcode(' 96385074 '), '96385074');
  assert.equal(barcode.normalizeBarcode('036000291452'), '036000291452');
});

test('normalizeBarcode：校验位错、长度不对、非数字一律拒绝', () => {
  assert.equal(barcode.normalizeBarcode('4006381333932'), '');
  assert.equal(barcode.normalizeBarcode('1234567'), '');
  assert.equal(barcode.normalizeBarcode('123456789012345'), '');
  assert.equal(barcode.normalizeBarcode('40063813339a1'), '');
  assert.equal(barcode.normalizeBarcode(''), '');
  assert.equal(barcode.normalizeBarcode(null), '');
});

test('isBarcodeShape：只判 8–14 位数字，不校验校验位', () => {
  assert.equal(barcode.isBarcodeShape('4006381333932'), true);
  assert.equal(barcode.isBarcodeShape('12345678'), true);
  assert.equal(barcode.isBarcodeShape('1234567'), false);
  assert.equal(barcode.isBarcodeShape('123456789012345'), false);
  assert.equal(barcode.isBarcodeShape('40063813339a1'), false);
});

test('buildOffProductUrl：带全部字段与 json=true', () => {
  const url = barcode.buildOffProductUrl('4006381333931');
  assert.ok(url.startsWith('https://world.openfoodfacts.org/api/v2/product/4006381333931'));
  assert.ok(url.includes('json=true'));
  for (const f of ['product_name_zh', 'serving_quantity', 'nutriments', 'image_front_url']) {
    assert.ok(url.includes(f), `缺少字段 ${f}`);
  }
});

test('mapOffProduct：营养/份量/单位/中文名正确映射', () => {
  const r = barcode.mapOffProduct({
    code: '4006381333931',
    product_name: 'Milch',
    product_name_zh: '纯牛奶',
    brands: 'TestBrand',
    quantity: '1L',
    serving_quantity: '250',
    serving_quantity_unit: 'ml',
    image_front_url: 'https://img.example/milk.jpg',
    nutriments: {
      'energy-kcal_100g': '64',
      proteins_100g: '3.3',
      carbohydrates_100g: '4.8',
      fat_100g: '3.6',
    },
  }, '4006381333931');
  assert.equal(r.ok, true);
  assert.equal(r.food.name, '纯牛奶');
  assert.equal(r.food.unit, 'ml');
  assert.equal(r.food.baseG, 250);
  assert.deepEqual(r.food.per100, { kcal: 64, protein: 3.3, carb: 4.8, fat: 3.6 });
  assert.equal(r.food.kcal, 160);          // 64 × 250 / 100
  assert.equal(r.food.protein, 8.3);        // 3.3 × 2.5 = 8.25 → 8.3
  assert.equal(r.food.id, 'off_4006381333931');
  assert.equal(r.food.source, 'off');
  assert.equal(r.food.verify, false);
});

test('mapOffProduct：缺营养/缺名返回明确 reason', () => {
  const noNutrition = barcode.mapOffProduct({
    code: '4006381333931', product_name: 'X', nutriments: { proteins_100g: 1 },
  }, '4006381333931');
  assert.equal(noNutrition.ok, false);
  assert.equal(noNutrition.reason, 'nutrition');

  const noName = barcode.mapOffProduct({
    code: '4006381333931',
    nutriments: { 'energy-kcal_100g': 100, proteins_100g: 1, carbohydrates_100g: 1, fat_100g: 1 },
  }, '4006381333931');
  assert.equal(noName.ok, false);
  assert.equal(noName.reason, 'name');
});

test('mapOffProduct：只有 kJ 时按 4.184 折算 kcal', () => {
  const r = barcode.mapOffProduct({
    code: '4006381333931',
    product_name: '只填 kJ 的商品',
    nutriments: { energy_100g: 418.4, proteins_100g: 1, carbohydrates_100g: 1, fat_100g: 1 },
  }, '4006381333931');
  assert.equal(r.ok, true);
  assert.equal(r.food.per100.kcal, 100);
});

test('mapOffProduct：能量与宏量明显不自洽时打 verify', () => {
  const r = barcode.mapOffProduct({
    code: '4006381333931',
    product_name: '怪数据',
    nutriments: { 'energy-kcal_100g': 900, proteins_100g: 1, carbohydrates_100g: 1, fat_100g: 1 },
  }, '4006381333931');
  assert.equal(r.ok, true);
  assert.equal(r.food.verify, true);
});

test('parseOffResponse：200+status0、404、200 正常、5xx 分别归类', () => {
  const nf = barcode.parseOffResponse(200, { status: 0, status_verbose: 'product not found' }, '4006381333931');
  assert.equal(nf.ok, false);
  assert.equal(nf.found, false);
  assert.equal(nf.reason, 'not_found');

  assert.equal(barcode.parseOffResponse(404, null, '4006381333931').reason, 'not_found');
  assert.equal(barcode.parseOffResponse(503, null, '4006381333931').reason, 'http');

  const good = barcode.parseOffResponse(200, {
    status: 1,
    product: {
      code: '4006381333931',
      product_name: '纯牛奶',
      nutriments: { 'energy-kcal_100g': 64, proteins_100g: 3.3, carbohydrates_100g: 4.8, fat_100g: 3.6 },
    },
  }, '4006381333931');
  assert.equal(good.ok, true);
  assert.equal(good.found, true);
  assert.equal(good.food.name, '纯牛奶');
});

test('customFoodRow：按 grams 反推 per100，字段与搜索行同形', () => {
  const row = barcode.customFoodRow({
    _id: 'abc', name: '自制酸奶', kcal: 150, grams: 200, unit: 'g',
    protein: 6, carb: 10, fat: 5, emoji: '🥛', barcode: '4006381333931',
  });
  assert.equal(row.id, 'cf_abc');
  assert.equal(row.per100.kcal, 75);
  assert.equal(row.per100.protein, 3);
  assert.equal(row.baseG, 200);
  assert.equal(row.barcode, '4006381333931');
  assert.equal(row.source, 'custom');
});

test('parseCnIdentity：成功返回商品身份，限流/未收录/HTTP 错误分类', () => {
  const ok = barcode.parseCnIdentity(200, {
    code: 0,
    data: {
      found: true, name: '君乐宝纯牛奶', brand: '君乐宝',
      manufacturer: '君乐宝乳业集团股份有限公司', spec: '250毫升',
      category: '牛奶（耐储存）',
    },
  });
  assert.equal(ok.found, true);
  assert.equal(ok.identity.name, '君乐宝纯牛奶');
  assert.equal(ok.identity.spec, '250毫升');

  assert.equal(barcode.parseCnIdentity(200, { code: 4029 }).reason, 'rate_limit');
  assert.equal(barcode.parseCnIdentity(200, { code: 0, data: { found: false } }).reason, 'not_found');
  assert.equal(barcode.parseCnIdentity(500, null).reason, 'http');
  assert.equal(barcode.parseCnIdentity(200, { code: 0, data: { found: true, name: '' } }).reason, 'name');
});

test('isCacheFresh：30 天内新鲜，超期或缺失为旧', () => {
  const now = Date.now();
  assert.equal(barcode.isCacheFresh({ updatedAt: now - 1000 }, now), true);
  assert.equal(barcode.isCacheFresh({ updatedAt: now - barcode.kOffCacheTtlMs - 1 }, now), false);
  assert.equal(barcode.isCacheFresh({}, now), false);
  assert.equal(barcode.isCacheFresh(null, now), false);
});
