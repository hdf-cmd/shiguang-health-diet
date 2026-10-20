# M14 自带 Key + 多厂商识菜 实施计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 用户可在 App 里填自己的 API Key 并选择厂商；识菜时由云函数用该 key 调对应厂商，未配置则回退服务器内置 key。

**Architecture:** key 只存在手机安全存储；每次识菜把 `{id, model, key}` 随请求发给云函数，函数按服务端常量表取 URL、用完即丢；自带 key 不占内置配额。

**Tech Stack:** Flutter 3.47 / Riverpod / flutter_secure_storage；Node 18 云函数（原生 fetch）。

**Spec:** `docs/superpowers/specs/2026-10-20-flutter-m14-byok-multi-provider-design.md`

## Global Constraints

- 版本：`2.9.0+20900`（Task 6 统一改）
- 厂商 URL **只能来自服务端常量表**，不接受客户端传任意 baseUrl（防 SSRF）
- key 只在请求内存里；**不写库、不打日志、不进返回体**；日志只允许 `AI_PROVIDER_HTTP <id> <status>`
- 厂商原始报错不透传；只按状态码翻译固定文案
- 自带 key **不占** 50 次/天配额；内置通道行为不变
- 不改 H5
- TDD：每条新行为先见红

---

### Task 1: 云函数纯逻辑（厂商表 / 校验 / 错误映射）

**Files:**
- Modify: `HealthyDiet/cloudfunctions/api-diet/ai.js`
- Test: `tests/ai-provider.test.js`

**Interfaces:**
- Produces:
  - `AI_PROVIDERS: Record<id, {url, model}>`
  - `validateProviderConfig(p): {ok:true,id,model,key} | {ok:false,message}`
  - `providerTarget(id): {url, model} | null`
  - `providerErrorMessage(status): string`

- [ ] **Step 1: 写失败测试** `tests/ai-provider.test.js`

```js
import test from 'node:test';
import assert from 'node:assert/strict';
import ai from '../HealthyDiet/cloudfunctions/api-diet/ai.js';

test('validateProviderConfig：合法配置通过，空 model 回填该厂商默认', () => {
  const v = ai.validateProviderConfig({ id: 'deepseek', model: '', key: 'sk-12345678' });
  assert.equal(v.ok, true);
  assert.equal(v.model, 'deepseek-flash');
  assert.equal(v.key, 'sk-12345678');
});

test('validateProviderConfig：未知厂商 / 非法模型 / 非法 key 各自拒绝', () => {
  assert.equal(ai.validateProviderConfig({ id: 'nope', model: 'x', key: 'sk-12345678' }).message, '不支持的模型厂商');
  assert.equal(ai.validateProviderConfig({ id: 'deepseek', model: 'has space', key: 'sk-12345678' }).message, '请填写有效的模型名');
  assert.equal(ai.validateProviderConfig({ id: 'qwen', model: '', key: 'sk-12345678' }).message, '请填写有效的模型名');
  assert.equal(ai.validateProviderConfig({ id: 'deepseek', model: 'm', key: 'short' }).message, 'API Key 格式不正确');
  assert.equal(ai.validateProviderConfig({ id: 'deepseek', model: 'm', key: 'sk-1234 5678' }).message, 'API Key 格式不正确');
});

test('providerTarget：已知厂商给 URL 与默认模型，未知返回 null', () => {
  assert.equal(ai.providerTarget('deepseek').url, 'https://api.deepseek.com/chat/completions');
  assert.equal(ai.providerTarget('deepseek').model, 'deepseek-flash');
  assert.equal(ai.providerTarget('nope'), null);
});

test('providerErrorMessage：状态码 → 固定文案', () => {
  assert.equal(ai.providerErrorMessage(401), 'Key 无效或无权限');
  assert.equal(ai.providerErrorMessage(403), 'Key 无效或无权限');
  assert.equal(ai.providerErrorMessage(429), '厂商额度用完或请求太频繁');
  assert.equal(ai.providerErrorMessage(0), '识别超时，请重试');
  assert.equal(ai.providerErrorMessage(500), '厂商服务异常（HTTP 500）');
});
```

- [ ] **Step 2: 跑测试确认红**（函数不存在）

Run: `node --test tests/ai-provider.test.js`

