import '../models/chat_dashboard_info.dart';
import '../models/round.dart';

/// Sort dashboard chats like a conveyor belt — what needs attention next rises to top:
/// 1. Not participated + active + timed — soonest phaseEndsAt first
/// 2. Not participated + active + no timer — by lastActivityAt DESC
/// 3. Participated + active + timed — soonest phaseEndsAt first
/// 4. Participated + active + no timer — by lastActivityAt DESC
/// 5. Paused — by lastActivityAt DESC
/// 6. Idle (no active round) — by lastActivityAt DESC
List<ChatDashboardInfo> sortByUrgency(List<ChatDashboardInfo> chats) {
  final sorted = List<ChatDashboardInfo>.from(chats);
  sorted.sort((a, b) {
    final aGroup = _urgencyGroup(a);
    final bGroup = _urgencyGroup(b);

    if (aGroup != bGroup) return aGroup.compareTo(bGroup);

    // Within timed groups (0, 2): sort by soonest timer
    if (aGroup == 0 || aGroup == 2) {
      return a.phaseEndsAt!.compareTo(b.phaseEndsAt!);
    }

    // All other groups: sort by lastActivityAt DESC
    final aActivity = a.chat.lastActivityAt ?? DateTime(2000);
    final bActivity = b.chat.lastActivityAt ?? DateTime(2000);
    return bActivity.compareTo(aActivity);
  });
  return sorted;
}

/// Split a sorted dashboard list into three feeder buckets:
/// - `nextUp`: active round in proposing/rating where the user still owes
///   an action (the "addictive feeder" queue — topmost card = do this next).
/// - `wrappingUp`: active round in proposing/rating where the user is done;
///   waiting for the group to finish so results can be revealed.
/// - `inactive`: paused, between-rounds, or in the `waiting` phase (round
///   hasn't opened for action yet). Nothing is running for the user here.
///
/// Order within each bucket is preserved from the input list (intended to be
/// the output of [sortByUrgency]).
({
  List<ChatDashboardInfo> nextUp,
  List<ChatDashboardInfo> wrappingUp,
  List<ChatDashboardInfo> inactive,
}) partitionByAttention(List<ChatDashboardInfo> sorted) {
  final nextUp = <ChatDashboardInfo>[];
  final wrappingUp = <ChatDashboardInfo>[];
  final inactive = <ChatDashboardInfo>[];
  for (final info in sorted) {
    final phase = info.currentRoundPhase;
    final isActionable =
        phase == RoundPhase.proposing || phase == RoundPhase.rating;
    if (info.isPaused || !isActionable) {
      inactive.add(info);
    } else if (!info.hasParticipated) {
      nextUp.add(info);
    } else {
      wrappingUp.add(info);
    }
  }
  return (nextUp: nextUp, wrappingUp: wrappingUp, inactive: inactive);
}

/// Returns urgency group (lower = more urgent):
/// 0 = not participated + active + timed (needs attention NOW)
/// 1 = not participated + active + no timer
/// 2 = participated + active + timed (done, but still running)
/// 3 = participated + active + no timer
/// 4 = paused
/// 5 = idle
int _urgencyGroup(ChatDashboardInfo info) {
  if (info.isPaused) return 4;
  if (!info.hasActiveRound) return 5;

  final participated = info.hasParticipated;

  if (info.hasActiveTimer) {
    return participated ? 2 : 0;
  }
  return participated ? 3 : 1;
}
