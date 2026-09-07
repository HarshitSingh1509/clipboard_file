import 'package:flutter/foundation.dart';

/// File read from the system clipboard (images, documents, CSV, etc.).
class ClipboardFileData {
  const ClipboardFileData({
    required this.bytes,
    required this.extension,
    this.fileName,
  });

  final Uint8List bytes;
  final String extension;
  final String? fileName;
}
