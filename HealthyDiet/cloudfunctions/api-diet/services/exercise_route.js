// services/exercise_route.js
// 运动记录写入（POST /diet/exercises）的幂等层。
// 手环云同步会在重装/多包场景下重复推送同一批运动：客户端带 externalId，
// 服务端按 uid+externalId 查重，已存在直接返回成功（不重复入库）。
const EXTERNAL_ID_MAX = 80;

function normalizeExternalId(value) {
  if (typeof value !== "string") return "";
  const s = value.trim();
  if (!s || s.length > EXTERNAL_ID_MAX) return "";
  return s;
}

/**
 * @param db CloudBase 数据库实例
 * @param uid 用户 id（调用方必须已鉴权）
 * @param body 请求体（date/key/name/emoji/amount/unit/kcal/externalId?）
 * @param today 缺省日期（YYYY-MM-DD）
 * @param now 时间戳（测试注入）
 */
async function addExercise(db, uid, body, today, now = Date.now()) {
  const kcal = Math.max(0, Math.round(Number(body.kcal) || 0));
  if (!kcal) return { ok: false, message: "消耗热量无效" };

  const externalId = normalizeExternalId(body.externalId);
  if (externalId) {
    const dup = await db
      .collection("sg_exercises")
      .where({ uid, externalId })
      .limit(1)
      .get();
    const row = (dup.data || [])[0];
    if (row) {
      return {
        ok: true,
        duplicate: true,
        id: row._id,
        date: row.date,
        key: row.key,
        name: row.name,
        emoji: row.emoji,
        amount: row.amount,
        unit: row.unit,
        kcal: row.kcal,
      };
    }
  }

  const doc = {
    uid,
    date: body.date || today,
    key: String(body.key || "").slice(0, 20),
    name: String(body.name || "运动").slice(0, 60),
    emoji: String(body.emoji || "🏃"),
    amount: Number(body.amount) || 0,
    unit: body.unit === "km" ? "km" : "min",
    kcal,
    createdAt: now,
  };
  if (externalId) doc.externalId = externalId;
  const added = await db.collection("sg_exercises").add(doc);
  return { ok: true, id: added.id, ...doc };
}

/**
 * 拉取指定日期集合内已入库的 externalId（重装/多包后客户端合并去重账本）。
 * dates 最多 31 个，格式非法项忽略。
 */
async function listExistingKeys(db, uid, dates) {
  const clean = (dates || [])
    .filter((d) => typeof d === "string" && /^\d{4}-\d{2}-\d{2}$/.test(d))
    .slice(0, 31);
  if (!clean.length) return [];
  const _ = db.command;
  const res = await db
    .collection("sg_exercises")
    .where({ uid, date: _.in(clean) })
    .limit(1000)
    .get();
  const externalIds = [];
  const signatures = [];
  for (const r of res.data || []) {
    if (typeof r.externalId === "string" && r.externalId) {
      externalIds.push(r.externalId);
    }
    // 旧数据没有 externalId 时按内容签名兜底（date|key|amount|kcal）
    signatures.push(`${r.date}|${r.key}|${r.amount}|${r.kcal}`);
  }
  return { externalIds, signatures };
}

module.exports = { addExercise, listExistingKeys, normalizeExternalId };
