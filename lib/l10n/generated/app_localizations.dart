import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'OneMind'**
  String get appTitle;

  /// No description provided for @discover.
  ///
  /// In en, this message translates to:
  /// **'Discover'**
  String get discover;

  /// No description provided for @discoverPublicChats.
  ///
  /// In en, this message translates to:
  /// **'Discover public chats'**
  String get discoverPublicChats;

  /// No description provided for @discoverChats.
  ///
  /// In en, this message translates to:
  /// **'Discover Chats'**
  String get discoverChats;

  /// No description provided for @joinWithCode.
  ///
  /// In en, this message translates to:
  /// **'Join with Code'**
  String get joinWithCode;

  /// No description provided for @joinAnExistingChatWithInviteCode.
  ///
  /// In en, this message translates to:
  /// **'Join an existing chat with invite code'**
  String get joinAnExistingChatWithInviteCode;

  /// No description provided for @joinChat.
  ///
  /// In en, this message translates to:
  /// **'Join Chat'**
  String get joinChat;

  /// No description provided for @join.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get join;

  /// No description provided for @findChat.
  ///
  /// In en, this message translates to:
  /// **'Find Chat'**
  String get findChat;

  /// No description provided for @requestToJoin.
  ///
  /// In en, this message translates to:
  /// **'Request to Join'**
  String get requestToJoin;

  /// No description provided for @createChat.
  ///
  /// In en, this message translates to:
  /// **'Create Chat'**
  String get createChat;

  /// No description provided for @createANewChat.
  ///
  /// In en, this message translates to:
  /// **'Create a new chat'**
  String get createANewChat;

  /// No description provided for @chatCreated.
  ///
  /// In en, this message translates to:
  /// **'Chat Created!'**
  String get chatCreated;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @continue_.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continue_;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @yes.
  ///
  /// In en, this message translates to:
  /// **'Yes'**
  String get yes;

  /// No description provided for @no.
  ///
  /// In en, this message translates to:
  /// **'No'**
  String get no;

  /// No description provided for @officialOneMind.
  ///
  /// In en, this message translates to:
  /// **'Official OneMind'**
  String get officialOneMind;

  /// No description provided for @official.
  ///
  /// In en, this message translates to:
  /// **'OFFICIAL'**
  String get official;

  /// No description provided for @pending.
  ///
  /// In en, this message translates to:
  /// **'PENDING'**
  String get pending;

  /// No description provided for @pendingRequests.
  ///
  /// In en, this message translates to:
  /// **'Pending Requests'**
  String get pendingRequests;

  /// No description provided for @yourChats.
  ///
  /// In en, this message translates to:
  /// **'Your Chats'**
  String get yourChats;

  /// No description provided for @cancelRequest.
  ///
  /// In en, this message translates to:
  /// **'Cancel Request'**
  String get cancelRequest;

  /// No description provided for @cancelRequestQuestion.
  ///
  /// In en, this message translates to:
  /// **'Cancel your request to join \"{chatName}\"?'**
  String cancelRequestQuestion(String chatName);

  /// No description provided for @yesCancel.
  ///
  /// In en, this message translates to:
  /// **'Yes, Cancel'**
  String get yesCancel;

  /// No description provided for @requestCancelled.
  ///
  /// In en, this message translates to:
  /// **'Request cancelled'**
  String get requestCancelled;

  /// No description provided for @waitingForHostApproval.
  ///
  /// In en, this message translates to:
  /// **'Waiting for host approval'**
  String get waitingForHostApproval;

  /// No description provided for @hostApprovalRequired.
  ///
  /// In en, this message translates to:
  /// **'Host approval required to join'**
  String get hostApprovalRequired;

  /// No description provided for @noChatsYet.
  ///
  /// In en, this message translates to:
  /// **'No chats yet'**
  String get noChatsYet;

  /// No description provided for @discoverPublicChatsJoinOrCreate.
  ///
  /// In en, this message translates to:
  /// **'Discover public chats, join with a code, or create your own'**
  String get discoverPublicChatsJoinOrCreate;

  /// No description provided for @discoverPublicChatsButton.
  ///
  /// In en, this message translates to:
  /// **'Discover Public Chats'**
  String get discoverPublicChatsButton;

  /// No description provided for @noActiveChatsYet.
  ///
  /// In en, this message translates to:
  /// **'No active chats yet. Your approved chats will appear here.'**
  String get noActiveChatsYet;

  /// No description provided for @loadingChats.
  ///
  /// In en, this message translates to:
  /// **'Loading chats'**
  String get loadingChats;

  /// No description provided for @failedToLoadChats.
  ///
  /// In en, this message translates to:
  /// **'Failed to load chats'**
  String get failedToLoadChats;

  /// No description provided for @chatNotFound.
  ///
  /// In en, this message translates to:
  /// **'Chat not found'**
  String get chatNotFound;

  /// No description provided for @failedToLookupChat.
  ///
  /// In en, this message translates to:
  /// **'Failed to lookup chat'**
  String get failedToLookupChat;

  /// No description provided for @failedToJoinChat.
  ///
  /// In en, this message translates to:
  /// **'Failed to join chat: {error}'**
  String failedToJoinChat(String error);

  /// No description provided for @enterInviteCode.
  ///
  /// In en, this message translates to:
  /// **'Enter the 6-character invite code:'**
  String get enterInviteCode;

  /// No description provided for @pleaseEnterSixCharCode.
  ///
  /// In en, this message translates to:
  /// **'Please enter a 6-character code'**
  String get pleaseEnterSixCharCode;

  /// No description provided for @inviteCodeHint.
  ///
  /// In en, this message translates to:
  /// **'ABC123'**
  String get inviteCodeHint;

  /// No description provided for @hostedBy.
  ///
  /// In en, this message translates to:
  /// **'Hosted by {hostName}'**
  String hostedBy(String hostName);

  /// No description provided for @thisChatsRequiresInvite.
  ///
  /// In en, this message translates to:
  /// **'This chat requires an invite'**
  String get thisChatsRequiresInvite;

  /// No description provided for @enterEmailForInvite.
  ///
  /// In en, this message translates to:
  /// **'Enter the email your invite was sent to:'**
  String get enterEmailForInvite;

  /// No description provided for @yourEmailHint.
  ///
  /// In en, this message translates to:
  /// **'your@email.com'**
  String get yourEmailHint;

  /// No description provided for @pleaseEnterEmailAddress.
  ///
  /// In en, this message translates to:
  /// **'Please enter your email address'**
  String get pleaseEnterEmailAddress;

  /// No description provided for @pleaseEnterValidEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email address'**
  String get pleaseEnterValidEmail;

  /// No description provided for @noInviteFoundForEmail.
  ///
  /// In en, this message translates to:
  /// **'No invite found for this email address'**
  String get noInviteFoundForEmail;

  /// No description provided for @failedToValidateInvite.
  ///
  /// In en, this message translates to:
  /// **'Failed to validate invite'**
  String get failedToValidateInvite;

  /// No description provided for @pleaseVerifyEmailFirst.
  ///
  /// In en, this message translates to:
  /// **'Please verify your email first'**
  String get pleaseVerifyEmailFirst;

  /// No description provided for @verifyEmail.
  ///
  /// In en, this message translates to:
  /// **'Verify Email'**
  String get verifyEmail;

  /// No description provided for @emailVerified.
  ///
  /// In en, this message translates to:
  /// **'Email verified: {email}'**
  String emailVerified(String email);

  /// No description provided for @enterDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Enter your display name:'**
  String get enterDisplayName;

  /// No description provided for @yourName.
  ///
  /// In en, this message translates to:
  /// **'Your name'**
  String get yourName;

  /// No description provided for @yourNamePlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Your Name'**
  String get yourNamePlaceholder;

  /// No description provided for @displayName.
  ///
  /// In en, this message translates to:
  /// **'Display name'**
  String get displayName;

  /// No description provided for @enterYourName.
  ///
  /// In en, this message translates to:
  /// **'Enter your name'**
  String get enterYourName;

  /// No description provided for @pleaseEnterYourName.
  ///
  /// In en, this message translates to:
  /// **'Please enter your name'**
  String get pleaseEnterYourName;

  /// No description provided for @yourDisplayName.
  ///
  /// In en, this message translates to:
  /// **'Your display name'**
  String get yourDisplayName;

  /// No description provided for @yourNameVisibleToAll.
  ///
  /// In en, this message translates to:
  /// **'Your name will be visible to all participants'**
  String get yourNameVisibleToAll;

  /// No description provided for @usingSavedName.
  ///
  /// In en, this message translates to:
  /// **'Using your saved name'**
  String get usingSavedName;

  /// No description provided for @joinRequestSent.
  ///
  /// In en, this message translates to:
  /// **'Join request sent. Waiting for host approval.'**
  String get joinRequestSent;

  /// No description provided for @searchPublicChats.
  ///
  /// In en, this message translates to:
  /// **'Search public chats...'**
  String get searchPublicChats;

  /// No description provided for @noChatsFoundFor.
  ///
  /// In en, this message translates to:
  /// **'No chats found for \"{query}\"'**
  String noChatsFoundFor(String query);

  /// No description provided for @noPublicChatsAvailable.
  ///
  /// In en, this message translates to:
  /// **'No public chats available'**
  String get noPublicChatsAvailable;

  /// No description provided for @beFirstToCreate.
  ///
  /// In en, this message translates to:
  /// **'Be the first to create one!'**
  String get beFirstToCreate;

  /// No description provided for @failedToLoadPublicChats.
  ///
  /// In en, this message translates to:
  /// **'Failed to load public chats: {error}'**
  String failedToLoadPublicChats(String error);

  /// No description provided for @participantCount.
  ///
  /// In en, this message translates to:
  /// **'{count} participant'**
  String participantCount(int count);

  /// No description provided for @participantsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} participants'**
  String participantsCount(int count);

  /// No description provided for @enterYourNameTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter Your Name'**
  String get enterYourNameTitle;

  /// No description provided for @anonymous.
  ///
  /// In en, this message translates to:
  /// **'Anonymous'**
  String get anonymous;

  /// No description provided for @timerWarning.
  ///
  /// In en, this message translates to:
  /// **'Timer Warning'**
  String get timerWarning;

  /// No description provided for @timerWarningMessage.
  ///
  /// In en, this message translates to:
  /// **'Your phase timers are longer than the {minutes}-minute schedule window.\n\nPhases may extend beyond the scheduled time, or pause when the window closes.\n\nConsider using shorter timers (5 min or 30 min) for scheduled sessions.'**
  String timerWarningMessage(int minutes);

  /// No description provided for @adjustSettings.
  ///
  /// In en, this message translates to:
  /// **'Adjust Settings'**
  String get adjustSettings;

  /// No description provided for @continueAnyway.
  ///
  /// In en, this message translates to:
  /// **'Continue Anyway'**
  String get continueAnyway;

  /// No description provided for @chatNowPublic.
  ///
  /// In en, this message translates to:
  /// **'Your chat is now public!'**
  String get chatNowPublic;

  /// No description provided for @anyoneCanJoinFrom.
  ///
  /// In en, this message translates to:
  /// **'Anyone can find and join \"{chatName}\" from the Discover page.'**
  String anyoneCanJoinFrom(String chatName);

  /// No description provided for @invitesSent.
  ///
  /// In en, this message translates to:
  /// **'{count} invite sent!'**
  String invitesSent(int count);

  /// No description provided for @invitesSentPlural.
  ///
  /// In en, this message translates to:
  /// **'{count} invites sent!'**
  String invitesSentPlural(int count);

  /// No description provided for @noInvitesSent.
  ///
  /// In en, this message translates to:
  /// **'No invites sent'**
  String get noInvitesSent;

  /// No description provided for @onlyInvitedUsersCanJoin.
  ///
  /// In en, this message translates to:
  /// **'Only invited users can join this chat.'**
  String get onlyInvitedUsersCanJoin;

  /// No description provided for @shareCodeWithParticipants.
  ///
  /// In en, this message translates to:
  /// **'Share this code with participants:'**
  String get shareCodeWithParticipants;

  /// No description provided for @inviteCodeCopied.
  ///
  /// In en, this message translates to:
  /// **'Invite code copied to clipboard'**
  String get inviteCodeCopied;

  /// No description provided for @tapToCopy.
  ///
  /// In en, this message translates to:
  /// **'Tap to copy'**
  String get tapToCopy;

  /// No description provided for @showQrCode.
  ///
  /// In en, this message translates to:
  /// **'Show QR Code'**
  String get showQrCode;

  /// No description provided for @addEmailForInviteOnly.
  ///
  /// In en, this message translates to:
  /// **'Add at least one email address for invite-only mode'**
  String get addEmailForInviteOnly;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @english.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get english;

  /// No description provided for @spanish.
  ///
  /// In en, this message translates to:
  /// **'Espanol'**
  String get spanish;

  /// No description provided for @rankPropositions.
  ///
  /// In en, this message translates to:
  /// **'Rank Propositions'**
  String get rankPropositions;

  /// No description provided for @placing.
  ///
  /// In en, this message translates to:
  /// **'Placing: '**
  String get placing;

  /// No description provided for @rankedSuccessfully.
  ///
  /// In en, this message translates to:
  /// **'Ranked {count} propositions successfully!'**
  String rankedSuccessfully(int count);

  /// No description provided for @failedToSaveRankings.
  ///
  /// In en, this message translates to:
  /// **'Failed to save rankings'**
  String get failedToSaveRankings;

  /// No description provided for @chatPausedByHost.
  ///
  /// In en, this message translates to:
  /// **'Chat was paused by host'**
  String get chatPausedByHost;

  /// No description provided for @goBack.
  ///
  /// In en, this message translates to:
  /// **'Go Back'**
  String get goBack;

  /// No description provided for @ratePropositions.
  ///
  /// In en, this message translates to:
  /// **'Rate Propositions'**
  String get ratePropositions;

  /// No description provided for @submitRatings.
  ///
  /// In en, this message translates to:
  /// **'Submit Ratings'**
  String get submitRatings;

  /// No description provided for @failedToSubmitRatings.
  ///
  /// In en, this message translates to:
  /// **'Failed to submit ratings: {error}'**
  String failedToSubmitRatings(String error);

  /// No description provided for @roundResults.
  ///
  /// In en, this message translates to:
  /// **'Round {roundNumber} Results'**
  String roundResults(int roundNumber);

  /// No description provided for @noPropositionsToDisplay.
  ///
  /// In en, this message translates to:
  /// **'No propositions to display'**
  String get noPropositionsToDisplay;

  /// No description provided for @noPreviousWinner.
  ///
  /// In en, this message translates to:
  /// **'No previous winner'**
  String get noPreviousWinner;

  /// No description provided for @roundWinner.
  ///
  /// In en, this message translates to:
  /// **'Round {roundNumber} Winner'**
  String roundWinner(int roundNumber);

  /// No description provided for @roundWinners.
  ///
  /// In en, this message translates to:
  /// **'Round {roundNumber} Winners'**
  String roundWinners(int roundNumber);

  /// No description provided for @unknownProposition.
  ///
  /// In en, this message translates to:
  /// **'Unknown proposition'**
  String get unknownProposition;

  /// No description provided for @score.
  ///
  /// In en, this message translates to:
  /// **'Score: {score}'**
  String score(String score);

  /// No description provided for @soleWinsProgress.
  ///
  /// In en, this message translates to:
  /// **'Sole wins: {current}/{required}'**
  String soleWinsProgress(int current, int required);

  /// No description provided for @tiedWinNoConsensus.
  ///
  /// In en, this message translates to:
  /// **'Tied win (does not count toward consensus)'**
  String get tiedWinNoConsensus;

  /// No description provided for @seeAllResults.
  ///
  /// In en, this message translates to:
  /// **'See All Results'**
  String get seeAllResults;

  /// No description provided for @startPhase.
  ///
  /// In en, this message translates to:
  /// **'Start Phase'**
  String get startPhase;

  /// No description provided for @waiting.
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get waiting;

  /// No description provided for @waitingForHostToStart.
  ///
  /// In en, this message translates to:
  /// **'Waiting for host to start...'**
  String get waitingForHostToStart;

  /// No description provided for @roundNumber.
  ///
  /// In en, this message translates to:
  /// **'Round {roundNumber}'**
  String roundNumber(int roundNumber);

  /// No description provided for @viewAllPropositions.
  ///
  /// In en, this message translates to:
  /// **'View all propositions'**
  String get viewAllPropositions;

  /// No description provided for @chatIsPaused.
  ///
  /// In en, this message translates to:
  /// **'Chat is paused...'**
  String get chatIsPaused;

  /// No description provided for @shareYourIdea.
  ///
  /// In en, this message translates to:
  /// **'Share your idea...'**
  String get shareYourIdea;

  /// No description provided for @addAnotherIdea.
  ///
  /// In en, this message translates to:
  /// **'Add another idea...'**
  String get addAnotherIdea;

  /// No description provided for @submit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submit;

  /// No description provided for @addProposition.
  ///
  /// In en, this message translates to:
  /// **'Add Proposition'**
  String get addProposition;

  /// No description provided for @waitingForRatingPhase.
  ///
  /// In en, this message translates to:
  /// **'Waiting for rating phase...'**
  String get waitingForRatingPhase;

  /// No description provided for @endProposingStartRating.
  ///
  /// In en, this message translates to:
  /// **'End Proposing & Start Rating'**
  String get endProposingStartRating;

  /// No description provided for @proposingComplete.
  ///
  /// In en, this message translates to:
  /// **'Proposing Complete'**
  String get proposingComplete;

  /// No description provided for @reviewPropositionsStartRating.
  ///
  /// In en, this message translates to:
  /// **'Review propositions and start rating when ready.'**
  String get reviewPropositionsStartRating;

  /// No description provided for @waitingForHostToStartRating.
  ///
  /// In en, this message translates to:
  /// **'Waiting for host to start the rating phase.'**
  String get waitingForHostToStartRating;

  /// No description provided for @startRatingPhase.
  ///
  /// In en, this message translates to:
  /// **'Start Rating Phase'**
  String get startRatingPhase;

  /// No description provided for @ratingComplete.
  ///
  /// In en, this message translates to:
  /// **'Rating Complete'**
  String get ratingComplete;

  /// No description provided for @waitingForRatingPhaseEnd.
  ///
  /// In en, this message translates to:
  /// **'Waiting for rating phase to end.'**
  String get waitingForRatingPhaseEnd;

  /// No description provided for @rateAllPropositions.
  ///
  /// In en, this message translates to:
  /// **'Rate all {count} propositions'**
  String rateAllPropositions(int count);

  /// No description provided for @continueRating.
  ///
  /// In en, this message translates to:
  /// **'Continue Rating'**
  String get continueRating;

  /// No description provided for @startRating.
  ///
  /// In en, this message translates to:
  /// **'Start Rating'**
  String get startRating;

  /// No description provided for @endRatingStartNextRound.
  ///
  /// In en, this message translates to:
  /// **'End Rating & Start Next Round'**
  String get endRatingStartNextRound;

  /// No description provided for @chatPaused.
  ///
  /// In en, this message translates to:
  /// **'Chat Paused'**
  String get chatPaused;

  /// No description provided for @chatPausedByHostTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat Paused by Host'**
  String get chatPausedByHostTitle;

  /// No description provided for @timerStoppedTapResume.
  ///
  /// In en, this message translates to:
  /// **'The timer is stopped. Tap Resume in the app bar to continue.'**
  String get timerStoppedTapResume;

  /// No description provided for @hostPausedPleaseWait.
  ///
  /// In en, this message translates to:
  /// **'The host has paused this chat. Please wait for them to resume.'**
  String get hostPausedPleaseWait;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
