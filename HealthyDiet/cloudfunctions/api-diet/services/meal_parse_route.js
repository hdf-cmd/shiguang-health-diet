/* 描述一餐路由（可注入依赖，tests/meal-route.test.js 覆盖）。
 *
 * 模型只抽食物名与份量；营养一律来自命中库。厂商顺序：自带 → 内置 DeepSeek。
 * 服务端总预算 20s，客户端 25s；每轮只拿剩余预算。 */
const {
  mealParseUserMessage,
  buildMealParseMessages,
  validateMealItems,
  rankMealMatches,
  dropUnstatedUnits,
  alignStatedUnits,
} = require("../ai_meal");
const { providerErrorMessage } = require("../ai");

async function handleMealParse({
  uid,
  body,
  profiles,
  getOrCreateProfile,
  today,
  dailyLimit,
  resolveAiChannels,
  callChat,
  parseModelJson,
  searchFoods,
  builtinKey,
  now = Date.now,
}) {
  const text = String(body.text || "").trim().slice(0, 500);
  if (text.length < 2) return { ok: false, message: mealParseUserMessage("too_short") };
  const meal = ["breakfast", "lunch", "dinner", "snack"].indexOf(body.meal) > -1 ? body.meal : "";
  const resolved = resolveAiChannels(body.provider, builtinKey);
  if (!resolved.channels.length) return { ok: false, message: resolved.message };

  let counted = false;
  let quota;
  let lastStatus = 0;
  let sawInvalid = false;
  let sawNetwork = false;
  const deadline = now() + 20000;

  channels:
  for (const channel of resolved.channels) {
    let result = null;
    for (let attempt = 0; attempt < 2 && !result; attempt++) {
      const remaining = deadline - now();
      if (remaining < 1500) break channels;
      /* 配额只在内置通道计数，且一次请求只计一次（重试/降级不重复扣）。 */
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
        buildMealParseMessages(text, attempt > 0),
        channel.target,
        channel.logTag,
        Math.min(12000, remaining),
      );
      lastStatus = r.status;
      if (r.status === 0) sawNetwork = true;
      /* 401/403/429 重试必败或只会加重，直接换下一个通道。 */
      if (r.status === 401 || r.status === 403 || r.status === 429) break;
      const parsed = parseModelJson(r.text);
      if (!parsed) {
        sawInvalid = true;
        console.log(channel.logTag, "MEAL_PARSE_FAIL", String(r.text || "").length);
        continue;
      }
      const v = validateMealItems(parsed);
      if (v.ok) {
        result = {
          ...v,
          items: alignStatedUnits(dropUnstatedUnits(v.items, text), text),
        };
      } else {
        sawInvalid = true;
        console.log(channel.logTag, "MEAL_INVALID", v.reason);
      }
    }
    if (!result) continue;

    /* 每条并发查一次现有食物库，只附 top-3 候选；查库失败不阻断整批，
       该行以未命中返回，客户端提供「按菜名估算 / 手动添加」。 */
    let hiddenFoods = [];
    try {
      const prof = await getOrCreateProfile(uid);
      hiddenFoods = Array.isArray(prof.hiddenFoods) ? prof.hiddenFoods : [];
    } catch (e) {
      console.log("MEAL_PROFILE_ERR", e && e.message ? String(e.message).slice(0, 80) : "");
    }
    const items = await Promise.all(result.items.map(async item => {
      let matches = [];
      try {
        const rows = await searchFoods(item.query, uid, meal, hiddenFoods);
        matches = rankMealMatches(rows, item.query, 3);
      } catch (e) {
        console.log("MEAL_MATCH_ERR", e && e.message ? String(e.message).slice(0, 80) : "");
      }
      return { ...item, match: matches[0] || null, matches };
    }));
    return {
      ok: true,
      items,
      channel: channel.isCustom ? "custom" : "deepseek",
      quota,
    };
  }

  if (lastStatus && lastStatus !== 200 && lastStatus !== 0) {
    return { ok: false, message: providerErrorMessage(lastStatus) };
  }
  if (sawNetwork) return { ok: false, message: "识别服务连接超时，请重试" };
  if (sawInvalid) return { ok: false, message: mealParseUserMessage("shape") };
  return { ok: false, message: resolved.customError || "识别服务未配置" };
}

module.exports = { handleMealParse };
