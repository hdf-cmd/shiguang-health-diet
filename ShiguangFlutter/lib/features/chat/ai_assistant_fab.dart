// P4 后续：AI 饮食助手入口=圆形 3D 头像「小光」。
// 默认左下、可拖拽吸附左右边缘；底部 AI 字标提示这是助手，不是用户头像。
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'ai_chat_screen.dart';

class AiAssistantFab extends StatefulWidget {
  const AiAssistantFab({super.key});

  static const size = 64.0;
  static const horizontalMargin = Tokens.sp4;

  /// 记录页底部「＋ 记一笔」= 52 高 + sp3 下边距；再留 sp3，头像不压主操作。
  static const bottomGap = 52.0 + Tokens.sp3 * 2;

  @override
  State<AiAssistantFab> createState() => _AiAssistantFabState();
}

class _AiAssistantFabState extends State<AiAssistantFab> {
  double? _left;
  double? _top;
  bool _dragging = false;

  Future<void> _openChat() async {
    await showAiChatSheet(context);
  }

  void _endDrag({
    required double minX,
    required double maxX,
    required double minY,
    required double maxY,
    required double width,
  }) {
    setState(() {
      _dragging = false;
      final left = _clamp(_left ?? minX, minX, maxX);
      _top = _clamp(_top ?? minY, minY, maxY);
      _left = left + AiAssistantFab.size / 2 < width / 2 ? minX : maxX;
    });
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top;
    return LayoutBuilder(
      builder: (context, constraints) {
        final minX = AiAssistantFab.horizontalMargin;
        final maxX = math.max(
            minX, constraints.maxWidth - AiAssistantFab.size - minX);
        final minY = topInset + Tokens.sp2;
        final maxY = math.max(
            minY,
            constraints.maxHeight -
                AiAssistantFab.size -
                AiAssistantFab.bottomGap);
        final left = _clamp(_left ?? minX, minX, maxX);
        final top = _clamp(_top ?? maxY, minY, maxY);

        return ValueListenableBuilder<bool>(
          valueListenable: aiChatSheetVisible,
          builder: (context, sheetOpen, _) {
            if (sheetOpen) return const SizedBox.shrink();
            return Stack(
              clipBehavior: Clip.none,
              children: [
                AnimatedPositioned(
              duration:
                  _dragging ? Duration.zero : const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              left: left,
              top: top,
              width: AiAssistantFab.size,
              height: AiAssistantFab.size,
              child: Semantics(
                button: true,
                label: 'AI 饮食助手',
                child: GestureDetector(
                  key: const Key('ai-fab'),
                  behavior: HitTestBehavior.opaque,
                  onTap: _openChat,
                  onPanStart: (_) => setState(() {
                    _dragging = true;
                    _left = left;
                    _top = top;
                  }),
                  onPanUpdate: (details) => setState(() {
                    _left = _clamp(
                        _left! + details.delta.dx, minX, maxX);
                    _top = _clamp(_top! + details.delta.dy, minY, maxY);
                  }),
                  onPanEnd: (_) => _endDrag(
                    minX: minX,
                    maxX: maxX,
                    minY: minY,
                    maxY: maxY,
                    width: constraints.maxWidth,
                  ),
                  onPanCancel: () => _endDrag(
                    minX: minX,
                    maxX: maxX,
                    minY: minY,
                    maxY: maxY,
                    width: constraints.maxWidth,
                  ),
                  child: const ExcludeSemantics(child: _AvatarBody()),
                ),
              ),
            ),
              ],
            );
          },
        );
      },
    );
  }
}

double _clamp(double value, double min, double max) =>
    value < min ? min : (value > max ? max : value);

class _AvatarBody extends StatelessWidget {
  const _AvatarBody();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: AiAssistantFab.size,
      height: AiAssistantFab.size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Tokens.surface2,
                border: Border.all(color: Tokens.surface2, width: 2),
                boxShadow: const [
                  BoxShadow(color: Color(0x1F234D30), spreadRadius: 1),
                  BoxShadow(
                    color: Color(0x3D1C2418),
                    blurRadius: 24,
                    offset: Offset(0, 10),
                    spreadRadius: -4,
                  ),
                ],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/ai_avatar.png',
                  fit: BoxFit.cover,
                  filterQuality: FilterQuality.high,
                  errorBuilder: (_, _, _) =>
                      const ColoredBox(color: Tokens.primarySoft),
                ),
              ),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: -6,
            child: Center(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: Tokens.surface2,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: Tokens.primaryDeep),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x2E1C2418),
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: const Text(
                  'AI',
                  style: TextStyle(
                    fontSize: 9,
                    height: 1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: .8,
                    color: Tokens.primaryDeep,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
