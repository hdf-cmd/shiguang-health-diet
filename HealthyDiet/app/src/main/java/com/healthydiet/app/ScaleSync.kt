package com.healthydiet.app

import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.content.Context
import android.os.Handler
import android.os.Looper
import java.util.UUID

/**
 * 蚂蚁阿福体脂秤（沃莱 AFU-WL-TZ-A1）BLE 读取。
 * 协议出自社区逆向（github.com/carl-chang/afu_scale，MIT）：
 * 秤不广播测量数据，必须 GATT 连接后订阅服务 0xFFB0 / 特征 0xFFB2 的通知，
 * 0xAC 报文：体重 = (b3-0x68)*65536 + b4*256 + b5（0.001kg），b6==0x02 为稳定读数。
 */
object ScaleSync {

    private const val DEV_NAME_PREFIX = "AFU-"   // 实测：B1 广播 AFU-BH-TZ-B1，A1 广播 AFU-WL-TZ-A1，按前缀匹配
    private val SERVICE_UUID = UUID.fromString("0000ffb0-0000-1000-8000-00805f9b34fb")
    private val CHAR_UUID = UUID.fromString("0000ffb2-0000-1000-8000-00805f9b34fb")
    private val CCCD_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    private const val SCAN_TIMEOUT_MS = 30_000L
    private const val READ_TIMEOUT_MS = 75_000L

    fun interface OnWeight { fun on(kg: Double, stable: Boolean) }
    fun interface OnStatus { fun on(message: String) }

    private val main = Handler(Looper.getMainLooper())
    private var gatt: BluetoothGatt? = null
    private var scanRef: ScanCallback? = null
    private var adapterRef: BluetoothAdapter? = null
    private var appCtx: Context? = null
    private var onWeight: OnWeight? = null
    private var onStatus: OnStatus? = null
    private var active = false
    private var probeOnLine: ((String) -> Unit)? = null
    private val probeSeen = LinkedHashMap<String, Int>()
    private var probeTotal = 0
    private var scanDeadline: Runnable? = null
    private var readDeadline: Runnable? = null
    private var lastKg = -1.0

    val isBusy: Boolean get() = active

    /** 诊断模式：不限名称扫 N 秒，把发现的所有 BLE 设备（名称·MAC·信号）回传，用于排查"找不到秤" */
    @SuppressLint("MissingPermission")
    fun debugScan(ctx: Context, seconds: Int, status: OnStatus, onList: (String) -> Unit): Boolean {
        stop()
        val mgr = ctx.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val adapter = mgr?.adapter ?: run { main.post { status.on("此设备不支持蓝牙") }; return false }
        if (!adapter.isEnabled) { main.post { status.on("请先打开手机蓝牙") }; return false }
        val scanner = adapter.bluetoothLeScanner ?: run { main.post { status.on("此设备不支持蓝牙低功耗") }; return false }
        adapterRef = adapter
        appCtx = ctx.applicationContext
        onStatus = status
        active = true
        val seen = LinkedHashMap<String, String>()
        scanRef = object : ScanCallback() {
            override fun onScanResult(type: Int, result: ScanResult) {
                val addr = result.device.address
                if (!seen.containsKey(addr)) {
                    val name = runCatching { result.scanRecord?.deviceName ?: result.device.name }.getOrNull() ?: "(无名称)"
                    seen[addr] = "$name · $addr · ${result.rssi}dBm"
                    android.util.Log.d("SGScale", "debugScan found: ${seen[addr]}")
                }
            }
            override fun onScanFailed(errorCode: Int) {
                main.post { status.on("扫描失败 errorCode=$errorCode（检查蓝牙/附近设备权限）") }
                stop()
            }
        }
        scanner.startScan(scanRef)
        main.post { status.on("诊断扫描 ${seconds}s：请光脚站上秤并保持") }
        main.postDelayed({
            val lines = if (seen.isEmpty()) "没扫到任何蓝牙设备：多半是权限没给到或蓝牙未开"
                else seen.values.sorted().joinToString("\n")
            stop()
            main.post { onList(lines) }
        }, seconds * 1000L)
        return true
    }

