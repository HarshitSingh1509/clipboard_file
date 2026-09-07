import 'package:flutter/services.dart';

import 'clipboard_file_data.dart';

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
  /// to normal text paste.
  static Future<ClipboardFileData?> readFile() async {
    try {
      final result = await _channel.invokeMethod<Object?>('readFile');
      if (result == null || result is! Map) return null;

      final bytes = _parseBytes(result['bytes']);
      final extension = result['extension']?.toString().toLowerCase();
      if (bytes == null || bytes.isEmpty || extension == null || extension.isEmpty) {
        return null;
      }

      final fileName = result['fileName']?.toString().trim();

      return ClipboardFileData(
        bytes: bytes,
        extension: extension,
        fileName: fileName?.isNotEmpty == true ? fileName : null,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  static Uint8List? _parseBytes(Object? raw) {
    if (raw is Uint8List) return raw;
    if (raw is ByteData) return raw.buffer.asUint8List();
    if (raw is List) return Uint8List.fromList(raw.cast<int>());
    return null;
  }
}
