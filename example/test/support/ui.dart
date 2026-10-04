/// Driving the example page by its control keys.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The widget keyed [key].
Finder byKey(String key) => find.byKey(ValueKey<String>(key));

/// Whether the button keyed [key] is enabled.
bool isEnabled(WidgetTester tester, String key) =>
    tester.widget<ButtonStyleButton>(byKey(key)).enabled;

/// Scrolls the button keyed [key] into view, checks it is enabled, taps it,
/// and lets the step finish.
Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(byKey(key));
  await tester.pumpAndSettle();
  expect(isEnabled(tester, key), isTrue, reason: '"$key" is disabled');
  await tester.tap(byKey(key));
  await tester.pumpAndSettle();
}

/// Types [text] into the field keyed [key] and lets the live checks finish.
Future<void> enterKey(WidgetTester tester, String key, String text) async {
  await tester.ensureVisible(byKey(key));
  await tester.enterText(byKey(key), text);
  await tester.pumpAndSettle();
}

/// All the text rendered under the widget keyed [key], one line per text
/// widget.
String textUnder(WidgetTester tester, String key) => tester
    .widgetList<RichText>(
      find.descendant(of: byKey(key), matching: find.byType(RichText)),
    )
    .map((text) => text.text.toPlainText())
    .join('\n');
