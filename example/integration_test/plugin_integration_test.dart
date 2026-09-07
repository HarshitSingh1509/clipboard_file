import 'package:clipboard_file/clipboard_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('readFile completes without throwing', (WidgetTester tester) async {
    final file = await ClipboardFileReader.readFile();
    expect(file == null || file.bytes.isNotEmpty, isTrue);
  });
}
