import 'package:clipboard_file/clipboard_file.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const ClipboardFileExampleApp());
}

class ClipboardFileExampleApp extends StatelessWidget {
  const ClipboardFileExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'clipboard_file example',
      home: const ClipboardDemoPage(),
    );
  }
}

class ClipboardDemoPage extends StatefulWidget {
  const ClipboardDemoPage({super.key});

  @override
  State<ClipboardDemoPage> createState() => _ClipboardDemoPageState();
}

class _ClipboardDemoPageState extends State<ClipboardDemoPage> {
  String _status =
      'Copy a file or image to the clipboard, then tap Read clipboard file.';

  Future<void> _readClipboard() async {
    setState(() => _status = 'Reading clipboard...');

    final file = await ClipboardFileReader.readFile();
    if (!mounted) return;

    setState(() {
      if (file == null) {
        _status = 'No file on clipboard (plain text or empty).';
        return;
      }

      final name = file.fileName ?? 'unnamed.${file.extension}';
      _status =
          'Read $name\n${file.bytes.length} bytes\nExtension: .${file.extension}';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('clipboard_file'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              _status,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _readClipboard,
              child: const Text('Read clipboard file'),
            ),
          ],
        ),
      ),
    );
  }
}
