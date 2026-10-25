// ShiguangFlutter/lib/features/profile/profile_edit_sheet.dart
// M5 Task 5：「我的」页资料编辑弹层（改名/改签名/换头像）。
// 行为权威源 H5（文案逐字）：
// - openProfileEdit（js/app.js:1137-1144）：资料未加载（!p）点开为 no-op；
//   预填 nickname||'' / signature||''；弹层头像预览 updatePeAvatar
//   （:1126-1136）：avatarData 画 img，否则 avatarText||nickname[0]||'食'。
// - pe-save（:1153-1166）：昵称 trim 空 → toast「昵称不能为空」return；
//   成功 → updateProfile({nickname,signature}) → 重取资料（:1159 getProfile +
//   renderProfile ≙ ref.invalidate(profileProvider)）→ closeProfileEdit →
//   toast「资料已保存」；catch → 「保存失败：' + (e.message||'网络异常')」。
// - handleAvatarPick（:1105-1119，经 T3 pickCompressedImageDataUrl）：取消静默
//   （:1106 !file return）；压缩后超限 → 「图片仍过大，请换一张」（:1111 逐字）；
//   读取/编码失败 → 「图片处理失败」（T3 新增映射，H5 的「请选择图片文件」/
//   「图片太大…5MB」两闸在原生重编码后不可见——差异已在 image_pick.dart 登记）；
//   成功 → updateAvatar(dataUrl) → toast「头像已更新」→ invalidate 重取
//   （:1114-1115 同款，弹层预览与页头随之刷新）；失败 → catch 统一
//   「头像上传失败：${e.message||'网络异常'}」（:1117 逐字。简报④写成
//   「保存失败：boom」，但 H5 :1117 为头像链权威，按逐字对齐取本分支）。
// 选择器注入：image_picker 插件不进 widget 测试——「选图」以顶层函数引用
// （AvatarPicker 参数，默认 galleryAvatarPicker）注入，测试传 fake；
// 真机选图链留 T8 抽查（简报 Step 1 ④）。
// 版式 R4 自主设计：H5 #pe-sheet（index.html:437-457）字段次序与文案保留
// —— 标题「编辑资料」、右上「✕」（aria 关闭）、头像行（预览+「更换头像」）、
// 标签「昵称」/「签名」（:448/:452）、占位「昵称」/「个性签名」、
// maxlength 28/40（:449/:453）、「保存」。H5 弹层内「退出登录」（:456）已由
// M4-T4 收敛到页面卡片，弹层不重复摆放。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../app/theme.dart';
import '../../data/api_client.dart' show ApiException;
import '../common/food_thumb.dart';
import '../common/image_pick.dart';
import '../common/breathing_capsule.dart' show LoadingSpinner;
import '../common/sheet.dart' show showShiguangSheet;
import '../home/home_controller.dart' show healthApiProvider;
import 'profile_providers.dart';

typedef AvatarPicker = Future<PickedImageData> Function();

/// 生产默认选择器：系统相册（≙ H5 #avatar-input 文件选择，js/app.js:1120）。
Future<PickedImageData> galleryAvatarPicker() =>
    pickCompressedImageDataUrl(ImageSource.gallery);

/// 头像 dataURL（非空串才算有图，renderProfile :1008 真值判定）。
String? avatarDataOf(Map<String, dynamic> p) {
  final v = p['avatarData'];
  return v is String && v.isNotEmpty ? v : null;
}

/// 无头像时的占位字：avatarText || nickname 首字（renderProfile :1018）。
/// [fallback] 对应弹层预览的 ''/'食' 兜底链（updatePeAvatar :1134 末位「食」）；
/// 页头（renderProfile）无该兜底，缺省空串。
String avatarInitial(Map<String, dynamic> p, {String fallback = ''}) {
  final t = p['avatarText'];
  if (t is String && t.isNotEmpty) return t;
  final n = (p['nickname'] is String) ? p['nickname'] as String : '';
  if (n.isNotEmpty) return n.substring(0, 1); // JS slice(0,1) 同为 UTF-16 码元
  return fallback;
}

@visibleForTesting
const peNicknameFieldKey = Key('pe-nickname'); // index.html:449 id 同名

