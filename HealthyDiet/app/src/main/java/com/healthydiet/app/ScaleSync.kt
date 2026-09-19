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
 * 蚂蚁阿福体脂秤 B1（AFU-BH-TZ-B1）BLE 读取。
 * 协议为 20 字节定长帧：AF 45 [子命令@2] [体@3..17] [线型@18] [校验@19]，
 * 校验 = sum(raw[2..18]) & 0x1F；线型 0x51=实时体重、0x54=存档记录，
 * 体重克数在 (字节反转(u32)) & 0x3FFFF，bit31=秤判定"最终值"。
 * 协议格式参考 openScale 的逆向文档（AfuB1Lib，GPL-3，仅协议事实），本实现为自写最小集。
 * 二期取数流程：0x51 locked → ACK → 等用户下秤（帧静默 2s）→ 重同步 + 取回档案
 * （profile 0x4b/0x5b + chunk 请求）→ 新鲜 0x54 带阻抗 le16@13；15s 拿不到则回退纯体重。
 */
object ScaleSync {

    private const val DEV_NAME_PREFIX = "AFU-"   // 实测：B1 广播 AFU-BH-TZ-B1，A1 广播 AFU-WL-TZ-A1
    private const val FRAME = 20
    private const val W_LIVE = 0x51
    private const val W_STORED = 0x54
    private const val W_CONTROL = 0x5F
    private const val W_SYNC = 0x62
    private val CCCD_UUID = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
    private const val SCAN_TIMEOUT_MS = 30_000L
    private const val READ_TIMEOUT_MS = 90_000L

    fun interface OnWeight {
        /** impedance 为 -1 表示本次没拿到阻抗（回退纯体重），kg>0 且 stable=true 即最终结果 */
        fun on(kg: Double, stable: Boolean, impedance: Double)
    }
    fun interface OnStatus { fun on(message: String) }

    /** 用户档案帧的四种用途（子命令 + 捕获自官方 App 的 af 开放字节对） */
    private enum class ProfileVariant(val cmd: Int, val open: Int) {
        INITIAL(0x3F, 0xB6), GWA1(0x4B, 0xB6), GWA2(0x5B, 0xD9)
    }

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
    @Volatile private var writeCh: BluetoothGattCharacteristic? = null
    // —— 二期 commit 流程会话状态（GATT 回调线程写、main 读，全部 @Volatile）——
    @Volatile private var userAge = 30
    @Volatile private var userSex = 1          // AFU 约定 1=男 0=女
    @Volatile private var userTargetKg = 60f
    @Volatile private var lastFrameAt = 0L
    @Volatile private var initialSent = false
    @Volatile private var finalKg = -1.0
    @Volatile private var weighStartedAt = 0L
    @Volatile private var commitSent = false
    @Volatile private var commitSentAt = 0L

    val isBusy: Boolean get() = active

    // ============================ 同步（取体重） ============================