- [ ] **Step 3: 实现**（追加到 `ai.js`，并加入 `module.exports`）

```js
const AI_PROVIDERS = {
  deepseek: { url: "https://api.deepseek.com/chat/completions", model: "deepseek-flash" },
  qwen: { url: "https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions", model: "" },
  kimi: { url: "https://api.moonshot.cn/v1/chat/completions", model: "" },
  zhipu: { url: "https://open.bigmodel.cn/api/paas/v4/chat/completions", model: "" },
  doubao: { url: "https://ark.cn-beijing.volces.com/api/v3/chat/completions", model: "" },
};
const kProviderModelPattern = /^[A-Za-z0-9._:/-]{1,60}$/;

function validateProviderConfig(p) {
  if (!p || typeof p !== "object") return { ok: false, message: "自定义模型配置不完整" };
  const id = typeof p.id === "string" ? p.id : "";
  const t = AI_PROVIDERS[id];
  if (!t) return { ok: false, message: "不支持的模型厂商" };
  const rawModel = typeof p.model === "string" ? p.model.trim() : "";
  const model = rawModel || t.model;
  if (!model || !kProviderModelPattern.test(model)) return { ok: false, message: "请填写有效的模型名" };
  const key = typeof p.key === "string" ? p.key : "";
  if (key.length < 8 || key.length > 200 || /\s/.test(key)) return { ok: false, message: "API Key 格式不正确" };
  return { ok: true, id, model, key };
}

function providerTarget(id) {
  const t = AI_PROVIDERS[id];
  return t ? { url: t.url, model: t.model } : null;
}

function providerErrorMessage(status) {
  if (status === 401 || status === 403) return "Key 无效或无权限";
  if (status === 429) return "厂商额度用完或请求太频繁";
  if (status === 0) return "识别超时，请重试";
  return "厂商服务异常（HTTP " + status + "）";
}
```

- [ ] **Step 4: 跑测试确认绿**

Run: `node --test tests/ai-provider.test.js` → 4 pass；再 `npm test` 全量 ≥108。

- [ ] **Step 5: 提交**

```bash
git add HealthyDiet/cloudfunctions/api-diet/ai.js tests/ai-provider.test.js
git commit -m "feat(m14): 多厂商纯逻辑（厂商表/配置校验/错误映射）"
```

---

### Task 2: `/ai/food-scan` 接入自带 provider

**Files:**
- Modify: `HealthyDiet/cloudfunctions/api-diet/index.js`

**Interfaces:**
- Consumes: Task 1 的 `validateProviderConfig / providerTarget / providerErrorMessage`
- Produces: `/ai/food-scan` 接受可选 `provider:{id,model,key}`；自带通道不占配额

- [ ] **Step 1: 顶部 require 增补**

```js
const {
  parseModelJson, validateScanResult, kAiScanDailyLimit, kAiImageMaxChars, kAiImagePrefix,
  validateProviderConfig, providerTarget, providerErrorMessage,
} = require("./ai");
```

- [ ] **Step 2: 重构 `callDeepSeek` 支持任意厂商 target 与日志标签**

```js
async function callDeepSeek(apiKey, imageDataUrl, strict, target, logTag) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), 12000);
  try {
    const resp = await fetch(target.url, {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: "Bearer " + apiKey },
      signal: controller.signal,
      body: JSON.stringify({
        model: target.model,
        temperature: 0.2,
        max_tokens: 300,
        response_format: { type: "json_object" },
        messages: [
          { role: "system", content: AI_SYSTEM_PROMPT },
          { role: "user", content: [
            { type: "text", text: strict
                ? "上一次结果不合法。请严格按 JSON 输出，并保证 4P+4C+9F 与热量相差不超过 25%。"
                : "请识别这道菜。" },
            { type: "image_url", image_url: { url: imageDataUrl } }
          ] }
        ]
      })
    });
    if (!resp.ok) {
      console.log(logTag, resp.status);
      return { text: null, status: resp.status };
    }
    const data = await resp.json();
    const msg = data && data.choices && data.choices[0] && data.choices[0].message;
    return { text: (msg && msg.content) || null, status: 200 };
  } catch (e) {
    if (e && e.name === "AbortError") console.log(logTag, "TIMEOUT");
    else console.log(logTag, "ERROR");
    return { text: null, status: 0 };
  } finally {
    clearTimeout(timer);
  }
}
```

