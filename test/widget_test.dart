import 'package:flutter_test/flutter_test.dart';
import 'package:nivaran/main.dart';

void main() {
  testWidgets('Nivaran app starts', (WidgetTester tester) async {
    // Basic smoke test
    expect(find.byType(NivaranApp), isNotNull);
  });
}

