// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'OneMind';

  @override
  String get discover => 'Discover';

  @override
  String get discoverPublicChats => 'Discover public chats';

  @override
  String get discoverChats => 'Discover Chats';

  @override
  String get joinWithCode => 'Join with Code';

  @override
  String get joinAnExistingChatWithInviteCode =>
      'Join an existing chat with invite code';

  @override
  String get joinChat => 'Join Chat';

  @override
  String get join => 'Join';

  @override
  String get findChat => 'Find Chat';

  @override
  String get requestToJoin => 'Request to Join';

  @override
  String get createChat => 'Create Chat';

  @override
  String get createANewChat => 'Create a new chat';

  @override
  String get chatCreated => 'Chat Created!';

  @override
  String get cancel => 'Cancel';

  @override
  String get continue_ => 'Continue';

  @override
  String get retry => 'Retry';

  @override
  String get yes => 'Yes';

  @override
  String get no => 'No';

  @override
  String get officialOneMind => 'Official OneMind';

  @override
  String get official => 'OFFICIAL';

  @override
  String get pending => 'PENDING';

  @override
  String get pendingRequests => 'Pending Requests';

  @override
  String get yourChats => 'Your Chats';

  @override
  String get cancelRequest => 'Cancel Request';

  @override
  String cancelRequestQuestion(String chatName) {
    return 'Cancel your request to join \"$chatName\"?';
  }

  @override
  String get yesCancel => 'Yes, Cancel';

  @override
  String get requestCancelled => 'Request cancelled';

  @override
  String get waitingForHostApproval => 'Waiting for host approval';

  @override
  String get hostApprovalRequired => 'Host approval required to join';

  @override
  String get noChatsYet => 'No chats yet';

  @override
  String get discoverPublicChatsJoinOrCreate =>
      'Discover public chats, join with a code, or create your own';

  @override
  String get discoverPublicChatsButton => 'Discover Public Chats';

  @override
  String get noActiveChatsYet =>
      'No active chats yet. Your approved chats will appear here.';

  @override
  String get loadingChats => 'Loading chats';

  @override
  String get failedToLoadChats => 'Failed to load chats';

  @override
  String get chatNotFound => 'Chat not found';

  @override
  String get failedToLookupChat => 'Failed to lookup chat';

  @override
  String failedToJoinChat(String error) {
    return 'Failed to join chat: $error';
  }

  @override
  String get enterInviteCode => 'Enter the 6-character invite code:';

  @override
  String get pleaseEnterSixCharCode => 'Please enter a 6-character code';

  @override
  String get inviteCodeHint => 'ABC123';

  @override
  String hostedBy(String hostName) {
    return 'Hosted by $hostName';
  }

  @override
  String get thisChatsRequiresInvite => 'This chat requires an invite';

  @override
  String get enterEmailForInvite => 'Enter the email your invite was sent to:';

  @override
  String get yourEmailHint => 'your@email.com';

  @override
  String get pleaseEnterEmailAddress => 'Please enter your email address';

  @override
  String get pleaseEnterValidEmail => 'Please enter a valid email address';

  @override
  String get noInviteFoundForEmail => 'No invite found for this email address';

  @override
  String get failedToValidateInvite => 'Failed to validate invite';

  @override
  String get pleaseVerifyEmailFirst => 'Please verify your email first';

  @override
  String get verifyEmail => 'Verify Email';

  @override
  String emailVerified(String email) {
    return 'Email verified: $email';
  }

  @override
  String get enterDisplayName => 'Enter your display name:';

  @override
  String get yourName => 'Your name';

  @override
  String get yourNamePlaceholder => 'Your Name';

  @override
  String get displayName => 'Display name';

  @override
  String get enterYourName => 'Enter your name';

  @override
  String get pleaseEnterYourName => 'Please enter your name';

  @override
  String get yourDisplayName => 'Your display name';

  @override
  String get yourNameVisibleToAll =>
      'Your name will be visible to all participants';

  @override
  String get usingSavedName => 'Using your saved name';

  @override
  String get joinRequestSent => 'Join request sent. Waiting for host approval.';

  @override
  String get searchPublicChats => 'Search public chats...';

  @override
  String noChatsFoundFor(String query) {
    return 'No chats found for \"$query\"';
  }

  @override
  String get noPublicChatsAvailable => 'No public chats available';

  @override
  String get beFirstToCreate => 'Be the first to create one!';

  @override
  String failedToLoadPublicChats(String error) {
    return 'Failed to load public chats: $error';
  }

  @override
  String participantCount(int count) {
    return '$count participant';
  }

  @override
  String participantsCount(int count) {
    return '$count participants';
  }

  @override
  String get enterYourNameTitle => 'Enter Your Name';

  @override
  String get anonymous => 'Anonymous';

  @override
  String get timerWarning => 'Timer Warning';

  @override
  String timerWarningMessage(int minutes) {
    return 'Your phase timers are longer than the $minutes-minute schedule window.\n\nPhases may extend beyond the scheduled time, or pause when the window closes.\n\nConsider using shorter timers (5 min or 30 min) for scheduled sessions.';
  }

  @override
  String get adjustSettings => 'Adjust Settings';

  @override
  String get continueAnyway => 'Continue Anyway';

  @override
  String get chatNowPublic => 'Your chat is now public!';

  @override
  String anyoneCanJoinFrom(String chatName) {
    return 'Anyone can find and join \"$chatName\" from the Discover page.';
  }

  @override
  String invitesSent(int count) {
    return '$count invite sent!';
  }

  @override
  String invitesSentPlural(int count) {
    return '$count invites sent!';
  }

  @override
  String get noInvitesSent => 'No invites sent';

  @override
  String get onlyInvitedUsersCanJoin =>
      'Only invited users can join this chat.';

  @override
  String get shareCodeWithParticipants => 'Share this code with participants:';

  @override
  String get inviteCodeCopied => 'Invite code copied to clipboard';

  @override
  String get tapToCopy => 'Tap to copy';

  @override
  String get showQrCode => 'Show QR Code';

  @override
  String get addEmailForInviteOnly =>
      'Add at least one email address for invite-only mode';

  @override
  String get settings => 'Settings';

  @override
  String get language => 'Language';

  @override
  String get english => 'English';

  @override
  String get spanish => 'Espanol';

  @override
  String get rankPropositions => 'Rank Propositions';

  @override
  String get placing => 'Placing: ';

  @override
  String rankedSuccessfully(int count) {
    return 'Ranked $count propositions successfully!';
  }

  @override
  String get failedToSaveRankings => 'Failed to save rankings';

  @override
  String get chatPausedByHost => 'Chat was paused by host';

  @override
  String get goBack => 'Go Back';

  @override
  String get ratePropositions => 'Rate Propositions';

  @override
  String get submitRatings => 'Submit Ratings';

  @override
  String failedToSubmitRatings(String error) {
    return 'Failed to submit ratings: $error';
  }

  @override
  String roundResults(int roundNumber) {
    return 'Round $roundNumber Results';
  }

  @override
  String get noPropositionsToDisplay => 'No propositions to display';

  @override
  String get noPreviousWinner => 'No previous winner';

  @override
  String roundWinner(int roundNumber) {
    return 'Round $roundNumber Winner';
  }

  @override
  String roundWinners(int roundNumber) {
    return 'Round $roundNumber Winners';
  }

  @override
  String get unknownProposition => 'Unknown proposition';

  @override
  String score(String score) {
    return 'Score: $score';
  }

  @override
  String soleWinsProgress(int current, int required) {
    return 'Sole wins: $current/$required';
  }

  @override
  String get tiedWinNoConsensus => 'Tied win (does not count toward consensus)';

  @override
  String get seeAllResults => 'See All Results';

  @override
  String get startPhase => 'Start Phase';

  @override
  String get waiting => 'Waiting';

  @override
  String get waitingForHostToStart => 'Waiting for host to start...';

  @override
  String roundNumber(int roundNumber) {
    return 'Round $roundNumber';
  }

  @override
  String get viewAllPropositions => 'View all propositions';

  @override
  String get chatIsPaused => 'Chat is paused...';

  @override
  String get shareYourIdea => 'Share your idea...';

  @override
  String get addAnotherIdea => 'Add another idea...';

  @override
  String get submit => 'Submit';

  @override
  String get addProposition => 'Add Proposition';

  @override
  String get waitingForRatingPhase => 'Waiting for rating phase...';

  @override
  String get endProposingStartRating => 'End Proposing & Start Rating';

  @override
  String get proposingComplete => 'Proposing Complete';

  @override
  String get reviewPropositionsStartRating =>
      'Review propositions and start rating when ready.';

  @override
  String get waitingForHostToStartRating =>
      'Waiting for host to start the rating phase.';

  @override
  String get startRatingPhase => 'Start Rating Phase';

  @override
  String get ratingComplete => 'Rating Complete';

  @override
  String get waitingForRatingPhaseEnd => 'Waiting for rating phase to end.';

  @override
  String rateAllPropositions(int count) {
    return 'Rate all $count propositions';
  }

  @override
  String get continueRating => 'Continue Rating';

  @override
  String get startRating => 'Start Rating';

  @override
  String get endRatingStartNextRound => 'End Rating & Start Next Round';

  @override
  String get chatPaused => 'Chat Paused';

  @override
  String get chatPausedByHostTitle => 'Chat Paused by Host';

  @override
  String get timerStoppedTapResume =>
      'The timer is stopped. Tap Resume in the app bar to continue.';

  @override
  String get hostPausedPleaseWait =>
      'The host has paused this chat. Please wait for them to resume.';
}