@visibleForTesting
const peSignatureFieldKey = Key('pe-signature'); // :453

@visibleForTesting
const peSaveKey = Key('pe-save'); // :455

/// 打开编辑弹层（≙ #profile-head 点击 → openProfileEdit，:1149）。
/// [pickAvatar] 仅为测试注入面，生产缺省走相册选择器。
Future<void> openProfileEditSheet(
  BuildContext context,
  WidgetRef ref, {
  AvatarPicker pickAvatar = galleryAvatarPicker,
}) async {
  // H5 :1138 `const p = state.profileData; if (!p) return;`——只读已加载值，
  // 不等待在途请求（加载/失败态点头部由页侧「点击重试」承担，见 profile_screen）。
  final p = ref.read(profileProvider).value;
  if (p == null) return;
  await showShiguangSheet<void>(
    context,
    title: '编辑资料', // index.html:440 逐字（M9-T8 起由 helper 标题行承载）
    child: _ProfileEditSheet(initial: p, pickAvatar: pickAvatar),
  );
}

class _ProfileEditSheet extends ConsumerStatefulWidget {
  const _ProfileEditSheet({required this.initial, required this.pickAvatar});

  final Map<String, dynamic> initial;
  final AvatarPicker pickAvatar;

  @override
  ConsumerState<_ProfileEditSheet> createState() => _ProfileEditSheetState();
}

class _ProfileEditSheetState extends ConsumerState<_ProfileEditSheet> {
  late final TextEditingController _nickCtl = TextEditingController(
      text: (widget.initial['nickname'] as String?) ?? ''); // :1139 ||''
  late final TextEditingController _sigCtl = TextEditingController(
      text: (widget.initial['signature'] as String?) ?? ''); // :1140 ||''

  bool _saving = false; // 重入门禁（仿体重卡 _saving；单拍行为与 H5 一致）
  bool _picking = false; // 同上：选图/上传在途禁用「更换头像」

  @override
  void dispose() {
    _nickCtl.dispose();
    _sigCtl.dispose();
    super.dispose();
  }

  /// e.message||'网络异常' 的 Dart 等价（:1153-1166/:1105-1119 catch 共用）：
  /// ApiException.message 空串按 falsy 落兜底；非 ApiException（本地抛错）同兜底。
  static String _reason(Object e) {
    final m = e is ApiException ? e.message : null;
    return (m == null || m.isEmpty) ? '网络异常' : m;
  }

