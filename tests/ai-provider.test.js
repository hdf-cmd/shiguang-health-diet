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
