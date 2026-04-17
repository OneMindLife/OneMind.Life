import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/models/personal_code.dart';
import 'package:onemind_app/providers/providers.dart';
import 'package:onemind_app/screens/chat/widgets/personal_code_sheet.dart';
import 'package:onemind_app/services/personal_code_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../mocks/mock_supabase_client.dart';

class MockPersonalCodeService extends Mock implements PersonalCodeService {}

void main() {
  late MockPersonalCodeService mockService;
  late MockSupabaseClient mockSupabase;
  late MockRealtimeChannel mockChannel;

  final activeCode = PersonalCode(
    id: 1,
    code: 'ABC123',
    createdAt: DateTime.utc(2026, 4, 5),
  );

  final usedCode = PersonalCode(
    id: 2,
    code: 'DEF456',
    usedBy: 'user-uuid',
    usedAt: DateTime.utc(2026, 4, 5, 12),
    createdAt: DateTime.utc(2026, 4, 5),
  );

  final revokedCode = PersonalCode(
    id: 3,
    code: 'GHI789',
    revokedAt: DateTime.utc(2026, 4, 5, 14),
    createdAt: DateTime.utc(2026, 4, 5),
  );

  setUpAll(() {
    registerFallbackValue(PostgresChangeEvent.all);
    registerFallbackValue(PostgresChangeFilter(
      type: PostgresChangeFilterType.eq,
      column: 'id',
      value: 1,
    ));
  });

  setUp(() {
    mockService = MockPersonalCodeService();
    mockSupabase = MockSupabaseClient();
    mockChannel = MockRealtimeChannel();

    // Setup Realtime channel mocks
    when(() => mockSupabase.channel(any())).thenReturn(mockChannel);
    when(() => mockChannel.onPostgresChanges(
          event: any(named: 'event'),
          schema: any(named: 'schema'),
          table: any(named: 'table'),
          filter: any(named: 'filter'),
          callback: any(named: 'callback'),
        )).thenReturn(mockChannel);
    when(() => mockChannel.subscribe()).thenReturn(mockChannel);
    when(() => mockChannel.unsubscribe()).thenAnswer((_) async => 'ok');
  });

  Widget buildSheet({int chatId = 42, String chatName = 'Test Chat'}) {
    return ProviderScope(
      overrides: [
        personalCodeServiceProvider.overrideWithValue(mockService),
        supabaseProvider.overrideWithValue(mockSupabase),
      ],
      child: MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: SizedBox(
            height: 600,
            child: PersonalCodeSheet(
              chatId: chatId,
              chatName: chatName,
            ),
          ),
        ),
      ),
    );
  }

  group('PersonalCodeSheet', () {
    group('loading and display', () {
      testWidgets('shows loading indicator initially', (tester) async {
        final completer = Completer<List<PersonalCode>>();
        when(() => mockService.listCodes(42))
            .thenAnswer((_) => completer.future);

        await tester.pumpWidget(buildSheet());
        await tester.pump();

        expect(find.byType(CircularProgressIndicator), findsWidgets);

        // Complete so teardown is clean
        completer.complete([activeCode]);
        await tester.pumpAndSettle();
      });

      testWidgets('displays codes after loading', (tester) async {
        when(() => mockService.listCodes(42))
            .thenAnswer((_) async => [activeCode, usedCode]);

        await tester.pumpWidget(buildSheet());
        await tester.pumpAndSettle();

        expect(find.text('ABC123'), findsOneWidget);
        expect(find.text('DEF456'), findsOneWidget);
      });

      testWidgets('shows empty state when no codes', (tester) async {
        when(() => mockService.listCodes(42))
            .thenAnswer((_) async => []);

        await tester.pumpWidget(buildSheet());
        await tester.pumpAndSettle();

        // Should show the "no codes yet" message
        expect(find.byType(ListView), findsNothing);
      });

      testWidgets('shows error on load failure', (tester) async {
        when(() => mockService.listCodes(42))
            .thenThrow(Exception('Network error'));

        await tester.pumpWidget(buildSheet());
        await tester.pumpAndSettle();

        expect(find.textContaining('Network error'), findsOneWidget);
      });

      testWidgets('shows active status badge for active code', (tester) async {
        when(() => mockService.listCodes(42))
            .thenAnswer((_) async => [activeCode]);

        await tester.pumpWidget(buildSheet());
        await tester.pumpAndSettle();

        expect(find.text('ABC123'), findsOneWidget);
        // Active codes show QR, copy, and revoke buttons
        expect(find.byIcon(Icons.qr_code), findsOneWidget);
        expect(find.byIcon(Icons.copy), findsOneWidget);
        expect(find.byIcon(Icons.block), findsOneWidget);
      });

      testWidgets('hides action buttons for used code', (tester) async {
        when(() => mockService.listCodes(42))
            .thenAnswer((_) async => [usedCode]);

        await tester.pumpWidget(buildSheet());
        await tester.pumpAndSettle();

        expect(find.text('DEF456'), findsOneWidget);
        // Used codes should not show action buttons
        expect(find.byIcon(Icons.qr_code), findsNothing);
        expect(find.byIcon(Icons.copy), findsNothing);
      });
    });

    group('Realtime subscription', () {
      testWidgets('subscribes to personal_codes channel on init',
          (tester) async {
        when(() => mockService.listCodes(42))
            .thenAnswer((_) async => [activeCode]);

        await tester.pumpWidget(buildSheet());
        await tester.pumpAndSettle();

        verify(() => mockSupabase.channel('personal_codes:42')).called(1);
        verify(() => mockChannel.onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'personal_codes',
              filter: any(named: 'filter'),
              callback: any(named: 'callback'),
            )).called(1);
        verify(() => mockChannel.subscribe()).called(1);
      });

      testWidgets('unsubscribes on dispose', (tester) async {
        when(() => mockService.listCodes(42))
            .thenAnswer((_) async => [activeCode]);

        await tester.pumpWidget(buildSheet());
        await tester.pumpAndSettle();

        // Remove the widget to trigger dispose
        await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: Container())),
        );
        await tester.pumpAndSettle();

        verify(() => mockChannel.unsubscribe()).called(1);
      });
    });

    group('generate code', () {
      testWidgets('generates code and shows QR dialog', (tester) async {
        final newCode = PersonalCode(
          id: 10,
          code: 'NEW999',
          createdAt: DateTime.utc(2026, 4, 5, 16),
        );

        when(() => mockService.listCodes(42))
            .thenAnswer((_) async => [activeCode]);
        when(() => mockService.generateCode(42))
            .thenAnswer((_) async => newCode);

        await tester.pumpWidget(buildSheet());
        await tester.pumpAndSettle();

        // Tap generate button
        await tester.tap(find.byIcon(Icons.add));
        await tester.pumpAndSettle();

        verify(() => mockService.generateCode(42)).called(1);
        // New code should be in the list
        expect(find.text('NEW999'), findsWidgets);
      });
    });

    group('revoke code', () {
      testWidgets('revokes code after confirmation', (tester) async {
        when(() => mockService.listCodes(42))
            .thenAnswer((_) async => [activeCode]);
        when(() => mockService.revokeCode(1)).thenAnswer((_) async {});

        await tester.pumpWidget(buildSheet());
        await tester.pumpAndSettle();

        // Tap revoke button (block icon)
        await tester.tap(find.byIcon(Icons.block));
        await tester.pumpAndSettle();

        // Confirm in dialog — button text is just "Revoke"
        await tester.tap(find.widgetWithText(FilledButton, 'Revoke'));
        await tester.pumpAndSettle();

        verify(() => mockService.revokeCode(1)).called(1);
      });
    });

    group('code status display', () {
      testWidgets('shows all three status types correctly', (tester) async {
        when(() => mockService.listCodes(42))
            .thenAnswer((_) async => [activeCode, usedCode, revokedCode]);

        await tester.pumpWidget(buildSheet());
        await tester.pumpAndSettle();

        expect(find.text('ABC123'), findsOneWidget);
        expect(find.text('DEF456'), findsOneWidget);
        expect(find.text('GHI789'), findsOneWidget);

        // Check status icons
        expect(find.byIcon(Icons.vpn_key), findsWidgets); // active + header
        expect(find.byIcon(Icons.check_circle_outline), findsOneWidget); // used
        expect(find.byIcon(Icons.block), findsWidgets); // revoked + active revoke btn
      });
    });
  });
}
