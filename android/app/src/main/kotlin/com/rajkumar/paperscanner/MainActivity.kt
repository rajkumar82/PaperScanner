package com.rajkumar.paperscanner

import android.content.ContentValues
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "paperscanner/downloads")
            .setMethodCallHandler { call, result ->
                if (call.method != "savePdf") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val name = call.argument<String>("name")
                val bytes = call.argument<ByteArray>("bytes")
                if (name == null || bytes == null) {
                    result.error("bad_args", "name and bytes are required", null)
                    return@setMethodCallHandler
                }
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
                    result.error("unsupported", "Saving to Downloads needs Android 10 or newer. Use Share instead.", null)
                    return@setMethodCallHandler
                }
                Thread {
                    try {
                        val values = ContentValues().apply {
                            put(MediaStore.Downloads.DISPLAY_NAME, name)
                            put(MediaStore.Downloads.MIME_TYPE, "application/pdf")
                            put(MediaStore.Downloads.IS_PENDING, 1)
                        }
                        val resolver = contentResolver
                        val uri = resolver.insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                            ?: throw IllegalStateException("Could not create the file in Downloads")
                        resolver.openOutputStream(uri)!!.use { it.write(bytes) }
                        values.clear()
                        values.put(MediaStore.Downloads.IS_PENDING, 0)
                        resolver.update(uri, values, null, null)
                        runOnUiThread { result.success(name) }
                    } catch (e: Exception) {
                        runOnUiThread { result.error("save_failed", e.message, null) }
                    }
                }.start()
            }
    }
}
