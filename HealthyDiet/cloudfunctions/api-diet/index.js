const cloud = require("@cloudbase/node-sdk");
const crypto = require("crypto");

const app = cloud.init({
  env: cloud.SYMBOL_CURRENT_ENV,
  credentials: require("./tcb_custom_login.json")
});
const auth = app.auth();
const db = app.database();
const _ = db.command;

const GATEWAY_BASE = "https://cloud1-d6g4x9h9m507b429c.api.tcloudbasegateway.com";
/* FATSECRET_REMOVED: 外部食物接口已移除，搜索走内置库+自定义库 */

/* ---------------- 工具 ---------------- */

function today() {
  return new Date().toISOString().slice(0, 10);
}

function callerUid() {
  try {
    const u = auth.getUserInfo();
    if (!u) return "";
    return u.customUserId || u.uid || "";
  } catch (e) {
    return "";
  }
}

function hashPassword(password, salt) {
  return crypto.scryptSync(password, salt, 64).toString("hex");
}

function emojiFor(name) {
  const n = (name || "").toLowerCase();
  const map = [
    ["西兰", "🥦"], ["番茄", "🍅"], ["黄瓜", "🥒"], ["土豆", "🥔"], ["红薯", "🍠"], ["玉米", "🌽"],
    ["鸡", "🍗"], ["鸭", "🍗"], ["牛", "🥩"], ["猪", "🥩"], ["肉", "🥩"], ["鱼", "🐟"], ["虾", "🍤"], ["蟹", "🦀"],
    ["蛋", "🥚"], ["米", "🍚"], ["饭", "🍚"], ["面", "🍜"], ["粉", "🍜"], ["饺", "🥟"], ["馒", "🥟"], ["包", "🥟"],
    ["菜", "🥬"], ["苹果", "🍎"], ["香蕉", "🍌"], ["橙", "🍊"], ["西瓜", "🍉"], ["草莓", "🍓"], ["蓝莓", "🫐"],
    ["牛油果", "🥑"], ["葡萄", "🍇"], ["桃", "🍑"], ["梨", "🍐"],
    ["酸奶", "🥛"], ["奶", "🥛"], ["豆浆", "🥛"], ["奶酪", "🧀"], ["咖啡", "☕"], ["茶", "🍵"], ["可乐", "🥤"], ["奶茶", "🧋"],
    ["汉堡", "🍔"], ["披萨", "🍕"], ["薯条", "🍟"], ["面包", "🍞"], ["吐司", "🍞"], ["蛋糕", "🍰"], ["沙拉", "🥗"], ["汤", "🍲"], ["粥", "🥣"],
  ];
  for (const [k, v] of map) if (n.includes(k)) return v;
  return "🍽️";
}


async function searchFoods(keyword, uid, meal) {
  const results = [];
  const kw = (keyword || "").trim();
  // 3) 内置常见食物库（仍无结果时兜底）
  if (!results.length) {
    for (const f of BUILTIN_FOODS) {
      if ((!kw || f.name.includes(kw)) && (!meal || !f.meals || f.meals.indexOf(meal) > -1)) results.push({ ...f });
    }
  }
  // 3) 自定义食物库
  const where = kw
    ? { uid, name: db.RegExp({ regexp: kw, options: "i" }) }
    : { uid };
  const customs = await db.collection("custom_foods").where(where).limit(20).get();
  for (const doc of customs.data || []) {
    results.push({
      id: "cf_" + doc._id,
      name: doc.name,
      meta: doc.portion ? "自定义 · " + doc.portion : "自定义 · 每 100g",
      kcal: doc.kcal || doc.caloriesPer100g || 0,
      emoji: doc.emoji || emojiFor(doc.name || ""),
      image: doc.image || ""
    });
  }
  return results;
}

async function foodDetail(foodId) {
  // 外部食物接口已移除：按 id 查内置库
  return BUILTIN_FOODS.find(f => f.id === foodId) || null;
}

/* ---------------- 业务处理 ---------------- */

