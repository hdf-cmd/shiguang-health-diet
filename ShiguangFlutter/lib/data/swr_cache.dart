// M9-A1（spec §1）：会话级 SWR 内存缓存。生命周期=ProviderContainer=一次启动
// 进程；不做磁盘持久化（spec §5 YAGNI——跨启动新鲜度优先，重开 App 重拉一次
// 400ms 属可接受地板）。换号/登出经 auth_state 波次 clear() 全清。
import 'package:flutter_riverpod/flutter_riverpod.dart';

class SwrCache {
  final Map<String, Object?> _store = <String, Object?>{};

  /// 类型命中才返回——异型键视为 miss（防键冲突时 ClassCastException）。
  T? read<T>(String key) {
    final v = _store[key];
    return v is T ? v : null;
  }

  void write(String key, Object? value) => _store[key] = value;
  void invalidate(String key) => _store.remove(key);
  void invalidatePrefix(String prefix) =>
      _store.removeWhere((k, _) => k.startsWith(prefix));
  void clear() => _store.clear();
}

final swrCacheProvider = Provider<SwrCache>((ref) => SwrCache());

/// 写路径统一辅助：在既有 ref.invalidate(provider) 旁并排调用——
/// provider 重建播种时不再吃到写前旧数（spec §1 规则：读播种、写删键）。
void swrInvalidate(Ref ref, String key) =>
    ref.read(swrCacheProvider).invalidate(key);
