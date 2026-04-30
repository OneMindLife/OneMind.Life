import 'package:flutter_test/flutter_test.dart';
import 'package:onemind_app/models/models.dart';
import 'package:onemind_app/services/in_memory_participant_repository.dart';
import 'package:onemind_app/services/participant_repository.dart';

/// Contract tests for [ParticipantRepository] using the in-memory impl.
/// These cover the join branching that was previously implemented inline in
/// [ParticipantService] and silently drifted when the soft-delete migration
/// shipped (commit e37ad8a → 0b9e986). Any future repository impl
/// (Supabase, mock, fake) must satisfy these same assertions.
void main() {
  late InMemoryParticipantRepository repo;
  const userA = '99000000-0000-0000-0000-0000000000a1';
  const userB = '99000000-0000-0000-0000-0000000000b1';
  const publicChatId = 100;
  const codeChatId = 101;
  const inviteOnlyChatId = 102;
  const inactiveChatId = 103;

  setUp(() {
    repo = InMemoryParticipantRepository(chats: {
      publicChatId: const ChatStub(id: publicChatId),
      codeChatId:
          const ChatStub(id: codeChatId, accessMethod: 'code'),
      inviteOnlyChatId:
          const ChatStub(id: inviteOnlyChatId, accessMethod: 'invite_only'),
      inactiveChatId: const ChatStub(id: inactiveChatId, isActive: false),
    });
    repo.setCurrentUserId(userA);
  });

  group('joinChat — fresh', () {
    test('first join returns JoinedFresh with active row', () async {
      final result = await repo.joinChat(
        chatId: publicChatId,
        displayName: 'A',
      );
      expect(result, isA<JoinedFresh>());
      expect(result.participant.status, ParticipantStatus.active);
      expect(result.participant.displayName, 'A');
      expect(result.participant.userId, userA);
    });

    test('first join in code-access chat works the same', () async {
      final result = await repo.joinChat(
        chatId: codeChatId,
        displayName: 'A',
      );
      expect(result, isA<JoinedFresh>());
    });

    test('joining same chat twice returns AlreadyIn (idempotent)', () async {
      await repo.joinChat(chatId: publicChatId, displayName: 'A');
      final second =
          await repo.joinChat(chatId: publicChatId, displayName: 'A again');
      expect(second, isA<AlreadyIn>());
      // Existing row preserved — display_name NOT overwritten by duplicate
      expect(second.participant.displayName, 'A');
      expect(repo.allParticipants.length, 1);
    });
  });

  group('joinChat — left → active reactivation', () {
    test('user who left and rejoins returns Reactivated, same id, status flipped', () async {
      final first = await repo.joinChat(
        chatId: publicChatId,
        displayName: 'A',
      );
      final originalId = first.participant.id;

      await repo.leaveChat(originalId);
      expect(
        repo.participantFor(chatId: publicChatId, userId: userA)?.status,
        ParticipantStatus.left,
      );

      final rejoin = await repo.joinChat(
        chatId: publicChatId,
        displayName: 'A renamed',
      );

      expect(rejoin, isA<Reactivated>());
      expect(rejoin.participant.id, originalId,
          reason: 'rejoin must reuse same row, not insert a new one');
      expect(rejoin.participant.status, ParticipantStatus.active);
      expect(rejoin.participant.displayName, 'A renamed');
      expect(repo.allParticipants.length, 1);
    });

    test('the bug: rejoin must NOT throw a unique-constraint error', () async {
      // This is the exact scenario that broke production: leave → rejoin.
      // Pre-fix Dart impl tried to .insert() a new row, hitting
      // idx_unique_user_per_chat. Repository contract: rejoin always works.
      final first = await repo.joinChat(
        chatId: publicChatId,
        displayName: 'A',
      );
      await repo.leaveChat(first.participant.id);
      final rejoin = await repo.joinChat(
        chatId: publicChatId,
        displayName: 'A',
      );
      expect(rejoin, isA<Reactivated>());
    });
  });

  group('joinChat — kicked stays kicked', () {
    test('kicked users cannot silently rejoin via joinChat', () async {
      final first = await repo.joinChat(
        chatId: publicChatId,
        displayName: 'A',
      );
      await repo.kickParticipant(first.participant.id);

      final rejoin = await repo.joinChat(
        chatId: publicChatId,
        displayName: 'A',
      );

      expect(rejoin, isA<CannotJoin>());
      expect((rejoin as CannotJoin).reason, CannotJoinReason.kicked);
      // Status stays kicked
      expect(
        repo.participantFor(chatId: publicChatId, userId: userA)?.status,
        ParticipantStatus.kicked,
      );
    });
  });

  group('joinChat — refusals', () {
    test('unauthenticated → CannotJoin(authRequired)', () async {
      repo.setCurrentUserId(null);
      final result = await repo.joinChat(
        chatId: publicChatId,
        displayName: 'A',
      );
      expect((result as CannotJoin).reason, CannotJoinReason.authRequired);
    });

    test('unknown chat → CannotJoin(chatNotFound)', () async {
      final result = await repo.joinChat(
        chatId: 9999,
        displayName: 'A',
      );
      expect((result as CannotJoin).reason, CannotJoinReason.chatNotFound);
    });

    test('inactive chat → CannotJoin(chatNotActive)', () async {
      final result = await repo.joinChat(
        chatId: inactiveChatId,
        displayName: 'A',
      );
      expect((result as CannotJoin).reason, CannotJoinReason.chatNotActive);
    });

    test('invite-only chat → CannotJoin(chatRequiresApproval)', () async {
      final result = await repo.joinChat(
        chatId: inviteOnlyChatId,
        displayName: 'A',
      );
      expect(
        (result as CannotJoin).reason,
        CannotJoinReason.chatRequiresApproval,
      );
    });
  });

  group('multi-user contract', () {
    test('two distinct users join the same chat without collision', () async {
      repo.setCurrentUserId(userA);
      final a = await repo.joinChat(chatId: publicChatId, displayName: 'A');
      repo.setCurrentUserId(userB);
      final b = await repo.joinChat(chatId: publicChatId, displayName: 'B');

      expect(a, isA<JoinedFresh>());
      expect(b, isA<JoinedFresh>());
      expect(a.participant.id, isNot(b.participant.id));
      expect(repo.allParticipants.length, 2);
    });

    test("user A's leave does not affect user B's status", () async {
      repo.setCurrentUserId(userA);
      final a = await repo.joinChat(chatId: publicChatId, displayName: 'A');
      repo.setCurrentUserId(userB);
      await repo.joinChat(chatId: publicChatId, displayName: 'B');

      repo.setCurrentUserId(userA);
      await repo.leaveChat(a.participant.id);

      final bRow =
          repo.participantFor(chatId: publicChatId, userId: userB);
      expect(bRow?.status, ParticipantStatus.active);
    });
  });

  group('host registration', () {
    test('addHost inserts an active host row regardless of access checks',
        () async {
      // Even invite-only chats can register their host (chat creation flow)
      final host = await repo.addHost(
        chatId: inviteOnlyChatId,
        displayName: 'Host',
      );
      expect(host.isHost, true);
      expect(host.status, ParticipantStatus.active);
      expect(host.userId, userA);
    });
  });

  group('leave/rejoin preserves the same participant_id', () {
    test('leave then 3 rejoins all reuse the same row', () async {
      final first = await repo.joinChat(
        chatId: publicChatId,
        displayName: 'A',
      );
      final id = first.participant.id;

      for (var i = 0; i < 3; i++) {
        await repo.leaveChat(id);
        final rejoin = await repo.joinChat(
          chatId: publicChatId,
          displayName: 'A round $i',
        );
        expect(rejoin.participant.id, id);
        expect(rejoin, isA<Reactivated>());
      }
      expect(repo.allParticipants.length, 1,
          reason: 'no duplicate rows ever created');
    });
  });

  group('approve_join_request flow', () {
    test('pending request approval inserts an active participant', () async {
      await repo.requestToJoin(
        chatId: publicChatId,
        displayName: 'A',
      );
      final pending = await repo.getMyPendingRequests();
      expect(pending.length, 1);

      await repo.approveRequest(pending.first.id);

      final p = repo.participantFor(chatId: publicChatId, userId: userA);
      expect(p, isNotNull);
      expect(p!.status, ParticipantStatus.active);
      expect((await repo.getMyPendingRequests()).length, 0);
    });
  });
}
