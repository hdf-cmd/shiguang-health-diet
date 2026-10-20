# M14 自带 Key + 多厂商识菜 设计档

- 日期：2026-10-20
- 状态：设计待老大评审（未实现）
- 老大原话：「api key能不能用户自己填写，然后内置多家的大模型」
- 三项裁决（2026-10-20 决策卡）：
  1. key **只存手机**，云端代发（用完即丢、不落库）
  2. 首批：**DeepSeek + 通用兼容**
  3. 没填自带 key 时 **回退到服务器自带 key**（保留既有 50 次/天闸）

## §0 目标与边界

- 用户可在「我的 → AI 识菜设置」里启用「使用我自己的 Key」，选厂商、填模型名与 key。
- 识菜时若已配置 → 云函数用该 key 调对应厂商；否则走服务器 `DEEPSEEK_API_KEY`（现状不变）。
- 自带 key 的调用**不占**服务器那把 key 的 50 次/天配额（花的是用户自己的钱）。

## §1 关键风险与对应（必须先看清）

| 风险 | 对应 |
|---|---|
| **SSRF**：若接受用户任意 baseUrl，云函数会变成内网探测器 | **v1 不接受任意域名**。厂商表是服务端常量（id → URL + 默认模型），客户端只能选 id、改模型名。「加一家」＝服务端加一行 + 部署 |
| **密钥经服务器** | 仅经 TLS 直达函数、只在本次请求内存里存在；**不写库、不打日志、不进返回体**；设置页只露末 4 位 |
| 厂商接口差异 | 首批 5 家均走 OpenAI 兼容的 `chat/completions` + `image_url`；模型名做成可编辑（各家视觉模型 id 常变，服务端只给 DeepSeek 一个已验证默认值） |
| 厂商原始报错泄漏 | 只按状态码翻译固定文案，**不透传厂商 body**（可能含账号/key 片段） |
| 误配 key 无处发现 | 首次识菜即验证；401/403 明确提示「Key 无效或无权限」 |

## §2 云函数

### 2.1 `/ai/food-scan` 入参扩展

```jsonc
{ "image": "data:image/jpeg;base64,...",
  "provider": { "id": "deepseek", "model": "deepseek-flash", "key": "sk-..." } }  // 可选
```

- 无 `provider` → 现状：`DEEPSEEK_API_KEY` + 50 次/天配额。
- 有 `provider` → 校验后**不占**配额、不走 `aiScanCount`。
- 校验（纯逻辑放 `ai.js`，node:test 覆盖）：
  - `id` ∈ `PROVIDERS`；`model` 1–60 字符且匹配 `[A-Za-z0-9._:/-]`；
  - `key` 8–200 字符、无空白；
  - 不合法 → 三条具体文案：未知厂商「不支持的模型厂商」、模型非法「请填写有效的模型名」、key 非法「API Key 格式不正确」（比统一文案更能定位问题）。

### 2.2 厂商表（服务端常量）

| id | 名称 | 接口 |
|---|---|---|
| `deepseek` | DeepSeek | `https://api.deepseek.com/chat/completions`（默认模型 `deepseek-flash`） |
| `qwen` | 通义千问 | `https://dashscope.aliyuncs.com/compatible-mode/v1/chat/completions` |
| `kimi` | Kimi | `https://api.moonshot.cn/v1/chat/completions` |
| `zhipu` | 智谱 GLM | `https://open.bigmodel.cn/api/paas/v4/chat/completions` |
| `doubao` | 豆包（方舟） | `https://ark.cn-beijing.volces.com/api/v3/chat/completions` |

非 DeepSeek 不给默认模型（避免写死过期型号），设置页要求手填。

### 2.3 调用与错误映射

- 同一套请求体（`model`/`temperature 0.2`/`max_tokens 300`/`response_format json_object`/`image_url` dataURL），`Authorization: Bearer <key>`，12s 超时，最多两次（沿用现状）。
- 状态翻译：`401/403` →「Key 无效或无权限」；`429` →「厂商额度用完或请求太频繁」；其它非 2xx →「厂商服务异常（HTTP n）」；超时/网络 →「识别超时，请重试」。
- 日志：内置通道沿用 `DEEPSEEK_HTTP <status>`；自带通道记 `AI_PROVIDER_HTTP <id> <status>`。两者均**不含 key、body 或厂商返回体**。

