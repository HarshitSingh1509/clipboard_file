import 'package:flutter/foundation.dart';

/// Binary image read from the system clipboard.
class ClipboardImageData {
  const ClipboardImageData({
    required this.bytes,
    required this.extension,
  });

  final Uint8List bytes;
  final String extension;
}

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
