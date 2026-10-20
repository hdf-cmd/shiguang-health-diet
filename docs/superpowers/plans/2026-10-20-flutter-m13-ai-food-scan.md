# M13 AI 拍照识菜 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 拍照/选图 → DeepSeek 识别出菜名与每 100g 营养 → 用户输克数确认 → 一并写入食物库（带照片）并记入当餐。

**Architecture:** 客户端压图后把 dataURL 发给云函数 `POST /ai/food-scan`；云函数调 `deepseek-flash` 并做服务端校验（范围 + 能量一致性 + 重试一次）；客户端确认页实时按克数换算；保存时 `POST /foods/custom/upsert` 按菜名写入食物库，再走现有乐观记账。key 只存云函数环境变量。

**Tech Stack:** Flutter 3.47 / Riverpod / Dio；Node 18 云函数（原生 fetch，无新依赖）；`node --test`；`deepseek-flash`。

**Spec:** `docs/superpowers/specs/2026-10-20-flutter-m13-ai-food-scan-design.md`

## Global Constraints

- 版本号：`2.8.0+20800`（Task 8 统一改）
- `DEEPSEEK_API_KEY` 只放云函数环境变量；**不进仓库、不打日志、不在对话里回显**
- 图片字符上限统一 `280000`（`kMaxDataUrlChars`），服务端同口径
- 每人每天识别上限 `50` 次（`kAiScanDailyLimit`）
- 云函数**不新增 npm 依赖**（Node 18 自带 fetch）
- 不改 H5 线（`js/`、`HealthyDiet/app/src/main/assets/web/` 一律不动）
- 提交按老大八步流程逐批等指令；计划里的 commit 步骤只是示范提交信息
- TDD：每条新行为先见红，再实现

---

### Task 1: 云函数纯逻辑 `ai.js`

**Files:**
- Create: `HealthyDiet/cloudfunctions/api-diet/ai.js`
- Test: `tests/ai-scan.test.js`

**Interfaces:**
- Produces:
  - `parseModelJson(text: string): object|null`
  - `normalizePer100(p): {kcal:int, protein:number, carb:number, fat:number}|null`
  - `energyDeviation(per100): number`（0 表示完全吻合）
  - `validateScanResult(obj): {ok:true, dish, confidence, per100, note} | {ok:false, reason:'shape'|'dish'|'range'|'energy'}`
  - 常量 `kAiScanDailyLimit=50`、`kAiImageMaxChars=280000`、`kAiImagePrefix`（正则）

- [ ] **Step 1: 写失败测试** `tests/ai-scan.test.js`

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import ai from '../HealthyDiet/cloudfunctions/api-diet/ai.js';

const good = { dish: '蒜薹鸡块', confidence: 'high',
  per100: { kcal: 156, protein: 8.6, carb: 7.4, fat: 9.8 }, note: '偏油' };

test('parseModelJson：纯 JSON / 围栏 / 前后寒暄 / 坏 JSON', () => {
  assert.equal(ai.parseModelJson('{"a":1}').a, 1);
  assert.equal(ai.parseModelJson('```json\n{"a":1}\n```').a, 1);
  assert.equal(ai.parseModelJson('好的，结果如下：{"a":1} 以上。').a, 1);
  assert.equal(ai.parseModelJson('不是 JSON'), null);
  assert.equal(ai.parseModelJson(null), null);
});

test('normalizePer100：kcal 取整、三大营养素 1 位小数；缺项返回 null', () => {
  assert.deepEqual(ai.normalizePer100({ kcal: 155.6, protein: 8.64, carb: 7.35, fat: 9.81 }),
    { kcal: 156, protein: 8.6, carb: 7.4, fat: 9.8 });
  assert.equal(ai.normalizePer100({ kcal: 100 }), null);
});

test('energyDeviation：4P+4C+9F 与热量之差的比例', () => {
  const d = ai.energyDeviation({ kcal: 100, protein: 10, carb: 10, fat: 4.84 }); // 4*10+4*10+9*4.84=123.56
  assert.ok(d > 0.23 && d < 0.24);
});

test('validateScanResult：合法通过，confidence 非法降为 low', () => {
  const v = ai.validateScanResult(good);
  assert.equal(v.ok, true);
  assert.equal(v.dish, '蒜薹鸡块');
  assert.equal(v.confidence, 'high');
  assert.equal(ai.validateScanResult({ ...good, confidence: 'sure' }).confidence, 'low');
});

test('validateScanResult：dish 空、数值越界、能量不自洽分别拒绝', () => {
  assert.equal(ai.validateScanResult({ ...good, dish: '  ' }).reason, 'dish');
  assert.equal(ai.validateScanResult({ ...good, per100: { ...good.per100, kcal: 901 } }).reason, 'range');
  assert.equal(ai.validateScanResult({ ...good, per100: { ...good.per100, protein: 101 } }).reason, 'range');
  assert.equal(ai.validateScanResult({ ...good, per100: { kcal: 300, protein: 1, carb: 1, fat: 1 } }).reason, 'energy');
});

