import test from 'node:test';
import assert from 'node:assert/strict';
import ai from '../HealthyDiet/cloudfunctions/api-diet/ai.js';

const ctx = '【今日饮食摘要】\n目标热量: 1800 kcal；已摄入: 1200 kcal；剩余: 600 kcal';

test('buildAssistantMessages：摘要放 user 内容前面，问题附在后面', () => {
  const messages = ai.buildAssistantMessages(ctx, '今天的热量缺口怎么样');
  assert.equal(messages.length, 2);
  assert.equal(messages[0].role, 'system');
  assert.match(messages[0].content, /不能替代医生或营养师的诊断/);
  assert.equal(messages[1].role, 'user');
  assert.equal(messages[1].content, ctx + '\n\n用户问题：今天的热量缺口怎么样');
});

test('buildAssistantMessages：无摘要时只发问题，问题截断到 500 字', () => {
  const none = ai.buildAssistantMessages('', '  晚饭吃什么  ');
  assert.equal(none[1].content, '晚饭吃什么');
  const long = ai.buildAssistantMessages(null, '鸭'.repeat(600));
  assert.equal(long[1].content.length, 500);
});

test('assistantRequestBody：不强制 JSON 输出，deepseek 关闭思考', () => {
  const messages = ai.buildAssistantMessages('', '你好');
  const deepseek = ai.assistantRequestBody({ model: 'deepseek-flash', providerId: 'deepseek' }, messages);
  assert.equal(deepseek.response_format, undefined);
  assert.equal(deepseek.reasoning_effort, 'none');
  assert.equal(deepseek.model, 'deepseek-flash');
  assert.deepEqual(deepseek.messages, messages);

  const qwen = ai.assistantRequestBody({ model: 'qwen-plus', providerId: 'qwen' }, messages);
  assert.equal(Object.hasOwn(qwen, 'reasoning_effort'), false);
});

test('parseChatReply：取 choices[0].message.content，坏 JSON/空正文返回空串', () => {
  assert.equal(ai.parseChatReply(
    JSON.stringify({ choices: [{ message: { content: '  多喝水  ' } }] })), '多喝水');
  assert.equal(ai.parseChatReply('not json'), '');
  assert.equal(ai.parseChatReply(JSON.stringify({ choices: [{ message: { content: '' } }] })), '');
  assert.equal(ai.parseChatReply(JSON.stringify({ error: { message: 'bad' } })), '');
  assert.equal(ai.parseChatReply(''), '');
});