- [ ] **Step 3: 路由里按有无 provider 分流（配额只给内置通道）**

```js
const custom = body.provider;
let apiKey = "", target = null, logTag = "DEEPSEEK_HTTP", isCustom = false;
if (custom) {
  const v = validateProviderConfig(custom);
  if (!v.ok) return { ok: false, message: v.message };
  target = providerTarget(v.id);
  target = { url: target.url, model: v.model };
  apiKey = v.key;
  logTag = "AI_PROVIDER_HTTP " + v.id;
  isCustom = true;
} else {
  apiKey = process.env.DEEPSEEK_API_KEY || "";
  if (!apiKey) return { ok: false, message: "识别服务未配置" };
  target = providerTarget("deepseek");
}
// 图片校验（不变）
if (!kAiImagePrefix.test(image) || image.length > kAiImageMaxChars) {
  return { ok: false, message: "图片格式不支持或过大" };
}
// 配额：只有内置通道计数
let used = 0;
if (!isCustom) {
  const prof = await getOrCreateProfile(uid);
  const d = today();
  used = prof.aiScanDate === d ? (Number(prof.aiScanCount) || 0) : 0;
  if (used >= kAiScanDailyLimit) return { ok: false, message: "今日识别次数已用完（" + kAiScanDailyLimit + " 次）" };
  await profiles.where({ uid }).update({ aiScanDate: d, aiScanCount: used + 1, updatedAt: Date.now() });
}
let result = null, lastStatus = 0;
for (let attempt = 0; attempt < 2 && !result; attempt++) {
  const r = await callDeepSeek(apiKey, image, attempt > 0, target, logTag);
  lastStatus = r.status;
  const parsed = parseModelJson(r.text);
  if (!parsed) continue;
  const v = validateScanResult(parsed);
  if (v.ok) result = v;
}
if (!result) {
  if (isCustom && lastStatus !== 200) return { ok: false, message: providerErrorMessage(lastStatus) };
  return { ok: false, message: "没认出来，换张更清楚的图或手动填写" };
}
return {
  ok: true, dish: result.dish, confidence: result.confidence,
  per100: result.per100, note: result.note,
  quota: isCustom ? undefined : { used: used + 1, limit: kAiScanDailyLimit }
};
```

- [ ] **Step 4: 语法检查**

Run: `cd HealthyDiet/cloudfunctions/api-diet && node --check index.js && node --check ai.js`

- [ ] **Step 5: 提交**

```bash
git add HealthyDiet/cloudfunctions/api-diet/index.js
git commit -m "feat(m14): /ai/food-scan 支持自带 provider（不占内置配额，错误按状态码翻译）"
```

---

### Task 3: 客户端密钥存储

**Files:**
- Create: `ShiguangFlutter/lib/data/ai_provider_store.dart`
- Modify: `ShiguangFlutter/lib/app/root_container.dart`（override 具体实现）
- Test: `ShiguangFlutter/test/data/ai_provider_store_test.dart`

**Interfaces:**
- Produces:
  - `class AiProviderConfig { bool enabled; String id; String model; String key; bool get isUsable; Map toJson(); static AiProviderConfig? fromJson(String) }`
  - `abstract class AiProviderStore { load(); save(config); clear(); }`
  - `class SecureAiProviderStore implements AiProviderStore`
  - `final aiProviderStoreProvider = Provider<AiProviderStore>(...)`

- [ ] **Step 1: 写失败测试**（用内存 `FlutterSecureStorage` 子类，参考 `token_store_cache_test.dart` 的 `_CountingStorage`）