test('常量口径', () => {
  assert.equal(ai.kAiScanDailyLimit, 50);
  assert.equal(ai.kAiImageMaxChars, 280000);
  assert.equal(ai.kAiImagePrefix.test('data:image/jpeg;base64,AAA'), true);
  assert.equal(ai.kAiImagePrefix.test('data:text/plain;base64,AAA'), false);
});
```

- [ ] **Step 2: 跑测试确认红**

Run: `node --test tests/ai-scan.test.js`
Expected: FAIL（模块不存在 / 函数未定义）

- [ ] **Step 3: 实现 `ai.js`**

```js
/* M13：拍照识菜的纯逻辑（与数据库/网络无关，node --test 可直接覆盖）。 */
const kAiScanDailyLimit = 50;
const kAiImageMaxChars = 280000;
const kAiImagePrefix = /^data:image\/(jpeg|png|webp);base64,/;
const kConfidences = ["high", "medium", "low"];

function parseModelJson(text) {
  if (typeof text !== "string") return null;
  const s = text.trim();
  const fenced = s.match(/```(?:json)?\s*([\s\S]*?)```/i);
  const body = fenced ? fenced[1] : s;
  const start = body.indexOf("{");
  const end = body.lastIndexOf("}");
  if (start === -1 || end <= start) return null;
  try {
    const obj = JSON.parse(body.slice(start, end + 1));
    return obj && typeof obj === "object" && !Array.isArray(obj) ? obj : null;
  } catch (e) {
    return null;
  }
}

function normalizePer100(p) {
  if (!p || typeof p !== "object") return null;
  const num = (v) => (typeof v === "number" && isFinite(v) ? v : null);
  const kcal = num(p.kcal), protein = num(p.protein), carb = num(p.carb), fat = num(p.fat);
  if (kcal === null || protein === null || carb === null || fat === null) return null;
  const r1 = (v) => Math.round(v * 10) / 10; // toFixed(1) 对 7.35 得 7.3（二进制误差），四舍五入必须走 *10→round
  return { kcal: Math.round(kcal), protein: r1(protein), carb: r1(carb), fat: r1(fat) };
}

function energyDeviation(per100) {
  const kcal = per100.kcal || 0;
  const calc = 4 * per100.protein + 4 * per100.carb + 9 * per100.fat;
  return Math.abs(calc - kcal) / Math.max(kcal, 1);
}

function validateScanResult(obj) {
  if (!obj || typeof obj !== "object") return { ok: false, reason: "shape" };
  const dish = typeof obj.dish === "string" ? obj.dish.trim().slice(0, 30) : "";
  if (!dish) return { ok: false, reason: "dish" };
  const per100 = normalizePer100(obj.per100);
  if (!per100) return { ok: false, reason: "shape" };
  if (per100.kcal < 0 || per100.kcal > 900) return { ok: false, reason: "range" };
  for (const k of ["protein", "carb", "fat"]) {
    if (per100[k] < 0 || per100[k] > 100) return { ok: false, reason: "range" };
  }
  if (energyDeviation(per100) > 0.25) return { ok: false, reason: "energy" };
  const confidence = kConfidences.indexOf(obj.confidence) > -1 ? obj.confidence : "low";
  const note = typeof obj.note === "string" ? obj.note.trim().slice(0, 80) : "";
  return { ok: true, dish, confidence, per100, note };
}

module.exports = {
  kAiScanDailyLimit, kAiImageMaxChars, kAiImagePrefix,
  parseModelJson, normalizePer100, energyDeviation, validateScanResult,
};
```

- [ ] **Step 4: 跑测试确认绿**

Run: `node --test tests/ai-scan.test.js` → 6 pass。再跑 `npm test` 确认全量 104 绿。

- [ ] **Step 5: 提交**

```bash
git add HealthyDiet/cloudfunctions/api-diet/ai.js tests/ai-scan.test.js
git commit -m "feat(m13): 识菜结果解析与校验纯逻辑（node --test 6 条）"
```

---

### Task 2: 云函数两条路由

**Files:**
- Modify: `HealthyDiet/cloudfunctions/api-diet/index.js`（顶部 require + 认证守卫后插入路由 + `callDeepSeek` 帮助函数）

**Interfaces:**
- Consumes: Task 1 的 `parseModelJson / validateScanResult / kAiScanDailyLimit / kAiImageMaxChars / kAiImagePrefix`
- Produces: `POST /ai/food-scan`、`POST /foods/custom/upsert` 两个路由

- [ ] **Step 1: 顶部接入纯逻辑**

```js
const { parseModelJson, validateScanResult, kAiScanDailyLimit, kAiImageMaxChars, kAiImagePrefix } = require("./ai");
```

- [ ] **Step 2: 加 DeepSeek 调用与提示词（放在 `handle` 之前）**

```js
const DEEPSEEK_URL = "https://api.deepseek.com/chat/completions";
const AI_SYSTEM_PROMPT = [
  "你是中文菜品营养估算器。",
  "看图识别图中最主要的一道菜（若有多样，取占比最大的）。",
  "估计可食部每 100g 的热量与三大营养素（不计骨头、餐具、包装）。",
  "只输出一个 JSON 对象，不要 markdown、不要解释，格式：",
  '{"dish":"菜名","confidence":"high|medium|low","per100":{"kcal":0,"protein":0,"carb":0,"fat":0},"note":"一句话说明"}'
].join("\n");

