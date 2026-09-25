// ShiguangFlutter/test/scale_service_test.dart
// M4-T3 体脂秤编排层单测：FakeTransport 注入，锁死 ScaleSync.kt 移植语义。
// 权威源：HealthyDiet/.../ScaleSync.kt :57/:81/:106 lockedSent、:83-85 读超时、
// :85 扫描超时、:91 AFU- 前缀、:129-131 断连、:187-193 握手三帧、:224-237 emit 去重。
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shiguang_flutter/domain/scale_protocol.dart';
import 'package:shiguang_flutter/features/scale/scale_service.dart';

/// 组一条合法的 0x51 实时体重帧（协议域常量 + frameCrc 复用，避免测试自造校验）
List<int> liveFrame(double kg, {bool locked = false, int wireType = kWireLive}) {
  final grams = (kg * 1000).round();
  var flags = grams & kWeightMask;
  if (locked) flags |= 1 << 31;
  final f = List<int>.filled(kScaleFrameLen, 0);
  f[0] = 0xAF;
  f[1] = 0x45;
  f[2] = flags & 0xFF;
  f[3] = (flags >> 8) & 0xFF;
  f[4] = (flags >> 16) & 0xFF;
  f[5] = (flags >> 24) & 0xFF;
  f[18] = wireType;
  f[19] = frameCrc(f);
  return f;
}

class FakeSession implements TransportSession {
  FakeSession(this._t);
  final FakeTransport _t;

  /// close() 已调用（编排层 _finish 归还登记）
  bool closed = false;

  /// 真机语义里"订阅取消 + GATT 断开"要 await 平台通道：本字段在 close 的
  /// 异步尾巴落地后才置 true。修复前 BluePlusTransport 把 device/_charSubs/
  /// _writeChr 挂在 transport 实例字段上，旧会话 close 执行到一半时会误伤
  /// "此刻字段里的"新会话（评审 I1）；会话状态收进 session 后不再可能。
  bool transportDisconnected = false;
  bool writeChannelOpen = true;

  @override
  Future<void> writeFrame(List<int> f) async {
    final block = _t.writeBlocker;
    if (block != null) await block.future; // 模拟握手写慢/在途
    // 对齐 blue_plus_transport：close 置空写通道后，在途/后续写帧抛
    // （评审 M2 的竞态入口：cancel→写抛→不得再产出第二终态）
    if (!writeChannelOpen) throw const TransportException('connect-fail', '已断开');
    _t.writes.add(List<int>.of(f));
  }

  @override
  Future<void> close() async {
    if (closed) return; // 幂等
    closed = true;
    final block = _t.closeBlocker;
    if (block != null) await block.future;
    writeChannelOpen = false;
    transportDisconnected = true;
  }
}

class FakeTransport implements ScaleTransport {
  FakeTransport({
    this.permissionsGranted = true,
    this.scanReturnsSession = true,
    this.scanError,
    this.gateScans = false,
  });

  final bool permissionsGranted;
  final bool scanReturnsSession;

  /// 非空 → scanAndConnect 抛该异常（TransportException 或任意 Error）
  final Object? scanError;

  /// true = scanAndConnect 不再即时完成：挂在 scanGates 上，由测试调
  /// completeScanGate "让扫描迟到成功"。真机扫描是秒级等待，即时完成的假
  /// 实现测不出"cancel 时旧 scanAndConnect 仍在途"的并发窗口（评审 I1）。
  final bool gateScans;

  final List<List<int>> writes = [];
  final List<FakeSession> sessions = [];
  final List<Completer<TransportSession?>> scanGates = [];

  /// 非空 → writeFrame 挂起（模拟在途握手写）
  Completer<void>? writeBlocker;

  /// 非空 → close() 挂在异步段（模拟 disconnect 未完成）
  Completer<void>? closeBlocker;

  int scanAndConnectCalls = 0;
  String? lastScanPrefix;
  Duration? lastScanTimeout;
  bool permissionsCalled = false;
  bool notificationsSubscribed = false;

  final StreamController<List<int>> _notifications =
      StreamController<List<int>>.broadcast();

