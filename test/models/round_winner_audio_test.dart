import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/round_winner.dart';

void main() {
  group('RoundWinner audio_url', () {
    test('parses audio_url from nested rounds join (Map)', () {
      final json = {
        'id': 1,
        'round_id': 100,
        'proposition_id': 200,
        'rank': 1,
        'global_score': 100.0,
        'created_at': '2026-04-17T00:00:00Z',
        'propositions': {'content': 'Test idea'},
        'rounds': {'audio_url': 'https://example.com/audio.mp3'},
      };

      final winner = RoundWinner.fromJson(json);
      expect(winner.audioUrl, 'https://example.com/audio.mp3');
      expect(winner.content, 'Test idea');
    });

    test('parses audio_url from nested rounds join (List)', () {
      final json = {
        'id': 1,
        'round_id': 100,
        'proposition_id': 200,
        'rank': 1,
        'global_score': 100.0,
        'created_at': '2026-04-17T00:00:00Z',
        'propositions': {'content': 'Test'},
        'rounds': [
          {'audio_url': 'https://example.com/a.mp3'},
        ],
      };

      final winner = RoundWinner.fromJson(json);
      expect(winner.audioUrl, 'https://example.com/a.mp3');
    });

    test('parses audio_url from flat key when rounds join missing', () {
      final json = {
        'id': 1,
        'round_id': 100,
        'proposition_id': 200,
        'rank': 1,
        'global_score': 100.0,
        'created_at': '2026-04-17T00:00:00Z',
        'propositions': {'content': 'Test'},
        'audio_url': 'https://example.com/flat.mp3',
      };

      final winner = RoundWinner.fromJson(json);
      expect(winner.audioUrl, 'https://example.com/flat.mp3');
    });

    test('audio_url is null when not provided', () {
      final json = {
        'id': 1,
        'round_id': 100,
        'proposition_id': 200,
        'rank': 1,
        'global_score': 100.0,
        'created_at': '2026-04-17T00:00:00Z',
        'propositions': {'content': 'Test'},
      };

      final winner = RoundWinner.fromJson(json);
      expect(winner.audioUrl, isNull);
    });

    test('copyWith preserves audio_url by default', () {
      final winner = RoundWinner(
        id: 1,
        roundId: 100,
        propositionId: 200,
        rank: 1,
        createdAt: DateTime.parse('2026-04-17T00:00:00Z'),
        audioUrl: 'https://example.com/original.mp3',
      );

      final copy = winner.copyWith(contentTranslated: 'Translated');
      expect(copy.audioUrl, 'https://example.com/original.mp3');
    });

    test('copyWith updates audio_url when provided', () {
      final winner = RoundWinner(
        id: 1,
        roundId: 100,
        propositionId: 200,
        rank: 1,
        createdAt: DateTime.parse('2026-04-17T00:00:00Z'),
        audioUrl: 'https://example.com/original.mp3',
      );

      final copy = winner.copyWith(audioUrl: 'https://example.com/new.mp3');
      expect(copy.audioUrl, 'https://example.com/new.mp3');
    });

    test('audio_url is part of equality', () {
      final w1 = RoundWinner(
        id: 1,
        roundId: 100,
        propositionId: 200,
        rank: 1,
        createdAt: DateTime.parse('2026-04-17T00:00:00Z'),
        audioUrl: 'https://example.com/a.mp3',
      );

      final w2 = RoundWinner(
        id: 1,
        roundId: 100,
        propositionId: 200,
        rank: 1,
        createdAt: DateTime.parse('2026-04-17T00:00:00Z'),
        audioUrl: 'https://example.com/b.mp3',
      );

      expect(w1, isNot(equals(w2)));
    });
  });
}