async function callDeepSeek(apiKey, imageDataUrl, strict) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 12000);
  try {
    const resp = await fetch(DEEPSEEK_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: "Bearer " + apiKey },
      signal: controller.signal,
      body: JSON.stringify({
        model: "deepseek-flash",
        temperature: 0.2,
        max_tokens: 300,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: AI_SYSTEM_PROMPT },
          {
            role: "user",
            content: [
              { type: "text", text: strict
                  ? "上一次结果不合法。请严格按 JSON 输出，并保证 4P+4C+9F 与热量相差不超过 25%。"
                  : "请识别这道菜。" },
              { type: "image_url", image_url: { url: imageDataUrl } }
            ]
          }
        ]
      })
    });
    if (!resp.ok) return null;
    const data = await resp.json();
    const msg = data && data.choices && data.choices[0] && data.choices[0].message;
    return (msg && msg.content) || null;
  } catch (e) {
    return null;
  } finally {
    clearTimeout(timer);
  }
}
```

- [ ] **Step 3: 插入 `/ai/food-scan` 路由（必须在 `if (!uid) return 401` 之后，建议紧跟 `/foods/custom` POST 之前）**

```js
/* M13：拍照识菜。图片只用于识别，不落库。 */
if (path === "/ai/food-scan" && method === "POST") {
  const apiKey = process.env.DEEPSEEK_API_KEY || "";
  if (!apiKey) return { ok: false, message: "识别服务未配置" };
  const image = String(body.image || "");
  if (!kAiImagePrefix.test(image) || image.length > kAiImageMaxChars) {
    return { ok: false, message: "图片格式不支持或过大" };
  }
  const prof = await getOrCreateProfile(uid);
  const d = today();
  const used = prof.aiScanDate === d ? (Number(prof.aiScanCount) || 0) : 0;
  if (used >= kAiScanDailyLimit) {
    return { ok: false, message: "今日识别次数已用完（" + kAiScanDailyLimit + " 次）" };
  }
  // 先计数再调用：失败也占一次，防止坏图反复刷成本
  await profiles.where({ uid }).update({ aiScanDate: d, aiScanCount: used + 1, updatedAt: Date.now() });
  let result = null;
  for (let attempt = 0; attempt < 2 && !result; attempt++) {
    const text = await callDeepSeek(apiKey, image, attempt > 0);
    const parsed = parseModelJson(text);
    if (!parsed) continue;
    const v = validateScanResult(parsed);
    if (v.ok) result = v;
  }
  if (!result) return { ok: false, message: "没认出来，换张更清楚的图或手动填写" };
  return {
    ok: true, dish: result.dish, confidence: result.confidence,
    per100: result.per100, note: result.note,
    quota: { used: used + 1, limit: kAiScanDailyLimit }
  };
}
```

- [ ] **Step 4: 插入 `/foods/custom/upsert` 路由（紧跟 `/foods/custom` POST 之后）**

```js
/* M13：按菜名 upsert（与内置库同名则不写库，只回 skipped）。 */
if (path === "/foods/custom/upsert" && method === "POST") {
  const name = String(body.name || "").trim().slice(0, 60);
  const kcal = Math.max(0, Math.round(Number(body.kcal) || 0));
  if (!name || !kcal) return { ok: false, message: "请填写食物名称和热量" };
  const grams = Math.max(0, Math.round(Number(body.grams) || 0));
  const unit = body.unit === "ml" ? "ml" : "g";
  const p0 = Math.max(0, Number(body.protein) || 0);
  const c0 = Math.max(0, Number(body.carb) || 0);
  const f0 = Math.max(0, Number(body.fat) || 0);
  const meals = Array.isArray(body.meals)
    ? body.meals.map(String).filter(m => ["breakfast", "lunch", "dinner", "snack"].indexOf(m) > -1).slice(0, 4)
    : [];
  const img = String(body.image || "");
  if (img && (!kAiImagePrefix.test(img) || img.length > kAiImageMaxChars)) {
    return { ok: false, message: "图片格式不支持或过大" };
  }
  const fields = {
    kcal, grams, unit, meals,
    protein: +p0.toFixed(1), carb: +c0.toFixed(1), fat: +f0.toFixed(1),
    portion: String(body.portion || (grams ? grams + unit : "1 份")).slice(0, 60),
    emoji: String(body.emoji || "") || emojiFor(name),
    image: img,
    updatedAt: Date.now()
  };
  const emoji = fields.emoji;
  const found = await db.collection("custom_foods").where({ uid, name }).limit(1).get();
  if (found.data && found.data[0]) {
    const patch = { ...fields };
    delete patch.meals; // 更新时保留已有餐次标签（扫码没有归类意图）
    await db.collection("custom_foods").doc(found.data[0]._id).update(patch);
    return { ok: true, id: found.data[0]._id, updated: true, emoji };
  }
  if (BUILTIN_FOODS.some(f => f.name === name)) {
    return { ok: true, skipped: "builtin", emoji };
  }
  const added = await db.collection("custom_foods").add({ uid, name, ...fields, createdAt: Date.now() });
  return { ok: true, id: added.id, created: true, emoji };
}
```

- [ ] **Step 5: 语法检查**

Run: `cd HealthyDiet/cloudfunctions/api-diet && node --check index.js && node --check ai.js`
Expected: 无输出（通过）。路由本身本地不可测（依赖目录无 node_modules），由 Task 8 部署闸真调用验收。

- [ ] **Step 6: 提交**

```bash
git add HealthyDiet/cloudfunctions/api-diet/index.js
git commit -m "feat(m13): 云函数 /ai/food-scan 与 /foods/custom/upsert（key 走环境变量，服务端校验+限流）"
```

---

### Task 3: ApiClient 可选超时 + HealthApi 两个方法

**Files:**
- Modify: `ShiguangFlutter/lib/data/api_client.dart:80-167`
- Modify: `ShiguangFlutter/lib/data/health_api.dart`（自定义食物段附近）
- Test: `ShiguangFlutter/test/data/api_client_test.dart`

**Interfaces:**
- Produces:
  - `ApiClient.call(..., Duration? timeout)` / `callValue(..., Duration? timeout)`
  - `HealthApi.scanFood(String imageDataUrl) → Future<Map<String,dynamic>>`（30s）
  - `HealthApi.upsertCustomFood(Map<String,dynamic> food) → Future<Map<String,dynamic>>`

- [ ] **Step 1: 写失败测试**（追加到 `api_client_test.dart`）

```dart
test('可选超时：显式传 30s 透传到 Dio，未传沿用默认 15s', () async {
  final adapter = RecordingAdapter();
  final dio = ApiClient.defaultDio()..httpClientAdapter = adapter;
  final api = ApiClient(tokenStore: InMemoryTokenStore(), dio: dio);

  await api.call('/ai/food-scan',
      method: 'POST', body: {'image': 'x'}, timeout: const Duration(seconds: 30));
  expect(adapter.requests.single.receiveTimeout, const Duration(seconds: 30));

  await api.call('/user/profile');
  expect(adapter.requests.last.receiveTimeout, const Duration(seconds: 15));
});
```

- [ ] **Step 2: 跑测试确认红**

Run: `flutter test test/data/api_client_test.dart --plain-name "可选超时"`
Expected: 编译失败（`timeout` 参数不存在）

- [ ] **Step 3: 实现**

`call` / `callValue` 增加可选参数并透传；`_doFetch` 增加可选 `Duration? timeout`，在 `Options()` 里设置：

```dart
options: Options(
  contentType: 'application/json',
  responseType: ResponseType.plain,
  headers: {'Authorization': 'Bearer $bearer'},
  receiveTimeout: timeout,
  sendTimeout: timeout,
  validateStatus: (_) => true,
),
```

（为 null 时 Dio 沿用 BaseOptions 的 15s，行为不变。）

`health_api.dart` 新增：

```dart
/// 拍照识菜（M13）：云函数调 DeepSeek，返回 {dish,confidence,per100,note,quota}
Future<Map<String, dynamic>> scanFood(String imageDataUrl) => _client.call(
      '/ai/food-scan',
      method: 'POST',
      body: <String, dynamic>{'image': imageDataUrl},
      timeout: const Duration(seconds: 30),
    );

