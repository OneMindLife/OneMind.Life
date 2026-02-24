import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/widgets/participant_badge.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

  group('ParticipantBadge', () {
    testWidgets('displays count', (tester) async {
      await tester.pumpWidget(wrap(
        const ParticipantBadge(count: 7),
      ));
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('shows person icon', (tester) async {
      await tester.pumpWidget(wrap(
        const ParticipantBadge(count: 3),
      ));
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
    });

    testWidgets('displays zero count', (tester) async {
      await tester.pumpWidget(wrap(
        const ParticipantBadge(count: 0),
      ));
      expect(find.text('0'), findsOneWidget);
    });
  });
}
