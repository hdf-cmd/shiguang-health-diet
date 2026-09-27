// ShiguangFlutter/lib/features/exercise/exercise_controller.dart
// 运动记录读写控制器（M6-T2 立，M7-T2 Notifier 化 + 乐观 temp 行）。
// 行为权威源 js/app.js：保存链 :1807-1830 / 删除链 :1831-1852 /
// 渲染 :1740-1754。
// M7-T2 已对齐 H5 时序（M6 登记的 R4 差异 #1/#2 本批退役）：
// - R4 #1「无 temp 瞬显」退役：保存即插 temp 行（id=tmpx_<ms>、自带
//   createdAt ≙ :1813），合计经 exerciseKcalProvider fold 含 temp ≙ :1814
//   `s.exerciseKcal += kcal`；环/代谢卡随 fold 派生自动联动，
//   ≙ :1815-1816 renderRing()/renderMetab()。
// - R4 #2「成功 toast 迟一个网络往返」退役：「已记录…」temp 入列后即弹
//   （:1818，不等回包）→ await → 成功 loadExercises 重取真值替换（:1826
//   then）/ 失败按 id 摘除本笔 temp + 合计扣回 +「记录失败：msg||网络异常」
//   （:1827-1828）。失败分支不重取——H5 catch 不调 loadExercises，回滚
//   本身即落真值。删除链同款：确认 → 行即摘 +「已删除运动记录」即弹（:1842）
//   → await → 成功重取（:1846）/ 失败 rec 末位回插 +「删除失败：msg」（:1848-1850）。
// - 云态 ok:false（index.js:353-355 kcal 取整为 0 非 HTTP 错）走失败支：
//   真实链路 ApiClient:130 已按 api.js:263 抛 ApiException(message||'操作
//   失败')，测试桩直回 map 由本文件判 ok——两路同落「记录失败：+msg」（M6-T2
//   ⑤b 裁定保留：H5 此处仅靠 loadExercises 静默抹行，Flutter 明示错误，超集）。
// 重取语义（T1 carried 收口，home_controller :84 注兑现）：exercisesProvider
// 改 autoDispose——切走再切回同一天必重发请求 ≙ H5 每次切日期都 loadExercises
// （app.js:223），与 summary/records 两族同法；keepAlive 派生 provider 会钉死
// autoDispose 依赖（常驻监听不释放），exerciseKcalProvider 必须同批 autoDispose。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart' show ApiException;
import '../../data/health_api.dart' show HealthApi;
import '../../data/swr_cache.dart';
import '../../domain/constants.dart' show Exercise;
import '../../domain/exercise.dart' show exerciseKcalOf;
import '../../domain/js_compat.dart' show jsOr;
import '../home/home_controller.dart'
    show healthApiProvider, SwrFamilyNotifier;
import '../profile/profile_providers.dart' show profileProvider;

/// 某日运动记录（≙ H5 state.exercises 的 family(date) 形态）。
/// M7-T2 起为 AsyncNotifier.family（spec §3.2，工程首个 Notifier 类形态，
/// 水卡 T3 复用同款）：乐观写链在 [ExercisesNotifier.add]/[remove]；
/// autoDispose 收口「同日回访重取」（见文件头注）。
/// M9-T3：改挂 [SwrFamilyNotifier] 播种基类（键 `exercises.$date`）——重开
/// 首帧先显缓存旧值、后台刷新；首访失败仍抛（现行口径，基类 catch 只覆盖
/// 「有缓存」分支）；add/remove 后的 _reload 成功回写、失败清键（降级空
/// 列表不得成为下次播种的脏源）。
final exercisesProvider = AsyncNotifierProvider.autoDispose
    .family<ExercisesNotifier, List<Map<String, dynamic>>, String>(
  ExercisesNotifier.new,
);