```dart
test('save→load 往返；clear 后为空', () async {
  final s = _MemStorage();
  final store = SecureAiProviderStore(storage: s);
  await store.save(const AiProviderConfig(enabled: true, id: 'deepseek', model: 'deepseek-flash', key: 'sk-12345678'));
  final c = await store.load();
  expect(c!.enabled, isTrue);
  expect(c.id, 'deepseek');
  expect(c.key, 'sk-12345678');
  await store.clear();
  expect(await store.load(), isNull);
});

test('坏 JSON / 缺字段 → null（按未配置处理）', () async {
  final s = _MemStorage()..seed('sg_ai_provider_v1', '{broken');
  expect(await SecureAiProviderStore(storage: s).load(), isNull);
  s.seed('sg_ai_provider_v1', '{"enabled":true}');
  expect(await SecureAiProviderStore(storage: s).load(), isNull);
});

test('isUsable：开关关 / 三项任一为空都不可用', () {
  expect(const AiProviderConfig(enabled: true, id: 'deepseek', model: 'm', key: 'k').isUsable, isTrue);
  expect(const AiProviderConfig(enabled: false, id: 'deepseek', model: 'm', key: 'k').isUsable, isFalse);
  expect(const AiProviderConfig(enabled: true, id: '', model: 'm', key: 'k').isUsable, isFalse);
});
```

- [ ] **Step 2: 跑测试确认红**

Run: `flutter test test/data/ai_provider_store_test.dart`

- [ ] **Step 3: 实现**

```dart
import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AiProviderConfig {
  const AiProviderConfig({required this.enabled, required this.id, required this.model, required this.key});
  final bool enabled;
  final String id;
  final String model;
  final String key;

  bool get isUsable => enabled && id.isNotEmpty && model.isNotEmpty && key.isNotEmpty;

  Map<String, dynamic> toJson() => {'enabled': enabled, 'id': id, 'model': model, 'key': key};

  static AiProviderConfig? fromJson(String raw) {
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return null;
      final enabled = m['enabled'];
      final id = m['id'];
      final model = m['model'];
      final key = m['key'];
      if (enabled is! bool || id is! String || model is! String || key is! String) return null;
      return AiProviderConfig(enabled: enabled, id: id, model: model, key: key);
    } catch (_) {
      return null;
    }
  }
}

abstract class AiProviderStore {
  Future<AiProviderConfig?> load();
  Future<void> save(AiProviderConfig config);
  Future<void> clear();
}

class SecureAiProviderStore implements AiProviderStore {
  SecureAiProviderStore({FlutterSecureStorage? storage}) : _storage = storage ?? const FlutterSecureStorage();
  final FlutterSecureStorage _storage;
  static const String storageKey = 'sg_ai_provider_v1';

  @override
  Future<AiProviderConfig?> load() async {
    try {
      final raw = await _storage.read(key: storageKey);
      if (raw == null || raw.isEmpty) return null;
      return AiProviderConfig.fromJson(raw);
    } catch (_) {
      return null; // 读盘失败按未配置处理，不打断识菜
    }
  }

  @override
  Future<void> save(AiProviderConfig config) => _storage.write(key: storageKey, value: jsonEncode(config.toJson()));

  @override
  Future<void> clear() => _storage.delete(key: storageKey);
}

final aiProviderStoreProvider = Provider<AiProviderStore>(
    (ref) => throw UnimplementedError('组合根注入'));
```

`root_container.dart` 增加（与 `foodFreqStoreProvider` 同处）：

```dart
aiProviderStoreProvider.overrideWithValue(SecureAiProviderStore()),
```

- [ ] **Step 4: 跑测试确认绿 + `dart analyze`**

- [ ] **Step 5: 提交**

```bash
git add ShiguangFlutter/lib/data/ai_provider_store.dart ShiguangFlutter/lib/app/root_container.dart ShiguangFlutter/test/data/ai_provider_store_test.dart
git commit -m "feat(m14): 自带 Key 安全存储（仅手机，坏数据按未配置处理）"
```

---

### Task 4: `HealthApi.scanFood` 带 provider

**Files:**
- Modify: `ShiguangFlutter/lib/data/health_api.dart`（`scanFood`）
- Test: `ShiguangFlutter/test/data/health_api_provider_test.dart`

**Interfaces:**
- Consumes: Task 3 `AiProviderConfig`
- Produces: `scanFood(String imageDataUrl, {AiProviderConfig? provider})`

- [ ] **Step 1: 写失败测试**（RecordingAdapter 断言 envelope body）

