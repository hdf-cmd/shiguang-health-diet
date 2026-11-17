/* 条形码链路纯逻辑：校验位、OFF 请求地址、OFF 商品 → 本应用食物结构。
 * 零依赖，tests/barcode.test.js 用 node --test 直接覆盖。
 *
 * 口径与客户端 barcode_check_digit 一致：EAN-8 / UPC-A / EAN-13 / GTIN-14
 * 共用 Modulo-10；只有 8/12/13/14 位纯数字才算合法条码。 */

const kAllowedLengths = new Set([8, 12, 13, 14]);
const kDigits = /^\d+$/;

/* OFF v2 只返回请求里点名的字段；少点一个，对应数据永远拿不到。 */
const kOffFields = [
  'code',
  'product_name',
  'product_name_zh',
  'product_name_en',
  'brands',
  'quantity',
  'product_quantity',
  'serving_quantity',
  'serving_quantity_unit',
  'serving_size',
  'image_front_url',
  'image_front_thumb_url',
  'image_url',
  'nutriments',
  'url',
];

const kOffCacheTtlMs = 30 * 24 * 60 * 60 * 1000; // 30 天
const kOffProductUrlBase = 'https://world.openfoodfacts.org/api/v2/product/';

function normalizeBarcode(raw) {
  const s = String(raw == null ? '' : raw).trim();
  if (!kDigits.test(s) || !kAllowedLengths.has(s.length)) return '';
  const digits = s.split('').map(ch => ch.charCodeAt(0) - 48);
  let sum = 0;
  for (let i = digits.length - 2, w3 = true; i >= 0; i--, w3 = !w3) {
    sum += digits[i] * (w3 ? 3 : 1);
  }
  const expected = (10 - (sum % 10)) % 10;
  return expected === digits[digits.length - 1] ? s : '';
}

/* 只做格式判断（8–14 位数字），不做校验位——给「绑条码」这类允许人工补录的
 * 入口用；查 OFF 的主链路必须走 normalizeBarcode。 */
function isBarcodeShape(raw) {
  const s = String(raw == null ? '' : raw).trim();
  return kDigits.test(s) && s.length >= 8 && s.length <= 14;
}

function buildOffProductUrl(barcode) {
  const url = new URL(kOffProductUrlBase + encodeURIComponent(barcode));
  url.searchParams.set('fields', kOffFields.join(','));
  url.searchParams.set('json', 'true');
  return url.toString();
}

function toNumber(value) {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value !== 'string') return null;
  const n = Number(value.replace(',', '.'));
  return Number.isFinite(n) ? n : null;
}

const round1 = v => Math.round(v * 10) / 10;

function brandsToString(value) {
  if (Array.isArray(value)) {
    return value.map(x => String(x == null ? '' : x).trim()).filter(Boolean).join(', ');
  }
  return String(value == null ? '' : value).trim();
}

function unitFromServingText(text) {
  const s = String(text || '').toLowerCase();
  if (/\bml\b|\bcl\b|\bdl\b|\bl\b/.test(s)) return 'ml';
  if (/\bg\b/.test(s)) return 'g';
  return '';
}

function normalizeUnit(raw) {
  const s = String(raw == null ? '' : raw).trim().toLowerCase();
  if (s === 'g') return 'g';
  if (s === 'ml' || s === 'cl' || s === 'dl' || s === 'l') return 'ml';
  return '';
}

function per100FromNutriments(n) {
  if (!n || typeof n !== 'object') return null;
  let kcal = toNumber(n['energy-kcal_100g']);
  // 不少商品只填了 kJ（energy_100g），没有 kcal 字段；1 kcal = 4.184 kJ。
  if (kcal === null) {
    const kj = toNumber(n.energy_100g);
    if (kj !== null) kcal = kj / 4.184;
  }
  const protein = toNumber(n.proteins_100g);
  const carb = toNumber(n.carbohydrates_100g);
  const fat = toNumber(n.fat_100g);
  if (kcal === null || protein === null || carb === null || fat === null) return null;
  if (kcal < 0 || kcal > 900) return null;
  if (protein < 0 || protein > 100 || carb < 0 || carb > 100 || fat < 0 || fat > 100) return null;
  return {
    kcal: Math.round(kcal),
    protein: round1(protein),
    carb: round1(carb),
    fat: round1(fat),
  };
}

