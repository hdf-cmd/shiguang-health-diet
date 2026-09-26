// ShiguangFlutter/lib/features/profile/profile_screen.dart
// M4 Task 4/7：「我的」页体——体重卡（当前值/手动 ±0.5/秤同步秒存）
// + 消息提醒卡（T7：总开关/测试餐点/测试喝水）+ 退出登录。
// M5 Task 5：标题下插资料卡头部（_profileHead：头像/昵称/签名，点击开编辑
// 弹层；T6 接线次序 = 资料头→体重卡→身体卡(T6)→提醒卡→退出）。
// M6 Task 6 方案 A：提醒卡压缩——卡面一行化（标题+副文案+设置入口+开关，
// 向 H5 remind-card 一行观感靠拢），M4 自加的两枚通栏测试钮收进「提醒设置」
// 弹层「诊断」区；handler 直连零行为变更，层内 toast 走 OverlayEntry 通道。
// 行为权威源 H5：
// - index.html:459-482 记体重区：label「今日体重」、stepper −/＋（aria ±0.5kg）、
//   保存、hint「点数字可直接输入…」、秤按钮「⚖️ 从体脂秤同步（光脚站上秤）」——文案逐字。
// - js/app.js:910 弹层初始值 = 当前体重 || 55；:927-929 bumpBodyVal ±0.5、
//   边界 20–300、两位小数。
// - js/app.js:930-949 saveWeightKg：校验 20–300（不过 → toast「请输入有效体重」）
//   → logWeight(w, todayIso()) → toast「已记录 r.weightKg kg · 趋势已更新」。
// - js/app.js:953-956 SG_onScaleWeight(kg, stable)：读数写进输入位，仅 stable
//   调 saveWeightKg —— 本页 ref.listen(scaleReadingsProvider) 同构：非 stable
//   只预览，stable 才落库（locked 秒存）。
// - js/app.js:1168 退出登录：HealthAPI.logout()（= _clearToken，js/api.js:312）
//   + location.reload() 回登录页；Flutter 侧 signOut() 清 token + 置 anon，
//   AuthGate（main.dart）切 LoginScreen，无需 reload。
// - 秤终态文案：ScaleSync.kt :71/:83/:85/:130、MainActivity.kt:52 逐字；
//   'ok' 静默（Kotlin finish :241 只转发非 ok，保存成功 toast 已覆盖）、
//   'cancelled' 静默（T3 账本 M5），未知状态 default 兜底静默。
// 布局差异说明：H5 是首页趋势卡入口的底部弹层；「我的」tab 落地后体重操作
// 收敛为本页内联卡片（简报 Files 指定 ProfileScreen 页体承载），弹层开/关
// 语义随之消失，cancel 时机 = 页内「取消」按钮 / 页面 dispose。

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/auth_state.dart';
import '../../app/theme.dart';
import '../../data/api_client.dart' show ApiException;
import '../../domain/dates.dart' show todayIso;
import '../common/food_thumb.dart';
import '../home/home_controller.dart' show healthApiProvider;
import '../notifications/reminder_scheduler.dart';
import '../scale/scale_service.dart';
import 'body_profile_card.dart' show BodyProfileCard;
import 'profile_edit_sheet.dart'
    show avatarDataOf, avatarInitial, openProfileEditSheet;
import 'profile_providers.dart' show profileProvider;

/// 当前体重（body-metrics.weightKg；键名对齐 contract/fixtures/diet-core.json
/// 与 domain/models.dart BodyMetrics.fromMap 的 weightKg）。
/// 保存成功后由本页 invalidate 重取（H5 saveWeightKg 里 renderBodyCard 的等价物）。
final profileWeightProvider = FutureProvider<double?>((ref) async {
  final m = await ref.watch(healthApiProvider).getBodyMetrics();
  final w = m['weightKg'];
  return w is num ? w.toDouble() : null;
});

