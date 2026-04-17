import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/models/proposition.dart';
import 'package:onemind_app/providers/chat_providers.dart';
import 'package:onemind_app/screens/chat/other_propositions_screen.dart';
import 'package:onemind_app/widgets/proposition_content_card.dart';

import '../../fixtures/proposition_fixtures.dart';

/// Minimal fake for OtherPropositionsScreen tests - only needs initial state.
class _FakeChatDetailNotifier
    extends StateNotifier<AsyncValue<ChatDetailState>>
    implements ChatDetailNotifier {
  _FakeChatDetailNotifier(ChatDetailState s) : super(AsyncData(s));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  const params = ChatDetailParams(chatId: 1, showPreviousResults: false);

  Widget buildApp(ChatDetailState state) {
    return ProviderScope(
      overrides: [
        chatDetailProvider(params)
            .overrideWith((ref) => _FakeChatDetailNotifier(state)),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: const OtherPropositionsScreen(params: params),
      ),
    );
  }

  Proposition propWithTime({
    required int id,
    required String content,
    required DateTime createdAt,
    int participantId = 1,
    int? carriedFromId,
  }) =>
      Proposition.fromJson(PropositionFixtures.json(
        id: id,
        participantId: participantId,
        content: content,
        createdAt: createdAt,
        carriedFromId: carriedFromId,
      ));

  group('OtherPropositionsScreen', () {
    testWidgets('shows empty state when no propositions', (tester) async {
      await tester.pumpWidget(buildApp(const ChatDetailState()));
      await tester.pumpAndSettle();

      expect(find.text('No propositions yet'), findsOneWidget);
    });

    testWidgets('renders all non-carried propositions', (tester) async {
      final now = DateTime.now();
      final state = ChatDetailState(
        propositions: [
          propWithTime(id: 1, content: 'Alpha', createdAt: now),
          propWithTime(
              id: 2, content: 'Beta', createdAt: now.subtract(const Duration(minutes: 1))),
        ],
      );
      await tester.pumpWidget(buildApp(state));
      await tester.pumpAndSettle();

      expect(find.text('Alpha'), findsOneWidget);
      expect(find.text('Beta'), findsOneWidget);
      expect(find.byType(PropositionContentCard), findsNWidgets(2));
    });

    testWidgets('sorts newest first', (tester) async {
      final now = DateTime.now();
      final state = ChatDetailState(
        propositions: [
          propWithTime(
              id: 1, content: 'Oldest', createdAt: now.subtract(const Duration(minutes: 5))),
          propWithTime(id: 2, content: 'Newest', createdAt: now),
          propWithTime(
              id: 3, content: 'Middle', createdAt: now.subtract(const Duration(minutes: 2))),
        ],
      );
      await tester.pumpWidget(buildApp(state));
      await tester.pumpAndSettle();

      final newestPos = tester.getTopLeft(find.text('Newest')).dy;
      final middlePos = tester.getTopLeft(find.text('Middle')).dy;
      final oldestPos = tester.getTopLeft(find.text('Oldest')).dy;

      expect(newestPos, lessThan(middlePos));
      expect(middlePos, lessThan(oldestPos));
    });

    testWidgets('excludes carried-forward propositions', (tester) async {
      final now = DateTime.now();
      final state = ChatDetailState(
        propositions: [
          propWithTime(id: 1, content: 'New submission', createdAt: now),
          propWithTime(
              id: 2,
              content: 'Previous winner',
              createdAt: now,
              carriedFromId: 99),
        ],
      );
      await tester.pumpWidget(buildApp(state));
      await tester.pumpAndSettle();

      expect(find.text('New submission'), findsOneWidget);
      expect(find.text('Previous winner'), findsNothing);
    });

    testWidgets('shows translated content when translation available',
        (tester) async {
      final translated = Proposition.fromJson(PropositionFixtures.json(
        id: 1,
        participantId: 1,
        content: 'Hello world',
        contentTranslated: 'Hola mundo',
        languageCode: 'es',
      ));
      await tester.pumpWidget(buildApp(ChatDetailState(propositions: [translated])));
      await tester.pumpAndSettle();

      expect(find.text('Hola mundo'), findsOneWidget);
      expect(find.text('Hello world'), findsNothing);
    });

    testWidgets('title shows count of visible propositions', (tester) async {
      final now = DateTime.now();
      final state = ChatDetailState(
        propositions: [
          propWithTime(id: 1, content: 'A', createdAt: now),
          propWithTime(id: 2, content: 'B', createdAt: now),
          propWithTime(id: 3, content: 'C', createdAt: now),
        ],
      );
      await tester.pumpWidget(buildApp(state));
      await tester.pumpAndSettle();

      expect(find.text('Propositions (3)'), findsOneWidget);
    });

    testWidgets('title count excludes carried-forward propositions',
        (tester) async {
      final now = DateTime.now();
      final state = ChatDetailState(
        propositions: [
          propWithTime(id: 1, content: 'New', createdAt: now),
          propWithTime(
              id: 2, content: 'Carried', createdAt: now, carriedFromId: 99),
          propWithTime(
              id: 3, content: 'Carried2', createdAt: now, carriedFromId: 100),
        ],
      );
      await tester.pumpWidget(buildApp(state));
      await tester.pumpAndSettle();

      // Only 1 non-carried proposition — count should reflect that.
      expect(find.text('Propositions (1)'), findsOneWidget);
    });

    testWidgets('title shows no count when empty', (tester) async {
      await tester.pumpWidget(buildApp(const ChatDetailState()));
      await tester.pumpAndSettle();

      expect(find.text('Propositions'), findsOneWidget);
      expect(find.textContaining('('), findsNothing);
    });

    testWidgets('loading state renders without error', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatDetailProvider(params).overrideWith((ref) =>
                _LoadingFakeNotifier()),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: const OtherPropositionsScreen(params: params),
          ),
        ),
      );
      await tester.pump(); // don't settle — we want to catch the loading frame

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('Propositions'), findsOneWidget);
    });

    testWidgets('error state renders error message', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            chatDetailProvider(params).overrideWith((ref) =>
                _ErrorFakeNotifier('boom')),
          ],
          child: MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('en'),
            home: const OtherPropositionsScreen(params: params),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('boom'), findsOneWidget);
    });
  });
}

class _LoadingFakeNotifier extends StateNotifier<AsyncValue<ChatDetailState>>
    implements ChatDetailNotifier {
  _LoadingFakeNotifier() : super(const AsyncLoading());

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ErrorFakeNotifier extends StateNotifier<AsyncValue<ChatDetailState>>
    implements ChatDetailNotifier {
  _ErrorFakeNotifier(String msg)
      : super(AsyncError(msg, StackTrace.current));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
