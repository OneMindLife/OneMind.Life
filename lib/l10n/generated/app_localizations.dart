import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_pt.dart';

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
    Locale('de'),
    Locale('en'),
    Locale('es'),
    Locale('fr'),
    Locale('pt'),
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'OneMind'**
  String get appTitle;

  /// No description provided for @howItWorks.
  ///
  /// In en, this message translates to:
  /// **'How it works'**
  String get howItWorks;

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

  /// No description provided for @joined.
  ///
  /// In en, this message translates to:
  /// **'Joined'**
  String get joined;

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

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @leave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get leave;

  /// No description provided for @kick.
  ///
  /// In en, this message translates to:
  /// **'Kick'**
  String get kick;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @resume.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resume;

  /// No description provided for @remove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get remove;

  /// No description provided for @clear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get clear;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

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

  /// No description provided for @nextUp.
  ///
  /// In en, this message translates to:
  /// **'Next up'**
  String get nextUp;

  /// No description provided for @nextUpWithCount.
  ///
  /// In en, this message translates to:
  /// **'Next up ({count})'**
  String nextUpWithCount(int count);

  /// No description provided for @wrappingUp.
  ///
  /// In en, this message translates to:
  /// **'Wrapping up'**
  String get wrappingUp;

  /// No description provided for @wrappingUpWithCount.
  ///
  /// In en, this message translates to:
  /// **'Wrapping up ({count})'**
  String wrappingUpWithCount(int count);

  /// No description provided for @inactive.
  ///
  /// In en, this message translates to:
  /// **'Inactive'**
  String get inactive;

  /// No description provided for @inactiveWithCount.
  ///
  /// In en, this message translates to:
  /// **'Inactive ({count})'**
  String inactiveWithCount(int count);

  /// No description provided for @allChats.
  ///
  /// In en, this message translates to:
  /// **'All chats'**
  String get allChats;

  /// No description provided for @allChatsWithCount.
  ///
  /// In en, this message translates to:
  /// **'All chats ({count})'**
  String allChatsWithCount(int count);

  /// No description provided for @noChatsHere.
  ///
  /// In en, this message translates to:
  /// **'Nothing here — you\'re all caught up.'**
  String get noChatsHere;

  /// No description provided for @enableNotificationsTitle.
  ///
  /// In en, this message translates to:
  /// **'Get notified when it\'s your turn'**
  String get enableNotificationsTitle;

  /// No description provided for @enableNotificationsBody.
  ///
  /// In en, this message translates to:
  /// **'We\'ll ping you when a round needs you.'**
  String get enableNotificationsBody;

  /// No description provided for @enableNotificationsCta.
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get enableNotificationsCta;

  /// No description provided for @notificationsBlockedTitle.
  ///
  /// In en, this message translates to:
  /// **'Notifications are blocked'**
  String get notificationsBlockedTitle;

  /// No description provided for @notificationsBlockedBody.
  ///
  /// In en, this message translates to:
  /// **'Unblock them in your browser\'s site settings to get notified.'**
  String get notificationsBlockedBody;

  /// No description provided for @gotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotIt;

  /// No description provided for @notNow.
  ///
  /// In en, this message translates to:
  /// **'Not now'**
  String get notNow;

  /// No description provided for @installOneMindTitle.
  ///
  /// In en, this message translates to:
  /// **'Install OneMind'**
  String get installOneMindTitle;

  /// No description provided for @installOneMindBody.
  ///
  /// In en, this message translates to:
  /// **'Add to your home screen for the best experience.'**
  String get installOneMindBody;

  /// No description provided for @installOneMindIosBody.
  ///
  /// In en, this message translates to:
  /// **'Tap Share then \"Add to Home Screen\".'**
  String get installOneMindIosBody;

  /// No description provided for @installCta.
  ///
  /// In en, this message translates to:
  /// **'Install'**
  String get installCta;

  /// No description provided for @lookingForMore.
  ///
  /// In en, this message translates to:
  /// **'Join one to keep going'**
  String get lookingForMore;

  /// No description provided for @lookingForMoreDescription.
  ///
  /// In en, this message translates to:
  /// **'Public chats with the most activity right now.'**
  String get lookingForMoreDescription;

  /// No description provided for @discoverPublicChatsCta.
  ///
  /// In en, this message translates to:
  /// **'Discover public chats'**
  String get discoverPublicChatsCta;

  /// No description provided for @seeAllPublicChats.
  ///
  /// In en, this message translates to:
  /// **'See all public chats'**
  String get seeAllPublicChats;

  /// No description provided for @nothingToJoinTitle.
  ///
  /// In en, this message translates to:
  /// **'Nothing new to join right now'**
  String get nothingToJoinTitle;

  /// No description provided for @nothingToJoinDescription.
  ///
  /// In en, this message translates to:
  /// **'Start your own chat and invite others.'**
  String get nothingToJoinDescription;

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
  /// **'Host must approve each request'**
  String get hostApprovalRequired;

  /// No description provided for @noChatsYet.
  ///
  /// In en, this message translates to:
  /// **'No chats yet'**
  String get noChatsYet;

  /// No description provided for @discoverPublicChatsJoinOrCreate.
  ///
  /// In en, this message translates to:
  /// **'Search for public chats above, or tap + to create your own.'**
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
  /// **'Your Name'**
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

  /// No description provided for @emailAlreadyAdded.
  ///
  /// In en, this message translates to:
  /// **'Email already added'**
  String get emailAlreadyAdded;

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

  /// No description provided for @portuguese.
  ///
  /// In en, this message translates to:
  /// **'Portugues'**
  String get portuguese;

  /// No description provided for @french.
  ///
  /// In en, this message translates to:
  /// **'Francais'**
  String get french;

  /// No description provided for @german.
  ///
  /// In en, this message translates to:
  /// **'Deutsch'**
  String get german;

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
  /// **'Failed to save ratings'**
  String get failedToSaveRankings;

  /// No description provided for @chatPausedByHost.
  ///
  /// In en, this message translates to:
  /// **'Chat was paused by host'**
  String get chatPausedByHost;

  /// No description provided for @ratingPhaseEnded.
  ///
  /// In en, this message translates to:
  /// **'Rating phase has ended'**
  String get ratingPhaseEnded;

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
  /// **'Rating Results'**
  String get roundResults;

  /// No description provided for @convergenceHistory.
  ///
  /// In en, this message translates to:
  /// **'Convergence {number} History'**
  String convergenceHistory(int number);

  /// No description provided for @convergenceNumber.
  ///
  /// In en, this message translates to:
  /// **'Convergence #{number}'**
  String convergenceNumber(int number);

  /// No description provided for @noPropositionsToDisplay.
  ///
  /// In en, this message translates to:
  /// **'No propositions to display'**
  String get noPropositionsToDisplay;

  /// No description provided for @noPreviousWinner.
  ///
  /// In en, this message translates to:
  /// **'No top candidate yet'**
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
  /// **'Tied win (does not count toward convergence)'**
  String get tiedWinNoConsensus;

  /// No description provided for @nWayTie.
  ///
  /// In en, this message translates to:
  /// **'{count}-WAY TIE'**
  String nWayTie(int count);

  /// No description provided for @winnerIndexOfTotal.
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}'**
  String winnerIndexOfTotal(int current, int total);

  /// No description provided for @seeAllResults.
  ///
  /// In en, this message translates to:
  /// **'See All Results'**
  String get seeAllResults;

  /// No description provided for @viewAllRatings.
  ///
  /// In en, this message translates to:
  /// **'View All Ratings'**
  String get viewAllRatings;

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

  /// No description provided for @previousWinner.
  ///
  /// In en, this message translates to:
  /// **'Current Top Candidate'**
  String get previousWinner;

  /// No description provided for @yourProposition.
  ///
  /// In en, this message translates to:
  /// **'Your Proposition'**
  String get yourProposition;

  /// No description provided for @yourPropositions.
  ///
  /// In en, this message translates to:
  /// **'Your Propositions'**
  String get yourPropositions;

  /// No description provided for @rate.
  ///
  /// In en, this message translates to:
  /// **'Rate'**
  String get rate;

  /// No description provided for @participants.
  ///
  /// In en, this message translates to:
  /// **'Participants'**
  String get participants;

  /// No description provided for @chatInfo.
  ///
  /// In en, this message translates to:
  /// **'Chat Info'**
  String get chatInfo;

  /// No description provided for @shareQrCode.
  ///
  /// In en, this message translates to:
  /// **'Share QR Code'**
  String get shareQrCode;

  /// No description provided for @joinRequests.
  ///
  /// In en, this message translates to:
  /// **'Join Requests'**
  String get joinRequests;

  /// No description provided for @resumeChat.
  ///
  /// In en, this message translates to:
  /// **'Resume Chat'**
  String get resumeChat;

  /// No description provided for @pauseChat.
  ///
  /// In en, this message translates to:
  /// **'Pause Chat'**
  String get pauseChat;

  /// No description provided for @turnMusicOn.
  ///
  /// In en, this message translates to:
  /// **'Turn music on'**
  String get turnMusicOn;

  /// No description provided for @turnMusicOff.
  ///
  /// In en, this message translates to:
  /// **'Turn music off'**
  String get turnMusicOff;

  /// No description provided for @leaveChat.
  ///
  /// In en, this message translates to:
  /// **'Leave Chat'**
  String get leaveChat;

  /// No description provided for @deleteChat.
  ///
  /// In en, this message translates to:
  /// **'Delete Chat'**
  String get deleteChat;

  /// No description provided for @host.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get host;

  /// No description provided for @deletePropositionQuestion.
  ///
  /// In en, this message translates to:
  /// **'Delete Proposition?'**
  String get deletePropositionQuestion;

  /// No description provided for @areYouSureDeleteProposition.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this proposition?'**
  String get areYouSureDeleteProposition;

  /// No description provided for @deleteChatQuestion.
  ///
  /// In en, this message translates to:
  /// **'Delete Chat?'**
  String get deleteChatQuestion;

  /// No description provided for @leaveChatQuestion.
  ///
  /// In en, this message translates to:
  /// **'Leave Chat?'**
  String get leaveChatQuestion;

  /// No description provided for @kickParticipantQuestion.
  ///
  /// In en, this message translates to:
  /// **'Kick Participant?'**
  String get kickParticipantQuestion;

  /// No description provided for @pauseChatQuestion.
  ///
  /// In en, this message translates to:
  /// **'Pause Chat?'**
  String get pauseChatQuestion;

  /// No description provided for @removePaymentMethodQuestion.
  ///
  /// In en, this message translates to:
  /// **'Remove Payment Method?'**
  String get removePaymentMethodQuestion;

  /// No description provided for @propositionDeleted.
  ///
  /// In en, this message translates to:
  /// **'Proposition deleted'**
  String get propositionDeleted;

  /// No description provided for @chatDeleted.
  ///
  /// In en, this message translates to:
  /// **'Chat deleted'**
  String get chatDeleted;

  /// No description provided for @youHaveLeftChat.
  ///
  /// In en, this message translates to:
  /// **'You have left the chat'**
  String get youHaveLeftChat;

  /// No description provided for @youHaveBeenRemoved.
  ///
  /// In en, this message translates to:
  /// **'You have been removed from this chat'**
  String get youHaveBeenRemoved;

  /// No description provided for @chatHasBeenDeleted.
  ///
  /// In en, this message translates to:
  /// **'This chat has been deleted'**
  String get chatHasBeenDeleted;

  /// No description provided for @participantRemoved.
  ///
  /// In en, this message translates to:
  /// **'{name} has been removed'**
  String participantRemoved(String name);

  /// No description provided for @chatPausedSuccess.
  ///
  /// In en, this message translates to:
  /// **'Chat paused'**
  String get chatPausedSuccess;

  /// No description provided for @requestApproved.
  ///
  /// In en, this message translates to:
  /// **'Request approved'**
  String get requestApproved;

  /// No description provided for @requestDenied.
  ///
  /// In en, this message translates to:
  /// **'Request denied'**
  String get requestDenied;

  /// No description provided for @failedToSubmit.
  ///
  /// In en, this message translates to:
  /// **'Failed to submit: {error}'**
  String failedToSubmit(String error);

  /// Error shown when user tries to submit a duplicate proposition
  ///
  /// In en, this message translates to:
  /// **'This proposition already exists in this round'**
  String get duplicateProposition;

  /// No description provided for @failedToStartPhase.
  ///
  /// In en, this message translates to:
  /// **'Failed to start phase: {error}'**
  String failedToStartPhase(String error);

  /// No description provided for @failedToAdvancePhase.
  ///
  /// In en, this message translates to:
  /// **'Failed to advance phase: {error}'**
  String failedToAdvancePhase(String error);

  /// No description provided for @failedToCompleteRating.
  ///
  /// In en, this message translates to:
  /// **'Failed to complete rating: {error}'**
  String failedToCompleteRating(String error);

  /// No description provided for @failedToDelete.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete: {error}'**
  String failedToDelete(String error);

  /// No description provided for @failedToDeleteChat.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete chat: {error}'**
  String failedToDeleteChat(String error);

  /// No description provided for @failedToLeaveChat.
  ///
  /// In en, this message translates to:
  /// **'Failed to leave chat: {error}'**
  String failedToLeaveChat(String error);

  /// No description provided for @failedToKickParticipant.
  ///
  /// In en, this message translates to:
  /// **'Failed to kick participant: {error}'**
  String failedToKickParticipant(String error);

  /// No description provided for @failedToPauseChat.
  ///
  /// In en, this message translates to:
  /// **'Failed to pause chat: {error}'**
  String failedToPauseChat(String error);

  /// No description provided for @error.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String error(String error);

  /// No description provided for @noPendingRequests.
  ///
  /// In en, this message translates to:
  /// **'No pending requests'**
  String get noPendingRequests;

  /// No description provided for @newRequestsWillAppear.
  ///
  /// In en, this message translates to:
  /// **'New requests will appear here'**
  String get newRequestsWillAppear;

  /// No description provided for @participantsJoined.
  ///
  /// In en, this message translates to:
  /// **'{count} participants have joined'**
  String participantsJoined(int count);

  /// No description provided for @waitingForMoreParticipants.
  ///
  /// In en, this message translates to:
  /// **'Waiting for {count} more participant(s) to join'**
  String waitingForMoreParticipants(int count);

  /// No description provided for @noMembersYetShareHint.
  ///
  /// In en, this message translates to:
  /// **'No other members yet. Tap the share button above to invite people.'**
  String get noMembersYetShareHint;

  /// No description provided for @scheduled.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get scheduled;

  /// No description provided for @chatOutsideSchedule.
  ///
  /// In en, this message translates to:
  /// **'Chat is outside schedule window'**
  String get chatOutsideSchedule;

  /// No description provided for @nextWindowStarts.
  ///
  /// In en, this message translates to:
  /// **'Next window starts {dateTime}'**
  String nextWindowStarts(String dateTime);

  /// No description provided for @scheduleWindows.
  ///
  /// In en, this message translates to:
  /// **'Schedule windows:'**
  String get scheduleWindows;

  /// No description provided for @scheduledToStart.
  ///
  /// In en, this message translates to:
  /// **'Scheduled to start'**
  String get scheduledToStart;

  /// No description provided for @chatWillAutoStart.
  ///
  /// In en, this message translates to:
  /// **'The chat will automatically start at the scheduled time.'**
  String get chatWillAutoStart;

  /// No description provided for @submittedCount.
  ///
  /// In en, this message translates to:
  /// **'{submitted}/{total} submitted'**
  String submittedCount(int submitted, int total);

  /// No description provided for @propositionCollected.
  ///
  /// In en, this message translates to:
  /// **'{count} proposition collected'**
  String propositionCollected(int count);

  /// No description provided for @propositionsCollected.
  ///
  /// In en, this message translates to:
  /// **'{count} propositions collected'**
  String propositionsCollected(int count);

  /// No description provided for @timeExpired.
  ///
  /// In en, this message translates to:
  /// **'Time expired'**
  String get timeExpired;

  /// No description provided for @noDataAvailable.
  ///
  /// In en, this message translates to:
  /// **'No data available'**
  String get noDataAvailable;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get tryAgain;

  /// No description provided for @requireApproval.
  ///
  /// In en, this message translates to:
  /// **'Require approval'**
  String get requireApproval;

  /// No description provided for @requireAuthentication.
  ///
  /// In en, this message translates to:
  /// **'Require authentication'**
  String get requireAuthentication;

  /// No description provided for @showPreviousResults.
  ///
  /// In en, this message translates to:
  /// **'Show full results from past rounds'**
  String get showPreviousResults;

  /// No description provided for @enableAdaptiveDuration.
  ///
  /// In en, this message translates to:
  /// **'Enable adaptive duration'**
  String get enableAdaptiveDuration;

  /// No description provided for @enableOneMindAI.
  ///
  /// In en, this message translates to:
  /// **'Enable OneMind AI'**
  String get enableOneMindAI;

  /// No description provided for @enableAutoAdvanceProposing.
  ///
  /// In en, this message translates to:
  /// **'Enable for ideas'**
  String get enableAutoAdvanceProposing;

  /// No description provided for @enableAutoAdvanceRating.
  ///
  /// In en, this message translates to:
  /// **'Enable for ratings'**
  String get enableAutoAdvanceRating;

  /// No description provided for @hideWhenOutsideSchedule.
  ///
  /// In en, this message translates to:
  /// **'Hide when outside schedule'**
  String get hideWhenOutsideSchedule;

  /// No description provided for @chatVisibleButPaused.
  ///
  /// In en, this message translates to:
  /// **'Chat visible but paused outside schedule'**
  String get chatVisibleButPaused;

  /// No description provided for @chatHiddenUntilNext.
  ///
  /// In en, this message translates to:
  /// **'Chat hidden until next scheduled window'**
  String get chatHiddenUntilNext;

  /// No description provided for @timezone.
  ///
  /// In en, this message translates to:
  /// **'Timezone'**
  String get timezone;

  /// No description provided for @scheduleType.
  ///
  /// In en, this message translates to:
  /// **'Schedule Type'**
  String get scheduleType;

  /// No description provided for @oneTime.
  ///
  /// In en, this message translates to:
  /// **'One-time'**
  String get oneTime;

  /// No description provided for @recurring.
  ///
  /// In en, this message translates to:
  /// **'Recurring'**
  String get recurring;

  /// No description provided for @startDateTime.
  ///
  /// In en, this message translates to:
  /// **'Start Date & Time'**
  String get startDateTime;

  /// No description provided for @scheduleWindowsLabel.
  ///
  /// In en, this message translates to:
  /// **'Schedule Windows'**
  String get scheduleWindowsLabel;

  /// No description provided for @addWindow.
  ///
  /// In en, this message translates to:
  /// **'Add Window'**
  String get addWindow;

  /// No description provided for @searchTimezone.
  ///
  /// In en, this message translates to:
  /// **'Search timezone...'**
  String get searchTimezone;

  /// No description provided for @manual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get manual;

  /// No description provided for @auto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get auto;

  /// No description provided for @credits.
  ///
  /// In en, this message translates to:
  /// **'Credits'**
  String get credits;

  /// No description provided for @refillAmountMustBeGreater.
  ///
  /// In en, this message translates to:
  /// **'Refill amount must be greater than threshold'**
  String get refillAmountMustBeGreater;

  /// No description provided for @autoRefillSettingsUpdated.
  ///
  /// In en, this message translates to:
  /// **'Auto-refill settings updated'**
  String get autoRefillSettingsUpdated;

  /// No description provided for @autoRefillEnabled.
  ///
  /// In en, this message translates to:
  /// **'Auto-refill enabled'**
  String get autoRefillEnabled;

  /// No description provided for @autoRefillDisabled.
  ///
  /// In en, this message translates to:
  /// **'Auto-refill disabled'**
  String get autoRefillDisabled;

  /// No description provided for @saveSettings.
  ///
  /// In en, this message translates to:
  /// **'Save Settings'**
  String get saveSettings;

  /// No description provided for @removeCard.
  ///
  /// In en, this message translates to:
  /// **'Remove Card'**
  String get removeCard;

  /// No description provided for @purchaseWithStripe.
  ///
  /// In en, this message translates to:
  /// **'Purchase with Stripe'**
  String get purchaseWithStripe;

  /// No description provided for @processing.
  ///
  /// In en, this message translates to:
  /// **'Processing...'**
  String get processing;

  /// No description provided for @pageNotFound.
  ///
  /// In en, this message translates to:
  /// **'Page Not Found'**
  String get pageNotFound;

  /// No description provided for @goHome.
  ///
  /// In en, this message translates to:
  /// **'Go Home'**
  String get goHome;

  /// No description provided for @somethingWentWrong.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong'**
  String get somethingWentWrong;

  /// No description provided for @pageNotFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'The page you\'re looking for doesn\'t exist.'**
  String get pageNotFoundMessage;

  /// No description provided for @demoTitle.
  ///
  /// In en, this message translates to:
  /// **'Demo'**
  String get demoTitle;

  /// No description provided for @allPropositionsCount.
  ///
  /// In en, this message translates to:
  /// **'All Propositions ({count})'**
  String allPropositionsCount(int count);

  /// No description provided for @hostCanModerateContent.
  ///
  /// In en, this message translates to:
  /// **'As host, you can moderate content. Submitter identity is hidden.'**
  String get hostCanModerateContent;

  /// No description provided for @yourPropositionLabel.
  ///
  /// In en, this message translates to:
  /// **'(Your proposition)'**
  String get yourPropositionLabel;

  /// No description provided for @previousWinnerLabel.
  ///
  /// In en, this message translates to:
  /// **'(Current Top Candidate)'**
  String get previousWinnerLabel;

  /// No description provided for @cannotBeUndone.
  ///
  /// In en, this message translates to:
  /// **'This action cannot be undone.'**
  String get cannotBeUndone;

  /// No description provided for @deleteChatConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{chatName}\"?\n\nThis will permanently delete all propositions, ratings, and history. This action cannot be undone.'**
  String deleteChatConfirmation(String chatName);

  /// No description provided for @leaveChatConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to leave \"{chatName}\"?'**
  String leaveChatConfirmation(String chatName);

  /// No description provided for @kickParticipantConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to remove \"{participantName}\" from this chat?\n\nThey will not be able to rejoin without approval.'**
  String kickParticipantConfirmation(String participantName);

  /// No description provided for @pauseChatConfirmation.
  ///
  /// In en, this message translates to:
  /// **'This will pause the current phase timer. Participants will see that the chat is paused by the host.'**
  String get pauseChatConfirmation;

  /// No description provided for @approveOrDenyRequests.
  ///
  /// In en, this message translates to:
  /// **'Approve or deny requests to join this chat.'**
  String get approveOrDenyRequests;

  /// No description provided for @signedIn.
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get signedIn;

  /// No description provided for @guest.
  ///
  /// In en, this message translates to:
  /// **'Guest'**
  String get guest;

  /// No description provided for @approve.
  ///
  /// In en, this message translates to:
  /// **'Approve'**
  String get approve;

  /// No description provided for @deny.
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get deny;

  /// No description provided for @initialMessage.
  ///
  /// In en, this message translates to:
  /// **'Initial Message'**
  String get initialMessage;

  /// No description provided for @consensusNumber.
  ///
  /// In en, this message translates to:
  /// **'Convergence #{number}'**
  String consensusNumber(int number);

  /// No description provided for @kickParticipant.
  ///
  /// In en, this message translates to:
  /// **'Kick participant'**
  String get kickParticipant;

  /// No description provided for @propositions.
  ///
  /// In en, this message translates to:
  /// **'Propositions'**
  String get propositions;

  /// No description provided for @leaderboard.
  ///
  /// In en, this message translates to:
  /// **'Leaderboard'**
  String get leaderboard;

  /// No description provided for @noLeaderboardData.
  ///
  /// In en, this message translates to:
  /// **'No leaderboard data available'**
  String get noLeaderboardData;

  /// No description provided for @skip.
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get skip;

  /// No description provided for @skipped.
  ///
  /// In en, this message translates to:
  /// **'Skipped'**
  String get skipped;

  /// No description provided for @skipsRemaining.
  ///
  /// In en, this message translates to:
  /// **'{remaining} skips remaining'**
  String skipsRemaining(int remaining);

  /// No description provided for @createChatTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Chat'**
  String get createChatTitle;

  /// No description provided for @enterYourNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Enter your name'**
  String get enterYourNameLabel;

  /// No description provided for @nameVisibleToAll.
  ///
  /// In en, this message translates to:
  /// **'Your name will be visible to all participants'**
  String get nameVisibleToAll;

  /// No description provided for @basicInfo.
  ///
  /// In en, this message translates to:
  /// **'Basic Info'**
  String get basicInfo;

  /// No description provided for @chatNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Chat Name *'**
  String get chatNameRequired;

  /// No description provided for @chatNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., Saturday Plans'**
  String get chatNameHint;

  /// No description provided for @required.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get required;

  /// No description provided for @initialMessageRequired.
  ///
  /// In en, this message translates to:
  /// **'Initial Message *'**
  String get initialMessageRequired;

  /// No description provided for @initialMessageOptional.
  ///
  /// In en, this message translates to:
  /// **'Initial Message (Optional)'**
  String get initialMessageOptional;

  /// No description provided for @initialMessageLabel.
  ///
  /// In en, this message translates to:
  /// **'Initial Message'**
  String get initialMessageLabel;

  /// No description provided for @setFirstMessage.
  ///
  /// In en, this message translates to:
  /// **'Set initial message'**
  String get setFirstMessage;

  /// No description provided for @initialMessageHint.
  ///
  /// In en, this message translates to:
  /// **'e.g., What\'s the best way to spend a free Saturday?'**
  String get initialMessageHint;

  /// No description provided for @initialMessageHelperText.
  ///
  /// In en, this message translates to:
  /// **'Participants will know you wrote this since you created the chat'**
  String get initialMessageHelperText;

  /// No description provided for @descriptionOptional.
  ///
  /// In en, this message translates to:
  /// **'Description (Optional)'**
  String get descriptionOptional;

  /// No description provided for @descriptionHint.
  ///
  /// In en, this message translates to:
  /// **'Additional context'**
  String get descriptionHint;

  /// No description provided for @visibility.
  ///
  /// In en, this message translates to:
  /// **'Visibility'**
  String get visibility;

  /// No description provided for @whoCanJoin.
  ///
  /// In en, this message translates to:
  /// **'Who can find and join this chat?'**
  String get whoCanJoin;

  /// No description provided for @accessPublic.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get accessPublic;

  /// No description provided for @accessPublicDesc.
  ///
  /// In en, this message translates to:
  /// **'Anyone can discover and join'**
  String get accessPublicDesc;

  /// No description provided for @accessCode.
  ///
  /// In en, this message translates to:
  /// **'Invite Code'**
  String get accessCode;

  /// No description provided for @accessCodeDesc.
  ///
  /// In en, this message translates to:
  /// **'Share a 6-character code to join'**
  String get accessCodeDesc;

  /// No description provided for @accessEmail.
  ///
  /// In en, this message translates to:
  /// **'Email Invite Only'**
  String get accessEmail;

  /// No description provided for @accessEmailDesc.
  ///
  /// In en, this message translates to:
  /// **'Only invited email addresses can join'**
  String get accessEmailDesc;

  /// No description provided for @instantJoin.
  ///
  /// In en, this message translates to:
  /// **'Users join instantly'**
  String get instantJoin;

  /// No description provided for @inviteByEmail.
  ///
  /// In en, this message translates to:
  /// **'Invite by Email'**
  String get inviteByEmail;

  /// No description provided for @inviteEmailOnly.
  ///
  /// In en, this message translates to:
  /// **'Only invited email addresses can join this chat'**
  String get inviteEmailOnly;

  /// No description provided for @emailAddress.
  ///
  /// In en, this message translates to:
  /// **'Email address'**
  String get emailAddress;

  /// No description provided for @emailHint.
  ///
  /// In en, this message translates to:
  /// **'user@example.com'**
  String get emailHint;

  /// No description provided for @invalidEmail.
  ///
  /// In en, this message translates to:
  /// **'Please enter a valid email address'**
  String get invalidEmail;

  /// No description provided for @addEmailToSend.
  ///
  /// In en, this message translates to:
  /// **'Add at least one email to send invites'**
  String get addEmailToSend;

  /// No description provided for @facilitationMode.
  ///
  /// In en, this message translates to:
  /// **'How Phases Run'**
  String get facilitationMode;

  /// No description provided for @facilitationDesc.
  ///
  /// In en, this message translates to:
  /// **'Choose between manual control or automatic timers for phase transitions.'**
  String get facilitationDesc;

  /// No description provided for @modeManual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get modeManual;

  /// No description provided for @modeAuto.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get modeAuto;

  /// No description provided for @modeManualDesc.
  ///
  /// In en, this message translates to:
  /// **'You control when each phase starts and ends. No timers.'**
  String get modeManualDesc;

  /// No description provided for @modeAutoDesc.
  ///
  /// In en, this message translates to:
  /// **'Timers run automatically. You can still end phases early.'**
  String get modeAutoDesc;

  /// No description provided for @autoStartParticipants.
  ///
  /// In en, this message translates to:
  /// **'Start when this many join'**
  String get autoStartParticipants;

  /// No description provided for @ratingStartMode.
  ///
  /// In en, this message translates to:
  /// **'Rating Start Mode'**
  String get ratingStartMode;

  /// No description provided for @ratingStartModeDesc.
  ///
  /// In en, this message translates to:
  /// **'Controls how the rating phase begins after proposing ends.'**
  String get ratingStartModeDesc;

  /// No description provided for @ratingAutoDesc.
  ///
  /// In en, this message translates to:
  /// **'Rating starts immediately after proposing ends or threshold is met.'**
  String get ratingAutoDesc;

  /// No description provided for @ratingManualDesc.
  ///
  /// In en, this message translates to:
  /// **'After proposing ends, you choose when to start rating (e.g., the next day).'**
  String get ratingManualDesc;

  /// No description provided for @phaseFlowExplanation.
  ///
  /// In en, this message translates to:
  /// **'Each phase runs for up to {duration}, but ends early if {threshold} people participate. Won\'t end until at least {minimum} ideas exist (timer extends if needed).'**
  String phaseFlowExplanation(String duration, int threshold, int minimum);

  /// No description provided for @enableSchedule.
  ///
  /// In en, this message translates to:
  /// **'Enable Schedule'**
  String get enableSchedule;

  /// No description provided for @restrictChatRoom.
  ///
  /// In en, this message translates to:
  /// **'Restrict when the chat room is open'**
  String get restrictChatRoom;

  /// No description provided for @timers.
  ///
  /// In en, this message translates to:
  /// **'Timers'**
  String get timers;

  /// No description provided for @useSameDuration.
  ///
  /// In en, this message translates to:
  /// **'Same duration for both phases'**
  String get useSameDuration;

  /// No description provided for @useSameDurationDesc.
  ///
  /// In en, this message translates to:
  /// **'Use the same time limit for proposing and rating'**
  String get useSameDurationDesc;

  /// No description provided for @phaseDuration.
  ///
  /// In en, this message translates to:
  /// **'Phase Duration'**
  String get phaseDuration;

  /// No description provided for @proposing.
  ///
  /// In en, this message translates to:
  /// **'Proposing'**
  String get proposing;

  /// No description provided for @rating.
  ///
  /// In en, this message translates to:
  /// **'Rating'**
  String get rating;

  /// No description provided for @preset5min.
  ///
  /// In en, this message translates to:
  /// **'5 min'**
  String get preset5min;

  /// No description provided for @preset30min.
  ///
  /// In en, this message translates to:
  /// **'30 min'**
  String get preset30min;

  /// No description provided for @preset1hour.
  ///
  /// In en, this message translates to:
  /// **'1 hour'**
  String get preset1hour;

  /// No description provided for @preset1day.
  ///
  /// In en, this message translates to:
  /// **'1 day'**
  String get preset1day;

  /// No description provided for @presetCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get presetCustom;

  /// No description provided for @duration1min.
  ///
  /// In en, this message translates to:
  /// **'1 min'**
  String get duration1min;

  /// No description provided for @duration2min.
  ///
  /// In en, this message translates to:
  /// **'2 min'**
  String get duration2min;

  /// No description provided for @duration10min.
  ///
  /// In en, this message translates to:
  /// **'10 min'**
  String get duration10min;

  /// No description provided for @duration2hours.
  ///
  /// In en, this message translates to:
  /// **'2 hours'**
  String get duration2hours;

  /// No description provided for @duration4hours.
  ///
  /// In en, this message translates to:
  /// **'4 hours'**
  String get duration4hours;

  /// No description provided for @duration8hours.
  ///
  /// In en, this message translates to:
  /// **'8 hours'**
  String get duration8hours;

  /// No description provided for @duration12hours.
  ///
  /// In en, this message translates to:
  /// **'12 hours'**
  String get duration12hours;

  /// No description provided for @hours.
  ///
  /// In en, this message translates to:
  /// **'Hours'**
  String get hours;

  /// No description provided for @minutes.
  ///
  /// In en, this message translates to:
  /// **'Minutes'**
  String get minutes;

  /// No description provided for @max24h.
  ///
  /// In en, this message translates to:
  /// **'(max 24h)'**
  String get max24h;

  /// No description provided for @minimumToAdvance.
  ///
  /// In en, this message translates to:
  /// **'Required Participation'**
  String get minimumToAdvance;

  /// No description provided for @timeExtendsAutomatically.
  ///
  /// In en, this message translates to:
  /// **'Phase won\'t end until requirements are met'**
  String get timeExtendsAutomatically;

  /// No description provided for @proposingMinimum.
  ///
  /// In en, this message translates to:
  /// **'Ideas needed'**
  String get proposingMinimum;

  /// No description provided for @proposingMinimumDesc.
  ///
  /// In en, this message translates to:
  /// **'Phase won\'t end until {count} ideas are submitted'**
  String proposingMinimumDesc(int count);

  /// No description provided for @ratingMinimum.
  ///
  /// In en, this message translates to:
  /// **'Ratings needed'**
  String get ratingMinimum;

  /// No description provided for @ratingMinimumDesc.
  ///
  /// In en, this message translates to:
  /// **'Phase won\'t end until each idea has {count} ratings'**
  String ratingMinimumDesc(int count);

  /// No description provided for @autoAdvanceAt.
  ///
  /// In en, this message translates to:
  /// **'End Phase Early'**
  String get autoAdvanceAt;

  /// No description provided for @skipTimerEarly.
  ///
  /// In en, this message translates to:
  /// **'Phase can end early when thresholds are reached'**
  String get skipTimerEarly;

  /// No description provided for @whenPercentSubmit.
  ///
  /// In en, this message translates to:
  /// **'When {percent}% of participants submit'**
  String whenPercentSubmit(int percent);

  /// No description provided for @minParticipantsSubmit.
  ///
  /// In en, this message translates to:
  /// **'Ideas needed'**
  String get minParticipantsSubmit;

  /// No description provided for @minAvgRaters.
  ///
  /// In en, this message translates to:
  /// **'Ratings needed'**
  String get minAvgRaters;

  /// No description provided for @proposingThresholdPreview.
  ///
  /// In en, this message translates to:
  /// **'Phase ends early when {threshold} of {participants} participants submit ideas ({percent}%)'**
  String proposingThresholdPreview(
    int threshold,
    int participants,
    int percent,
  );

  /// No description provided for @proposingThresholdPreviewSimple.
  ///
  /// In en, this message translates to:
  /// **'Phase ends early when {threshold} ideas are submitted'**
  String proposingThresholdPreviewSimple(int threshold);

  /// No description provided for @ratingThresholdPreview.
  ///
  /// In en, this message translates to:
  /// **'Phase ends early when each idea has {threshold} ratings'**
  String ratingThresholdPreview(int threshold);

  /// No description provided for @consensusSettings.
  ///
  /// In en, this message translates to:
  /// **'Convergence Settings'**
  String get consensusSettings;

  /// No description provided for @confirmationRounds.
  ///
  /// In en, this message translates to:
  /// **'Confirmation rounds'**
  String get confirmationRounds;

  /// No description provided for @firstWinnerConsensus.
  ///
  /// In en, this message translates to:
  /// **'First winner reaches convergence immediately'**
  String get firstWinnerConsensus;

  /// No description provided for @mustWinConsecutive.
  ///
  /// In en, this message translates to:
  /// **'Same proposition must win {count} rounds in a row'**
  String mustWinConsecutive(int count);

  /// No description provided for @showFullResults.
  ///
  /// In en, this message translates to:
  /// **'Show full results from past rounds'**
  String get showFullResults;

  /// No description provided for @seeAllPropositions.
  ///
  /// In en, this message translates to:
  /// **'Users see all propositions and ratings'**
  String get seeAllPropositions;

  /// No description provided for @seeWinningOnly.
  ///
  /// In en, this message translates to:
  /// **'Users only see the winning proposition'**
  String get seeWinningOnly;

  /// No description provided for @propositionLimits.
  ///
  /// In en, this message translates to:
  /// **'Proposition Limits'**
  String get propositionLimits;

  /// No description provided for @propositionsPerUser.
  ///
  /// In en, this message translates to:
  /// **'Propositions per user'**
  String get propositionsPerUser;

  /// No description provided for @onePropositionPerRound.
  ///
  /// In en, this message translates to:
  /// **'Each user can submit 1 proposition per round'**
  String get onePropositionPerRound;

  /// No description provided for @nPropositionsPerRound.
  ///
  /// In en, this message translates to:
  /// **'Each user can submit up to {count} propositions per round'**
  String nPropositionsPerRound(int count);

  /// No description provided for @adaptiveDuration.
  ///
  /// In en, this message translates to:
  /// **'Adaptive Duration'**
  String get adaptiveDuration;

  /// No description provided for @adjustDurationDesc.
  ///
  /// In en, this message translates to:
  /// **'Auto-adjust phase duration based on participation'**
  String get adjustDurationDesc;

  /// No description provided for @durationAdjusts.
  ///
  /// In en, this message translates to:
  /// **'Duration adjusts based on participation'**
  String get durationAdjusts;

  /// No description provided for @fixedDurations.
  ///
  /// In en, this message translates to:
  /// **'Fixed phase durations'**
  String get fixedDurations;

  /// No description provided for @usesThresholds.
  ///
  /// In en, this message translates to:
  /// **'Uses early advance thresholds to determine participation'**
  String get usesThresholds;

  /// No description provided for @adjustmentPercent.
  ///
  /// In en, this message translates to:
  /// **'Adjustment: {percent}%'**
  String adjustmentPercent(int percent);

  /// No description provided for @minDuration.
  ///
  /// In en, this message translates to:
  /// **'Minimum duration'**
  String get minDuration;

  /// No description provided for @maxDuration.
  ///
  /// In en, this message translates to:
  /// **'Maximum duration'**
  String get maxDuration;

  /// No description provided for @aiParticipant.
  ///
  /// In en, this message translates to:
  /// **'AI Participant'**
  String get aiParticipant;

  /// No description provided for @enableAI.
  ///
  /// In en, this message translates to:
  /// **'Enable OneMind AI'**
  String get enableAI;

  /// No description provided for @aiPropositionsPerRound.
  ///
  /// In en, this message translates to:
  /// **'AI propositions per round'**
  String get aiPropositionsPerRound;

  /// No description provided for @scheduleTypeLabel.
  ///
  /// In en, this message translates to:
  /// **'Schedule Type'**
  String get scheduleTypeLabel;

  /// No description provided for @scheduleOneTime.
  ///
  /// In en, this message translates to:
  /// **'One-time'**
  String get scheduleOneTime;

  /// No description provided for @scheduleRecurring.
  ///
  /// In en, this message translates to:
  /// **'Recurring'**
  String get scheduleRecurring;

  /// No description provided for @hideOutsideSchedule.
  ///
  /// In en, this message translates to:
  /// **'Hide when outside schedule'**
  String get hideOutsideSchedule;

  /// No description provided for @visiblePaused.
  ///
  /// In en, this message translates to:
  /// **'Chat visible but paused outside schedule'**
  String get visiblePaused;

  /// No description provided for @hiddenUntilWindow.
  ///
  /// In en, this message translates to:
  /// **'Chat hidden until next scheduled window'**
  String get hiddenUntilWindow;

  /// No description provided for @timezoneLabel.
  ///
  /// In en, this message translates to:
  /// **'Timezone'**
  String get timezoneLabel;

  /// No description provided for @scheduleWindowsTitle.
  ///
  /// In en, this message translates to:
  /// **'Schedule Windows'**
  String get scheduleWindowsTitle;

  /// No description provided for @addWindowButton.
  ///
  /// In en, this message translates to:
  /// **'Add Window'**
  String get addWindowButton;

  /// No description provided for @scheduleWindowsDesc.
  ///
  /// In en, this message translates to:
  /// **'Define when the chat is active each week.'**
  String get scheduleWindowsDesc;

  /// No description provided for @windowNumber.
  ///
  /// In en, this message translates to:
  /// **'Window {n}'**
  String windowNumber(int n);

  /// No description provided for @removeWindow.
  ///
  /// In en, this message translates to:
  /// **'Remove window'**
  String get removeWindow;

  /// No description provided for @startDay.
  ///
  /// In en, this message translates to:
  /// **'Start Day'**
  String get startDay;

  /// No description provided for @endDay.
  ///
  /// In en, this message translates to:
  /// **'End Day'**
  String get endDay;

  /// No description provided for @daySun.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get daySun;

  /// No description provided for @dayMon.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get dayMon;

  /// No description provided for @dayTue.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get dayTue;

  /// No description provided for @dayWed.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get dayWed;

  /// No description provided for @dayThu.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get dayThu;

  /// No description provided for @dayFri.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get dayFri;

  /// No description provided for @daySat.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get daySat;

  /// No description provided for @timerWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'Timer Warning'**
  String get timerWarningTitle;

  /// No description provided for @timerWarningContent.
  ///
  /// In en, this message translates to:
  /// **'Your phase timers are longer than the {minutes}-minute schedule window.\n\nPhases may extend beyond the scheduled time, or pause when the window closes.\n\nConsider using shorter timers (5 min or 30 min) for scheduled sessions.'**
  String timerWarningContent(int minutes);

  /// No description provided for @adjustSettingsButton.
  ///
  /// In en, this message translates to:
  /// **'Adjust Settings'**
  String get adjustSettingsButton;

  /// No description provided for @continueAnywayButton.
  ///
  /// In en, this message translates to:
  /// **'Continue Anyway'**
  String get continueAnywayButton;

  /// No description provided for @chatCreatedTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat Created!'**
  String get chatCreatedTitle;

  /// No description provided for @chatNowPublicTitle.
  ///
  /// In en, this message translates to:
  /// **'Your chat is now public!'**
  String get chatNowPublicTitle;

  /// No description provided for @anyoneCanJoinDiscover.
  ///
  /// In en, this message translates to:
  /// **'Anyone can find and join \"{name}\" from the Discover page.'**
  String anyoneCanJoinDiscover(String name);

  /// No description provided for @invitesSentTitle.
  ///
  /// In en, this message translates to:
  /// **'{count} invites sent!'**
  String invitesSentTitle(int count);

  /// No description provided for @noInvitesSentTitle.
  ///
  /// In en, this message translates to:
  /// **'No invites sent'**
  String get noInvitesSentTitle;

  /// No description provided for @inviteOnlyMessage.
  ///
  /// In en, this message translates to:
  /// **'Only invited users can join this chat.'**
  String get inviteOnlyMessage;

  /// No description provided for @shareCodeInstruction.
  ///
  /// In en, this message translates to:
  /// **'Share this code with participants:'**
  String get shareCodeInstruction;

  /// No description provided for @codeCopied.
  ///
  /// In en, this message translates to:
  /// **'Invite code copied to clipboard'**
  String get codeCopied;

  /// No description provided for @joinScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Join Chat'**
  String get joinScreenTitle;

  /// No description provided for @noTokenOrCode.
  ///
  /// In en, this message translates to:
  /// **'No invite token or code provided'**
  String get noTokenOrCode;

  /// No description provided for @invalidExpiredInvite.
  ///
  /// In en, this message translates to:
  /// **'This invite link is invalid or has expired'**
  String get invalidExpiredInvite;

  /// No description provided for @inviteOnlyError.
  ///
  /// In en, this message translates to:
  /// **'This chat requires an email invite. Please use the invite link sent to your email.'**
  String get inviteOnlyError;

  /// No description provided for @invalidInviteTitle.
  ///
  /// In en, this message translates to:
  /// **'Invalid Invite'**
  String get invalidInviteTitle;

  /// No description provided for @invalidInviteDefault.
  ///
  /// In en, this message translates to:
  /// **'This invite link is not valid.'**
  String get invalidInviteDefault;

  /// No description provided for @invitedToJoin.
  ///
  /// In en, this message translates to:
  /// **'You\'re invited to join'**
  String get invitedToJoin;

  /// No description provided for @enterNameToJoin.
  ///
  /// In en, this message translates to:
  /// **'Enter your name to join:'**
  String get enterNameToJoin;

  /// No description provided for @nameVisibleNotice.
  ///
  /// In en, this message translates to:
  /// **'This name will be visible to other participants.'**
  String get nameVisibleNotice;

  /// No description provided for @requiresApprovalNotice.
  ///
  /// In en, this message translates to:
  /// **'This chat requires host approval to join.'**
  String get requiresApprovalNotice;

  /// No description provided for @requestToJoinButton.
  ///
  /// In en, this message translates to:
  /// **'Request to Join'**
  String get requestToJoinButton;

  /// No description provided for @joinChatButton.
  ///
  /// In en, this message translates to:
  /// **'Join Chat'**
  String get joinChatButton;

  /// No description provided for @creditsTitle.
  ///
  /// In en, this message translates to:
  /// **'Credits'**
  String get creditsTitle;

  /// No description provided for @yourBalance.
  ///
  /// In en, this message translates to:
  /// **'Your Balance'**
  String get yourBalance;

  /// No description provided for @paidCredits.
  ///
  /// In en, this message translates to:
  /// **'Paid Credits'**
  String get paidCredits;

  /// No description provided for @freeThisMonth.
  ///
  /// In en, this message translates to:
  /// **'Free This Month'**
  String get freeThisMonth;

  /// No description provided for @totalAvailable.
  ///
  /// In en, this message translates to:
  /// **'Total Available'**
  String get totalAvailable;

  /// No description provided for @userRounds.
  ///
  /// In en, this message translates to:
  /// **'user-rounds'**
  String get userRounds;

  /// No description provided for @freeTierResets.
  ///
  /// In en, this message translates to:
  /// **'Free tier resets {date}'**
  String freeTierResets(String date);

  /// No description provided for @buyCredits.
  ///
  /// In en, this message translates to:
  /// **'Buy Credits'**
  String get buyCredits;

  /// No description provided for @pricingInfo.
  ///
  /// In en, this message translates to:
  /// **'1 credit = 1 user-round = \$0.01'**
  String get pricingInfo;

  /// No description provided for @total.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get total;

  /// No description provided for @autoRefillTitle.
  ///
  /// In en, this message translates to:
  /// **'Auto-Refill'**
  String get autoRefillTitle;

  /// No description provided for @autoRefillDesc.
  ///
  /// In en, this message translates to:
  /// **'Automatically purchase credits when balance falls below threshold'**
  String get autoRefillDesc;

  /// No description provided for @lastError.
  ///
  /// In en, this message translates to:
  /// **'Last error: {error}'**
  String lastError(String error);

  /// No description provided for @autoRefillComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Auto-refill setup coming soon. For now, purchase credits manually above.'**
  String get autoRefillComingSoon;

  /// No description provided for @whenBelow.
  ///
  /// In en, this message translates to:
  /// **'When below'**
  String get whenBelow;

  /// No description provided for @refillTo.
  ///
  /// In en, this message translates to:
  /// **'Refill to'**
  String get refillTo;

  /// No description provided for @disableAutoRefillMessage.
  ///
  /// In en, this message translates to:
  /// **'This will disable auto-refill. You can add a new payment method later.'**
  String get disableAutoRefillMessage;

  /// No description provided for @recentTransactions.
  ///
  /// In en, this message translates to:
  /// **'Recent Transactions'**
  String get recentTransactions;

  /// No description provided for @noTransactionHistory.
  ///
  /// In en, this message translates to:
  /// **'No transaction history'**
  String get noTransactionHistory;

  /// No description provided for @chatSettingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat Settings'**
  String get chatSettingsTitle;

  /// No description provided for @accessVisibility.
  ///
  /// In en, this message translates to:
  /// **'Access & Visibility'**
  String get accessVisibility;

  /// No description provided for @accessMethod.
  ///
  /// In en, this message translates to:
  /// **'Access Method'**
  String get accessMethod;

  /// No description provided for @facilitation.
  ///
  /// In en, this message translates to:
  /// **'Facilitation'**
  String get facilitation;

  /// No description provided for @startMode.
  ///
  /// In en, this message translates to:
  /// **'Start Mode'**
  String get startMode;

  /// No description provided for @autoStartThreshold.
  ///
  /// In en, this message translates to:
  /// **'Auto-Start Threshold'**
  String get autoStartThreshold;

  /// No description provided for @nParticipants.
  ///
  /// In en, this message translates to:
  /// **'{n} participants'**
  String nParticipants(int n);

  /// No description provided for @proposingDuration.
  ///
  /// In en, this message translates to:
  /// **'Proposing Duration'**
  String get proposingDuration;

  /// No description provided for @ratingDuration.
  ///
  /// In en, this message translates to:
  /// **'Rating Duration'**
  String get ratingDuration;

  /// No description provided for @nSeconds.
  ///
  /// In en, this message translates to:
  /// **'{n} seconds'**
  String nSeconds(int n);

  /// No description provided for @nMinutes.
  ///
  /// In en, this message translates to:
  /// **'{n} minutes'**
  String nMinutes(int n);

  /// No description provided for @nHours.
  ///
  /// In en, this message translates to:
  /// **'{n} hours'**
  String nHours(int n);

  /// No description provided for @nDays.
  ///
  /// In en, this message translates to:
  /// **'{n} days'**
  String nDays(int n);

  /// No description provided for @minimumRequirements.
  ///
  /// In en, this message translates to:
  /// **'Minimum Requirements'**
  String get minimumRequirements;

  /// No description provided for @nPropositions.
  ///
  /// In en, this message translates to:
  /// **'{n} propositions'**
  String nPropositions(int n);

  /// No description provided for @nAvgRaters.
  ///
  /// In en, this message translates to:
  /// **'{n} avg raters'**
  String nAvgRaters(double n);

  /// No description provided for @earlyAdvanceThresholds.
  ///
  /// In en, this message translates to:
  /// **'Early Advance Thresholds'**
  String get earlyAdvanceThresholds;

  /// No description provided for @proposingThreshold.
  ///
  /// In en, this message translates to:
  /// **'Proposing Threshold'**
  String get proposingThreshold;

  /// No description provided for @ratingThreshold.
  ///
  /// In en, this message translates to:
  /// **'Rating Threshold'**
  String get ratingThreshold;

  /// No description provided for @nConsecutiveWins.
  ///
  /// In en, this message translates to:
  /// **'{n} consecutive wins'**
  String nConsecutiveWins(int n);

  /// No description provided for @enabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get enabled;

  /// No description provided for @nPerRound.
  ///
  /// In en, this message translates to:
  /// **'{n} per round'**
  String nPerRound(int n);

  /// No description provided for @scheduledStart.
  ///
  /// In en, this message translates to:
  /// **'Scheduled Start'**
  String get scheduledStart;

  /// No description provided for @windows.
  ///
  /// In en, this message translates to:
  /// **'Windows'**
  String get windows;

  /// No description provided for @nConfigured.
  ///
  /// In en, this message translates to:
  /// **'{n} configured'**
  String nConfigured(int n);

  /// No description provided for @visibleOutsideSchedule.
  ///
  /// In en, this message translates to:
  /// **'Visible Outside Schedule'**
  String get visibleOutsideSchedule;

  /// No description provided for @chatSettings.
  ///
  /// In en, this message translates to:
  /// **'Chat Settings'**
  String get chatSettings;

  /// No description provided for @chatName.
  ///
  /// In en, this message translates to:
  /// **'Chat Name'**
  String get chatName;

  /// No description provided for @chatDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get chatDescription;

  /// No description provided for @accessAndVisibility.
  ///
  /// In en, this message translates to:
  /// **'Access & Visibility'**
  String get accessAndVisibility;

  /// No description provided for @autoMode.
  ///
  /// In en, this message translates to:
  /// **'Auto'**
  String get autoMode;

  /// No description provided for @avgRatersPerProposition.
  ///
  /// In en, this message translates to:
  /// **'avg raters per proposition'**
  String get avgRatersPerProposition;

  /// No description provided for @consensus.
  ///
  /// In en, this message translates to:
  /// **'Convergence'**
  String get consensus;

  /// No description provided for @aiPropositions.
  ///
  /// In en, this message translates to:
  /// **'AI Propositions'**
  String get aiPropositions;

  /// No description provided for @perRound.
  ///
  /// In en, this message translates to:
  /// **'per round'**
  String get perRound;

  /// No description provided for @schedule.
  ///
  /// In en, this message translates to:
  /// **'Schedule'**
  String get schedule;

  /// No description provided for @configured.
  ///
  /// In en, this message translates to:
  /// **'configured'**
  String get configured;

  /// No description provided for @publicAccess.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get publicAccess;

  /// No description provided for @inviteCodeAccess.
  ///
  /// In en, this message translates to:
  /// **'Invite Code'**
  String get inviteCodeAccess;

  /// No description provided for @inviteOnlyAccess.
  ///
  /// In en, this message translates to:
  /// **'Invite Only'**
  String get inviteOnlyAccess;

  /// No description provided for @privacyPolicyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy Policy'**
  String get privacyPolicyTitle;

  /// No description provided for @termsOfServiceTitle.
  ///
  /// In en, this message translates to:
  /// **'Terms of Service'**
  String get termsOfServiceTitle;

  /// No description provided for @legalDocuments.
  ///
  /// In en, this message translates to:
  /// **'Legal'**
  String get legalDocuments;

  /// No description provided for @contact.
  ///
  /// In en, this message translates to:
  /// **'Contact'**
  String get contact;

  /// No description provided for @sourceCode.
  ///
  /// In en, this message translates to:
  /// **'Source Code'**
  String get sourceCode;

  /// No description provided for @byContinuingYouAgree.
  ///
  /// In en, this message translates to:
  /// **'By continuing, you agree to our'**
  String get byContinuingYouAgree;

  /// No description provided for @andText.
  ///
  /// In en, this message translates to:
  /// **'and'**
  String get andText;

  /// No description provided for @lastUpdated.
  ///
  /// In en, this message translates to:
  /// **'Last updated: {date}'**
  String lastUpdated(String date);

  /// No description provided for @shareLinkTitle.
  ///
  /// In en, this message translates to:
  /// **'Anyone with this link can join {chatName}'**
  String shareLinkTitle(String chatName);

  /// No description provided for @shareButton.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareButton;

  /// No description provided for @copyLinkButton.
  ///
  /// In en, this message translates to:
  /// **'Copy Link'**
  String get copyLinkButton;

  /// No description provided for @linkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied to clipboard'**
  String get linkCopied;

  /// No description provided for @enterCodeManually.
  ///
  /// In en, this message translates to:
  /// **'Or enter code manually:'**
  String get enterCodeManually;

  /// No description provided for @shareNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Share not available - link copied instead'**
  String get shareNotSupported;

  /// No description provided for @orScan.
  ///
  /// In en, this message translates to:
  /// **'or scan'**
  String get orScan;

  /// No description provided for @tutorialTemplateSaturday.
  ///
  /// In en, this message translates to:
  /// **'Saturday Plans'**
  String get tutorialTemplateSaturday;

  /// No description provided for @tutorialTemplateSaturdayDesc.
  ///
  /// In en, this message translates to:
  /// **'What\'s the best way to spend a free Saturday?'**
  String get tutorialTemplateSaturdayDesc;

  /// No description provided for @tutorialTemplateCustom.
  ///
  /// In en, this message translates to:
  /// **'Custom Topic'**
  String get tutorialTemplateCustom;

  /// No description provided for @tutorialTemplateCustomDesc.
  ///
  /// In en, this message translates to:
  /// **'Enter your own question'**
  String get tutorialTemplateCustomDesc;

  /// No description provided for @tutorialCustomQuestionHint.
  ///
  /// In en, this message translates to:
  /// **'Type your question...'**
  String get tutorialCustomQuestionHint;

  /// No description provided for @tutorialRound1ResultTemplate.
  ///
  /// In en, this message translates to:
  /// **'\'{winner}\' won Round 1!'**
  String tutorialRound1ResultTemplate(String winner);

  /// No description provided for @tutorialAppBarTitle.
  ///
  /// In en, this message translates to:
  /// **'OneMind Tutorial'**
  String get tutorialAppBarTitle;

  /// No description provided for @tutorialWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome to OneMind!'**
  String get tutorialWelcomeTitle;

  /// No description provided for @tutorialWelcomeDescription.
  ///
  /// In en, this message translates to:
  /// **'Anonymous groupchats where many minds think as one.'**
  String get tutorialWelcomeDescription;

  /// No description provided for @tutorialWelcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'See how it works'**
  String get tutorialWelcomeSubtitle;

  /// No description provided for @tutorialTheQuestion.
  ///
  /// In en, this message translates to:
  /// **'The question:'**
  String get tutorialTheQuestion;

  /// No description provided for @tutorialQuestion.
  ///
  /// In en, this message translates to:
  /// **'What\'s the best way to spend a free Saturday?'**
  String get tutorialQuestion;

  /// No description provided for @tutorialStartButton.
  ///
  /// In en, this message translates to:
  /// **'Start Tutorial'**
  String get tutorialStartButton;

  /// No description provided for @tutorialSkipButton.
  ///
  /// In en, this message translates to:
  /// **'Skip tutorial'**
  String get tutorialSkipButton;

  /// No description provided for @tutorialConsensusReached.
  ///
  /// In en, this message translates to:
  /// **'Convergence Reached!'**
  String get tutorialConsensusReached;

  /// No description provided for @tutorialWonTwoRounds.
  ///
  /// In en, this message translates to:
  /// **'Your idea won again, so it is added permanently to the chat.'**
  String get tutorialWonTwoRounds;

  /// No description provided for @tutorialConvergenceExplain.
  ///
  /// In en, this message translates to:
  /// **'Tap it to continue.'**
  String get tutorialConvergenceExplain;

  /// No description provided for @tutorialCycleHistoryExplainTitle.
  ///
  /// In en, this message translates to:
  /// **'Round Winners'**
  String get tutorialCycleHistoryExplainTitle;

  /// No description provided for @tutorialCycleHistoryExplainDesc.
  ///
  /// In en, this message translates to:
  /// **'See how the same idea won Round 2 and Round 3? That\'s called convergence — the group has converged on an idea.'**
  String get tutorialCycleHistoryExplainDesc;

  /// No description provided for @tutorialCycleHistoryBackDesc.
  ///
  /// In en, this message translates to:
  /// **'Press [back] to continue.'**
  String get tutorialCycleHistoryBackDesc;

  /// No description provided for @tutorialPressBackToContinue.
  ///
  /// In en, this message translates to:
  /// **'Press [back] to continue.'**
  String get tutorialPressBackToContinue;

  /// No description provided for @tutorialR1LeaderboardTapDesc.
  ///
  /// In en, this message translates to:
  /// **'Tap [leaderboard] to continue.'**
  String get tutorialR1LeaderboardTapDesc;

  /// No description provided for @tutorialR1LeaderboardUpdatedDesc.
  ///
  /// In en, this message translates to:
  /// **'The leaderboard has been updated.'**
  String get tutorialR1LeaderboardUpdatedDesc;

  /// No description provided for @tutorialR1LeaderboardDoneDesc.
  ///
  /// In en, this message translates to:
  /// **'Press the X to continue.'**
  String get tutorialR1LeaderboardDoneDesc;

  /// No description provided for @tutorialR1ResultWinnerTitle.
  ///
  /// In en, this message translates to:
  /// **'Round 1 Winner'**
  String get tutorialR1ResultWinnerTitle;

  /// No description provided for @tutorialR1ResultWinnerDesc.
  ///
  /// In en, this message translates to:
  /// **'Everyone has rated. \"Movie Night\" won! It is now the new placeholder.'**
  String get tutorialR1ResultWinnerDesc;

  /// No description provided for @tutorialR1ResultTapTitle.
  ///
  /// In en, this message translates to:
  /// **'Round Winners'**
  String get tutorialR1ResultTapTitle;

  /// No description provided for @tutorialR1ResultTapDesc.
  ///
  /// In en, this message translates to:
  /// **'Tap it to continue.'**
  String get tutorialR1ResultTapDesc;

  /// No description provided for @tutorialR1CycleExplainTitle.
  ///
  /// In en, this message translates to:
  /// **'Round Winners'**
  String get tutorialR1CycleExplainTitle;

  /// No description provided for @tutorialR1CycleExplainDesc.
  ///
  /// In en, this message translates to:
  /// **'This shows all completed round winners. Only 1 round has been completed so far.'**
  String get tutorialR1CycleExplainDesc;

  /// No description provided for @tutorialR2CycleExplainDesc.
  ///
  /// In en, this message translates to:
  /// **'Now there are 2 completed rounds.'**
  String get tutorialR2CycleExplainDesc;

  /// No description provided for @tutorialR2ResultsExplainDesc.
  ///
  /// In en, this message translates to:
  /// **'\"Movie Night\" lost this round, so it was replaced by the new winner — your idea.'**
  String get tutorialR2ResultsExplainDesc;

  /// No description provided for @tutorialR1CycleTapDesc.
  ///
  /// In en, this message translates to:
  /// **'Tap it to view the full rating results.'**
  String get tutorialR1CycleTapDesc;

  /// No description provided for @tutorialR2CycleTapDesc.
  ///
  /// In en, this message translates to:
  /// **'Tap the Round 2 winner to view the full rating results.'**
  String get tutorialR2CycleTapDesc;

  /// No description provided for @tutorialCarriedWinnerTitle.
  ///
  /// In en, this message translates to:
  /// **'Previous Winner'**
  String get tutorialCarriedWinnerTitle;

  /// No description provided for @tutorialCarriedWinnerDesc.
  ///
  /// In en, this message translates to:
  /// **'\"Movie Night\" is the previous round\'s winner. If it also wins this round, it gets placed permanently in the chat.'**
  String get tutorialCarriedWinnerDesc;

  /// No description provided for @tutorialProcessContinuesTitle.
  ///
  /// In en, this message translates to:
  /// **'The Process Continues'**
  String get tutorialProcessContinuesTitle;

  /// No description provided for @tutorialProcessContinuesDesc.
  ///
  /// In en, this message translates to:
  /// **'Now the group works toward its next convergence.'**
  String get tutorialProcessContinuesDesc;

  /// No description provided for @tutorialAddedToChat.
  ///
  /// In en, this message translates to:
  /// **'You\'ve also been automatically added to the Official OneMind chat, where everyone discusses topics together.'**
  String get tutorialAddedToChat;

  /// No description provided for @tutorialFinishButton.
  ///
  /// In en, this message translates to:
  /// **'Finish Tutorial'**
  String get tutorialFinishButton;

  /// No description provided for @tutorialRound1Result.
  ///
  /// In en, this message translates to:
  /// **'\'Movie Night\' won Round 1!'**
  String get tutorialRound1Result;

  /// No description provided for @tutorialProposingHint.
  ///
  /// In en, this message translates to:
  /// **'Submit your idea — it\'ll compete against everyone else\'s.'**
  String get tutorialProposingHint;

  /// No description provided for @tutorialTimeRemaining.
  ///
  /// In en, this message translates to:
  /// **'You have {time} left.'**
  String tutorialTimeRemaining(String time);

  /// No description provided for @tutorialProposingHintWithWinner.
  ///
  /// In en, this message translates to:
  /// **'Submit a new idea to compete against last round\'s winner.'**
  String get tutorialProposingHintWithWinner;

  /// No description provided for @tutorialRatingHint.
  ///
  /// In en, this message translates to:
  /// **'Now rate everyone\'s responses. The highest-rated response wins the round.'**
  String get tutorialRatingHint;

  /// No description provided for @tutorialRatingPhaseExplanation.
  ///
  /// In en, this message translates to:
  /// **'Everyone has submitted. Now rate their responses to pick a winner before the timer runs out!'**
  String get tutorialRatingPhaseExplanation;

  /// No description provided for @tutorialRatingPhaseTitle.
  ///
  /// In en, this message translates to:
  /// **'Rating Phase'**
  String get tutorialRatingPhaseTitle;

  /// No description provided for @tutorialRatingPhaseHint.
  ///
  /// In en, this message translates to:
  /// **'Now that everyone has submitted their ideas, the rating phase begins.'**
  String get tutorialRatingPhaseHint;

  /// No description provided for @tutorialRatingButtonHint.
  ///
  /// In en, this message translates to:
  /// **'Click Start Rating below to start rating everyone\'s ideas.'**
  String get tutorialRatingButtonHint;

  /// No description provided for @tutorialRatingButtonHintRich.
  ///
  /// In en, this message translates to:
  /// **'Click [startRating] below to start rating everyone\'s ideas.'**
  String get tutorialRatingButtonHintRich;

  /// No description provided for @tutorialRatingIntroHint.
  ///
  /// In en, this message translates to:
  /// **'This is the rating screen. You won\'t rate your own idea — only other people\'s.'**
  String get tutorialRatingIntroHint;

  /// No description provided for @tutorialRatingRankHint.
  ///
  /// In en, this message translates to:
  /// **'The closer your ratings match the group\'s, the higher you rank.'**
  String get tutorialRatingRankHint;

  /// No description provided for @tutorialRatingTimeRemaining.
  ///
  /// In en, this message translates to:
  /// **'You have {time} left to rate.'**
  String tutorialRatingTimeRemaining(String time);

  /// No description provided for @tutorialRatingBinaryHint.
  ///
  /// In en, this message translates to:
  /// **'The top idea scores higher. Tap [swap] to put your preferred idea on top, then tap [check] to lock it in.'**
  String get tutorialRatingBinaryHint;

  /// No description provided for @tutorialRatingPositioningHint.
  ///
  /// In en, this message translates to:
  /// **'Place each idea on the scale. Use [up] [down] to move, then tap [check] to lock it in. Press [undo] to redo your previous placement.'**
  String get tutorialRatingPositioningHint;

  /// No description provided for @tutorialRound2Result.
  ///
  /// In en, this message translates to:
  /// **'Your idea \"{proposition}\" won! It replaces \"{previousWinner}\" as the one to beat. Win next round and it\'s decided!'**
  String tutorialRound2Result(String proposition, String previousWinner);

  /// No description provided for @tutorialRatingCarryForwardHint.
  ///
  /// In en, this message translates to:
  /// **'Last round\'s winner carries forward to compete again.'**
  String get tutorialRatingCarryForwardHint;

  /// No description provided for @tutorialTapTabHint.
  ///
  /// In en, this message translates to:
  /// **'Tap \"{tabName}\" above to continue.'**
  String tutorialTapTabHint(String tabName);

  /// No description provided for @tutorialResultTapTabHint.
  ///
  /// In en, this message translates to:
  /// **'Think you can do better? Tap \"{tabName}\" to submit your next idea.'**
  String tutorialResultTapTabHint(String tabName);

  /// No description provided for @tutorialRound2PromptSimplified.
  ///
  /// In en, this message translates to:
  /// **'The winner competes again this round. If it wins again, that\'s convergence — the group\'s answer. Can you beat it?'**
  String get tutorialRound2PromptSimplified;

  /// No description provided for @tutorialRound2PromptSimplifiedTemplate.
  ///
  /// In en, this message translates to:
  /// **'\'{winner}\' competes again this round. If it wins again, that\'s convergence — the group\'s answer. Can you beat it?'**
  String tutorialRound2PromptSimplifiedTemplate(String winner);

  /// No description provided for @tutorialRound3Prompt.
  ///
  /// In en, this message translates to:
  /// **'Your idea replaced the last winner. One more win means convergence!'**
  String get tutorialRound3Prompt;

  /// No description provided for @tutorialRound3PromptTemplate.
  ///
  /// In en, this message translates to:
  /// **'\'{winner}\' replaced \'{previousWinner}\'. If it wins again next round, the group places it permanently in the chat.'**
  String tutorialRound3PromptTemplate(String winner, String previousWinner);

  /// No description provided for @tutorialR2ResultsHint.
  ///
  /// In en, this message translates to:
  /// **'Your idea won! It is now the new placeholder.'**
  String get tutorialR2ResultsHint;

  /// No description provided for @tutorialRound3ConvergenceHint.
  ///
  /// In en, this message translates to:
  /// **'If it wins again, no one could beat it — that\'s convergence.'**
  String get tutorialRound3ConvergenceHint;

  /// No description provided for @tutorialHintSubmitIdea.
  ///
  /// In en, this message translates to:
  /// **'Submit Your Idea'**
  String get tutorialHintSubmitIdea;

  /// No description provided for @tutorialHintRateIdeas.
  ///
  /// In en, this message translates to:
  /// **'Rate Ideas'**
  String get tutorialHintRateIdeas;

  /// No description provided for @tutorialHintRoundResults.
  ///
  /// In en, this message translates to:
  /// **'Rating Results'**
  String get tutorialHintRoundResults;

  /// No description provided for @tutorialHintR1Winner.
  ///
  /// In en, this message translates to:
  /// **'New Placeholder'**
  String get tutorialHintR1Winner;

  /// No description provided for @tutorialHintR1WinnerDesc.
  ///
  /// In en, this message translates to:
  /// **'\"{winner}\" won Round 1, so it replaced the previous placeholder. Now it is the new placeholder.'**
  String tutorialHintR1WinnerDesc(String winner);

  /// No description provided for @tutorialHintConvergenceExplain.
  ///
  /// In en, this message translates to:
  /// **'Convergence'**
  String get tutorialHintConvergenceExplain;

  /// No description provided for @tutorialHintConvergenceExplainDesc.
  ///
  /// In en, this message translates to:
  /// **'If the placeholder wins 2 rounds in a row, it becomes a permanent part of the chat. This is called convergence.'**
  String get tutorialHintConvergenceExplainDesc;

  /// No description provided for @tutorialHintNewRound.
  ///
  /// In en, this message translates to:
  /// **'New Round'**
  String get tutorialHintNewRound;

  /// No description provided for @tutorialHintNewRoundDesc.
  ///
  /// In en, this message translates to:
  /// **'Round 2 begins now.'**
  String get tutorialHintNewRoundDesc;

  /// No description provided for @tutorialHintRound2.
  ///
  /// In en, this message translates to:
  /// **'Round 2'**
  String get tutorialHintRound2;

  /// No description provided for @tutorialHintReplaceWinner.
  ///
  /// In en, this message translates to:
  /// **'Can You Beat It?'**
  String get tutorialHintReplaceWinner;

  /// No description provided for @tutorialHintReplaceWinnerDesc.
  ///
  /// In en, this message translates to:
  /// **'Try to replace \"Movie Night\". Send your best idea!'**
  String get tutorialHintReplaceWinnerDesc;

  /// No description provided for @tutorialHintNewRound3.
  ///
  /// In en, this message translates to:
  /// **'New Round'**
  String get tutorialHintNewRound3;

  /// No description provided for @tutorialHintNewRound3Desc.
  ///
  /// In en, this message translates to:
  /// **'Now time for Round 3.'**
  String get tutorialHintNewRound3Desc;

  /// No description provided for @tutorialHintR3Replace.
  ///
  /// In en, this message translates to:
  /// **'Last Chance!'**
  String get tutorialHintR3Replace;

  /// No description provided for @tutorialHintR3ReplaceDesc.
  ///
  /// In en, this message translates to:
  /// **'Can you think of something better? Type your best idea and submit it! If you can\'t think of anything, tap [skip] to skip.'**
  String get tutorialHintR3ReplaceDesc;

  /// No description provided for @tutorialHintYouWon.
  ///
  /// In en, this message translates to:
  /// **'You Won!'**
  String get tutorialHintYouWon;

  /// No description provided for @tutorialHintCompare.
  ///
  /// In en, this message translates to:
  /// **'Compare Ideas'**
  String get tutorialHintCompare;

  /// No description provided for @tutorialHintPosition.
  ///
  /// In en, this message translates to:
  /// **'Position Ideas'**
  String get tutorialHintPosition;

  /// No description provided for @tutorialHintCarryForward.
  ///
  /// In en, this message translates to:
  /// **'Carry Forward'**
  String get tutorialHintCarryForward;

  /// No description provided for @tutorialPropMovieNight.
  ///
  /// In en, this message translates to:
  /// **'Movie Night'**
  String get tutorialPropMovieNight;

  /// No description provided for @tutorialPropCookOff.
  ///
  /// In en, this message translates to:
  /// **'Cook-off'**
  String get tutorialPropCookOff;

  /// No description provided for @tutorialPropBoardGames.
  ///
  /// In en, this message translates to:
  /// **'Board Games'**
  String get tutorialPropBoardGames;

  /// No description provided for @tutorialPropKaraoke.
  ///
  /// In en, this message translates to:
  /// **'Karaoke'**
  String get tutorialPropKaraoke;

  /// No description provided for @tutorialPropPotluckDinner.
  ///
  /// In en, this message translates to:
  /// **'Potluck Dinner'**
  String get tutorialPropPotluckDinner;

  /// No description provided for @tutorialPropDiyCraftNight.
  ///
  /// In en, this message translates to:
  /// **'DIY Craft Night'**
  String get tutorialPropDiyCraftNight;

  /// No description provided for @tutorialPropTriviaNight.
  ///
  /// In en, this message translates to:
  /// **'Trivia Night'**
  String get tutorialPropTriviaNight;

  /// No description provided for @tutorialPropVideoGameTournament.
  ///
  /// In en, this message translates to:
  /// **'Video Game Tournament'**
  String get tutorialPropVideoGameTournament;

  /// No description provided for @tutorialPropSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get tutorialPropSuccess;

  /// No description provided for @tutorialPropAdventure.
  ///
  /// In en, this message translates to:
  /// **'Adventure'**
  String get tutorialPropAdventure;

  /// No description provided for @tutorialPropGrowth.
  ///
  /// In en, this message translates to:
  /// **'Growth'**
  String get tutorialPropGrowth;

  /// No description provided for @tutorialPropHarmony.
  ///
  /// In en, this message translates to:
  /// **'Harmony'**
  String get tutorialPropHarmony;

  /// No description provided for @tutorialPropInnovation.
  ///
  /// In en, this message translates to:
  /// **'Innovation'**
  String get tutorialPropInnovation;

  /// No description provided for @tutorialPropFreedom.
  ///
  /// In en, this message translates to:
  /// **'Freedom'**
  String get tutorialPropFreedom;

  /// No description provided for @tutorialPropSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get tutorialPropSecurity;

  /// No description provided for @tutorialPropStability.
  ///
  /// In en, this message translates to:
  /// **'Stability'**
  String get tutorialPropStability;

  /// No description provided for @tutorialDuplicateProposition.
  ///
  /// In en, this message translates to:
  /// **'This idea already exists in this round. Try something different!'**
  String get tutorialDuplicateProposition;

  /// No description provided for @tutorialShareTitle.
  ///
  /// In en, this message translates to:
  /// **'Share Your Chat'**
  String get tutorialShareTitle;

  /// No description provided for @tutorialShareExplanation.
  ///
  /// In en, this message translates to:
  /// **'Share this link, QR code, or invite code for others to join your chat.'**
  String get tutorialShareExplanation;

  /// No description provided for @tutorialShareTapDesc.
  ///
  /// In en, this message translates to:
  /// **'Tap the share button to continue.'**
  String get tutorialShareTapDesc;

  /// No description provided for @tutorialShareCloseDesc.
  ///
  /// In en, this message translates to:
  /// **'Press the X to continue.'**
  String get tutorialShareCloseDesc;

  /// No description provided for @tutorialShareTryIt.
  ///
  /// In en, this message translates to:
  /// **'Try it now!'**
  String get tutorialShareTryIt;

  /// No description provided for @tutorialShareButtonHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the share button in the top right ↗'**
  String get tutorialShareButtonHint;

  /// No description provided for @tutorialSkipMenuItem.
  ///
  /// In en, this message translates to:
  /// **'Skip Tutorial'**
  String get tutorialSkipMenuItem;

  /// No description provided for @tutorialSkipConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Skip Tutorial?'**
  String get tutorialSkipConfirmTitle;

  /// No description provided for @tutorialSkipConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'You can always access the tutorial later from the home screen.'**
  String get tutorialSkipConfirmMessage;

  /// No description provided for @tutorialSkipConfirmYes.
  ///
  /// In en, this message translates to:
  /// **'Yes, Skip'**
  String get tutorialSkipConfirmYes;

  /// No description provided for @tutorialSkipConfirmNo.
  ///
  /// In en, this message translates to:
  /// **'Continue Tutorial'**
  String get tutorialSkipConfirmNo;

  /// No description provided for @tutorialShareTooltip.
  ///
  /// In en, this message translates to:
  /// **'Share Chat'**
  String get tutorialShareTooltip;

  /// No description provided for @tutorialYourIdea.
  ///
  /// In en, this message translates to:
  /// **'Your idea'**
  String get tutorialYourIdea;

  /// No description provided for @tutorialTransitionTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat tutorial complete!'**
  String get tutorialTransitionTitle;

  /// No description provided for @tutorialTransitionDesc.
  ///
  /// In en, this message translates to:
  /// **'Now for a quick look at the home screen, where all your chats live.'**
  String get tutorialTransitionDesc;

  /// No description provided for @tutorialRateIdeas.
  ///
  /// In en, this message translates to:
  /// **'Rate Ideas'**
  String get tutorialRateIdeas;

  /// No description provided for @tutorialResultsTitle.
  ///
  /// In en, this message translates to:
  /// **'Rating Results'**
  String get tutorialResultsTitle;

  /// No description provided for @tutorialResultsWinnerHint.
  ///
  /// In en, this message translates to:
  /// **'These are the group\'s combined rating results.'**
  String get tutorialResultsWinnerHint;

  /// No description provided for @tutorialResultsBackHint.
  ///
  /// In en, this message translates to:
  /// **'When done viewing the results, press [back] to continue.'**
  String get tutorialResultsBackHint;

  /// No description provided for @deleteConsensusTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Convergence #{number}?'**
  String deleteConsensusTitle(int number);

  /// No description provided for @deleteConsensusMessage.
  ///
  /// In en, this message translates to:
  /// **'This will restart the current cycle with a fresh round.'**
  String get deleteConsensusMessage;

  /// No description provided for @deleteInitialMessageTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Initial Message?'**
  String get deleteInitialMessageTitle;

  /// No description provided for @deleteInitialMessageMessage.
  ///
  /// In en, this message translates to:
  /// **'This will restart the current cycle with a fresh round.'**
  String get deleteInitialMessageMessage;

  /// No description provided for @editInitialMessage.
  ///
  /// In en, this message translates to:
  /// **'Edit Initial Message'**
  String get editInitialMessage;

  /// No description provided for @consensusDeleted.
  ///
  /// In en, this message translates to:
  /// **'Convergence deleted'**
  String get consensusDeleted;

  /// No description provided for @initialMessageUpdated.
  ///
  /// In en, this message translates to:
  /// **'Initial message updated'**
  String get initialMessageUpdated;

  /// No description provided for @initialMessageDeleted.
  ///
  /// In en, this message translates to:
  /// **'Initial message deleted'**
  String get initialMessageDeleted;

  /// No description provided for @failedToDeleteConsensus.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete convergence: {error}'**
  String failedToDeleteConsensus(String error);

  /// No description provided for @failedToUpdateInitialMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to update initial message: {error}'**
  String failedToUpdateInitialMessage(String error);

  /// No description provided for @failedToDeleteInitialMessage.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete initial message: {error}'**
  String failedToDeleteInitialMessage(String error);

  /// No description provided for @deleteTaskResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Research Results?'**
  String get deleteTaskResultTitle;

  /// No description provided for @deleteTaskResultMessage.
  ///
  /// In en, this message translates to:
  /// **'The agent will re-research on the next heartbeat.'**
  String get deleteTaskResultMessage;

  /// No description provided for @taskResultDeleted.
  ///
  /// In en, this message translates to:
  /// **'Research results deleted'**
  String get taskResultDeleted;

  /// No description provided for @failedToDeleteTaskResult.
  ///
  /// In en, this message translates to:
  /// **'Failed to delete research results: {error}'**
  String failedToDeleteTaskResult(String error);

  /// No description provided for @wizardStep1Title.
  ///
  /// In en, this message translates to:
  /// **'What do you want to talk about?'**
  String get wizardStep1Title;

  /// No description provided for @wizardStep1Subtitle.
  ///
  /// In en, this message translates to:
  /// **'Give your chat a name'**
  String get wizardStep1Subtitle;

  /// No description provided for @wizardStep2Title.
  ///
  /// In en, this message translates to:
  /// **'How fast?'**
  String get wizardStep2Title;

  /// No description provided for @wizardStep2Subtitle.
  ///
  /// In en, this message translates to:
  /// **'How long for each phase?'**
  String get wizardStep2Subtitle;

  /// No description provided for @wizardOneLastThing.
  ///
  /// In en, this message translates to:
  /// **'One last thing...'**
  String get wizardOneLastThing;

  /// No description provided for @wizardProposingLabel.
  ///
  /// In en, this message translates to:
  /// **'Proposing (submit ideas)'**
  String get wizardProposingLabel;

  /// No description provided for @wizardRatingLabel.
  ///
  /// In en, this message translates to:
  /// **'Rating (rank ideas)'**
  String get wizardRatingLabel;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @spectatingInsufficientCredits.
  ///
  /// In en, this message translates to:
  /// **'Spectating — insufficient credits'**
  String get spectatingInsufficientCredits;

  /// No description provided for @creditPausedTitle.
  ///
  /// In en, this message translates to:
  /// **'Paused — Insufficient Credits'**
  String get creditPausedTitle;

  /// No description provided for @creditBalance.
  ///
  /// In en, this message translates to:
  /// **'Balance: {balance} credits'**
  String creditBalance(int balance);

  /// No description provided for @creditsNeeded.
  ///
  /// In en, this message translates to:
  /// **'Need {count} credits to start round'**
  String creditsNeeded(int count);

  /// No description provided for @waitingForHostCredits.
  ///
  /// In en, this message translates to:
  /// **'Waiting for host to add credits'**
  String get waitingForHostCredits;

  /// No description provided for @buyMoreCredits.
  ///
  /// In en, this message translates to:
  /// **'Buy Credits'**
  String get buyMoreCredits;

  /// No description provided for @forceAsConsensus.
  ///
  /// In en, this message translates to:
  /// **'Force as Convergence'**
  String get forceAsConsensus;

  /// No description provided for @forceAsConsensusDescription.
  ///
  /// In en, this message translates to:
  /// **'Submit directly as convergence, skipping voting'**
  String get forceAsConsensusDescription;

  /// No description provided for @forceConsensus.
  ///
  /// In en, this message translates to:
  /// **'Force Convergence'**
  String get forceConsensus;

  /// No description provided for @forceConsensusTitle.
  ///
  /// In en, this message translates to:
  /// **'Force Convergence?'**
  String get forceConsensusTitle;

  /// No description provided for @forceConsensusMessage.
  ///
  /// In en, this message translates to:
  /// **'This will immediately set your proposition as the convergence and start a new cycle. All current round progress will be lost.'**
  String get forceConsensusMessage;

  /// No description provided for @forceConsensusSuccess.
  ///
  /// In en, this message translates to:
  /// **'Convergence forced successfully'**
  String get forceConsensusSuccess;

  /// No description provided for @failedToForceConsensus.
  ///
  /// In en, this message translates to:
  /// **'Failed to force convergence: {error}'**
  String failedToForceConsensus(String error);

  /// No description provided for @glossaryUserRoundTitle.
  ///
  /// In en, this message translates to:
  /// **'user-round'**
  String get glossaryUserRoundTitle;

  /// No description provided for @glossaryUserRoundDef.
  ///
  /// In en, this message translates to:
  /// **'One participant completing one round of rating. Each user-round costs 1 credit (\$0.01).'**
  String get glossaryUserRoundDef;

  /// No description provided for @glossaryConsensusTitle.
  ///
  /// In en, this message translates to:
  /// **'convergence'**
  String get glossaryConsensusTitle;

  /// No description provided for @glossaryConsensusDef.
  ///
  /// In en, this message translates to:
  /// **'When no one can beat the same proposition across multiple rounds, convergence is reached.'**
  String get glossaryConsensusDef;

  /// No description provided for @glossaryProposingTitle.
  ///
  /// In en, this message translates to:
  /// **'proposing'**
  String get glossaryProposingTitle;

  /// No description provided for @glossaryProposingDef.
  ///
  /// In en, this message translates to:
  /// **'The phase where participants submit their ideas anonymously for the group to consider.'**
  String get glossaryProposingDef;

  /// No description provided for @glossaryRatingTitle.
  ///
  /// In en, this message translates to:
  /// **'rating'**
  String get glossaryRatingTitle;

  /// No description provided for @glossaryRatingDef.
  ///
  /// In en, this message translates to:
  /// **'The phase where participants rank all propositions on a 0–100 grid to determine the winner.'**
  String get glossaryRatingDef;

  /// No description provided for @glossaryCycleTitle.
  ///
  /// In en, this message translates to:
  /// **'cycle'**
  String get glossaryCycleTitle;

  /// No description provided for @glossaryCycleDef.
  ///
  /// In en, this message translates to:
  /// **'A sequence of rounds working toward convergence. A new cycle starts after convergence is reached.'**
  String get glossaryCycleDef;

  /// No description provided for @glossaryCreditBalanceTitle.
  ///
  /// In en, this message translates to:
  /// **'credit balance'**
  String get glossaryCreditBalanceTitle;

  /// No description provided for @glossaryCreditBalanceDef.
  ///
  /// In en, this message translates to:
  /// **'Credits fund rounds. 1 credit = 1 user-round = \$0.01. Free credits reset monthly.'**
  String get glossaryCreditBalanceDef;

  /// No description provided for @enterTaskResult.
  ///
  /// In en, this message translates to:
  /// **'Enter task result...'**
  String get enterTaskResult;

  /// No description provided for @submitResult.
  ///
  /// In en, this message translates to:
  /// **'Submit Result'**
  String get submitResult;

  /// No description provided for @taskResultSubmitted.
  ///
  /// In en, this message translates to:
  /// **'Task result submitted'**
  String get taskResultSubmitted;

  /// No description provided for @homeTourPendingRequestTitle.
  ///
  /// In en, this message translates to:
  /// **'Pending Requests'**
  String get homeTourPendingRequestTitle;

  /// No description provided for @homeTourPendingRequestDesc.
  ///
  /// In en, this message translates to:
  /// **'These are chats you\'re waiting to be accepted into.'**
  String get homeTourPendingRequestDesc;

  /// No description provided for @homeTourYourChatsTitle.
  ///
  /// In en, this message translates to:
  /// **'Your Chats'**
  String get homeTourYourChatsTitle;

  /// No description provided for @homeTourYourChatsDesc.
  ///
  /// In en, this message translates to:
  /// **'These are the chats that you are in.'**
  String get homeTourYourChatsDesc;

  /// No description provided for @homeTourCreateFabTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get homeTourCreateFabTitle;

  /// No description provided for @homeTourCreateFabDesc.
  ///
  /// In en, this message translates to:
  /// **'Tap to create a chat, join an existing one, or discover public chats.'**
  String get homeTourCreateFabDesc;

  /// No description provided for @homeTourDemoTitle.
  ///
  /// In en, this message translates to:
  /// **'Try the Demo'**
  String get homeTourDemoTitle;

  /// No description provided for @homeTourDemoDesc.
  ///
  /// In en, this message translates to:
  /// **'Want to see how voting works? Tap here to try a quick interactive demo.'**
  String get homeTourDemoDesc;

  /// No description provided for @homeTourHowItWorksTitle.
  ///
  /// In en, this message translates to:
  /// **'How It Works'**
  String get homeTourHowItWorksTitle;

  /// No description provided for @homeTourHowItWorksDesc.
  ///
  /// In en, this message translates to:
  /// **'Need a refresher? Tap here to replay the tutorial anytime.'**
  String get homeTourHowItWorksDesc;

  /// No description provided for @homeTourLegalDocsTitle.
  ///
  /// In en, this message translates to:
  /// **'Legal Documents'**
  String get homeTourLegalDocsTitle;

  /// No description provided for @homeTourLegalDocsDesc.
  ///
  /// In en, this message translates to:
  /// **'View the Privacy Policy and Terms of Service here.'**
  String get homeTourLegalDocsDesc;

  /// No description provided for @homeTourTutorialButtonTitle.
  ///
  /// In en, this message translates to:
  /// **'How It Works'**
  String get homeTourTutorialButtonTitle;

  /// No description provided for @homeTourTutorialButtonDesc.
  ///
  /// In en, this message translates to:
  /// **'Replay the tutorial to learn how OneMind works.'**
  String get homeTourTutorialButtonDesc;

  /// No description provided for @homeTourMenuTitle.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get homeTourMenuTitle;

  /// No description provided for @homeTourMenuDesc.
  ///
  /// In en, this message translates to:
  /// **'Contact us, view the source code, or read the legal documents.'**
  String get homeTourMenuDesc;

  /// No description provided for @searchOrJoinWithCode.
  ///
  /// In en, this message translates to:
  /// **'Search chats or enter invite code...'**
  String get searchOrJoinWithCode;

  /// No description provided for @searchYourChatsOrJoinWithCode.
  ///
  /// In en, this message translates to:
  /// **'Search your chats...'**
  String get searchYourChatsOrJoinWithCode;

  /// No description provided for @noMatchingChats.
  ///
  /// In en, this message translates to:
  /// **'No matching chats'**
  String get noMatchingChats;

  /// No description provided for @inviteCodeDetected.
  ///
  /// In en, this message translates to:
  /// **'Join with invite code: {code}'**
  String inviteCodeDetected(String code);

  /// No description provided for @wizardVisibilityTitle.
  ///
  /// In en, this message translates to:
  /// **'Who can join?'**
  String get wizardVisibilityTitle;

  /// No description provided for @wizardVisibilitySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose who can find and join your chat'**
  String get wizardVisibilitySubtitle;

  /// No description provided for @wizardVisibilityPublicTitle.
  ///
  /// In en, this message translates to:
  /// **'Public'**
  String get wizardVisibilityPublicTitle;

  /// No description provided for @wizardVisibilityPublicDesc.
  ///
  /// In en, this message translates to:
  /// **'Anyone can discover and join this chat'**
  String get wizardVisibilityPublicDesc;

  /// No description provided for @wizardVisibilityPrivateTitle.
  ///
  /// In en, this message translates to:
  /// **'Private'**
  String get wizardVisibilityPrivateTitle;

  /// No description provided for @wizardVisibilityPrivateDesc.
  ///
  /// In en, this message translates to:
  /// **'Only people with the invite code can join'**
  String get wizardVisibilityPrivateDesc;

  /// No description provided for @wizardVisibilityPersonalCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Personal Codes'**
  String get wizardVisibilityPersonalCodeTitle;

  /// No description provided for @wizardVisibilityPersonalCodeDesc.
  ///
  /// In en, this message translates to:
  /// **'Generate unique codes for each person. Each code works once.'**
  String get wizardVisibilityPersonalCodeDesc;

  /// No description provided for @personalCodes.
  ///
  /// In en, this message translates to:
  /// **'Personal Codes'**
  String get personalCodes;

  /// No description provided for @generateNewCode.
  ///
  /// In en, this message translates to:
  /// **'Generate New Code'**
  String get generateNewCode;

  /// No description provided for @codeStatusActive.
  ///
  /// In en, this message translates to:
  /// **'Active'**
  String get codeStatusActive;

  /// No description provided for @codeStatusReserved.
  ///
  /// In en, this message translates to:
  /// **'Reserved'**
  String get codeStatusReserved;

  /// No description provided for @codeStatusUsed.
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get codeStatusUsed;

  /// No description provided for @codeStatusRevoked.
  ///
  /// In en, this message translates to:
  /// **'Revoked'**
  String get codeStatusRevoked;

  /// No description provided for @revokeCode.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get revokeCode;

  /// No description provided for @revokeCodeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Revoke this code? It can no longer be used to join.'**
  String get revokeCodeConfirm;

  /// No description provided for @codeAlreadyUsed.
  ///
  /// In en, this message translates to:
  /// **'This code has already been used.'**
  String get codeAlreadyUsed;

  /// No description provided for @noCodesYet.
  ///
  /// In en, this message translates to:
  /// **'No codes yet. Generate one to invite someone.'**
  String get noCodesYet;

  /// No description provided for @codeGenerated.
  ///
  /// In en, this message translates to:
  /// **'Code generated!'**
  String get codeGenerated;

  /// No description provided for @codeRevoked.
  ///
  /// In en, this message translates to:
  /// **'Code revoked'**
  String get codeRevoked;

  /// No description provided for @homeTourSearchBarTitle.
  ///
  /// In en, this message translates to:
  /// **'Search Your Chats'**
  String get homeTourSearchBarTitle;

  /// No description provided for @homeTourSearchBarDesc.
  ///
  /// In en, this message translates to:
  /// **'Filter your chats by name.'**
  String get homeTourSearchBarDesc;

  /// No description provided for @homeTourExploreButtonTitle.
  ///
  /// In en, this message translates to:
  /// **'Explore Public Chats'**
  String get homeTourExploreButtonTitle;

  /// No description provided for @homeTourExploreButtonDesc.
  ///
  /// In en, this message translates to:
  /// **'Tap here to discover and join public chats created by other users.'**
  String get homeTourExploreButtonDesc;

  /// No description provided for @homeTourLanguageSelectorTitle.
  ///
  /// In en, this message translates to:
  /// **'Change Language'**
  String get homeTourLanguageSelectorTitle;

  /// No description provided for @homeTourLanguageSelectorDesc.
  ///
  /// In en, this message translates to:
  /// **'Tap here to switch the app language.'**
  String get homeTourLanguageSelectorDesc;

  /// No description provided for @homeTourSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip tour'**
  String get homeTourSkip;

  /// No description provided for @homeTourNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get homeTourNext;

  /// No description provided for @homeTourFinish.
  ///
  /// In en, this message translates to:
  /// **'Got it!'**
  String get homeTourFinish;

  /// No description provided for @homeTourStepOf.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}'**
  String homeTourStepOf(int current, int total);

  /// No description provided for @wizardTranslationsTitle.
  ///
  /// In en, this message translates to:
  /// **'What languages?'**
  String get wizardTranslationsTitle;

  /// No description provided for @wizardTranslationsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose what languages this chat supports'**
  String get wizardTranslationsSubtitle;

  /// No description provided for @singleLanguageToggle.
  ///
  /// In en, this message translates to:
  /// **'Single language'**
  String get singleLanguageToggle;

  /// No description provided for @singleLanguageDesc.
  ///
  /// In en, this message translates to:
  /// **'Everyone participates in one language'**
  String get singleLanguageDesc;

  /// No description provided for @multiLanguageDesc.
  ///
  /// In en, this message translates to:
  /// **'Propositions are automatically translated between languages'**
  String get multiLanguageDesc;

  /// No description provided for @chatLanguageLabel.
  ///
  /// In en, this message translates to:
  /// **'Chat language'**
  String get chatLanguageLabel;

  /// No description provided for @selectLanguages.
  ///
  /// In en, this message translates to:
  /// **'Supported languages:'**
  String get selectLanguages;

  /// No description provided for @autoTranslateHint.
  ///
  /// In en, this message translates to:
  /// **'Propositions will be automatically translated between all selected languages'**
  String get autoTranslateHint;

  /// No description provided for @translationsSection.
  ///
  /// In en, this message translates to:
  /// **'Languages'**
  String get translationsSection;

  /// No description provided for @translationLanguagesLabel.
  ///
  /// In en, this message translates to:
  /// **'Languages'**
  String get translationLanguagesLabel;

  /// No description provided for @autoTranslateLabel.
  ///
  /// In en, this message translates to:
  /// **'Auto-translate'**
  String get autoTranslateLabel;

  /// No description provided for @chatAutoTranslated.
  ///
  /// In en, this message translates to:
  /// **'Auto-translated'**
  String get chatAutoTranslated;

  /// No description provided for @scanQrCode.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get scanQrCode;

  /// No description provided for @pointCameraAtQrCode.
  ///
  /// In en, this message translates to:
  /// **'Point your camera at an invite QR code'**
  String get pointCameraAtQrCode;

  /// No description provided for @invalidQrCode.
  ///
  /// In en, this message translates to:
  /// **'This QR code doesn\'t contain a valid invite link'**
  String get invalidQrCode;

  /// No description provided for @cameraPermissionDenied.
  ///
  /// In en, this message translates to:
  /// **'Camera permission is required to scan QR codes'**
  String get cameraPermissionDenied;

  /// No description provided for @actionPickerTitle.
  ///
  /// In en, this message translates to:
  /// **'What would you like to do?'**
  String get actionPickerTitle;

  /// No description provided for @actionPickerCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Create a Chat'**
  String get actionPickerCreateTitle;

  /// No description provided for @actionPickerCreateDesc.
  ///
  /// In en, this message translates to:
  /// **'Start a new conversation on any topic'**
  String get actionPickerCreateDesc;

  /// No description provided for @actionPickerJoinTitle.
  ///
  /// In en, this message translates to:
  /// **'Join a Chat'**
  String get actionPickerJoinTitle;

  /// No description provided for @actionPickerJoinDesc.
  ///
  /// In en, this message translates to:
  /// **'Enter an invite code or scan a QR code'**
  String get actionPickerJoinDesc;

  /// No description provided for @actionPickerDiscoverTitle.
  ///
  /// In en, this message translates to:
  /// **'Discover Chats'**
  String get actionPickerDiscoverTitle;

  /// No description provided for @actionPickerDiscoverDesc.
  ///
  /// In en, this message translates to:
  /// **'Browse public chats and join the conversation'**
  String get actionPickerDiscoverDesc;

  /// No description provided for @joinMethodTitle.
  ///
  /// In en, this message translates to:
  /// **'How would you like to join?'**
  String get joinMethodTitle;

  /// No description provided for @joinMethodCodeTitle.
  ///
  /// In en, this message translates to:
  /// **'Enter Code'**
  String get joinMethodCodeTitle;

  /// No description provided for @joinMethodCodeDesc.
  ///
  /// In en, this message translates to:
  /// **'Type a 6-character invite code'**
  String get joinMethodCodeDesc;

  /// No description provided for @joinMethodScanTitle.
  ///
  /// In en, this message translates to:
  /// **'Scan QR Code'**
  String get joinMethodScanTitle;

  /// No description provided for @joinMethodScanDesc.
  ///
  /// In en, this message translates to:
  /// **'Use your camera to scan an invite QR code'**
  String get joinMethodScanDesc;

  /// No description provided for @wizardScheduleTitle.
  ///
  /// In en, this message translates to:
  /// **'Set a schedule?'**
  String get wizardScheduleTitle;

  /// No description provided for @wizardScheduleAlwaysTitle.
  ///
  /// In en, this message translates to:
  /// **'Always Active'**
  String get wizardScheduleAlwaysTitle;

  /// No description provided for @wizardScheduleAlwaysDesc.
  ///
  /// In en, this message translates to:
  /// **'Chat runs 24/7, no time restrictions'**
  String get wizardScheduleAlwaysDesc;

  /// No description provided for @wizardScheduleOnceTitle.
  ///
  /// In en, this message translates to:
  /// **'Starts at a specific time'**
  String get wizardScheduleOnceTitle;

  /// No description provided for @wizardScheduleOnceDesc.
  ///
  /// In en, this message translates to:
  /// **'Chat begins at a date and time you choose'**
  String get wizardScheduleOnceDesc;

  /// No description provided for @wizardScheduleRecurringTitle.
  ///
  /// In en, this message translates to:
  /// **'Weekly schedule'**
  String get wizardScheduleRecurringTitle;

  /// No description provided for @wizardScheduleRecurringDesc.
  ///
  /// In en, this message translates to:
  /// **'Chat is active during set time windows each week'**
  String get wizardScheduleRecurringDesc;

  /// No description provided for @scheduleEndTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'End Date & Time (optional)'**
  String get scheduleEndTimeLabel;

  /// No description provided for @scheduleEndTimeHint.
  ///
  /// In en, this message translates to:
  /// **'Leave empty to keep the chat active indefinitely after start'**
  String get scheduleEndTimeHint;

  /// No description provided for @scheduleSetEndTime.
  ///
  /// In en, this message translates to:
  /// **'Set an end time'**
  String get scheduleSetEndTime;

  /// No description provided for @scheduleClearEndTime.
  ///
  /// In en, this message translates to:
  /// **'Remove end time'**
  String get scheduleClearEndTime;

  /// No description provided for @welcomeName.
  ///
  /// In en, this message translates to:
  /// **'Welcome, {name}'**
  String welcomeName(String name);

  /// No description provided for @editName.
  ///
  /// In en, this message translates to:
  /// **'Edit name'**
  String get editName;

  /// No description provided for @primaryLanguage.
  ///
  /// In en, this message translates to:
  /// **'Primary Language'**
  String get primaryLanguage;

  /// No description provided for @iAlsoSpeak.
  ///
  /// In en, this message translates to:
  /// **'I also speak'**
  String get iAlsoSpeak;

  /// No description provided for @spokenLanguages.
  ///
  /// In en, this message translates to:
  /// **'Spoken Languages'**
  String get spokenLanguages;

  /// No description provided for @homeTourWelcomeNameTitle.
  ///
  /// In en, this message translates to:
  /// **'Your Display Name'**
  String get homeTourWelcomeNameTitle;

  /// No description provided for @homeTourWelcomeNameDesc.
  ///
  /// In en, this message translates to:
  /// **'This is your display name.'**
  String get homeTourWelcomeNameDesc;

  /// No description provided for @chatTourIntroTitle.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get chatTourIntroTitle;

  /// No description provided for @chatTourIntroDesc.
  ///
  /// In en, this message translates to:
  /// **'This is a OneMind chat. You\'ll see how ideas compete until the group reaches a decision. Let\'s walk through how it works.'**
  String get chatTourIntroDesc;

  /// No description provided for @chatTourTitleTitle.
  ///
  /// In en, this message translates to:
  /// **'Chat Name'**
  String get chatTourTitleTitle;

  /// No description provided for @chatTourTitleDesc.
  ///
  /// In en, this message translates to:
  /// **'This is the chat name.'**
  String get chatTourTitleDesc;

  /// No description provided for @chatTourMessageTitle.
  ///
  /// In en, this message translates to:
  /// **'Discussion Question'**
  String get chatTourMessageTitle;

  /// No description provided for @chatTourMessageDesc.
  ///
  /// In en, this message translates to:
  /// **'This is the discussion topic. Everyone submits their idea in response.'**
  String get chatTourMessageDesc;

  /// No description provided for @currentLeader.
  ///
  /// In en, this message translates to:
  /// **'Current Leader'**
  String get currentLeader;

  /// No description provided for @chatTourPlaceholderTitle.
  ///
  /// In en, this message translates to:
  /// **'Placeholder'**
  String get chatTourPlaceholderTitle;

  /// No description provided for @chatTourPlaceholderDesc.
  ///
  /// In en, this message translates to:
  /// **'This is where the chosen idea will go.'**
  String get chatTourPlaceholderDesc;

  /// No description provided for @chatTourPlaceholderDesc2.
  ///
  /// In en, this message translates to:
  /// **'The chat hasn\'t started yet, so it\'s empty for now.'**
  String get chatTourPlaceholderDesc2;

  /// No description provided for @chatTourRoundTitle.
  ///
  /// In en, this message translates to:
  /// **'Round Number'**
  String get chatTourRoundTitle;

  /// No description provided for @chatTourRoundDesc.
  ///
  /// In en, this message translates to:
  /// **'This shows which round the chat is in. The group goes through multiple rounds to choose the winning idea.'**
  String get chatTourRoundDesc;

  /// No description provided for @chatTourPhasesTitle.
  ///
  /// In en, this message translates to:
  /// **'Round Phases'**
  String get chatTourPhasesTitle;

  /// No description provided for @chatTourPhasesDesc.
  ///
  /// In en, this message translates to:
  /// **'Each round has two phases: [proposing] and [rating].'**
  String get chatTourPhasesDesc;

  /// No description provided for @chatTourPhasesDesc2.
  ///
  /// In en, this message translates to:
  /// **'Each round starts in the [proposing] phase.'**
  String get chatTourPhasesDesc2;

  /// No description provided for @chatTourProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Participation'**
  String get chatTourProgressTitle;

  /// No description provided for @chatTourProgressDesc.
  ///
  /// In en, this message translates to:
  /// **'This is the participation bar. It tracks the group\'s progress in the current phase.'**
  String get chatTourProgressDesc;

  /// No description provided for @chatTourProgressDesc2.
  ///
  /// In en, this message translates to:
  /// **'Once it reaches 100%, the chat moves on to the next phase.'**
  String get chatTourProgressDesc2;

  /// No description provided for @chatTourTimerTitle.
  ///
  /// In en, this message translates to:
  /// **'Phase Timer'**
  String get chatTourTimerTitle;

  /// No description provided for @chatTourTimerDesc.
  ///
  /// In en, this message translates to:
  /// **'Each phase has a time limit — when it runs out, the chat moves on.'**
  String get chatTourTimerDesc;

  /// No description provided for @chatTourSubmitTitle.
  ///
  /// In en, this message translates to:
  /// **'Submit Ideas'**
  String get chatTourSubmitTitle;

  /// No description provided for @chatTourSubmitDesc.
  ///
  /// In en, this message translates to:
  /// **'Type your best idea here to replace the placeholder above.'**
  String get chatTourSubmitDesc;

  /// No description provided for @chatTourSubmitDesc2.
  ///
  /// In en, this message translates to:
  /// **'Alex, Sam, and Jordan have already submitted their ideas for this [proposing] phase.'**
  String get chatTourSubmitDesc2;

  /// No description provided for @chatTourSubmitDesc3.
  ///
  /// In en, this message translates to:
  /// **'The better the idea, the higher the rank.'**
  String get chatTourSubmitDesc3;

  /// No description provided for @tutorialR1ProposingHint.
  ///
  /// In en, this message translates to:
  /// **'Propose your idea! Type it below and submit.'**
  String get tutorialR1ProposingHint;

  /// No description provided for @chatTourParticipantsTitle.
  ///
  /// In en, this message translates to:
  /// **'Leaderboard'**
  String get chatTourParticipantsTitle;

  /// No description provided for @chatTourParticipantsDesc.
  ///
  /// In en, this message translates to:
  /// **'Tap [leaderboard] to see the leaderboard.'**
  String get chatTourParticipantsDesc;

  /// No description provided for @chatTourParticipantsDoneTitle.
  ///
  /// In en, this message translates to:
  /// **'Participation Status'**
  String get chatTourParticipantsDoneTitle;

  /// No description provided for @chatTourParticipantsDoneDesc.
  ///
  /// In en, this message translates to:
  /// **'\"Done\" means the participant has contributed to the current phase. Once everyone is done, the chat moves on.'**
  String get chatTourParticipantsDoneDesc;

  /// No description provided for @chatTourLeaderboardParticipants.
  ///
  /// In en, this message translates to:
  /// **'Participants'**
  String get chatTourLeaderboardParticipants;

  /// No description provided for @chatTourLeaderboardParticipantsDesc.
  ///
  /// In en, this message translates to:
  /// **'These are the participants in the chat. You, Alex, Sam, and Jordan.'**
  String get chatTourLeaderboardParticipantsDesc;

  /// No description provided for @chatTourLeaderboardRankings.
  ///
  /// In en, this message translates to:
  /// **'Rankings'**
  String get chatTourLeaderboardRankings;

  /// No description provided for @chatTourLeaderboardRankingsDesc.
  ///
  /// In en, this message translates to:
  /// **'These are the user rankings. Everyone is ranked based on their performance in the [proposing] and [rating] phases across all rounds.'**
  String get chatTourLeaderboardRankingsDesc;

  /// No description provided for @chatTourLeaderboardRankingsDesc2.
  ///
  /// In en, this message translates to:
  /// **'No rounds have been completed yet, so everyone starts unranked.'**
  String get chatTourLeaderboardRankingsDesc2;

  /// No description provided for @chatTourClosePanel.
  ///
  /// In en, this message translates to:
  /// **'Close Leaderboard'**
  String get chatTourClosePanel;

  /// No description provided for @chatTourClosePanelDesc.
  ///
  /// In en, this message translates to:
  /// **'Tap the X to close the leaderboard.'**
  String get chatTourClosePanelDesc;

  /// No description provided for @chatTourShareTitle.
  ///
  /// In en, this message translates to:
  /// **'Share Chat'**
  String get chatTourShareTitle;

  /// No description provided for @chatTourShareDesc.
  ///
  /// In en, this message translates to:
  /// **'Share this chat with friends using an invite link or QR code.'**
  String get chatTourShareDesc;

  /// No description provided for @tutorialShareContinueHint.
  ///
  /// In en, this message translates to:
  /// **'Tap the Continue button to continue the tutorial.'**
  String get tutorialShareContinueHint;

  /// No description provided for @myLanguage.
  ///
  /// In en, this message translates to:
  /// **'My language'**
  String get myLanguage;

  /// No description provided for @notJoined.
  ///
  /// In en, this message translates to:
  /// **'Not joined'**
  String get notJoined;

  /// No description provided for @noChatsMatchFilters.
  ///
  /// In en, this message translates to:
  /// **'No chats match your filters'**
  String get noChatsMatchFilters;

  /// No description provided for @tryAdjustingFilters.
  ///
  /// In en, this message translates to:
  /// **'Try adjusting your language or join filters.'**
  String get tryAdjustingFilters;

  /// No description provided for @tryDifferentSearch.
  ///
  /// In en, this message translates to:
  /// **'Try a different search term.'**
  String get tryDifferentSearch;

  /// No description provided for @viewOtherPropositions.
  ///
  /// In en, this message translates to:
  /// **'View propositions'**
  String get viewOtherPropositions;

  /// No description provided for @otherPropositionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Propositions'**
  String get otherPropositionsTitle;

  /// No description provided for @noOtherPropositionsYet.
  ///
  /// In en, this message translates to:
  /// **'No propositions yet'**
  String get noOtherPropositionsYet;

  /// No description provided for @donate.
  ///
  /// In en, this message translates to:
  /// **'Donate'**
  String get donate;

  /// No description provided for @supportOneMindTitle.
  ///
  /// In en, this message translates to:
  /// **'Support OneMind'**
  String get supportOneMindTitle;

  /// No description provided for @supportOneMindBody.
  ///
  /// In en, this message translates to:
  /// **'OneMind is free and runs on donations. If this group just helped you reach a real decision together, would you consider chipping in to keep it going?'**
  String get supportOneMindBody;

  /// No description provided for @maybeLater.
  ///
  /// In en, this message translates to:
  /// **'Maybe later'**
  String get maybeLater;
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
      <String>['de', 'en', 'es', 'fr', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'es':
      return AppLocalizationsEs();
    case 'fr':
      return AppLocalizationsFr();
    case 'pt':
      return AppLocalizationsPt();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
