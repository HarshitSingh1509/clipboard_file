import 'package:clipboard_file_example/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows read button and initial status', (WidgetTester tester) async {
    await tester.pumpWidget(const ClipboardFileExampleApp());

    expect(find.text('Read clipboard file'), findsOneWidget);
    expect(
      find.textContaining('Copy a file or image to the clipboard'),
      findsOneWidget,
    );
  });
}
