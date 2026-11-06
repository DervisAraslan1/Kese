import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kese/core/store.dart';
import 'package:kese/ui/ambient.dart';
import 'package:kese/ui/app.dart';
import 'package:kese/ui/pouch.dart';

import 'core_test.dart' show MemoryPersistence;

Store _store() =>
    Store(MemoryPersistence(), clock: () => DateTime(2026, 11, 18, 12))..startEmpty();

Future<void> _pump(WidgetTester tester, Store store, {bool ambient = true}) async {
  tester.view.physicalSize = const Size(1080, 2200);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(KeseApp(store: store, ambient: ambient));
}

void main() {
  group('seviye', () {
    test('shows the share of income left', () {
      expect(pouchLevel(spent: 25000, earned: 100000), 0.75);
      expect(pouchLevel(spent: 0, earned: 100000), 1);
    });

    test('overspending and no income are empty, not negative', () {
      expect(pouchLevel(spent: 200000, earned: 100000), 0);
      expect(pouchLevel(spent: 500, earned: 0), 0);
      expect(pouchLevel(spent: 0, earned: 0), 0);
    });
  });

  group('renk', () {
    const accent = Color(0xFF3FD6A0);
    const danger = Color(0xFFF87171);

    test('stays the theme color while half is left', () {
      expect(pouchColor(1, accent, danger), accent);
      expect(pouchColor(.5, accent, danger), accent);
    });

    test('turns to danger as it empties', () {
      expect(pouchColor(0, accent, danger), danger);
      expect(pouchColor(.3, accent, danger), isNot(accent));
    });
  });

  testWidgets('ambient motion keeps running and the app stays usable', (tester) async {
    await _pump(tester, _store());
    await tester.pump(const Duration(seconds: 3));
    expect(tester.hasRunningAnimations, isTrue);
    expect(find.text('Bu ay kalan'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('the phone setting to remove animations stops it', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await _pump(tester, _store());
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });

  testWidgets('without ambient the app settles', (tester) async {
    await _pump(tester, _store(), ambient: false);
    await tester.pumpAndSettle();
    expect(find.byType(LivePouch), findsOneWidget);
    expect(find.byType(Aurora), findsOneWidget);
  });

  testWidgets('touching the pouch shakes it, then it settles', (tester) async {
    await _pump(tester, _store(), ambient: false);
    await tester.pumpAndSettle();
    await tester.tap(find.byType(LivePouch));
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.hasRunningAnimations, isTrue);
    await tester.pumpAndSettle();
    expect(tester.hasRunningAnimations, isFalse);
  });
}
