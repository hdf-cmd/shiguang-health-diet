// ShiguangFlutter/lib/features/scale/blue_plus_transport.dart
// M4-T3：ScaleTransport 的 flutter_blue_plus 薄实现。**全工程唯一 import
// BLE/权限插件的文件**（编排层 scale_service.dart 只依赖抽象，用 FakeTransport 测）。
// 无单测（插件走平台通道，VM 测试环境无真实蓝牙），真机验收；analyze 必须过。
//
// 插件 API 逐一对照安装源核实（禁止照记忆写）：
//   flutter_blue_plus 2.3.13
//     lib/src/flutter_blue_plus.dart :269 startScan({withServices, withNames,
//       withKeywords, Duration? timeout, ...})（timeout 由插件内部到点停扫）、
//       :83 scanResults → Stream<List<ScanResult>>、:412 stopScan()、
//       :195 adapterState → Stream<BluetoothAdapterState>（首事件即当前态）
//     lib/src/bluetooth_device.dart :106 connect({required License license,
//       Duration timeout = 35s, int? mtu = 512, bool autoConnect})——2.x 起
//       license 为必填枚举；:207 disconnect({timeout, queue, androidDelay})；
//       :262 discoverServices({timeout = 15}) → List<BluetoothService>；
//       :34 platformName / :41 advName
//     lib/src/bluetooth_characteristic.dart :256 setNotifyValue(bool, {timeout})、
//       :99 onValueReceived → Stream<List<int>>（仅通知到达）、
//       :189 write(List<int>, {withoutResponse, allowLongWrite, timeout})、
//       :28 properties → CharacteristicProperties{notify,indicate,write,
//       writeWithoutResponse}
//     platform_interface 9.0.3 guid.dart :68 Guid.str → 128-bit 厂商 UUID 返回
//       小写全串 → startsWith('af000002') 与 Kotlin uuid.toString() 语义一致
//   permission_handler 13.0.2 extension PermissionActions.request() →
//     PermissionStatus（isGranted）；permission_handler_android 14.1.0
//     PermissionUtils.java :489-504：API<31 时 BLUETOOTH_SCAN/CONNECT 不进
//     请求名单（返回 granted）→ 与 H5 壳 MainActivity.kt:57-60 的
//     「≥31 要蓝牙双权限，≤30 要精确定位」分流一致。
//
// 编排语义对应 ScaleSync.kt：:87-97 名称前缀过滤（advName 优先，回退
// platformName）；:136-148 订阅全部 NOTIFY/INDICATE；:150-157 写特征
// af000002 前缀否则退化任一可写。

import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:permission_handler/permission_handler.dart';

import 'scale_service.dart';

/// flutter_blue_plus 实现。个人/非商业项目按插件许可枚举选
/// [License.nonprofit]（2.3.13 connect 必填参数，见 LICENSE 条款）。
class BluePlusTransport implements ScaleTransport {
  /// transport 级广播通知流：跨会话复用，close 会话只退订不关流
  final StreamController<List<int>> _notifications =
      StreamController<List<int>>.broadcast();

  final List<StreamSubscription<List<int>>> _charSubs = [];
  BluetoothCharacteristic? _writeChr;
  BluetoothDevice? _device;

  @override
  Stream<List<int>> notifications() => _notifications.stream;

  // ============================ 权限 ============================

  @override
  Future<bool> ensurePermissions() async {
    // 对齐 MainActivity.kt:57-60 分流：API≥31 → 蓝牙扫描+连接；≤30 → 精确定位。
    final bt = await [
      Permission.bluetoothScan,
      Permission.bluetoothConnect,
    ].request();
    if (!bt.values.every((s) => s.isGranted || s.isLimited)) return false;
    // API<31 时上面两项恒 granted（插件源码行为），真机扫描靠定位权限
    final sdk = _androidSdkInt();
    if (sdk != null && sdk <= 30) {
      final loc = await Permission.location.request();
      return loc.isGranted;
    }
    return true;
  }

  /// 从 Platform.operatingSystemVersion（Android 形如 "Android 12 (API 31)"）
  /// 解析 SDK 整型；解析失败返回 null → 按 ≥31 处理（只走蓝牙权限分支）。
  int? _androidSdkInt() {
    if (!Platform.isAndroid) return null;
    final m = RegExp(r'API\s+(\d+)').firstMatch(Platform.operatingSystemVersion);
    return m == null ? null : int.tryParse(m.group(1)!);
  }

  // ============================ 扫描+连接 ============================