class ExercisesNotifier
    extends SwrFamilyNotifier<List<Map<String, dynamic>>, String> {
  ExercisesNotifier(super.date);

  /// family 实参（≙ 取数刻的 state.date）——基类以 arg 承载，本文件沿用
  /// date 命名（add 的 body 「date': date」等多处读取）。
  String get date => arg;

  @override
  String cacheKey(String date) => 'exercises.$date';

  @override
  Future<List<Map<String, dynamic>>> fetch(String date) =>
      _fetchAll(ref.watch(healthApiProvider));

  Future<List<Map<String, dynamic>>> _fetch() =>
      _fetchAll(ref.read(healthApiProvider));

  Future<List<Map<String, dynamic>>> _fetchAll(HealthApi api) async =>
      _mapRows(await api.getExercises(date));

  /// 契约映射：云端不回 createdAt（T1 登记）→ isRepRecord 对云行恒 false、
  /// rep 型退化按分钟显示，H5 同病 bug-for-bug，禁改云。
  static List<Map<String, dynamic>> _mapRows(List<dynamic> list) => list
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList(growable: false);

  /// ≙ app.js:1730-1737 loadExercises：重取失败 catch→[] 降级为空，不抛出
  /// （不阻断主流程；toast 已由写链先行给出，此处仅静默回落）。
  /// M9-T3：成功回写缓存（下次重开播种的就是云真值）；失败**连带清键**——
  /// 降级空列表若留在缓存里，下次重开先显「今天没运动」的假象即脏源。
  Future<void> _reload() async {
    final cache = ref.read(swrCacheProvider);
    try {
      final fresh = await _fetch();
      cache.write('exercises.$date', fresh);
      state = AsyncData(fresh);
    } catch (_) {
      cache.invalidate('exercises.$date'); // 降级不存脏（M9 失效矩阵行3）
      state = AsyncData(const <Map<String, dynamic>>[]); // :1732-1733
    }
  }

  /// 记一笔（≙ :1807-1830）。[kcal] 由调用层算好传入（客户端口径，
  /// :1810-1811；保存闸 :1812「请先设置运动量」是弹层职责，不到这里）。
  /// [toast] 由调用方注入（弹层 pop 后走 host ScaffoldMessenger / 首页卡
  /// 自身 messenger）。
  Future<void> add(
      Exercise lib, num amount, num kcal, void Function(String) toast) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final temp = <String, dynamic>{
      'id': 'tmpx_$now', // :1813 'tmpx_' + Date.now()
      'key': lib.key,
      'name': lib.name,
      'emoji': lib.emoji,
      'amount': amount,
      'unit': lib.unit,
      'kcal': kcal,
      'createdAt': now, // rep 型 temp 即显「N 次」（:1746 isRepRecord 吃 createdAt）
    };
    final prev = state.value ?? const <Map<String, dynamic>>[];
    // :1813-1816：push(temp) + 合计 +=（fold 派生即涨，环/代谢自动联动）
    state = AsyncData(<Map<String, dynamic>>[...prev, temp]);
    toast('已记录${lib.name} · 消耗 $kcal kcal'); // :1818 即弹，不等回包
    try {
      // body 七键逐字 :1820-1822（不含 id/createdAt——temp 键多，须显式取；
      // unit 直传 lib.unit，rep 归 min 是云 index.js:362 的事，端上不预处理）
      final res = await ref.read(healthApiProvider).addExercise(
        <String, dynamic>{
          'date': date,
          'key': lib.key,
          'name': lib.name,
          'emoji': lib.emoji,
          'amount': amount,
          'unit': lib.unit,
          'kcal': kcal,
        },
      );
      if (res['ok'] == false) {
        // 仅桩场景可达（真链 ApiClient 已抛 ≙ api.js:263）；文案口径同款
        throw ApiException(jsOr('${res['message'] ?? ''}', '操作失败'));
      }
      await _reload(); // :1826 then → loadExercises()：云真值替换 temp
    } on ApiException catch (e) {
      _rollbackTemp(temp, prev);
      toast('记录失败：${_failReason(e.message)}'); // :1828 「记录失败：+msg||网络异常」
    } catch (_) {
      _rollbackTemp(temp, prev);
      toast('记录失败：网络异常'); // 非 ApiException ≙ JS err.message undefined
    }
  }

  /// :1826 `s.exercises.filter(r => r.id !== temp.id)`——按 id 摘除本笔 temp
  /// （快照式回滚会误伤并发后到的行；temp 若已被中途重取吞掉则 no-op）。
  /// 合计扣回 ≙ :1826 `s.exerciseKcal -= kcal`（fold 重算天然成立）。
  void _rollbackTemp(
      Map<String, dynamic> temp, List<Map<String, dynamic>> prev) {
    final cur = state.value ?? prev;
    state = AsyncData(cur
        .where((r) => r['id'] != temp['id'])
        .toList(growable: false));
  }

  /// 删一条（≙ :1831-1852；确认弹层 :1833 与防重入守卫 :1832 归 UI——
  /// confirmDeleteExercise / 首页卡 _confirmOpen）。成功后重取真值；失败
  /// rec 末位回插 + 第二条 toast，H5 双 toast 链同款。
  Future<void> remove(
      Map<String, dynamic> rec, void Function(String) toast) async {
    final id = '${rec['id']}'; // 云 DELETE /diet/exercises/:id
    final prev = state.value ?? const <Map<String, dynamic>>[];
    if (prev.any((r) => '${r['id']}' == id)) {
      // :1836-1837 乐观删（H5 find 不到 rec 时跳过删块、toast 照弹——同构）
      state = AsyncData(prev
          .where((r) => '${r['id']}' != id)
          .toList(growable: false));
    }
    toast('已删除运动记录'); // :1842 即弹，不等回包
    try {
      await ref.read(healthApiProvider).deleteExercise(id); // :1843
      await _reload(); // :1846 then → loadExercises()
    } on ApiException catch (e) {
      _reinsert(rec);
      toast('删除失败：${_failReason(e.message)}'); // :1850
    } catch (_) {
      _reinsert(rec);
      toast('删除失败：网络异常');
    }
  }

  /// :1848 `s.exercises.push(rec)`——末位回插而非复原位（H5 Array.push 原样，
  /// bug-for-bug）。
  /// M7-T8（评审 T2 Minor①）：回插补 H5 :1835/:1836/:1844 `if (rec)` 的等值
  /// 闸——回插前判该行是否仍**不在** state：
  /// - 删链开局 find 不到行（H5 :1836 skip 删块、:1844 `if(rec)` skip push）
  ///   ⇔ Flutter prev.any 未命中跳过乐观删，本闸同判「行仍在场→不再回插」；
  /// - 乐观窗口内并发写链（add 成功支 :1826 loadExercises）把该行重取吞回 →
  ///   本闸不再插幽灵行（H5 该窗理论双插、下一拍 loadExercises 抹平——本端
  ///   对齐其抹平后稳态，超集防御登记）。
  void _reinsert(Map<String, dynamic> rec) {
    final cur = state.value ?? const <Map<String, dynamic>>[];
    final id = '${rec['id']}';
    if (cur.any((r) => '${r['id']}' == id)) return; // 闸：在场即吞（≙ !rec 支）
    state = AsyncData(<Map<String, dynamic>>[...cur, rec]);
  }
}

