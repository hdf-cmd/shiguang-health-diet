// ShiguangFlutter/lib/features/profile/weight_log_card.dart
// M8-①（老大 09-27 真机反馈）：体重记录卡从「我的」页整体搬入——现挂
// 「报告」页体重趋势卡下方（记录入口贴着趋势图，记完即见图变化）。
// 自 profile_screen.dart 原样拆出（行为零变更）：当前体重行/±0.5 stepper/
// 手动输入/保存/秤同步与 stable 秒存全链。
// 行为权威源 H5（拆分前口径，逐字未动）：
// - index.html:459-482 记体重区：label「今日体重」、stepper −/＋（aria ±0.5kg）、
//   保存、hint「点数字可直接输入…」、秤按钮「⚖️ 从体脂秤同步（光脚站上秤）」——文案逐字。
// - js/app.js:910 初始值 = 当前体重 || 55；:927-929 bumpBodyVal ±0.5、
//   边界 20–300、两位小数。
// - js/app.js:930-949 saveWeightKg：校验 20–300（不过 → toast「请输入有效体重」）
//   → logWeight(w, todayIso()) → toast「已记录 r.weightKg kg · 趋势已更新」。
// - js/app.js:953-956 SG_onScaleWeight(kg, stable)：读数写进输入位，仅 stable
//   调 saveWeightKg —— 本卡 ref.listen(scaleReadingsProvider) 同构：非 stable
//   只预览，stable 才落库（locked 秒存）。
// - 秤终态文案：ScaleSync.kt :71/:83/:85/:130、MainActivity.kt:52 逐字；
//   'ok' 静默（Kotlin finish :241 只转发非 ok，保存成功 toast 已覆盖）、
//   'cancelled' 静默（T3 账本 M5），未知状态 default 兜底静默。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/api_client.dart' show ApiException;
import '../common/breathing_capsule.dart' show LoadingSpinner;
import '../common/skeleton.dart' show SkeletonBar;
import '../../data/swr_cache.dart' show swrCacheProvider;
import '../../domain/dates.dart' show todayIso;
import '../home/home_controller.dart' show healthApiProvider;
import '../report/report_controller.dart' show weightTrendProvider;
import '../scale/scale_service.dart';
import 'profile_providers.dart' show profileProvider;

/// 当前体重（body-metrics.weightKg；键名对齐 contract/fixtures/diet-core.json
/// 与 domain/models.dart BodyMetrics.fromMap 的 weightKg）。
/// 保存成功后由本卡 invalidate 重取（H5 saveWeightKg 里 renderBodyCard 的等价物）。
/// M8-① 自 profile_screen.dart 迁入，随卡走；auth_state 换号失效清单引用同源。
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

/// 体重记录卡（当前体重/今日体重/秤同步/保存）——M8-① 起挂报告页体重趋势下方。
class WeightLogCard extends ConsumerStatefulWidget {
  const WeightLogCard({super.key});

  @override
  ConsumerState<WeightLogCard> createState() => _WeightLogCardState();
}

class _WeightLogCardState extends ConsumerState<WeightLogCard> {
  /// 今日体重输入位（手动 ±0.5 与秤 live 预览共写此处，对齐 H5 #weight-log-val）
  final _kgCtl = TextEditingController(text: '55.00');

  bool _seeded = false; // 首次取到当前体重时播种输入位（app.js:910 语义）
  bool _saving = false;
  bool _syncing = false;
  String? _syncStatus; // 进行中=寻找文案；终态错误=映射文案；ok/cancelled=null
  ScaleService? _scaleService; // dispose 时 cancel 用（不在 dispose 里读 ref）

  static const _kScanning = '正在寻找体脂秤…（请光脚站上秤）'; // ScaleSync.kt:98

  @override
  void dispose() {
    // 离开报告页（或整壳销毁）即终止进行中的秤会话——M4-T4 原「我的」页
    // 口径原样跟卡走：Shell 的 PageView 常驻四页，真离开整壳才到这里。
    if (_syncing) _scaleService?.cancel();
    _kgCtl.dispose();
    super.dispose();
  }

  void _toast(String msg) {
    if (!mounted) return;
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
      final r = await ref.read(healthApiProvider).logWeight(w, todayIso());
      if (!mounted) return;
      final rw = r['weightKg'];
      final shown = rw is num ? _jsNum(rw) : _jsNum(w);
      _toast('已记录 $shown kg · 趋势已更新'); // app.js:944 逐字
      ref.invalidate(profileWeightProvider); // 卡上当前体重跟着更新（renderBodyCard 等价）
      ref.invalidate(profileProvider); // M5-T6 身体卡/资料卡体重同步
      // M9-T3 评审 I1：写路径成功链必须删键（对照 record_controller._syncDay
      // 双删口径）——记重后旧趋势若留键，下次元素重建会播种「已记录」前的旧点。
      ref.read(swrCacheProvider).invalidate('weightTrend');
      ref.invalidate(weightTrendProvider); // M8-① 同页趋势卡随之重取（H5「趋势已更新」语义坐实）
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

  /// 手动保存入口：解析输入位（H5 Number(input.value)：空/非法 → 走无效体重）
  void _saveManual() {
    final w = _parsedKg;
    if (w == null) {
      _toast('请输入有效体重');
      return;
    }
    _saveWeight(w);
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

    return Container(
      width: double.infinity,
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
                loading: () => const SkeletonBar(width: 56, height: 20),
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
            child: _syncing
                ? const Row(mainAxisSize: MainAxisSize.min, children: [
                    LoadingSpinner(size: 14, color: Tokens.primaryDeep),
                    SizedBox(width: Tokens.sp2),
                    Text('⚖️ 从体脂秤同步（光脚站上秤）'),
                  ])
                : const Text('⚖️ 从体脂秤同步（光脚站上秤）'),
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
            onPressed: _saving ? null : _saveManual,
            child: _saving
                ? const Row(mainAxisSize: MainAxisSize.min, children: [
                    LoadingSpinner(),
                    SizedBox(width: Tokens.sp2),
                    Text('保存'),
                  ])
                : const Text('保存'), // index.html:481 逐字
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
