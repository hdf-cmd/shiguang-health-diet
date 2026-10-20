// ShiguangFlutter/lib/data/swr_disk.dart
// M11-T3：SWR 缓存的磁盘后层（**保守版 a：落盘绑定 owner**）。
//
// 为什么是保守版：冷启动首帧之前，App 无法确认「当前 token 属于哪个账号」——
// prefs 里的 `sg_food_freq_counts_<uid>` 只能证明"本机最后一次用过谁"，不能证明
// "现在的会话是谁"。而 M9-T3 已经把「A 号的缓存键留着 ⇒ B 号首帧显 A 数」钉成
// 跨号脏源（auth_state.dart:67-92）。健康数据（体重/每日饮食）不容互读，故：
//   · login/register 成功 → wipe（清 entries + owner 置未绑定）
//   · profile 首次解析出 uid → bindOwner(uid)；owner 变了同样先清盘
//   · 未绑定 owner 期间只留存快照、不落盘（写了也没人认）
//   · 冷启动仅当盘上 owner 非空才播种
// 代价如实登记：同账号「杀进程再开」的首帧仍走网络一次（要等 profile 到手才知道
// 能落盘），换来的是零泄漏窗。
//
// 🔴 构建纪律（踩过才写下的）：本层曾被判"真机不生效"，实为**沙盒重打时漏拷
// `pubspec.lock`** ⇒ 无锁解析把 shared_preferences 换成 2.5.6 / android 2.5.0，
// Pigeon 桥签名对不上，运行时 `NoSuchMethodError: SharedPreferencesApiRegistrar
// .getAll` 使该插件全线失败。带上仓库锁（2.5.5 / 2.4.28）重打后，真机第二次冷启动
// T0+718ms 已直接显出额度与环（详见 M11 spec §14 复测记录）。
import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../domain/models.dart' show Summary;

/// 落盘键（单 blob，非每键一条：一次读盘即可灌满，避免启动期 N 次平台通道）。
abstract class SwrDisk {
  static const String kBlobKey = 'sg_swr_disk_v1';

  /// 已绑定的账号 uid；未绑定为空串。
  String get ownerUid;

  /// 读盘并解码成 {缓存键: 端上对象}。owner 未绑定 / 内容损坏 → 空表（不抛）。
  Future<Map<String, Object?>> readEntries();

  /// 绑定账号。uid 为空 → 不动；与现 owner 相同 → 不动（不清盘）；
  /// 不同 → 先清盘再绑定。**立即写穿**，不等节流。
  Future<void> bindOwner(String uid);

  /// 覆盖式落一份快照（节流 [kSwrFlushDelay] 后合并写盘；未绑定 owner 时只留存
  /// 快照不落盘，等 `bindOwner` 后由 `SwrCache.syncDisk()` 补一次）。
  void writeEntries(Map<String, Object?> entries);

  /// 立即把节流中的快照写下去（测试/退出前收口）。
  Future<void> flush();

  /// 清空盘与 owner（登录、登出、换号）。
  Future<void> wipe();
}

/// 落盘节流窗口：一次进页会连写 summary/records 数个键，合并成一次 prefs 写；
/// 进程被杀时最多丢这 300ms 内的增量（下轮回包照样重写）。
const Duration kSwrFlushDelay = Duration(milliseconds: 300);

/// 默认 null ＝ **不落盘**（纯内存退化）。组合根 root_container 注入
/// [PrefsSwrDisk]；单测自建容器时不注入即自然无 IO，避免「profile 解析点要读
/// disk」把一堆既有容器用例打成 UnimplementedError。
final swrDiskProvider = Provider<SwrDisk?>((ref) => null);

/* ---------------- 白名单与编解码（键驱动，值不需要自带类型标记） ---------------- */

/// 落盘窗口：只保今天起往前 [kSwrWindowDays] 天的日键，防 blob 无界增长。
const int kSwrWindowDays = 7;

final RegExp _dayKeyRe = RegExp(r'^(records|summary)\.(\d{4}-\d{2}-\d{2})$');

/// 该键是否落盘：日键（records./summary.，且在窗口内）+ 食物库快照族。
/// 其余一律不持久化——profile/exercises/周月报/体重趋势涉及更多新鲜度与
/// 编解码面，本批按最小可用收口（登记见 M11 spec §10）。
bool swrKeyPersists(String key) {
  if (key.startsWith('foods.full.')) return true;
  final m = _dayKeyRe.firstMatch(key);
  if (m == null) return false;
  return _withinWindow(m.group(2)!);
}

bool _withinWindow(String isoDate) {
  final d = DateTime.tryParse(isoDate);
  if (d == null) return false;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final cutoff = today.subtract(const Duration(days: kSwrWindowDays - 1));
  return !d.isBefore(cutoff);
}

/// 端上对象 → 可 jsonEncode 的结构。
Object? swrEncode(String key, Object? value) {
  if (key.startsWith('summary.')) {
    return value is Summary ? value.toMap() : null;
  }
  if (value is List) return value; // records.* / foods.full.* 本就是 Map 数组
  return null;
}

