# clipboard_file

Read and copy files from the system clipboard on **iOS** and **Android**.

Supports pasted images, PDFs, Office documents, CSV, and other common file types while leaving plain-text clipboard content available for normal text paste.

## Features

- `ClipboardFileReader.readFile()` — read a file from the clipboard (returns `null` for plain text)
- `ClipboardFileReader.readImage()` — read image bytes from the clipboard
- `ClipboardFileReader.copyImage()` — copy PNG/JPEG bytes to the clipboard

## Usage

```yaml
dependencies:
  clipboard_file: ^0.1.0
```

```dart
import 'package:clipboard_file/clipboard_file.dart';

final file = await ClipboardFileReader.readFile();
if (file != null) {
  print('${file.fileName ?? 'unnamed'}.${file.extension}');
}

await ClipboardFileReader.copyImage(pngBytes);
```

## Platform notes

- **iOS**: Uses `UIPasteboard`, `NSItemProvider`, and `suggestedName` for original filenames.
- **Android**: Reads `content://` URIs from the clipboard. CSV files copied as files are attached; copied cell content still pastes as text.

## Publishing

```bash
dart pub publish --dry-run
dart pub publish
```

Update `homepage`, `repository`, and `issue_tracker` in `pubspec.yaml` with your GitHub username before publishing.
