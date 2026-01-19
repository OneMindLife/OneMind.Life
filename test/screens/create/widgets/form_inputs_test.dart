import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/create/widgets/form_inputs.dart';

void main() {
  group('NumberInput', () {
    testWidgets('displays label and value', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberInput(
              label: 'Test Label',
              value: 5,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Test Label'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
    });

    testWidgets('increment button increases value', (tester) async {
      int currentValue = 5;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return NumberInput(
                  label: 'Count',
                  value: currentValue,
                  onChanged: (v) => setState(() => currentValue = v),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.add));
      await tester.pump();

      expect(currentValue, 6);
    });

    testWidgets('decrement button decreases value', (tester) async {
      int currentValue = 5;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return NumberInput(
                  label: 'Count',
                  value: currentValue,
                  onChanged: (v) => setState(() => currentValue = v),
                );
              },
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.remove));
      await tester.pump();

      expect(currentValue, 4);
    });

    testWidgets('decrement disabled at min value', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberInput(
              label: 'Count',
              value: 1,
              min: 1,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      final decrementButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.remove),
      );
      expect(decrementButton.onPressed, isNull);
    });

    testWidgets('increment disabled at max value', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: NumberInput(
              label: 'Count',
              value: 100,
              max: 100,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      final incrementButton = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.add),
      );
      expect(incrementButton.onPressed, isNull);
    });
  });

  group('LabeledSlider', () {
    testWidgets('displays label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LabeledSlider(
              label: 'Threshold',
              value: 50,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Threshold'), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
    });

    testWidgets('slider shows current value', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LabeledSlider(
              label: 'Progress',
              value: 75,
              min: 0,
              max: 100,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, 75);
    });

    testWidgets('clamps value to min/max range', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LabeledSlider(
              label: 'Clamped',
              value: 150, // Above max
              min: 0,
              max: 100,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      final slider = tester.widget<Slider>(find.byType(Slider));
      expect(slider.value, 100); // Clamped to max
    });
  });

  group('DurationDropdown', () {
    testWidgets('displays label', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DurationDropdown(
              label: 'Duration',
              value: 3600,
              onChanged: (_) {},
              isMin: false,
            ),
          ),
        ),
      );

      expect(find.text('Duration'), findsOneWidget);
    });

    testWidgets('shows min duration options when isMin is true', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DurationDropdown(
              label: 'Min Duration',
              value: 60,
              onChanged: (_) {},
              isMin: true,
            ),
          ),
        ),
      );

      // Tap to open dropdown
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();

      // Should see min duration options (may find duplicates due to dropdown overlay)
      // Minimum is 60s (1 min) due to cron job granularity
      expect(find.text('1 min'), findsAtLeastNWidgets(1));
      expect(find.text('2 min'), findsAtLeastNWidgets(1));
      expect(find.text('5 min'), findsAtLeastNWidgets(1));
    });

    testWidgets('shows max duration options when isMin is false', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DurationDropdown(
              label: 'Max Duration',
              value: 86400,
              onChanged: (_) {},
              isMin: false,
            ),
          ),
        ),
      );

      // Tap to open dropdown
      await tester.tap(find.byType(DropdownButtonFormField<int>));
      await tester.pumpAndSettle();

      // Should see max duration options (may find duplicates due to dropdown overlay)
      expect(find.text('1 hour'), findsAtLeastNWidgets(1));
      expect(find.text('1 day'), findsAtLeastNWidgets(1));
    });
  });

  group('SectionHeader', () {
    testWidgets('displays title with correct style', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SectionHeader('Settings'),
          ),
        ),
      );

      expect(find.text('Settings'), findsOneWidget);
    });
  });

  group('TimerPresets', () {
    testWidgets('displays all preset chips including Custom', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimerPresets(
              label: 'Timer',
              selected: '1hour',
              onChanged: (_, __) {},
            ),
          ),
        ),
      );

      expect(find.text('Timer'), findsOneWidget);
      expect(find.text('5 min'), findsOneWidget);
      expect(find.text('30 min'), findsOneWidget);
      expect(find.text('1 hour'), findsOneWidget);
      expect(find.text('1 day'), findsOneWidget);
      expect(find.text('Custom'), findsOneWidget);
    });

    testWidgets('highlights selected preset', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimerPresets(
              label: 'Timer',
              selected: '1day',
              onChanged: (_, __) {},
            ),
          ),
        ),
      );

      // Find the ChoiceChip for '1 day'
      final chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, '1 day'),
      );
      expect(chip.selected, isTrue);
    });

    testWidgets('calls onChanged when chip selected', (tester) async {
      String? selectedPreset;
      int? selectedDuration;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TimerPresets(
              label: 'Timer',
              selected: '1hour',
              onChanged: (preset, duration) {
                selectedPreset = preset;
                selectedDuration = duration;
              },
            ),
          ),
        ),
      );

      await tester.tap(find.text('5 min'));
      expect(selectedPreset, '5min');
      expect(selectedDuration, 300);
    });

    test('presets map has correct values', () {
      expect(TimerPresets.presets['5min'], 300);
      expect(TimerPresets.presets['30min'], 1800);
      expect(TimerPresets.presets['1hour'], 3600);
      expect(TimerPresets.presets['1day'], 86400);
      expect(TimerPresets.presets['custom'], 0); // Placeholder for custom
      expect(TimerPresets.presets.length, 5);
    });
  });
}
