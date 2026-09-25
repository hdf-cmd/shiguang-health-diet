// ShiguangFlutter/test/scale_fakes.dart
// 秤编排层测试共用替身（M4-T4 起被 scale_service_test 与 profile_screen_test
// 两处消费，非 *_test.dart 后缀不会被单独执行）。原为 scale_service_test.dart
// 私有——体重卡 UI 测试同样需要 FakeTransport 推读数/挂扫描/断言协作取消，
// 第三份不该再抄（harness.dart 同款收敛理由）。
import 'dart:async';

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
    this.ignoreCancelSignal = false,
  });

  final bool permissionsGranted;
  final bool scanReturnsSession;

  /// 非空 → scanAndConnect 抛该异常（TransportException 或任意 Error）
  final Object? scanError;

  /// true = scanAndConnect 不再即时完成：挂在 scanGates 上，由测试调
  /// completeScanGate "让扫描迟到成功"。真机扫描是秒级等待，即时完成的假
  /// 实现测不出"cancel 时旧 scanAndConnect 仍在途"的并发窗口（评审 I1）。
  final bool gateScans;

  /// true（配合 gateScans）= scanAndConnect **不**协作取消：cancelSignal 先行
  /// 落地也照旧挂在 gate 上，由测试 completeScanGate 迟到产出会话。模拟
  /// honor 不了 cancelSignal 的 transport 实现，专打编排层
  /// scale_service.dart:200-207 的兜底分支（T8 缓办 A）。
  final bool ignoreCancelSignal;

  final List<List<int>> writes = [];
  final List<FakeSession> sessions = [];
  final List<Completer<TransportSession?>> scanGates = [];

  /// 非空 → writeFrame 挂起（模拟在途握手写）
  Completer<void>? writeBlocker;

  /// 非空 → close() 挂在异步段（模拟 disconnect 未完成）
  Completer<void>? closeBlocker;

  int scanAndConnectCalls = 0;

  /// M4-T4 协作取消：scanAndConnect 带 cancelSignal 且其先行落地的次数
  /// （真机契约 = 协作终结：不产生会话、返回 null，blue_plus_transport
  /// 的代际守卫在用例里由本字段 + scanGates 不被消费来钉）。
  int scanAborts = 0;

  /// 最近一次 scanAndConnect 收到的 cancelSignal（编排层必须注入，M4-T4）
  Future<void>? lastCancelSignal;
  String? lastScanPrefix;
  Duration? lastScanTimeout;
  bool permissionsCalled = false;
  bool notificationsSubscribed = false;

  final StreamController<List<int>> _notifications =
      StreamController<List<int>>.broadcast();

  void emit(List<int> frame) => _notifications.add(frame);

  /// 测试驱动：让第 index 条挂起的扫描"终于成功"，现场创建并返回新会话。
  /// 已被协作取消的扫描不得再调本方法（其 gate 由 cancelSignal 先行完成）。
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

  // 协作取消竞速哨兵（与 blue_plus_transport 同构：迟到完成包成值，
  // 不产生 unhandled error）
  static const Object _abortToken = _FakeAbort();

  @override
  Future<TransportSession?> scanAndConnect({
    required String namePrefix,
    required Duration timeout,
    Future<void>? cancelSignal,
  }) async {
    scanAndConnectCalls++;
    lastScanPrefix = namePrefix;
    lastScanTimeout = timeout;
    lastCancelSignal = cancelSignal;
    if (scanError != null) throw scanError!;
    if (!scanReturnsSession) return null;
    if (gateScans) {
      final gate = Completer<TransportSession?>();
      scanGates.add(gate);
      if (cancelSignal != null && !ignoreCancelSignal) {
        final winner = await Future.any(<Future<Object?>>[
          gate.future.then<Object?>((s) => s),
          cancelSignal.then<Object?>((_) => _abortToken),
        ]);
        if (identical(winner, _abortToken)) {
          scanAborts++; // 协作终结：不建会话、不 close、返回 null
          return null;
        }
        return winner as TransportSession?;
      }
      return gate.future; // 兼容不带信号的旧路径
    }
    final s = FakeSession(this);
    sessions.add(s);
    return s;
  }
}

class _FakeAbort {
  const _FakeAbort();
}

/// 让 start() 里的权限/连接等 microtask 段跑完
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 5));
