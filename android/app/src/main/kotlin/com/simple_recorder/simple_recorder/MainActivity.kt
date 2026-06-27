package com.simple_recorder.simple_recorder

import android.content.Intent
import android.net.Uri
import android.os.Build
import androidx.core.content.FileProvider
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.simple_recorder/open_folder"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "openFolder") {
                    val path = call.argument<String>("path") ?: ""
                    if (path.isEmpty()) {
                        result.error("INVALID_PATH", "路径为空", null)
                        return@setMethodCallHandler
                    }
                    try {
                        val file = File(path)
                        if (!file.exists()) {
                            result.error("NOT_FOUND", "目录不存在: $path", null)
                            return@setMethodCallHandler
                        }
                        val uri: Uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                            FileProvider.getUriForFile(
                                this,
                                "${applicationContext.packageName}.fileprovider",
                                file
                            )
                        } else {
                            Uri.fromFile(file)
                        }
                        val intent = Intent(Intent.ACTION_VIEW).apply {
                            setDataAndType(uri, "resource/folder")
                            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                        }
                        // Fallback: try opening with ACTION_VIEW on the directory URI
                        if (intent.resolveActivity(packageManager) == null) {
                            val dirIntent = Intent(Intent.ACTION_VIEW).apply {
                                setDataAndType(uri, "*/*")
                                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                            }
                            startActivity(dirIntent)
                        } else {
                            startActivity(intent)
                        }
                        result.success(true)
                    } catch (e: Exception) {
                        result.error("OPEN_FAILED", "无法打开文件夹: ${e.message}", null)
                    }
                } else {
                    result.notImplemented()
                }
            }
    }
}
