import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hackathon_reading/search/companion_selection.dart';

void main() {
  test('a book starts in automatic mode', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(companionSelectionProvider('b1')), null);
  });

  test('choosing threads switches that book to an explicit selection', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(companionSelectionProvider('b1').notifier)
        .setSelection({'t1', 't2'});

    expect(container.read(companionSelectionProvider('b1')), {'t1', 't2'});
    expect(container.read(companionSelectionProvider('b2')), null);
  });

  test('an empty selection is kept as "no companion context"', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(companionSelectionProvider('b1').notifier).setSelection({});

    expect(container.read(companionSelectionProvider('b1')), isEmpty);
    expect(container.read(companionSelectionProvider('b1')), isNotNull);
  });

  test('resetting returns the book to automatic mode', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(companionSelectionProvider('b1').notifier)
        .setSelection({'t1'});
    container.read(companionSelectionProvider('b1').notifier).reset();

    expect(container.read(companionSelectionProvider('b1')), null);
  });
}
