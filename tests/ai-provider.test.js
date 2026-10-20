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

test('validateProviderConfig：模型名边界 60 通过、61 拒绝', () => {
  const model60 = 'a'.repeat(60);
  const model61 = 'a'.repeat(61);
  assert.equal(ai.validateProviderConfig({ id: 'deepseek', model: model60, key: 'sk-12345678' }).ok, true);
  assert.equal(ai.validateProviderConfig({ id: 'deepseek', model: model61, key: 'sk-12345678' }).message, '请填写有效的模型名');
});

test('validateProviderConfig：API Key 边界 200 通过、201 拒绝', () => {
  const key200 = 'sk-' + 'a'.repeat(197);
  const key201 = 'sk-' + 'a'.repeat(198);
  assert.equal(key200.length, 200);
  assert.equal(key201.length, 201);
  assert.equal(ai.validateProviderConfig({ id: 'deepseek', model: 'm', key: key200 }).ok, true);
  assert.equal(ai.validateProviderConfig({ id: 'deepseek', model: 'm', key: key201 }).message, 'API Key 格式不正确');
});

test('原型链键不得绕过厂商校验', () => {
  assert.equal(ai.validateProviderConfig({ id: 'constructor', model: 'x', key: 'sk-12345678' }).ok, false);
  assert.equal(ai.validateProviderConfig({ id: 'constructor', model: 'x', key: 'sk-12345678' }).message, '不支持的模型厂商');
  assert.equal(ai.validateProviderConfig({ id: '__proto__', model: 'x', key: 'sk-12345678' }).ok, false);
  assert.equal(ai.validateProviderConfig({ id: 'toString', model: 'x', key: 'sk-12345678' }).ok, false);
  assert.equal(ai.providerTarget('constructor'), null);
  assert.equal(ai.providerTarget('__proto__'), null);
  assert.equal(ai.providerTarget('toString'), null);
});
