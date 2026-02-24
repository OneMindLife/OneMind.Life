import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/widgets/compact_countdown.dart';

void main() {
  Widget buildCountdown({Duration? remaining}) {
    return MaterialApp(
      home: Scaffold(
        body: CompactCountdown(remaining: remaining),
      ),
    );
  }

  group('CompactCountdown', () {
    testWidgets('renders nothing when remaining is null', (tester) async {
      await tester.pumpWidget(buildCountdown(remaining: null));
      expect(find.byType(SizedBox), findsOneWidget);
      expect(find.byType(Text), findsNothing);
    });

    testWidgets('shows "Ending..." when remaining is zero', (tester) async {
      await tester.pumpWidget(buildCountdown(remaining: Duration.zero));
      expect(find.text('Ending...'), findsOneWidget);
    });

    testWidgets('shows seconds only for < 1 minute', (tester) async {
      await tester
          .pumpWidget(buildCountdown(remaining: const Duration(seconds: 45)));
      expect(find.text('45s'), findsOneWidget);
    });

    testWidgets('shows minutes and zero-padded seconds for < 1 hour',
        (tester) async {
      await tester.pumpWidget(buildCountdown(
          remaining: const Duration(minutes: 3, seconds: 5)));
      expect(find.text('3m 05s'), findsOneWidget);
    });

    testWidgets('shows hours and zero-padded minutes for >= 1 hour',
        (tester) async {
      await tester.pumpWidget(buildCountdown(
          remaining: const Duration(hours: 1, minutes: 3)));
      expect(find.text('1h 03m'), findsOneWidget);
    });

    testWidgets('shows "Ending..." for negative duration', (tester) async {
      await tester.pumpWidget(
          buildCountdown(remaining: const Duration(seconds: -5)));
      expect(find.text('Ending...'), findsOneWidget);
    });
  });
}