    /** 返回 false 表示当场失败（无蓝牙/未开），true 表示已发起、结果走回调 */
    @SuppressLint("MissingPermission")
    fun start(ctx: Context, weight: OnWeight, status: OnStatus): Boolean {
        stop()
        val mgr = ctx.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val adapter = mgr?.adapter ?: run {
            main.post { status.on("此设备不支持蓝牙") }; return false
        }
        if (!adapter.isEnabled) {
            main.post { status.on("请先打开手机蓝牙") }; return false
        }
        val scanner = adapter.bluetoothLeScanner ?: run {
            main.post { status.on("此设备不支持蓝牙低功耗") }; return false
        }
        adapterRef = adapter
        appCtx = ctx.applicationContext
        onWeight = weight
        onStatus = status
        active = true
        lastKg = -1.0
        readDeadline = runnable { finish("读取超时：请站上秤后重新点同步") }
        main.postDelayed(readDeadline!!, READ_TIMEOUT_MS)
        scanDeadline = runnable { if (gatt == null) finish("30 秒没找到秤：请光脚站上秤再点一次") }
        main.postDelayed(scanDeadline!!, SCAN_TIMEOUT_MS)
        scanRef = object : ScanCallback() {
            override fun onScanResult(type: Int, result: ScanResult) {
                val name = runCatching { result.scanRecord?.deviceName ?: result.device.name }.getOrNull()
                android.util.Log.d("SGScale", "scan seen: name=$name addr=${result.device.address} rssi=${result.rssi}")
                if (name != null && name.startsWith(DEV_NAME_PREFIX)) connect(result.device)
            }
            override fun onScanFailed(errorCode: Int) {
                finish("蓝牙扫描失败（$errorCode），重启蓝牙后再试")
            }
        }
        scanner.startScan(scanRef)
        main.post { status.on("正在寻找体脂秤…（请光脚站上秤）") }
        return true
    }

    @SuppressLint("MissingPermission")
    fun stop() {
        active = false
        probeOnLine = null
        scanDeadline?.let { main.removeCallbacks(it) }
        readDeadline?.let { main.removeCallbacks(it) }
        scanDeadline = null
        readDeadline = null
        scanRef?.let { cb -> adapterRef?.bluetoothLeScanner?.stopScan(cb) }
        scanRef = null
        gatt?.close()
        gatt = null
        onWeight = null
        onStatus = null
    }

    @SuppressLint("MissingPermission")
    private fun connect(device: BluetoothDevice) {
        if (gatt != null || !active) return
        scanRef?.let { adapterRef?.bluetoothLeScanner?.stopScan(it) }
        scanRef = null
        scanDeadline?.let { main.removeCallbacks(it) }
        gatt = device.connectGatt(appCtx ?: return, false, object : BluetoothGattCallback() {
            override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
                if (!active) return
                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> g.discoverServices()
                    BluetoothProfile.STATE_DISCONNECTED -> finish("与秤的连接断开，请重试")
                }
            }

            override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
                if (!active) return
                val ch = g.getService(SERVICE_UUID)?.getCharacteristic(CHAR_UUID)
                if (ch == null) {
                    finish("秤服务不可用：可能正被阿福 App 占用，请先断开它")
                    return
                }
                g.setCharacteristicNotification(ch, true)
                ch.getDescriptor(CCCD_UUID)?.let { d ->
                    @Suppress("DEPRECATION")
                    d.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    @Suppress("DEPRECATION")
                    g.writeDescriptor(d)
                }
            }

            override fun onDescriptorWrite(g: BluetoothGatt, d: BluetoothGattDescriptor, status: Int) {
                if (active) status0Connected()
            }

