import 'dart:typed_data';

import 'package:clipboard_file/clipboard_file.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('isImagePlaceholderText detects Teams/Jira placeholders', () {
    expect(ClipboardFileReader.isImagePlaceholderText('Image'), isTrue);
    expect(ClipboardFileReader.isImagePlaceholderText('[Image]'), isTrue);
    expect(ClipboardFileReader.isImagePlaceholderText('  [Image] [Image]  '), isTrue);
    expect(ClipboardFileReader.isImagePlaceholderText('hello.txt'), isFalse);
    expect(ClipboardFileReader.isImagePlaceholderText('report.pdf'), isFalse);
  });

  test('ClipboardImageFormat detects magic bytes over reported extension', () {
    final jpegHeader = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]);
    expect(
      ClipboardImageFormat.normalizeExtension(jpegHeader, 'png'),
      'jpeg',
    );

    final pngHeader = Uint8List.fromList([
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ]);
    expect(
      ClipboardImageFormat.normalizeExtension(pngHeader, 'jpeg'),
      'png',
    );
    expect(ClipboardImageFormat.normalizeExtension([1, 2, 3], 'jpg'), 'jpeg');
  });

  test('ClipboardImageFormat fixes fileName extension', () {
    final jpegHeader = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
    expect(
      ClipboardImageFormat.normalizeFileName('photo.png', jpegHeader),
      'photo.jpeg',
    );
  });

  test('dedupeClipboardFiles collapses iOS photo duplicate only', () {
    final unnamed = ClipboardFileData(
      bytes: Uint8List.fromList(List.filled(10, 1)),
      extension: 'png',
    );
    final named = ClipboardFileData(
      bytes: Uint8List.fromList(List.filled(12, 2)),
      extension: 'png',
      fileName: 'IMG_0045.png',
    );

    final result = dedupeClipboardFiles([unnamed, named]);
    expect(result, hasLength(1));
    expect(result.single.fileName, 'IMG_0045.png');
  });

  test('dedupeClipboardFiles keeps Teams multi-image paste', () {
    final images = List.generate(
      3,
      (i) => ClipboardFileData(
        bytes: Uint8List.fromList([i, i, i]),
        extension: 'png',
      ),
    );

    expect(dedupeClipboardFiles(images), images);
  });

  test('dedupeClipboardFiles keeps multiple named images', () {
    final a = ClipboardFileData(
      bytes: Uint8List.fromList([1]),
      extension: 'png',
      fileName: 'a.png',
    );
    final b = ClipboardFileData(
      bytes: Uint8List.fromList([2]),
      extension: 'png',
      fileName: 'b.png',
    );

    expect(dedupeClipboardFiles([a, b]), [a, b]);
  });

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
