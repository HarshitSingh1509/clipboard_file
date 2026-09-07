package com.clipboardfile.clipboard_file

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.OpenableColumns
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.io.FileOutputStream

class ClipboardFilePlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel
    private lateinit var applicationContext: Context

    override fun onAttachedToEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        applicationContext = binding.applicationContext
        channel = MethodChannel(binding.binaryMessenger, "clipboard_file")
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "copyImage" -> copyImage(call, result)
            "readFile" -> {
                try {
                    result.success(readFileFromClipboard())
                } catch (e: Exception) {
                    result.error(
                        "READ_FAILED",
                        "Failed to read clipboard file: ${e.localizedMessage}",
                        null,
                    )
                }
            }
            else -> result.notImplemented()
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }

    private fun copyImage(call: MethodCall, result: Result) {
        try {
            val byteArray = call.arguments as ByteArray
            val bitmap = BitmapFactory.decodeByteArray(byteArray, 0, byteArray.size)
            val cacheDir = File(applicationContext.cacheDir, "clipboard_images")
            cacheDir.mkdirs()
            val file = File(cacheDir, "clipboard_image.png")
            FileOutputStream(file).use { output ->
                bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, output)
            }

            val uri = FileProvider.getUriForFile(
                applicationContext,
                "${applicationContext.packageName}.clipboard_file.provider",
                file,
            )
            val clip = ClipData.newUri(applicationContext.contentResolver, "Image", uri)
            val clipboard =
                applicationContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
            clipboard.setPrimaryClip(clip)
            result.success(null)
        } catch (e: Exception) {
            result.error("COPY_FAILED", "Failed to copy image: ${e.localizedMessage}", null)
        }
    }

    private fun readFileFromClipboard(): Map<String, Any>? {
        val clipboard =
            applicationContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        if (!clipboard.hasPrimaryClip()) return null

        val clip = clipboard.primaryClip ?: return null
        if (clip.itemCount == 0) return null

        val clipLabel = clip.description.label?.toString()?.trim()?.takeIf { it.contains('.') }
        val item = clip.getItemAt(0)
        val uri = item.uri
        if (uri != null) {
            val mime = applicationContext.contentResolver.getType(uri)
            val fileName = queryDisplayName(uri) ?: clipLabel
            if (mime == "text/plain" && !isDocumentFileName(fileName)) return null

            val bytes = readUriBytes(uri) ?: return null
            val extension = extensionFrom(fileName, mime, bytes) ?: return null

            val payload = mutableMapOf<String, Any>(
                "bytes" to bytes,
                "extension" to extension,
            )
            if (!fileName.isNullOrBlank()) {
                payload["fileName"] = fileName
            }
            return payload
        }

        val description = clip.description
        val hasImageMime = (0 until description.mimeTypeCount).any { index ->
            description.getMimeType(index)?.startsWith("image/") == true
        }
        if (hasImageMime) {
            for (index in 0 until clip.itemCount) {
                val clipUri = clip.getItemAt(index).uri ?: continue
                val mime = applicationContext.contentResolver.getType(clipUri)
                if (mime?.startsWith("image/") != true) continue
                val bytes = readUriBytes(clipUri) ?: continue
                val extension = detectImageExtension(mime, bytes) ?: continue
                val fileName = queryDisplayName(clipUri)
                val payload = mutableMapOf<String, Any>(
                    "bytes" to bytes,
                    "extension" to extension,
                )
                if (!fileName.isNullOrBlank()) {
                    payload["fileName"] = fileName
                }
                return payload
            }
        }

        if (clipLabel != null && isDocumentFileName(clipLabel)) {
            val text = item.text?.toString() ?: return null
            if (text.isEmpty()) return null
            val bytes = text.toByteArray(Charsets.UTF_8)
            val extension = extensionFrom(clipLabel, null, bytes) ?: return null
            return mutableMapOf(
                "bytes" to bytes,
                "extension" to extension,
                "fileName" to clipLabel,
            )
        }

        return null
    }

    private fun isDocumentFileName(fileName: String?): Boolean {
        val extension = fileName
            ?.substringAfterLast('.', "")
            ?.lowercase()
            ?.takeIf { it.isNotEmpty() }
            ?: return false
        return extension in documentExtensions
    }

    private fun queryDisplayName(uri: Uri): String? {
        applicationContext.contentResolver.query(
            uri,
            arrayOf(OpenableColumns.DISPLAY_NAME),
            null,
            null,
            null,
        )?.use { cursor ->
            val index = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index >= 0 && cursor.moveToFirst()) {
                return cursor.getString(index)?.trim()?.takeIf { it.isNotEmpty() }
            }
        }
        return uri.lastPathSegment?.takeIf { it.contains('.') }
    }

    private fun extensionFrom(
        fileName: String?,
        mime: String?,
        bytes: ByteArray,
    ): String? {
        fileName
            ?.substringAfterLast('.', "")
            ?.lowercase()
            ?.takeIf { it.isNotEmpty() }
            ?.let { return it }

        detectImageExtension(mime, bytes)?.let { return it }

        if (bytes.size >= 4 &&
            bytes[0] == 0x25.toByte() &&
            bytes[1] == 0x50.toByte() &&
            bytes[2] == 0x44.toByte() &&
            bytes[3] == 0x46.toByte()
        ) {
            return "pdf"
        }

        return when {
            mime?.contains("pdf", ignoreCase = true) == true -> "pdf"
            mime?.contains("wordprocessingml", ignoreCase = true) == true -> "docx"
            mime?.contains("msword", ignoreCase = true) == true -> "doc"
            mime?.contains("presentationml", ignoreCase = true) == true -> "pptx"
            mime?.contains("powerpoint", ignoreCase = true) == true -> "ppt"
            mime?.contains("spreadsheetml", ignoreCase = true) == true -> "xlsx"
            mime?.contains("ms-excel", ignoreCase = true) == true -> "xls"
            mime?.contains("csv", ignoreCase = true) == true -> "csv"
            mime?.contains("plain", ignoreCase = true) == true -> "txt"
            else -> null
        }
    }

    private fun readUriBytes(uri: Uri): ByteArray? {
        return applicationContext.contentResolver.openInputStream(uri)?.use { it.readBytes() }
    }

    private fun detectImageExtension(mime: String?, bytes: ByteArray): String? {
        when {
            mime?.contains("png", ignoreCase = true) == true -> return "png"
            mime?.contains("jpeg", ignoreCase = true) == true -> return "jpeg"
            mime?.contains("jpg", ignoreCase = true) == true -> return "jpg"
        }

        if (bytes.size >= 8 &&
            bytes[0] == 0x89.toByte() &&
            bytes[1] == 0x50.toByte() &&
            bytes[2] == 0x4E.toByte() &&
            bytes[3] == 0x47.toByte()
        ) {
            return "png"
        }

        if (bytes.size >= 2 &&
            bytes[0] == 0xFF.toByte() &&
            bytes[1] == 0xD8.toByte()
        ) {
            return "jpeg"
        }

        return null
    }

    companion object {
        private val documentExtensions = setOf(
            "csv",
            "txt",
            "pdf",
            "doc",
            "docx",
            "ppt",
            "pptx",
            "xls",
            "xlsx",
            "png",
            "jpg",
            "jpeg",
        )
    }
}
