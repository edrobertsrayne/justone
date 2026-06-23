import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/ui/empty_pool_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('shows empty-pool copy and fires onAdd', (tester) async {
    var added = false;
    await tester.pumpWidget(MaterialApp(home: EmptyPoolScreen(onAdd: () => added = true)));
    expect(find.textContaining('Your pool'), findsOneWidget);
    expect(find.textContaining('Add a chore whenever one turns up'), findsOneWidget);
    await tester.tap(find.text('Add a chore'));
    expect(added, isTrue);
  });
}