/* 内置常见食物库：FatSecret 未配置时的搜索兜底（kcal 为常见单份热量） */
const BUILTIN_FOODS = [
  // 早餐（protein/carb/fat 单位 g/份，依据中国食物成分表第6版/包装配料表核算）
  { id: "u_01", name: "纯牛奶", meta: "奶类 · 1 盒 250ml", kcal: 175, emoji: "🥛", image: "img/foods/milk.jpg", meals: ["breakfast", "snack"], protein: 8, carb: 12, fat: 9 },
  { id: "u_02", name: "面包", meta: "主食 · 80g", kcal: 256, emoji: "🍞", image: "img/foods/bread.jpg", meals: ["breakfast", "snack"], protein: 7, carb: 44, fat: 4 },
  { id: "u_03", name: "糯玉米", meta: "主食 · 1 根约 250g(可食165g)", kcal: 270, emoji: "🌽", image: "img/foods/corn.jpg", meals: ["breakfast", "snack"], protein: 6, carb: 55, fat: 3 },
  { id: "u_04", name: "煮鸡蛋", meta: "蛋类 · 1 个约 50g", kcal: 78, emoji: "🥚", image: "img/foods/egg.jpg", meals: ["breakfast", "snack"], protein: 7, carb: 1, fat: 5 },
  { id: "u_05", name: "肉包", meta: "主食 · 1 个约 100g", kcal: 230, emoji: "🥟", image: "img/foods/meatbun.jpg", meals: ["breakfast"], protein: 8, carb: 30, fat: 10 },
  // 午餐/晚餐
  { id: "u_06", name: "米饭", meta: "主食 · 1 碗约 150g", kcal: 174, emoji: "🍚", image: "img/foods/rice.jpg", meals: ["lunch", "dinner"], protein: 4, carb: 39, fat: 0, per100: { kcal: 116, protein: 2.6, carb: 25.9, fat: 0.3 }, baseG: 150 },
  { id: "u_07", name: "清炒青菜", meta: "蔬菜 · 1 份约 120g", kcal: 60, emoji: "🥬", image: "img/foods/greens.jpg", meals: ["lunch", "dinner"], protein: 2, carb: 3, fat: 5 },
  { id: "u_08", name: "鸡腿", meta: "禽肉 · 1 个(可食约105g)", kcal: 190, emoji: "🍗", image: "img/foods/chickenleg.jpg", meals: ["lunch", "dinner"], protein: 18, carb: 0, fat: 15 },
  { id: "u_09", name: "鸭腿", meta: "禽肉 · 1 个(可食约105g)", kcal: 240, emoji: "🍗", image: "img/foods/duckleg.jpg", meals: ["lunch", "dinner"], protein: 16, carb: 0, fat: 21 },
  { id: "u_10", name: "芹菜木耳炒蛋", meta: "家常菜 · 1 份约 120g", kcal: 130, emoji: "🍳", image: "img/foods/celeryegg.jpg", meals: ["lunch", "dinner"], protein: 7, carb: 4, fat: 10 },
  { id: "u_11", name: "白切鸡", meta: "禽肉 · 1 份约 120g", kcal: 240, emoji: "🍗", image: "img/foods/whitecut.jpg", meals: ["lunch", "dinner"], protein: 23, carb: 0, fat: 19 },
  { id: "u_12", name: "西兰花炒肉", meta: "家常菜 · 1 份约 130g", kcal: 150, emoji: "🥦", image: "img/foods/broccolipork.jpg", meals: ["lunch", "dinner"], protein: 10, carb: 5, fat: 8 },
  { id: "u_13", name: "胡萝卜炒蛋", meta: "家常菜 · 1 份约 130g", kcal: 140, emoji: "🥕", image: "img/foods/carrotegg.jpg", meals: ["lunch", "dinner"], protein: 7, carb: 7, fat: 9 },
  { id: "u_14", name: "辣椒炒肉", meta: "家常菜 · 1 份约 130g", kcal: 150, emoji: "🌶️", image: "img/foods/chilipork.jpg", meals: ["lunch", "dinner"], protein: 11, carb: 4, fat: 15 },
  { id: "u_15", name: "白切鸭", meta: "禽肉 · 1 份约 140g", kcal: 345, emoji: "🦆", image: "img/foods/whitecutduck.jpg", meals: ["lunch", "dinner"], protein: 22, carb: 0, fat: 28 },
  { id: "u_16", name: "汉堡", meta: "快餐 · 1 个约 200g", kcal: 500, emoji: "🍔", image: "img/foods/burger.jpg", meals: ["lunch", "dinner"], protein: 22, carb: 42, fat: 25 },
  { id: "u_17", name: "鸡块", meta: "快餐 · 3 个约 48g", kcal: 140, emoji: "🍗", image: "img/foods/nuggets.jpg", meals: ["lunch", "dinner"], protein: 7, carb: 8, fat: 9 },
  { id: "u_18", name: "可乐", meta: "饮品 · 200ml", kcal: 86, emoji: "🥤", image: "img/foods/cola.jpg", meals: ["lunch", "dinner"], protein: 0, carb: 21, fat: 0 },
  { id: "u_22", name: "沙县鸭腿饭", meta: "快餐 · 1 份(饭+鸭腿+菜)", kcal: 750, emoji: "🍱", image: "img/foods/shaxian.jpg", meals: ["lunch", "dinner"], protein: 27, carb: 72, fat: 39 },
  { id: "u_23", name: "黄瓜炒火腿肠", meta: "家常菜 · 1 份约 135g", kcal: 167, emoji: "🥒", image: "img/foods/cucumberham.jpg", meals: ["lunch", "dinner"], protein: 7, carb: 10, fat: 11 },
  { id: "u_24", name: "炒西蓝花", meta: "蔬菜 · 1 份约 135g", kcal: 86, emoji: "🥦", image: "img/foods/broccoli.jpg", meals: ["lunch", "dinner"], protein: 3, carb: 5, fat: 6 },
  { id: "u_25", name: "葱姜鸡", meta: "粤菜 · 1 份约 135g", kcal: 266, emoji: "🐔", image: "img/foods/congjiangji.jpg", meals: ["lunch", "dinner"], protein: 23, carb: 3, fat: 18 },
  { id: "u_26", name: "饼干", meta: "零食 · 1 块约 35g", kcal: 152, emoji: "🍪", image: "img/foods/biscuit.jpg", meals: ["breakfast", "snack"], protein: 3.2, carb: 25.1, fat: 4.4, per100: { kcal: 435, protein: 9, carb: 71.7, fat: 12.7 }, baseG: 35 },
  { id: "u_27", name: "泡面", meta: "主食 · 1 桶面饼+配料 128g", kcal: 600, emoji: "🍜", image: "img/foods/cupnoodle.jpg", meals: ["lunch", "dinner"], protein: 10.5, carb: 76.8, fat: 27.8, per100: { kcal: 469, protein: 8.2, carb: 60, fat: 21.7 }, baseG: 128 },
  { id: "u_28", name: "啤酒", meta: "饮品 · 500ml(能量含酒精)", kcal: 215, emoji: "🍺", image: "img/foods/beer.jpg", meals: ["lunch", "dinner", "snack"], protein: 2.5, carb: 18, fat: 0, per100: { kcal: 43, protein: 0.5, carb: 3.6, fat: 0 }, baseG: 500 },
  { id: "u_29", name: "咸鸭蛋", meta: "蛋类 · 1 个约 50g", kcal: 95, emoji: "🥚", image: "img/foods/saltedegg.jpg", meals: ["breakfast", "lunch", "dinner"], protein: 6.4, carb: 3.2, fat: 6.4, per100: { kcal: 190, protein: 12.7, carb: 6.3, fat: 12.7 }, baseG: 50 },
  // 零食/饮品
  { id: "u_19", name: "冰红茶", meta: "饮品 · 500ml", kcal: 190, emoji: "🧋", image: "img/foods/icetea.jpg", meals: ["snack"], protein: 0, carb: 47, fat: 0 },
  { id: "u_20", name: "可乐", meta: "饮品 · 500ml", kcal: 215, emoji: "🥤", image: "img/foods/cola.jpg", meals: ["snack"], protein: 0, carb: 53, fat: 0 },
  { id: "u_21", name: "奶茶", meta: "饮品 · 1 杯约 500ml(5分糖)", kcal: 400, emoji: "🧋", image: "img/foods/milktea.jpg", meals: ["snack"], protein: 6, carb: 62, fat: 14 },
];   // 内置食物库暂空：等用户报常吃的菜后逐条 curated 添加（name/meta/kcal/emoji/image）