/// 扫码入库（M13）：按菜名 upsert，回 {ok,id|skipped,emoji}
Future<Map<String, dynamic>> upsertCustomFood(Map<String, dynamic> food) =>
    _client.call('/foods/custom/upsert', method: 'POST', body: food);
```

- [ ] **Step 4: 跑测试确认绿 + 契约面不破**

Run: `flutter test test/data/`、`dart analyze`
Expected: 全绿、0 issue（`contract_test.dart` 不受影响——新路由不进 fixture，原因见 spec §7）

- [ ] **Step 5: 提交**

```bash
git add ShiguangFlutter/lib/data/api_client.dart ShiguangFlutter/lib/data/health_api.dart ShiguangFlutter/test/data/api_client_test.dart
git commit -m "feat(m13): ApiClient 支持按请求覆盖超时；HealthApi 增 scanFood/upsertCustomFood"
```

---

### Task 4: 选图参数化（识别用 512）

**Files:**
- Modify: `ShiguangFlutter/lib/features/common/image_pick.dart`
- Test: `ShiguangFlutter/test/data/`（新建 `image_pick_test.dart`）

**Interfaces:**
- Produces:
  - `classifyPicked(String? dataUrl, {int maxChars = kMaxDataUrlChars})`
  - `pickCompressedImageDataUrl(ImageSource source, {int maxDim = 256, int quality = 82, int maxChars = kMaxDataUrlChars})`
  - 常量 `kScanImageMaxDim = 512`、`kScanImageQuality = 75`

- [ ] **Step 1: 写失败测试**

```dart
test('classifyPicked 支持自定义上限；默认上限不变', () {
  final s = 'data:image/jpeg;base64,' + 'A' * 100;
  expect(classifyPicked(s, maxChars: 50).failure, ImagePickFailure.tooLargeEncoded);
  expect(classifyPicked(s).failure, isNull);
  expect(classifyPicked(null).dataUrl, isNull);
});

