// P4a/P4b：AI 饮食助手聊天页（文字多轮 + 今日摘要开关 + 回复朗读按钮）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/theme.dart' show shiguangTheme;
import 'package:shiguang_flutter/data/api_client.dart' show ApiException;
import 'package:shiguang_flutter/data/tts_service.dart';
import 'package:shiguang_flutter/features/chat/ai_chat_screen.dart';
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider;

import 'harness.dart' show useBigSurface;
import 'stubs/stub_health_api.dart';

class FakeTts implements TtsService {
  bool available = true;
  String? spoken;
  int stops = 0;

  @override
  Future<bool> prepare() async => available;

  @override
  Future<void> speak(String text) async {
    if (!available) throw StateError('系统没有可用的中文语音包');
    spoken = text;
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

Future<FakeTts> pumpChat(WidgetTester tester, StubHealthApi api) async {
  await useBigSurface(tester);
  final tts = FakeTts();
  await tester.pumpWidget(ProviderScope(
    overrides: [
      healthApiProvider.overrideWithValue(api),
      ttsServiceProvider.overrideWithValue(tts),
    ],
    child: MaterialApp(
      theme: shiguangTheme(),
      home: const AiChatScreen(),
    ),
  ));
  await tester.pumpAndSettle();
  return tts;
}

void main() {
  testWidgets('空态显示推荐问题；发送后展示用户与助手消息，并带 conversationId',
      (tester) async {
    final api = StubHealthApi()
      ..cozeResult = {
        'ok': true,
        'reply': '今天的蛋白质还差 53g，晚餐加 120g 瘦牛肉。',
        'conversationId': 'conv1',
      };
    await pumpChat(tester, api);

    expect(find.text('我是食光饮食助手'), findsOneWidget);
    expect(find.text('今天的热量和蛋白质够吗？'), findsOneWidget);

    await tester.enterText(
        find.byKey(const Key('ai-chat-input')), '今天晚餐吃什么？');
    await tester.tap(find.byKey(const Key('ai-chat-send')));
    await tester.pumpAndSettle();

    expect(api.cozeCalls, 1);
    expect(api.lastCozeMessage, '今天晚餐吃什么？');
    expect(api.lastCozeUseSummary, isTrue);
    expect(api.lastCozeDate, hasLength(10));
    expect(api.lastCozeConversationId, isNull);
    expect(find.text('今天晚餐吃什么？'), findsOneWidget);
    expect(find.text('今天的蛋白质还差 53g，晚餐加 120g 瘦牛肉。'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('ai-chat-input')), '继续');
    await tester.tap(find.byKey(const Key('ai-chat-send')));
    await tester.pumpAndSettle();
    expect(api.lastCozeConversationId, 'conv1');
  });

  testWidgets('推荐问题直接发送；关闭今日摘要后 useTodaySummary=false', (tester) async {
    final api = StubHealthApi();
    await pumpChat(tester, api);

    await tester.tap(find.text('晚餐吃什么比较合适？'));
    await tester.pumpAndSettle();
    expect(api.cozeCalls, 1);
    expect(api.lastCozeMessage, '晚餐吃什么比较合适？');
    expect(api.lastCozeUseSummary, isTrue);

    await tester.tap(find.byKey(const Key('ai-chat-summary')));
    await tester.pump();
    await tester.enterText(find.byKey(const Key('ai-chat-input')), '继续');
    await tester.tap(find.byKey(const Key('ai-chat-send')));
    await tester.pumpAndSettle();
    expect(api.lastCozeUseSummary, isFalse);
  });

  testWidgets('助手消息有朗读按钮；点一次把正文交给 TTS；新对话会停止并清空',
      (tester) async {
    final api = StubHealthApi()
      ..cozeResult = {
        'ok': true,
        'reply': '晚餐加一份水煮虾。',
        'conversationId': 'conv1',
      };
    final tts = await pumpChat(tester, api);
    await tester.enterText(find.byKey(const Key('ai-chat-input')), '晚餐怎么补？');
    await tester.tap(find.byKey(const Key('ai-chat-send')));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.volume_up_outlined), findsOneWidget);
    await tester.tap(find.byIcon(Icons.volume_up_outlined));
    await tester.pump();
    expect(tts.spoken, '晚餐加一份水煮虾。');

    await tester.tap(find.byKey(const Key('ai-chat-new')));
    await tester.pumpAndSettle();
    expect(tts.stops, greaterThan(0));
    expect(find.text('晚餐加一份水煮虾。'), findsNothing);
    expect(find.text('我是食光饮食助手'), findsOneWidget);
  });

  testWidgets('TTS 中文语音不可用时提示，不崩溃', (tester) async {
    final api = StubHealthApi()
      ..cozeResult = {
        'ok': true,
        'reply': '晚餐加一份水煮虾。',
        'conversationId': 'conv1',
      };
    final tts = await pumpChat(tester, api);
    tts.available = false;
    await tester.enterText(find.byKey(const Key('ai-chat-input')), '晚餐怎么补？');
    await tester.tap(find.byKey(const Key('ai-chat-send')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.volume_up_outlined));
    await tester.pump();
    expect(find.text('朗读失败：系统没有可用的中文语音包'), findsOneWidget);
  });

  testWidgets('接口失败显示错误行，保留用户消息', (tester) async {
    final api = StubHealthApi()
      ..cozeError = ApiException('AI 助手未授权，请检查令牌');
    await pumpChat(tester, api);
    await tester.enterText(find.byKey(const Key('ai-chat-input')), '你好');
    await tester.tap(find.byKey(const Key('ai-chat-send')));
    await tester.pumpAndSettle();

    expect(find.text('请求失败：AI 助手未授权，请检查令牌'), findsOneWidget);
    expect(find.text('你好'), findsOneWidget);
    expect(find.text('正在思考…'), findsNothing);
  });
}
