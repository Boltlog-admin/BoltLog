import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Sanity check: test harness runs', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(child: Text('Boltlog')),
        ),
      ),
    );
    expect(find.text('Boltlog'), findsOneWidget);
  });
}