test('扫码参数常量：比默认大、质量更低', () {
  expect(kScanImageMaxDim, 512);
  expect(kScanImageQuality, 75);
  expect(kScanImageMaxDim, greaterThan(256));
  expect(kScanImageQuality, lessThan(82));
});
```

- [ ] **Step 2: 跑测试确认红**（函数签名/常量不存在）

- [ ] **Step 3: 实现**

`classifyPicked` 增加 `maxChars` 参数并按参数比较；`pickCompressedImageDataUrl` 增加 `maxDim/quality/maxChars` 并传给 `ImagePicker().pickImage(maxWidth: maxDim, maxHeight: maxDim, imageQuality: quality)`；新增两个常量。

- [ ] **Step 4: 跑 `flutter test test/data/image_pick_test.dart` + 全量 `flutter test test/custom_food_sheet_test.dart`**
Expected: 绿（既有调用不传参 → 默认值不变）

- [ ] **Step 5: 提交**

```bash
git add ShiguangFlutter/lib/features/common/image_pick.dart ShiguangFlutter/test/data/image_pick_test.dart
git commit -m "feat(m13): 选图支持自定义尺寸/质量/字符上限（扫码用 512px）"
```

---

### Task 5: `scanPortionTotals` 纯函数

**Files:**
- Create: `ShiguangFlutter/lib/features/record/food_scan_math.dart`
- Test: `ShiguangFlutter/test/record/food_scan_math_test.dart`

**Interfaces:**
- Produces: `({int kcal, double protein, double carb, double fat}) scanPortionTotals(Map<String, num> per100, int grams)`

- [ ] **Step 1: 写失败测试**

```dart
test('按克数等比换算：kcal 取整、三大营养素 1 位小数', () {
  final t = scanPortionTotals({'kcal': 156, 'protein': 8.6, 'carb': 7.4, 'fat': 9.8}, 200);
  expect(t.kcal, 312);
  expect(t.protein, 17.2);
  expect(t.carb, 14.8);
  expect(t.fat, 19.6);
});

test('非整百克数与 0g 边界', () {
  final t = scanPortionTotals({'kcal': 156, 'protein': 8.6, 'carb': 7.4, 'fat': 9.8}, 137);
  expect(t.kcal, 214); // 213.72
  expect(scanPortionTotals({'kcal': 156, 'protein': 8.6, 'carb': 7.4, 'fat': 9.8}, 0).kcal, 0);
});
```

- [ ] **Step 2: 跑测试确认红**

- [ ] **Step 3: 实现**

```dart
double _round1(double v) => (v * 10).round() / 10;

({int kcal, double protein, double carb, double fat}) scanPortionTotals(
    Map<String, num> per100, int grams) {
  final scale = grams / 100;
  num at(String k) => per100[k] ?? 0;
  return (
    kcal: (at('kcal') * scale).round(),
    protein: _round1((at('protein') * scale).toDouble()),
    carb: _round1((at('carb') * scale).toDouble()),
    fat: _round1((at('fat') * scale).toDouble()),
  );
}
```

- [ ] **Step 4: 跑测试确认绿**

- [ ] **Step 5: 提交**

```bash
git add ShiguangFlutter/lib/features/record/food_scan_math.dart ShiguangFlutter/test/record/food_scan_math_test.dart
git commit -m "feat(m13): 扫码按克数换算纯函数（scanPortionTotals）"
```

---

### Task 6: 确认表单 `FoodScanSheet` + 保存链

**Files:**
- Create: `ShiguangFlutter/lib/features/record/food_scan_sheet.dart`
- Modify: `ShiguangFlutter/lib/features/record/food_scan_math.dart`（舍入改用 `domain/js_compat.dart` 的 `jsRound/jsFixed1`，与 `domain/portion.dart` 同口径）+ 其测试补断言
- Modify: `ShiguangFlutter/test/stubs/stub_health_api.dart`（新增 `scanFood/upsertCustomFood` 桩与调用记录）
- Test: `ShiguangFlutter/test/food_scan_sheet_test.dart`

**Interfaces:**
- Consumes: Task 3 `HealthApi.upsertCustomFood`、Task 5 `scanPortionTotals`、`invalidateFoodLibrary(WidgetRef)`、`recordControllerProvider.addRecord`
- Produces:
  - `class FoodScanSheet extends ConsumerStatefulWidget`，构造：`{required String date, required String meal, required Map<String,dynamic> scan, required String initialImage, bool recordMeal = true}`
  - Key：`scan-name / scan-grams / scan-kcal / scan-protein / scan-carb / scan-fat / scan-total / scan-save / scan-pick-photo / scan-remove-photo`
  - `openFoodScanFlow(BuildContext, WidgetRef, {required String date, required String meal, bool recordMeal = true})`（Task 7 用）
  - `final scanImagePickProvider = Provider<ScanImagePick>(...)`

- [ ] **Step 1: 扩展桩**（`StubHealthApi`）

```dart
/// M13 识菜桩：可编程返回体 + 调用记录
Map<String, dynamic> scanResult = {
  'ok': true, 'dish': '蒜薹鸡块', 'confidence': 'high',
  'per100': {'kcal': 156, 'protein': 8.6, 'carb': 7.4, 'fat': 9.8},
  'note': '', 'quota': {'used': 1, 'limit': 50},
};
ApiException? scanError;
Map<String, dynamic>? lastUpsertBody;
Map<String, dynamic> upsertResult = {'ok': true, 'id': 'new_1', 'created': true, 'emoji': '🍗'};
ApiException? upsertError;
@override
Future<Map<String, dynamic>> scanFood(String imageDataUrl) async {
  scanCalls++;
  if (scanError != null) throw scanError!;
  return scanResult;
}

