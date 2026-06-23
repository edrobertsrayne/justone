import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/ui/cleared_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('shows cleared copy, a Review pool CTA, and no Keep going', (tester) async {
    var reviewed = false;
    await tester.pumpWidget(MaterialApp(home: ClearedScreen(onReviewPool: () => reviewed = true)));
    expect(find.textContaining("on top of"), findsOneWidget);
    expect(find.textContaining('Enjoy the quiet'), findsOneWidget);
    expect(find.textContaining('Keep going'), findsNothing);
    await tester.tap(find.text('Review pool'));
    expect(reviewed, isTrue);
  });
}
