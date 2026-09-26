// ShiguangFlutter/lib/features/profile/profile_providers.dart
// 用户资料唯一读取源（GET /user/profile 一次拿全：nickname/signature/avatar/
// goal/body/bodyUpdatedAt，fixture 契约已锁 responseFields，见
// contract/fixtures/diet-core.json routes[profile]）。T5 资料卡头部/编辑弹层
// 与 T6 身体卡共用。非 autoDispose：与 profileWeightProvider 同属账号级缓存，
// 登出/换号经 auth_state._invalidateAccountScopedCaches 显式失效（终审 I1 口径）。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../home/home_controller.dart' show healthApiProvider;

final profileProvider = FutureProvider<Map<String, dynamic>>((ref) =>
    ref.watch(healthApiProvider).getProfile());

/// profile.goal.waterMl 的水目标口径（M6-T7 评审 F3+F4：收敛 water_card /
/// advice_card 两份近重复 `_goalOf` 为单一工具，并复刻 H5 falsy 支）。
/// ≙ app.js:1948 `state.waterGoalMl = profile.goal.waterMl || 1600`——
/// null/0 皆落 1600（state.js:13 初值），在途/失败无数据同档。
/// round 系显示取整（云回包恒整数值，对 advice 消费点为恒等；原 advice
/// 版不 round 的语义差在此闭合，登记 task-7-report）。
/// 消费点：water_card（goal 行/顶格闸）、advice_card（buildAdvice ctx）。
int waterGoalMlOf(AsyncValue<Map<String, dynamic>> profile) {
  final wm = profile.maybeWhen(
    data: (p) {
      final goal = p['goal'];
      final v = goal is Map ? goal['waterMl'] : null;
      return v is num ? v : null;
    },
    orElse: () => null,
  );
  if (wm == null || wm == 0) return 1600; // ≙ `|| 1600` falsy 支（F3）
  return wm.round();
}
