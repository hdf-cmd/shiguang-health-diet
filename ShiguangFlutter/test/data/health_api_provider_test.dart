// ShiguangFlutter/test/data/health_api_provider_test.dart
// M14-T4：scanFood 自带 provider 的信封契约（TDD 先红后绿）。
// 可用配置 → body.provider 恰为 {id,model,key}；未传 / 不可用（含开关关、
// 半成品三项缺一）→ **整键省略**。云端收到 `provider: {}` 会报
// 「自定义模型配置不完整」，故断言 containsKey 为 false，不能只断言空值。
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/data/ai_provider_store.dart';
import 'package:shiguang_flutter/data/api_client.dart';
import 'package:shiguang_flutter/data/health_api.dart';
import 'package:shiguang_flutter/data/token_store.dart';

import '../harness.dart';

void main() {
  late RecordingAdapter adapter;
  late HealthApi api;

  setUp(() {
    adapter = RecordingAdapter();
    api = HealthApi(ApiClient(
      tokenStore: InMemoryTokenStore(),
      dio: Dio()..httpClientAdapter = adapter,
    ));
  });

  test('配置可用 → body 含 provider；不可用/未配置 → 不含', () async {
    await api.scanFood('data:image/jpeg;base64,AAA',
        provider: const AiProviderConfig(enabled: true, id: 'deepseek', model: 'deepseek-flash', key: 'sk-12345678'));
    expect(adapter.envelopes.last['body']['image'], 'data:image/jpeg;base64,AAA');
    expect(adapter.envelopes.last['body']['provider'],
        {'id': 'deepseek', 'model': 'deepseek-flash', 'key': 'sk-12345678'});

    await api.scanFood('data:image/jpeg;base64,AAA',
        provider: const AiProviderConfig(enabled: false, id: 'deepseek', model: 'm', key: 'sk-12345678'));
    expect(adapter.envelopes.last['body'].containsKey('provider'), isFalse);
  });

  test('未传 provider / 半成品配置 → 整键省略（不能发 {}）', () async {
    await api.scanFood('data:image/jpeg;base64,AAA');
    expect(adapter.envelopes.last['body'].containsKey('provider'), isFalse);

    await api.scanFood('data:image/jpeg;base64,AAA',
        provider: const AiProviderConfig(
            enabled: true, id: 'deepseek', model: 'deepseek-flash', key: ''));
    expect(adapter.envelopes.last['body'].containsKey('provider'), isFalse);
  });

  test('scanFood → hint 非空才进 body；空白/未传整键省略', () async {
    await api.scanFood('data:image/jpeg;base64,AAA', hint: '番茄炒蛋');
    expect(adapter.envelopes.last['body']['hint'], '番茄炒蛋');

    await api.scanFood('data:image/jpeg;base64,AAA', hint: '   ');
    expect(adapter.envelopes.last['body'].containsKey('hint'), isFalse);

    await api.scanFood('data:image/jpeg;base64,AAA');
    expect(adapter.envelopes.last['body'].containsKey('hint'), isFalse);
  });

  test('estimateFood → /ai/food-estimate；菜名与 provider 信封同口径', () async {
    await api.estimateFood('番茄炒蛋');
    expect(adapter.envelopes.last['path'], '/ai/food-estimate');
    expect(adapter.envelopes.last['method'], 'POST');
    expect(adapter.envelopes.last['body'], {'name': '番茄炒蛋'});

    await api.estimateFood('番茄炒蛋',
        provider: const AiProviderConfig(
            enabled: true,
            id: 'qwen',
            model: 'qwen-plus',
            key: 'sk-12345678'));
    expect(adapter.envelopes.last['body']['provider'],
        {'id': 'qwen', 'model': 'qwen-plus', 'key': 'sk-12345678'});
  });

  test('cozeChat → /ai/coze-chat；message/date/useTodaySummary/conversationId', () async {
    await api.cozeChat('今天晚餐吃什么？',
        date: '2026-10-20', useTodaySummary: true);
    expect(adapter.envelopes.last['path'], '/ai/coze-chat');
    expect(adapter.envelopes.last['method'], 'POST');
    expect(adapter.envelopes.last['body'], {
      'message': '今天晚餐吃什么？',
      'useTodaySummary': true,
      'date': '2026-10-20',
    });

    await api.cozeChat('继续',
        conversationId: 'conv1', useTodaySummary: false);
    expect(adapter.envelopes.last['body'], {
      'message': '继续',
      'conversationId': 'conv1',
      'useTodaySummary': false,
    });
  });
}
