import 'clipboard_file_data.dart';

const _imageExtensions = {
  'png',
  'jpeg',
  'jpg',
  'heic',
  'heif',
  'gif',
  'webp',
};

/// Collapses the iOS single-photo duplicate: one unnamed PNG + one named file.
///
/// Does not alter multi-image pastes (e.g. Teams/Jira HTML with several images).
List<ClipboardFileData> dedupeClipboardFiles(List<ClipboardFileData> files) {
  if (files.length != 2) return files;

  final allImages = files.every(
    (f) => _imageExtensions.contains(f.extension.toLowerCase()),
  );
  if (!allImages) return files;

  final named = files
      .where((f) => f.fileName?.trim().isNotEmpty == true)
      .toList();
  final unnamed = files
      .where((f) => f.fileName?.trim().isNotEmpty != true)
      .toList();

  if (named.length == 1 && unnamed.length == 1) {
    return named;
  }

  return files;
}
