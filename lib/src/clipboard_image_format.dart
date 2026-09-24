/// Detects image format from magic bytes when clipboard metadata is wrong.
class ClipboardImageFormat {
  ClipboardImageFormat._();

  /// Returns a normalized extension from [bytes], or `null` if not recognized.
  static String? extensionFromBytes(List<int> bytes) {
    if (bytes.length >= 8 &&
        bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return 'png';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xFF &&
        bytes[1] == 0xD8 &&
        bytes[2] == 0xFF) {
      return 'jpeg';
    }
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'webp';
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0x47 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46) {
      return 'gif';
    }
    return null;
  }

  /// Prefers magic-byte detection over [reportedExtension]; normalizes `jpg` → `jpeg`.
  static String normalizeExtension(List<int> bytes, String reportedExtension) {
    final detected = extensionFromBytes(bytes);
    if (detected != null) return detected;
    final lower = reportedExtension.toLowerCase();
    return lower == 'jpg' ? 'jpeg' : lower;
  }

  /// Adjusts [fileName] when its extension disagrees with [bytes].
  static String? normalizeFileName(String? fileName, List<int> bytes) {
    final trimmed = fileName?.trim();
    if (trimmed == null || trimmed.isEmpty) return fileName;

    final ext = normalizeExtension(bytes, _extensionOf(trimmed));
    if (!trimmed.contains('.')) return '$trimmed.$ext';

    final base = trimmed.substring(0, trimmed.lastIndexOf('.'));
    return '$base.$ext';
  }

  static String _extensionOf(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }
}
