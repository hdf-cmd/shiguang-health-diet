// ShiguangFlutter/lib/features/profile/profile_screen.dart
// M4 Task 4/7：「我的」页体——体重卡（当前值/手动 ±0.5/秤同步秒存）
// + 消息提醒卡（T7：总开关/测试餐点/测试喝水）+ 退出登录。
// M5 Task 5：标题下插资料卡头部（_profileHead：头像/昵称/签名，点击开编辑
// 弹层；T6 接线次序 = 资料头→体重卡→身体卡(T6)→提醒卡→退出）。
// M6 Task 6 方案 A：提醒卡压缩——卡面一行化（标题+副文案+设置入口+开关，
// 向 H5 remind-card 一行观感靠拢），M4 自加的两枚通栏测试钮收进「提醒设置」
// 弹层「诊断」区；handler 直连零行为变更，层内 toast 走 OverlayEntry 通道。
// M8-①（老大 09-27 真机反馈）：体重记录卡整卡迁出至「报告」页体重趋势下方
// （weight_log_card.dart，行为零变更随卡走）；本页次序变
// 资料头→身体卡→提醒卡→食物库→退出。js/app.js:910-956 记体重/秤同步的
// 行为对照注释一并迁至新文件头。
// - js/app.js:1168 退出登录：HealthAPI.logout()（= _clearToken，js/api.js:312）
//   + location.reload() 回登录页；Flutter 侧 signOut() 清 token + 置 anon，
//   AuthGate（main.dart）切 LoginScreen，无需 reload。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/auth_state.dart';
import '../../app/theme.dart';
import '../band_sync/band_sync_sheet.dart' show openBandSyncSheet;
import '../common/food_thumb.dart';
import '../common/sheet.dart' show showShiguangSheet;
import '../common/skeleton.dart' show SkeletonBar;
import '../common/sheet_toast.dart' show SheetToast;
import '../notifications/reminder_scheduler.dart';
import 'ai_provider_sheet.dart' show openAiProviderSheet;
import 'body_profile_card.dart' show BodyProfileCard;
import 'food_lib_sheet.dart' show openFoodLibSheet;
import 'profile_edit_sheet.dart'
    show avatarDataOf, avatarInitial, openProfileEditSheet;