/// 某日运动合计（H5 state.exerciseKcal，app.js:1733 reduce 同构；
/// M7-T2 起 temp 行天然计入 ≙ :1814 `s.exerciseKcal += kcal`）。
/// autoDispose：不可 keepAlive——常驻派生会钉死 [exercisesProvider] 的
/// 同日元素，「回访重取」收口失效（文件头注）。签名不变（消费端零改动）。
final exerciseKcalProvider = Provider.autoDispose
    .family<int, String>((ref, date) => ref
        .watch(exercisesProvider(date))
        .maybeWhen(
          data: (l) => l.fold<int>(
              0, (a, r) => a + ((r['kcal'] as num?)?.toInt() ?? 0)),
          orElse: () => 0,
        ));

/// 体重源（app.js:1766/1810 `state.body ? state.body.weightKg : 55` 的
/// Flutter 等价：profileProvider.body.weightKg，缺省/在途 → null →
/// exerciseKcalOf 内部 55 兜底 ≙ JS undefined falsy 同路）。
num? exerciseWeightKg(WidgetRef ref) {
  final p = ref.read(profileProvider).maybeWhen(
      data: (v) => v, orElse: () => null); // 在途/失败 → 55 档（H5 state.body 未就绪同值）
  final body = p?['body'];
  final w = body is Map ? body['weightKg'] : null;
  return w is num ? w : null;
}

String _failReason(String msg) =>
    jsOr(msg, '网络异常'); // :1828 `err.message || '网络异常'`（口径收敛 jsOr）

/// 记一笔运动（顶层兼容壳，M6 消费端签名不变令）：kcal 客户端口径
/// （:1810-1811）→ 转调 [ExercisesNotifier.add] 全量乐观链（temp 即插、
/// toast 即弹、成功重取/失败摘除，见类注）。M7-T2 起「await 完成 = 云端
/// 终态已落」仍成立——壳的 Future 在回包处理完后结束，但 UI 反馈不再等它。
Future<void> addExerciseRecord(WidgetRef ref, String date, Exercise lib,
    num amount, void Function(String) toast) async {
  final kcal = exerciseKcalOf(lib, amount, exerciseWeightKg(ref));
  await ref.read(exercisesProvider(date).notifier).add(lib, amount, kcal, toast);
}

/// 删除一条运动（顶层兼容壳，签名不变）：转调 [ExercisesNotifier.remove]。
/// 确认弹层归 UI（confirmDeleteExercise，:1833）；调用点在回包处理完成后
/// 返回，成功/失败文案见链注（:1842/:1850）。
Future<void> deleteExerciseRecord(WidgetRef ref, String date,
    Map<String, dynamic> rec, void Function(String) toast) async {
  await ref.read(exercisesProvider(date).notifier).remove(rec, toast);
}
