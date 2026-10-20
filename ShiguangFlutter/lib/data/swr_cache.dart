// M9-A1（spec §1）：会话级 SWR 内存缓存，生命周期=ProviderContainer=一次启动进程。
// M11-T3 起增**磁盘后层**（[SwrDisk]，保守版 a：落盘绑定账号 owner，见 swr_disk.dart
// 头注）——推翻 M9 §5「不做磁盘持久化」那条 YAGNI 裁定；根因是老大 10-19 反馈
// 「每次加载数据都很慢」：内存缓存跨进程即失效，冷启动 4 次往返全裸奔。
// 换号/登出经 auth_state 波次 clear() 全清（含盘）。
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'swr_disk.dart';

class SwrCache {
  /// [disk] 为 null 时退化为纯内存（单测与未注入组合根的默认形态）。
  SwrCache({this.disk});

  final SwrDisk? disk;
  final Map<String, Object?> _store = <String, Object?>{};

  /// 键代次（M11-T2）：任何一次 `write`/`invalidate`/`clear` 都算「比在途回包更新
  /// 的事件」，代次 +1。SWR 语义是「先播种再后台刷新」，而刷新用的值是**发起时**
  /// 抓的——期间若发生写路径的乐观落位或删键，迟到回包就会把旧数据盖回缓存
  /// （实测：删掉的那条在回包后复活，直到下一次重取）。fetch 方据此判定自己是否
  /// 过期（见 [revision] 与 home_controller.SwrFamilyNotifier.build）。
  final Map<String, int> _rev = <String, int>{};

  /// 当前代次；键不存在按 0。
  int revision(String key) => _rev[key] ?? 0;

  /// 显式把键的代次 +1，宣告「此刻之前的在途读数全部作废」。
  /// 用于写路径的服务端提交点（M11-T2）：乐观位与提交之间发起的那次后台刷新，
  /// 拿的是**提交前**的云端数据，回包必须丢弃——否则刚删掉的记录会闪回。
  void stamp(String key) => _bump(key);

  /// 挂起中的键：本次会话内「有写操作在途」，期间任何后台刷新回包都不得落缓存。
  /// 为什么代次判据不够：删一笔提交**之前**发起的刷新，服务端此刻确实还留着那条
  /// 记录——那是合法读数，代次也判不出来。实测结果就是「删掉的行闪一下又回来」
  /// 约一个往返（~400ms）。故写路径 hold→提交→release，期间回包一律作废
  /// （release 时会再 stamp 一次并重建 provider，云端终态照样对账回来）。
  final Set<String> _held = <String>{};

  void hold(String key) => _held.add(key);
  void release(String key) => _held.remove(key);
  bool isHeld(String key) => _held.contains(key);

  void _bump(String key) => _rev[key] = (_rev[key] ?? 0) + 1;

  /// 类型命中才返回——异型键视为 miss（防键冲突时 ClassCastException）。
  T? read<T>(String key) {
    final v = _store[key];
    return v is T ? v : null;
  }

  void write(String key, Object? value) {
    _store[key] = value;
    _bump(key);
    syncDisk();
  }

  void invalidate(String key) {
    if (_store.remove(key) != null || _rev.containsKey(key)) _bump(key);
    syncDisk();
  }

  void invalidatePrefix(String prefix) {
    for (final k in _store.keys.where((k) => k.startsWith(prefix)).toList()) {
      _store.remove(k);
      _bump(k);
    }
    syncDisk();
  }

  void clear() {
    for (final k in _store.keys.toList()) {
      _bump(k);
    }
    _store.clear();
    _held.clear(); // 换号/登出：挂起标记同清，防跨账号残留
    disk?.wipe(); // M11-T3：登出/换号连盘一起清（owner 同清，防下号吃到）
  }

  /// 冷启动播种：把盘上白名单键灌回内存。只灌内存里还没有的键，且必须在任何
  /// provider 起建之前 await 完（组合根在 AuthGate.bootstrap 里调用），否则
  /// 「回包先写、盘后灌」会由本方法的 containsKey 闸自动避让。
  Future<void> hydrate() async {
    final d = disk;
    if (d == null) return;
    final entries = await d.readEntries();
    for (final e in entries.entries) {
      if (e.value != null && !_store.containsKey(e.key)) _store[e.key] = e.value;
    }
  }

  /// 把节流中的落盘快照立即写下去（测试与退出收口用；生产由 debounce 自动跑）。
  Future<void> flushDisk() async => disk?.flush();

  /// 每次缓存变动后重算白名单快照交盘层（含 7 天窗口剪枝，防 blob 无界增长）。
  /// 公开给「owner 刚绑定」的时刻补一次同步：绑定前发生的写入只在盘层留着快照、
  /// 并未落盘，靠这里推一次才真正落（真机实测缺陷，见 swr_disk.dart ⑭ 号钉）。
  void syncDisk() {
    final d = disk;
    if (d == null) return;
    d.writeEntries({
      for (final e in _store.entries)
        if (swrKeyPersists(e.key)) e.key: e.value,
    });
  }
}

final swrCacheProvider = Provider<SwrCache>((ref) => SwrCache());

/// 写路径统一辅助：在既有 ref.invalidate(provider) 旁并排调用——
/// provider 重建播种时不再吃到写前旧数（spec §1 规则：读播种、写删键）。
void swrInvalidate(Ref ref, String key) =>
    ref.read(swrCacheProvider).invalidate(key);