```dart
test('配置可用 → body 含 provider；不可用/未配置 → 不含', () async {
  final adapter = RecordingAdapter();
  final api = HealthApi(ApiClient(tokenStore: InMemoryTokenStore(), dio: Dio()..httpClientAdapter = adapter));
  await api.scanFood('data:image/jpeg;base64,AAA',
      provider: const AiProviderConfig(enabled: true, id: 'deepseek', model: 'deepseek-flash', key: 'sk-12345678'));
  expect(adapter.envelopes.last['body']['provider'],
      {'id': 'deepseek', 'model': 'deepseek-flash', 'key': 'sk-12345678'});

  await api.scanFood('data:image/jpeg;base64,AAA',
      provider: const AiProviderConfig(enabled: false, id: 'deepseek', model: 'm', key: 'sk-12345678'));
  expect(adapter.envelopes.last['body'].containsKey('provider'), isFalse);
});
```

- [ ] **Step 2: 跑测试确认红**

- [ ] **Step 3: 实现**

```dart
/// 拍照识菜（M14）：可选自带 provider；不可用/未配置时不传，回退内置通道。
Future<Map<String, dynamic>> scanFood(String imageDataUrl, {AiProviderConfig? provider}) =>
    _client.call(
      '/ai/food-scan',
      method: 'POST',
      body: <String, dynamic>{
        'image': imageDataUrl,
        if (provider != null && provider.isUsable)
          'provider': <String, dynamic>{'id': provider.id, 'model': provider.model, 'key': provider.key},
      },
      timeout: const Duration(seconds: 30),
    );
```

（`health_api.dart` 增加 `import 'ai_provider_store.dart';`）

- [ ] **Step 4: 跑 `flutter test test/data/` 与 `dart analyze`**

- [ ] **Step 5: 提交**

```bash
git add ShiguangFlutter/lib/data/health_api.dart ShiguangFlutter/test/data/health_api_provider_test.dart
git commit -m "feat(m14): scanFood 支持自带 provider（可用才传）"
```

---

### Task 5: 设置弹层 + 两个调用点接线

**Files:**
- Create: `ShiguangFlutter/lib/features/profile/ai_provider_sheet.dart`
- Modify: `ShiguangFlutter/lib/features/record/food_scan_sheet.dart`（`openFoodScanFlow` 读配置并传给 `scanFood`）
- Modify: `ShiguangFlutter/lib/features/profile/profile_screen.dart`（入口）
- Test: `ShiguangFlutter/test/ai_provider_sheet_test.dart`

**Interfaces:**
- Consumes: `aiProviderStoreProvider`、`AiProviderConfig`、`scanFood(..., provider:)`
- Produces: `Future<void> openAiProviderSheet(BuildContext, WidgetRef)`

- [ ] **Step 1: 写失败测试**

```dart
testWidgets('保存：开关开 + 厂商 + 模型 + key → 落库；清除 → 开关关且清空', (tester) async {
  final store = _MemStore();
  await pumpSheet(tester, store);
  await tester.tap(find.byKey(const Key('ai-switch')));
  await tester.tap(find.byKey(const Key('ai-provider')));
  await tester.pumpAndSettle();
  await tester.tap(find.text('通义千问').last);
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('ai-model')), 'qwen-vl-max');
  await tester.enterText(find.byKey(const Key('ai-key')), 'sk-12345678');
  await tester.tap(find.byKey(const Key('ai-save')));
  await tester.pumpAndSettle();
  final c = await store.load();
  expect(c!.enabled, isTrue);
  expect(c.id, 'qwen');
  expect(c.model, 'qwen-vl-max');

  await tester.tap(find.byKey(const Key('ai-clear')));
  await tester.pumpAndSettle();
  expect(await store.load(), isNull);
});

testWidgets('开关开但 key 为空 → 保存被拒，不落库', (tester) async {
  final store = _MemStore();
  await pumpSheet(tester, store);
  await tester.tap(find.byKey(const Key('ai-switch')));
  await tester.enterText(find.byKey(const Key('ai-model')), 'm');
  await tester.tap(find.byKey(const Key('ai-save')));
  await tester.pump();
  expect(await store.load(), isNull);
  expect(find.textContaining('请填写'), findsOneWidget);
});
```

- [ ] **Step 2: 实现 `ai_provider_sheet.dart`**