/* 4P+4C+9F 与标称热量差太多时仍然返回（OFF 数据由志愿者填，纤维/酒精/糖醇
 * 都会让公式偏离），但打上 verify 标记，客户端在复核行提示用户看一眼。 */
function atwaterDeviation(per100) {
  const calc = 4 * per100.protein + 4 * per100.carb + 9 * per100.fat;
  return Math.abs(calc - per100.kcal) / Math.max(per100.kcal, 1);
}

function emojiFor(name) {
  const n = String(name || '').toLowerCase();
  const map = [
    ['西兰', '🥦'], ['番茄', '🍅'], ['黄瓜', '🥒'], ['土豆', '🥔'], ['红薯', '🍠'], ['玉米', '🌽'],
    ['鸡', '🍗'], ['鸭', '🍗'], ['牛', '🥩'], ['猪', '🥩'], ['肉', '🥩'], ['鱼', '🐟'], ['虾', '🍤'], ['蟹', '🦀'],
    ['蛋', '🥚'], ['米', '🍚'], ['饭', '🍚'], ['面', '🍜'], ['粉', '🍜'], ['饺', '🥟'], ['馒', '🥟'], ['包', '🥟'],
    ['菜', '🥬'], ['苹果', '🍎'], ['香蕉', '🍌'], ['橙', '🍊'], ['西瓜', '🍉'], ['草莓', '🍓'], ['蓝莓', '🫐'],
    ['牛油果', '🥑'], ['葡萄', '🍇'], ['桃', '🍑'], ['梨', '🍐'],
    ['酸奶', '🥛'], ['奶', '🥛'], ['豆浆', '🥛'], ['奶酪', '🧀'], ['咖啡', '☕'], ['茶', '🍵'], ['可乐', '🥤'], ['奶茶', '🧋'],
    ['汉堡', '🍔'], ['披萨', '🍕'], ['薯条', '🍟'], ['面包', '🍞'], ['吐司', '🍞'], ['蛋糕', '🍰'], ['沙拉', '🥗'], ['汤', '🍲'], ['粥', '🥣'],
  ];
  for (const [k, v] of map) if (n.includes(k)) return v;
  return '🍽️';
}

/* OFF 商品 → 本应用食物行。返回 {ok:true, food} 或 {ok:false, reason}。
 *
 * food 字段与 /foods/search 的行同形：列表直接用 kcal（按 baseG 份量），
 * 「按克加」弹层用 per100。额外带 barcode/source/verify，供客户端标来源。 */
function mapOffProduct(product, barcode) {
  if (!product || typeof product !== 'object') return { ok: false, reason: 'shape' };
  const code = String(product.code || barcode || '').trim();
  if (!normalizeBarcode(code)) return { ok: false, reason: 'barcode' };

  const name =
    String(product.product_name_zh || '').trim() ||
    String(product.product_name || '').trim() ||
    String(product.product_name_en || '').trim();
  if (!name) return { ok: false, reason: 'name' };

  const per100 = per100FromNutriments(product.nutriments);
  if (!per100) return { ok: false, reason: 'nutrition' };

  const unit =
    normalizeUnit(product.serving_quantity_unit) ||
    unitFromServingText(product.serving_size) ||
    unitFromServingText(product.quantity) ||
    'g';

  const servingQty = toNumber(product.serving_quantity);
  const productQty = toNumber(product.product_quantity);
  const servingTextQty = toNumber(String(product.serving_size || '').match(/(\d+(?:[.,]\d+)?)\s*(?:g|ml|cl|dl|l)\b/i)?.[1]);
  let baseG = 100;
  if (servingQty !== null && servingQty > 0 && servingQty <= 5000) baseG = Math.round(servingQty);
  else if (servingTextQty !== null && servingTextQty > 0 && servingTextQty <= 5000) baseG = Math.round(servingTextQty);
  else if (productQty !== null && productQty > 0 && productQty <= 5000) baseG = Math.round(productQty);

  const brands = brandsToString(product.brands);
  const quantity = String(product.quantity || '').trim();
  const kcal = Math.round((per100.kcal * baseG) / 100);
  const protein = round1((per100.protein * baseG) / 100);
  const carb = round1((per100.carb * baseG) / 100);
  const fat = round1((per100.fat * baseG) / 100);
  const metaParts = ['Open Food Facts'];
  if (brands) metaParts.push(brands);
  metaParts.push(`每 100${unit} · 1 份 ${baseG}${unit}`);
  if (quantity) metaParts.push(quantity);

  return {
    ok: true,
    food: {
      id: 'off_' + code,
      name,
      meta: metaParts.join(' · '),
      kcal,
      emoji: emojiFor(name),
      image: String(product.image_front_url || product.image_front_thumb_url || product.image_url || ''),
      unit,
      baseG,
      protein,
      carb,
      fat,
      per100,
      barcode: code,
      source: 'off',
      sourceUrl: String(product.url || ''),
      verify: atwaterDeviation(per100) > 0.35,
    },
  };
}

