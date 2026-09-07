# clipboard_file

[![pub package](https://img.shields.io/pub/v/clipboard_file.svg)](https://pub.dev/packages/clipboard_file)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

A Flutter plugin to read and copy files from the system clipboard on **iOS** and **Android**.

Use it when your app needs to accept pasted files — images, PDFs, Office documents, CSV, and other common types — while still allowing plain-text clipboard content to fall through to normal text paste.

## Features

- Read files and images from the clipboard with a single API
- Copy PNG/JPEG image bytes to the clipboard
- Preserve original filenames when the platform provides them
- Return `null` for plain text so you can combine file paste with standard text paste

## Supported file types

| Type | Extensions |
|------|------------|
| Images | `png`, `jpg`, `jpeg`, `heic` (iOS) |
| Documents | `pdf`, `doc`, `docx`, `ppt`, `pptx`, `xls`, `xlsx` |
| Text files | `csv`, `txt` |

Detection uses MIME types, file extensions, and magic-byte signatures where available.

## Installation

Add `clipboard_file` to your `pubspec.yaml`:

```yaml
dependencies:
  clipboard_file: ^0.1.2
```

Then run:

```bash
flutter pub get
```

## Usage

Import the package:

```dart
import 'package:clipboard_file/clipboard_file.dart';
```

### Read a file from the clipboard

```dart
final file = await ClipboardFileReader.readFile();

if (file != null) {
  print('Name: ${file.fileName ?? 'unnamed.${file.extension}'}');
  print('Extension: ${file.extension}');
  print('Size: ${file.bytes.length} bytes');

  // Save, upload, or process file.bytes
} else {
  // No file on the clipboard — fall back to text paste if needed
}
```

### Copy an image to the clipboard

```dart
await ClipboardFileReader.copyImage(pngOrJpegBytes);
```

On Android, bytes must decode as a valid PNG or JPEG image.

## API reference

### `ClipboardFileReader.readFile()`

Returns `Future<ClipboardFileData?>`.

- Returns file data when the clipboard contains a supported file or image
- Returns `null` when the clipboard is empty, contains plain text, or the platform cannot read the content
- Never throws — platform errors are handled and surfaced as `null`

### `ClipboardFileReader.copyImage(Uint8List bytes)`

Copies image bytes to the system clipboard as a PNG image.

### `ClipboardFileData`

| Field | Type | Description |
|-------|------|-------------|
| `bytes` | `Uint8List` | Raw file contents |
| `extension` | `String` | Lowercase extension without a dot (e.g. `pdf`) |
| `fileName` | `String?` | Original filename when available |

## Platform behavior

### iOS

- Uses `UIPasteboard`, `NSItemProvider`, and `suggestedName` for filenames
- Supports file URLs, images, PDFs, Office Open XML documents, and CSV
- Minimum deployment target: iOS 13.0

### Android

- Reads `content://` URIs from the clipboard
- CSV copied as a file is read as file data; copied cell content still pastes as plain text
- `copyImage` uses a `FileProvider` merged automatically from the plugin manifest — no extra Android setup is required in your app

## Example

See the [`example/`](example/) app for a minimal demo:

```bash
cd example
flutter run
```

Copy a file or screenshot to your device clipboard, then tap **Read clipboard file** in the example app.

## Contributing

Contributions are welcome. Please open an issue or pull request on [GitHub](https://github.com/HarshitSingh1509/clipboard_file).

## License

This project is licensed under the MIT License — see the [LICENSE](LICENSE) file for details.
