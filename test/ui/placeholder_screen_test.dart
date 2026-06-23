import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/ui/placeholder_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('shows the title and a coming-soon line', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: PlaceholderScreen(title: 'Manage')));
    expect(find.text('Manage'), findsOneWidget);
    expect(find.textContaining('coming soon'), findsOneWidget);
  });
}
