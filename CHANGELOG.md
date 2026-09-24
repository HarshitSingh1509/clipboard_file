## 0.1.3

### Teams / Jira / multi-image paste

- **Android:** Scan all primary-clip items (URIs, `Intent` `EXTRA_STREAM`, HTML per item); extract every `data:image/...;base64` match from HTML; ignore placeholder plain text (`Image`, `[Image]`).
- **iOS:** Read `pasteboard.items` and RTFD/RTF **all** `NSTextAttachment` images (not only the first); parse HTML on each pasteboard item; resolve `NSItemProvider`s sequentially and collect every image UTI; support Teams-style payloads (`com.apple.flat-rtfd`, etc.).
- **Dart:** Add `ClipboardFileReader.readFiles()` for multiple clipboard images; `readFile()` returns the first entry from `readFiles()`. Add `readPasteDiagnostics()` for item/provider counts and placeholder hints (debugging).

### Correct image extension (magic bytes)

- **iOS / Android:** Prefer file magic bytes over declared MIME/UTI when building payloads (fixes JPEG bytes labeled as PNG from Teams).
- **Dart:** Add `ClipboardImageFormat` (`extensionFromBytes`, `normalizeExtension`, `normalizeFileName`); apply automatically in `readFiles()` / `readFile()` parsing so `ClipboardFileData.extension` matches actual bytes.
- **Dart:** Add `ClipboardFileReader.isImagePlaceholderText()` for apps that fall back to plain-text paste.

### Notes for integrators

- Call `readFiles()` (or `readFile()`) **before** `Clipboard.kTextPlain` when handling paste in chat-style UIs.
- Rebuild the app after upgrading; native plugin changes require a full restart.

## 0.1.2

- Expanded README with installation, API reference, supported file types, and platform notes.
- Updated example app and tests to demonstrate the current API.
- Added pub.dev metadata (topics, documentation link) and publish tooling.

## 0.1.1

- Merged `readImage()` into `readFile()`; use `readFile()` for both files and images.
- Removed `ClipboardImageData` and the separate `readImage()` API.

## 0.1.0

- Initial publishable release.
- Read files and images from the clipboard on iOS and Android.
- Copy images to the clipboard.