/// 数字串形：对齐 JS Number.toString（66.66→"66.66"，60.5→"60.5"，70.0→"70"）。
/// H5 toast/输入位显示的都是该串形，Dart double.toString 对整数值多 ".0"，在此抹平。
String _jsNum(num v) {
  if (v is double && v == v.truncateToDouble() && v.abs() < 1e15) {
    return v.toInt().toString();
  }
  return v.toString();
}

/// 秤终态 status → 用户可见文案（逐字抄 HealthyDiet/.../ScaleSync.kt 与
/// MainActivity.kt 的 OnStatus 现文案；映射表覆盖全部 7 态 + default 兜底，
/// T3 账本 M5 要求 cancelled 必须显式静默）。
String? scaleStatusText(String status) => switch (status) {
      // kt:85 scanDeadline「30 秒没找到秤」
      'scan-timeout' => '30 秒没找到秤：请光脚站上秤再点一次',
      // kt:83 readDeadline「读取超时」
      'read-timeout' => '读取超时：请站上秤后重新点同步',
      // kt:71 蓝牙未开（kt:68/:74 机型不支持同归此支，transport 已合并 no-bluetooth）
      'no-bluetooth' => '请先打开手机蓝牙',
      // kt:130 GATT STATE_DISCONNECTED
      'connect-fail' => '与秤的连接断开，请重试',
      // MainActivity.kt:52 权限被拒
      'permission-denied' => '需要蓝牙权限才能读取体脂秤，请在设置中允许后重试',
      // 'ok'：Kotlin finish("ok") 不转发状态文案（:241），保存成功由
      // 「已记录 X kg · 趋势已更新」toast 表达；'cancelled'：用户主动取消，
      // 静默。其余未知态兜底静默，不把英文 status 裸露给用户。
      _ => null,
    };

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  /// 今日体重输入位（手动 ±0.5 与秤 live 预览共写此处，对齐 H5 #weight-log-val）
  final _kgCtl = TextEditingController(text: '55.00');

  bool _seeded = false; // 首次取到当前体重时播种输入位（app.js:910 语义）
  bool _saving = false;
  bool _syncing = false;
  String? _syncStatus; // 进行中=寻找文案；终态错误=映射文案；ok/cancelled=null
  ScaleService? _scaleService; // dispose 时 cancel 用（不在 dispose 里读 ref）

  static const _kScanning = '正在寻找体脂秤…（请光脚站上秤）'; // ScaleSync.kt:98

  // ---- T7 消息提醒卡 ----
  /// 开关状态；null = enabled() 在途（初值经异步读偏好，build 里不 await）。
  bool? _remindOn;

  /// 重入门禁（T8 缓办 C，仿 [_saving]）：setEnabled 在途时忽略再次拨动，
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
  /// 样式沿用弹层族（profile_edit_sheet/goal_sheet 的 showModalBottomSheet 定式）。
  Future<void> _openReminderSettings() {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Tokens.surface,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(Tokens.radiusSheet)),
      ),
      builder: (_) => _ReminderSettingsSheet(
        onTestMeal: _testMealReminder,
        onTestWater: _testWaterReminder,
        bindToastSink: (sink) => _reminderSheetToast = sink,
      ),
    );
  }

  @override
  void dispose() {
    // 离开「我的」tab 即终止进行中的会话（简报：cancel 时机=按钮/页面 dispose；
    // Shell 的 PageView 常驻四页，真离开整壳时才走到这里）
    if (_syncing) _scaleService?.cancel();
    _kgCtl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
    // M6-T6：「提醒设置」弹层开着的提示走层内 OverlayEntry（见
    // [_reminderSheetToast] 注释）；弹层外（开关直拨/体重/同步）仍页级 SnackBar。
    final inSheet = _reminderSheetToast;
    if (inSheet != null) {
      inSheet(msg);
      return;
    }
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  double? get _parsedKg => double.tryParse(_kgCtl.text.trim());

  /// ±0.5 步进（js/app.js:927-928 bumpBodyVal(step=±0.5, min=20, max=300, dp=2)）。
  /// 以"分"为整数运算，避免浮点累加漂出两位小数。
  /// T8 缓办 D：钳制后与原值相等 → toast「已到上限/已到下限」
  /// （js/app.js:1633 `if (next === cur)` 逐支对照）。
  void _bump(double deltaKg) {
    final base = ((_parsedKg ?? _seedKgFallback()) * 100).round();
    var next = base + (deltaKg * 100).round();
    if (next < 2000) next = 2000; // 下界 20kg（bumpBodyVal min 钳制）
    if (next > 30000) next = 30000; // 上界 300kg
    _kgCtl.text = (next / 100).toStringAsFixed(2);
    if (next == base) _toast(deltaKg > 0 ? '已到上限' : '已到下限'); // app.js:1633 逐字
  }

  double _seedKgFallback() {
    final w = ref.read(profileWeightProvider).value;
    return w ?? 55; // H5 兜底：state.body.weightKg || 55
  }

  /// 保存（js/app.js:930-949 saveWeightKg 逐支对照：校验 → logWeight → toast）。
  Future<void> _saveWeight(num w) async {
    if (_saving) return;
    // H5 `if (!w || w < 20 || w > 300)`：0/空/NaN/越界全拒（!w 覆盖 0 与 NaN）
    if (w.isNaN || w < 20 || w > 300) {
      _toast('请输入有效体重');
      return;
    }
    setState(() => _saving = true);
    try {
      final r =
          await ref.read(healthApiProvider).logWeight(w, todayIso());
      if (!mounted) return;
      final rw = r['weightKg'];
      final shown = rw is num ? _jsNum(rw) : _jsNum(w);
      _toast('已记录 $shown kg · 趋势已更新'); // app.js:944 逐字
      ref.invalidate(profileWeightProvider); // 卡上当前体重跟着更新（renderBodyCard 等价）
      ref.invalidate(profileProvider); // M5-T6 计划 Step 2：身体卡/资料卡体重同步
    } on ApiException catch (e) {
      _toast('保存失败：${e.message}'); // app.js:946
    } catch (_) {
      _toast('保存失败：网络异常'); // app.js:946 '网络异常' 兜底
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  /// 秤同步：进行中按钮禁用 + 状态行；读数经 scaleReadingsProvider 预览，
  /// stable 才存（在 build 的 ref.listen 里）。
  Future<void> _startSync() async {
    final svc = ref.read(scaleServiceProvider);
    _scaleService = svc;
    setState(() {
      _syncing = true;
      _syncStatus = _kScanning; // kt:98 发起即"正在寻找"
    });
    final outcome = await svc.start();
    if (!mounted) return;
    final err = scaleStatusText(outcome.status);
    setState(() {
      _syncing = false;
      _syncStatus = err; // ok/cancelled → null：状态行清空（静默）
    });
  }

  void _cancelSync() {
    _scaleService?.cancel(); // 终态经 start() 的 await 回来，cancelled 静默
  }

  @override
  Widget build(BuildContext context) {
    final weight = ref.watch(profileWeightProvider);

    // 首次取到当前体重 → 播种输入位（H5 openWeightLogSheet :910）。
    // 只播一次，之后的手动编辑/秤预览不被后台刷新覆盖。
    if (!_seeded) {
      final w = weight.value;
      if (w != null) {
        _seeded = true;
        _kgCtl.text = w.toStringAsFixed(2); // 两位小数（简报）
      }
    }

    // 秤读数 → 输入位预览；仅 stable（locked）自动落库——对齐 H5
    // SG_onScaleWeight(kg, stable)：非 stable 只写 value，stable 才 saveWeightKg。
    ref.listen<AsyncValue<ScaleReading>>(scaleReadingsProvider, (_, next) {
      final r = next.value;
      if (r == null) return;
      _kgCtl.text = _jsNum(r.kg); // 串形与 H5 input.value = kg 一致
      if (r.stable) _saveWeight(r.kg);
    });

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
            // 体重卡次序（老大 09-26 反馈+R4）：档案在前、今日记录在后，
            // 语义链=我是谁→我什么身板→今天记一笔→系统设置。
            _weightCard(weight),
            const SizedBox(height: Tokens.sp3),
            _remindCard(),
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
      final tip = profile is AsyncError
          ? const Text('未登录信息', // 简报 Step 3 指定占位
              style: TextStyle(fontSize: Tokens.textMd, color: Tokens.ink3))
          : const Text('…', // 加载态占位
              style: TextStyle(fontSize: Tokens.textMd, color: Tokens.ink3));
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

  Widget _weightCard(AsyncValue<double?> weight) {
    return Container(
      padding: const EdgeInsets.all(Tokens.sp4),
      decoration: BoxDecoration(
        color: Tokens.surface,
        borderRadius: BorderRadius.circular(Tokens.radiusLg),
        boxShadow: Tokens.shadowCard,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 当前体重卡（对照 index.html:206 stat-card「体重」；值取
          // body-metrics.weightKg，JS 数字串形 + kg 单位）
          Row(
            children: [
              const Text('当前体重',
                  style: TextStyle(
                      fontSize: Tokens.textSm, color: Tokens.ink2)),
              const Spacer(),
              weight.when(
                loading: () => const Text('…',
                    style: TextStyle(
                        fontSize: Tokens.textLg, color: Tokens.ink3)),
                error: (_, _) => const Text('获取失败',
                    style: TextStyle(
                        fontSize: Tokens.textLg, color: Tokens.danger)),
                data: (w) => Text(
                    w == null // 云端无记录时回落 bodyDefault（constants.dart:52 55）
                        ? '55 kg'
                        : '${_jsNum(w)} kg',
                    style: const TextStyle(
                        fontSize: Tokens.textLg,
                        fontWeight: FontWeight.w700,
                        color: Tokens.ink)),
              ),
            ],
          ),
          const SizedBox(height: Tokens.sp3),
          const Divider(height: 1, color: Tokens.line),
          const SizedBox(height: Tokens.sp3),
          const Text('今日体重', // index.html:468 逐字
              style: TextStyle(fontSize: Tokens.textSm, color: Tokens.ink2)),
          const SizedBox(height: Tokens.sp2),
          Row(
            children: [
              _stepBtn('−', () => _bump(-0.5), '减少 0.5kg'), // index.html:470
              Expanded(
                child: TextField(
                  controller: _kgCtl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: Tokens.textLg,
                      fontWeight: FontWeight.w700,
                      color: Tokens.ink),
                  decoration: const InputDecoration(
                    isDense: true,
                    suffixText: 'kg',
                    border: InputBorder.none,
                  ),
                ),
              ),
              _stepBtn('＋', () => _bump(0.5), '增加 0.5kg'), // index.html:472
            ],
          ),
          const Text('点数字可直接输入（支持 0.1 精度）· 建议每天固定时间称',
              // index.html:480 逐字
              style: TextStyle(fontSize: Tokens.textXs, color: Tokens.ink3)),
          const SizedBox(height: Tokens.sp3),
          // 从体脂秤同步（index.html:474 文案逐字）；进行中禁用（简报 Step 2）
          FilledButton.tonal(
            onPressed: _syncing ? null : _startSync,
            child: const Text('⚖️ 从体脂秤同步（光脚站上秤）'),
          ),
          if (_syncing)
            TextButton(
              onPressed: _cancelSync,
              child: const Text('取消',
                  style: TextStyle(color: Tokens.ink3)),
            ),
          if (_syncStatus != null)
            Padding(
              padding: const EdgeInsets.only(top: Tokens.sp1),
              child: Text(_syncStatus!,
                  style: TextStyle(
                      fontSize: Tokens.textSm,
                      color: _syncing ? Tokens.ink2 : Tokens.warn)),
            ),
          const SizedBox(height: Tokens.sp2),
          FilledButton(
            onPressed: _saving ? null : () => _saveManual(),
            child: const Text('保存'), // index.html:481 逐字
          ),
        ],
      ),
    );
  }

  /// 手动保存入口：解析输入位（H5 Number(input.value)：空/非法 → 走无效体重）
  void _saveManual() {
    final w = _parsedKg;
    if (w == null) {
      _toast('请输入有效体重');
      return;
    }
    _saveWeight(w);
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

  Widget _stepBtn(String label, VoidCallback onTap, String hint) {
    return SizedBox(
      width: 44,
      height: 44,
      child: OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Tokens.line),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Tokens.radiusSm)),
        ),
        child: Text(label,
            style: const TextStyle(
                fontSize: Tokens.textLg,
                fontWeight: FontWeight.w700,
                color: Tokens.primaryDeep)),
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
  final void Function(void Function(String)? sink) bindToastSink;

  @override
  State<_ReminderSettingsSheet> createState() => _ReminderSettingsSheetState();
}

