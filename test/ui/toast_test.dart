import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/toast_controller.dart';
import 'package:justone/ui/toast.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('renders nothing when no toast, shows the pill when set', (tester) async {
    await tester.pumpWidget(const ProviderScope(
      child: MaterialApp(home: Scaffold(body: Stack(children: [ToastOverlay()]))),
    ));
    expect(find.text('Saved'), findsNothing);

    final element = tester.element(find.byType(ToastOverlay));
    final container = ProviderScope.containerOf(element);
    container.read(toastProvider.notifier).show('Saved', duration: const Duration(seconds: 5));
    await tester.pump();
    expect(find.text('Saved'), findsOneWidget);
  });
}
