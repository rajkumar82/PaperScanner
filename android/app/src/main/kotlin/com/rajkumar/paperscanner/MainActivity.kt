package com.rajkumar.paperscanner

import android.content.ContentValues
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import android.media.ExifInterface
import android.os.Build
import android.provider.MediaStore
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import kotlin.math.max

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "paperscanner/downloads")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "savePdf" -> savePdf(call, result)
                    "renderPage" -> renderPage(call, result)
                    else -> result.notImplemented()
                }
            }
    }

    /** Runs [work] off the UI thread and reports its value or error back on it. */
    private fun <T> background(result: MethodChannel.Result, code: String, work: () -> T) {
        Thread {
            try {
                val value = work()
                runOnUiThread { result.success(value) }
            } catch (e: Throwable) {
                runOnUiThread { result.error(code, e.message, null) }
            }
        }.start()
    }

    private fun savePdf(call: MethodCall, result: MethodChannel.Result) {
        val name = call.argument<String>("name")
        val bytes = call.argument<ByteArray>("bytes")
        if (name == null || bytes == null) {
            result.error("bad_args", "name and bytes are required", null)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            result.error("unsupported", "Saving to Downloads needs Android 10 or newer. Use Share instead.", null)
            return
        }
        background(result, "save_failed") {
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
            name
        }
    }

    /**
     * Rotates (EXIF + the user's quarter turns), crops (0..1 fractions of the
     * rotated photo), downsizes and JPEG-encodes a page. Native bitmap code is
     * far faster than doing this in Dart.
     */
    private fun renderPage(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        val turns = call.argument<Int>("turns") ?: 0
        val l = call.argument<Double>("l") ?: 0.0
        val t = call.argument<Double>("t") ?: 0.0
        val r = call.argument<Double>("r") ?: 1.0
        val b = call.argument<Double>("b") ?: 1.0
        val maxSide = call.argument<Int>("maxSide") ?: 2200
        val quality = call.argument<Int>("quality") ?: 90
        if (path == null) {
            result.error("bad_args", "path is required", null)
            return
        }
        background(result, "render_failed") {
            val src = BitmapFactory.decodeFile(path)
                ?: throw IllegalStateException("Unreadable photo")

            val matrix = Matrix()
            when (ExifInterface(path).getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)) {
                ExifInterface.ORIENTATION_ROTATE_90 -> matrix.postRotate(90f)
                ExifInterface.ORIENTATION_ROTATE_180 -> matrix.postRotate(180f)
                ExifInterface.ORIENTATION_ROTATE_270 -> matrix.postRotate(270f)
                ExifInterface.ORIENTATION_FLIP_HORIZONTAL -> matrix.postScale(-1f, 1f)
                ExifInterface.ORIENTATION_FLIP_VERTICAL -> matrix.postScale(1f, -1f)
                ExifInterface.ORIENTATION_TRANSPOSE -> { matrix.postRotate(90f); matrix.postScale(-1f, 1f) }
                ExifInterface.ORIENTATION_TRANSVERSE -> { matrix.postRotate(270f); matrix.postScale(-1f, 1f) }
            }
            matrix.postRotate((turns % 4) * 90f)
            val rotated = Bitmap.createBitmap(src, 0, 0, src.width, src.height, matrix, true)
            if (rotated !== src) src.recycle()

            val x = Math.round(l * rotated.width).toInt().coerceIn(0, rotated.width - 1)
            val y = Math.round(t * rotated.height).toInt().coerceIn(0, rotated.height - 1)
            val w = Math.round((r - l) * rotated.width).toInt().coerceIn(1, rotated.width - x)
            val h = Math.round((b - t) * rotated.height).toInt().coerceIn(1, rotated.height - y)
            val cropped = Bitmap.createBitmap(rotated, x, y, w, h)
            if (cropped !== rotated) rotated.recycle()

            val longest = max(cropped.width, cropped.height)
            val out = if (longest > maxSide) {
                val scale = maxSide.toFloat() / longest
                Bitmap.createScaledBitmap(
                    cropped,
                    max(1, Math.round(cropped.width * scale)),
                    max(1, Math.round(cropped.height * scale)),
                    true,
                ).also { cropped.recycle() }
            } else cropped

            val stream = ByteArrayOutputStream()
            out.compress(Bitmap.CompressFormat.JPEG, quality, stream)
            out.recycle()
            stream.toByteArray()
        }
    }
}
