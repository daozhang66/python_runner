import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:python_runner/ui/app_skeleton.dart';

void main() {
  testWidgets('list skeleton renders reusable loading placeholders',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: AppListSkeleton(itemCount: 3)),
      ),
    );

    expect(find.byType(AppSkeleton), findsNWidgets(9));
  });
}