class _ReminderSettingsSheetState extends State<_ReminderSettingsSheet> {
  OverlayEntry? _toastEntry;

  @override
  void initState() {
    super.initState();
    widget.bindToastSink(_toastInSheet); // 页体 _toast 改道层内
  }

  @override
  void dispose() {
    widget.bindToastSink(null); // 注销：页级通道复位 SnackBar（⑥用例钉）
    _toastEntry?.remove(); // 层内 toast 随层销毁
    super.dispose();
  }

  void _toastInSheet(String msg) {
    final overlay = Overlay.of(context);
    _toastEntry?.remove();
    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (_) => _ReminderToast(
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
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
            Tokens.sp5, Tokens.sp3, Tokens.sp5, Tokens.sp4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Text('提醒设置',
                    style: TextStyle(
                        fontSize: Tokens.textLg,
                        fontWeight: FontWeight.w800,
                        color: Tokens.ink)),
                const Spacer(),
                Semantics(
                  label: '关闭', // 弹层族 ✕ aria 定式
                  button: true,
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Padding(
                      padding: EdgeInsets.all(Tokens.sp1),
                      child: Text('✕',
                          style: TextStyle(
                              fontSize: Tokens.textMd, color: Tokens.ink3)),
                    ),
                  ),
                ),
              ],
            ),
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
      ),
    );
  }
}

