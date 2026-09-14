package com.healthydiet.app

import android.content.Context
import android.content.res.AssetManager
import fi.iki.elonen.NanoHTTPD
import java.io.InputStream

/**
 * 内嵌静态资源服务：把 assets/web 以 http://127.0.0.1:8765 暴露给 WebView。
 * 走本地 http 源而非 file://，是为了让前端 fetch 云函数网关时通过 CORS
 * （CloudBase 网关对 localhost 来源放行，对 file:// 的 null 源拒绝）。
 */
class AssetServer(context: Context, port: Int) : NanoHTTPD("127.0.0.1", port) {

    private val assets: AssetManager = context.assets

    override fun serve(session: IHTTPSession): Response {
        var path = session.uri.removePrefix("/")
        if (path.isEmpty()) path = "index.html"
        return try {
            val stream: InputStream = assets.open("web/$path")
            val mime = when {
                path.endsWith(".html") -> "text/html; charset=utf-8"
                path.endsWith(".css") -> "text/css; charset=utf-8"
                path.endsWith(".js") -> "application/javascript; charset=utf-8"
                path.endsWith(".jpg") || path.endsWith(".jpeg") -> "image/jpeg"
                path.endsWith(".png") -> "image/png"
                path.endsWith(".webp") -> "image/webp"
                else -> "application/octet-stream"
            }
            val resp = newChunkedResponse(Response.Status.OK, mime, stream)
            resp.addHeader("Cache-Control", "no-store")   // 本地服务不缓存，避免 WebView  heuristic 缓存旧 css/js
            resp
        } catch (e: Exception) {
            newFixedLengthResponse(Response.Status.NOT_FOUND, "text/plain", "not found: $path")
        }
    }
}
