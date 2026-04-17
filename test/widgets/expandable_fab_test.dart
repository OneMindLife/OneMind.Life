import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/l10n/generated/app_localizations.dart';
import 'package:onemind_app/widgets/expandable_fab.dart';

void main() {
  group('FabActionSheet', () {
    late List<String> tappedItems;

    setUp(() {
      tappedItems = [];
    });

    Widget buildWidget() {
      return MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => FabActionSheet.show(
                  context,
                  onCreateChat: () => tappedItems.add('create'),
                  onJoinWithCode: () => tappedItems.add('joinCode'),
                  onScanQrCode: () => tappedItems.add('scanQr'),
                  onDiscoverChats: () => tappedItems.add('discover'),
                ),
                child: const Text('Open Sheet'),
              ),
            ),
          ),
        ),
      );
    }

    Future<void> openSheet(WidgetTester tester) async {
      await tester.tap(find.text('Open Sheet'));
      await tester.pumpAndSettle();
    }

    testWidgets('shows 3 main action items', (tester) async {
      await tester.pumpWidget(buildWidget());
      await openSheet(tester);

      expect(find.text('Create Chat'), findsOneWidget);
      expect(find.text('Join Chat'), findsOneWidget);
      expect(find.text('Discover Chats'), findsOneWidget);
    });

    testWidgets('join sub-options not visible initially', (tester) async {
      await tester.pumpWidget(buildWidget());
      await openSheet(tester);

      expect(find.text('Join with Code'), findsNothing);
      expect(find.text('Scan QR Code'), findsNothing);
    });

    testWidgets('Join Chat splits into two buttons inline', (tester) async {
      await tester.pumpWidget(buildWidget());
      await openSheet(tester);

      await tester.tap(find.text('Join Chat'));
      await tester.pumpAndSettle();

      // Sub-options visible
      expect(find.text('Join with Code'), findsOneWidget);
      expect(find.text('Scan QR Code'), findsOneWidget);
      // Create Chat and Discover Chats still visible
      expect(find.text('Create Chat'), findsOneWidget);
      expect(find.text('Discover Chats'), findsOneWidget);
      // Original Join Chat tile gone
      expect(find.byIcon(Icons.chevron_right), findsNothing);
    });

    testWidgets('back arrow collapses join options', (tester) async {
      await tester.pumpWidget(buildWidget());
      await openSheet(tester);

      await tester.tap(find.text('Join Chat'));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();

      // Back to single Join Chat tile
      expect(find.text('Join Chat'), findsOneWidget);
      expect(find.text('Join with Code'), findsNothing);
      expect(find.text('Scan QR Code'), findsNothing);
    });

    testWidgets('Create Chat triggers callback and closes sheet',
        (tester) async {
      await tester.pumpWidget(buildWidget());
      await openSheet(tester);

      await tester.tap(find.text('Create Chat'));
      await tester.pumpAndSettle();

      expect(tappedItems, ['create']);
      expect(find.text('Join Chat'), findsNothing);
    });

    testWidgets('Discover Chats triggers callback', (tester) async {
      await tester.pumpWidget(buildWidget());
      await openSheet(tester);

      await tester.tap(find.text('Discover Chats'));
      await tester.pumpAndSettle();

      expect(tappedItems, ['discover']);
    });

    testWidgets('Join with Code triggers callback', (tester) async {
      await tester.pumpWidget(buildWidget());
      await openSheet(tester);

      await tester.tap(find.text('Join Chat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Join with Code'));
      await tester.pumpAndSettle();

      expect(tappedItems, ['joinCode']);
    });

    testWidgets('Scan QR Code triggers callback', (tester) async {
      await tester.pumpWidget(buildWidget());
      await openSheet(tester);

      await tester.tap(find.text('Join Chat'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Scan QR Code'));
      await tester.pumpAndSettle();

      expect(tappedItems, ['scanQr']);
    });
  });
}