@override
Future<Map<String, dynamic>> upsertCustomFood(Map<String, dynamic> food) async {
  lastUpsertBody = Map.of(food);
  if (upsertError != null) throw upsertError!;
  return upsertResult;
}

int scanCalls = 0;
```

记账侧不用新桩：既有 `StubHealthApi.addBodies` 已经按次收集 `addFoodRecord` 的入参，用例直接断言它。

- [ ] **Step 2: 写失败测试** `test/food_scan_sheet_test.dart`

```dart
testWidgets('预填模型建议；改克数实时改汇总', (tester) async {
  final api = StubHealthApi();
  await pumpScan(tester, api);
  expect(find.text('蒜薹鸡块'), findsOneWidget);
  expect(find.textContaining('312 kcal'), findsOneWidget); // 200g 默认
  await tester.enterText(find.byKey(const Key('scan-grams')), '150');
  await tester.pump();
  expect(find.textContaining('234 kcal'), findsOneWidget);
});

testWidgets('低置信度提示', (tester) async {
  final api = StubHealthApi()..scanResult = {...StubHealthApi().scanResult, 'confidence': 'low'};
  await pumpScan(tester, api);
  expect(find.textContaining('识别把握不大'), findsOneWidget);
});

testWidgets('保存：upsert 入参按份、记录带同一张入库照片', (tester) async {
  final api = StubHealthApi();
  await pumpScan(tester, api);
  await tester.tap(find.byKey(const Key('scan-save')));
  await tester.pumpAndSettle();
  expect(api.lastUpsertBody!['name'], '蒜薹鸡块');
  expect(api.lastUpsertBody!['grams'], 200);
  expect(api.lastUpsertBody!['kcal'], 312);
  expect(api.lastUpsertBody!['portion'], '200g');
  expect(api.lastUpsertBody!['image'], startsWith('data:image/jpeg;base64,'));
  expect(api.addBodies.single['kcal'], 312);
  expect(api.addBodies.single['image'], api.lastUpsertBody!['image']);
});

testWidgets('内置同名：不入库但照常记账', (tester) async {
  final api = StubHealthApi()..upsertResult = {'ok': true, 'skipped': 'builtin', 'emoji': '🍚'};
  await pumpScan(tester, api);
  await tester.tap(find.byKey(const Key('scan-save')));
  await tester.pump();
  expect(api.addBodies, hasLength(1));
});

testWidgets('入库失败：停留表单并显示错误', (tester) async {
  final api = StubHealthApi()..upsertError = ApiException('网络异常');
  await pumpScan(tester, api);
  await tester.tap(find.byKey(const Key('scan-save')));
  await tester.pumpAndSettle();
  expect(find.textContaining('保存失败'), findsOneWidget);
  expect(api.addBodies, isEmpty);
});

