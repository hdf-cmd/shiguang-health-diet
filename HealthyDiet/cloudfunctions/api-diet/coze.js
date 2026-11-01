/* P3：扣子智能体接入的纯逻辑（不依赖数据库/网络，node --test 可直接覆盖）。 */

const MEAL_NAMES = {
  breakfast: '早餐',
  lunch: '午餐',
  dinner: '晚餐',
  snack: '加餐',
};
const MEAL_ORDER = ['breakfast', 'lunch', 'dinner', 'snack'];
const MAX_CONTEXT_RECORDS = 40;

function fmt1(v) {
  const n = Number(v);
  return Number.isFinite(n) ? n.toFixed(1) : '0.0';
}

function targetMacros(kcal) {
  const target = Math.max(0, Number(kcal) || 0);
  return {
    target,
    carb: Math.round((target * 0.5) / 4),
    protein: Math.round((target * 0.25) / 4),
    fat: Math.round((target * 0.25) / 9),
  };
}

/* 今日摘要文本：App 的云函数取数后交给这里格式化；扣子 Bot 的提示词按这个格式读取。 */
function buildTodaySummaryContext({ date, summary, records, exercises, profile }) {
  const s = summary || {};
  const p = profile || {};
  const m = targetMacros(s.target);
  const kcal = Math.max(0, Math.round(Number(s.kcal) || 0));
  const remaining = m.target - kcal;
  const waterMl = Math.max(0, Math.round(Number(s.water) || 0)) * 200; // 水卡口径：1 杯 = 200ml
  const waterGoal = Math.max(0, Math.round(Number(p.waterMl) || 0)) || 1600;
  const exerciseKcal = (exercises || []).reduce(
    (sum, e) => sum + Math.max(0, Math.round(Number(e.kcal) || 0)), 0);

  const grouped = new Map();
  for (const r of records || []) {
    const meal = MEAL_NAMES[r.meal] ? r.meal : 'snack';
    const name = String(r.name || '').trim();
    if (!name) continue;
    if (!grouped.has(meal)) grouped.set(meal, []);
    grouped.get(meal).push(`${name} ${Math.max(0, Math.round(Number(r.kcal) || 0))} kcal`);
  }
  const lines = [];
  let shown = 0;
  let total = 0;
  for (const meal of MEAL_ORDER) {
    for (const item of grouped.get(meal) || []) {
      total++;
      if (shown >= MAX_CONTEXT_RECORDS) continue;
      if (!lines[meal]) lines[meal] = [];
      lines[meal].push(item);
      shown++;
    }
  }
  const recordLines = [];
  for (const meal of MEAL_ORDER) {
    if (lines[meal] && lines[meal].length) {
      recordLines.push(`- ${MEAL_NAMES[meal]}: ${lines[meal].join('、')}`);
    }
  }
  if (!recordLines.length) recordLines.push('- 今日暂无记录');
  if (total > shown) recordLines.push(`- …共 ${total} 条，仅列出前 ${shown} 条`);

  const remainText = remaining >= 0
    ? `剩余: ${remaining} kcal`
    : `超出: ${Math.abs(remaining)} kcal`;

  return [
    '【今日饮食摘要】',
    `日期: ${date || ''}`,
    `目标热量: ${m.target} kcal；已摄入: ${kcal} kcal；${remainText}`,
    `蛋白质: ${Math.max(0, Math.round(Number(s.protein) || 0))}/${m.protein} g；` +
      `碳水: ${Math.max(0, Math.round(Number(s.carb) || 0))}/${m.carb} g；` +
      `脂肪: ${Math.max(0, Math.round(Number(s.fat) || 0))}/${m.fat} g`,
    `饮水: ${waterMl} ml（目标 ${waterGoal} ml）；运动消耗: ${exerciseKcal} kcal；` +
      `体重: ${fmt1(p.weightKg)} kg；目标体重: ${fmt1(p.targetWeight)} kg`,
    '今日记录:',
    ...recordLines,
  ].join('\n');
}

/* 扣子 v3/chat 流式请求体；conversationId 为空时整键省略，让扣子新建会话。 */
function buildCozeChatBody({ botId, userId, content, conversationId }) {
  const body = {
    bot_id: botId,
    user_id: userId,
    stream: true,
    auto_save_history: true,
    additional_messages: [
      { role: 'user', content, content_type: 'text', type: 'question' },
    ],
  };
  if (conversationId) body.conversation_id = conversationId;
  return body;
}

