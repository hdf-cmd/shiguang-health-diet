/* AI 饮食助手对话链路（依赖注入，tests/assistant-route.test.js 覆盖）。
 *
 * 默认 DeepSeek 主通道：扣子免费版额度耗尽后每次先等扣子失败再兜底，白付一次往返；
 * 这里改为 DeepSeek 先答，扣子只在 DeepSeek 失败时尝试，并对「额度用完」做进程内熔断，
 * 熔断期内直接跳过扣子。ASSISTANT_PRIMARY=coze 可切回扣子优先。 */
const { providerTarget, buildAssistantMessages, assistantRequestBody, parseChatReply } = require('../ai');
const { isCozeQuotaError } = require('../coze');

const kCozeCooldownMs = 10 * 60 * 1000;
const kDeepSeekTimeoutMs = 9000;
const kCozeTimeoutMs = 18000;
const kMessageMaxChars = 500;

/* 进程内熔断：扣子额度用完 → 冷却期内不再调用（多实例各自一份，冷启动重试一次可接受）。 */
function createCozeCooldown({ ttlMs = kCozeCooldownMs, now = Date.now } = {}) {
  let until = 0;
  return {
    open() { until = now() + ttlMs; },
    close() { until = 0; },
    isOpen() { return until > now(); },
  };
}

/* DeepSeek 非流式回复：校验 HTTP/正文，超时与网络错误分类返回，不抛异常。 */
async function requestDeepSeekReply({
  apiKey,
  context,
  message,
  history,
  fetchImpl = fetch,
  timeoutMs = kDeepSeekTimeoutMs,
}) {
  const base = providerTarget('deepseek');
  if (!base || !base.url) return { ok: false, status: 0, error: 'no_target' };
  const target = { ...base, providerId: 'deepseek' };
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const resp = await fetchImpl(target.url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: 'Bearer ' + apiKey },
      signal: controller.signal,
      body: JSON.stringify(
        assistantRequestBody(target, buildAssistantMessages(context, message, history))),
    });
    if (!resp.ok) {
      const errText = await resp.text().catch(() => '');
      return { ok: false, status: resp.status, error: String(errText).slice(0, 200) };
    }
    const raw = await resp.text();
    const reply = parseChatReply(raw);
    if (!reply) return { ok: false, status: resp.status, error: 'empty_reply' };
    return { ok: true, reply };
  } catch (e) {
    const aborted = e && e.name === 'AbortError';
    const cause = e && e.cause && e.cause.message ? e.cause.message : '';
    return {
      ok: false,
      status: 0,
      error: aborted ? 'timeout' : ('error:' + (cause || (e && e.message) || 'unknown')),
    };
  } finally {
    clearTimeout(timer);
  }
}

/* 对话主入口：校验 → 组上下文 → 按顺序尝试通道 → 统一错误文案。 */
async function handleAssistantChat({
  uid,
  message,
  history,
  useTodaySummary = true,
  buildContext,
  primary = 'deepseek',
  deepSeek = {},
  coze = {},
  fetchImpl = fetch,
  now = Date.now,
  log = console.log,
}) {
  const question = typeof message === 'string' ? message.trim() : '';
  if (!question) return { ok: false, message: '请输入问题' };
  if (question.length > kMessageMaxChars) {
    return { ok: false, message: '问题太长，请控制在 ' + kMessageMaxChars + ' 字以内' };
  }

  const deepseekKey = String(deepSeek.apiKey || '').trim();
  const cozeReady = !!(coze.call && typeof coze.call === 'function');
  const cooldown = coze.cooldown;
  if (!deepseekKey && !cozeReady) return { ok: false, message: 'AI 助手未配置' };

  let context = '';
  if (useTodaySummary && typeof buildContext === 'function') {
    const ctxStart = now();
    try {
      context = String(await buildContext() || '');
    } catch (e) {
      /* 摘要取数失败不阻断对话：模型会按“看不到今日记录”回答。 */
      log('ASSISTANT_CONTEXT_ERR', e && e.message ? String(e.message).slice(0, 120) : '');
    }
    log('ASSISTANT_CTX_TIMING', now() - ctxStart);
  }

  const content = context ? context + '\n\n用户问题：' + question : question;
  const started = now();
  const order = primary === 'coze' ? ['coze', 'deepseek'] : ['deepseek', 'coze'];
  let lastCozeMessage = '';
  let cozeQuota = false;

  for (const channel of order) {
    if (channel === 'deepseek') {
      if (!deepseekKey) continue;
      const r = await requestDeepSeekReply({
        apiKey: deepseekKey,
        context,
        message: question,
        history,
        fetchImpl,
        timeoutMs: deepSeek.timeoutMs || kDeepSeekTimeoutMs,
      });
      if (r.ok) {
        log('ASSISTANT_CHANNEL deepseek', now() - started);
        return { ok: true, reply: r.reply, conversationId: '', channel: 'deepseek' };
      }
      log('ASSISTANT_FAIL deepseek', r.status, r.error || '');
      continue;
    }
    if (!cozeReady) continue;
    if (cooldown && typeof cooldown.isOpen === 'function' && cooldown.isOpen()) {
      log('ASSISTANT_SKIP_COZE cooldown');
      continue;
    }
    const r = await coze.call({
      content,
      conversationId: String(coze.conversationId || ''),
      timeoutMs: coze.timeoutMs || kCozeTimeoutMs,
    });
    if (r && r.ok) {
      log('ASSISTANT_CHANNEL coze', now() - started);
      return {
        ok: true,
        reply: r.reply,
        conversationId: r.conversationId || coze.conversationId || '',
        channel: 'coze',
      };
    }
    lastCozeMessage = (r && r.message) || 'AI 助手服务异常';
    cozeQuota = isCozeQuotaError(lastCozeMessage);
    if (cozeQuota && cooldown && typeof cooldown.open === 'function') cooldown.open();
    log('ASSISTANT_FAIL coze', cozeQuota ? 'quota' : 'other');
  }

  log('ASSISTANT_ALL_FAIL', now() - started, cozeQuota ? 'coze_quota' : '');
  /* 扣子优先模式下保留原有的额度文案；DeepSeek 主通道时额度与用户无关，给通用文案。 */
  if (primary === 'coze' && lastCozeMessage) {
    const { cozeUserMessage } = require('../coze');
    return { ok: false, message: cozeUserMessage(lastCozeMessage) };
  }
  return { ok: false, message: 'AI 助手暂时不可用，请稍后再试' };
}

module.exports = {
  kCozeCooldownMs, kDeepSeekTimeoutMs, kCozeTimeoutMs,
  createCozeCooldown, requestDeepSeekReply, handleAssistantChat,
};
