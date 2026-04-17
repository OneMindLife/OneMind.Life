import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/models.dart';
import 'package:onemind_app/screens/tutorial/tutorial_data.dart';

void main() {
  group('TutorialTemplate', () {
    test('getTemplate returns saturday for default key', () {
      final template = TutorialTemplate.getTemplate(TutorialTemplate.defaultKey);
      expect(template.key, 'saturday');
      expect(template.question, "What's the best way to spend a free Saturday?");
      expect(template.chatName, 'Saturday Plans');
    });

    test('getTemplate returns classic for classic key', () {
      final template = TutorialTemplate.getTemplate('classic');
      expect(template.key, 'classic');
      expect(template.question, 'What do we value?');
      expect(template.chatName, 'Values');
    });

    test('getTemplate falls back to saturday for unknown key', () {
      final template = TutorialTemplate.getTemplate('nonexistent');
      expect(template.key, 'saturday');
    });

    test('getTemplate falls back to saturday for null key', () {
      final template = TutorialTemplate.getTemplate(null);
      expect(template.key, 'saturday');
    });

    test('defaultKey is saturday', () {
      expect(TutorialTemplate.defaultKey, 'saturday');
    });

    test('saturday template has correct round propositions', () {
      final t = TutorialTemplate.templates['saturday']!;
      expect(t.round1Props, ['Movie Night', 'Cook-off', 'Board Games']);
      expect(t.round1Winner, 'Movie Night');
      expect(t.round2Props, ['Karaoke', 'Potluck Dinner', 'Movie Night', 'Board Games']);
      expect(t.round3Props, ['DIY Craft Night', 'Trivia Night', 'Video Game Tournament']);
    });

    test('classic template has correct round propositions', () {
      final t = TutorialTemplate.templates['classic']!;
      expect(t.round1Props, ['Success', 'Adventure', 'Growth']);
      expect(t.round1Winner, 'Success');
      expect(t.round2Props, ['Harmony', 'Innovation', 'Success']);
      expect(t.round3Props, ['Freedom', 'Security', 'Stability']);
    });

    test('all templates have matching round1Winner in round1Props', () {
      for (final entry in TutorialTemplate.templates.entries) {
        final t = entry.value;
        expect(t.round1Props, contains(t.round1Winner),
            reason: '${entry.key} template round1Winner should be in round1Props');
      }
    });

    test('all templates have required icon', () {
      for (final t in TutorialTemplate.templates.values) {
        expect(t.icon, isA<IconData>());
      }
    });

    test('all templates have non-empty props for each round', () {
      for (final entry in TutorialTemplate.templates.entries) {
        final t = entry.value;
        expect(t.round1Props, isNotEmpty,
            reason: '${entry.key} round1Props should not be empty');
        expect(t.round2Props, isNotEmpty,
            reason: '${entry.key} round2Props should not be empty');
        expect(t.round3Props, isNotEmpty,
            reason: '${entry.key} round3Props should not be empty');
      }
    });
  });

  group('TutorialData', () {
    group('mock models', () {
      test('tutorialChat has negative ID', () {
        final chat = TutorialData.tutorialChat;
        expect(chat.id, -1);
        expect(chat.name, 'Saturday Plans');
        expect(chat.inviteCode, 'ABC123');
      });

      test('tutorialParticipant is the user host', () {
        final p = TutorialData.tutorialParticipant;
        expect(p.id, -1);
        expect(p.userId, 'tutorial-user');
        expect(p.displayName, 'You');
        expect(p.isHost, true);
      });

      test('otherParticipants has 3 NPCs', () {
        final others = TutorialData.otherParticipants;
        expect(others.length, 3);
        expect(others.map((p) => p.displayName), ['Alex', 'Sam', 'Jordan']);
        expect(others.every((p) => !p.isHost), true);
        expect(others.every((p) => p.id < 0), true);
      });

      test('allParticipants has user + 3 NPCs = 4 total', () {
        final all = TutorialData.allParticipants;
        expect(all.length, 4);
        expect(all.first.displayName, 'You');
      });
    });

    group('rounds', () {
      test('round1 defaults to proposing phase', () {
        final round = TutorialData.round1();
        expect(round.id, -1);
        expect(round.customId, 1);
        expect(round.phase, RoundPhase.proposing);
      });

      test('round1 can be created with rating phase', () {
        final round = TutorialData.round1(phase: RoundPhase.rating);
        expect(round.phase, RoundPhase.rating);
      });

      test('round2 has correct IDs', () {
        final round = TutorialData.round2();
        expect(round.id, -2);
        expect(round.customId, 2);
      });

      test('round3 has correct IDs', () {
        final round = TutorialData.round3();
        expect(round.id, -3);
        expect(round.customId, 3);
      });

      test('all rounds have 5-minute deadline', () {
        final before = DateTime.now();
        final round = TutorialData.round1();
        final after = DateTime.now();

        // phaseEndsAt should be ~5 minutes from now
        expect(round.phaseEndsAt, isNotNull);
        expect(round.phaseEndsAt!.isAfter(before.add(const Duration(minutes: 4, seconds: 59))), true);
        expect(round.phaseEndsAt!.isBefore(after.add(const Duration(minutes: 5, seconds: 1))), true);
      });
    });

    group('template-aware props', () {
      test('round1Props returns saturday props for null template', () {
        expect(TutorialData.round1Props(null), ['Movie Night', 'Cook-off', 'Board Games']);
      });

      test('round1Props returns saturday props for saturday key', () {
        expect(TutorialData.round1Props('saturday'), ['Movie Night', 'Cook-off', 'Board Games']);
      });

      test('round1Props returns classic props for classic key', () {
        expect(TutorialData.round1Props('classic'), ['Success', 'Adventure', 'Growth']);
      });

      test('round2Props returns correct props', () {
        expect(TutorialData.round2Props('saturday'),
            ['Karaoke', 'Potluck Dinner', 'Movie Night', 'Board Games']);
      });

      test('round3Props returns correct props', () {
        expect(TutorialData.round3Props('saturday'),
            ['DIY Craft Night', 'Trivia Night', 'Video Game Tournament']);
      });
    });

    group('createPropositions', () {
      test('creates propositions from contents with user prop', () {
        final props = TutorialData.createPropositions(
          ['A', 'B', 'C'],
          userProposition: 'User Idea',
        );
        expect(props.length, 4); // 3 NPC + 1 user
        expect(props.last.content, 'User Idea');
        expect(props.last.participantId, -1); // User
      });

      test('creates propositions without user prop when null', () {
        final props = TutorialData.createPropositions(
          ['A', 'B'],
          userProposition: null,
        );
        expect(props.length, 2);
      });

      test('creates propositions without user prop when includeUserProp is false', () {
        final props = TutorialData.createPropositions(
          ['A', 'B'],
          userProposition: 'User',
          includeUserProp: false,
        );
        expect(props.length, 2);
      });

      test('marks carried forward proposition correctly', () {
        final props = TutorialData.createPropositions(
          ['A', 'B', 'C'],
          carriedPropIndex: 1,
          carriedFromId: -50,
        );
        expect(props[0].carriedFromId, isNull);
        expect(props[1].carriedFromId, -50);
        expect(props[2].carriedFromId, isNull);
      });

      test('uses specified roundId', () {
        final props = TutorialData.createPropositions(
          ['A'],
          roundId: -5,
        );
        expect(props.first.roundId, -5);
      });

      test('assigns negative IDs starting from -100', () {
        final props = TutorialData.createPropositions(['A', 'B', 'C']);
        expect(props[0].id, -100);
        expect(props[1].id, -101);
        expect(props[2].id, -102);
      });
    });

    group('propositionsForRating', () {
      test('converts propositions to rating format', () {
        final props = [
          Proposition(
            id: -100,
            roundId: -1,
            participantId: -2,
            content: 'Test',
            createdAt: DateTime.now(),
          ),
        ];
        final rating = TutorialData.propositionsForRating(props);
        expect(rating.length, 1);
        expect(rating.first['id'], -100);
        expect(rating.first['content'], 'Test');
      });
    });

    group('winners', () {
      test('round1Winner uses template winner', () {
        final winner = TutorialData.round1Winner();
        expect(winner.content, 'Movie Night');
        expect(winner.rank, 1);
      });

      test('round1Winner uses classic template when specified', () {
        final winner = TutorialData.round1Winner(templateKey: 'classic');
        expect(winner.content, 'Success');
      });

      test('round1TiedWinner uses second prop', () {
        final tied = TutorialData.round1TiedWinner();
        expect(tied.content, 'Cook-off');
        expect(tied.rank, 1);
      });

      test('round2Winner uses user proposition', () {
        final winner = TutorialData.round2Winner('My Great Idea');
        expect(winner.content, 'My Great Idea');
      });

      test('round3Winner uses user proposition for consensus', () {
        final winner = TutorialData.round3Winner('My Great Idea');
        expect(winner.content, 'My Great Idea');
      });

      test('consensusProposition creates proposition with user content', () {
        final prop = TutorialData.consensusProposition('Winning Idea');
        expect(prop.content, 'Winning Idea');
        expect(prop.participantId, -1); // User
        expect(prop.id, -999);
      });
    });

    group('round1ResultsWithRatings', () {
      test('returns 4 propositions (3 NPC + 1 user)', () {
        final results = TutorialData.round1ResultsWithRatings('My Idea');
        expect(results.length, 4);
      });

      test('winner gets rating 100', () {
        final results = TutorialData.round1ResultsWithRatings('My Idea');
        final winner = results.firstWhere((p) => p.content == 'Movie Night');
        expect(winner.finalRating, 100.0);
      });

      test('user prop gets rating 0 (lowest)', () {
        final results = TutorialData.round1ResultsWithRatings('My Idea');
        final userProp = results.firstWhere((p) => p.content == 'My Idea');
        expect(userProp.finalRating, 0.0);
        expect(userProp.participantId, -1);
      });

      test('non-winner NPC props get descending scores', () {
        final results = TutorialData.round1ResultsWithRatings('My Idea');
        final npcNonWinners = results
            .where((p) => p.content != 'Movie Night' && p.content != 'My Idea')
            .toList();
        expect(npcNonWinners.length, 2);
        // Scores should be 58 and 33
        final ratings = npcNonWinners.map((p) => p.finalRating).toList()..sort();
        expect(ratings, [33.0, 58.0]);
      });

      test('uses classic template when specified', () {
        final results = TutorialData.round1ResultsWithRatings(
          'My Idea',
          templateKey: 'classic',
        );
        final winner = results.firstWhere((p) => p.finalRating == 100.0);
        expect(winner.content, 'Success');
      });
    });

    group('round2ResultsWithRatings', () {
      test('user prop wins with rating 100', () {
        final results = TutorialData.round2ResultsWithRatings('Bowling');
        expect(results.first.content, 'Bowling');
        expect(results.first.finalRating, 100.0);
        expect(results.first.participantId, -1);
      });

      test('R1 winner carried forward gets 75', () {
        final results = TutorialData.round2ResultsWithRatings('Bowling');
        final carried = results.firstWhere((p) => p.content == 'Movie Night');
        expect(carried.finalRating, 75.0);
      });

      test('returns 5 propositions total', () {
        final results = TutorialData.round2ResultsWithRatings('Bowling');
        expect(results.length, 5);
      });

      test('ratings are in descending order', () {
        final results = TutorialData.round2ResultsWithRatings('Bowling');
        final ratings = results.map((p) => p.finalRating!).toList();
        for (var i = 0; i < ratings.length - 1; i++) {
          expect(ratings[i], greaterThanOrEqualTo(ratings[i + 1]));
        }
      });
    });

    group('round3ResultsWithRatings', () {
      test('user carried forward prop wins again (consensus)', () {
        final results = TutorialData.round3ResultsWithRatings('Bowling');
        expect(results.first.content, 'Bowling');
        expect(results.first.finalRating, 100.0);
      });

      test('without R3 submission has 4 props', () {
        final results = TutorialData.round3ResultsWithRatings('Bowling');
        expect(results.length, 4); // carried + 3 NPC
      });

      test('with R3 submission has 5 props', () {
        final results = TutorialData.round3ResultsWithRatings(
          'Bowling',
          userR3Proposition: 'New Idea',
        );
        expect(results.length, 5);
        final userNew = results.firstWhere((p) => p.content == 'New Idea');
        expect(userNew.finalRating, 75.0);
      });

      test('NPC ratings differ based on user R3 submission presence', () {
        final withoutR3 = TutorialData.round3ResultsWithRatings('Bowling');
        final withR3 = TutorialData.round3ResultsWithRatings(
          'Bowling',
          userR3Proposition: 'New Idea',
        );

        // Without R3: NPC ratings are 67, 33, 0
        final npcWithout = withoutR3.where((p) => p.participantId != -1).toList();
        final ratingsWithout = npcWithout.map((p) => p.finalRating).toList()..sort();
        expect(ratingsWithout, [0.0, 33.0, 67.0]);

        // With R3: NPC ratings are 50, 25, 0
        final npcWith = withR3.where((p) => p.participantId != -1).toList();
        final ratingsWith = npcWith.map((p) => p.finalRating).toList()..sort();
        expect(ratingsWith, [0.0, 25.0, 50.0]);
      });
    });

    group('static constants', () {
      test('demoInviteCode is ABC123', () {
        expect(TutorialData.demoInviteCode, 'ABC123');
      });

      test('question matches default template', () {
        expect(TutorialData.question, TutorialTemplate.templates['saturday']!.question);
      });

      test('chatName matches default template', () {
        expect(TutorialData.chatName, TutorialTemplate.templates['saturday']!.chatName);
      });

      test('questionForTemplate returns correct questions', () {
        expect(TutorialData.questionForTemplate('saturday'),
            "What's the best way to spend a free Saturday?");
        expect(TutorialData.questionForTemplate('classic'),
            'What do we value?');
        expect(TutorialData.questionForTemplate(null),
            "What's the best way to spend a free Saturday?");
      });

      test('chatNameForTemplate returns correct names', () {
        expect(TutorialData.chatNameForTemplate('saturday'), 'Saturday Plans');
        expect(TutorialData.chatNameForTemplate('classic'), 'Values');
      });
    });

    group('legacy propositions', () {
      test('round1Propositions has 3 items', () {
        expect(TutorialData.round1Propositions.length, 3);
        expect(TutorialData.round1Propositions.first.content, 'Movie Night');
      });

      test('round2Propositions has carried forward item', () {
        final carried = TutorialData.round2Propositions
            .where((p) => p.isCarriedForward)
            .toList();
        expect(carried.length, 1);
        expect(carried.first.content, 'Movie Night');
      });

      test('round3Propositions has 3 items', () {
        expect(TutorialData.round3Propositions.length, 3);
      });
    });
  });
}