  void emit(List<int> frame) => _notifications.add(frame);

  /// 测试驱动：让第 index 条挂起的扫描"终于成功"，现场创建并返回新会话
  FakeSession completeScanGate(int index) {
    final s = FakeSession(this);
    sessions.add(s);
    scanGates[index].complete(s);
    return s;
  }

  @override
  Stream<List<int>> notifications() {
    notificationsSubscribed = true;
    return _notifications.stream;
  }

  @override
  Future<bool> ensurePermissions() async {
    permissionsCalled = true;
    return permissionsGranted;
  }

  @override
  Future<TransportSession?> scanAndConnect(
      {required String namePrefix, required Duration timeout}) async {
    scanAndConnectCalls++;
    lastScanPrefix = namePrefix;
    lastScanTimeout = timeout;
    if (scanError != null) throw scanError!;
    if (!scanReturnsSession) return null;
    if (gateScans) {
      final gate = Completer<TransportSession?>();
      scanGates.add(gate);
      return gate.future; // 会话由 completeScanGate 现场创建后才交还
    }
    final s = FakeSession(this);
    sessions.add(s);
    return s;
  }
}

/// 让 start() 里的权限/连接等 microtask 段跑完
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 5));

void main() {
  // 测试用毫秒级超时（构造参数可注入是硬要求）
  ScaleService build(FakeTransport t) => ScaleService(
        t,
        scanTimeout: const Duration(milliseconds: 300),
        readTimeout: const Duration(milliseconds: 1500),
      );

  group('ScaleService 正常序列', () {
    test('3×非锁定渐进值→locked：readings 三条 + outcome ok/66.66', () async {
      final t = FakeTransport();
      final svc = build(t);
      final readings = <ScaleReading>[];
      svc.readings.listen(readings.add);

      final future = svc.start();
      await settle();
      expect(t.notificationsSubscribed, isTrue); // 连接后必须已订阅通知流
      expect(t.lastScanPrefix, 'AFU-'); // ScaleSync.kt:31 前缀过滤
      // M4：编排层 scanTimeout 必须原样注入 transport（钉死注入链）
      expect(t.lastScanTimeout, svc.scanTimeout);

      t.emit(liveFrame(60.1));
      t.emit(liveFrame(60.5));
      t.emit(liveFrame(66.66, locked: true));
      final outcome = await future;

      expect(outcome.status, 'ok');
      expect(outcome.kg, 66.66);
      expect(readings.map((r) => r.kg).toList(), [60.1, 60.5, 66.66]);
      expect(readings.map((r) => r.stable).toList(), [false, false, true]);
      expect(t.sessions.single.closed, isTrue); // finish → close
    });

    test('握手三帧逐帧写出，等于 handshakeFrames(now)，时间窗 ±2s', () async {
      final t = FakeTransport();
      final svc = build(t);
      final future = svc.start();
      final t0 = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      await future;
      final t1 = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      expect(t.writes.length, 3);
      for (final w in t.writes) {
        expect(w.length, kScaleFrameLen);
        expect(frameCrc(w), w[19]); // 写出的帧自身 crc 必须合法
      }
      // 帧2/帧3 与 SYNC 帧逐字节一致
      final expected = handshakeFrames(t0);
      expect(t.writes[1], expected[1]);
      expect(t.writes[2], expected[2]);
      // 帧1 校时帧：从 writes[0][3..6] 反解秒数，须在 [t0-2, t1+2] 窗内，
      // 且除 time4 外其余字节与 handshakeFrames(该秒) 帧1 全等
      final sec = t.writes[0][3] |
          (t.writes[0][4] << 8) |
          (t.writes[0][5] << 16) |
          (t.writes[0][6] << 24);
      expect(sec, inInclusiveRange(t0 - 2, t1 + 2));
      expect(t.writes[0], handshakeFrames(sec)[0]);
    });
  });

  group('ScaleService 去重/忽略', () {
    test('重复 locked 只发一次（lockedSent，ScaleSync.kt:57/:229）', () async {
      final t = FakeTransport();
      final svc = build(t);
      final readings = <ScaleReading>[];
      svc.readings.listen(readings.add);

      final future = svc.start();
      await settle();
      t.emit(liveFrame(66.66, locked: true));
      final outcome = await future;
      // 会话已结束；再推第二帧 locked 不得再发读数/再改 outcome
      t.emit(liveFrame(66.66, locked: true));
      await settle();

      expect(outcome.status, 'ok');
      expect(readings.length, 1);
      expect(readings.single.stable, isTrue);
    });

    test('同值非锁定只发一次（lastKg 去重，ScaleSync.kt:233）', () async {
      final t = FakeTransport();
      final svc = build(t);
      final readings = <ScaleReading>[];
      svc.readings.listen(readings.add);

      final future = svc.start();
      await settle();
      t.emit(liveFrame(60.1));
      t.emit(liveFrame(60.1));
      t.emit(liveFrame(60.5));
      t.emit(liveFrame(66.66, locked: true));
      await future;

      expect(readings.map((r) => r.kg).toList(), [60.1, 60.5, 66.66]);
    });

    test('0x54 旧存档 / 坏 crc / 坏头 / 坏长度帧全部被忽略', () async {
      final t = FakeTransport();
      final svc = build(t);
      final readings = <ScaleReading>[];
      svc.readings.listen(readings.add);

      final future = svc.start();
      await settle();
      t.emit(liveFrame(13.05, locked: true, wireType: 0x54)); // 旧存档
      final badCrc = liveFrame(70.0);
      badCrc[19] = (badCrc[19] + 7) & 0x1F;
      t.emit(badCrc);
      final badHeader = liveFrame(71.0)..[0] = 0x00;
      t.emit(badHeader);
      t.emit(liveFrame(72.0).sublist(0, 19)); // 长度≠20
      t.emit(liveFrame(60.1));
      t.emit(liveFrame(66.66, locked: true));
      final outcome = await future;

      expect(readings.map((r) => r.kg).toList(), [60.1, 66.66]);
      expect(outcome.kg, 66.66);
    });
  });

  group('ScaleService 错误路径', () {
    test('scanAndConnect 返回 null → scan-timeout', () async {
      final t = FakeTransport(scanReturnsSession: false);
      final svc = build(t);
      final outcome = await svc.start();
      expect(outcome.status, 'scan-timeout');
      expect(outcome.kg, isNull);
    });

    test('scanAndConnect 抛 TransportException(no-bluetooth) → no-bluetooth',
        () async {
      final t = FakeTransport(
          scanError: const TransportException('no-bluetooth', '蓝牙未开'));
      final svc = build(t);
      final outcome = await svc.start();
      expect(outcome.status, 'no-bluetooth');
    });

    test('scanAndConnect 抛其它异常 → connect-fail', () async {
      final t = FakeTransport(scanError: Exception('gatt 133'));
      final svc = build(t);
      final outcome = await svc.start();
      expect(outcome.status, 'connect-fail');
    });

    test('ensurePermissions 拒绝 → permission-denied 且不再扫描', () async {
      final t = FakeTransport(permissionsGranted: false);
      final svc = build(t);
      final outcome = await svc.start();
      expect(outcome.status, 'permission-denied');
      expect(t.scanAndConnectCalls, 0);
    });

    test('读数超时 → read-timeout 且关闭会话', () async {
      final t = FakeTransport();
      final svc = ScaleService(
        t,
        scanTimeout: const Duration(milliseconds: 300),
        readTimeout: const Duration(milliseconds: 60),
      );
      final outcome = await svc.start();
      expect(outcome.status, 'read-timeout');
      expect(t.sessions.single.closed, isTrue);
    });
  });

  group('ScaleService cancel/重入', () {
    test('cancel 幂等：进行中取消→cancelled，重复 cancel 不炸，可再 start',
        () async {
      final t = FakeTransport();
      final svc = build(t);
      final future = svc.start();
      await settle();
      await svc.cancel();
      final outcome = await future;
      expect(outcome.status, 'cancelled');

      await svc.cancel(); // 二次 cancel 幂等
      expect(t.sessions.single.closed, isTrue);

      // 取消后可重新发起（Kotlin start 前置 stop 语义）
      final next = svc.start();
      await settle();
      t.emit(liveFrame(66.66, locked: true));
      final outcome2 = await next;
      expect(outcome2.status, 'ok');
      expect(t.scanAndConnectCalls, 2);
    });

    test('重入 start 返回同一进行中 outcome（不并发两条会话）', () async {
      final t = FakeTransport();
      final svc = build(t);
      final a = svc.start();
      final b = svc.start();
      await settle();
      t.emit(liveFrame(66.66, locked: true));
      final oa = await a;
      final ob = await b;
      expect(identical(a, b), isTrue);
      expect(oa.status, 'ok');
      expect(ob.status, 'ok');
      expect(t.scanAndConnectCalls, 1);
    });

    test('I1 复现：cancel 时旧 scanAndConnect 在途 → 不得放行第二条会话；'
        '迟到会话归还与 close 异步尾巴均不得影响新会话', () async {
      final t = FakeTransport(gateScans: true);
      final svc = build(t);
      final readings = <ScaleReading>[];
      svc.readings.listen(readings.add);

      final f1 = svc.start();
      await settle();
      expect(t.scanGates.length, 1);

      await svc.cancel(); // 旧 _run 此刻仍卡在 scanAndConnect（真机秒级窗口）
      final f2 = svc.start();
      await settle();
      // 修复前：_finish 提前清 _inflight → 这里会并发发起第二条扫描（交叉断连根因）
      expect(t.scanAndConnectCalls, 1);
      expect(identical(f1, f2), isTrue); // 重入保护未解除：返回同一进行中 Future

      final s1 = t.completeScanGate(0); // 迟到的扫描"成功"→ 必须立即归还、不改终态
      final o1 = await f1;
      expect(o1.status, 'cancelled');
      expect(s1.closed, isTrue);

      final f3 = svc.start(); // 旧 _run 落地后，重来才真正发起第二条扫描
      await settle();
      expect(t.scanAndConnectCalls, 2);
      final s2 = t.completeScanGate(1);
      await settle();
      expect(s2.transportDisconnected, isFalse); // 旧会话归还没碰新会话
      expect(t.writes.length, 3); // 新会话握手三帧正常写出

      // 新会话收尾：close 挂异步尾巴（真机 disconnect 未完成）期间再开一条
      t.closeBlocker = Completer<void>();
      t.emit(liveFrame(66.66, locked: true));
      final o3 = await f3;
      expect(o3.status, 'ok');
      expect(o3.kg, 66.66);
      expect(readings.map((r) => r.kg).toList(), [66.66]);

      final f4 = svc.start();
      await settle();
      expect(t.scanAndConnectCalls, 3);
      final s3 = t.completeScanGate(2);
      await settle();
      expect(s3.transportDisconnected, isFalse); // s2 的 close 未串台到 s3
      t.closeBlocker!.complete(); // s2 的"断开落地"发生在 s3 已建立之后
      await settle();
      expect(s2.transportDisconnected, isTrue);
      t.emit(liveFrame(70.0, locked: true));
      final o4 = await f4;
      expect(o4.status, 'ok');
      expect(o4.kg, 70.0);
      expect(readings.map((r) => r.kg).toList(), [66.66, 70.0]);
    });

    test('M2：cancel 与在途握手写异常竞态 → start 与 cancel 两 waiter 同终态',
        () async {
      final t = FakeTransport();
      final svc = build(t);
      t.writeBlocker = Completer<void>(); // 握手第一帧卡在写上（真机秒级）
      final f = svc.start();
      await settle();
      await svc.cancel(); // _finish 关闭会话 → 写通道置空
      t.writeBlocker!.complete(); // 在途写恢复后抛（blue_plus :206-208 形状）
      final o = await f;
      // 修复前：_run 返回 connect-fail，而 cancel() 已拿到 cancelled——双终态
      expect(o.status, 'cancelled');
      expect(t.writes, isEmpty);
    });
  });
}
