import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/round_winner.dart';

void main() {
  group('RoundWinner video_url', () {
    test('parses video_url from nested rounds join (Map)', () {
      final json = {
        'id': 1,
        'round_id': 100,
        'proposition_id': 200,
        'rank': 1,
        'created_at': '2026-04-17T00:00:00Z',
        'propositions': {'content': 'Test'},
        'rounds': {
          'audio_url': 'https://example.com/a.mp3',
          'video_url': 'https://example.com/v.mp4',
        },
      };

      final winner = RoundWinner.fromJson(json);
      expect(winner.videoUrl, 'https://example.com/v.mp4');
      expect(winner.audioUrl, 'https://example.com/a.mp3');
    });

    test('parses video_url from nested rounds join (List)', () {
      final json = {
        'id': 1,
        'round_id': 100,
        'proposition_id': 200,
        'rank': 1,
        'created_at': '2026-04-17T00:00:00Z',
        'propositions': {'content': 'Test'},
        'rounds': [
          {'video_url': 'https://example.com/v.mp4'},
        ],
      };

      final winner = RoundWinner.fromJson(json);
      expect(winner.videoUrl, 'https://example.com/v.mp4');
    });

    test('parses video_url from flat key when rounds join missing', () {
      final json = {
        'id': 1,
        'round_id': 100,
        'proposition_id': 200,
        'rank': 1,
        'created_at': '2026-04-17T00:00:00Z',
        'propositions': {'content': 'Test'},
        'video_url': 'https://example.com/flat.mp4',
      };

      final winner = RoundWinner.fromJson(json);
      expect(winner.videoUrl, 'https://example.com/flat.mp4');
    });

    test('video_url is null when not provided', () {
      final json = {
        'id': 1,
        'round_id': 100,
        'proposition_id': 200,
        'rank': 1,
        'created_at': '2026-04-17T00:00:00Z',
        'propositions': {'content': 'Test'},
      };

      final winner = RoundWinner.fromJson(json);
      expect(winner.videoUrl, isNull);
    });

    test('copyWith preserves video_url by default', () {
      final winner = RoundWinner(
        id: 1,
        roundId: 100,
        propositionId: 200,
        rank: 1,
        createdAt: DateTime.parse('2026-04-17T00:00:00Z'),
        videoUrl: 'https://example.com/original.mp4',
      );

      final copy = winner.copyWith(contentTranslated: 'Translated');
      expect(copy.videoUrl, 'https://example.com/original.mp4');
    });

    test('copyWith updates video_url when provided', () {
      final winner = RoundWinner(
        id: 1,
        roundId: 100,
        propositionId: 200,
        rank: 1,
        createdAt: DateTime.parse('2026-04-17T00:00:00Z'),
        videoUrl: 'https://example.com/original.mp4',
      );

      final copy = winner.copyWith(videoUrl: 'https://example.com/new.mp4');
      expect(copy.videoUrl, 'https://example.com/new.mp4');
    });

    test('video_url is part of equality', () {
      final w1 = RoundWinner(
        id: 1,
        roundId: 100,
        propositionId: 200,
        rank: 1,
        createdAt: DateTime.parse('2026-04-17T00:00:00Z'),
        videoUrl: 'https://example.com/a.mp4',
      );

      final w2 = RoundWinner(
        id: 1,
        roundId: 100,
        propositionId: 200,
        rank: 1,
        createdAt: DateTime.parse('2026-04-17T00:00:00Z'),
        videoUrl: 'https://example.com/b.mp4',
      );

      expect(w1, isNot(equals(w2)));
    });
  });
}