要点：
- `showShiguangSheet` 承载；State 内 `initState` 读 `aiProviderStoreProvider.load()` 预填。
- 厂商下拉 5 项（DeepSeek/通义千问/Kimi/智谱/豆包）；**切换厂商时模型重置**（DeepSeek 填 `deepseek-flash`，其余清空）。
- Key 输入 `obscureText`，已保存时占位显示 `•••• ` + 末 4 位；编辑即覆盖。
- 保存：`enabled && (model.isEmpty || key.isEmpty)` → inline 红字「请填写模型名与 API Key」，不落库。
- 清除：`store.clear()` + 开关置 false + 清空输入。
- Key：`ai-switch / ai-provider / ai-model / ai-key / ai-save / ai-clear`。

- [ ] **Step 3: 接线**

- `food_scan_sheet.dart` 的 `openFoodScanFlow` 在 `scanFood` 前：

```dart
final provider = await ref.read(aiProviderStoreProvider).load();
final scan = await ref.read(healthApiProvider).scanFood(img, provider: provider);
```

- `profile_screen.dart`：在「食物库」按钮附近加一行「AI 识菜设置」（key `ai-settings`），点击 `openAiProviderSheet(context, ref)`。

- [ ] **Step 4: 跑测试 + 回归**

Run: `flutter test test/ai_provider_sheet_test.dart test/food_scan_entry_test.dart test/food_scan_sheet_test.dart test/profile_screen_test.dart`、`dart analyze`

- [ ] **Step 5: 提交**

```bash
git add ShiguangFlutter/lib/features/profile/ai_provider_sheet.dart ShiguangFlutter/lib/features/profile/profile_screen.dart ShiguangFlutter/lib/features/record/food_scan_sheet.dart ShiguangFlutter/test/ai_provider_sheet_test.dart
git commit -m "feat(m14): AI 识菜设置弹层与接线（自带 key 优先，未配置回退内置）"
```

---

### Task 6: 收口——版本、日志、全量闸、部署

**Files:**
- Modify: `ShiguangFlutter/pubspec.yaml`（`2.9.0+20900`）、`CHANGELOG.md`

- [ ] **Step 1: 版本与更新日志**

`## [2.9.0] - 2026-10-20`：新增「AI 识菜支持自带 Key 与多厂商（DeepSeek/千问/Kimi/智谱/豆包）」；
说明 key 只存本机、自带 key 不占内置次数；未配置自动回退。

- [ ] **Step 2: 全量闸**

```bash
cd ShiguangFlutter && dart analyze && flutter test
cd .. && npm test && npm run lint && npm run check:version
```

Expected：analyze 0；flutter ≥ 591（M14 进行中实测基线）；H5 ≥ 111；lint 0 error。

- [ ] **Step 3: 部署（需老大令）**

1. `manageFunctions updateFunctionCode`（含新 `ai.js`）
2. 真调用验收：
   - 不带 provider → 与现状一致、配额 +1；
   - 带 provider（用老大自己的 DeepSeek key 模拟自带）→ 正常识别、**配额 +0**；
   - 错 key → 「Key 无效或无权限」；qwen + 空模型 → 「请填写有效的模型名」。
3. 回滚：用 `c0e524c` 的 `index.js`/`ai.js` 重部署。

- [ ] **Step 4: 出包与真机目检**

ASCII 沙盒重打 `--split-per-abi` → 验签 `cc7e2dd9…` → `adb install -r`；
目检四条：设置页保存/清除；配好后识菜成功；关开关后回退内置；错 key 报「Key 无效或无权限」。

- [ ] **Step 5: 提交**

```bash
git add ShiguangFlutter/pubspec.yaml CHANGELOG.md
git commit -m "build: M14 自带 Key + 多厂商 2.9.0+20900（云函数部署与真机目检见 spec §5）"
```

---

## 自审记录

- **Spec 覆盖**：§2.1/2.3→T1/T2；§2.2→T1；§3.1→T3；§3.2→T5；§3.3→T4；§4→各任务；§5→T6；§6/§7→文档。
- **占位符**：无 TBD；部署步骤写明具体命令与验收值。
- **类型一致**：`AiProviderConfig` 在 T3 定义（`enabled/id/model/key/isUsable/toJson/fromJson`），T4/T5 使用一致；`validateProviderConfig` 返回 `{ok,id,model,key}`，T2 按此取值。