    /** 返回 false 表示当场失败（无蓝牙/未开），true 表示已发起、结果走回调 */
    @SuppressLint("MissingPermission")
    fun start(ctx: Context, age: Int, sexMale: Boolean, targetKg: Float, weight: OnWeight, status: OnStatus): Boolean {
        stop()
        val adapter = obtainAdapter(ctx) ?: run {
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
        userAge = age
        userSex = if (sexMale) 1 else 0
        userTargetKg = targetKg
        active = true
        lastKg = -1.0
        lastFrameAt = 0L
        initialSent = false
        finalKg = -1.0
        weighStartedAt = 0L
        commitSent = false
        readDeadline = runnable { finish("读取超时：请站上秤后重新点同步") }
        main.postDelayed(readDeadline!!, READ_TIMEOUT_MS)
        scanDeadline = runnable { if (gatt == null) finish("30 秒没找到秤：请光脚站上秤再点一次") }
        main.postDelayed(scanDeadline!!, SCAN_TIMEOUT_MS)
        scanRef = object : ScanCallback() {
            override fun onScanResult(type: Int, result: ScanResult) {
                val name = runCatching { result.scanRecord?.deviceName ?: result.device.name }.getOrNull()
                android.util.Log.d("SGScale", "scan seen: name=$name addr=${result.device.address}")
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
        writeCh = null
        initialSent = false
        finalKg = -1.0
        commitSent = false
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
                val notifies = g.services.flatMap { s ->
                    s.characteristics.filter { ch ->
                        val p = ch.properties
                        (p and BluetoothGattCharacteristic.PROPERTY_NOTIFY) != 0 ||
                            (p and BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0
                    }
                }
                if (notifies.isEmpty()) {
                    finish("秤没有通知特征，无法读数")
                    return
                }
                notifies.forEachIndexed { i, ch ->
                    main.postDelayed({ subscribeNotify(g, ch) }, 200L * (i + 1))
                }
                val wc = g.services
                    .flatMap { it.characteristics }
                    .firstOrNull { it.uuid.toString().startsWith("af000002") }
                    ?: g.services.flatMap { c -> c.characteristics }.firstOrNull { ch ->
                        val p = ch.properties
                        (p and BluetoothGattCharacteristic.PROPERTY_WRITE_NO_RESPONSE) != 0 ||
                            (p and BluetoothGattCharacteristic.PROPERTY_WRITE) != 0
                    }
                writeCh = wc
                if (wc != null) {
                    main.postDelayed({ handshake(g, wc) }, 200L * (notifies.size + 2))
                }
            }

            override fun onDescriptorWrite(g: BluetoothGatt, d: BluetoothGattDescriptor, st: Int) {
                if (active) onStatus?.on("已连接体脂秤，请光脚站稳等待稳定")
            }

            override fun onCharacteristicChanged(g: BluetoothGatt, ch: BluetoothGattCharacteristic) {
                parse(ch.value)
            }
        })
    }

    @SuppressLint("MissingPermission")
    private fun subscribeNotify(g: BluetoothGatt, ch: BluetoothGattCharacteristic) {
        if (!active) return
        g.setCharacteristicNotification(ch, true)
        ch.getDescriptor(CCCD_UUID)?.let { d ->
            @Suppress("DEPRECATION")
            d.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            @Suppress("DEPRECATION")
            g.writeDescriptor(d)
        }
    }

    /** 握手：校时 + 两次同步请求，让秤进入正常上报节奏（对齐官方 App 会话开头） */
    @SuppressLint("MissingPermission")
    private fun handshake(g: BluetoothGatt, wc: BluetoothGattCharacteristic) {
        if (!active) return
        val now = System.currentTimeMillis() / 1000L
        writeFrame(g, wc, buildFrame(0x16, W_CONTROL, time4(now) + byteArrayOf(0x20) + ByteArray(10)))
        writeFrame(g, wc, buildFrame(0x04, W_SYNC, SYNC_BODY_1))
        writeFrame(g, wc, buildFrame(0x04, W_SYNC, SYNC_BODY_2))
    }

    @SuppressLint("MissingPermission")
    private fun writeFrame(g: BluetoothGatt, wc: BluetoothGattCharacteristic, data: ByteArray) {
        val writeType = if ((wc.properties and BluetoothGattCharacteristic.PROPERTY_WRITE) != 0)
            BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
        else BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
        if (android.os.Build.VERSION.SDK_INT >= 33) {
            g.writeCharacteristic(wc, data, writeType)
        } else {
            @Suppress("DEPRECATION")
            wc.writeType = writeType
            @Suppress("DEPRECATION")
            wc.value = data
            @Suppress("DEPRECATION")
            g.writeCharacteristic(wc)
        }
    }

    private fun parse(b: ByteArray?) {
        if (b == null || b.size != FRAME) return
        if ((b[0].toInt() and 0xFF) != 0xAF || (b[1].toInt() and 0xFF) != 0x45) return
        if (crc(b) != (b[19].toInt() and 0x1F)) return
        lastFrameAt = System.currentTimeMillis()
        when (b[18].toInt() and 0xFF) {
            W_LIVE -> {
                val flags = swap32(be32(b, 2))
                val g = flags and WEIGHT_MASK
                if (weighStartedAt == 0L && g > 2000) weighStartedAt = lastFrameAt / 1000L
                // 秤进入称重后下发一次用户档案（官方 App 同序；测体脂需要它）
                if (!initialSent && g > 2000) {
                    initialSent = true
                    sendProfile(ProfileVariant.INITIAL)
                }
                emitLive(g / 1000.0, bit(flags, 31))
            }
            // 0x54 连接即推的多为旧存档（实测 13.05kg 且时钟不准）——只有 commit 之后、
            // 时间戳新鲜且与最终体重吻合的那条才算数，从中取阻抗 le16@13
            W_STORED -> {
                if (!commitSent || finalKg <= 0) return
                val flags = swap32(be32(b, 7))
                val g = flags and WEIGHT_MASK
                val kg = g / 1000.0
                val ts = le32(b, 3)
                val now = System.currentTimeMillis() / 1000L
                if (kg !in 2.0..300.0) return
                if (ts < weighStartedAt - 60L || kotlin.math.abs(now - ts) > 900L) return
                if (kotlin.math.abs(g - finalKg * 1000) > 1000) return
                sendAck(W_STORED, (b[2].toInt() and 0xFF) ushr 2 and 0x3F)
                publish(kg, le16(b, 13).toDouble())
            }
            else -> {}
        }
    }

    private fun emitLive(rawKg: Double, locked: Boolean) {
        if (!active) return
        val kg = Math.round(rawKg * 100.0) / 100.0
        if (kg !in 2.0..300.0) return
        if (locked) {
            if (finalKg > 0) return
            finalKg = kg
            sendAck(W_LIVE, 0)
            main.post { onStatus?.on("测量完成，请下秤，正在取回记录…") }
            startCommitPoll()
        } else if (kg != lastKg) {
            lastKg = kg
            main.post { onWeight?.on(kg, false, -1.0) }
        }
    }

    /** 等秤空闲（用户下秤、帧静默 2s）后发重同步 + 取回档案；发出后 15s 内等新鲜 0x54 */
    private fun startCommitPoll() {
        var waited = 0L
        val poll = object : Runnable {
            override fun run() {
                if (!active) return
                val now = System.currentTimeMillis()
                if (!commitSent) {
                    if (now - lastFrameAt > 2000L) {
                        commitSent = true
                        commitSentAt = now
                        sendCommitFrames()
                    }
                } else if (now - commitSentAt > 15_000L) {
                    publish(finalKg, -1.0)   // 取回档案超时：回退发布实时最终值（无阻抗）
                    return
                }
                waited += 250
                if (waited < 60_000L) main.postDelayed(this, 250L)
                else publish(finalKg, -1.0)
            }
        }
        main.postDelayed(poll, 500L)
    }

    private fun sendCommitFrames() {
        val wc = writeCh ?: run { publish(finalKg, -1.0); return }
        val g = gatt ?: run { publish(finalKg, -1.0); return }
        val now = System.currentTimeMillis() / 1000L
        writeFrame(g, wc, buildFrame(0x16, W_CONTROL, time4(now) + byteArrayOf(0x20) + ByteArray(10)))
        writeFrame(g, wc, buildFrame(0x04, W_SYNC, SYNC_BODY_1))
        writeFrame(g, wc, buildFrame(0x04, W_SYNC, SYNC_BODY_2))
        sendProfile(ProfileVariant.GWA1)
        sendProfile(ProfileVariant.GWA2)
        writeFrame(g, wc, buildFrame(0x14, W_CONTROL, ByteArray(15)))   // chunk 请求 → 秤推新鲜 0x54
    }

    private fun sendProfile(v: ProfileVariant) {
        val wc = writeCh ?: return
        val g = gatt ?: return
        val targetX100 = Math.round(userTargetKg * 100f) and 0xFFFF
        val body = time4(System.currentTimeMillis() / 1000L) + byteArrayOf(
            0, 1,
            0xAF.toByte(), v.open.toByte(), 0x17,
            (userAge and 0xFF).toByte(), (userSex and 0xFF).toByte(),
            (targetX100 and 0xFF).toByte(), ((targetX100 ushr 8) and 0xFF).toByte(),
            0x03, 0x00
        )
        writeFrame(g, wc, buildFrame(v.cmd, 0x61, body))
    }

    private fun sendAck(replyWire: Int, correlation: Int) {
        val wc = writeCh ?: return
        val g = gatt ?: return
        writeFrame(g, wc, buildFrame(0x12, W_CONTROL,
            byteArrayOf(replyWire.toByte(), 0, (correlation and 0xFF).toByte()) + ByteArray(12)))
    }

    private fun publish(kg: Double, impedance: Double) {
        if (!active) return
        val v = Math.round(kg * 100.0) / 100.0
        main.post { onWeight?.on(v, true, impedance) }
        finish("ok")
    }

    private fun finish(message: String) {
        if (!active) return
        main.post { if (message != "ok") onStatus?.on(message) }
        stop()
    }

    // ============================ 帧编解码工具 ============================

    private const val WEIGHT_MASK = 0x3FFFF

    private val SYNC_BODY_1 = byteArrayOf(
        0, 1, 0xAF.toByte(), 0xB6.toByte(), 0x17, 0x1D, 1,
        0, 2, 0xB4.toByte(), 0xC6.toByte(), 0x1B, 0x56, 1, 0
    )
    private val SYNC_BODY_2 = byteArrayOf(
        1, 3, 0xA5.toByte(), 0xF8.toByte(), 0x11, 0x1D, 2,
        0, 4, 0xB4.toByte(), 0xC6.toByte(), 0x1B, 0x1D, 1, 0
    )

    private fun buildFrame(cmd: Int, wireType: Int, body: ByteArray): ByteArray {
        val f = ByteArray(FRAME)
        f[0] = 0xAF.toByte(); f[1] = 0x45.toByte()
        f[2] = (cmd and 0xFF).toByte()
        body.copyInto(f, 3)
        f[18] = (wireType and 0xFF).toByte()
        f[19] = crc(f).toByte()
        return f
    }

    private fun time4(epochSeconds: Long): ByteArray {
        val v = swap32((epochSeconds and 0xFFFFFFFFL).toInt())
        return byteArrayOf(
            ((v ushr 24) and 0xFF).toByte(), ((v ushr 16) and 0xFF).toByte(),
            ((v ushr 8) and 0xFF).toByte(), (v and 0xFF).toByte()
        )
    }

    private fun crc(f: ByteArray): Int {
        var sum = 0
        for (i in 2..18) sum += f[i].toInt() and 0xFF
        return sum and 0x1F
    }

    private fun be32(b: ByteArray, off: Int): Int =
        ((b[off].toInt() and 0xFF) shl 24) or ((b[off + 1].toInt() and 0xFF) shl 16) or
            ((b[off + 2].toInt() and 0xFF) shl 8) or (b[off + 3].toInt() and 0xFF)

    private fun le16(b: ByteArray, off: Int): Int =
        (b[off].toInt() and 0xFF) or ((b[off + 1].toInt() and 0xFF) shl 8)

    private fun le32(b: ByteArray, off: Int): Long =
        (le16(b, off).toLong()) or ((b[off + 2].toLong() and 0xFF) shl 16) or ((b[off + 3].toLong() and 0xFF) shl 24)

    private fun swap32(v: Int): Int =
        ((v and 0xFF) shl 24) or ((v and 0xFF00) shl 8) or
            ((v ushr 8) and 0xFF00) or ((v ushr 24) and 0xFF)

    private fun bit(v: Int, n: Int): Boolean = ((v ushr n) and 1) == 1

    private fun runnable(block: () -> Unit) = Runnable { main.post(block) }

    private fun obtainAdapter(ctx: Context): BluetoothAdapter? =
        (ctx.getSystemService(Context.BLUETOOTH_SERVICE) as? BluetoothManager)?.adapter

    // ============================ 诊断（扫描/探测） ============================

    /** 诊断模式：不限名称扫 N 秒，把发现的所有 BLE 设备（名称·MAC·信号）回传 */
    @SuppressLint("MissingPermission")
    fun debugScan(ctx: Context, seconds: Int, status: OnStatus, onList: (String) -> Unit): Boolean {
        stop()
        val adapter = obtainAdapter(ctx) ?: run { main.post { status.on("此设备不支持蓝牙") }; return false }
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

    /** 连接探测：连上 AFU- 设备后订阅全部可通知特征，逐行回显原始报文 */
    @SuppressLint("MissingPermission")
    fun debugConnect(ctx: Context, seconds: Int, status: OnStatus, onLine: (String) -> Unit): Boolean {
        stop()
        val adapter = obtainAdapter(ctx) ?: run { main.post { status.on("此设备不支持蓝牙") }; return false }
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
                probeLine("服务发现 status=$status，共 ${g.services.size} 个服务")
                g.services.forEach { s ->
                    s.characteristics.forEach { ch ->
                        probeLineOnce("服务 ${s.uuid} · 特征 ${ch.uuid} · 属性 ${ch.properties}")
                    }
                }
                val subs = g.services.flatMap { s ->
                    s.characteristics.filter { ch ->
                        val p = ch.properties
                        (p and BluetoothGattCharacteristic.PROPERTY_NOTIFY) != 0 ||
                            (p and BluetoothGattCharacteristic.PROPERTY_INDICATE) != 0
                    }
                }
                probeLine("可通知特征 ${subs.size} 个，逐个订阅")
                subs.forEachIndexed { i, ch ->
                    main.postDelayed({ probeSubscribe(g, ch) }, 250L * (i + 1))
                }
            }

            override fun onCharacteristicChanged(g: BluetoothGatt, ch: BluetoothGattCharacteristic) {
                val b = ch.value ?: return
                val hex = b.joinToString(" ") { String.format("%02X", it) }
                probeLineOnce("数据 ${ch.uuid}: $hex")
                if (b.size == FRAME && (b[0].toInt() and 0xFF) == 0xAF && (b[1].toInt() and 0xFF) == 0x45 &&
                    crc(b) == (b[19].toInt() and 0x1F) && (b[18].toInt() and 0xFF) == W_LIVE
                ) {
                    val flags = swap32(be32(b, 2))
                    probeLineOnce("→ B1 实时体重：${(flags and WEIGHT_MASK) / 1000.0}kg 最终=${bit(flags, 31)}")
                }
            }
        })
    }

    @SuppressLint("MissingPermission")
    private fun probeSubscribe(g: BluetoothGatt, ch: BluetoothGattCharacteristic) {
        if (!active) return
        g.setCharacteristicNotification(ch, true)
        ch.getDescriptor(CCCD_UUID)?.let { d ->
            @Suppress("DEPRECATION")
            d.value = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
            @Suppress("DEPRECATION")
            g.writeDescriptor(d)
        }
        probeLineOnce("已订阅 ${ch.uuid}")
    }

    private fun probeLine(text: String) {
        android.util.Log.d("SGScale", "probe: $text")
        val cb = probeOnLine
        main.post { cb?.invoke(text) }
    }

    /** 去重回显：内容完全相同的行只发第一次，结尾汇总条数 */
    private fun probeLineOnce(text: String) {
        val n = (probeSeen[text] ?: 0) + 1
        probeSeen[text] = n
        probeTotal++
        if (n == 1) probeLine(text)
    }
}
