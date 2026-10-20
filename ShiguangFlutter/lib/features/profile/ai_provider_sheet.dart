// ShiguangFlutter/lib/features/profile/ai_provider_sheet.dart
// M14-T5：「AI 识菜设置」弹层（我的 → AI 识菜设置）。行为权威源
// spec §3.1/§3.2 与控制者四条硬线：
// - 开关「使用我自己的 Key」默认关；关＝走内置通道、**不清除**已存 key
//   （spec §3.2 末条），开关开但配置不完整时保存被拒——绝不落半成品可用态。
// - 厂商 5 项（id 与云函数 ai.js 的 AI_PROVIDERS 一致）；模型名可编辑：
//   DeepSeek 预填 deepseek-flash（服务端已验证的唯一默认值），其余厂商留空
//   强制手填（各家视觉模型 id 常变，不写死）。**切换厂商时模型重置**——
//   DeepSeek 回填默认名、其余清空，防带着上一家型号误用（硬线 3）。
// - Key 输入密文；已保存时输入框留空、占位显示「•••• 末4位」（明文不回填；
//   短 key ≤4 位只显示「••••」，不整串回显），编辑即覆盖；同一厂商下不编辑
//   直接保存 = 保留原 key。**切换厂商视为换凭据**：已存 key 与输入一并清空，
//   保存必须重填——否则空输入会沿用上一家的 Key，造成跨厂商泄漏。
// - 保存前模型名与 key 都 trim；有效 key 为空一律拒绝保存（任何开关状态下都
//   不落空凭据），开关开时 trim 后模型为空也拒绝（硬线 2）。
// - 行内错误随开关/厂商/模型/Key 任一输入变化清除，避免「改了还不消失」。
// - 「清除」= 清存储 + 开关置 false + 清空输入（brief Step 2），不留
//   「开着但没有 key」的悬挂态；厂商回到 DeepSeek。
// - 文案三条逐字：Key 只存本机加密存储/经服务器转发不保存（spec §3.2）、
//   「换人使用请先清除」（Key 是设备级，spec §3.1）、以及硬线 1 的
//   「配置不完整（缺模型或 Key）时仍走内置通道、会消耗内置每日次数」。
// 层内提示走 OverlayEntry/SheetToast（goal_sheet 07b 定式：SnackBar 会被
// 弹层遮挡并向下层 Scaffold 广播双份）。厂商选择用 SimpleDialog——弹层内再开
// 对话框是识菜来源选择的既有形态（food_scan_sheet.dart:119）。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/ai_provider_store.dart';
import '../common/sheet.dart' show showShiguangSheet;
import '../common/sheet_toast.dart' show SheetToast;

/* ---------- Key（简报指定；widget 测试直接按 Key 定位） ---------- */

@visibleForTesting
const aiSwitchKey = Key('ai-switch');

@visibleForTesting
const aiProviderKey = Key('ai-provider');

@visibleForTesting
const aiModelKey = Key('ai-model');

@visibleForTesting
const aiKeyKey = Key('ai-key');

@visibleForTesting
const aiSaveKey = Key('ai-save');

@visibleForTesting
const aiClearKey = Key('ai-clear');

/// DeepSeek 默认模型名（spec §2.2：服务端唯一已验证的默认值）。
const _deepseekDefaultModel = 'deepseek-flash';

/// 厂商选项（id 必须与云函数 ai.js AI_PROVIDERS 的键一致，顺序即下拉顺序）。
const _providerOptions = <({String id, String name})>[
  (id: 'deepseek', name: 'DeepSeek'),
  (id: 'qwen', name: '通义千问'),
  (id: 'kimi', name: 'Kimi'),
  (id: 'zhipu', name: '智谱'),
  (id: 'doubao', name: '豆包'),
];

/// 打开「AI 识菜设置」弹层（≙ 我的 → AI 识菜设置）。存储实现在组合根注入，
/// 本层只依赖 [AiProviderStore] 接口。
Future<void> openAiProviderSheet(BuildContext context, WidgetRef ref) {
  final store = ref.read(aiProviderStoreProvider);
  return showShiguangSheet<void>(
    context,
    title: 'AI 识菜设置',
    child: _AiProviderSheet(store: store),
  );
}

/// 厂商 id → 显示名；未知 id 回落 DeepSeek（存储被改坏时不让下拉空着）。
String _providerName(String id) => _providerOptions
    .firstWhere((p) => p.id == id, orElse: () => _providerOptions.first)
    .name;

bool _knownProvider(String? id) => _providerOptions.any((p) => p.id == id);

class _AiProviderSheet extends StatefulWidget {
  const _AiProviderSheet({required this.store});

  final AiProviderStore store;

  @override
  State<_AiProviderSheet> createState() => _AiProviderSheetState();
}

