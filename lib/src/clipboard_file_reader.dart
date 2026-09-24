import 'package:flutter/services.dart';

import 'clipboard_file_data.dart';
import 'clipboard_image_format.dart';

/// Reads files and images from the native clipboard on iOS and Android.
class ClipboardFileReader {
  ClipboardFileReader._();

  static const MethodChannel _channel = MethodChannel('clipboard_file');

  /// Copies [bytes] as a PNG image to the system clipboard.
  static Future<void> copyImage(Uint8List bytes) async {
    await _channel.invokeMethod<void>('copyImage', bytes);
  }

  /// Returns clipboard file or image data when present, otherwise `null`.
  ///
  /// Plain text without file metadata returns `null` so callers can fall back
  /// to normal text paste. Apps such as Microsoft Teams and Jira often put
  /// placeholder strings like `Image` or `[Image]` on the plain-text slot while
  /// image bytes live on another clip item or in HTML — call this method before
  /// reading [Clipboard.kTextPlain].
  static Future<ClipboardFileData?> readFile() async {
    final files = await readFiles();
    return files.isEmpty ? null : files.first;
  }

  /// All image files on the clipboard (e.g. multiple `[Image]` entries in Teams/Jira HTML).
  /// Native clipboard shape (item count, UTIs, placeholder text) for debugging multi-paste.
  static Future<Map<String, dynamic>> readPasteDiagnostics() async {
    try {
      final result = await _channel.invokeMethod<Object?>('readPasteDiagnostics');
      if (result is Map) {
        return Map<String, dynamic>.from(result);
      }
    } on PlatformException {
      // fall through
    } on MissingPluginException {
      // fall through
    }
    return {};
  }

  static Future<List<ClipboardFileData>> readFiles() async {
    try {
      final result = await _channel.invokeMethod<Object?>('readFiles');
      if (result is! List) {
        final single = await _channel.invokeMethod<Object?>('readFile');
        if (single is Map) {
          final parsed = _parseClipboardMap(single);
          return parsed == null ? [] : [parsed];
        }
        return [];
      }

      final files = <ClipboardFileData>[];
      for (final item in result) {
        if (item is! Map) continue;
        final parsed = _parseClipboardMap(item);
        if (parsed != null) files.add(parsed);
      }
      return files;
    } on PlatformException {
      return [];
    } on MissingPluginException {
      return [];
    }
  }

  static ClipboardFileData? _parseClipboardMap(Map<dynamic, dynamic> result) {
    final bytes = _parseBytes(result['bytes']);
    final reported = result['extension']?.toString().toLowerCase();
    if (bytes == null || bytes.isEmpty || reported == null || reported.isEmpty) {
      return null;
    }

    final extension = ClipboardImageFormat.normalizeExtension(bytes, reported);
    final rawName = result['fileName']?.toString().trim();
    final fileName = rawName?.isNotEmpty == true
        ? ClipboardImageFormat.normalizeFileName(rawName, bytes)
        : null;

    return ClipboardFileData(
      bytes: bytes,
      extension: extension,
      fileName: fileName?.isNotEmpty == true ? fileName : null,
    );
  }

  /// True when [text] is a known image placeholder from chat apps (not real content).
  static bool isImagePlaceholderText(String text) {
    final trimmed = text.trim();
    if (trimmed.toLowerCase() == 'image') return true;
    return RegExp(r'^\s*(\[Image\]\s*)+\s*$', caseSensitive: false).hasMatch(trimmed);
  }

  static Uint8List? _parseBytes(Object? raw) {
    if (raw is Uint8List) return raw;
    if (raw is ByteData) return raw.buffer.asUint8List();
    if (raw is List) return Uint8List.fromList(raw.cast<int>());
    return null;
  }
}
