import '../models/chat_dashboard_info.dart';

/// Sort dashboard chats by urgency:
/// 1. Active + timed — soonest phaseEndsAt first
/// 2. Active + no timer (manual mode) — by lastActivityAt DESC
/// 3. Paused — by lastActivityAt DESC
/// 4. Idle (no active round) — by lastActivityAt DESC
List<ChatDashboardInfo> sortByUrgency(List<ChatDashboardInfo> chats) {
  final sorted = List<ChatDashboardInfo>.from(chats);
  sorted.sort((a, b) {
    final aGroup = _urgencyGroup(a);
    final bGroup = _urgencyGroup(b);

    if (aGroup != bGroup) return aGroup.compareTo(bGroup);

    // Within group 0 (active + timed): sort by soonest timer
    if (aGroup == 0) {
      return a.phaseEndsAt!.compareTo(b.phaseEndsAt!);
    }

    // All other groups: sort by lastActivityAt DESC
    final aActivity = a.chat.lastActivityAt ?? DateTime(2000);
    final bActivity = b.chat.lastActivityAt ?? DateTime(2000);
    return bActivity.compareTo(aActivity);
  });
  return sorted;
}

/// Returns urgency group (lower = more urgent):
/// 0 = active + timed
/// 1 = active + no timer
/// 2 = paused
/// 3 = idle
int _urgencyGroup(ChatDashboardInfo info) {
  if (info.isPaused) return 2;
  if (!info.hasActiveRound) return 3;
  if (info.hasActiveTimer) return 0;
  return 1; // active, no timer
}
