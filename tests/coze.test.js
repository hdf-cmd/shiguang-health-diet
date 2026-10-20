import test from 'node:test';
import assert from 'node:assert/strict';
import coze from '../HealthyDiet/cloudfunctions/api-diet/coze.js';

const summary = {
  kcal: 1200, target: 1800, carb: 150, protein: 60, fat: 40, water: 6,
};
const records = [
  { meal: 'breakfast', name: '燕麦牛奶', kcal: 300 },
  { meal: 'lunch', name: '葱姜鸡', kcal: 266 },
  { meal: 'lunch', name: '米饭', kcal: 232 },
  { meal: 'snack', name: '苹果', kcal: 90 },
  { meal: 'snack', name: '无糖酸奶', kcal: 120 },
  { meal: 'dinner', name: '清炒青菜', kcal: 60 },
  { meal: 'dinner', name: '水煮虾', kcal: 132 },
];
const exercises = [{ kcal: 120 }, { kcal: 80 }];
const profile = { waterMl: 1600, weightKg: 55, targetWeight: 52 };

test('buildTodaySummaryContext：输出今日摘要块，含目标/缺口/餐次记录', () => {
  const text = coze.buildTodaySummaryContext({
    date: '2026-10-20', summary, records, exercises, profile,
  });
  assert.match(text, /^【今日饮食摘要】/);
  assert.match(text, /日期: 2026-10-20/);
  assert.match(text, /目标热量: 1800 kcal；已摄入: 1200 kcal；剩余: 600 kcal/);
  assert.match(text, /蛋白质: 60\/113 g；碳水: 150\/225 g；脂肪: 40\/50 g/);
  assert.match(text, /饮水: 1200 ml（目标 1600 ml）；运动消耗: 200 kcal；体重: 55\.0 kg；目标体重: 52\.0 kg/);
  assert.match(text, /- 早餐: 燕麦牛奶 300 kcal/);
  assert.match(text, /- 午餐: 葱姜鸡 266 kcal、米饭 232 kcal/);
  assert.match(text, /- 晚餐: 清炒青菜 60 kcal、水煮虾 132 kcal/);
});

test('buildTodaySummaryContext：无记录与饮水目标缺失的兜底', () => {
  const text = coze.buildTodaySummaryContext({
    date: '2026-10-20',
    summary: { kcal: 0, target: 1800, carb: 0, protein: 0, fat: 0, water: 0 },
    records: [], exercises: [], profile: { waterMl: 0, weightKg: 55, targetWeight: 52 },
  });
  assert.match(text, /今日记录:\n- 今日暂无记录/);
  assert.match(text, /目标 1600 ml/); // waterMl=0 回退 1600，和 App 水卡口径一致
});

test('buildCozeChatBody：流式、自动保存历史；无 conversationId 时整键省略', () => {
  const a = coze.buildCozeChatBody({
    botId: 'bot1', userId: 'u1', content: '你好',
  });
  assert.equal(a.bot_id, 'bot1');
  assert.equal(a.user_id, 'u1');
  assert.equal(a.stream, true);
  assert.equal(a.auto_save_history, true);
  assert.equal(Object.hasOwn(a, 'conversation_id'), false);
  assert.deepEqual(a.additional_messages, [
    { role: 'user', content: '你好', content_type: 'text', type: 'question' },
  ]);

  const b = coze.buildCozeChatBody({
    botId: 'bot1', userId: 'u1', content: '继续', conversationId: 'conv1',
  });
  assert.equal(b.conversation_id, 'conv1');
});

test('SSE 解析：跨 chunk 拼接，completed 覆盖 delta，不重复正文', () => {
  const p = coze.createCozeStreamParser();
  p.feed('event:conversation.chat.created\ndata:{"id":"chat1","conversation_id":"conv1","status":"created"}\n\n');
  p.feed('event:conversation.message.delta\ndata:{"id":"msg1","conversation_id":"conv1","role":"assistant","type":"answer","content":"你好","content_type":"text"}\n\nevent:conversation.message.delta\ndata:{"id":"msg1","conversation_id":"conv1","role":"assistant","type":"answer","content":"，我是助手","content_type":"text"}\n\n');
  p.feed('event:conversation.message.completed\ndata:{"id":"msg1","conversation_id":"conv1","role":"assistant","type":"answer","content":"你好，我是助手","content_type":"text"}\n\n');
  p.feed('event:conversation.chat.completed\ndata:{"id":"chat1","conversation_id":"conv1","status":"completed"}\n\nevent:done\ndata:"[DONE]"\n\n');
  const r = p.finish();
  assert.equal(r.ok, true);
  assert.equal(r.reply, '你好，我是助手');
  assert.equal(r.conversationId, 'conv1');
});

test('SSE 解析：首个正文到达时只触发一次 onFirstText', () => {
  let count = 0;
  const p = coze.createCozeStreamParser({ onFirstText: () => { count++; } });
  p.feed('event:conversation.chat.created\ndata:{"id":"chat1","conversation_id":"conv1","status":"created"}\n\n');
  assert.equal(count, 0);
  p.feed('event:conversation.message.delta\ndata:{"id":"msg1","role":"assistant","type":"answer","content":""}\n\n');
  assert.equal(count, 0);
  p.feed('event:conversation.message.delta\ndata:{"id":"msg1","role":"assistant","type":"answer","content":"你好"}\n\n');
  assert.equal(count, 1);
  p.feed('event:conversation.message.delta\ndata:{"id":"msg1","role":"assistant","type":"answer","content":"，世界"}\n\n');
  p.feed('event:conversation.message.completed\ndata:{"id":"msg1","role":"assistant","type":"answer","content":"你好，世界"}\n\n');
  assert.equal(count, 1);

  let completedOnly = 0;
  const p2 = coze.createCozeStreamParser({ onFirstText: () => { completedOnly++; } });
  p2.feed('event:conversation.message.completed\ndata:{"id":"msg2","role":"assistant","type":"answer","content":"只有 completed"}\n\n');
  assert.equal(completedOnly, 1);
});

test('SSE 解析：verbose / follow_up 不进正文；失败与空正文报错', () => {
  const p = coze.createCozeStreamParser();
  p.feed('event:conversation.message.delta\ndata:{"id":"v1","role":"assistant","type":"verbose","content":"内部","content_type":"text"}\n\n');
  p.feed('event:conversation.message.completed\ndata:{"id":"f1","role":"assistant","type":"follow_up","content":"追问","content_type":"text"}\n\n');
  p.feed('event:conversation.chat.failed\ndata:{"id":"chat1","conversation_id":"conv1","status":"failed","last_error":{"code":4000,"msg":"bot error"}}\n\n');
  const r = p.finish();
  assert.equal(r.ok, false);
  assert.equal(r.message, 'bot error');
  assert.equal(r.conversationId, 'conv1');
});

test('SSE 解析：没有正文时给出固定错误', () => {
  const p = coze.createCozeStreamParser();
  p.feed('event:conversation.chat.completed\ndata:{"id":"chat1","conversation_id":"conv1","status":"completed"}\n\n');
  const r = p.finish();
  assert.equal(r.ok, false);
  assert.equal(r.message, 'AI 助手没有返回内容');
});
