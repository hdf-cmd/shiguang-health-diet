/* 营养成分表识别路由（可注入依赖，tests/label-route.test.js 覆盖）。
 * 图片只用于识别，不落库；营养值由用户复核后保存到 custom_foods。 */
const {
  kAiImagePrefix, kAiScanDailyLimit, providerErrorMessage,
} = require("../ai");
const {
  kLabelImageMaxChars, buildLabelScanMessages, validateLabelResult,
} = require("../ai_label");

async function handleNutritionLabel({
  uid,
  body,
  profiles,
  getOrCreateProfile,
  today,
  dailyLimit = kAiScanDailyLimit,
  resolveAiChannels,
  callChat,
  parseModelJson,
  builtinKey,
  now = Date.now,
}) {
  const image = String(body.image || "");
  const hint = String(body.hint || "").trim().slice(0, 30);
  if (!kAiImagePrefix.test(image) || image.length > kLabelImageMaxChars) {
    return { ok: false, message: "图片格式不支持或过大" };
  }

  const resolved = resolveAiChannels(body.provider, builtinKey);
  if (!resolved.channels.length) return { ok: false, message: resolved.message };

  let counted = false;
  let quota;
  let lastStatus = 0;
  let sawInvalid = false;
  let sawNetwork = false;

  for (const channel of resolved.channels) {
    let result = null;
    for (let attempt = 0; attempt < 2 && !result; attempt++) {
      if (!channel.isCustom && !counted) {
        const prof = await getOrCreateProfile(uid);
        const d = today();
        const used = prof.aiScanDate === d ? (Number(prof.aiScanCount) || 0) : 0;
        if (used >= dailyLimit) {
          lastStatus = 429;
          break;
        }
        await profiles.where({ uid }).update({
          aiScanDate: d, aiScanCount: used + 1, updatedAt: now(),
        });
        counted = true;
        quota = { used: used + 1, limit: dailyLimit };
      }
      const r = await callChat(
        channel.apiKey,
        buildLabelScanMessages(image, hint, attempt > 0),
        channel.target,
        channel.logTag,
      );
      lastStatus = r.status;
      if (r.status === 0) sawNetwork = true;
      if (r.status === 401 || r.status === 403 || r.status === 429) break;
      const parsed = parseModelJson(r.text);
      if (!parsed) {
        sawInvalid = true;
        console.log(channel.logTag, "LABEL_PARSE_FAIL", String(r.text || "").length);
        continue;
      }
      const v = validateLabelResult(parsed);
      if (v.ok) result = v;
      else {
        sawInvalid = true;
        console.log(channel.logTag, "LABEL_INVALID", v.reason);
      }
    }
    if (!result) continue;
    return {
      ok: true,
      name: result.name,
      brand: result.brand,
      unit: result.unit,
      servingGrams: result.servingGrams,
      per100: result.per100,
      note: result.note,
      confidence: result.confidence,
      verify: result.verify,
      channel: channel.isCustom ? "custom" : "deepseek",
      quota,
    };
  }

  if (lastStatus && lastStatus !== 200 && lastStatus !== 0) {
    return { ok: false, message: providerErrorMessage(lastStatus) };
  }
  if (sawNetwork) return { ok: false, message: "识别服务连接超时，请重试" };
  if (sawInvalid) return { ok: false, message: "没读出来，拍清楚一点或手动填写" };
  return { ok: false, message: resolved.customError || "识别服务未配置" };
}

module.exports = { handleNutritionLabel };