const RECOMMENDATIONS = [
  { id: "m_01", name: "牛油果鸡蛋全麦堡", kcal: 368, tag: "早餐 · 10 分钟", emoji: "🥑", macros: { carb: 34, protein: 18, fat: 19 } },
  { id: "m_02", name: "茄汁虾仁烩糙饭", kcal: 412, tag: "晚餐 · 高蛋白", emoji: "🍤", macros: { carb: 46, protein: 32, fat: 10 } },
  { id: "m_03", name: "酸奶燕麦果粒杯", kcal: 295, tag: "加餐 · 免烹饪", emoji: "🥣", macros: { carb: 38, protein: 14, fat: 9 } }
];

async function getOrCreateProfile(uid) {
  const col = db.collection("sg_profiles");
  const found = await col.where({ uid }).limit(1).get();
  if (found.data && found.data[0]) return found.data[0];
  const doc = {
    uid,
    nickname: "食光用户",
    avatarText: "食",
    signature: "把每一餐，记成时光",
    dailyKcal: 1800,
    targetWeight: 55,
    waterMl: 1600,
    heightCm: 165,
    weightKg: 55,
    bmi: 20.2,
    age: 28,
    gender: "female",
    activity: "light",
    deficit: 500,
    createdAt: Date.now()
  };
  await col.add(doc);
  return doc;
}

