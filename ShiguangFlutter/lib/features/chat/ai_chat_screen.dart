// P4：AI 饮食助手聊天页（文字多轮 + 可选今日摘要 + 回复朗读）。
// V1 只做「点了才读」的系统 TTS，不做语音输入/免手循环；默认不自动播。
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/api_client.dart' show ApiException;
import '../../data/tts_service.dart';
import '../../domain/dates.dart' show todayIso;
import '../home/home_controller.dart' show healthApiProvider;

const _suggestions = <String>[
  '今天的热量和蛋白质够吗？',
  '晚餐吃什么比较合适？',
  '今天运动了，还需要补什么？',
  '帮我看看今天哪一餐吃得太油？',
];

class AiChatScreen extends ConsumerStatefulWidget {
  const AiChatScreen({super.key, this.embedded = false});

  /// true 时嵌在半屏底部面板里，不重复套 Scaffold/AppBar。
  final bool embedded;

  @override
  ConsumerState<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends ConsumerState<AiChatScreen> {
  final List<_ChatMessage> _messages = <_ChatMessage>[];
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  late final TtsService _tts;

  String? _conversationId;
  String? _error;
  int? _speakingId;
  bool _useTodaySummary = true;
  bool _sending = false;
  int _seq = 0;
  int _epoch = 0;

  @override
  void initState() {
    super.initState();
    _tts = ref.read(ttsServiceProvider);
  }

  @override
  void dispose() {
    unawaited(_tts.stop());
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _send([String? preset]) async {
    if (_sending) return;
    final text = (preset ?? _input.text).trim();
    if (text.isEmpty) return;
    if (_speakingId != null) await _stopSpeak();
    if (!mounted) return;
    final epoch = _epoch;
    setState(() {
      _messages.add(_ChatMessage(++_seq, _ChatRole.user, text));
      _input.clear();
      _sending = true;
      _error = null;
    });
    _scrollToBottom();
    try {
      final r = await ref.read(healthApiProvider).cozeChat(
            text,
            conversationId: _conversationId,
            useTodaySummary: _useTodaySummary,
            date: todayIso(),
          );
      if (!mounted || epoch != _epoch) return;
      final reply = '${r['reply'] ?? ''}'.trim();
      final cid = '${r['conversationId'] ?? ''}'.trim();
      if (reply.isEmpty) throw ApiException('AI 助手没有返回内容');
      setState(() {
        _messages.add(_ChatMessage(++_seq, _ChatRole.assistant, reply));
        if (cid.isNotEmpty) _conversationId = cid;
        _sending = false;
      });
      _scrollToBottom();
    } catch (e) {
      if (!mounted || epoch != _epoch) return;
      setState(() {
        _sending = false;
        _error = '请求失败：${e is ApiException ? e.message : '网络异常'}';
      });
      _scrollToBottom();
    }
  }

  Future<void> _newChat() async {
    _epoch++;
    await _stopSpeak();
    if (!mounted) return;
    setState(() {
      _messages.clear();
      _conversationId = null;
      _error = null;
      _sending = false;
    });
  }

  Future<void> _toggleSpeak(_ChatMessage m) async {
    if (_speakingId == m.id) {
      await _stopSpeak();
      return;
    }
    if (_speakingId != null) await _stopSpeak();
    if (!mounted) return;
    setState(() => _speakingId = m.id);
    try {
      await _tts.speak(m.text);
    } on StateError catch (e) {
      if (mounted) _toast('朗读失败：${e.message}');
    } catch (_) {
      if (mounted) _toast('朗读失败：系统语音不可用');
    } finally {
      if (mounted && _speakingId == m.id) {
        setState(() => _speakingId = null);
      }
    }
  }

  Future<void> _stopSpeak() async {
    await _tts.stop();
    if (mounted) setState(() => _speakingId = null);
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedded) {
      return ClipRRect(
        borderRadius: const BorderRadius.vertical(
            top: Radius.circular(Tokens.radiusSheet)),
        child: ColoredBox(
          color: Tokens.surface2,
          child: Column(
            children: [
              _sheetHeader(),
              Expanded(child: _chatBody()),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      backgroundColor: Tokens.bg,
      appBar: AppBar(
        backgroundColor: Tokens.bg,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Text('AI 饮食助手',
            style: TextStyle(
                fontSize: Tokens.textLg,
                fontWeight: FontWeight.w800,
                color: Tokens.ink)),
        actions: [
          IconButton(
            key: const Key('ai-chat-new'),
            tooltip: '新对话',
            onPressed: _sending ? null : _newChat,
            icon: const Icon(Icons.add_comment_outlined, color: Tokens.ink2),
          ),
        ],
      ),
      body: _chatBody(),
    );
  }

  Widget _sheetHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.sp2, Tokens.sp2, Tokens.sp2, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 38,
            height: 4,
            decoration: BoxDecoration(
              color: Tokens.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          SizedBox(
            height: 48,
            child: Row(
              children: [
                IconButton(
                  key: const Key('ai-chat-close'),
                  tooltip: '收起',
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: const Icon(Icons.keyboard_arrow_down, color: Tokens.ink2),
                ),
                const Expanded(
                  child: Center(
                    child: Text('AI 饮食助手',
                        style: TextStyle(
                            fontSize: Tokens.textMd,
                            fontWeight: FontWeight.w800,
                            color: Tokens.ink)),
                  ),
                ),
                IconButton(
                  key: const Key('ai-chat-new'),
                  tooltip: '新对话',
                  onPressed: _sending ? null : _newChat,
                  icon: const Icon(Icons.add_comment_outlined, color: Tokens.ink2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _chatBody() {
    return SafeArea(
      top: false,
      child: Column(
        children: [
          _summaryBar(),
          Expanded(child: _messageList()),
          if (_error != null) _errorBar(_error!),
          _inputBar(),
          const Padding(
            padding: EdgeInsets.fromLTRB(Tokens.sp4, 0, Tokens.sp4, Tokens.sp2),
            child: Text(
              'AI 建议仅供参考，不能替代医生或营养师诊断。',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: Tokens.textXs, color: Tokens.ink3),
            ),
          ),
        ],
      ),
    );
  }

  Widget _summaryBar() {
    return Container(
      margin: const EdgeInsets.fromLTRB(
          Tokens.sp3, Tokens.sp1, Tokens.sp3, Tokens.sp1),
      padding: const EdgeInsets.fromLTRB(
          Tokens.sp3, Tokens.sp2, Tokens.sp2, Tokens.sp2),
      decoration: BoxDecoration(
        color: Tokens.surfaceSoft,
        borderRadius: BorderRadius.circular(Tokens.radiusMd),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, size: 18, color: Tokens.primary),
          const SizedBox(width: Tokens.sp2),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('参考今日饮食',
                    style: TextStyle(
                        fontSize: Tokens.textSm,
                        fontWeight: FontWeight.w700,
                        color: Tokens.ink)),
                Text(
                  _useTodaySummary
                      ? '会发送今天的饮食摘要给扣子智能体'
                      : '不发送今天的饮食数据',
                  style: const TextStyle(
                      fontSize: Tokens.textXs, color: Tokens.ink3),
                ),
              ],
            ),
          ),
          Switch(
            key: const Key('ai-chat-summary'),
            value: _useTodaySummary,
            activeTrackColor: Tokens.primarySoft,
            activeThumbColor: Tokens.primaryDeep,
            onChanged: (v) => setState(() => _useTodaySummary = v),
          ),
        ],
      ),
    );
  }

  Widget _messageList() {
    final showEmpty = _messages.isEmpty && !_sending;
    return ListView(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(
          Tokens.sp4, Tokens.sp3, Tokens.sp4, Tokens.sp4),
      children: [
        if (showEmpty) _emptyState(),
        for (final m in _messages) _bubble(m),
        if (_sending) _thinkingBubble(),
      ],
    );
  }

  Widget _emptyState() {
    final compact = widget.embedded;
    return Column(
      children: [
        SizedBox(height: compact ? Tokens.sp3 : Tokens.sp8),
        Icon(Icons.restaurant_menu,
            size: compact ? 32 : 44, color: Tokens.primary),
        SizedBox(height: compact ? Tokens.sp2 : Tokens.sp3),
        Text('我是食光饮食助手',
            style: TextStyle(
                fontSize: compact ? Tokens.textMd : Tokens.textLg,
                fontWeight: FontWeight.w800,
                color: Tokens.ink)),
        const SizedBox(height: Tokens.sp1),
        const Text(
          '可以问我今天吃得怎么样、下一餐怎么搭配、外卖怎么选。',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: Tokens.textSm, color: Tokens.ink3),
        ),
        SizedBox(height: compact ? Tokens.sp3 : Tokens.sp4),
        if (compact)
          Column(
            children: [
              for (final q in _suggestions)
                Padding(
                  padding: const EdgeInsets.only(bottom: 5),
                  child: SizedBox(
                    width: double.infinity,
                    child: OutlinedButton(
                      onPressed: _sending ? null : () => _send(q),
                      style: OutlinedButton.styleFrom(
                        backgroundColor: Tokens.surface,
                        foregroundColor: Tokens.ink,
                        side: const BorderSide(color: Tokens.line),
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(
                            horizontal: Tokens.sp3),
                        alignment: Alignment.centerLeft,
                        shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(Tokens.radiusSm)),
                        textStyle: const TextStyle(fontSize: Tokens.textSm),
                      ),
                      child: Text(q),
                    ),
                  ),
                ),
            ],
          )
        else
          Wrap(
            spacing: Tokens.sp2,
            runSpacing: Tokens.sp2,
            alignment: WrapAlignment.center,
            children: [
              for (final q in _suggestions)
                ActionChip(
                  label: Text(q),
                  onPressed: _sending ? null : () => _send(q),
                  backgroundColor: Tokens.surface,
                  side: const BorderSide(color: Tokens.line),
                  labelStyle: const TextStyle(
                      fontSize: Tokens.textSm, color: Tokens.ink2),
                ),
            ],
          ),
      ],
    );
  }

  Widget _thinkingBubble() {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: Tokens.sp3),
        padding: const EdgeInsets.all(Tokens.sp3),
        decoration: BoxDecoration(
          color: Tokens.surface,
          borderRadius: BorderRadius.circular(Tokens.radiusLg),
          border: Border.all(color: Tokens.line),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: Tokens.sp2),
            Text('正在思考…',
                style: TextStyle(fontSize: Tokens.textSm, color: Tokens.ink3)),
          ],
        ),
      ),
    );
  }

  Widget _bubble(_ChatMessage m) {
    final isUser = m.role == _ChatRole.user;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: Tokens.sp3),
        constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        padding: const EdgeInsets.fromLTRB(
            Tokens.sp3, Tokens.sp2, Tokens.sp3, Tokens.sp1),
        decoration: BoxDecoration(
          color: isUser ? Tokens.primaryDeep : Tokens.surface,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(Tokens.radiusLg),
            topRight: const Radius.circular(Tokens.radiusLg),
            bottomLeft: Radius.circular(
                isUser ? Tokens.radiusLg : Tokens.radiusSm),
            bottomRight: Radius.circular(
                isUser ? Tokens.radiusSm : Tokens.radiusLg),
          ),
          border: isUser ? null : Border.all(color: Tokens.line),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              m.text,
              style: TextStyle(
                  fontSize: Tokens.textMd,
                  height: 1.45,
                  color: isUser ? Colors.white : Tokens.ink),
            ),
            if (!isUser)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    key: ValueKey('tts-${m.id}'),
                    tooltip: _speakingId == m.id ? '停止朗读' : '朗读',
                    onPressed: () => _toggleSpeak(m),
                    iconSize: 18,
                    visualDensity: VisualDensity.compact,
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    padding: EdgeInsets.zero,
                    icon: Icon(
                      _speakingId == m.id
                          ? Icons.stop_circle_outlined
                          : Icons.volume_up_outlined,
                      color: Tokens.primaryDeep,
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _errorBar(String text) {
    return Container(
      width: double.infinity,
      color: Tokens.warnSoft,
      padding: const EdgeInsets.symmetric(
          horizontal: Tokens.sp4, vertical: Tokens.sp2),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 16, color: Tokens.danger),
          const SizedBox(width: Tokens.sp2),
          Expanded(
            child: Text(text,
                style: const TextStyle(
                    fontSize: Tokens.textSm, color: Tokens.danger)),
          ),
        ],
      ),
    );
  }

  Widget _inputBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          Tokens.sp4, Tokens.sp2, Tokens.sp4, Tokens.sp1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              key: const Key('ai-chat-input'),
              controller: _input,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              decoration: InputDecoration(
                hintText: '问我今天吃得怎么样…',
                hintStyle:
                    const TextStyle(fontSize: Tokens.textMd, color: Tokens.ink3),
                filled: true,
                fillColor: Tokens.surface,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                    horizontal: Tokens.sp3, vertical: Tokens.sp3),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Tokens.radiusLg),
                  borderSide: const BorderSide(color: Tokens.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(Tokens.radiusLg),
                  borderSide: const BorderSide(color: Tokens.primary),
                ),
              ),
            ),
          ),
          const SizedBox(width: Tokens.sp2),
          IconButton.filled(
            key: const Key('ai-chat-send'),
            tooltip: '发送',
            onPressed: _sending ? null : () => _send(),
            style: IconButton.styleFrom(
              backgroundColor: Tokens.primaryDeep,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Tokens.line,
            ),
            icon: const Icon(Icons.arrow_upward),
          ),
        ],
      ),
    );
  }
}

/// 半屏打开时隐藏左下入口头像，避免遮罩下残留/错位。
final ValueNotifier<bool> aiChatSheetVisible = ValueNotifier<bool>(false);

/// 打开固定 62% 的半屏聊天。收起即销毁本次会话，重新打开从空态开始。
Future<void> showAiChatSheet(BuildContext context) async {
  aiChatSheetVisible.value = true;
  try {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      barrierColor: const Color(0x5C1C2418),
      builder: (sheetContext) {
        final media = MediaQuery.of(sheetContext);
        final keyboard = media.viewInsets.bottom;
        final available =
            media.size.height - keyboard - media.padding.top - Tokens.sp3;
        final height =
            math.min(media.size.height * 0.62, math.max(0.0, available));
        return Padding(
          padding: EdgeInsets.only(bottom: keyboard),
          child: SizedBox(
            height: height,
            child: const AiChatScreen(embedded: true),
          ),
        );
      },
    );
  } finally {
    aiChatSheetVisible.value = false;
  }
}

enum _ChatRole { user, assistant }

class _ChatMessage {
  _ChatMessage(this.id, this.role, this.text);
  final int id;
  final _ChatRole role;
  final String text;
}
