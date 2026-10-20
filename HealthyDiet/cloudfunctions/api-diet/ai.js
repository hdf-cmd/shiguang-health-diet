/* M13：拍照识菜的纯逻辑（与数据库/网络无关，node --test 可直接覆盖）。 */
const kAiScanDailyLimit = 50;
const kAiImageMaxChars = 280000;
const kAiImagePrefix = /^data:image\/(jpeg|png|webp);base64,/;
const kConfidences = ['high', 'medium', 'low'];

function parseModelJson(text) {
  if (typeof text !== 'string') return null;
  const s = text.trim();
  const fenced = s.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const body = fenced ? fenced[1] : s;
  const start = body.indexOf('{');
  const end = body.lastIndexOf('}');
  if (start === -1 || end <= start) return null;
  try {
    const obj = JSON.parse(body.slice(start, end + 1));
    return obj && typeof obj === 'object' && !Array.isArray(obj) ? obj : null;
  } catch (e) {
    return null;
  }
}

function normalizePer100(p) {
  if (!p || typeof p !== 'object') return null;
  const num = (v) => (typeof v === 'number' && isFinite(v) ? v : null);
  const kcal = num(p.kcal), protein = num(p.protein), carb = num(p.carb), fat = num(p.fat);
  if (kcal === null || protein === null || carb === null || fat === null) return null;
  /* 1 位小数用 Math.round(v*10)/10：toFixed(1) 在 7.35 这类值上按二进制实际值截成 7.3，不符“四舍五入”口径。 */
  const round1 = (v) => Math.round(v * 10) / 10;
  return { kcal: Math.round(kcal), protein: round1(protein), carb: round1(carb), fat: round1(fat) };
}

function energyDeviation(per100) {
  const kcal = per100.kcal || 0;
  const calc = 4 * per100.protein + 4 * per100.carb + 9 * per100.fat;
  return Math.abs(calc - kcal) / Math.max(kcal, 1);
}

function validateScanResult(obj) {
  if (!obj || typeof obj !== 'object') return { ok: false, reason: 'shape' };
  const dish = typeof obj.dish === 'string' ? obj.dish.trim().slice(0, 30) : '';
  if (!dish) return { ok: false, reason: 'dish' };
  const per100 = normalizePer100(obj.per100);
  if (!per100) return { ok: false, reason: 'shape' };
  if (per100.kcal < 0 || per100.kcal > 900) return { ok: false, reason: 'range' };
  for (const k of ['protein', 'carb', 'fat']) {
    if (per100[k] < 0 || per100[k] > 100) return { ok: false, reason: 'range' };
  }
  if (energyDeviation(per100) > 0.25) return { ok: false, reason: 'energy' };
  const confidence = kConfidences.indexOf(obj.confidence) > -1 ? obj.confidence : 'low';
  const note = typeof obj.note === 'string' ? obj.note.trim().slice(0, 80) : '';
  return { ok: true, dish, confidence, per100, note };
}

module.exports = {
  kAiScanDailyLimit, kAiImageMaxChars, kAiImagePrefix,
  parseModelJson, normalizePer100, energyDeviation, validateScanResult,
};
