import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/providers.dart';
import 'package:justone/data/in_memory_repository.dart';
import 'package:justone/domain/user_state.dart';
import 'package:justone/ui/add_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 6, 24, 9);

  testWidgets('add flow: type title -> enrich -> save creates a task', (tester) async {
    final repo = InMemoryRepository(
      user: UserState(timezone: 'UTC', lastActiveDate: now, onboardingComplete: true),
      tasks: const [],
    );
    late WidgetRef capturedRef;
    await tester.pumpWidget(ProviderScope(
      overrides: [
        repositoryProvider.overrideWithValue(repo),
        nowProvider.overrideWithValue(() => now),
      ],
      child: MaterialApp(
        home: Consumer(builder: (context, ref, _) {
          capturedRef = ref;
          return Scaffold(body: Center(
            child: ElevatedButton(
              onPressed: () => showAddSheet(context, ref),
              child: const Text('open'),
            ),
          ));
        }),
      ),
    ));

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Descale kettle');
    await tester.tap(find.text('Add to pool'));
    await tester.pumpAndSettle();

    // Enrich sheet now showing; Repeat defaults to One-off; just Save.
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final tasks = await repo.watchTasks().first;
    expect(tasks.map((t) => t.title), contains('Descale kettle'));
    expect(capturedRef, isNotNull);
  });
}
