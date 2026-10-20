// ShiguangFlutter/test/data/swr_disk_test.dart
// M11-T3 钉：SWR 磁盘后层（保守版 a：落盘绑定 owner，换号/登录必清）。
//
// 为什么保守版：冷启动首帧之前确认不了「当前 token 属于谁」，而 M9-T3 已钉死
// 「A 号键留着 ⇒ B 号首帧显 A 数」这条跨号脏源（auth_state.dart:67-92）。
// 故落盘 blob 带 owner：login/register → 清盘并置未绑定；profile 首次解析出
// uid → 绑定；冷启动仅 owner 非空才播种。
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/app/root_container.dart';
import 'package:shiguang_flutter/data/swr_cache.dart';
import 'package:shiguang_flutter/data/swr_disk.dart';
import 'package:shiguang_flutter/data/token_store.dart';
import 'package:shiguang_flutter/domain/models.dart' show Summary;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  Future<PrefsSwrDisk> mkDisk(
      {String owner = '', Map<String, Object?> entries = const {}}) async {
    final p = await SharedPreferences.getInstance();
    await p.setString(
        SwrDisk.kBlobKey, jsonEncode({'owner': owner, 'entries': entries}));
    return PrefsSwrDisk();
  }

  test('①owner 已绑定：hydrate 后内存命中，首帧可零网络播种', () async {
    final disk = await mkDisk(owner: 'u_a', entries: {
      'records.2026-10-19': [
        {'id': 'r1', 'name': '米饭', 'kcal': 232}
      ],
      'summary.2026-10-19': {'kcal': 232, 'target': 1679, 'carb': 51.8, 'protein': 5.2, 'fat': 0.6, 'water': 2},
    });
    final cache = SwrCache(disk: disk);
    await cache.hydrate();

    final rows = cache.read<List<Map<String, dynamic>>>('records.2026-10-19');
    expect(rows, isNotNull);
    expect(rows!.single['name'], '米饭');
    // Summary 必须还原成对象（不是 Map），否则 SwrFamilyNotifier 的 read<T> 判 miss
    expect(cache.read<Summary>('summary.2026-10-19'), isA<Summary>());
    expect(cache.read<Summary>('summary.2026-10-19')!.kcal, 232);
  });

  test('②owner 未绑定（空串）：一律不播种', () async {
    final disk = await mkDisk(owner: '', entries: {
      'records.2026-10-19': [
        {'id': 'r1', 'name': '写前旧餐'}
      ],
    });
    final cache = SwrCache(disk: disk);
    await cache.hydrate();
    expect(cache.read<Object>('records.2026-10-19'), isNull);
  });

  test('③换号即清盘：bindOwner 到不同 uid 时旧账号数据必丢弃', () async {
    final disk = await mkDisk(owner: 'u_a', entries: {
      'records.2026-10-19': [
        {'id': 'r1', 'name': 'A 的饮食'}
      ],
    });
    final cache = SwrCache(disk: disk);
    await cache.hydrate();
    expect(cache.read<Object>('records.2026-10-19'), isNotNull);

    await disk.bindOwner('u_b'); // B 号 profile 到手（立即写穿，不等节流）

    // 盘上 A 的数据必须已消失：重新构造 disk 只读盘，不再写夹具
    final fresh = SwrCache(disk: PrefsSwrDisk());
    await fresh.hydrate();
    expect(fresh.read<Object>('records.2026-10-19'), isNull);
    expect((await SharedPreferences.getInstance()).getString(SwrDisk.kBlobKey),
        contains('"owner":"u_b"'));
  });

  test('④同一 uid 重复绑定不清盘（每次进 App 都会解析 profile）', () async {
    final disk = await mkDisk(owner: 'u_a', entries: {
      'records.2026-10-19': [
        {'id': 'r1', 'name': '米饭'}
      ],
    });
    await disk.bindOwner('u_a');
    final fresh = SwrCache(disk: PrefsSwrDisk());
    await fresh.hydrate();
    expect(fresh.read<Object>('records.2026-10-19'), isNotNull);
  });

  test('⑤白名单外的键不落盘（profile/weightTrend/exercises 等）', () async {
    final disk = PrefsSwrDisk();
    await disk.bindOwner('u_a'); // 未绑定期间本就不落盘（②/保守版口径）
    final cache = SwrCache(disk: disk);
    cache.write('records.2026-10-19', [
      {'id': 'r1', 'name': '米饭'}
    ]);
    cache.write('exercises.2026-10-19', []);
    cache.write('weightTrend', {'points': <double>[], 'labels': <String>[]});
    await cache.flushDisk();

    final blob = (await SharedPreferences.getInstance()).getString(SwrDisk.kBlobKey)!;
    expect(blob, contains('records.2026-10-19'));
    expect(blob, isNot(contains('weightTrend')));
    expect(blob, isNot(contains('exercises.')));
  });

  test('⑥超 7 天窗口的 records/summary 键被剪掉（防 blob 无界增长）', () async {
    final disk = PrefsSwrDisk();
    await disk.bindOwner('u_a');
    final cache = SwrCache(disk: disk);
    cache.write('records.2026-10-19', [
      {'id': 'ok'}
    ]);
    cache.write('records.2020-01-01', [
      {'id': 'ancient'}
    ]);
    await cache.flushDisk();

    final fresh = SwrCache(disk: PrefsSwrDisk());
    await fresh.hydrate();
    expect(fresh.read<Object>('records.2026-10-19'), isNotNull);
    expect(fresh.read<Object>('records.2020-01-01'), isNull);
  });

  test('⑦blob 损坏 → 静默视为空，不抛（下次回包自然重写）', () async {
    final p = await SharedPreferences.getInstance();
    await p.setString(SwrDisk.kBlobKey, '{这不是 JSON');
    final cache = SwrCache(disk: PrefsSwrDisk());
    await cache.hydrate(); // 不抛即通过
    expect(cache.read<Object>('records.2026-10-19'), isNull);
  });

  test('⑧写路径删键同步落盘：invalidate 后重开也不得吃到旧值', () async {
    final disk = PrefsSwrDisk();
    await disk.bindOwner('u_a');
    final cache = SwrCache(disk: disk);
    cache.write('records.2026-10-19', [
      {'id': 'r1', 'name': '旧行'}
    ]);
    await cache.flushDisk();
    cache.invalidate('records.2026-10-19');
    await cache.flushDisk();

    final fresh = SwrCache(disk: PrefsSwrDisk());
    await fresh.hydrate();
    expect(fresh.read<Object>('records.2026-10-19'), isNull);
  });

  test('⑨clear()（登出/换号）连盘一起清', () async {
    final disk = PrefsSwrDisk();
    await disk.bindOwner('u_a');
    final cache = SwrCache(disk: disk);
    cache.write('records.2026-10-19', [
      {'id': 'r1'}
    ]);
    await cache.flushDisk();

    cache.clear();
    await cache.flushDisk();

    final p = await SharedPreferences.getInstance();
    final blob = p.getString(SwrDisk.kBlobKey);
    expect(blob == null || blob.contains('"entries":{}'), isTrue,
        reason: '登出后盘上不得残留任何账号数据');
  });

  test('⑩组合根未注入 disk 时退化为纯内存（既有 15 处同步读点不受影响）', () async {
    final cache = SwrCache();
    cache.write('records.2026-10-19', [
      {'id': 'r1'}
    ]);
    await cache.flushDisk(); // 无 disk 也必须是 no-op 而非抛
    await cache.hydrate();
    expect(cache.read<Object>('records.2026-10-19'), isNotNull);
  });

  test('⑪未绑定 owner 时即便 flush 也不产生任何盘内容', () async {
    final disk = PrefsSwrDisk();
    final cache = SwrCache(disk: disk);
    cache.write('records.2026-10-19', [
      {'id': 'r1', 'name': '登录前的写入'}
    ]);
    await cache.flushDisk();
    final p = await SharedPreferences.getInstance();
    expect(p.getString(SwrDisk.kBlobKey), isNull);
  });

  /* ---------- 接线面：生产装配真的带盘，且换号真的清盘 ---------- */

  test('⑫buildRootContainer 默认装配把 disk 接进 SwrCache（漏接＝T3 整批白做）',
      () async {
    final fake = _FakeDisk();
    final container = buildRootContainer(
      tokenStore: InMemoryTokenStore(),
      dio: Dio(),
      swrDisk: fake,
    );
    addTearDown(container.dispose);
    expect(container.read(swrCacheProvider).disk, same(fake));
    expect(container.read(swrDiskProvider), same(fake));
  });

  test('⑭🔴 绑定前发生的写入，绑定后必须能补落盘（真机实测缺陷）', () async {
    // 时序真相：首页 summary/records 常在 profile 回包（=bindOwner）之前就写进
    // SwrCache。早先实现里 writeEntries 未绑定即 return，快照被丢弃，之后再没有
    // 补写触发点 → 盘上永远空 → 冷启动永远播不出数据（v2.7.2 真机 730ms 仍是骨架）。
    final disk = PrefsSwrDisk();
    final cache = SwrCache(disk: disk);
    cache.write('records.2026-10-19', [
      {'id': 'r1', 'name': '米饭', 'kcal': 232}
    ]);
    cache.write('summary.2026-10-19',
        Summary.fromMap(StubSummaryMaps.k232));
    await cache.flushDisk();
    var p = await SharedPreferences.getInstance();
    expect(p.getString(SwrDisk.kBlobKey), isNull); // 未绑定：不落（⑪口径）

    await disk.bindOwner('u_a'); // profile 到手才绑定
    cache.syncDisk(); // 绑定后补一次同步（生产由 profileProvider 调）
    await cache.flushDisk();

    p = await SharedPreferences.getInstance();
    expect(p.getString(SwrDisk.kBlobKey), isNotNull);
    final fresh = SwrCache(disk: PrefsSwrDisk());
    await fresh.hydrate();
    final rows = fresh.read<List<Map<String, dynamic>>>('records.2026-10-19');
    expect(rows, isNotNull, reason: '绑定前的写入必须在绑定后落盘，否则冷启动无数据可播');
    expect(rows!.single['name'], '米饭');
    expect(fresh.read<Summary>('summary.2026-10-19')!.kcal, 232);
  });

  test('⑮换号绑定不得把上一个账号的在途快照写进新 owner', () async {
    final disk = PrefsSwrDisk();
    await disk.bindOwner('u_a');
    final cache = SwrCache(disk: disk);
    cache.write('records.2026-10-19', [
      {'id': 'r1', 'name': 'A 的饮食'}
    ]);
    await cache.flushDisk();

    // 生产序：login → SwrCache.clear()（含 wipe）→ 重取 B 数据 → profile 绑 B
    cache.clear();
    await cache.flushDisk();
    await disk.bindOwner('u_b');
    cache.syncDisk();
    await cache.flushDisk();

    final p = await SharedPreferences.getInstance();
    final blob = p.getString(SwrDisk.kBlobKey)!;
    expect(blob, contains('"owner":"u_b"'));
    expect(blob, isNot(contains('A 的饮食')), reason: '换号后盘上只能是新账号数据');
  });

  test('⑬SwrCache.clear() 连盘一起清（submit/signOut 波次打到盘的这一环；'
      '「换号后无 A 残留」的端到端面已由 account_switch_cache_test 钉住）', () async {
    final fake = _FakeDisk();
    final container = buildRootContainer(
      tokenStore: InMemoryTokenStore(),
      dio: Dio(),
      swrDisk: fake,
    );
    addTearDown(container.dispose);
    // 走真实装配的 AuthApi 需要网络，这里只验「失效波次确实打到盘」：
    // AuthNotifier._invalidateAccountScopedCaches → SwrCache.clear → disk.wipe。
    container.read(swrCacheProvider).clear();
    await Future<void>.delayed(Duration.zero);
    expect(fake.wipeCount, 1);
  });
}

/// Summary 夹具（避免依赖 StubHealthApi 的构造签名）。
class StubSummaryMaps {
  static final Map<String, Object?> k232 = {
    'kcal': 232,
    'target': 1679,
    'carb': 51.8,
    'protein': 5.2,
    'fat': 0.6,
    'water': 2,
  };
}

/// 记录调用次数的盘替身（不碰 prefs）。
class _FakeDisk implements SwrDisk {
  int wipeCount = 0;
  int bindCount = 0;
  Map<String, Object?>? lastSnapshot;

  @override
  String get ownerUid => '';

  @override
  Future<Map<String, Object?>> readEntries() async => const {};

  @override
  Future<void> bindOwner(String uid) async => bindCount++;

  @override
  void writeEntries(Map<String, Object?> entries) => lastSnapshot = entries;

  @override
  Future<void> flush() async {}

  @override
  Future<void> wipe() async => wipeCount++;
}