class _AiProviderSheetState extends State<_AiProviderSheet> {
  final TextEditingController _model = TextEditingController();
  final TextEditingController _key = TextEditingController();

  /// 初值读取在途（load 回来前不渲染表单：防用户先拨开关、随后被预填覆盖）。
  bool _loading = true;

  /// 保存/清除在途（防连点）。
  bool _busy = false;

  bool _enabled = false;
  String _providerId = 'deepseek';

  /// 已保存的 key（明文只留在 State 里供「不编辑即保留」，不回填输入框）。
  String _savedKey = '';

  /// 行内错误（不完整配置/存储失败），红字。
  String? _error;

  OverlayEntry? _toastEntry;

  @override
  void initState() {
    super.initState();
    // 输入一变就清行内错误：用户已经改了，旧提示不该继续挂着。
    _model.addListener(_clearErrorOnEdit);
    _key.addListener(_clearErrorOnEdit);
    _prefill();
  }

  @override
  void dispose() {
    _toastEntry?.remove(); // 层内 toast 随层销毁
    _model.dispose();
    _key.dispose();
    super.dispose();
  }

  /// 读已存配置预填（spec §3.2）。load 自身已把坏数据/读盘异常归为 null；
  /// 这里再兜一层「实现被替换/未注入」，按未配置处理，不打断设置页。
  Future<void> _prefill() async {
    AiProviderConfig? c;
    try {
      c = await widget.store.load();
    } catch (_) {
      c = null;
    }
    if (!mounted) return;
    final id = _knownProvider(c?.id) ? c!.id : 'deepseek';
    setState(() {
      _enabled = c?.enabled ?? false;
      _providerId = id;
      _savedKey = c?.key ?? '';
      _model.text = c == null
          ? (id == 'deepseek' ? _deepseekDefaultModel : '')
          : c.model;
      _loading = false;
    });
  }

  /// 任一输入框变化时清掉行内错误（listener 挂在两个 controller 上）。
  void _clearErrorOnEdit() {
    if (_error == null) return;
    setState(() => _error = null);
  }

  /// Key 占位：已保存只露末 4 位（spec §3.2 密文口径）；短 key 整串回显
  /// 等于没遮，一律只显示「••••」。
  String get _keyHint {
    if (_savedKey.isEmpty) return '粘贴该厂商的 API Key';
    if (_savedKey.length <= 4) return '••••';
    return '•••• ${_savedKey.substring(_savedKey.length - 4)}';
  }