/// 盘上结构 → 端上对象。**必须还原成 `read<T>` 认得的运行型**，
/// 否则 Summary 解成 Map 会让类型闸判 miss，冷启动白播一次空。
Object? swrDecode(String key, Object? raw) {
  if (key.startsWith('summary.')) {
    return raw is Map ? Summary.fromMap(raw.cast<String, Object?>()) : null;
  }
  if (raw is List) {
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList(growable: false);
  }
  return null;
}

/// SharedPreferences 实现。整份会话数据存一个 JSON blob。
///
/// 🔴 全程「拿不到盘就当没盘」：本层是缓存旁路，绝不能把启动播种（main() 里
/// runApp 之前 await hydrate）或 profile 链拖挂。两处实测依据：① widget 测试未
/// mock prefs 时 `getInstance()` 抛 MissingPluginException，早先版本把 hydrate
/// 放在 AuthGate.bootstrap 里 await，导致 auth_expiry/account_switch 四用例整批
/// 停在登录页（Shell 永不出现）；② v2.7.2 真机 release 下该调用持续失败，
/// 本层因此全程静默降级——不崩、不拖慢，只是不生效。
class PrefsSwrDisk implements SwrDisk {
  Future<SharedPreferences>? _inst;

  Future<SharedPreferences?> get _prefs async {
    try {
      return await (_inst ??= SharedPreferences.getInstance());
    } catch (_) {
      _inst = null; // 失败不缓存 rejected future：下次仍有机会（如稍后已 mock）
      return null;
    }
  }

  String _owner = '';
  Map<String, Object?>? _pending; // 节流中的快照（null=无待写）
  Timer? _timer;
  Future<void>? _writing;

  @override
  String get ownerUid => _owner;

  @override
  Future<Map<String, Object?>> readEntries() async => (await _readBlob()).entries;

  Future<_Blob> _readBlob() async {
    final p = await _prefs;
    if (p == null) return const _Blob(owner: '', entries: {});
    final raw = p.getString(SwrDisk.kBlobKey);
    if (raw == null) return const _Blob(owner: '', entries: {});
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return const _Blob(owner: '', entries: {});
      final owner = '${decoded['owner'] ?? ''}';
      _owner = owner;
      if (owner.isEmpty) return const _Blob(owner: '', entries: {});
      final entries = decoded['entries'];
      if (entries is! Map) return _Blob(owner: owner, entries: const {});
      return _Blob(
        owner: owner,
        entries: {
          for (final e in entries.entries)
            if (swrKeyPersists('${e.key}'))
              '${e.key}': swrDecode('${e.key}', e.value),
        },
      );
    } catch (_) {
      return const _Blob(owner: '', entries: {}); // 损坏即弃，下轮回包重写
    }
  }

  @override
  Future<void> bindOwner(String uid) async {
    if (uid.isEmpty) return; // 解析不出 uid：不绑，也不清已有绑定
    if (_owner.isEmpty) await _readBlob(); // 先认盘上现主，避免把同账号当换号
    if (_owner == uid) return;
    _owner = uid;
    _pending = null;
    _timer?.cancel();
    await _write(uid, const {}); // 换号：立即清 entries
  }

  @override
  void writeEntries(Map<String, Object?> entries) {
    // 🔴 未绑定 owner 时**照样留存快照**，只是先不落盘。
    // 早先这里是直接 return——而首页的 summary/records 常在 profile 回包（绑定
    // 时刻）之前就写入，快照被丢，绑定后又无补写触发点，结果盘上永远空、冷启动
    // 永远播不出数据（v2.7.2 真机 730ms 仍是骨架，实测）。
    _pending = Map.of(entries);
    if (_owner.isEmpty) return;
    _timer?.cancel();
    _timer = Timer(kSwrFlushDelay, _flushNow);
  }

  void _flushNow() {
    final snapshot = _pending;
    if (snapshot == null || _owner.isEmpty) return;
    _pending = null; // 只有真要写了才清，避免丢快照
    _writing = _write(_owner, snapshot);
  }

  @override
  Future<void> flush() async {
    _timer?.cancel();
    if (_pending != null && _owner.isNotEmpty) {
      _flushNow();
      await _writing;
      return;
    }
    await _writing; // 未绑定：保留 _pending，等绑定后 syncDisk 补一次
  }

  @override
  Future<void> wipe() async {
    _owner = '';
    _pending = null;
    _timer?.cancel();
    final p = await _prefs;
    if (p == null) return;
    await p.remove(SwrDisk.kBlobKey);
    await _writing;
  }

  Future<void> _write(String owner, Map<String, Object?> entries) async {
    final p = await _prefs;
    if (p == null) return; // 拿不到盘＝本次不落盘，绝不抛穿到调用方
    await p.setString(
      SwrDisk.kBlobKey,
      jsonEncode({
        'owner': owner,
        'entries': {
          for (final e in entries.entries)
            if (swrKeyPersists(e.key)) e.key: swrEncode(e.key, e.value),
        },
      }),
    );
  }
}

class _Blob {
  const _Blob({required this.owner, required this.entries});
  final String owner;
  final Map<String, Object?> entries;
}
