import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/widgets/participant_badge.dart';

void main() {
  Widget buildBadge({required int count}) {
    return MaterialApp(
      home: Scaffold(
        body: ParticipantBadge(count: count),
      ),
    );
  }

  group('ParticipantBadge', () {
    testWidgets('renders participant count', (tester) async {
      await tester.pumpWidget(buildBadge(count: 5));
      expect(find.text('5'), findsOneWidget);
      expect(find.byIcon(Icons.person_outline), findsOneWidget);
    });

    testWidgets('renders zero count', (tester) async {
      await tester.pumpWidget(buildBadge(count: 0));
      expect(find.text('0'), findsOneWidget);
    });

    testWidgets('renders large count', (tester) async {
      await tester.pumpWidget(buildBadge(count: 999));
      expect(find.text('999'), findsOneWidget);
    });
  });
}
