import 'package:flutter_test/flutter_test.dart';
import 'package:justone/main.dart';
import 'package:justone/ui/home_router.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('app boots into the home router on the seeded daily loop', (tester) async {
    await tester.pumpWidget(const ProviderScopedApp());
    await tester.pump();
    expect(find.byType(HomeRouter), findsOneWidget);
    expect(find.text('TODAY'), findsOneWidget); // seeded pool opens on daily
  });
}
