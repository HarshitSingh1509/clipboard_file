package com.clipboardfile.clipboard_file

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.net.Uri
import android.provider.OpenableColumns
import android.util.Base64
import androidx.core.content.FileProvider
import androidx.core.content.IntentCompat
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import java.io.FileOutputStream
import java.util.regex.Pattern

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
            "readFiles" -> {
                try {
                    result.success(readFilesFromClipboard())
                } catch (e: Exception) {
                    result.error(
                        "READ_FAILED",
                        "Failed to read clipboard files: ${e.localizedMessage}",
                        null,
                    )
                }
            }
            "readPasteDiagnostics" -> {
                try {
                    result.success(readPasteDiagnostics())
                } catch (e: Exception) {
                    result.error(
                        "READ_FAILED",
                        "Failed to read clipboard diagnostics: ${e.localizedMessage}",
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

        for (index in 0 until clip.itemCount) {
            val item = clip.getItemAt(index)
            item.intent?.let { readPayloadFromIntent(it) }?.let { return it }
            val uri = item.uri ?: continue
            readPayloadFromUri(uri, clipLabel)?.let { return it }
        }

        for (index in 0 until clip.itemCount) {
            val item = clip.getItemAt(index)
            val html = item.coerceToHtmlText(applicationContext.contentResolver)
            readImagePayloadFromHtml(html)?.let { return it }
        }

        if (clipLabel != null && isDocumentFileName(clipLabel)) {
            val text = clip.getItemAt(0).text?.toString() ?: return null
            if (text.isEmpty() || isImagePlaceholderText(text)) return null
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

    private fun readPasteDiagnostics(): Map<String, Any> {
        val clipboard =
            applicationContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        if (!clipboard.hasPrimaryClip()) {
            return mapOf("itemsCount" to 0, "placeholderCount" to 0)
        }
        val clip = clipboard.primaryClip ?: return mapOf("itemsCount" to 0, "placeholderCount" to 0)
        val plain = clip.getItemAt(0).text?.toString().orEmpty()
        val placeholderCount = Regex("\\[Image\\]", RegexOption.IGNORE_CASE)
            .findAll(plain)
            .count()
        return mapOf(
            "itemsCount" to clip.itemCount,
            "placeholderCount" to placeholderCount,
            "plainTextPreview" to plain.take(160),
        )
    }

    private fun readFilesFromClipboard(): List<Map<String, Any>> {
        val clipboard =
            applicationContext.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
        if (!clipboard.hasPrimaryClip()) return emptyList()

        val clip = clipboard.primaryClip ?: return emptyList()
        if (clip.itemCount == 0) return emptyList()

        val clipLabel = clip.description.label?.toString()?.trim()?.takeIf { it.contains('.') }
        val payloads = mutableListOf<Map<String, Any>>()
        val seen = mutableSetOf<String>()

        fun addPayload(payload: Map<String, Any>?) {
            if (payload == null) return
            val bytes = payload["bytes"] as? ByteArray ?: return
            val fingerprint = payloadFingerprint(bytes)
            if (!seen.add(fingerprint)) return
            payloads.add(payload)
        }

        for (index in 0 until clip.itemCount) {
            val item = clip.getItemAt(index)
            item.intent?.let { addPayload(readPayloadFromIntent(it)) }
            item.uri?.let { addPayload(readPayloadFromUri(it, clipLabel)) }
        }

        for (index in 0 until clip.itemCount) {
            val html = clip.getItemAt(index).coerceToHtmlText(applicationContext.contentResolver)
            readAllImagePayloadsFromHtml(html).forEach { addPayload(it) }
        }

        return payloads
    }

    private fun payloadFingerprint(bytes: ByteArray): String {
        val prefix = bytes.take(32).joinToString("") { b ->
            (b.toInt() and 0xFF).toString(16).padStart(2, '0')
        }
        return "${bytes.size}-$prefix"
    }

    private fun readPayloadFromIntent(intent: Intent): Map<String, Any>? {
        val streamUri = IntentCompat.getParcelableExtra(intent, Intent.EXTRA_STREAM, Uri::class.java)
            ?: intent.clipData?.takeIf { it.itemCount > 0 }?.getItemAt(0)?.uri
        if (streamUri != null) {
            readPayloadFromUri(streamUri, null)?.let { return it }
        }
        return null
    }

    private fun readPayloadFromUri(uri: Uri, clipLabel: String?): Map<String, Any>? {
        val mime = applicationContext.contentResolver.getType(uri)
        val fileName = queryDisplayName(uri) ?: clipLabel
        if (mime == "text/plain" && !isDocumentFileName(fileName)) return null

        val bytes = readUriBytes(uri) ?: return null
        val extension = resolveImageExtension(bytes, fileName, mime) ?: return null

        val payload = mutableMapOf<String, Any>(
            "bytes" to bytes,
            "extension" to extension,
        )
        if (!fileName.isNullOrBlank()) {
            payload["fileName"] = fileName
        }
        return payload
    }

    private fun readImagePayloadFromHtml(html: String?): Map<String, Any>? {
        if (html.isNullOrBlank()) return null
        val matcher = HTML_DATA_IMAGE.matcher(html)
        if (!matcher.find()) return null

        val subtype = matcher.group(1)?.lowercase() ?: return null
        val base64 = matcher.group(2)?.replace("\\s".toRegex(), "") ?: return null
        val bytes = try {
            Base64.decode(base64, Base64.DEFAULT)
        } catch (_: IllegalArgumentException) {
            return null
        }
        if (bytes.isEmpty()) return null

        val declared = when (subtype) {
            "png" -> "png"
            "jpeg", "jpg" -> "jpeg"
            "gif" -> "gif"
            "webp" -> "webp"
            else -> detectImageExtension("image/$subtype", bytes) ?: return null
        }

        return mutableMapOf(
            "bytes" to bytes,
            "extension" to resolveImageExtension(bytes, null, "image/$declared") ?: declared,
        )
    }

    private fun readAllImagePayloadsFromHtml(html: String?): List<Map<String, Any>> {
        if (html.isNullOrBlank()) return emptyList()
        val matcher = HTML_DATA_IMAGE.matcher(html)
        val payloads = mutableListOf<Map<String, Any>>()
        while (matcher.find()) {
            readImagePayloadFromHtml(matcher.group(0))?.let { payloads.add(it) }
        }
        return payloads
    }

    private fun resolveImageExtension(
        bytes: ByteArray,
        fileName: String?,
        mime: String?,
    ): String? {
        detectImageExtension(mime, bytes)?.let { return it }
        return extensionFrom(fileName, mime, bytes)
    }

    private fun isImagePlaceholderText(text: String?): Boolean {
        if (text == null) return false
        val trimmed = text.trim()
        if (trimmed.equals("Image", ignoreCase = true)) return true
        return IMAGE_PLACEHOLDER_PATTERN.matches(trimmed)
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
            mime?.contains("gif", ignoreCase = true) == true -> return "gif"
            mime?.contains("webp", ignoreCase = true) == true -> return "webp"
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

        if (bytes.size >= 3 &&
            bytes[0] == 0x47.toByte() &&
            bytes[1] == 0x49.toByte() &&
            bytes[2] == 0x46.toByte()
        ) {
            return "gif"
        }

        if (bytes.size >= 12 &&
            bytes[0] == 0x52.toByte() &&
            bytes[1] == 0x49.toByte() &&
            bytes[2] == 0x46.toByte() &&
            bytes[3] == 0x46.toByte() &&
            bytes[8] == 0x57.toByte() &&
            bytes[9] == 0x45.toByte() &&
            bytes[10] == 0x42.toByte() &&
            bytes[11] == 0x50.toByte()
        ) {
            return "webp"
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

        private val HTML_DATA_IMAGE = Pattern.compile(
            """data:image/(png|jpeg|jpg|gif|webp);base64,([A-Za-z0-9+/=\s]+)""",
            Pattern.CASE_INSENSITIVE,
        )

        private val IMAGE_PLACEHOLDER_PATTERN = Regex(
            """^\s*(\[Image\]\s*)+\s*$""",
            RegexOption.IGNORE_CASE,
        )
    }
}
