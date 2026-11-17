import test from 'node:test';
import assert from 'node:assert/strict';
import {
  handleAssistantChat, createCozeCooldown, requestDeepSeekReply,
} from '../HealthyDiet/cloudfunctions/api-diet/services/assistant_route.js';

const okDeepSeek = (body = {}) => async (url, init) => {
  body.received = init;
  return {
    ok: true,
    status: 200,
    text: async () => JSON.stringify({ choices: [{ message: { content: '  晚餐加一份水煮虾。  ' } }] }),
  };
};

function baseDeps(over = {}) {
  return {
    uid: 'u_test',
    message: '晚餐吃什么',
    useTodaySummary: true,
    buildContext: async () => '【今日饮食摘要】剩余 600 kcal',
    primary: 'deepseek',
    deepSeek: { apiKey: 'sk-test' },
    coze: { conversationId: '', cooldown: createCozeCooldown(), call: null },
    fetchImpl: okDeepSeek(),
    now: () => 1000,
    log: () => {},
    ...over,
  };
}

test('DeepSeek 主通道成功时不调用扣子，返回 channel=deepseek', async () => {
  let cozeCalls = 0;
  const r = await handleAssistantChat(baseDeps({
    coze: {
      conversationId: '',
      cooldown: createCozeCooldown({ now: () => 1000 }),
      call: async () => { cozeCalls++; return { ok: true, reply: '扣子' }; },
    },
  }));
  assert.equal(r.ok, true);
  assert.equal(r.channel, 'deepseek');
  assert.equal(r.reply, '晚餐加一份水煮虾。');
  assert.equal(r.conversationId, '');
  assert.equal(cozeCalls, 0);
});

test('请求体带系统提示、历史与今日摘要，不强制 JSON 输出', async () => {
  const seen = {};
  const r = await handleAssistantChat(baseDeps({
    history: [{ role: 'user', content: '你好' }, { role: 'assistant', content: '你好呀' }],
    fetchImpl: okDeepSeek(seen),
  }));
  assert.equal(r.ok, true);
  const body = JSON.parse(seen.received.body);
  assert.equal(body.response_format, undefined);
  assert.equal(body.reasoning_effort, 'none');
  assert.equal(body.messages[0].role, 'system');
  assert.deepEqual(body.messages.slice(1, 3), [
    { role: 'user', content: '你好' },
    { role: 'assistant', content: '你好呀' },
  ]);
  assert.match(body.messages.at(-1).content, /剩余 600 kcal[\s\S]*用户问题：晚餐吃什么/);
});

test('DeepSeek 失败后回退扣子，沿用 conversationId', async () => {
  const badFetch = async () => ({ ok: false, status: 500, text: async () => 'boom' });
  const r = await handleAssistantChat(baseDeps({
    fetchImpl: badFetch,
    coze: {
      conversationId: 'conv-old',
      cooldown: createCozeCooldown({ now: () => 1000 }),
      call: async ({ conversationId }) => {
        assert.equal(conversationId, 'conv-old');
        return { ok: true, reply: '扣子回答', conversationId: 'conv-new' };
      },
    },
  }));
  assert.equal(r.ok, true);
  assert.equal(r.channel, 'coze');
  assert.equal(r.conversationId, 'conv-new');
});

test('扣子额度用完 → 熔断 10 分钟，之后直接走 DeepSeek 不再调用扣子', async () => {
  let clock = 1000;
  const now = () => clock;
  let cozeCalls = 0;
  const cooldown = createCozeCooldown({ now, ttlMs: 10 * 60 * 1000 });
  const deps = baseDeps({
    now,
    fetchImpl: async () => ({ ok: false, status: 500, text: async () => '' }),
    coze: {
      conversationId: '',
      cooldown,
      call: async () => {
        cozeCalls++;
        return { ok: false, message: 'Insufficient coze credits balance, please wait' };
      },
    },
  });

  const first = await handleAssistantChat(deps);
  assert.equal(first.ok, false);
  assert.equal(cozeCalls, 1);
  assert.equal(cooldown.isOpen(), true);

  const second = await handleAssistantChat(deps);
  assert.equal(second.ok, false);
  assert.equal(cozeCalls, 1, '熔断期内不得再调扣子');

  clock += 11 * 60 * 1000;
  await handleAssistantChat(deps);
  assert.equal(cozeCalls, 2, '冷却过期后应重试一次');
});