function profileToClient(p) {
  return {
    id: p.uid,
    nickname: p.nickname,
    avatarText: p.avatarText,
    avatarData: p.avatarData || null,
    signature: p.signature,
    goal: { dailyKcal: p.dailyKcal, targetWeight: p.targetWeight, waterMl: p.waterMl },
    body: {
      heightCm: p.heightCm, weightKg: p.weightKg, bmi: p.bmi,
      age: p.age == null ? 28 : p.age,
      gender: p.gender || "female",
      activity: p.activity || "light",
      deficit: p.deficit == null ? 500 : p.deficit
    }
  };
}

async function handle(path, method, params, body, uid) {
  /* ---- 认证（匿名可调，uid 为空） ---- */
  if (path === "/auth/register" && method === "POST") {
    const username = String(body.username || "").trim().toLowerCase();
    const password = String(body.password || "");
    if (!/^[\u4e00-\u9fa5A-Za-z0-9_]{2,28}$/.test(username)) return { ok: false, message: "用户名需为 2-28 位中文、字母、数字或下划线" };
    if (password.length < 8) return { ok: false, message: "密码至少 8 位" };
    const users = db.collection("app_users");
    const exists = await users.where({ username }).count();
    if (exists.total > 0) return { ok: false, message: "用户名已被占用" };
    const salt = crypto.randomBytes(16).toString("hex");
    await users.add({
      username,
      customUserId: "u_" + crypto.createHash("sha256").update(username).digest("hex").slice(0, 24),   // uid 必须 ASCII（createTicket 不接受中文），用哈希派生
      salt,
      pwdHash: hashPassword(password, salt),
      createdAt: Date.now()
    });
    return { ok: true };
  }

  if (path === "/auth/login" && method === "POST") {
    const username = String(body.username || "").trim().toLowerCase();
    const password = String(body.password || "");
    const res = await db.collection("app_users").where({ username }).limit(1).get();
    const user = res.data && res.data[0];
    if (!user || hashPassword(password, user.salt) !== user.pwdHash) {
      return { ok: false, message: "用户名或密码错误" };
    }
    const ticket = auth.createTicket(user.customUserId, {
      refresh: 3600 * 1000,
      expire: 30 * 24 * 3600 * 1000
    });
    // 用 ticket 换标准 token（服务端直调网关，客户端一次拿到完整登录态）
    const tokenUrl = new URL("/auth/v1/signin/custom", GATEWAY_BASE);
    const resp = await fetch(tokenUrl, {
      method: "POST",
      headers: { "Content-Type": "application/json", "x-device-id": "sg-app-" + user.customUserId },
      body: JSON.stringify({ provider_id: "custom", ticket })
    });
    const token = await resp.json();
    if (!token.access_token) return { ok: false, message: "登录态换取失败" };
    return {
      ok: true,
      token: {
        accessToken: token.access_token,
        refreshToken: token.refresh_token || "",
        expiresIn: token.expires_in || 7200,
        uid: token.sub || user.customUserId
      }
    };
  }

  /* ---- 以下业务接口均需登录（uid 必须存在） ---- */
  if (!uid) return { statusCode: 401, ok: false, message: "未登录" };

  const profiles = db.collection("sg_profiles");

  if (path === "/user/profile" && method === "GET") {
    return profileToClient(await getOrCreateProfile(uid));
  }

  if (path === "/user/profile" && method === "PUT") {
    await getOrCreateProfile(uid);
    const patch = {};
    if (body.nickname) patch.nickname = body.nickname;
    if (body.signature) patch.signature = body.signature;
    const H = Number(body.heightCm), W = Number(body.weightKg);
    if (body.heightCm) patch.heightCm = Math.max(100, Math.min(250, H));
    if (body.weightKg) patch.weightKg = Math.max(30, Math.min(200, W));
    if (patch.heightCm && patch.weightKg) {
      patch.bmi = +(patch.weightKg / Math.pow(patch.heightCm / 100, 2)).toFixed(1);
    }
    if (body.age) patch.age = Math.max(10, Math.min(100, Number(body.age) || 28));
    if (body.gender) patch.gender = body.gender === "male" ? "male" : "female";
    if (body.activity) patch.activity = String(body.activity);
    if (body.deficit) patch.deficit = Number(body.deficit) || 500;
    await profiles.where({ uid }).update({ ...patch, updatedAt: Date.now() });
    return { ok: true };
  }

  /** 上传头像：前端压缩后的 dataURL（max ~200KB），存 profile.avatarData */
  if (path === "/user/avatar" && method === "PUT") {
    const raw = String(body.data || "");
    const m = raw.match(/^data:image\/(png|jpeg|jpg|webp);base64,(.+)$/i);
    if (!m) return { ok: false, message: "头像格式无效，仅支持 png/jpeg/webp" };
    const b64 = m[2];
    if (b64.length > 280000) return { ok: false, message: "头像图片过大，请换一张小图" };
    await getOrCreateProfile(uid);
    await profiles.where({ uid }).update({ avatarData: raw, updatedAt: Date.now() });
    return { ok: true, avatarData: raw };
  }

  if (path === "/user/goal" && method === "PUT") {
    await getOrCreateProfile(uid);
    const patch = { updatedAt: Date.now() };
    if (body.dailyKcal) patch.dailyKcal = Number(body.dailyKcal) || 1800;
    if (body.targetWeight) patch.targetWeight = Number(body.targetWeight) || 55;
    await profiles.where({ uid }).update(patch);
    return { ok: true };
  }

  if (path === "/user/water-goal" && method === "PUT") {
    await getOrCreateProfile(uid);
    const ml = Math.max(800, Math.min(3000, Number(body.waterGoalMl) || 1600));
    await profiles.where({ uid }).update({ waterMl: ml, updatedAt: Date.now() });
    return { ok: true, waterGoalMl: ml };
  }

  if (path === "/user/body-metrics" && method === "GET") {
    const p = await getOrCreateProfile(uid);
    return { heightCm: p.heightCm, weightKg: p.weightKg, bmi: p.bmi };
  }

  /* ---- 运动记录（sg_exercises）：刻意运动单独记，消耗计入当日报销额度 ---- */
  if (path === "/foods/custom" && method === "POST") {
    const name = String(body.name || "").trim().slice(0, 60);
    const kcal = Math.max(0, Math.round(Number(body.kcal) || 0));
    if (!name || !kcal) return { ok: false, message: "请填写食物名称和热量" };
    const doc = {
      uid, name, kcal,
      portion: String(body.portion || "1 份").slice(0, 60),
      emoji: String(body.emoji || "") || emojiFor(name),
      image: String(body.image || "").slice(0, 300000),   // 自定义食物图片（压缩后 dataURL）
      createdAt: Date.now()
    };
    const added = await db.collection("custom_foods").add(doc);
    return { ok: true, id: added.id, ...doc };
  }

  if (path === "/diet/exercises" && method === "GET") {
    const date = params.date || today();
    const res = await db.collection("sg_exercises")
      .where({ uid, date }).orderBy("createdAt", "asc").limit(100).get();
    return (res.data || []).map(r => ({
      id: r._id, key: r.key, name: r.name, emoji: r.emoji,
      amount: r.amount, unit: r.unit, kcal: r.kcal
    }));
  }

  if (path === "/diet/exercises" && method === "POST") {
    const kcal = Math.max(0, Math.round(Number(body.kcal) || 0));
    if (!kcal) return { ok: false, message: "消耗热量无效" };
    const doc = {
      uid,
      date: body.date || today(),
      key: String(body.key || "").slice(0, 20),
      name: String(body.name || "运动").slice(0, 60),
      emoji: String(body.emoji || "🏃"),
      amount: Number(body.amount) || 0,
      unit: body.unit === "km" ? "km" : "min",
      kcal,
      createdAt: Date.now()
    };
    const added = await db.collection("sg_exercises").add(doc);
    return { ok: true, id: added.id, ...doc };
  }

  if (path.startsWith("/diet/exercises/") && method === "DELETE") {
    const id = path.split("/")[3];
    await db.collection("sg_exercises").doc(id).remove();
    return { ok: true };
  }

  if (path === "/diet/summary" && method === "GET") {
    const date = params.date || today();
    const p = await getOrCreateProfile(uid);
    const recs = await db.collection("sg_records").where({ uid, date }).get();
    const sum = { kcal: 0, carb: 0, protein: 0, fat: 0 };
    for (const r of recs.data || []) {
      sum.kcal += r.kcal || 0;
      sum.carb += r.carb || 0;
      sum.protein += r.protein || 0;
      sum.fat += r.fat || 0;
    }
    const w = await db.collection("sg_water").where({ uid, date }).limit(1).get();
    return {
      kcal: sum.kcal,
      target: p.dailyKcal,
      carb: sum.carb,
      protein: sum.protein,
      fat: sum.fat,
      water: (w.data && w.data[0] && w.data[0].cups) || 0
    };
  }

  if (path === "/diet/records" && method === "GET") {
    const date = params.date || today();
    const recs = await db.collection("sg_records")
      .where({ uid, date }).orderBy("createdAt", "asc").limit(100).get();
    return (recs.data || []).map(r => ({
      id: r._id, meal: r.meal, name: r.name, portion: r.portion, kcal: r.kcal, emoji: r.emoji, image: r.image || "", protein: r.protein || 0, carb: r.carb || 0, fat: r.fat || 0
    }));
  }

  if (path === "/diet/records" && method === "POST") {
    const kcal = Math.max(0, Math.round(Number(body.kcal) || 0));
    // 前端只传热量，三大营养素按供能比估算（碳 50% / 蛋白 25% / 脂 25%）
    const doc = {
      uid,
      date: body.date || today(),
      meal: ["breakfast", "lunch", "dinner", "snack"].includes(body.meal) ? body.meal : "snack",
      name: String(body.name || "").slice(0, 60),
      portion: String(body.portion || "").slice(0, 60),
      kcal,
      emoji: body.emoji || "🍽️",
      image: String(body.image || ""),
      carb: body.carb != null ? Math.max(0, Math.round(Number(body.carb))) : Math.round(kcal * 0.5 / 4),
      protein: body.protein != null ? Math.max(0, Math.round(Number(body.protein))) : Math.round(kcal * 0.25 / 4),
      fat: body.fat != null ? Math.max(0, Math.round(Number(body.fat))) : Math.round(kcal * 0.25 / 9),
      createdAt: Date.now()
    };
    const added = await db.collection("sg_records").add(doc);
    return { id: added.id, meal: doc.meal, name: doc.name, portion: doc.portion, kcal, emoji: doc.emoji };
  }

  if (path.startsWith("/diet/records/") && method === "DELETE") {
    const id = path.split("/").pop();
    await db.collection("sg_records").where({ uid, _id: id }).remove();
    return { ok: true };
  }

  if (path === "/diet/water" && method === "POST") {
    const date = body.date || today();
    const delta = Number(body.delta) || 0;
    const col = db.collection("sg_water");
    const found = await col.where({ uid, date }).limit(1).get();
    const current = (found.data && found.data[0]) || null;
    const cups = Math.max(0, Math.min(15, ((current && current.cups) || 0) + delta));
    if (current) {
      await col.doc(current._id).update({ cups });
    } else {
      await col.add({ uid, date, cups });
    }
    return { water: cups };
  }

  if (path === "/foods/search" && method === "GET") {
    return searchFoods(params.keyword || "", uid, params.meal);
  }

  if (path.startsWith("/foods/") && method === "GET") {
    return foodDetail(path.split("/").pop());
  }

  if (path === "/recommend/meals" && method === "GET") {
    return RECOMMENDATIONS;
  }

  if (path === "/report/week" && method === "GET") {
    const offset = Number(params.offset) || 0;
    const p = await getOrCreateProfile(uid);
    // 本周（周一起）7 天日期，offset 往回推周数
    const nowCst = new Date(Date.now() + 8 * 3600000);
    const dow = (nowCst.getUTCDay() + 6) % 7; // 周一=0
    const monday = new Date(Date.now() + 8 * 3600000 - (dow + offset * 7) * 86400000);
    const dates = [];
    for (let i = 0; i < 7; i++) {
      dates.push(new Date(monday.getTime() + i * 86400000).toISOString().slice(0, 10));
    }
    const kcal = [0, 0, 0, 0, 0, 0, 0];
    const carb = [0, 0, 0, 0, 0, 0, 0];
    const protein = [0, 0, 0, 0, 0, 0, 0];
    const fat = [0, 0, 0, 0, 0, 0, 0];
    const recs = await db.collection("sg_records")
      .where({ uid, date: _.in(dates) }).limit(1000).get();
    for (const r of recs.data || []) {
      const i = dates.indexOf(r.date);
      if (i > -1) {
        kcal[i] += r.kcal || 0;
        carb[i] += r.carb || 0;
        protein[i] += r.protein || 0;
        fat[i] += r.fat || 0;
      }
    }
    const dayCount = Math.max(1, kcal.filter(v => v > 0).length);
    const carbTarget = Math.round((p.dailyKcal * 0.5) / 4);
    const proteinTarget = Math.round((p.dailyKcal * 0.25) / 4);
    const fatTarget = Math.round((p.dailyKcal * 0.25) / 9);
    const rate = (sum, t) => Math.min(100, Math.round((sum / dayCount) / t * 100));
    return {
      days: ["一", "二", "三", "四", "五", "六", "日"],
      kcal,
      target: p.dailyKcal,
      rates: {
        carb: rate(carb.reduce((a, b) => a + b, 0), carbTarget),
        protein: rate(protein.reduce((a, b) => a + b, 0), proteinTarget),
        fat: rate(fat.reduce((a, b) => a + b, 0), fatTarget)
      }
    };
  }

  if (path === "/report/month" && method === "GET") {
    const offset = Number(params.offset) || 0;
    const p = await getOrCreateProfile(uid);
    const nowCst = new Date(Date.now() + 8 * 3600000);
    const y = nowCst.getUTCFullYear(), m = nowCst.getUTCMonth() - offset;
    const first = new Date(Date.UTC(y, m, 1));
    const last = new Date(Date.UTC(y, m + 1, 0));
    const startStr = first.toISOString().slice(0, 10);
    const endStr = last.toISOString().slice(0, 10);
    const recs = await db.collection("sg_records")
      .where({ uid, date: _.gte(startStr).and(_.lte(endStr)) }).limit(1000).get();
    const byDate = {};
    const nut = { carb: 0, protein: 0, fat: 0 };
    for (const r of recs.data || []) {
      const d = (byDate[r.date] ||= { kcal: 0, carb: 0, protein: 0, fat: 0 });
      d.kcal += r.kcal || 0; d.carb += r.carb || 0; d.protein += r.protein || 0; d.fat += r.fat || 0;
      nut.carb += r.carb || 0; nut.protein += r.protein || 0; nut.fat += r.fat || 0;
    }
    const daysInMonth = last.getUTCDate();
    const weeks = [], wkcal = [];
    for (let w = 0; w < Math.ceil(daysInMonth / 7); w++) {
      const sDay = w * 7 + 1, eDay = Math.min(daysInMonth, (w + 1) * 7);
      let sum = 0, cnt = 0;
      for (let d = sDay; d <= eDay; d++) {
        const key = new Date(Date.UTC(y, m, d)).toISOString().slice(0, 10);
        if (byDate[key]) { sum += byDate[key].kcal; cnt++; }
      }
      weeks.push("W" + (w + 1));
      wkcal.push(cnt ? Math.round(sum / cnt) : 0);   // 该周记录日均
    }
    const recordedDays = Object.keys(byDate).length;
    const target = p.dailyKcal || 1800;
    const dayTarget = { carb: Math.round(target * 0.5 / 4), protein: Math.round(target * 0.25 / 4), fat: Math.round(target * 0.25 / 9) };
    const rate = (sum, t) => recordedDays ? Math.min(100, Math.round(sum / recordedDays / t * 100)) : 0;
    return {
      weeks, kcal: wkcal, target,
      days: recordedDays,
      total: Object.values(byDate).reduce((a, d) => a + d.kcal, 0),
      rates: { carb: rate(nut.carb, dayTarget.carb), protein: rate(nut.protein, dayTarget.protein), fat: rate(nut.fat, dayTarget.fat) },
      isWeek: false
    };
  }

  /* ---- 每日体重日志（sg_weights）：按天 upsert；今天的记录同步回身体档案 ---- */
  if (path === "/user/weight" && method === "POST") {
    const w = Number(body.weightKg);
    if (!w || w < 20 || w > 300) return { ok: false, message: "请输入有效体重（20–300 kg）" };
    const weightKg = +w.toFixed(1);
    const date = String(body.date || today());
    const col = db.collection("sg_weights");
    const found = await col.where({ uid, date }).limit(1).get();
    if (found.data && found.data[0]) {
      await col.doc(found.data[0]._id).update({ weightKg, updatedAt: Date.now() });
    } else {
      await col.add({ uid, date, weightKg, createdAt: Date.now() });
    }
    let patch = null;
    if (date === today()) {
      const p = await getOrCreateProfile(uid);
      const bmi = +(weightKg / Math.pow((p.heightCm || 165) / 100, 2)).toFixed(1);
      await profiles.where({ uid }).update({ weightKg, bmi, updatedAt: Date.now() });
      patch = { weightKg, bmi };
    }
    return { ok: true, weightKg, date, patch };
  }

  if (path === "/report/weight-trend" && method === "GET") {
    const p = await getOrCreateProfile(uid);
    const logs = await db.collection("sg_weights")
      .where({ uid }).orderBy("date", "asc").limit(30).get();
    const data = logs.data || [];
    if (!data.length) {
      const labels = [];
      for (let i = 6; i >= 0; i--) {
        labels.push(today(-i).slice(5).replace("-", "."));
      }
      return {
        points: [p.weightKg, p.weightKg, p.weightKg, p.weightKg, p.weightKg, p.weightKg, p.weightKg],
        labels
      };
    }
    const recent = data.slice(-7);
    return {
      points: recent.map(d => d.weightKg),
      labels: recent.map(d => d.date.slice(5).replace("-", "."))
    };
  }

  return { ok: false, message: `接口未实现: ${method} ${path}` };
}

/* ---------------- 入口 ---------------- */

exports.main = async (event) => {
  const isHttp = !!(event.httpMethod || event.headers);
  let req = event;
  if (typeof event.body === "string") {
    try {
      req = JSON.parse(event.body);
    } catch (e) {
      req = {};
    }
  }

  try {
    const uid = callerUid();
    const path = String(req.path || "");
    const method = String(req.method || "GET").toUpperCase();
    const params = req.params || {};
    const body = req.body || {};
    const result = await handle(path, method, params, body, uid);
    const status = result && result.statusCode === 401 ? 401 : 200;
    if (isHttp) return json(status, result);
    return result;
  } catch (e) {
    const err = { ok: false, message: e.message || "服务异常" };
    if (isHttp) return json(500, err);
    return err;
  }
};