/* SSE 增量解析：跨 chunk 缓冲；message.completed 覆盖 delta，避免正文重复。 */
function createCozeStreamParser({ onFirstText } = {}) {
  let buffer = '';
  let conversationId = '';
  let completed = false;
  let ended = false;
  let failed = '';
  let firstTextFired = false;
  const messages = new Map();
  const order = [];

  function noteText(content) {
    if (firstTextFired || typeof content !== 'string' || !content.trim()) return;
    firstTextFired = true;
    if (typeof onFirstText === 'function') onFirstText();
  }

  function ensureMessage(id) {
    if (!messages.has(id)) {
      messages.set(id, '');
      order.push(id);
    }
  }

  function handle(event, data) {
    if (data && typeof data === 'object' && data.conversation_id) {
      conversationId = String(data.conversation_id);
    }
    if (!event) return;
    if (event === 'done') {
      ended = true;
      return;
    }
    if (event === 'error') {
      failed = String((data && (data.msg || data.message)) || 'AI 助手服务异常');
      return;
    }
    if (event === 'conversation.chat.failed') {
      const err = data && data.last_error;
      failed = String((err && err.msg) || (data && data.msg) || 'AI 助手处理失败');
      return;
    }
    if (event === 'conversation.chat.completed') {
      completed = true;
      return;
    }
    if (event === 'conversation.chat.created' || event === 'conversation.chat.in_progress' ||
        event === 'conversation.chat.inprogress') {
      return;
    }
    if (event !== 'conversation.message.delta' && event !== 'conversation.message.completed') {
      return;
    }
    if (!data || data.role !== 'assistant' || data.type !== 'answer') return;
    const id = String(data.id || 'answer');
    const content = typeof data.content === 'string' ? data.content : '';
    ensureMessage(id);
    if (event === 'conversation.message.completed') {
      if (content) messages.set(id, content);
    } else {
      messages.set(id, messages.get(id) + content);
    }
    noteText(content);
  }

  function processFrame(frame) {
    const lines = frame.split('\n');
    let event = '';
    const dataLines = [];
    for (const raw of lines) {
      const line = raw.trimEnd();
      if (line.startsWith('event:')) event = line.slice(6).trim();
      else if (line.startsWith('data:')) dataLines.push(line.slice(5).trim());
    }
    if (!event && !dataLines.length) return;
    const dataText = dataLines.join('\n');
    if (!dataText) {
      handle(event, null);
      return;
    }
    let data = null;
    try {
      data = JSON.parse(dataText);
    } catch (_) {
      data = null;
    }
    handle(event, data);
  }

  return {
    feed(chunk) {
      buffer += String(chunk == null ? '' : chunk).replace(/\r\n/g, '\n');
      let idx;
      while ((idx = buffer.indexOf('\n\n')) !== -1) {
        const frame = buffer.slice(0, idx);
        buffer = buffer.slice(idx + 2);
        processFrame(frame);
      }
    },
    finish() {
      if (buffer.trim()) {
        processFrame(buffer);
        buffer = '';
      }
      if (failed) return { ok: false, message: failed, conversationId };
      const parts = [];
      for (const id of order) {
        const text = messages.get(id) || '';
        if (text.trim()) parts.push(text);
      }
      const reply = parts.join('\n').trim();
      if (!reply) return { ok: false, message: 'AI 助手没有返回内容', conversationId };
      if (!completed && !ended) {
        return { ok: false, message: 'AI 助手响应中断，请重试', conversationId };
      }
      return { ok: true, reply, conversationId };
    },
  };
}

/* 额度/付费类失败：扣子免费版 API 累计次数用完后只回一句英文余额提示，
   这类失败换 DeepSeek 兜底仍能正常回答；其余失败也走兜底，但日志要分开记。 */
const kCozeQuotaPattern = /insufficient|credits?|quota|balance|paid version|额度|余额|付费/i;

function isCozeQuotaError(message) {
  const s = typeof message === 'string' ? message : '';
  return s ? kCozeQuotaPattern.test(s) : false;
}

/* 面向前端的错误文案：不让英文原文直接透传给用户。 */
function cozeUserMessage(message) {
  const s = typeof message === 'string' ? message.trim() : '';
  if (!s) return 'AI 助手服务异常，请稍后再试';
  if (isCozeQuotaError(s)) return 'AI 助手额度已用完，请稍后再试';
  if (/token|unauthor|invalid|credential/i.test(s)) return 'AI 助手授权失效，请稍后再试';
  return s;
}

module.exports = {
  buildTodaySummaryContext,
  buildCozeChatBody,
  createCozeStreamParser,
  isCozeQuotaError,
  cozeUserMessage,
};