test('扣子优先模式：扣子成功后不再调用 DeepSeek', async () => {
  let deepseekCalls = 0;
  const r = await handleAssistantChat(baseDeps({
    primary: 'coze',
    fetchImpl: async () => { deepseekCalls++; return { ok: false, status: 500, text: async () => '' }; },
    coze: {
      conversationId: '',
      cooldown: createCozeCooldown({ now: () => 1000 }),
      call: async () => ({ ok: true, reply: '扣子回答', conversationId: 'c1' }),
    },
  }));
  assert.equal(r.ok, true);
  assert.equal(r.channel, 'coze');
  assert.equal(deepseekCalls, 0);
});

test('扣子优先模式下扣子额度用完 → 用户看到额度文案', async () => {
  const r = await handleAssistantChat(baseDeps({
    primary: 'coze',
    fetchImpl: async () => ({ ok: false, status: 500, text: async () => '' }),
    coze: {
      conversationId: '',
      cooldown: createCozeCooldown({ now: () => 1000 }),
      call: async () => ({ ok: false, message: 'Insufficient coze credits balance' }),
    },
  }));
  assert.equal(r.ok, false);
  assert.match(r.message, /额度/);
});

test('两条通道都失败 → DeepSeek 主通道给通用文案', async () => {
  const r = await handleAssistantChat(baseDeps({
    fetchImpl: async () => ({ ok: false, status: 401, text: async () => 'bad key' }),
    coze: { conversationId: '', cooldown: createCozeCooldown({ now: () => 1000 }), call: null },
  }));
  assert.equal(r.ok, false);
  assert.equal(r.message, 'AI 助手暂时不可用，请稍后再试');
});

test('未配置任何通道 → AI 助手未配置；空问题与超长问题在调用前拦下', async () => {
  const none = await handleAssistantChat(baseDeps({
    deepSeek: { apiKey: '' },
    coze: { conversationId: '', cooldown: createCozeCooldown(), call: null },
  }));
  assert.equal(none.message, 'AI 助手未配置');

  let fetched = 0;
  const spyFetch = async () => { fetched++; return { ok: true, text: async () => '{}' }; };
  const empty = await handleAssistantChat(baseDeps({ message: '   ', fetchImpl: spyFetch }));
  assert.equal(empty.message, '请输入问题');
  const long = await handleAssistantChat(baseDeps({ message: '鸭'.repeat(501), fetchImpl: spyFetch }));
  assert.match(long.message, /500/);
  assert.equal(fetched, 0);
});

test('上下文取数失败不阻断回答', async () => {
  const r = await handleAssistantChat(baseDeps({
    buildContext: async () => { throw new Error('db down'); },
    fetchImpl: okDeepSeek(),
  }));
  assert.equal(r.ok, true);
});

test('requestDeepSeekReply：网络异常/超时/空正文分类返回，不抛异常', async () => {
  const boom = await requestDeepSeekReply({
    apiKey: 'sk', context: '', message: 'hi',
    fetchImpl: async () => { throw new TypeError('fetch failed'); },
  });
  assert.equal(boom.ok, false);
  assert.equal(boom.status, 0);
  assert.match(boom.error, /error:/);

  const abort = await requestDeepSeekReply({
    apiKey: 'sk', context: '', message: 'hi',
    fetchImpl: async () => { const e = new Error('aborted'); e.name = 'AbortError'; throw e; },
  });
  assert.equal(abort.error, 'timeout');

  const empty = await requestDeepSeekReply({
    apiKey: 'sk', context: '', message: 'hi',
    fetchImpl: async () => ({ ok: true, status: 200, text: async () => '{}' }),
  });
  assert.equal(empty.error, 'empty_reply');
});