/// 弹层内浮层 toast（≙ H5 #toast：fixed 底部居中、盖在弹层之上、2.4s 自隐）。
/// Ticker 驱动（无裸 Timer，测试 pumpAndSettle 语义安全），播完自删。
/// 抄 goal_sheet.dart `_SheetToast` 定式——跨库私有类不可复用，若第三处再
/// 需则迁 common/（T7 收官可顺手，此处不过度设计）。
class _ReminderToast extends StatefulWidget {
  const _ReminderToast({required this.msg, required this.onDone});

  final String msg;
  final VoidCallback onDone;

  @override
  State<_ReminderToast> createState() => _ReminderToastState();
}

class _ReminderToastState extends State<_ReminderToast>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2400),
  );

  @override
  void initState() {
    super.initState();
    _c.forward().whenComplete(widget.onDone);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final opacity = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 0.0, end: 1.0), weight: 10),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.0), weight: 78),
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 0.0), weight: 12),
    ]).animate(_c);
    return IgnorePointer(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: Tokens.sp8),
          child: FadeTransition(
            opacity: opacity,
            child: Material(
              color: const Color(0xE632352D),
              borderRadius: BorderRadius.circular(14),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: Tokens.sp4,
                  vertical: Tokens.sp2,
                ),
                child: Text(
                  widget.msg,
                  style: const TextStyle(
                    fontSize: Tokens.textSm,
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
