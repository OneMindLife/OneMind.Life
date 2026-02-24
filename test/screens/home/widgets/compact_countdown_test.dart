import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/widgets/compact_countdown.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('CompactCountdown', () {
    testWidgets('shows nothing when remaining is null', (tester) async {
      await tester.pumpWidget(wrap(
        const CompactCountdown(remaining: null),
      ));
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('shows "Ending..." for zero duration', (tester) async {
      await tester.pumpWidget(wrap(
        const CompactCountdown(remaining: Duration.zero),
      ));
      expect(find.text('Ending...'), findsOneWidget);
    });

    testWidgets('shows seconds only for < 1 minute', (tester) async {
      await tester.pumpWidget(wrap(
        const CompactCountdown(remaining: Duration(seconds: 45)),
      ));
      expect(find.text('45s'), findsOneWidget);
    });

    testWidgets('shows minutes + seconds for < 1 hour', (tester) async {
      await tester.pumpWidget(wrap(
        const CompactCountdown(
            remaining: Duration(minutes: 3, seconds: 42)),
      ));
      expect(find.text('3m 42s'), findsOneWidget);
    });

    testWidgets('shows hours + minutes for >= 1 hour', (tester) async {
      await tester.pumpWidget(wrap(
        const CompactCountdown(
            remaining: Duration(hours: 2, minutes: 15)),
      ));
      expect(find.text('2h 15m'), findsOneWidget);
    });
  });
}