import 'profile_providers.dart' show profileProvider;

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  // ---- T7 消息提醒卡 ----
  /// 开关状态；null = enabled() 在途（初值经异步读偏好，build 里不 await）。
  bool? _remindOn;

  /// 重入门禁（T8 缓办 C）：setEnabled 在途时忽略再次拨动，
  /// 防快速连拨两次出现「乐观置位→失败回弹」交织出与云端不符的终态。
  bool _reminderBusy = false;

  /// 「提醒设置」弹层在途的层内通知通道（M6-T6）：弹层 initState 置入、
  /// dispose 清空；非空时 [_toast] 走该通道（OverlayEntry，goal_sheet T4
  /// 07b 结论：SnackBar 会被弹层遮挡且向下层 Scaffold 广播出双份），
  /// 各 handler 不感知——行为零变更，仅呈现层随宿主位置换通道。
  void Function(String)? _reminderSheetToast;

  @override
  void initState() {
    super.initState();
    // H5 renderRemindSwitch（app.js:1036-1042）等价：进页读一次开关初值。
    // 读取失败静默按「关」渲染——对齐 Notify.kt:92-93 getBoolean(KEY_ON,false)
    // 的默认关语义，且 H5 初值渲染本就无 toast 分支。
    ref.read(reminderSchedulerProvider).enabled().then((v) {
      if (mounted) setState(() => _remindOn = v);
    }).catchError((Object _) {
      if (mounted) setState(() => _remindOn = false);
    });
  }

  /// 开关切换（app.js:1043-1049：先翻 UI 再落盘）。setEnabled 内部已联动
  /// sync 排程/撤销（T6 reminder_scheduler.dart:179-183），UI 不再补 sync；
  /// 失败回弹到切换前的值并 toast。
  Future<void> _setReminders(bool on) async {
    if (_reminderBusy) return; // 在途连拨：忽略（T8 缓办 C）
    final prev = _remindOn;
    setState(() {
      _remindOn = on; // renderRemindSwitch 的立即翻转
      _reminderBusy = true;
    });
    try {
      await ref.read(reminderSchedulerProvider).setEnabled(on);
      _toast(on ? '提醒已开启：每天定点弹系统通知' : '提醒已关闭'); // app.js:1048 逐字
    } catch (_) {
      if (mounted) setState(() => _remindOn = prev);
      _toast('提醒开关设置失败'); // H5 桥为 fire-and-forget 无失败分支，文案自拟（报告登记）
    } finally {
      if (mounted) setState(() => _reminderBusy = false);
    }
  }

  /// 测试餐点提醒（app.js:1050-1053：testNotify → toast）。
  Future<void> _testMealReminder() async {
    try {
      await ref.read(reminderSchedulerProvider).testMeal();
      _toast('测试通知已发，看通知栏'); // app.js:1051 逐字
    } catch (_) {
      _toast('测试通知发送失败'); // 自拟，同上
    }
  }

  /// 测试喝水提醒（app.js:1054-1059）。H5 toast「已发出：看状态栏胶囊 / 通知
  /// 栏」中的灵动岛胶囊为 Android 原生壳专属，Flutter M4 无该形态，去半句留
  /// 「看通知栏」；H5 的「开关未开则拒绝」分支对应 Kotlin 常驻卡缺失，
  /// T6 testWater 与开关无关（直接 show 真实文案），故不搬该门禁。
  Future<void> _testWaterReminder() async {
    try {
      await ref.read(reminderSchedulerProvider).testWater();
      _toast('已发出：看通知栏'); // app.js:1058 裁剪版（见上）
    } catch (_) {
      _toast('喝水提醒发送失败'); // 自拟，同上
    }
  }

  /// 「提醒设置」弹层（M6-T6 方案 A）：卡面两枚诊断钮收进层内「诊断」区，
  /// 按钮直连原 [_testMealReminder]/[_testWaterReminder]，行为零变更。
  /// M9-T8：开层样板收口 showShiguangSheet（原定式与弹层族同构；本层原
  /// 未传 isScrollControlled，收口后统一 78% 最大高+可滚容器语义）。
  Future<void> _openReminderSettings() {
    return showShiguangSheet<void>(
      context,
      title: '提醒设置', // 原标题行逐字（现由 helper 承载）
      child: _ReminderSettingsSheet(
        onTestMeal: _testMealReminder,
        onTestWater: _testWaterReminder,
        bindToastSink: (sink, mySink) {
          // F5（M6-T7 评审）注销守卫：sink==null 表示注销，仅当当前通道仍
          // 是注销方自己的 sink 才复位——防旧层迟到的 dispose 误清新层注册
          if (sink == null) {
            if (_reminderSheetToast == mySink) _reminderSheetToast = null;
          } else {
            _reminderSheetToast = sink;
          }
        },
      ),
    );
  }

  @override
  void dispose() {
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    // M6-T6：「提醒设置」弹层开着的提示走层内 OverlayEntry（见
    // [_reminderSheetToast] 注释）；弹层外（开关直拨）仍页级 SnackBar。
    final inSheet = _reminderSheetToast;
    if (inSheet != null) {
      inSheet(msg);
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    // 自带 Scaffold：SnackBar（H5 toast 位）在本页内呈现，不依赖 Shell
    // （对齐 record_screen.dart:97 的惯例）。
    return Scaffold(
      backgroundColor: Tokens.bg,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(Tokens.sp4),
          children: [
            const Text('我的',
                style: TextStyle(
                    fontSize: Tokens.textXl,
                    fontWeight: FontWeight.w800,
                    color: Tokens.ink)),
            const SizedBox(height: Tokens.sp3),
            _profileHead(), // M5-T5：资料卡
            const SizedBox(height: Tokens.sp3),
            const BodyProfileCard(), // M5-T6：身体参数卡
            const SizedBox(height: Tokens.sp3),
            // M8-①：体重记录卡迁往报告页体重趋势下方（weight_log_card.dart）
            _remindCard(),
            const SizedBox(height: Tokens.sp3),
            // 食物库管理入口（M7-T4；≙ index.html:249 #btn-foodlib「食物库」
            // btn-soft 钮，文案逐字；位置=提醒卡后、退出登录前——R4 定，
            // H5 本钮在记录页，spec §4.2 裁定落「我的」页）。
            FilledButton.tonal(
              onPressed: () => openFoodLibSheet(context, ref),
              child: const Text('食物库'),
            ),
            const SizedBox(height: Tokens.sp3),
            // M14-T5：AI 识菜设置入口（用户自带厂商 Key；spec §3.2
            // 「我的 → AI 识菜设置」）。开层即生产函数，存储由组合根注入。
            FilledButton.tonal(
              key: const Key('ai-settings'),
              onPressed: () => openAiProviderSheet(context, ref),
              child: const Text('AI 识菜设置'),
            ),
            const SizedBox(height: Tokens.sp3),
            // M17：手环数据同步入口（小米云通道，官方 App 连接不受影响）。
            FilledButton.tonal(
              key: const Key('band-import-open'),
              onPressed: () => openBandSyncSheet(context, ref),
              child: const Text('手环数据同步'),
            ),
            const SizedBox(height: Tokens.sp3),
            // 退出登录（index.html:456「退出登录」，danger 色）
            TextButton(
              onPressed: () =>
                  ref.read(authStateProvider.notifier).signOut(),
              child: const Text('退出登录',
                  style: TextStyle(
                      color: Tokens.danger, fontSize: Tokens.textMd)),
            ),
          ],
        ),
      ),
    );
  }

  /// 资料卡头部（M5-T5；≙ index.html:179-186 #profile-head +
  /// js/app.js renderProfile :1004-1020 渲染规则，文案逐字面）：
  /// - data：昵称(:1005)/签名(:1006)；avatarData 非空画圆头像(:1009-1014)，
  ///   否则画 avatarText||nickname 首字(:1015-1019，页头无「食」兜底)；
  ///   点击 → openProfileEditSheet（≙ :1149 #profile-head click）。
  /// - loading：占位「…」（简报 Step 3）；error：「未登录信息」点击重试
  ///   （ref.invalidate）。版式（卡壳/排布）R4 自主：与体重卡同壳。
  Widget _profileHead() {
    final profile = ref.watch(profileProvider);
    final p = profile.value;

    final Widget body;
    if (p == null) {
      // 加载中/失败共用占位骨架：头像位 + 文案位
      final Widget tip = profile is AsyncError
          ? const Text('未登录信息', // 简报 Step 3 指定占位
              style: TextStyle(fontSize: Tokens.textMd, color: Tokens.ink3))
          : const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                SkeletonBar(width: 88, height: 14),
                SizedBox(height: 6),
                SkeletonBar(width: 156, height: 11),
              ],
            );
      body = Row(
        children: [
          const _HeadAvatar(child: SizedBox.shrink()),
          const SizedBox(width: Tokens.sp3),
          Expanded(child: tip),
        ],
      );
    } else {
      final avatarData = avatarDataOf(p);
      body = Row(
        children: [
          _HeadAvatar(
            child: avatarData != null
                ? FoodThumb(source: avatarData, size: 56)
                : Text(avatarInitial(p), // :1018 avatarText||nickname 首字
                    style: const TextStyle(
                        fontSize: Tokens.textXl,
                        fontWeight: FontWeight.w700,
                        color: Tokens.primaryDeep)),
          ),
          const SizedBox(width: Tokens.sp3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text((p['nickname'] as String?) ?? '', // :1005
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: Tokens.textLg,
                        fontWeight: FontWeight.w700,
                        color: Tokens.ink)),
                if (((p['signature'] as String?) ?? '').isNotEmpty)
                  Text(p['signature'] as String, // :1006
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: Tokens.textSm, color: Tokens.ink3)),
              ],
            ),
          ),
          const SizedBox(width: Tokens.sp2),
          const Text('编辑 ›', // index.html:185 ph-edit 逐字
              style: TextStyle(fontSize: Tokens.textSm, color: Tokens.ink3)),
        ],
      );
    }

    return Semantics(
      label: '编辑资料', // index.html:179 aria-label 逐字
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (p == null) {
            // 失败占位可点重试（简报 Step 3）；在途 loading 点击无害（幂等重取）
            ref.invalidate(profileProvider);
            return;
          }
          openProfileEditSheet(context, ref); // ≙ app.js:1149 → :1137
        },
        child: Container(
          padding: const EdgeInsets.all(Tokens.sp4),
          decoration: BoxDecoration(
            color: Tokens.surface,
            borderRadius: BorderRadius.circular(Tokens.radiusLg),
            boxShadow: Tokens.shadowCard,
          ),
          child: body,
        ),
      ),
    );
  }

  /// 消息提醒卡（M6-T6 方案 A：index.html:227-233 remind-row 一行同构——标题
  /// +副文案，右侧「设置」入口与开关；H5 本就没有测试钮，卡面两枚通栏钮是
  /// Flutter M4 自加的诊断便利，压缩回一行=向 H5 观感靠拢，钮迁进弹层）。
  /// 文案逐字不动；开关 aria-label「消息提醒」→ Semantics。初值在途时开关
  /// 禁用，防「未知态」下误翻。
  Widget _remindCard() {
    return Container(
      padding: const EdgeInsets.all(Tokens.sp4),
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
        boxShadow: Tokens.shadowCard,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('消息提醒 · 系统通知', // index.html:230 逐字
                    style: TextStyle(
                        fontSize: Tokens.textMd,
                        fontWeight: FontWeight.w700,
                        color: Tokens.ink)),
                const SizedBox(height: Tokens.sp1),
                const Text(
                    '三餐定点 8:00/12:00/18:30 + 喝水每天 8 次随机（8:00–24:00），横幅弹出',
                    // index.html:231 逐字
                    style:
                        TextStyle(fontSize: Tokens.textXs, color: Tokens.ink3)),
              ],
            ),
          ),
          const SizedBox(width: Tokens.sp2),
          Semantics(
            label: '提醒设置', // 弹层入口（简报 Step 1 ②）
            button: true,
            // container: true —— IconButton 内部自带语义节点，非容器 Semantics
            // 的属性会并到子节点上导致 bySemanticsLabel 找不到独立 label（①实证）。
            container: true,
            child: IconButton(
              onPressed: _openReminderSettings,
              icon: const Icon(Icons.settings_outlined, color: Tokens.ink3),
              // 卡高压缩：默认触摸目标 48 会把一行卡顶回两行高
              visualDensity: VisualDensity.compact,
            ),
          ),
          Semantics(
            label: '消息提醒', // index.html:233 aria-label 逐字
            child: Switch(
              value: _remindOn ?? false,
              // 初值在途禁用；setEnabled 在途亦禁用（T8 缓办 C）
              onChanged: (_remindOn == null || _reminderBusy)
                  ? null
                  : _setReminders,
            ),
          ),
        ],
      ),
    );
  }
}