## §3 客户端

### 3.1 存储

- `AiProviderStore`（`flutter_secure_storage`，与 `SecureTokenStore` 同一套）：
  键 `sg_ai_provider_v1`，值 JSON `{enabled, id, model, key}`（enabled=设置页开关）；`load/save/clear`；坏数据按未配置处理。
- 不写 SharedPreferences、不同步云端、不随备份导出。
- **设备级**：Key 不随登录态清（与登录 token 不同），同一台手机换账号登录仍会用上一个账号填的 Key —— 这是「只存手机」的必然结果；设置页文案需提示「换人使用请先清除」。

### 3.2 设置页（我的 → AI 识菜设置）

- 开关「使用我自己的 Key」（默认关）。
- 厂商下拉（5 项）；模型名输入（DeepSeek 预填 `deepseek-flash`，其余空、提示「填该厂商的视觉模型名」）。
- **切换厂商时模型重置且 Key 清空**：DeepSeek 回填默认名、其余清空；已保存/已输入的 Key 一并清掉，必须重填（各家 Key 不通用，沿用会把 A 厂商凭据发到 B 厂商端点）。
- **开关打开但配置不完整**（缺 key 或缺模型）→ 保存时拒绝并提示；若历史数据损坏/被清，识菜按「未配置」处理、回退内置通道，不报错打断。
- Key 输入：密文，已保存时只显示「•••• 末4位」；「保存」「清除」。
- **「清除」同时把开关关掉**（不留「开着但没有 key」的悬挂态）。
- 说明文案：「Key 只存在本机加密存储；每次识别经你的服务器转发给厂商，不会保存。」
- 关闭开关＝走内置（不清除已保存的 key）。

### 3.3 请求

`HealthApi.scanFood(image, {AiProviderConfig? provider})`：已配置且开关打开时，body 里带
`provider:{id,model,key}`；否则不带，行为与 M13 完全一致。

## §4 判据（TDD）

**云函数纯逻辑**（`tests/ai-provider.test.js`）
1. `validateProviderConfig`：合法通过；未知 id 拒；模型含空格/超长拒；key 太短/含空白拒
2. `providerTarget('deepseek')` 返回正确 URL 与默认模型；未知 id 返回 null
3. 状态映射：401/403/429/500/超时 → 五条固定文案

**Dart**
4. `AiProviderStore`：save→load 往返；clear 后为空；坏 JSON 视为未配置
5. `scanFood`：配置开 → body 含 provider；未配置/开关关 → 不含
6. 设置页 widget：保存后 store 落值；清除后为空；开关关闭时 scan 不带 provider
7. 我的页存在「AI 识菜设置」入口

**全量闸**：`flutter test`（基线 569）、H5 `node --test`（基线 104）、lint 0 error、`dart analyze` 0 issue。

## §5 部署闸与回滚

- `updateFunctionCode` 部署 `index.js` + `ai.js`（含厂商表/校验）。
- 真调用验收：
  - 不带 provider → 与现状一致、配额 +1；
  - 带 provider（用老大自己的 DeepSeek key 模拟「自带」）→ 正常识别、**配额 +0**；
  - 故意错 key → 「Key 无效或无权限」；空模型 → 「自定义模型配置不完整」。
- 回滚：用 `c0e524c` 的 `index.js`/`ai.js` 重部署。

## §6 行为差异与风险登记

1. **「通用兼容」的实际边界**：只能选 5 家预设，不能填任意域名（防 SSRF）。加厂商＝服务端加一行 + 部署。
2. **自带 key 不受 50 次/天限制**：若被脚本刷，消耗的是 key 所有者的额度与他的函数并发；不做额外限流（YAGNI），网关并发是天然上限。
3. **key 在服务端内存里短暂存在**：这是「云端代发」的必然代价，已在设置页明示；不接受者可选择不用自带 key。
4. 厂商视觉模型名可能随时间变化：非 DeepSeek 默认留空强制手填，避免写死过期型号。

## §7 不做

- 任意 baseUrl / 自建代理、多 key 轮换、用量统计、云端保存配置、测试连接按钮（首次识菜即验证）、H5 接入。