            override fun onCharacteristicChanged(g: BluetoothGatt, ch: BluetoothGattCharacteristic) {
                if (ch.uuid == CHAR_UUID) parse(ch.value)
            }
        })
    }

    private fun status0Connected() {
        onStatus?.on("已连接体脂秤，请光脚站稳等待稳定")
    }

    /** 连接探测：连上 AFU- 设备后订阅全部可通知特征，逐行回显原始报文（排查 B1 协议差异） */
    @SuppressLint("MissingPermission")
    fun debugConnect(ctx: Context, seconds: Int, status: OnStatus, onLine: (String) -> Unit): Boolean {
        stop()
        val mgr = ctx.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager
        val adapter = mgr?.adapter ?: run { main.post { status.on("此设备不支持蓝牙") }; return false }
        if (!adapter.isEnabled) { main.post { status.on("请先打开手机蓝牙") }; return false }
        val scanner = adapter.bluetoothLeScanner ?: run { main.post { status.on("此设备不支持蓝牙低功耗") }; return false }
        adapterRef = adapter
        appCtx = ctx.applicationContext
        onStatus = status
        probeSeen.clear()
        probeTotal = 0
        probeOnLine = onLine
        active = true
        scanRef = object : ScanCallback() {
            override fun onScanResult(type: Int, result: ScanResult) {
                val name = runCatching { result.scanRecord?.deviceName ?: result.device.name }.getOrNull()
                if (name != null && name.startsWith(DEV_NAME_PREFIX)) probeConnectDevice(result.device, name)
            }
        }
        scanner.startScan(scanRef)
        main.post { status.on("探测中：请光脚站上秤保持 ${seconds}s") }
        scanDeadline = runnable { if (gatt == null) { probeLine("15 秒内没扫到 AFU- 设备"); stop() } }
        main.postDelayed(scanDeadline!!, 15_000L)
        readDeadline = runnable {
            probeLine("探测结束：共 ${probeTotal} 条通知 / ${probeSeen.size} 种内容")
            stop()
        }
        main.postDelayed(readDeadline!!, seconds * 1000L)
        return true
    }

    @SuppressLint("MissingPermission")
    private fun probeConnectDevice(device: BluetoothDevice, name: String) {
        if (gatt != null || !active) return
        scanRef?.let { adapterRef?.bluetoothLeScanner?.stopScan(it) }
        scanRef = null
        scanDeadline?.let { main.removeCallbacks(it) }
        probeLine("扫到 $name，连接中…")
        gatt = device.connectGatt(appCtx ?: return, false, object : BluetoothGattCallback() {
            override fun onConnectionStateChange(g: BluetoothGatt, status: Int, newState: Int) {
                when (newState) {
                    BluetoothProfile.STATE_CONNECTED -> { probeLine("已连接，发现服务…"); g.discoverServices() }
                    BluetoothProfile.STATE_DISCONNECTED -> probeLine("连接断开 status=$status")
                }
            }

            override fun onServicesDiscovered(g: BluetoothGatt, status: Int) {
                val subs = g.services.flatMap { s ->
                    s.characteristics.filter { ch ->
                        ch.properties.let { p ->
                            (p and BluetoothGattCharacteristic.PROPERTY_NOTIFY) != 0 ||
                            (p and BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0
                        }
                    }.map { s to it }
                }
                probeLine("可通知特征 ${subs.size} 个，逐个订阅")
                subs.forEachIndexed { i, (svc, ch) ->
                    main.postDelayed({ subscribe(g, svc.uuid.toString(), ch) }, 250L * (i + 1))
                }
            }

            override fun onCharacteristicChanged(g: BluetoothGatt, ch: BluetoothGattCharacteristic) {
                val b = ch.value ?: return
                val hex = b.joinToString(" ") { String.format("%02X", it) }
                probeLineOnce("数据 ${ch.uuid}: $hex")
                if (b.size >= 7 && (b[0].toInt() and 0xFF) == 0xAC) {
                    val raw = (((b[3].toInt() and 0xFF) - 0x68) shl 16) or
                        ((b[4].toInt() and 0xFF) shl 8) or (b[5].toInt() and 0xFF)
                    probeLineOnce("→ 0xAC 协议命中：体重 ${Math.round(raw / 10.0) / 100.0}kg 稳定=${(b[6].toInt() and 0xFF) == 0x02}")
                }
            }
        })
    }

    @SuppressLint("MissingPermission")
    private fun subscribe(g: BluetoothGatt, svcUuid: String, ch: BluetoothGattCharacteristic) {
        if (!active) return
        g.setCharacteristicNotification(ch, true)
        ch.getDescriptor(CCCD_UUID)?.let { d ->
            @Suppress("DEPRECATION")
            d.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            @Suppress("DEPRECATION")
            g.writeDescriptor(d)
        }
        probeLineOnce("已订阅 $svcUuid/${ch.uuid}")
    }

    private fun probeLine(text: String) {
        android.util.Log.d("SGScale", "probe: $text")
        val cb = probeOnLine
        main.post { cb?.invoke(text) }
    }

    /** 去重回显：内容完全相同的行只发第一次（附计数在结尾汇总），避免秤高频推送刷屏 */
    private fun probeLineOnce(text: String) {
        val n = (probeSeen[text] ?: 0) + 1
        probeSeen[text] = n
        probeTotal++
        if (n == 1) probeLine(text)
    }

    private fun parse(b: ByteArray?) {
        if (b == null || b.size < 7 || (b[0].toInt() and 0xFF) != 0xAC) return
        val raw = (((b[3].toInt() and 0xFF) - 0x68) shl 16) or
            ((b[4].toInt() and 0xFF) shl 8) or
            (b[5].toInt() and 0xFF)
        val kg = Math.round(raw / 10.0) / 100.0   // 0.001kg → 0.01kg 精度
        val stable = (b[6].toInt() and 0xFF) == 0x02
        if (kg !in 2.0..300.0) return
        if (stable) {
            main.post { onWeight?.on(kg, true) }
            finish("ok")
        } else if (kg != lastKg) {
            lastKg = kg
            main.post { onWeight?.on(kg, false) }
        }
    }

    private fun finish(message: String) {
        if (!active) return
        main.post { if (message != "ok") onStatus?.on(message) }
        stop()
    }

    private fun runnable(block: () -> Unit) = Runnable { main.post(block) }
}
