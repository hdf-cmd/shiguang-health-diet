// ShiguangFlutter/lib/features/exercise/exercise_controller.dart
// 运动记录读写控制器（M6-T2）。乐观更新+失败回滚模式对齐 record_controller
// 的 _syncDay 先例；行为权威源 js/app.js:1781-1852（chips 重置/步进/保存/删除）。
// 乐观简化裁定（M6 计划正文）：不做本地 temp 瞬显——写动作统一「await 云端 →
// 无论成败 invalidate 重取真值 → toast」；失败路径的 invalidate ≙ H5 :1824/:1845
// 的回滚（temp 行 removed / rec 回插在 Flutter 侧由「云端从未落库」天然成立）。
// 观感差异（无本地瞬显、成功 toast 迟于 H5 一个网络往返）登记 R4 面。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/api_client.dart' show ApiException;
import '../../domain/constants.dart' show Exercise;
import '../../domain/exercise.dart' show exerciseKcalOf;
import '../../domain/js_compat.dart' show jsOr;
import '../home/home_controller.dart'
    show healthApiProvider, summaryProvider;
import '../profile/profile_providers.dart' show profileProvider;

/// 某日运动记录（HealthAPI.getExercises → 契约 exercises 数组：
/// {id,key,name,emoji,amount,unit,kcal}——云端不回 createdAt（T1 登记），
/// isRepRecord 判别恒退化按分钟显示，H5 同病 bug-for-bug，禁改云）。
final exercisesProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((
  ref,
  date,
) async {
  final list = await ref.watch(healthApiProvider).getExercises(date);
  return list
      .whereType<Map>()
      .map((e) => Map<String, dynamic>.from(e))
      .toList(growable: false);
});

/// 某日运动合计（H5 state.exerciseKcal，app.js:1733 reduce 同构）
final exerciseKcalProvider = Provider.family<int, String>((ref, date) =>
    ref.watch(exercisesProvider(date)).maybeWhen(
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

void _syncDay(WidgetRef ref, String date) {
  ref.invalidate(exercisesProvider(date));
  ref.invalidate(summaryProvider(date));
}

String _failReason(String msg) =>
    jsOr(msg, '网络异常'); // :1828 `err.message || '网络异常'`（口径收敛 jsOr）

/// 记一笔运动（≙ app.js:1807-1830 save 处理链的云端段）。
/// body 七键逐字 :1820-1822：{date,key,name,emoji,amount,unit,kcal}，
/// unit 直传 lib.unit（rep 归 min 是云 index.js:362 的事，端上不预处理）。
/// 云 kcal 取整为 0 时回 {ok:false,message} 而非 HTTP 错（index.js:353-355，
/// T1 桩已锁）→ 调用层判 ok 走失败文案；ApiException/其它错走网络错，
/// 两路 toast 同「记录失败：+msg」。成功文案「已记录{名} · 消耗 {kcal} kcal」。
Future<void> addExerciseRecord(WidgetRef ref, String date, Exercise lib,
    num amount, void Function(String) toast) async {
  final kcal = exerciseKcalOf(lib, amount, exerciseWeightKg(ref));
  final body = <String, dynamic>{
    'date': date,
    'key': lib.key,
    'name': lib.name,
    'emoji': lib.emoji,
    'amount': amount,
    'unit': lib.unit,
    'kcal': kcal,
  };
  try {
    final res = await ref.read(healthApiProvider).addExercise(body);
    _syncDay(ref, date); // 成败均重取真值（简化裁定，见头注）
    if (res['ok'] == false) {
      toast('记录失败：${_failReason('${res['message'] ?? ''}')}');
      return;
    }
    toast('已记录${lib.name} · 消耗 $kcal kcal'); // :1819 逐字
  } on ApiException catch (e) {
    _syncDay(ref, date);
    toast('记录失败：${_failReason(e.message)}'); // :1828 逐字
  } catch (_) {
    _syncDay(ref, date);
    toast('记录失败：网络异常');
  }
}

/// 删除一条运动（≙ app.js:1831-1852 deleteExerciseById 的云端段，
/// 确认弹层归 UI：confirmDeleteExercise）。成功「已删除运动记录」(:1842)、
/// 失败「删除失败：+msg」(:1850)；R4 差异：H5 确认后立即乐观删行并出成功
/// toast（失败再回插+第二条 toast），Flutter 单条 toast（成功或失败）。
Future<void> deleteExerciseRecord(WidgetRef ref, String date,
    Map<String, dynamic> rec, void Function(String) toast) async {
  final id = '${rec['id']}'; // 云 DELETE /diet/exercises/:id
  try {
    await ref.read(healthApiProvider).deleteExercise(id);
    _syncDay(ref, date);
    toast('已删除运动记录'); // :1842 逐字
  } on ApiException catch (e) {
    _syncDay(ref, date); // 重取真值 ≙ 回滚回插
    toast('删除失败：${_failReason(e.message)}'); // :1850 逐字
  } catch (_) {
    _syncDay(ref, date);
    toast('删除失败：网络异常');
  }
}
