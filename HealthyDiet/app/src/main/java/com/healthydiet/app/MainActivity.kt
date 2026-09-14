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

    @SuppressLint("SetJavaScriptEnabled")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        // Android 15+ 强制 edge-to-edge 会让 WebView 内容顶进状态栏；显式 fit 系统窗口避免重叠
        WindowCompat.setDecorFitsSystemWindows(window, true)
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
        webView.webViewClient = WebViewClient()
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

    override fun onKeyDown(keyCode: Int, event: KeyEvent?): Boolean {
        // 返回键回退网页历史，而不是直接退出
        if (keyCode == KeyEvent.KEYCODE_BACK && webView.canGoBack()) {
            webView.goBack()
            return true
        }
        return super.onKeyDown(keyCode, event)
    }

    override fun onDestroy() {
        server?.stop()
        webView.destroy()
        super.onDestroy()
    }

    companion object {
        /** 与网关安全域名白名单对应的本地端口 */
        const val PORT = 8765
        private const val SO_TIMEOUT = 5000
    }
}