testWidgets('食物库入口（recordMeal=false）只入库不记账', (tester) async {
  final api = StubHealthApi();
  await pumpScan(tester, api, recordMeal: false);
  await tester.tap(find.byKey(const Key('scan-save')));
  await tester.pumpAndSettle();
  expect(api.lastUpsertBody, isNotNull);
  expect(api.addBodies, isEmpty);
});
```

`pumpScan` 助手：`ProviderScope(overrides:[healthApiProvider.overrideWithValue(api), foodFreqStoreProvider.overrideWithValue(_MemStore())], child: MaterialApp(home: Scaffold(body: FoodScanSheet(date:'2026-10-25', meal:'lunch', scan: api.scanResult, initialImage: 'data:image/jpeg;base64,AAA', recordMeal: recordMeal))))`。

- [ ] **Step 3: 实现 `FoodScanSheet`**

要点（完整实现按此结构）：
- State：`_name`（预填 `scan['dish']`）、`_grams=200`、四个 per100 的 `TextEditingController`、`_image=initialImage`、`_busy`、`_error`。
- `_totalText`：`scanPortionTotals` → `'这份 ≈ ${t.kcal} kcal · 蛋白 ${t.protein}g / 碳水 ${t.carb}g / 脂肪 ${t.fat}g'`，挂在 key `scan-total`。
- `confidence == 'low'` → 黄字提示（key 不必须，文案含「识别把握不大」）。
- `scan-pick-photo`：`ref.read(scanImagePickProvider)(ImageSource.gallery)`（测试覆盖 provider）；
  `scan-remove-photo`：`_image=''`。
- `_save()`：
  1. 校验菜名非空、克数 1–2000；
  2. `final t = scanPortionTotals(per100, grams);`
  3. `final r = await api.upsertCustomFood({name, kcal:t.kcal, grams, unit:'g', meals:<String>[], protein:t.protein, carb:t.carb, fat:t.fat, portion:'${grams}g', image:_image});`
  4. `r['skipped']=='builtin'` → toast「内置库已有「X」，本条未重复入库」；否则 `ref.read(swrCacheProvider).invalidate('foods.custom'); invalidateFoodLibrary(ref);`
  5. `recordMeal` → `try { await ref.read(recordControllerProvider).addRecord(widget.date, {date, meal, name, portion:'${grams}g', kcal:t.kcal, emoji: r['emoji'] ?? '🍽️', image:_image, protein:t.protein, carb:t.carb, fat:t.fat}, pendingKey:'scan:$name_${DateTime.now().millisecondsSinceEpoch}'); } catch(_) { toast('已入库，本餐记入失败'); }`
  6. `Navigator.pop(true)`
  - 失败（upsert 抛错）→ `setState(_error='保存失败：${e.message}')`，停留。
- toast 用 `SheetToast`（复制 `food_lib_sheet.dart:216-231` 的 `_toast` 模式）。

- [ ] **Step 4: 跑测试确认绿 + `dart analyze`**

Run: `flutter test test/food_scan_sheet_test.dart`、`dart analyze`
Expected: 6 绿、0 issue

- [ ] **Step 5: 提交**

```bash
git add ShiguangFlutter/lib/features/record/food_scan_sheet.dart ShiguangFlutter/test/food_scan_sheet_test.dart ShiguangFlutter/test/stubs/stub_health_api.dart
git commit -m "feat(m13): 识菜确认表单（可改名/克数/营养/入库照片）+ 保存链六条判据"
```

---

### Task 7: 两处入口接线

**Files:**
- Modify: `ShiguangFlutter/lib/features/record/search_sheet.dart`（搜索框右侧加 📷，key `sheet-scan-open`）
- Modify: `ShiguangFlutter/lib/features/profile/food_lib_sheet.dart`（底部按钮行加「📷 拍照添加」，key `lib-scan-add`）
- Modify: `ShiguangFlutter/lib/features/record/food_scan_sheet.dart`（`openFoodScanFlow`：选来源 → 识别中 → 成功开表单 / 失败弹提示）
- Test: `ShiguangFlutter/test/food_scan_entry_test.dart`

**Interfaces:**
- Produces: `Future<void> openFoodScanFlow(BuildContext context, WidgetRef ref, {required String date, required String meal, bool recordMeal = true})`
- `scanImagePickProvider` 在测试里被覆盖成固定返回 `data:image/jpeg;base64,AAA`

- [ ] **Step 1: 写失败测试**

```dart
testWidgets('记一笔弹层有 📷 入口，点后开确认表单', (tester) async {
  final api = StubHealthApi();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      healthApiProvider.overrideWithValue(api),
      foodFreqStoreProvider.overrideWithValue(memStore()),
      scanImagePickProvider.overrideWithValue((_) async =>
          (dataUrl: 'data:image/jpeg;base64,AAA', failure: null)),
    ],
    child: const MaterialApp(home: Scaffold(body: SearchSheet(date: '2026-10-25', meal: 'lunch'))),
  ));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('sheet-scan-open')));
  await tester.pumpAndSettle();          // 来源选择 → 选「相册」→ 识别 → 表单
  await tester.tap(find.text('从相册选'));
  await tester.pumpAndSettle();
  expect(find.byType(FoodScanSheet), findsOneWidget);
});

