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
  String get howItWorks => 'How it works';

  @override
  String get discover => 'Discover';

  @override
  String get discoverPublicChats => 'Discover public chats';

  @override
  String get discoverChats => 'Discover Chats';

  @override
  String get joinWithCode => 'Join with Code';

  @override
  String get joinAnExistingChatWithInviteCode => 'Join an existing chat with invite code';

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
  String get delete => 'Delete';

  @override
  String get leave => 'Leave';

  @override
  String get kick => 'Kick';

  @override
  String get pause => 'Pause';

  @override
  String get resume => 'Resume';

  @override
  String get remove => 'Remove';

  @override
  String get clear => 'Clear';

  @override
  String get done => 'Done';

  @override
  String get save => 'Save';

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
  String get hostApprovalRequired => 'Host must approve each request';

  @override
  String get noChatsYet => 'No chats yet';

  @override
  String get discoverPublicChatsJoinOrCreate => 'Discover public chats, join with a code, or create your own';

  @override
  String get discoverPublicChatsButton => 'Discover Public Chats';

  @override
  String get noActiveChatsYet => 'No active chats yet. Your approved chats will appear here.';

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
  String get yourName => 'Your Name';

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
  String get yourNameVisibleToAll => 'Your name will be visible to all participants';

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
  String get onlyInvitedUsersCanJoin => 'Only invited users can join this chat.';

  @override
  String get shareCodeWithParticipants => 'Share this code with participants:';

  @override
  String get inviteCodeCopied => 'Invite code copied to clipboard';

  @override
  String get tapToCopy => 'Tap to copy';

  @override
  String get showQrCode => 'Show QR Code';

  @override
  String get addEmailForInviteOnly => 'Add at least one email address for invite-only mode';

  @override
  String get emailAlreadyAdded => 'Email already added';

  @override
  String get settings => 'Settings';

  @override
  String get language => 'Language';

  @override
  String get english => 'English';

  @override
  String get spanish => 'Espanol';

  @override
  String get portuguese => 'Portugues';

  @override
  String get french => 'Francais';

  @override
  String get german => 'Deutsch';

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
  String get ratingPhaseEnded => 'Rating phase has ended';

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
  String nWayTie(int count) {
    return '$count-WAY TIE';
  }

  @override
  String winnerIndexOfTotal(int current, int total) {
    return '$current of $total';
  }

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
  String get reviewPropositionsStartRating => 'Review propositions and start rating when ready.';

  @override
  String get waitingForHostToStartRating => 'Waiting for host to start the rating phase.';

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
  String get timerStoppedTapResume => 'The timer is stopped. Tap Resume in the app bar to continue.';

  @override
  String get hostPausedPleaseWait => 'The host has paused this chat. Please wait for them to resume.';

  @override
  String get previousWinner => 'Winner';

  @override
  String get yourProposition => 'Your Proposition';

  @override
  String get yourPropositions => 'Your Propositions';

  @override
  String get rate => 'Rate';

  @override
  String get participants => 'Participants';

  @override
  String get chatInfo => 'Chat Info';

  @override
  String get shareQrCode => 'Share QR Code';

  @override
  String get joinRequests => 'Join Requests';

  @override
  String get resumeChat => 'Resume Chat';

  @override
  String get pauseChat => 'Pause Chat';

  @override
  String get leaveChat => 'Leave Chat';

  @override
  String get deleteChat => 'Delete Chat';

  @override
  String get host => 'Host';

  @override
  String get deletePropositionQuestion => 'Delete Proposition?';

  @override
  String get areYouSureDeleteProposition => 'Are you sure you want to delete this proposition?';

  @override
  String get deleteChatQuestion => 'Delete Chat?';

  @override
  String get leaveChatQuestion => 'Leave Chat?';

  @override
  String get kickParticipantQuestion => 'Kick Participant?';

  @override
  String get pauseChatQuestion => 'Pause Chat?';

  @override
  String get removePaymentMethodQuestion => 'Remove Payment Method?';

  @override
  String get propositionDeleted => 'Proposition deleted';

  @override
  String get chatDeleted => 'Chat deleted';

  @override
  String get youHaveLeftChat => 'You have left the chat';

  @override
  String get youHaveBeenRemoved => 'You have been removed from this chat';

  @override
  String get chatHasBeenDeleted => 'This chat has been deleted';

  @override
  String participantRemoved(String name) {
    return '$name has been removed';
  }

  @override
  String get chatPausedSuccess => 'Chat paused';

  @override
  String get requestApproved => 'Request approved';

  @override
  String get requestDenied => 'Request denied';

  @override
  String failedToSubmit(String error) {
    return 'Failed to submit: $error';
  }

  @override
  String get duplicateProposition => 'This proposition already exists in this round';

  @override
  String failedToStartPhase(String error) {
    return 'Failed to start phase: $error';
  }

  @override
  String failedToAdvancePhase(String error) {
    return 'Failed to advance phase: $error';
  }

  @override
  String failedToCompleteRating(String error) {
    return 'Failed to complete rating: $error';
  }

  @override
  String failedToDelete(String error) {
    return 'Failed to delete: $error';
  }

  @override
  String failedToDeleteChat(String error) {
    return 'Failed to delete chat: $error';
  }

  @override
  String failedToLeaveChat(String error) {
    return 'Failed to leave chat: $error';
  }

  @override
  String failedToKickParticipant(String error) {
    return 'Failed to kick participant: $error';
  }

  @override
  String failedToPauseChat(String error) {
    return 'Failed to pause chat: $error';
  }

  @override
  String error(String error) {
    return 'Error: $error';
  }

  @override
  String get noPendingRequests => 'No pending requests';

  @override
  String get newRequestsWillAppear => 'New requests will appear here';

  @override
  String participantsJoined(int count) {
    return '$count participants have joined';
  }

  @override
  String waitingForMoreParticipants(int count) {
    return 'Waiting for $count more participant(s) to join';
  }

  @override
  String get scheduled => 'Scheduled';

  @override
  String get chatOutsideSchedule => 'Chat is outside schedule window';

  @override
  String nextWindowStarts(String dateTime) {
    return 'Next window starts $dateTime';
  }

  @override
  String get scheduleWindows => 'Schedule windows:';

  @override
  String get scheduledToStart => 'Scheduled to start';

  @override
  String get chatWillAutoStart => 'The chat will automatically start at the scheduled time.';

  @override
  String submittedCount(int submitted, int total) {
    return '$submitted/$total submitted';
  }

  @override
  String propositionCollected(int count) {
    return '$count proposition collected';
  }

  @override
  String propositionsCollected(int count) {
    return '$count propositions collected';
  }

  @override
  String get timeExpired => 'Time expired';

  @override
  String get noDataAvailable => 'No data available';

  @override
  String get tryAgain => 'Try Again';

  @override
  String get requireApproval => 'Require approval';

  @override
  String get requireAuthentication => 'Require authentication';

  @override
  String get showPreviousResults => 'Show full results from past rounds';

  @override
  String get enableAdaptiveDuration => 'Enable adaptive duration';

  @override
  String get enableOneMindAI => 'Enable OneMind AI';

  @override
  String get enableAutoAdvanceProposing => 'Enable for ideas';

  @override
  String get enableAutoAdvanceRating => 'Enable for ratings';

  @override
  String get hideWhenOutsideSchedule => 'Hide when outside schedule';

  @override
  String get chatVisibleButPaused => 'Chat visible but paused outside schedule';

  @override
  String get chatHiddenUntilNext => 'Chat hidden until next scheduled window';

  @override
  String get timezone => 'Timezone';

  @override
  String get scheduleType => 'Schedule Type';

  @override
  String get oneTime => 'One-time';

  @override
  String get recurring => 'Recurring';

  @override
  String get startDateTime => 'Start Date & Time';

  @override
  String get scheduleWindowsLabel => 'Schedule Windows';

  @override
  String get addWindow => 'Add Window';

  @override
  String get searchTimezone => 'Search timezone...';

  @override
  String get manual => 'Manual';

  @override
  String get auto => 'Auto';

  @override
  String get credits => 'Credits';

  @override
  String get refillAmountMustBeGreater => 'Refill amount must be greater than threshold';

  @override
  String get autoRefillSettingsUpdated => 'Auto-refill settings updated';

  @override
  String get autoRefillEnabled => 'Auto-refill enabled';

  @override
  String get autoRefillDisabled => 'Auto-refill disabled';

  @override
  String get saveSettings => 'Save Settings';

  @override
  String get removeCard => 'Remove Card';

  @override
  String get purchaseWithStripe => 'Purchase with Stripe';

  @override
  String get processing => 'Processing...';

  @override
  String get pageNotFound => 'Page Not Found';

  @override
  String get goHome => 'Go Home';

  @override
  String allPropositionsCount(int count) {
    return 'All Propositions ($count)';
  }

  @override
  String get hostCanModerateContent => 'As host, you can moderate content. Submitter identity is hidden.';

  @override
  String get yourPropositionLabel => '(Your proposition)';

  @override
  String get previousWinnerLabel => '(Previous winner)';

  @override
  String get cannotBeUndone => 'This action cannot be undone.';

  @override
  String deleteChatConfirmation(String chatName) {
    return 'Are you sure you want to delete \"$chatName\"?\n\nThis will permanently delete all propositions, ratings, and history. This action cannot be undone.';
  }

  @override
  String leaveChatConfirmation(String chatName) {
    return 'Are you sure you want to leave \"$chatName\"?\n\nYou will no longer see this chat in your list.';
  }

  @override
  String kickParticipantConfirmation(String participantName) {
    return 'Are you sure you want to remove \"$participantName\" from this chat?\n\nThey will not be able to rejoin without approval.';
  }

  @override
  String get pauseChatConfirmation => 'This will pause the current phase timer. Participants will see that the chat is paused by the host.';

  @override
  String get approveOrDenyRequests => 'Approve or deny requests to join this chat.';

  @override
  String get signedIn => 'Signed in';

  @override
  String get guest => 'Guest';

  @override
  String get approve => 'Approve';

  @override
  String get deny => 'Deny';

  @override
  String get initialMessage => 'Initial Message';

  @override
  String consensusNumber(int number) {
    return 'Consensus #$number';
  }

  @override
  String get kickParticipant => 'Kick participant';

  @override
  String get propositions => 'Propositions';

  @override
  String get leaderboard => 'Leaderboard';

  @override
  String get noLeaderboardData => 'No leaderboard data available';

  @override
  String get skip => 'Skip';

  @override
  String get skipped => 'Skipped';

  @override
  String skipsRemaining(int remaining) {
    return '$remaining skips remaining';
  }

  @override
  String get createChatTitle => 'Create Chat';

  @override
  String get enterYourNameLabel => 'Enter your name';

  @override
  String get nameVisibleToAll => 'Your name will be visible to all participants';

  @override
  String get basicInfo => 'Basic Info';

  @override
  String get chatNameRequired => 'Chat Name *';

  @override
  String get chatNameHint => 'e.g., Team Lunch Friday';

  @override
  String get required => 'Required';

  @override
  String get initialMessageRequired => 'Initial Message *';

  @override
  String get initialMessageOptional => 'Initial Message (Optional)';

  @override
  String get initialMessageHint => 'The opening topic or question';

  @override
  String get initialMessageHelperText => 'Participants will know you wrote this since you created the chat';

  @override
  String get descriptionOptional => 'Description (Optional)';

  @override
  String get descriptionHint => 'Additional context';

  @override
  String get visibility => 'Visibility';

  @override
  String get whoCanJoin => 'Who can find and join this chat?';

  @override
  String get accessPublic => 'Public';

  @override
  String get accessPublicDesc => 'Anyone can discover and join';

  @override
  String get accessCode => 'Invite Code';

  @override
  String get accessCodeDesc => 'Share a 6-character code to join';

  @override
  String get accessEmail => 'Email Invite Only';

  @override
  String get accessEmailDesc => 'Only invited email addresses can join';

  @override
  String get instantJoin => 'Users join instantly';

  @override
  String get inviteByEmail => 'Invite by Email';

  @override
  String get inviteEmailOnly => 'Only invited email addresses can join this chat';

  @override
  String get emailAddress => 'Email address';

  @override
  String get emailHint => 'user@example.com';

  @override
  String get invalidEmail => 'Please enter a valid email address';

  @override
  String get addEmailToSend => 'Add at least one email to send invites';

  @override
  String get facilitationMode => 'How Phases Run';

  @override
  String get facilitationDesc => 'Choose between manual control or automatic timers for phase transitions.';

  @override
  String get modeManual => 'Manual';

  @override
  String get modeAuto => 'Auto';

  @override
  String get modeManualDesc => 'You control when each phase starts and ends. No timers.';

  @override
  String get modeAutoDesc => 'Timers run automatically. You can still end phases early.';

  @override
  String get autoStartParticipants => 'Start when this many join';

  @override
  String get ratingStartMode => 'Rating Start Mode';

  @override
  String get ratingStartModeDesc => 'Controls how the rating phase begins after proposing ends.';

  @override
  String get ratingAutoDesc => 'Rating starts immediately after proposing ends or threshold is met.';

  @override
  String get ratingManualDesc => 'After proposing ends, you choose when to start rating (e.g., the next day).';

  @override
  String phaseFlowExplanation(String duration, int threshold, int minimum) {
    return 'Each phase runs for up to $duration, but ends early if $threshold people participate. Won\'t end until at least $minimum ideas exist (timer extends if needed).';
  }

  @override
  String get enableSchedule => 'Enable Schedule';

  @override
  String get restrictChatRoom => 'Restrict when the chat room is open';

  @override
  String get timers => 'Timers';

  @override
  String get useSameDuration => 'Same duration for both phases';

  @override
  String get useSameDurationDesc => 'Use the same time limit for proposing and rating';

  @override
  String get phaseDuration => 'Phase Duration';

  @override
  String get proposing => 'Proposing';

  @override
  String get rating => 'Rating';

  @override
  String get preset5min => '5 min';

  @override
  String get preset30min => '30 min';

  @override
  String get preset1hour => '1 hour';

  @override
  String get preset1day => '1 day';

  @override
  String get presetCustom => 'Custom';

  @override
  String get duration1min => '1 min';

  @override
  String get duration2min => '2 min';

  @override
  String get duration10min => '10 min';

  @override
  String get duration2hours => '2 hours';

  @override
  String get duration4hours => '4 hours';

  @override
  String get duration8hours => '8 hours';

  @override
  String get duration12hours => '12 hours';

  @override
  String get hours => 'Hours';

  @override
  String get minutes => 'Minutes';

  @override
  String get max24h => '(max 24h)';

  @override
  String get minimumToAdvance => 'Required Participation';

  @override
  String get timeExtendsAutomatically => 'Phase won\'t end until requirements are met';

  @override
  String get proposingMinimum => 'Ideas needed';

  @override
  String proposingMinimumDesc(int count) {
    return 'Phase won\'t end until $count ideas are submitted';
  }

  @override
  String get ratingMinimum => 'Ratings needed';

  @override
  String ratingMinimumDesc(int count) {
    return 'Phase won\'t end until each idea has $count ratings';
  }

  @override
  String get autoAdvanceAt => 'End Phase Early';

  @override
  String get skipTimerEarly => 'Phase can end early when thresholds are reached';

  @override
  String whenPercentSubmit(int percent) {
    return 'When $percent% of participants submit';
  }

  @override
  String get minParticipantsSubmit => 'Ideas needed';

  @override
  String get minAvgRaters => 'Ratings needed';

  @override
  String proposingThresholdPreview(int threshold, int participants, int percent) {
    return 'Phase ends early when $threshold of $participants participants submit ideas ($percent%)';
  }

  @override
  String proposingThresholdPreviewSimple(int threshold) {
    return 'Phase ends early when $threshold ideas are submitted';
  }

  @override
  String ratingThresholdPreview(int threshold) {
    return 'Phase ends early when each idea has $threshold ratings';
  }

  @override
  String get consensusSettings => 'Consensus Settings';

  @override
  String get confirmationRounds => 'Confirmation rounds';

  @override
  String get firstWinnerConsensus => 'First winner reaches consensus immediately';

  @override
  String mustWinConsecutive(int count) {
    return 'Same proposition must win $count rounds in a row';
  }

  @override
  String get showFullResults => 'Show full results from past rounds';

  @override
  String get seeAllPropositions => 'Users see all propositions and ratings';

  @override
  String get seeWinningOnly => 'Users only see the winning proposition';

  @override
  String get propositionLimits => 'Proposition Limits';

  @override
  String get propositionsPerUser => 'Propositions per user';

  @override
  String get onePropositionPerRound => 'Each user can submit 1 proposition per round';

  @override
  String nPropositionsPerRound(int count) {
    return 'Each user can submit up to $count propositions per round';
  }

  @override
  String get adaptiveDuration => 'Adaptive Duration';

  @override
  String get adjustDurationDesc => 'Auto-adjust phase duration based on participation';

  @override
  String get durationAdjusts => 'Duration adjusts based on participation';

  @override
  String get fixedDurations => 'Fixed phase durations';

  @override
  String get usesThresholds => 'Uses early advance thresholds to determine participation';

  @override
  String adjustmentPercent(int percent) {
    return 'Adjustment: $percent%';
  }

  @override
  String get minDuration => 'Minimum duration';

  @override
  String get maxDuration => 'Maximum duration';

  @override
  String get aiParticipant => 'AI Participant';

  @override
  String get enableAI => 'Enable OneMind AI';

  @override
  String get aiPropositionsPerRound => 'AI propositions per round';

  @override
  String get scheduleTypeLabel => 'Schedule Type';

  @override
  String get scheduleOneTime => 'One-time';

  @override
  String get scheduleRecurring => 'Recurring';

  @override
  String get hideOutsideSchedule => 'Hide when outside schedule';

  @override
  String get visiblePaused => 'Chat visible but paused outside schedule';

  @override
  String get hiddenUntilWindow => 'Chat hidden until next scheduled window';

  @override
  String get timezoneLabel => 'Timezone';

  @override
  String get scheduleWindowsTitle => 'Schedule Windows';

  @override
  String get addWindowButton => 'Add Window';

  @override
  String get scheduleWindowsDesc => 'Define when the chat is active. Supports overnight windows (e.g., 11pm to 1am next day).';

  @override
  String windowNumber(int n) {
    return 'Window $n';
  }

  @override
  String get removeWindow => 'Remove window';

  @override
  String get startDay => 'Start Day';

  @override
  String get endDay => 'End Day';

  @override
  String get daySun => 'Sun';

  @override
  String get dayMon => 'Mon';

  @override
  String get dayTue => 'Tue';

  @override
  String get dayWed => 'Wed';

  @override
  String get dayThu => 'Thu';

  @override
  String get dayFri => 'Fri';

  @override
  String get daySat => 'Sat';

  @override
  String get timerWarningTitle => 'Timer Warning';

  @override
  String timerWarningContent(int minutes) {
    return 'Your phase timers are longer than the $minutes-minute schedule window.\n\nPhases may extend beyond the scheduled time, or pause when the window closes.\n\nConsider using shorter timers (5 min or 30 min) for scheduled sessions.';
  }

  @override
  String get adjustSettingsButton => 'Adjust Settings';

  @override
  String get continueAnywayButton => 'Continue Anyway';

  @override
  String get chatCreatedTitle => 'Chat Created!';

  @override
  String get chatNowPublicTitle => 'Your chat is now public!';

  @override
  String anyoneCanJoinDiscover(String name) {
    return 'Anyone can find and join \"$name\" from the Discover page.';
  }

  @override
  String invitesSentTitle(int count) {
    return '$count invites sent!';
  }

  @override
  String get noInvitesSentTitle => 'No invites sent';

  @override
  String get inviteOnlyMessage => 'Only invited users can join this chat.';

  @override
  String get shareCodeInstruction => 'Share this code with participants:';

  @override
  String get codeCopied => 'Invite code copied to clipboard';

  @override
  String get joinScreenTitle => 'Join Chat';

  @override
  String get noTokenOrCode => 'No invite token or code provided';

  @override
  String get invalidExpiredInvite => 'This invite link is invalid or has expired';

  @override
  String get inviteOnlyError => 'This chat requires an email invite. Please use the invite link sent to your email.';

  @override
  String get invalidInviteTitle => 'Invalid Invite';

  @override
  String get invalidInviteDefault => 'This invite link is not valid.';

  @override
  String get invitedToJoin => 'You\'re invited to join';

  @override
  String get enterNameToJoin => 'Enter your name to join:';

  @override
  String get nameVisibleNotice => 'This name will be visible to other participants.';

  @override
  String get requiresApprovalNotice => 'This chat requires host approval to join.';

  @override
  String get requestToJoinButton => 'Request to Join';

  @override
  String get joinChatButton => 'Join Chat';

  @override
  String get creditsTitle => 'Credits';

  @override
  String get yourBalance => 'Your Balance';

  @override
  String get paidCredits => 'Paid Credits';

  @override
  String get freeThisMonth => 'Free This Month';

  @override
  String get totalAvailable => 'Total Available';

  @override
  String get userRounds => 'user-rounds';

  @override
  String freeTierResets(String date) {
    return 'Free tier resets $date';
  }

  @override
  String get buyCredits => 'Buy Credits';

  @override
  String get pricingInfo => '1 credit = 1 user-round = \$0.01';

  @override
  String get total => 'Total';

  @override
  String get autoRefillTitle => 'Auto-Refill';

  @override
  String get autoRefillDesc => 'Automatically purchase credits when balance falls below threshold';

  @override
  String lastError(String error) {
    return 'Last error: $error';
  }

  @override
  String get autoRefillComingSoon => 'Auto-refill setup coming soon. For now, purchase credits manually above.';

  @override
  String get whenBelow => 'When below';

  @override
  String get refillTo => 'Refill to';

  @override
  String get disableAutoRefillMessage => 'This will disable auto-refill. You can add a new payment method later.';

  @override
  String get recentTransactions => 'Recent Transactions';

  @override
  String get noTransactionHistory => 'No transaction history';

  @override
  String get chatSettingsTitle => 'Chat Settings';

  @override
  String get accessVisibility => 'Access & Visibility';

  @override
  String get accessMethod => 'Access Method';

  @override
  String get facilitation => 'Facilitation';

  @override
  String get startMode => 'Start Mode';

  @override
  String get autoStartThreshold => 'Auto-Start Threshold';

  @override
  String nParticipants(int n) {
    return '$n participants';
  }

  @override
  String get proposingDuration => 'Proposing Duration';

  @override
  String get ratingDuration => 'Rating Duration';

  @override
  String nSeconds(int n) {
    return '$n seconds';
  }

  @override
  String nMinutes(int n) {
    return '$n minutes';
  }

  @override
  String nHours(int n) {
    return '$n hours';
  }

  @override
  String nDays(int n) {
    return '$n days';
  }

  @override
  String get minimumRequirements => 'Minimum Requirements';

  @override
  String nPropositions(int n) {
    return '$n propositions';
  }

  @override
  String nAvgRaters(double n) {
    return '$n avg raters';
  }

  @override
  String get earlyAdvanceThresholds => 'Early Advance Thresholds';

  @override
  String get proposingThreshold => 'Proposing Threshold';

  @override
  String get ratingThreshold => 'Rating Threshold';

  @override
  String nConsecutiveWins(int n) {
    return '$n consecutive wins';
  }

  @override
  String get enabled => 'Enabled';

  @override
  String nPerRound(int n) {
    return '$n per round';
  }

  @override
  String get scheduledStart => 'Scheduled Start';

  @override
  String get windows => 'Windows';

  @override
  String nConfigured(int n) {
    return '$n configured';
  }

  @override
  String get visibleOutsideSchedule => 'Visible Outside Schedule';

  @override
  String get chatSettings => 'Chat Settings';

  @override
  String get chatName => 'Name';

  @override
  String get chatDescription => 'Description';

  @override
  String get accessAndVisibility => 'Access & Visibility';

  @override
  String get autoMode => 'Auto';

  @override
  String get avgRatersPerProposition => 'avg raters per proposition';

  @override
  String get consensus => 'Consensus';

  @override
  String get aiPropositions => 'AI Propositions';

  @override
  String get perRound => 'per round';

  @override
  String get schedule => 'Schedule';

  @override
  String get configured => 'configured';

  @override
  String get publicAccess => 'Public';

  @override
  String get inviteCodeAccess => 'Invite Code';

  @override
  String get inviteOnlyAccess => 'Invite Only';

  @override
  String get privacyPolicyTitle => 'Privacy Policy';

  @override
  String get termsOfServiceTitle => 'Terms of Service';

  @override
  String get legalDocuments => 'Legal';

  @override
  String get byContinuingYouAgree => 'By continuing, you agree to our';

  @override
  String get andText => 'and';

  @override
  String lastUpdated(String date) {
    return 'Last updated: $date';
  }

  @override
  String shareLinkTitle(String chatName) {
    return 'Share link to join $chatName';
  }

  @override
  String get shareButton => 'Share';

  @override
  String get copyLinkButton => 'Copy Link';

  @override
  String get linkCopied => 'Link copied to clipboard';

  @override
  String get enterCodeManually => 'Or enter code manually:';

  @override
  String get shareNotSupported => 'Share not available - link copied instead';

  @override
  String get orScan => 'or scan';

  @override
  String get tutorialNextButton => 'Next';

  @override
  String get tutorialChooseTemplate => 'Personalize Your Tutorial';

  @override
  String get tutorialChooseTemplateSubtitle => 'Choose a scenario that matters to you';

  @override
  String get tutorialTemplateCommunity => 'Community Decision';

  @override
  String get tutorialTemplateCommunityDesc => 'What should our neighborhood do together?';

  @override
  String get tutorialTemplateWorkplace => 'Workplace Culture';

  @override
  String get tutorialTemplateWorkplaceDesc => 'What should our team focus on?';

  @override
  String get tutorialTemplateWorld => 'Global Issues';

  @override
  String get tutorialTemplateWorldDesc => 'What global issue matters most?';

  @override
  String get tutorialTemplateFamily => 'Family';

  @override
  String get tutorialTemplateFamilyDesc => 'Where should we go on vacation?';

  @override
  String get tutorialTemplatePersonal => 'Personal Decision';

  @override
  String get tutorialTemplatePersonalDesc => 'What should I do after graduation?';

  @override
  String get tutorialTemplateGovernment => 'City Budget';

  @override
  String get tutorialTemplateGovernmentDesc => 'How should we spend the city budget?';

  @override
  String get tutorialTemplateCustom => 'Custom Topic';

  @override
  String get tutorialTemplateCustomDesc => 'Enter your own question';

  @override
  String get tutorialCustomQuestionHint => 'Type your question...';

  @override
  String tutorialRound1ResultTemplate(String winner) {
    return '\'$winner\' won this round! To become a permanent answer, it must win again next round.';
  }

  @override
  String tutorialRound2PromptTemplate(String winner) {
    return 'Seeing \'$winner\' as the group\'s current answer - can you think of something better?';
  }

  @override
  String get tutorialWelcomeTitle => 'Welcome to OneMind';

  @override
  String get tutorialWelcomeSubtitle => 'Learn how groups reach consensus together';

  @override
  String get tutorialWhatYoullLearn => 'In this tutorial, you\'ll:';

  @override
  String get tutorialBullet1 => 'Submit your ideas anonymously';

  @override
  String get tutorialBullet2 => 'Rate ideas from others';

  @override
  String get tutorialBullet3 => 'See how consensus is reached';

  @override
  String get tutorialTheQuestion => 'The question:';

  @override
  String get tutorialQuestion => 'What do we value?';

  @override
  String get tutorialStartButton => 'Start Tutorial';

  @override
  String get tutorialSkipButton => 'Skip tutorial';

  @override
  String get tutorialConsensusReached => 'Consensus Reached!';

  @override
  String tutorialWonTwoRounds(String proposition) {
    return '\"$proposition\" won 2 rounds in a row.';
  }

  @override
  String get tutorialAddedToChat => 'It\'s now added to the chat above.';

  @override
  String get tutorialFinishButton => 'Finish Tutorial';

  @override
  String get tutorialRound1Result => '\'Success\' won this round! To become a permanent answer, it must win again next round.';

  @override
  String get tutorialProposingHint => 'Submit an idea you want to become the group\'s answer.';

  @override
  String get tutorialProposingHintWithWinner => 'Can you think of something better? Submit an idea to challenge the current winner.';

  @override
  String get tutorialRatingHint => 'To prevent bias, everyone rates all ideas except their own. Yours is hidden from you but others will rate it.';

  @override
  String get tutorialRatingBinaryHint => 'Which idea do you prefer? Place it at the top (100). Use [swap] to flip them, then tap [check] to confirm.';

  @override
  String get tutorialRatingPositioningHint => 'Use [up] and [down] to move the highlighted idea. Tap [check] to place it. Use [undo] to undo a placement, and [zoomin] [zoomout] to zoom in and out.';

  @override
  String tutorialRound2Result(String proposition) {
    return 'Your idea \"$proposition\" won! If it wins next round, it will be permanently added to the chat.';
  }

  @override
  String get tutorialRound2Prompt => 'Seeing \'Success\' as the group\'s current answer - what do you think we REALLY value?';

  @override
  String get tutorialPropSuccess => 'Success';

  @override
  String get tutorialPropAdventure => 'Adventure';

  @override
  String get tutorialPropGrowth => 'Growth';

  @override
  String get tutorialPropHarmony => 'Harmony';

  @override
  String get tutorialPropInnovation => 'Innovation';

  @override
  String get tutorialPropFreedom => 'Freedom';

  @override
  String get tutorialPropSecurity => 'Security';

  @override
  String get tutorialPropStability => 'Stability';

  @override
  String get tutorialPropTravelAbroad => 'Travel Abroad';

  @override
  String get tutorialPropStartABusiness => 'Start a Business';

  @override
  String get tutorialPropGraduateSchool => 'Graduate School';

  @override
  String get tutorialPropGetAJobFirst => 'Get a Job First';

  @override
  String get tutorialPropTakeAGapYear => 'Take a Gap Year';

  @override
  String get tutorialPropFreelance => 'Freelance';

  @override
  String get tutorialPropMoveToANewCity => 'Move to a New City';

  @override
  String get tutorialPropVolunteerProgram => 'Volunteer Program';

  @override
  String get tutorialPropBeachResort => 'Beach Resort';

  @override
  String get tutorialPropMountainCabin => 'Mountain Cabin';

  @override
  String get tutorialPropCityTrip => 'City Trip';

  @override
  String get tutorialPropRoadTrip => 'Road Trip';

  @override
  String get tutorialPropCampingAdventure => 'Camping Adventure';

  @override
  String get tutorialPropCruise => 'Cruise';

  @override
  String get tutorialPropThemePark => 'Theme Park';

  @override
  String get tutorialPropCulturalExchange => 'Cultural Exchange';

  @override
  String get tutorialPropBlockParty => 'Block Party';

  @override
  String get tutorialPropCommunityGarden => 'Community Garden';

  @override
  String get tutorialPropNeighborhoodWatch => 'Neighborhood Watch';

  @override
  String get tutorialPropToolLibrary => 'Tool Library';

  @override
  String get tutorialPropMutualAidFund => 'Mutual Aid Fund';

  @override
  String get tutorialPropFreeLittleLibrary => 'Free Little Library';

  @override
  String get tutorialPropStreetMural => 'Street Mural';

  @override
  String get tutorialPropSkillShareNight => 'Skill-Share Night';

  @override
  String get tutorialPropFlexibleHours => 'Flexible Hours';

  @override
  String get tutorialPropMentalHealthSupport => 'Mental Health Support';

  @override
  String get tutorialPropTeamBuilding => 'Team Building';

  @override
  String get tutorialPropSkillsTraining => 'Skills Training';

  @override
  String get tutorialPropOpenCommunication => 'Open Communication';

  @override
  String get tutorialPropFairCompensation => 'Fair Compensation';

  @override
  String get tutorialPropWorkLifeBalance => 'Work-Life Balance';

  @override
  String get tutorialPropInnovationTime => 'Innovation Time';

  @override
  String get tutorialPropPublicTransportation => 'Public Transportation';

  @override
  String get tutorialPropSchoolFunding => 'School Funding';

  @override
  String get tutorialPropEmergencyServices => 'Emergency Services';

  @override
  String get tutorialPropRoadRepairs => 'Road Repairs';

  @override
  String get tutorialPropPublicHealth => 'Public Health';

  @override
  String get tutorialPropAffordableHousing => 'Affordable Housing';

  @override
  String get tutorialPropSmallBusinessGrants => 'Small Business Grants';

  @override
  String get tutorialPropParksAndRecreation => 'Parks & Recreation';

  @override
  String get tutorialPropClimateChange => 'Climate Change';

  @override
  String get tutorialPropGlobalPoverty => 'Global Poverty';

  @override
  String get tutorialPropAiGovernance => 'AI Governance';

  @override
  String get tutorialPropPandemicPreparedness => 'Pandemic Preparedness';

  @override
  String get tutorialPropNuclearDisarmament => 'Nuclear Disarmament';

  @override
  String get tutorialPropOceanConservation => 'Ocean Conservation';

  @override
  String get tutorialPropDigitalRights => 'Digital Rights';

  @override
  String get tutorialPropSpaceCooperation => 'Space Cooperation';

  @override
  String get tutorialDuplicateProposition => 'This idea already exists in this round. Try something different!';

  @override
  String get tutorialShareTitle => 'Share Your Chat';

  @override
  String get tutorialShareExplanation => 'To invite others to join your chat, tap the share button at the top of your screen.';

  @override
  String get tutorialShareTryIt => 'Try it now!';

  @override
  String get tutorialShareButtonHint => 'Tap the share button in the top right ↗';

  @override
  String get tutorialSkipMenuItem => 'Skip Tutorial';

  @override
  String get tutorialSkipConfirmTitle => 'Skip Tutorial?';

  @override
  String get tutorialSkipConfirmMessage => 'You can always access the tutorial later from the home screen.';

  @override
  String get tutorialSkipConfirmYes => 'Yes, Skip';

  @override
  String get tutorialSkipConfirmNo => 'Continue Tutorial';

  @override
  String get tutorialShareTooltip => 'Share Chat';

  @override
  String get tutorialYourIdea => 'Your idea';

  @override
  String get tutorialRateIdeas => 'Rate Ideas';

  @override
  String get tutorialSeeResultsHint => 'Tap below to see how all ideas ranked.';

  @override
  String get tutorialSeeResultsContinueHint => 'Great! Now you understand how the ranking works. Continue to try again in Round 2.';

  @override
  String get tutorialResultsBackHint => 'Press the back arrow when done viewing the results.';

  @override
  String deleteConsensusTitle(int number) {
    return 'Delete Consensus #$number?';
  }

  @override
  String get deleteConsensusMessage => 'This will restart the current cycle with a fresh round.';

  @override
  String get deleteInitialMessageTitle => 'Delete Initial Message?';

  @override
  String get deleteInitialMessageMessage => 'This will restart the current cycle with a fresh round.';

  @override
  String get editInitialMessage => 'Edit Initial Message';

  @override
  String get consensusDeleted => 'Consensus deleted';

  @override
  String get initialMessageUpdated => 'Initial message updated';

  @override
  String get initialMessageDeleted => 'Initial message deleted';

  @override
  String failedToDeleteConsensus(String error) {
    return 'Failed to delete consensus: $error';
  }

  @override
  String failedToUpdateInitialMessage(String error) {
    return 'Failed to update initial message: $error';
  }

  @override
  String failedToDeleteInitialMessage(String error) {
    return 'Failed to delete initial message: $error';
  }

  @override
  String get deleteTaskResultTitle => 'Delete Research Results?';

  @override
  String get deleteTaskResultMessage => 'The agent will re-research on the next heartbeat.';

  @override
  String get taskResultDeleted => 'Research results deleted';

  @override
  String failedToDeleteTaskResult(String error) {
    return 'Failed to delete research results: $error';
  }

  @override
  String get wizardStep1Title => 'What do you want to talk about?';

  @override
  String get wizardStep1Subtitle => 'This is the heart of your chat';

  @override
  String get wizardStep2Title => 'Set the pace';

  @override
  String get wizardStep2Subtitle => 'How long for each phase?';

  @override
  String get wizardOneLastThing => 'One last thing...';

  @override
  String get wizardProposingLabel => 'Proposing (submit ideas)';

  @override
  String get wizardRatingLabel => 'Rating (rank ideas)';

  @override
  String get back => 'Back';

  @override
  String get spectatingInsufficientCredits => 'Spectating — insufficient credits';

  @override
  String get creditPausedTitle => 'Paused — Insufficient Credits';

  @override
  String creditBalance(int balance) {
    return 'Balance: $balance credits';
  }

  @override
  String creditsNeeded(int count) {
    return 'Need $count credits to start round';
  }

  @override
  String get waitingForHostCredits => 'Waiting for host to add credits';

  @override
  String get buyMoreCredits => 'Buy Credits';

  @override
  String get forceAsConsensus => 'Force as Consensus';

  @override
  String get forceAsConsensusDescription => 'Submit directly as consensus, skipping voting';

  @override
  String get forceConsensus => 'Force Consensus';

  @override
  String get forceConsensusTitle => 'Force Consensus?';

  @override
  String get forceConsensusMessage => 'This will immediately set your proposition as the consensus and start a new cycle. All current round progress will be lost.';

  @override
  String get forceConsensusSuccess => 'Consensus forced successfully';

  @override
  String failedToForceConsensus(String error) {
    return 'Failed to force consensus: $error';
  }

  @override
  String get glossaryUserRoundTitle => 'user-round';

  @override
  String get glossaryUserRoundDef => 'One participant completing one round of rating. Each user-round costs 1 credit (\$0.01).';

  @override
  String get glossaryConsensusTitle => 'consensus';

  @override
  String get glossaryConsensusDef => 'When the same proposition wins multiple consecutive rounds, the group has reached consensus on that idea.';

  @override
  String get glossaryProposingTitle => 'proposing';

  @override
  String get glossaryProposingDef => 'The phase where participants submit their ideas anonymously for the group to consider.';

  @override
  String get glossaryRatingTitle => 'rating';

  @override
  String get glossaryRatingDef => 'The phase where participants rank all propositions on a 0–100 grid to determine the winner.';

  @override
  String get glossaryCycleTitle => 'cycle';

  @override
  String get glossaryCycleDef => 'A sequence of rounds working toward consensus. A new cycle starts after consensus is reached.';

  @override
  String get glossaryCreditBalanceTitle => 'credit balance';

  @override
  String get glossaryCreditBalanceDef => 'Credits fund rounds. 1 credit = 1 user-round = \$0.01. Free credits reset monthly.';

  @override
  String get enterTaskResult => 'Enter task result...';

  @override
  String get submitResult => 'Submit Result';

  @override
  String get taskResultSubmitted => 'Task result submitted';
}
