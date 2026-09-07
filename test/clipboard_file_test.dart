import 'dart:typed_data';

import 'package:clipboard_file/clipboard_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ClipboardFileData stores metadata', () {
    final data = ClipboardFileData(
      bytes: Uint8List.fromList([1, 2, 3]),
      extension: 'pdf',
      fileName: 'report.pdf',
    );

    expect(data.extension, 'pdf');
    expect(data.fileName, 'report.pdf');
    expect(data.bytes, [1, 2, 3]);
  });
}