  @override
  Future<TransportSession?> scanAndConnect({
    required String namePrefix,
    required Duration timeout,
  }) async {
    // 蓝牙开关检查（ScaleSync.kt:67-75 的三段判断归并为 no-bluetooth）
    final state = await FlutterBluePlus.adapterState.first;
    if (state != BluetoothAdapterState.on) {
      throw const TransportException('no-bluetooth', '蓝牙未开或不支持');
    }

    // 防「startScan already called」：上一轮异常退出可能残留扫描（isScanningNow 有守卫）
    if (FlutterBluePlus.isScanningNow) {
      await FlutterBluePlus.stopScan();
    }

    final found = Completer<BluetoothDevice>();
    final scanSub = FlutterBluePlus.scanResults.listen((results) {
      for (final r in results) {
        // ScaleSync.kt:89-91：广播名优先，回退设备名；startsWith('AFU-')
        final name = r.advertisementData.advName.isNotEmpty
            ? r.advertisementData.advName
            : r.device.platformName;
        if (name.startsWith(namePrefix) && !found.isCompleted) {
          found.complete(r.device);
        }
      }
    });

    BluetoothDevice? device;
    try {
      await FlutterBluePlus.startScan(timeout: timeout);
      device = await found.future
          .timeout(timeout + const Duration(seconds: 1), onTimeout: () {
        throw TimeoutException('scan');
      });
    } on TimeoutException {
      await scanSub.cancel();
      await FlutterBluePlus.stopScan();
      return null; // 编排层 → scan-timeout
    } on TransportException {
      await scanSub.cancel();
      await FlutterBluePlus.stopScan();
      rethrow;
    } catch (e) {
      await scanSub.cancel();
      await FlutterBluePlus.stopScan();
      throw TransportException('connect-fail', '$e');
    }
    await scanSub.cancel();
    await FlutterBluePlus.stopScan(); // ScaleSync.kt:122 扫到即停扫

    try {
      await device.connect(license: License.nonprofit);
      final services = await device.discoverServices();

      // :136-148 订阅全部 NOTIFY/INDICATE 特征
      final notifies = <BluetoothCharacteristic>[
        for (final s in services)
          for (final c in s.characteristics)
            if (c.properties.notify || c.properties.indicate) c,
      ];
      if (notifies.isEmpty) {
        // ScaleSync.kt:143-145 "秤没有通知特征，无法读数"
        throw const TransportException('connect-fail', '无通知特征');
      }

      // :150-157 写特征：af000002 前缀优先，否则退化任一可写
      final all = <BluetoothCharacteristic>[
        for (final s in services) ...s.characteristics,
      ];
      final writeChr = all.where((c) => c.uuid.str.startsWith('af000002')).firstOrNull ??
          all.where((c) => c.properties.write || c.properties.writeWithoutResponse)
              .firstOrNull;
      if (writeChr == null) {
        // Kotlin 无写特征时静默跳过握手（最终吃读超时）；这里显式快速失败
        throw const TransportException('connect-fail', '无可写特征');
      }

      // 先建立订阅再交给编排层握手（Kotlin :147-159 时序）
      for (final c in notifies) {
        await c.setNotifyValue(true);
        _charSubs.add(c.onValueReceived.listen(_notifications.add));
      }
      _writeChr = writeChr;
      _device = device;
      return _BluePlusSession(this);
    } on TransportException {
      await _teardown(device);
      rethrow;
    } catch (e) {
      // :130 连接失败/断开
      await _teardown(device);
      throw TransportException('connect-fail', '$e');
    }
  }

  Future<void> _teardown(BluetoothDevice? device) async {
    for (final s in _charSubs) {
      await s.cancel();
    }
    _charSubs.clear();
    _writeChr = null;
    try {
      if (device != null && device.isConnected) {
        await device.disconnect();
      }
    } catch (_) {
      // 断开失败不再抛：会话已作废
    }
    _device = null;
  }
}

class _BluePlusSession implements TransportSession {
  _BluePlusSession(this._t);
  final BluePlusTransport _t;
  bool _closed = false;

  @override
  Future<void> writeFrame(List<int> frame) async {
    final c = _t._writeChr;
    if (c == null) throw const TransportException('connect-fail', '已断开');
    // ScaleSync.kt:197-199：有 write 属性走有响应写，否则 writeWithoutResponse
    await c.write(frame, withoutResponse: !c.properties.write);
  }

  @override
  Future<void> close() async {
    if (_closed) return; // 幂等
    _closed = true;
    final device = _t._device;
    _t._device = null;
    _t._writeChr = null;
    for (final s in _t._charSubs) {
      await s.cancel();
    }
    _t._charSubs.clear();
    try {
      if (device != null && device.isConnected) {
        await device.disconnect();
      }
    } catch (_) {
      // 幂等 close：断开异常吞掉
    }
  }
}
