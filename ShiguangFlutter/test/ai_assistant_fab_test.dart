// P4 后续：AI 饮食助手圆形头像入口——默认位、拖拽吸附、点按打开半屏聊天。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/data/tts_service.dart';
import 'package:shiguang_flutter/features/chat/ai_assistant_fab.dart';
import 'package:shiguang_flutter/features/chat/ai_chat_screen.dart';
import 'package:shiguang_flutter/features/home/home_controller.dart'
    show healthApiProvider;

import 'stubs/stub_health_api.dart';

class _FakeTts implements TtsService {
  @override
  Future<bool> prepare() async => true;

  @override
  Future<void> speak(String text) async {}

  @override
  Future<void> stop() async {}
}

void main() {
  setUp(() => aiChatSheetVisible.value = false);

  Widget harness() => ProviderScope(
        overrides: [
          healthApiProvider.overrideWithValue(StubHealthApi()),
          ttsServiceProvider.overrideWithValue(_FakeTts()),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                SizedBox.expand(),
                Positioned.fill(child: AiAssistantFab()),
              ],
            ),
          ),
        ),
      );

  testWidgets('默认停左下（圆形头像 + AI 字标），且高于底部主操作区',
      (tester) async {
    await tester.pumpWidget(harness());
    final screen = tester.getSize(find.byType(Scaffold));
    final rect = tester.getRect(find.byKey(const Key('ai-fab')));

    expect(rect.left,
        closeTo(AiAssistantFab.horizontalMargin, 0.01));
    expect(rect.bottom,
        closeTo(screen.height - AiAssistantFab.bottomGap, 0.01));
    expect(rect.width, AiAssistantFab.size);
    expect(rect.height, AiAssistantFab.size);
    expect(find.text('AI'), findsOneWidget);
  });

  testWidgets('拖到右侧松手吸附右边缘，不误开聊天页', (tester) async {
    await tester.pumpWidget(harness());
    await tester.drag(
        find.byKey(const Key('ai-fab')), const Offset(600, -100));
    await tester.pumpAndSettle();

    final screen = tester.getSize(find.byType(Scaffold));
    final rect = tester.getRect(find.byKey(const Key('ai-fab')));
    expect(rect.right,
        closeTo(screen.width - AiAssistantFab.horizontalMargin, 0.01));
    expect(find.byType(AiChatScreen), findsNothing);
  });

  testWidgets('拖到顶部停在标题区之下（不压问候/页标题）', (tester) async {
    await tester.pumpWidget(harness());
    await tester.drag(find.byKey(const Key('ai-fab')), const Offset(0, -2000));
    await tester.pumpAndSettle();
    final rect = tester.getRect(find.byKey(const Key('ai-fab')));
    expect(rect.top,
        closeTo(AiAssistantFab.headerReserve, 0.01));
  });

  testWidgets('再拖回左侧松手吸附左边缘', (tester) async {
    await tester.pumpWidget(harness());
    await tester.drag(find.byKey(const Key('ai-fab')), const Offset(600, 0));
    await tester.pumpAndSettle();
    await tester.drag(find.byKey(const Key('ai-fab')), const Offset(-600, 0));
    await tester.pumpAndSettle();

    final rect = tester.getRect(find.byKey(const Key('ai-fab')));
    expect(rect.left, closeTo(AiAssistantFab.horizontalMargin, 0.01));
  });

  testWidgets('点圆形头像打开 62% 半屏；收起后重新打开从空态开始',
      (tester) async {
    await tester.pumpWidget(harness());
    final screen = tester.getSize(find.byType(Scaffold));
    await tester.tap(find.byKey(const Key('ai-fab')));
    await tester.pumpAndSettle();

    expect(find.byType(AiChatScreen), findsOneWidget);
    expect(find.text('AI 饮食助手'), findsOneWidget);
    expect(find.byKey(const Key('ai-chat-close')), findsOneWidget);
    expect(find.byKey(const Key('ai-fab')), findsNothing);
    final sheetSize = tester.getSize(find.byType(AiChatScreen));
    expect(sheetSize.height, closeTo(screen.height * 0.62, 1.0));

    await tester.enterText(find.byKey(const Key('ai-chat-input')), '测试对话');
    await tester.tap(find.byKey(const Key('ai-chat-send')));
    await tester.pumpAndSettle();
    expect(find.text('测试对话'), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai-chat-close')));
    await tester.pumpAndSettle();
    expect(find.byType(AiChatScreen), findsNothing);
    expect(find.byKey(const Key('ai-fab')), findsOneWidget);

    await tester.tap(find.byKey(const Key('ai-fab')));
    await tester.pumpAndSettle();
    expect(find.byType(AiChatScreen), findsOneWidget);
    expect(find.text('测试对话'), findsNothing);
    expect(find.text('我是食光饮食助手'), findsOneWidget);
  });
}
