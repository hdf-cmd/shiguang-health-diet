/* 条码查询路由（可注入依赖，tests/barcode-route.test.js 覆盖）。
 *
 * 顺序：用户自定义绑定 → OFF 全局缓存 → OFF 实时。只有实时请求计每日配额；
 * 缓存/自定义命中不消耗。 */
const { normalizeBarcode, customFoodRow, isCacheFresh } = require("../barcode");

async function handleBarcodeLookup({
  uid,
  code,
  db,
  profiles,
  getOrCreateProfile,
  today,
  dailyLimit,
  fetchOffProduct,
  readOffCache,
  writeOffCache,
  fetchIdentity,
  writeIdentityCache,
  now = Date.now,
}) {
  const barcode = normalizeBarcode(code);
  if (!barcode) return { ok: false, message: "条码格式不正确" };

  // 1) 用户自己给某个自定义食物绑过这个条码：用户数据优先
  try {
    const own = await db.collection("custom_foods").where({ uid, barcode }).limit(1).get();
    if (own.data && own.data[0]) {
      return { ok: true, found: true, source: "custom", barcode, food: customFoodRow(own.data[0]) };
    }
  } catch (e) {
    console.log("BARCODE_CUSTOM_ERR", e && e.message ? String(e.message).slice(0, 120) : "");
  }

  // 2) 全局 OFF 缓存（30 天内直接返回）
  const cached = await readOffCache(barcode);
  if (cached && cached.food && isCacheFresh(cached, now())) {
    return { ok: true, found: true, source: "cache", barcode, food: cached.food };
  }
  // 只有商品身份、没有营养的缓存（国内条码库）：同样 30 天有效
  if (cached && cached.identity && isCacheFresh({ updatedAt: cached.identityAt || 0 }, now())) {
    return { ok: true, found: true, source: "cn-name", barcode, product: cached.identity };
  }

  // 3) 配额：只在实际查 OFF 前扣
  const prof = await getOrCreateProfile(uid);
  const d = today();
  const used = prof.barcodeDate === d ? (Number(prof.barcodeCount) || 0) : 0;
  if (used >= dailyLimit) {
    return { ok: false, message: "今日条码查询次数已用完（" + dailyLimit + " 次）" };
  }
  await profiles.where({ uid }).update({
    barcodeDate: d, barcodeCount: used + 1, updatedAt: Date.now(),
  });

  // 4) 实时 OFF
  const r = await fetchOffProduct(barcode);
  if (r.ok && r.found) {
    await writeOffCache(barcode, r.food);
    return {
      ok: true, found: true, source: "off", barcode, food: r.food,
      quota: { used: used + 1, limit: dailyLimit },
    };
  }

  /* OFF 明确「没这条 / 营养不全」→ 有旧缓存就给旧缓存（stale），
     否则查国内条码库拿商品身份；网络/5xx 也先回旧缓存。 */
  const notFound = r.found === false &&
    ["not_found", "nutrition", "name"].indexOf(r.reason) > -1;
  if (cached && cached.food) {
    return { ok: true, found: true, source: "cache", stale: true, barcode, food: cached.food };
  }

  const identity = await fetchIdentity(barcode);
  if (identity && identity.found) {
    await writeIdentityCache(barcode, identity.identity);
    return {
      ok: true, found: true, source: "cn-name", barcode,
      product: identity.identity,
      quota: { used: used + 1, limit: dailyLimit },
    };
  }

  const identityBusy = identity && ["network", "http", "rate_limit"].indexOf(identity.reason) > -1;
  const offBusy = r.reason === "network" || r.reason === "http";
  const busy = identityBusy || offBusy;
  if (notFound) {
    return {
      ok: true, found: false, barcode, reason: r.reason,
      message: busy ? "条码服务繁忙，请拍营养表或手动添加" : "条码未收录",
    };
  }
  return {
    ok: true, found: false, barcode,
    message: busy
      ? "条码服务暂时不可用，请拍营养表或手动添加"
      : "条码未收录，请拍营养表或手动添加",
  };
}

module.exports = { handleBarcodeLookup };
