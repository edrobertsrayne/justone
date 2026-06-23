import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:justone/app/toast_controller.dart';

void main() {
  test('show sets the message then auto-clears after the duration', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(toastProvider), isNull);
    container.read(toastProvider.notifier).show('hi', duration: const Duration(milliseconds: 20));
    expect(container.read(toastProvider), 'hi');

    await Future<void>.delayed(const Duration(milliseconds: 40));
    expect(container.read(toastProvider), isNull);
  });

  test('a second show replaces the first message', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final c = container.read(toastProvider.notifier);
    c.show('one');
    c.show('two');
    expect(container.read(toastProvider), 'two');
  });
}