testWidgets('识别失败弹提示，不打开表单', (tester) async { ... api.scanError = ApiException('网络异常') ... expect(find.byType(FoodScanSheet), findsNothing); expect(find.textContaining('识别失败'), findsOneWidget); });
```

- [ ] **Step 2: 实现 `openFoodScanFlow`**

```dart
Future<void> openFoodScanFlow(BuildContext context, WidgetRef ref,
    {required String date, required String meal, bool recordMeal = true}) async {
  final source = await showDialog<ImageSource>(
    context: context,
    builder: (ctx) => SimpleDialog(
      title: const Text('识菜照片'),
      children: [
        SimpleDialogOption(onPressed: () => Navigator.pop(ctx, ImageSource.camera), child: const Text('拍照')),
        SimpleDialogOption(onPressed: () => Navigator.pop(ctx, ImageSource.gallery), child: const Text('从相册选')),
      ],
    ),
  );
  if (source == null || !context.mounted) return;
  final picked = await ref.read(scanImagePickProvider)(source);
  if (picked.failure == ImagePickFailure.tooLargeEncoded) { /* toast 图片仍过大 */ return; }
  final img = picked.dataUrl;
  if (img == null || !context.mounted) return;
  showDialog<void>(context: context, barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator())); // 识别中
  Map<String, dynamic> scan;
  try {
    scan = await ref.read(healthApiProvider).scanFood(img);
  } catch (e) {
    if (context.mounted) { Navigator.pop(context); /* 关识别中 */ _showScanError(context, e); }
    return;
  }
  if (!context.mounted) return;
  Navigator.pop(context); // 关识别中
  await showShiguangSheet<void>(context, title: '确认食物',
    child: FoodScanSheet(date: date, meal: meal, scan: scan, initialImage: img, recordMeal: recordMeal));
}
```

失败提示用 `showDialog` + 文案「识别失败：{message}」，含「手动填写」按钮 → 打开现有 `openCustomFoodSheet`。

- [ ] **Step 3: 接线两个入口**

- search_sheet 头部 Row：在「＋ 自定义」前插入 `IconButton(key: Key('sheet-scan-open'), icon: Icon(Icons.photo_camera_outlined), onPressed: () => openFoodScanFlow(context, ref, date: widget.date, meal: widget.meal))`。
- food_lib_sheet 底部：把现有单个 FilledButton 包进 `Row`：左「＋ 添加自定义食物」(`lib-add`)、右 `FilledButton.tonal`「📷 拍照添加」(`lib-scan-add`)，两钮 `Expanded`。
  `onPressed` = `openFoodScanFlow(context, ref, date: ref.read(plateDateProvider), meal: 'lunch', recordMeal: false)`。

- [ ] **Step 4: 跑测试确认绿 + 回归**

Run: `flutter test test/food_scan_entry_test.dart test/food_lib_sheet_test.dart test/record/ test/record_flow_test.dart`、`dart analyze`
Expected: 全绿

- [ ] **Step 5: 提交**

```bash
git add ShiguangFlutter/lib/features/record/search_sheet.dart ShiguangFlutter/lib/features/profile/food_lib_sheet.dart ShiguangFlutter/lib/features/record/food_scan_sheet.dart ShiguangFlutter/test/food_scan_entry_test.dart
git commit -m "feat(m13): 记一笔/食物库两处识菜入口接线"
```

---

### Task 8: 收口——版本、全量闸、部署与真机验收

**Files:**
- Modify: `ShiguangFlutter/pubspec.yaml`（`version: 2.8.0+20800`）
- Modify: `CHANGELOG.md`（2.8.0 条目）

- [ ] **Step 1: 版本与日志**

`pubspec.yaml` 改 `2.8.0+20800`；`CHANGELOG.md` 顶部加 `## [2.8.0] - 待发版日期`：新增「拍照识菜」段
（拍照/相册 → AI 识别 → 输克数 → 自动入库带图 + 记一笔；AI 估算可改；每人每天 50 次）。

- [ ] **Step 2: 全量闸（本机）**

```bash
cd ShiguangFlutter && dart analyze && flutter test
cd .. && npm test && npm run lint && npm run check:version
```
Expected：`dart analyze` 0 issue；`flutter test` **≥ 551 绿**（基线 545 + 新增 6）；H5 **≥ 104 绿**；lint 0 error。

- [ ] **Step 3: 部署（需老大令 + 他提供 key）**

1. `manageFunctions updateFunctionCode`（functionRootPath，含 `ai.js`）
2. `updateFunctionConfig`：`envVariables: {DEEPSEEK_API_KEY: "<key>"}`、`timeout: 60`
3. 真调用验收（用一张真实菜品照，老大提供或 `img/foods/` 里的菜图）：
   - 返回 `{ok:true,dish,per100}`；**记录 Duration**（P95 决定是否需要改异步）
   - 连续调用 3 次看 `aiScanCount` 递增；把上限临时改 1 验证文案后改回
   - 老路由：`/diet/records`、`/foods/custom` 正常

- [ ] **Step 4: 打包与真机目检**

按 M11/M12 现成流程：ASCII 沙盒（**必须带 pubspec.lock**）→ `flutter build apk --release --split-per-abi`
→ 验签 `cc7e2dd9…` → `adb install -r` → 目检四条：

| # | 动作 | 期望 |
|---|---|---|
| 1 | 记一笔 → 📷 → 拍照一道菜 | 约 3–10s 出确认页，菜名预填、数值合理 |
| 2 | 改克数 | 汇总热量随克数线性变化 |
| 3 | 换一张本地照片 → 保存 | 食物库出现该条目且**带的是本地那张图**；当日记录 +1 笔 |
| 4 | 食物库 → 📷 拍照添加 → 保存 | 只入库、不产生记录；食物库列表立即有图 |

另测失败面：飞行模式下点 📷 → 提示识别失败且可重试；「没认出来」的图 → 文案正确。

- [ ] **Step 5: 提交**

```bash
git add ShiguangFlutter/pubspec.yaml CHANGELOG.md 食光Flutter-v2.8.0.apk
git commit -m "build: M13 拍照识菜 2.8.0+20800 出包 + 更新日志（真机四条目检通过）"
```

---

## 自审记录

- **Spec 覆盖**：§2.1→Task 2，§2.2→Task 1，§2.3→Task 2，§2.4→Task 2/6，§2.5→Task 3/8，§3.1→Task 7，§3.2→Task 4，§3.3→Task 6，§3.4→Task 6，§3.5→Task 6/7，§4→各任务，§5→Task 8，§6→文档，§7→不做。
- **占位符**：无 TBD/TODO；deploy key 用 `<key>` 占位属安全要求，执行时由老大提供。
- **类型一致**：`scanPortionTotals` 返回记录类型在 Task 5 定义、Task 6 按 `t.kcal/t.protein/...` 使用；`upsertCustomFood` 签名 Task 3 定义、Task 6 调用一致；`ScanImagePick`/`scanImagePickProvider` 在 Task 6 定义、Task 7 使用一致。