/// 页头头像位（56 圆壳，≙ index.html:180 .avatar）。[child] 为空时是
/// 加载/失败占位壳；FoodThumb 自带圆角矩形裁剪，外层圆壳 antiAlias 收成圆形
/// （T4 备忘：圆形需外层裁剪，尺寸传大）。
class _HeadAvatar extends StatelessWidget {
  const _HeadAvatar({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Container(
        width: 56,
        height: 56,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Tokens.primarySoft,
        ),
        clipBehavior: Clip.antiAlias,
        child: Center(child: child),
      );
}

/// 「提醒设置」弹层的 toast 通道 binder（M6-T7 评审 F5）：
/// - `sink != null`：注册——页体提示改道层内 OverlayEntry；
/// - `sink == null`：注销请求，此时 [mySink] 为注销方自证身份，宿主仅当
///   当前通道恰等于 mySink 才复位——防旧弹层迟到的 dispose 误清新弹层
///   刚注册的通道（快速重开弹层时序）。
typedef _SheetToastBinder = void Function(
  void Function(String)? sink,
  void Function(String)? mySink,
);

/// 「提醒设置」弹层（M6-T6 方案 A）：说明 + 分隔线 + 「诊断」小标题 + 两枚
/// 通栏测试钮。钮直连页体原 handler（testMeal/testWater 链与 toast 文案零
/// 变更）；两钮文本逐字 index.html:235-236（H5 无此钮，M4 自加诊断便利的
/// 迁移位）。层内提示走 OverlayEntry（goal_sheet T4 07b 定式：SnackBar 会被
/// 弹层遮挡并向下层 Scaffold 广播出双份）；通道经 [bindToastSink] 在开层时
/// 注册进页体 _toast、关层时注销，页级提示随之回 SnackBar。
/// 版式 R4 自主：标题行「提醒设置」+ ✕ 沿用弹层族定式（profile_edit:440-441、
/// goal_sheet :296-299 同构）。
class _ReminderSettingsSheet extends StatefulWidget {
  const _ReminderSettingsSheet({
    required this.onTestMeal,
    required this.onTestWater,
    required this.bindToastSink,
  });

