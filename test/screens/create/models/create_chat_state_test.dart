import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/create/models/create_chat_state.dart';

void main() {
  group('TimerSettings', () {
    test('defaults() returns correct default values', () {
      final settings = TimerSettings.defaults();

      expect(settings.proposingPreset, '1day');
      expect(settings.ratingPreset, '1day');
      expect(settings.proposingDuration, 86400);
      expect(settings.ratingDuration, 86400);
    });

    test('copyWith updates specified fields only', () {
      final settings = TimerSettings.defaults();
      final updated = settings.copyWith(proposingPreset: '5min');

      expect(updated.proposingPreset, '5min');
      expect(updated.ratingPreset, settings.ratingPreset);
      expect(updated.proposingDuration, settings.proposingDuration);
      expect(updated.ratingDuration, settings.ratingDuration);
    });

    test('copyWith updates multiple fields', () {
      final settings = TimerSettings.defaults();
      final updated = settings.copyWith(
        proposingPreset: '30min',
        proposingDuration: 1800,
        ratingPreset: '1hour',
        ratingDuration: 3600,
      );

      expect(updated.proposingPreset, '30min');
      expect(updated.proposingDuration, 1800);
      expect(updated.ratingPreset, '1hour');
      expect(updated.ratingDuration, 3600);
    });
  });

  group('MinimumSettings', () {
    test('defaults() returns correct default values', () {
      final settings = MinimumSettings.defaults();

      // proposingMinimum is 3 because users can't rate their own propositions,
      // so need at least 3 total for each user to see 2+ to rank
      expect(settings.proposingMinimum, 3);
      expect(settings.ratingMinimum, 2);
    });

    test('copyWith updates specified fields only', () {
      final settings = MinimumSettings.defaults();
      final updated = settings.copyWith(proposingMinimum: 5);

      expect(updated.proposingMinimum, 5);
      expect(updated.ratingMinimum, settings.ratingMinimum);
    });

    test('copyWith preserves values when null passed', () {
      final settings = const MinimumSettings(
        proposingMinimum: 10,
        ratingMinimum: 15,
      );
      final updated = settings.copyWith();

      expect(updated.proposingMinimum, 10);
      expect(updated.ratingMinimum, 15);
    });
  });

  group('AutoAdvanceSettings', () {
    test('defaults() returns correct default values', () {
      final settings = AutoAdvanceSettings.defaults();

      // Smart defaults: 100% participation triggers early advance
      expect(settings.enableProposing, true);
      expect(settings.proposingThresholdPercent, 100);
      expect(settings.proposingThresholdCount, 3);
      expect(settings.enableRating, true);
      expect(settings.ratingThresholdPercent, 100);
      expect(settings.ratingThresholdCount, 2);
    });

    test('copyWith updates specified fields only', () {
      final settings = AutoAdvanceSettings.defaults();
      final updated = settings.copyWith(enableProposing: false);

      expect(updated.enableProposing, false);
      expect(updated.proposingThresholdPercent, settings.proposingThresholdPercent);
      expect(updated.proposingThresholdCount, settings.proposingThresholdCount);
      expect(updated.enableRating, settings.enableRating);
    });

    test('copyWith updates multiple fields', () {
      final settings = AutoAdvanceSettings.defaults();
      final updated = settings.copyWith(
        enableProposing: false,
        proposingThresholdPercent: 60,
        enableRating: false,
        ratingThresholdCount: 10,
      );

      expect(updated.enableProposing, false);
      expect(updated.proposingThresholdPercent, 60);
      expect(updated.enableRating, false);
      expect(updated.ratingThresholdCount, 10);
    });
  });

  group('AdaptiveDurationSettings', () {
    test('defaults() returns correct default values', () {
      final settings = AdaptiveDurationSettings.defaults();

      expect(settings.enabled, false);
      expect(settings.adjustmentPercent, 10);
      expect(settings.minDurationSeconds, 60);
      expect(settings.maxDurationSeconds, 86400);
    });

    test('copyWith updates specified fields only', () {
      final settings = AdaptiveDurationSettings.defaults();
      final updated = settings.copyWith(enabled: true);

      expect(updated.enabled, true);
      expect(updated.adjustmentPercent, settings.adjustmentPercent);
      expect(updated.minDurationSeconds, settings.minDurationSeconds);
      expect(updated.maxDurationSeconds, settings.maxDurationSeconds);
    });

    test('copyWith updates all fields', () {
      final settings = AdaptiveDurationSettings.defaults();
      final updated = settings.copyWith(
        enabled: true,
        adjustmentPercent: 25,
        minDurationSeconds: 300,
        maxDurationSeconds: 7200,
      );

      expect(updated.enabled, true);
      expect(updated.adjustmentPercent, 25);
      expect(updated.minDurationSeconds, 300);
      expect(updated.maxDurationSeconds, 7200);
    });
  });

  group('AISettings', () {
    test('defaults() returns correct default values', () {
      final settings = AISettings.defaults();

      // AI proposer retired - always disabled
      expect(settings.enabled, false);
      expect(settings.propositionCount, 1);
    });

    test('copyWith updates specified fields only', () {
      final settings = AISettings.defaults();
      final updated = settings.copyWith(enabled: true);

      expect(updated.enabled, true);
      expect(updated.propositionCount, settings.propositionCount);
    });

    test('copyWith updates both fields', () {
      final settings = AISettings.defaults();
      final updated = settings.copyWith(
        enabled: true,
        propositionCount: 5,
      );

      expect(updated.enabled, true);
      expect(updated.propositionCount, 5);
    });
  });

  group('AgentConfig', () {
    test('creates with required name and empty personality', () {
      const config = AgentConfig(name: 'Agent 1');
      expect(config.name, 'Agent 1');
      expect(config.personality, '');
    });

    test('creates with name and personality', () {
      const config = AgentConfig(name: 'My Agent', personality: 'Focus on cost');
      expect(config.name, 'My Agent');
      expect(config.personality, 'Focus on cost');
    });

    test('copyWith updates name only', () {
      const config = AgentConfig(name: 'Agent 1', personality: 'Be skeptical');
      final updated = config.copyWith(name: 'Custom Name');
      expect(updated.name, 'Custom Name');
      expect(updated.personality, 'Be skeptical');
    });

    test('copyWith updates personality only', () {
      const config = AgentConfig(name: 'Agent 1');
      final updated = config.copyWith(personality: 'Focus on data');
      expect(updated.name, 'Agent 1');
      expect(updated.personality, 'Focus on data');
    });

    test('toJson returns correct map', () {
      const config = AgentConfig(name: 'Agent 1', personality: 'Be practical');
      final json = config.toJson();
      expect(json, {'name': 'Agent 1', 'personality': 'Be practical'});
    });

    test('equality works correctly', () {
      const a = AgentConfig(name: 'Agent 1', personality: 'Test');
      const b = AgentConfig(name: 'Agent 1', personality: 'Test');
      const c = AgentConfig(name: 'Agent 2', personality: 'Test');
      expect(a, equals(b));
      expect(a, isNot(equals(c)));
    });
  });

  group('AgentSettings', () {
    test('defaults() returns correct default values', () {
      final settings = AgentSettings.defaults();
      expect(settings.enabled, false);
      expect(settings.customizeIndividually, false);
      expect(settings.agentsAlsoRate, true);
      expect(settings.agentCount, 1);
      expect(settings.sharedInstructions, '');
      expect(settings.agents.length, 1);
      expect(settings.agents[0].name, 'Agent 1');
    });

    test('copyWith updates enabled only', () {
      final settings = AgentSettings.defaults();
      final updated = settings.copyWith(enabled: true);
      expect(updated.enabled, true);
      expect(updated.customizeIndividually, false);
      expect(updated.agentCount, 1);
    });

    test('copyWith updates sharedInstructions', () {
      final settings = AgentSettings.defaults();
      final updated = settings.copyWith(sharedInstructions: 'Focus on cost');
      expect(updated.sharedInstructions, 'Focus on cost');
    });

    test('withCount grows agents list', () {
      final settings = AgentSettings.defaults(); // 3 agents
      final updated = settings.withCount(5);
      expect(updated.agentCount, 5);
      expect(updated.agents.length, 5);
      // Original agents preserved
      expect(updated.agents[0].name, 'Agent 1');
      expect(updated.agents[1].name, 'Agent 2');
      expect(updated.agents[2].name, 'Agent 3');
      // New agents auto-named
      expect(updated.agents[3].name, 'Agent 4');
      expect(updated.agents[4].name, 'Agent 5');
    });

    test('withCount shrinks agents list', () {
      final settings = AgentSettings.defaults(); // 3 agents
      final updated = settings.withCount(1);
      expect(updated.agentCount, 1);
      expect(updated.agents.length, 1);
      expect(updated.agents[0].name, 'Agent 1');
    });

    test('withCount preserves customized agents when growing', () {
      final settings = AgentSettings.defaults().copyWith(
        agents: [
          const AgentConfig(name: 'Custom', personality: 'Be bold'),
          const AgentConfig(name: 'Agent 2'),
          const AgentConfig(name: 'Agent 3'),
        ],
      );
      final updated = settings.withCount(4);
      expect(updated.agents[0].name, 'Custom');
      expect(updated.agents[0].personality, 'Be bold');
      expect(updated.agents[3].name, 'Agent 4');
    });

    test('withCount clamps to valid range', () {
      final settings = AgentSettings.defaults();
      final tooLow = settings.withCount(0);
      expect(tooLow.agentCount, 1);

      final tooHigh = settings.withCount(10);
      expect(tooHigh.agentCount, 5);
    });

    test('equality works correctly', () {
      final a = AgentSettings.defaults();
      final b = AgentSettings.defaults();
      expect(a, equals(b));

      final c = a.copyWith(enabled: true);
      expect(a, isNot(equals(c)));
    });
  });

  group('ConsensusSettings', () {
    test('defaults() returns correct default values', () {
      final settings = ConsensusSettings.defaults();

      expect(settings.confirmationRoundsRequired, 2);
      expect(settings.showPreviousResults, true);
      expect(settings.propositionsPerUser, 1);
    });

    test('copyWith updates specified fields only', () {
      final settings = ConsensusSettings.defaults();
      final updated = settings.copyWith(confirmationRoundsRequired: 3);

      expect(updated.confirmationRoundsRequired, 3);
      expect(updated.showPreviousResults, settings.showPreviousResults);
      expect(updated.propositionsPerUser, settings.propositionsPerUser);
    });

    test('copyWith updates all fields', () {
      final settings = ConsensusSettings.defaults();
      final updated = settings.copyWith(
        confirmationRoundsRequired: 5,
        showPreviousResults: true,
        propositionsPerUser: 3,
      );

      expect(updated.confirmationRoundsRequired, 5);
      expect(updated.showPreviousResults, true);
      expect(updated.propositionsPerUser, 3);
    });
  });

  group('ScheduleSettings', () {
    test('defaults() returns correct default values', () {
      final settings = ScheduleSettings.defaults();

      expect(settings.type, ScheduleType.once);
      expect(settings.scheduledStartAt, isA<DateTime>());
      // Windows are empty by default - user adds them if switching to recurring
      expect(settings.windows, isEmpty);
      expect(settings.timezone, 'America/New_York');
      expect(settings.visibleOutsideSchedule, true);
    });

    test('defaults() scheduledStartAt is in the future', () {
      final settings = ScheduleSettings.defaults();
      expect(settings.scheduledStartAt.isAfter(DateTime.now()), isTrue);
    });

    test('copyWith updates specified fields only', () {
      final settings = ScheduleSettings.defaults();
      final updated = settings.copyWith(type: ScheduleType.recurring);

      expect(updated.type, ScheduleType.recurring);
      expect(updated.windows, settings.windows);
      expect(updated.timezone, settings.timezone);
    });

    test('copyWith updates multiple fields', () {
      final settings = ScheduleSettings.defaults();
      final newWindows = [
        const ScheduleWindow(
          startDay: 'monday',
          startTime: TimeOfDay(hour: 14, minute: 30),
          endDay: 'monday',
          endTime: TimeOfDay(hour: 16, minute: 0),
        ),
        const ScheduleWindow(
          startDay: 'friday',
          startTime: TimeOfDay(hour: 14, minute: 30),
          endDay: 'friday',
          endTime: TimeOfDay(hour: 16, minute: 0),
        ),
      ];

      final updated = settings.copyWith(
        type: ScheduleType.recurring,
        windows: newWindows,
        timezone: 'Europe/London',
        visibleOutsideSchedule: false,
      );

      expect(updated.type, ScheduleType.recurring);
      expect(updated.windows.length, 2);
      expect(updated.windows[0].startDay, 'monday');
      expect(updated.windows[1].startDay, 'friday');
      expect(updated.timezone, 'Europe/London');
      expect(updated.visibleOutsideSchedule, false);
    });

    test('copyWith updates scheduledStartAt', () {
      final settings = ScheduleSettings.defaults();
      final newDate = DateTime(2025, 6, 15, 12, 0);
      final updated = settings.copyWith(scheduledStartAt: newDate);

      expect(updated.scheduledStartAt, newDate);
    });
  });

  group('ScheduleType enum', () {
    test('has correct values', () {
      expect(ScheduleType.values.length, 2);
      expect(ScheduleType.values.contains(ScheduleType.once), isTrue);
      expect(ScheduleType.values.contains(ScheduleType.recurring), isTrue);
    });
  });
}
