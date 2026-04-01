import 'package:flutter_test/flutter_test.dart';

import 'package:python_runner/main.dart';

void main() {
  testWidgets('App renders', (WidgetTester tester) async {
    await tester.pumpWidget(const PythonRunnerApp());
    expect(find.text('Python Runner'), findsOneWidget);
  });
}
