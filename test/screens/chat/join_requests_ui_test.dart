import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Join Requests UI Components', () {
    group('Badge Widget', () {
      testWidgets('Badge displays count when visible', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                actions: [
                  IconButton(
                    icon: Badge(
                      label: const Text('3'),
                      isLabelVisible: true,
                      child: const Icon(Icons.person_add),
                    ),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        );

        expect(find.byIcon(Icons.person_add), findsOneWidget);
        expect(find.text('3'), findsOneWidget);
      });

      testWidgets('Badge hides count when not visible', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              appBar: AppBar(
                actions: [
                  IconButton(
                    icon: Badge(
                      label: const Text('0'),
                      isLabelVisible: false,
                      child: const Icon(Icons.person_add),
                    ),
                    onPressed: () {},
                  ),
                ],
              ),
            ),
          ),
        );

        expect(find.byIcon(Icons.person_add), findsOneWidget);
        // Badge label should not be visible
        expect(find.text('0'), findsNothing);
      });
    });

    group('Request Card', () {
      testWidgets('displays requester name and status', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _TestRequestCard(
                displayName: 'TestUser',
                isAuthenticated: false,
              ),
            ),
          ),
        );

        expect(find.text('TestUser'), findsOneWidget);
        expect(find.text('Guest'), findsOneWidget);
        expect(find.byIcon(Icons.check_circle), findsOneWidget);
        expect(find.byIcon(Icons.cancel), findsOneWidget);
      });

      testWidgets('shows "Signed in" for authenticated users', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _TestRequestCard(
                displayName: 'AuthUser',
                isAuthenticated: true,
              ),
            ),
          ),
        );

        expect(find.text('AuthUser'), findsOneWidget);
        expect(find.text('Signed in'), findsOneWidget);
      });

      testWidgets('displays first letter in avatar', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _TestRequestCard(
                displayName: 'Alice',
                isAuthenticated: false,
              ),
            ),
          ),
        );

        expect(find.text('A'), findsOneWidget);
      });

      testWidgets('approve button is tappable', (tester) async {
        bool approved = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _TestRequestCard(
                displayName: 'TestUser',
                isAuthenticated: false,
                onApprove: () => approved = true,
              ),
            ),
          ),
        );

        await tester.tap(find.byIcon(Icons.check_circle));
        await tester.pump();

        expect(approved, isTrue);
      });

      testWidgets('deny button is tappable', (tester) async {
        bool denied = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _TestRequestCard(
                displayName: 'TestUser',
                isAuthenticated: false,
                onDeny: () => denied = true,
              ),
            ),
          ),
        );

        await tester.tap(find.byIcon(Icons.cancel));
        await tester.pump();

        expect(denied, isTrue);
      });
    });

    group('Empty State', () {
      testWidgets('displays empty state message', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_circle_outline, size: 48),
                    const SizedBox(height: 16),
                    const Text('No pending requests'),
                    const SizedBox(height: 4),
                    const Text('New requests will appear here'),
                  ],
                ),
              ),
            ),
          ),
        );

        expect(find.byIcon(Icons.check_circle_outline), findsOneWidget);
        expect(find.text('No pending requests'), findsOneWidget);
        expect(find.text('New requests will appear here'), findsOneWidget);
      });
    });

    group('Bottom Sheet Header', () {
      testWidgets('displays title with count', (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Join Requests (5)',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text('Approve or deny requests to join this chat.'),
                ],
              ),
            ),
          ),
        );

        expect(find.text('Join Requests (5)'), findsOneWidget);
        expect(
          find.text('Approve or deny requests to join this chat.'),
          findsOneWidget,
        );
      });
    });

    group('Modal Stays Open After Action', () {
      testWidgets('bottom sheet stays open after approving request',
          (tester) async {
        bool approved = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      builder: (context) => Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Join Requests'),
                            _TestRequestCard(
                              displayName: 'TestUser',
                              isAuthenticated: false,
                              onApprove: () {
                                // Action handler should NOT close the modal
                                approved = true;
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Sheet'),
                ),
              ),
            ),
          ),
        );

        // Open the bottom sheet
        await tester.tap(find.text('Open Sheet'));
        await tester.pumpAndSettle();

        // Verify sheet is open
        expect(find.text('Join Requests'), findsOneWidget);

        // Tap approve
        await tester.tap(find.byIcon(Icons.check_circle));
        await tester.pumpAndSettle();

        // Sheet should STILL be open (not closed)
        expect(approved, isTrue);
        expect(find.text('Join Requests'), findsOneWidget);
      });

      testWidgets('bottom sheet stays open after denying request',
          (tester) async {
        bool denied = false;

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Builder(
                builder: (context) => ElevatedButton(
                  onPressed: () {
                    showModalBottomSheet(
                      context: context,
                      builder: (context) => Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text('Join Requests'),
                            _TestRequestCard(
                              displayName: 'TestUser',
                              isAuthenticated: false,
                              onDeny: () {
                                // Action handler should NOT close the modal
                                denied = true;
                              },
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                  child: const Text('Open Sheet'),
                ),
              ),
            ),
          ),
        );

        // Open the bottom sheet
        await tester.tap(find.text('Open Sheet'));
        await tester.pumpAndSettle();

        // Verify sheet is open
        expect(find.text('Join Requests'), findsOneWidget);

        // Tap deny
        await tester.tap(find.byIcon(Icons.cancel));
        await tester.pumpAndSettle();

        // Sheet should STILL be open (not closed)
        expect(denied, isTrue);
        expect(find.text('Join Requests'), findsOneWidget);
      });
    });
  });
}

/// Test widget that mimics the request card structure
class _TestRequestCard extends StatelessWidget {
  final String displayName;
  final bool isAuthenticated;
  final VoidCallback? onApprove;
  final VoidCallback? onDeny;

  const _TestRequestCard({
    required this.displayName,
    required this.isAuthenticated,
    this.onApprove,
    this.onDeny,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          CircleAvatar(
            child: Text(displayName[0].toUpperCase()),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(displayName),
                Text(isAuthenticated ? 'Signed in' : 'Guest'),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.check_circle,
                color: Theme.of(context).colorScheme.primary),
            onPressed: onApprove,
            tooltip: 'Approve',
          ),
          IconButton(
            icon:
                Icon(Icons.cancel, color: Theme.of(context).colorScheme.error),
            onPressed: onDeny,
            tooltip: 'Deny',
          ),
        ],
      ),
    );
  }
}
