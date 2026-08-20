import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/screens/chat/widgets/tree_stack_section.dart';
import 'package:onemind_app/services/matches/match_pair_selector.dart';

/// Unit tests for the similar-props fuzzy matcher that filters the proposing
/// feed while the user types (duplicate awareness before submitting).
void main() {
  Map<String, dynamic> prop(int id, String content) =>
      {'id': id, 'content': content};

  List<int> ids(List<Map<String, dynamic>> result) =>
      result.map((p) => p['id'] as int).toList();

  group('similarProps', () {
    final board = [
      prop(1, 'Pizza night with the team'),
      prop(2, 'Go hiking on Saturday'),
      prop(3, 'Order pizza and watch a movie'),
      prop(4, 'Weekly game night'),
    ];

    test('empty query matches nothing', () {
      expect(similarProps(board, ''), isEmpty);
      expect(similarProps(board, '   '), isEmpty);
    });

    test('token match finds the overlapping takes only', () {
      final result = similarProps(board, 'pizza');
      expect(ids(result), containsAll([1, 3]));
      expect(ids(result), isNot(contains(2)));
      expect(ids(result), isNot(contains(4)));
    });

    test('whole-phrase containment ranks above scattered token overlap', () {
      // "game night" is contained verbatim in 4; 1 only shares "night".
      final result = similarProps(board, 'game night');
      expect(ids(result).first, 4);
      expect(ids(result), contains(1));
    });

    test('is case- and punctuation-insensitive', () {
      final result = similarProps(board, 'PIZZA!!!');
      expect(ids(result), containsAll([1, 3]));
    });

    test('prefix typing matches longer words (hik → hiking)', () {
      final result = similarProps(board, 'hik');
      expect(ids(result), [2]);
    });

    test('no overlap → empty result', () {
      expect(similarProps(board, 'zqxv'), isEmpty);
    });

    test('stopwords carry no signal — a sentence of function words matches nothing', () {
      // "the is to and" is all stopwords; without filtering, containment would
      // "match" nearly every take on the board. Kept in sync with the wedge.
      expect(similarProps(board, 'the is to and'), isEmpty);
    });

    test('stopwords are stripped but real tokens still match', () {
      // Only 'pizza' carries signal here; the/for/is are dropped.
      final result = similarProps(board, 'is the pizza for');
      expect(ids(result), containsAll([1, 3]));
      expect(ids(result), isNot(contains(2)));
    });

    test('short noise tokens (1 char) are ignored', () {
      // "a" alone shouldn't match everything containing "a".
      expect(similarProps(board, 'a'), isEmpty);
    });

    test('handles empty and null-ish contents without throwing', () {
      final messy = [
        prop(1, ''),
        {'id': 2, 'content': null},
        prop(3, 'real take'),
      ];
      expect(ids(similarProps(messy, 'real')), [3]);
    });

    test('does not mutate the input list', () {
      final input = List<Map<String, dynamic>>.from(board);
      similarProps(input, 'pizza night');
      expect(input, board);
    });
  });

  group('highlightRanges', () {
    String marked(String content, String query) {
      final ranges = highlightRanges(content, query);
      final sb = StringBuffer();
      var cursor = 0;
      for (final (start, end) in ranges) {
        sb.write(content.substring(cursor, start));
        sb.write('[${content.substring(start, end)}]');
        cursor = end;
      }
      sb.write(content.substring(cursor));
      return sb.toString();
    }

    test('marks exact token matches, preserving original casing', () {
      expect(
        marked('Pizza night with the team', 'pizza'),
        '[Pizza] night with the team',
      );
    });

    test('marks every matched word across the take', () {
      expect(
        marked('game night is game time', 'game night'),
        '[game] [night] is [game] time',
      );
    });

    test('marks prefix matches (hik → hiking)', () {
      expect(marked('Go hiking on Saturday', 'hik'), 'Go [hiking] on Saturday');
    });

    test('punctuation in the query is ignored', () {
      expect(
        marked('Order pizza and watch a movie', 'PIZZA!!!'),
        'Order [pizza] and watch a movie',
      );
    });

    test('no matches → no ranges', () {
      expect(highlightRanges('Go hiking on Saturday', 'zqxv'), isEmpty);
      expect(highlightRanges('Go hiking on Saturday', ''), isEmpty);
      expect(highlightRanges('Go hiking on Saturday', 'a'), isEmpty);
    });

    test('stopwords in the query never highlight', () {
      // 'on' is a stopword; even though it appears in the content, the query
      // 'on' carries no signal → nothing highlights.
      expect(highlightRanges('Go hiking on Saturday', 'on'), isEmpty);
    });

    test('ranges are within bounds and non-overlapping ascending', () {
      const content = 'pizza pizza pizza';
      final ranges = highlightRanges(content, 'pizza');
      expect(ranges.length, 3);
      var prevEnd = 0;
      for (final (start, end) in ranges) {
        expect(start, greaterThanOrEqualTo(prevEnd));
        expect(end, lessThanOrEqualTo(content.length));
        expect(content.substring(start, end), 'pizza');
        prevEnd = end;
      }
    });
  });

  group('liveStandings', () {
    PriorVote vote(int w, int l, {bool tie = false, bool skip = false}) =>
        PriorVote(winnerId: w, loserId: l, isTie: tie, isSkip: skip);

    final props = [prop(1, 'A'), prop(2, 'B'), prop(3, 'C')];

    test('no votes → incoming order preserved', () {
      expect(ids(liveStandings(props, const [])), [1, 2, 3]);
    });

    test('wins re-rank; ties within score keep incoming order', () {
      // C beats A twice, B beats A once → C(2), B(1), A(0).
      final result = liveStandings(props, [
        vote(3, 1),
        vote(3, 1),
        vote(2, 1),
      ]);
      expect(ids(result), [3, 2, 1]);
    });

    test('a tie gives half a point to BOTH sides', () {
      // B–C tie → B: 0.5, C: 0.5, A: 0 → B and C keep incoming order, A last.
      final result = liveStandings(props, [vote(2, 3, tie: true)]);
      expect(ids(result), [2, 3, 1]);
    });

    test('skips count nothing', () {
      final result = liveStandings(props, [vote(3, 1, skip: true)]);
      expect(ids(result), [1, 2, 3]);
    });

    test('votes for unknown props are ignored gracefully', () {
      final result = liveStandings(props, [vote(99, 1), vote(2, 98)]);
      expect(ids(result), [2, 1, 3]);
    });
  });
}
