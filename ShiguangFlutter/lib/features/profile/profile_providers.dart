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