  /// 厂商下拉：弹 SimpleDialog 五项；**选中即重置模型**（硬线 3）。
  Future<void> _pickProvider() async {
    if (_busy) return;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        backgroundColor: Tokens.surface,
        title: const Text('选择厂商'),
        children: [
          for (final p in _providerOptions)
            SimpleDialogOption(
              onPressed: () => Navigator.of(ctx).pop(p.id),
              child: Text(p.name),
            ),
        ],
      ),
    );
    if (!mounted || picked == null || picked == _providerId) return;
    setState(() {
      _providerId = picked;
      // 切换厂商 = 换凭据：模型重置（硬线 3）；已存 key 与输入一并清空，
      // 用户必须重填——否则保存时空输入会沿用上一家的 Key（跨厂商泄漏）。
      _model.text = picked == 'deepseek' ? _deepseekDefaultModel : '';
      _key.clear();
      _savedKey = '';
      _error = null;
    });
  }

  /// 保存：trim → 校验 → 落库（失败停留层内可重试）。
  Future<void> _save() async {
    if (_busy) return;
    final model = _model.text.trim();
    final typedKey = _key.text.trim();
    // 输入框为空 = 沿用已存 key（同厂商下用户没重填不代表要删 key；切厂商时
    // _savedKey 已被清空，不会拿到上一家的凭据）。
    final key = typedKey.isEmpty ? _savedKey : typedKey;
    // 有效 key 为空一律拒绝（含开关关时）：既防空输入在切厂商后复用旧 key，
    // 也防把已存凭据静默写成空串。
    if (key.isEmpty || (_enabled && model.isEmpty)) {
      setState(() => _error = '请填写模型名与 API Key');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.save(AiProviderConfig(
        enabled: _enabled,
        id: _providerId,
        model: model,
        key: key,
      ));
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '保存失败，请重试';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _savedKey = key;
      _model.text = model; // 回写 trim 后的值（输入面与落库一致）
      _key.clear(); // 已存 → 输入框留空、只露「•••• 末4位」
    });
    _toast('已保存');
  }

  /// 清除：清存储 + 开关置 false + 清空输入（brief Step 2 逐字）。
  Future<void> _clear() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.store.clear();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '清除失败，请重试';
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _enabled = false;
      _providerId = 'deepseek';
      _model.clear();
      _key.clear();
      _savedKey = '';
    });
    _toast('已清除');
  }

  /// 层内 toast（SheetToast 定式；同刻只留一条）。
  void _toast(String msg) {
    final overlay = Overlay.of(context);
    _toastEntry?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => SheetToast(
        msg: msg,
        onDone: () {
          if (entry.mounted) entry.remove();
          if (identical(_toastEntry, entry)) _toastEntry = null;
        },
      ),
    );
    _toastEntry = entry;
    overlay.insert(entry);
  }

  static const _label = TextStyle(
      fontSize: Tokens.textSm, fontWeight: FontWeight.w700, color: Tokens.ink);
  static const _sub = TextStyle(fontSize: Tokens.textXs, color: Tokens.ink3);

  InputDecoration _field(String hint) => InputDecoration(
        hintText: hint,
        isDense: true,
        counterText: '',
      );

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      // 初值未知时不渲染可交互表单（防「先拨开关 → 预填覆盖」竞态）。
      return const Padding(
        padding: EdgeInsets.all(Tokens.sp6),
        child: Center(
          child: SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    return Padding(
      // 键盘上滚（表单可滚到保存/清除钮）
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
            Tokens.sp5, 0, Tokens.sp5, Tokens.sp4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: Tokens.sp3),
            Row(
              children: [
                const Expanded(
                    child: Text('使用我自己的 Key', style: _label)),
                Switch(
                  key: aiSwitchKey,
                  value: _enabled,
                  onChanged: _busy
                      ? null
                      : (v) => setState(() {
                            _enabled = v;
                            _error = null; // 输入变化即清旧错误
                          }),
                ),
              ],
            ),
            const SizedBox(height: Tokens.sp1),
            // spec §3.2 说明文案逐字；「换人使用请先清除」= spec §3.1 设备级提示
            const Text('Key 只存在本机加密存储；每次识别经你的服务器转发给厂商，不会保存。',
                style: _sub),
            const SizedBox(height: Tokens.sp1),
            const Text('换人使用请先清除',
                style: TextStyle(fontSize: Tokens.textXs, color: Tokens.warn)),
            const SizedBox(height: Tokens.sp2),
            // 控制者硬线 1：配置不完整仍走内置并消耗内置次数（必须写明）
            const Text('配置不完整（缺模型或 Key）时仍走内置通道、会消耗内置每日次数',
                style: TextStyle(fontSize: Tokens.textSm, color: Tokens.ink2)),
            const SizedBox(height: Tokens.sp3),
            const Text('厂商', style: _label),
            const SizedBox(height: Tokens.sp1),
            // 触发器（Key ai-provider）：点开 SimpleDialog 五项
            InkWell(
              key: aiProviderKey,
              onTap: _busy ? null : _pickProvider,
              borderRadius: BorderRadius.circular(Tokens.radiusSm),
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: Tokens.sp3, vertical: Tokens.sp3),
                decoration: BoxDecoration(
                  color: Tokens.surface2,
                  borderRadius: BorderRadius.circular(Tokens.radiusSm),
                  border: Border.all(color: Tokens.line),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(_providerName(_providerId),
                          style: const TextStyle(
                              fontSize: Tokens.textMd, color: Tokens.ink)),
                    ),
                    const Icon(Icons.arrow_drop_down, color: Tokens.ink3),
                  ],
                ),
              ),
            ),
            const SizedBox(height: Tokens.sp3),
            const Text('模型名', style: _label),
            const SizedBox(height: Tokens.sp1),
            TextField(
              controller: _model,
              key: aiModelKey,
              enabled: !_busy,
              decoration: _field(
                _providerId == 'deepseek'
                    ? _deepseekDefaultModel
                    : '填该厂商的视觉模型名',
              ),
            ),
            const SizedBox(height: Tokens.sp3),
            const Text('API Key', style: _label),
            const SizedBox(height: Tokens.sp1),
            TextField(
              controller: _key,
              key: aiKeyKey,
              enabled: !_busy,
              obscureText: true,
              autocorrect: false,
              enableSuggestions: false,
              decoration: _field(_keyHint),
            ),
            if (_error != null) ...[
              const SizedBox(height: Tokens.sp2),
              Text(_error!,
                  key: const Key('ai-error'),
                  style: const TextStyle(
                      fontSize: Tokens.textSm, color: Tokens.danger)),
            ],
            const SizedBox(height: Tokens.sp4),
            FilledButton(
              key: aiSaveKey,
              onPressed: _busy ? null : _save,
              child: Text(_busy ? '保存中…' : '保存'),
            ),
            const SizedBox(height: Tokens.sp2),
            OutlinedButton(
              key: aiClearKey,
              onPressed: _busy ? null : _clear,
              child: const Text('清除'),
            ),
          ],
        ),
      ),
    );
  }
}
