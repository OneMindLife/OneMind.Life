import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/join_request.dart';

void main() {
  group('PendingRequestCard UI', () {
    JoinRequest createTestRequest({
      int id = 1,
      int chatId = 10,
      String displayName = 'Test Requester',
      String? chatName = 'Test Chat',
      String? chatInitialMessage = 'Welcome to the chat!',
      JoinRequestStatus status = JoinRequestStatus.pending,
    }) {
      return JoinRequest(
        id: id,
        chatId: chatId,
        displayName: displayName,
        isAuthenticated: false,
        status: status,
        createdAt: DateTime.now(),
        chatName: chatName,
        chatInitialMessage: chatInitialMessage,
      );
    }

    testWidgets('displays chat name', (tester) async {
      final request = createTestRequest(chatName: 'My Test Chat');

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestPendingRequestCard(
              request: request,
              onCancel: () {},
            ),
          ),
        ),
      );

      expect(find.text('My Test Chat'), findsOneWidget);
    });

    testWidgets('displays chat initial message when present', (tester) async {
      final request = createTestRequest(
        chatInitialMessage: 'This is the welcome message',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestPendingRequestCard(
              request: request,
              onCancel: () {},
            ),
          ),
        ),
      );

      expect(find.text('This is the welcome message'), findsOneWidget);
    });

    testWidgets('shows PENDING badge', (tester) async {
      final request = createTestRequest();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestPendingRequestCard(
              request: request,
              onCancel: () {},
            ),
          ),
        ),
      );

      expect(find.text('PENDING'), findsOneWidget);
    });

    testWidgets('shows waiting message', (tester) async {
      final request = createTestRequest();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestPendingRequestCard(
              request: request,
              onCancel: () {},
            ),
          ),
        ),
      );

      expect(find.text('Waiting for host approval'), findsOneWidget);
    });

    testWidgets('shows hourglass icon', (tester) async {
      final request = createTestRequest();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestPendingRequestCard(
              request: request,
              onCancel: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.hourglass_empty), findsOneWidget);
    });

    testWidgets('shows cancel button', (tester) async {
      final request = createTestRequest();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestPendingRequestCard(
              request: request,
              onCancel: () {},
            ),
          ),
        ),
      );

      expect(find.byIcon(Icons.close), findsOneWidget);
    });

    testWidgets('cancel button is tappable', (tester) async {
      bool cancelled = false;
      final request = createTestRequest();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestPendingRequestCard(
              request: request,
              onCancel: () => cancelled = true,
            ),
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(cancelled, isTrue);
    });

    testWidgets('shows chat id when no chat name', (tester) async {
      final request = createTestRequest(chatId: 42, chatName: null);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestPendingRequestCard(
              request: request,
              onCancel: () {},
            ),
          ),
        ),
      );

      expect(find.text('Chat #42'), findsOneWidget);
    });

    testWidgets('handles null initial message', (tester) async {
      final request = createTestRequest(chatInitialMessage: null);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: _TestPendingRequestCard(
              request: request,
              onCancel: () {},
            ),
          ),
        ),
      );

      // Should not crash, waiting message should still show
      expect(find.text('Waiting for host approval'), findsOneWidget);
    });
  });
}

/// Test widget that mimics the pending request card structure
class _TestPendingRequestCard extends StatelessWidget {
  final JoinRequest request;
  final VoidCallback onCancel;

  const _TestPendingRequestCard({
    required this.request,
    required this.onCancel,
  });

  @override
  Widget build(BuildContext context) {
    final chatName = request.chatName ?? 'Chat #${request.chatId}';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                Icons.hourglass_empty,
                color: Theme.of(context).colorScheme.onTertiaryContainer,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          chatName,
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.tertiary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'PENDING',
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                color: Theme.of(context).colorScheme.onTertiary,
                                fontWeight: FontWeight.bold,
                              ),
                        ),
                      ),
                    ],
                  ),
                  if (request.chatInitialMessage != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      request.chatInitialMessage!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Colors.grey.shade600,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 4),
                  Text(
                    'Waiting for host approval',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                          fontStyle: FontStyle.italic,
                        ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancel request',
              onPressed: onCancel,
            ),
          ],
        ),
      ),
    );
  }
}