  final Future<void> Function() onTestMeal;
  final Future<void> Function() onTestWater;

  /// 通道注册/注销 binder（见 [_SheetToastBinder]，F5 注销守卫）。
  final _SheetToastBinder bindToastSink;

  @override
  State<_ReminderSettingsSheet> createState() => _ReminderSettingsSheetState();
}

class _ReminderSettingsSheetState extends State<_ReminderSettingsSheet> {
  OverlayEntry? _toastEntry;

  @override
  void initState() {
    super.initState();
    widget.bindToastSink(_toastInSheet, _toastInSheet); // 页体 _toast 改道层内
  }

  @override
  void dispose() {
    // 注销走 F5 守卫：仅当通道仍是自己的 _toastInSheet 才复位 SnackBar
    widget.bindToastSink(null, _toastInSheet); // （⑥用例钉）
    _toastEntry?.remove(); // 层内 toast 随层销毁
    super.dispose();
  }

  void _toastInSheet(String msg) {
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

  @override
  Widget build(BuildContext context) {
    // M9-T8：标题行「提醒设置」+ ✕ 与 SafeArea 由 showShiguangSheet 承载，
    // 本地副本删除；原顶部 sp3 内边距归零（层内标题后既有 sp3 间距保留，
    // 标题→说明的净距离不变），其余业务内容一字未改。
    return Padding(
      padding:
          const EdgeInsets.fromLTRB(Tokens.sp5, 0, Tokens.sp5, Tokens.sp4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: Tokens.sp3),
            // 说明（与开关开启 toast「提醒已开启：每天定点弹系统通知」同族措辞，
            // 简报 Step 2 指定文本）
            const Text('开启后每天定点弹系统通知',
                style: TextStyle(fontSize: Tokens.textSm, color: Tokens.ink2)),
            const SizedBox(height: Tokens.sp3),
            const Divider(height: 1, color: Tokens.line),
            const SizedBox(height: Tokens.sp3),
            const Text('诊断',
                style: TextStyle(fontSize: Tokens.textSm, color: Tokens.ink3)),
            const SizedBox(height: Tokens.sp2),
            FilledButton.tonal( // index.html:235 逐字（M6-T6 自卡面迁入）
              onPressed: widget.onTestMeal,
              child: const Text('发一条测试通知'),
            ),
            const SizedBox(height: Tokens.sp3),
            FilledButton.tonal( // index.html:236 逐字（M6-T6 自卡面迁入）
              onPressed: widget.onTestWater,
              child: const Text('发一条喝水到点提醒（测试）'),
            ),
        ],
      ),
    );
  }
}
