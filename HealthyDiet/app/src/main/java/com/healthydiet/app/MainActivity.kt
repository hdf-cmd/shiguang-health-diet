package com.healthydiet.app

import android.annotation.SuppressLint
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.view.KeyEvent
import android.webkit.ValueCallback
import android.webkit.WebChromeClient
import android.webkit.WebSettings
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.ComponentActivity
import androidx.activity.result.contract.ActivityResultContracts
import androidx.core.view.WindowCompat

/**
 * 食光 · WebView 壳。
 * 界面与逻辑在前端（assets/web，经内嵌本地服务加载），数据走 CloudBase 云函数，
 * 登录态存于 WebView localStorage。
 */
class MainActivity : ComponentActivity() {

    private lateinit var webView: WebView
    private var server: AssetServer? = null
    private var filePathCallback: ValueCallback<Array<Uri>>? = null
    /* 通知卡片点进来的落点；页面加载完成后再交给前端执行 */
    private var pendingGoto: String? = null

    private val pickImage = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val callback = filePathCallback ?: return@registerForActivityResult
        filePathCallback = null
        if (result.resultCode == RESULT_OK && result.data != null) {
            val clip = result.data?.clipData
            val uris = if (clip != null && clip.itemCount > 0) {
                Array(clip.itemCount) { i -> clip.getItemAt(i).uri }
            } else {
                result.data?.data?.let { arrayOf(it) } ?: emptyArray()
            }
            callback.onReceiveValue(uris)
        } else {
            callback.onReceiveValue(null)
        }
    }

    private val reqNotifyPerm = registerForActivityResult(ActivityResultContracts.RequestPermission()) { /* 结果不阻断：未授权时通知静默跳过 */ }

    private val reqScalePerms = registerForActivityResult(ActivityResultContracts.RequestMultiplePermissions()) { grants ->
        if (grants.values.all { it }) startScaleSync()
        else jsScaleStatus("需要蓝牙权限才能读取体脂秤，请在设置中允许后重试")
    }

    /** JS 桥 SGNative.startScale 的实际执行体（须在主线程调用） */
    fun requestScale() {
        val need = if (Build.VERSION.SDK_INT >= 31)
            arrayOf(android.Manifest.permission.BLUETOOTH_SCAN, android.Manifest.permission.BLUETOOTH_CONNECT)
        else
            arrayOf(android.Manifest.permission.ACCESS_FINE_LOCATION)
        val missing = need.filter { checkSelfPermission(it) != PackageManager.PERMISSION_GRANTED }
        if (missing.isNotEmpty()) reqScalePerms.launch(missing.toTypedArray())
        else startScaleSync()
    }

    private fun startScaleSync() {
        ScaleSync.start(this,
            { kg, stable -> webView.evaluateJavascript("window.SG_onScaleWeight&&SG_onScaleWeight($kg,${if (stable) "true" else "false"})", null) },
            { msg -> jsScaleStatus(msg) })
    }

    /** 诊断扫描：列出 12 秒内所有 BLE 设备到前端（排查"找不到秤"） */
    fun debugScaleScan() {
        ScaleSync.debugScan(this, 12,
            { msg -> jsScaleStatus(msg) },
            { text ->
                val quoted = org.json.JSONObject.quote(text)
                webView.evaluateJavascript("window.SG_onScaleDebug&&SG_onScaleDebug($quoted)", null)
            })
    }

    private fun jsScaleStatus(msg: String) {
        val quoted = org.json.JSONObject.quote(msg)
        webView.evaluateJavascript("window.SG_onScaleStatus&&SG_onScaleStatus($quoted)", null)
    }

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android 15+ 强制 edge-to-edge 会让 WebView 内容顶进状态栏；显式 fit 系统窗口避免重叠
        WindowCompat.setDecorFitsSystemWindows(window, true)
        pendingGoto = intent.getStringExtra(EXTRA_GOTO)
        Notify.ensureChannel(this)
        // 已开启提醒时补排喝水随机闹钟（跨天/漏排自愈）
        if (Reminders.enabled(this)) Reminders.ensureWaterSchedule(this)
        // Android 13+ 发通知需运行时权限：首次进入申请一次
        if (Build.VERSION.SDK_INT >= 33 &&
            checkSelfPermission(android.Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
            reqNotifyPerm.launch(android.Manifest.permission.POST_NOTIFICATIONS)
        }
        server = try {
            AssetServer(this, PORT).also { it.start(SO_TIMEOUT, false) }
        } catch (e: Exception) {
            null
        }
        webView = WebView(this)
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            cacheMode = WebSettings.LOAD_DEFAULT
            useWideViewPort = true
            loadWithOverviewMode = true
        }
        webView.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView?, url: String?) {
                // 页面（含 ES module）执行完才能调前端函数，故在此转交点击落点
                pendingGoto?.let { goto ->
                    pendingGoto = null
                    gotoSection(goto)
                }
            }
        }
        // JS 桥接：window.SGNative（系统通知提醒开关/测试）
        webView.addJavascriptInterface(NativeBridge(this), "SGNative")
        // 支持 <input type=file> 选图（自定义头像上传）
        webView.webChromeClient = object : WebChromeClient() {
            override fun onShowFileChooser(
                webView: WebView,
                filePathCallback: ValueCallback<Array<Uri>>?,
                fileChooserParams: FileChooserParams?
            ): Boolean {
                this@MainActivity.filePathCallback?.onReceiveValue(null)
                this@MainActivity.filePathCallback = filePathCallback
                val intent = Intent(Intent.ACTION_GET_CONTENT).apply {
                    addCategory(Intent.CATEGORY_OPENABLE)
                    type = "image/*"
                    putExtra(Intent.EXTRA_ALLOW_MULTIPLE, false)
                }
                pickImage.launch(intent)
                return true
            }
        }
        if (BuildConfig.DEBUG) WebView.setWebContentsDebuggingEnabled(true)
        setContentView(webView)
        // 清缓存避免旧版前端残留；带版本参数做缓存失效
        webView.clearCache(true)
        webView.loadUrl("http://127.0.0.1:$PORT/index.html?v=${System.currentTimeMillis()}")
    }

    /** App 已打开时再点通知卡片：singleTask 走这里，不重新加载页面、不丢当前状态 */
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        intent.getStringExtra(EXTRA_GOTO)?.let { gotoSection(it) }
    }

    private fun gotoSection(target: String) {
        if (target != GOTO_WATER) return
        webView.evaluateJavascript("window.SG_GOTO_WATER && window.SG_GOTO_WATER()", null)
    }

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        // 返回键回退网页历史，而不是直接退出
        if (keyCode == KeyEvent.KEYCODE_BACK && webView.canGoBack()) {
            webView.goBack()
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onDestroy() {
        ScaleSync.stop()
        server?.stop()
        webView.destroy()
        super.onDestroy()
    }

    companion object {
        /** 与网关安全域名白名单对应的本地端口 */
        const val PORT = 8765
        private const val SO_TIMEOUT = 5000
        /** 通知 → 页内落点，如 water（喝水区块） */
        const val EXTRA_GOTO = "goto"
        /** 喝水卡的独立 action：否则与三餐通知的 PendingIntent 撞签名（extras 不参与匹配），goto 会被覆盖 */
        const val ACTION_OPEN_WATER = "com.healthydiet.app.action.OPEN_WATER"
        const val GOTO_WATER = "water"
    }
}