/* 自定义食物文档 → 搜索行同形。与 index.js searchFoods 里的自定义分支同口径：
 * doc.kcal 是「doc.grams 这一份」的热量，per100 由它反推。 */
function customFoodRow(doc) {
  if (!doc || typeof doc !== 'object') return null;
  const name = String(doc.name || '').trim();
  if (!name) return null;
  const unit = doc.unit === 'ml' ? 'ml' : 'g';
  const g = Math.max(0, Number(doc.grams) || 0);
  const per100 = g > 0 ? {
    kcal: Math.round((Number(doc.kcal) || 0) * 100 / g),
    protein: round1((Number(doc.protein) || 0) * 100 / g),
    carb: round1((Number(doc.carb) || 0) * 100 / g),
    fat: round1((Number(doc.fat) || 0) * 100 / g),
  } : null;
  return {
    id: 'cf_' + String(doc._id || ''),
    name,
    meta: doc.portion ? '自定义 · ' + doc.portion : '自定义 · 每 100' + unit,
    kcal: Number(doc.kcal) || 0,
    emoji: doc.emoji || emojiFor(name),
    image: doc.image || '',
    unit,
    baseG: g || 100,
    protein: Number(doc.protein) || 0,
    carb: Number(doc.carb) || 0,
    fat: Number(doc.fat) || 0,
    per100,
    barcode: String(doc.barcode || ''),
    source: 'custom',
  };
}

/* OFF 响应 → 商品或明确的「没查到」。OFF 对未知条码会回 HTTP 200 + status 0
 * 且没有 product，不能只看状态码。 */
function parseOffResponse(status, payload, barcode) {
  if (status === 404) return { ok: false, found: false, reason: 'not_found' };
  if (status !== 200) return { ok: false, found: false, reason: 'http', status };
  if (!payload || typeof payload !== 'object') return { ok: false, found: false, reason: 'shape' };
  if (Number(payload.status) === 0 || !payload.product) {
    return { ok: false, found: false, reason: 'not_found' };
  }
  const mapped = mapOffProduct(payload.product, barcode);
  if (!mapped.ok) return { ok: false, found: false, reason: mapped.reason };
  return { ok: true, found: true, food: mapped.food };
}

function isCacheFresh(doc, now) {
  if (!doc || typeof doc !== 'object') return false;
  const at = Number(doc.updatedAt || doc.fetchedAt || 0);
  return at > 0 && now - at < kOffCacheTtlMs;
}

module.exports = {
  kAllowedLengths,
  kOffCacheTtlMs,
  kOffFields,
  normalizeBarcode,
  isBarcodeShape,
  buildOffProductUrl,
  per100FromNutriments,
  mapOffProduct,
  customFoodRow,
  parseOffResponse,
  isCacheFresh,
  emojiFor,
};
