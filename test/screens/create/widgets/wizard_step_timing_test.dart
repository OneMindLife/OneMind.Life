import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/screens/create/models/create_chat_state.dart'
    as state;
import 'package:onemind_app/screens/create/widgets/wizard_step_timing.dart';

void main() {
  Widget harness({
    int proposingDuration = 43200,
    int? ratingDuration,
    void Function(state.TimerSettings)? onChanged,
  }) {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: Scaffold(
        body: WizardStepTiming(
          timerSettings: state.TimerSettings(
            useSameDuration: ratingDuration == null,
            proposingPreset: 'custom',
            ratingPreset: 'custom',
            proposingDuration: proposingDuration,
            ratingDuration: ratingDuration ?? proposingDuration,
          ),
          onTimerSettingsChanged: onChanged ?? (_) {},
          onContinue: () {},
        ),
      ),
    );
  }

  group('timing step', () {
    testWidgets('shows duration presets and the same-duration toggle',
        (tester) async {
      await tester.pumpWidget(harness());
      expect(find.text('How long for proposing?'), findsOneWidget);
      expect(find.text('Same duration for rating phase?'), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
    });

    testWidgets(
        'the cadence anchor does NOT live here — it has its own step now',
        (tester) async {
      await tester.pumpWidget(harness());
      expect(find.text('First deadline'), findsNothing);
      expect(find.text('When should the first phase end?'), findsNothing);
      expect(find.text('3 AM / 3 PM rhythm'), findsNothing);
    });

    testWidgets('separate rating duration section appears when toggled off',
        (tester) async {
      await tester.pumpWidget(
          harness(proposingDuration: 43200, ratingDuration: 86400));
      expect(find.text('How long for rating?'), findsOneWidget);
    });
  });
}