  void _toast(ScaffoldMessengerState m, String msg) {
    m
      ..hideCurrentSnackBar()
      ..showSnackBar(
          SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating));
  }

  /// 更换头像（≙ #pe-change-avatar → #avatar-input.change → handleAvatarPick）
  Future<void> _pickAvatar(ScaffoldMessengerState messenger) async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final r = await widget.pickAvatar();
      if (r.failure == null && r.dataUrl == null) return; // :1106 取消静默
      if (r.failure == ImagePickFailure.tooLargeEncoded) {
        _toast(messenger, '图片仍过大，请换一张'); // :1111 逐字
        return;
      }
      if (r.failure == ImagePickFailure.readFailed) {
        _toast(messenger, '图片处理失败'); // T3 映射（文件头登记）
        return;
      }
      try {
        await ref.read(healthApiProvider).updateAvatar(r.dataUrl!);
        _toast(messenger, '头像已更新'); // :1113 逐字
        ref.invalidate(profileProvider); // :1114-1115 重取，预览/页头同步刷新
      } catch (e) {
        _toast(messenger, '头像上传失败：${_reason(e)}'); // :1117 逐字
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  /// 保存（≙ #pe-save click，:1153-1166）
  Future<void> _save(ScaffoldMessengerState messenger) async {
    if (_saving) return;
    final nickname = _nickCtl.text.trim(); // :1154
    final signature = _sigCtl.text.trim(); // :1155
    if (nickname.isEmpty) {
      _toast(messenger, '昵称不能为空'); // :1156 逐字
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(healthApiProvider)
          .updateProfile(<String, dynamic>{
            'nickname': nickname,
            'signature': signature,
          }); // :1158 只发这两键
      ref.invalidate(profileProvider); // :1159-1161 重取 + renderProfile
      if (mounted) Navigator.of(context).pop(); // :1162 closeProfileEdit
      _toast(messenger, '资料已保存'); // :1163 逐字（pop 后用捕获的 messenger）
    } catch (e) {
      _toast(messenger, '保存失败：${_reason(e)}'); // :1165 逐字
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    // 头像预览随重取刷新（≙ renderProfile 尾部 updatePeAvatar :1029）；
    // 重取在途短暂回落开层快照，无闪烁面（invalidate 后 value 为 null 时）。
    final p = ref.watch(profileProvider).value ?? widget.initial;
    final avatarData = avatarDataOf(p);
    final initial = avatarInitial(p, fallback: '食'); // :1134 弹层链带「食」
    // M9-T8：标题「编辑资料」+ ✕（index.html:440-441）与内层 SafeArea 由
    // showShiguangSheet 承载，本地副本删除；顶部 sp3 归零（其下原有
    // SizedBox(sp3) 承接标题→头像行净距）；viewInsets 包裹保留（键盘避让）。
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Tokens.sp5, 0, Tokens.sp5, Tokens.sp4),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: Tokens.sp3),
              // 头像预览行（:443-446 pe-avatar-row）
              Row(
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: const BoxDecoration(
                      shape: BoxShape.circle,
                      color: Tokens.primarySoft,
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: avatarData != null
                        ? FoodThumb(source: avatarData, size: 64)
                        : Center(
                            child: Text(initial,
                                style: const TextStyle(
                                    fontSize: Tokens.textXl,
                                    fontWeight: FontWeight.w700,
                                    color: Tokens.primaryDeep)),
                          ),
                  ),
                  const SizedBox(width: Tokens.sp4),
                  // Expanded：主题 filledButtonTheme.minimumSize=Size.fromHeight(52)
                  // （宽=∞）在 Row 非 flex 子节点下会抛 "infinite width"（目检抓得），
                  // 通栏按钮亦合 H5 pe-avatar-row 视觉（头像+更换按钮）。
                  Expanded(
                    child: FilledButton.tonal( // :445 btn-soft
                      onPressed: _picking ? null : () => _pickAvatar(messenger),
                      child: _picking
                          ? const Row(mainAxisSize: MainAxisSize.min, children: [
                              LoadingSpinner(
                                  size: 14, color: Tokens.primaryDeep),
                              SizedBox(width: Tokens.sp2),
                              Text('更换头像'),
                            ])
                          : const Text('更换头像'), // 逐字
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Tokens.sp4),
              const Text('昵称', style: _label), // :448 逐字
              TextField(
                controller: _nickCtl,
                key: peNicknameFieldKey,
                maxLength: 28, // :449
                decoration: const InputDecoration(
                  hintText: '昵称', // :449 placeholder 逐字
                  isDense: true,
                  counterText: '', // 版式：不占行高（R4）
                ),
              ),
              const SizedBox(height: Tokens.sp3),
              const Text('签名', style: _label), // :452 逐字
              TextField(
                controller: _sigCtl,
                key: peSignatureFieldKey,
                maxLength: 40, // :453
                decoration: const InputDecoration(
                  hintText: '个性签名', // :453 placeholder 逐字
                  isDense: true,
                  counterText: '',
                ),
              ),
              const SizedBox(height: Tokens.sp4),
              FilledButton( // :455 btn-primary
                key: peSaveKey,
                onPressed: _saving ? null : () => _save(messenger),
                style: FilledButton.styleFrom(
                  disabledBackgroundColor:
                      Tokens.primaryDeep.withValues(alpha: .72),
                  disabledForegroundColor: Colors.white,
                ),
                child: _saving
                    ? const Row(mainAxisSize: MainAxisSize.min, children: [
                        LoadingSpinner(),
                        SizedBox(width: Tokens.sp2),
                        Text('保存中…'),
                      ])
                    : const Text('保存'), // 逐字
              ),
            ],
          ),
        ),
    );
  }

  static const _label = TextStyle(fontSize: Tokens.textSm, color: Tokens.ink2);
}
