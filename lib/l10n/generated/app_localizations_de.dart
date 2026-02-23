// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'OneMind';

  @override
  String get howItWorks => 'So funktioniert es';

  @override
  String get discover => 'Entdecken';

  @override
  String get discoverPublicChats => 'Oeffentliche Chats entdecken';

  @override
  String get discoverChats => 'Chats Entdecken';

  @override
  String get joinWithCode => 'Mit Code Beitreten';

  @override
  String get joinAnExistingChatWithInviteCode =>
      'Einem bestehenden Chat mit Einladungscode beitreten';

  @override
  String get joinChat => 'Chat Beitreten';

  @override
  String get join => 'Beitreten';

  @override
  String get findChat => 'Chat Finden';

  @override
  String get requestToJoin => 'Beitritt Anfragen';

  @override
  String get createChat => 'Chat Erstellen';

  @override
  String get createANewChat => 'Einen neuen Chat erstellen';

  @override
  String get chatCreated => 'Chat Erstellt!';

  @override
  String get cancel => 'Abbrechen';

  @override
  String get continue_ => 'Weiter';

  @override
  String get retry => 'Erneut Versuchen';

  @override
  String get yes => 'Ja';

  @override
  String get no => 'Nein';

  @override
  String get delete => 'Loeschen';

  @override
  String get leave => 'Verlassen';

  @override
  String get kick => 'Entfernen';

  @override
  String get pause => 'Pause';

  @override
  String get resume => 'Fortsetzen';

  @override
  String get remove => 'Entfernen';

  @override
  String get clear => 'Loeschen';

  @override
  String get done => 'Fertig';

  @override
  String get save => 'Speichern';

  @override
  String get officialOneMind => 'Offizielles OneMind';

  @override
  String get official => 'OFFIZIELL';

  @override
  String get pending => 'AUSSTEHEND';

  @override
  String get pendingRequests => 'Ausstehende Anfragen';

  @override
  String get yourChats => 'Deine Chats';

  @override
  String get cancelRequest => 'Anfrage Abbrechen';

  @override
  String cancelRequestQuestion(String chatName) {
    return 'Deine Anfrage zum Beitritt zu \"$chatName\" abbrechen?';
  }

  @override
  String get yesCancel => 'Ja, Abbrechen';

  @override
  String get requestCancelled => 'Anfrage abgebrochen';

  @override
  String get waitingForHostApproval => 'Warte auf Genehmigung des Gastgebers';

  @override
  String get hostApprovalRequired => 'Genehmigung des Gastgebers erforderlich';

  @override
  String get noChatsYet => 'Noch keine Chats';

  @override
  String get discoverPublicChatsJoinOrCreate =>
      'Entdecke oeffentliche Chats, tritt mit einem Code bei oder erstelle deinen eigenen';

  @override
  String get discoverPublicChatsButton => 'Oeffentliche Chats Entdecken';

  @override
  String get noActiveChatsYet =>
      'Noch keine aktiven Chats. Deine genehmigten Chats erscheinen hier.';

  @override
  String get loadingChats => 'Chats werden geladen';

  @override
  String get failedToLoadChats => 'Fehler beim Laden der Chats';

  @override
  String get chatNotFound => 'Chat nicht gefunden';

  @override
  String get failedToLookupChat => 'Fehler bei der Chat-Suche';

  @override
  String failedToJoinChat(String error) {
    return 'Fehler beim Beitreten: $error';
  }

  @override
  String get enterInviteCode => 'Gib den 6-stelligen Einladungscode ein:';

  @override
  String get pleaseEnterSixCharCode => 'Bitte gib einen 6-stelligen Code ein';

  @override
  String get inviteCodeHint => 'ABC123';

  @override
  String hostedBy(String hostName) {
    return 'Organisiert von $hostName';
  }

  @override
  String get thisChatsRequiresInvite => 'Dieser Chat erfordert eine Einladung';

  @override
  String get enterEmailForInvite =>
      'Gib die E-Mail ein, an die deine Einladung gesendet wurde:';

  @override
  String get yourEmailHint => 'deine@email.de';

  @override
  String get pleaseEnterEmailAddress => 'Bitte gib deine E-Mail-Adresse ein';

  @override
  String get pleaseEnterValidEmail => 'Bitte gib eine gueltige E-Mail ein';

  @override
  String get noInviteFoundForEmail =>
      'Keine Einladung fuer diese E-Mail gefunden';

  @override
  String get failedToValidateInvite =>
      'Fehler bei der Validierung der Einladung';

  @override
  String get pleaseVerifyEmailFirst => 'Bitte verifiziere zuerst deine E-Mail';

  @override
  String get verifyEmail => 'E-Mail Verifizieren';

  @override
  String emailVerified(String email) {
    return 'E-Mail verifiziert: $email';
  }

  @override
  String get enterDisplayName => 'Gib deinen Anzeigenamen ein:';

  @override
  String get yourName => 'Dein Name';

  @override
  String get yourNamePlaceholder => 'Dein Name';

  @override
  String get displayName => 'Anzeigename';

  @override
  String get enterYourName => 'Gib deinen Namen ein';

  @override
  String get pleaseEnterYourName => 'Bitte gib deinen Namen ein';

  @override
  String get yourDisplayName => 'Dein Anzeigename';

  @override
  String get yourNameVisibleToAll =>
      'Dein Name wird allen Teilnehmern angezeigt';

  @override
  String get usingSavedName => 'Verwende deinen gespeicherten Namen';

  @override
  String get joinRequestSent =>
      'Anfrage gesendet. Warte auf Genehmigung des Gastgebers.';

  @override
  String get searchPublicChats => 'Oeffentliche Chats suchen...';

  @override
  String noChatsFoundFor(String query) {
    return 'Keine Chats gefunden fuer \"$query\"';
  }

  @override
  String get noPublicChatsAvailable => 'Keine oeffentlichen Chats verfuegbar';

  @override
  String get beFirstToCreate => 'Sei der Erste und erstelle einen!';

  @override
  String failedToLoadPublicChats(String error) {
    return 'Fehler beim Laden oeffentlicher Chats: $error';
  }

  @override
  String participantCount(int count) {
    return '$count Teilnehmer';
  }

  @override
  String participantsCount(int count) {
    return '$count Teilnehmer';
  }

  @override
  String get enterYourNameTitle => 'Gib Deinen Namen Ein';

  @override
  String get anonymous => 'Anonym';

  @override
  String get timerWarning => 'Timer-Warnung';

  @override
  String timerWarningMessage(int minutes) {
    return 'Deine Phasen-Timer sind laenger als das $minutes-Minuten-Zeitfenster.\n\nPhasen koennen ueber die geplante Zeit hinausgehen oder pausieren, wenn das Fenster schliesst.\n\nErwaege kuerzere Timer (5 Min oder 30 Min) fuer geplante Sitzungen.';
  }

  @override
  String get adjustSettings => 'Einstellungen Anpassen';

  @override
  String get continueAnyway => 'Trotzdem Fortfahren';

  @override
  String get chatNowPublic => 'Dein Chat ist jetzt oeffentlich!';

  @override
  String anyoneCanJoinFrom(String chatName) {
    return 'Jeder kann \"$chatName\" auf der Entdecken-Seite finden und beitreten.';
  }

  @override
  String invitesSent(int count) {
    return '$count Einladung gesendet!';
  }

  @override
  String invitesSentPlural(int count) {
    return '$count Einladungen gesendet!';
  }

  @override
  String get noInvitesSent => 'Keine Einladungen gesendet';

  @override
  String get onlyInvitedUsersCanJoin =>
      'Nur eingeladene Benutzer koennen diesem Chat beitreten.';

  @override
  String get shareCodeWithParticipants =>
      'Teile diesen Code mit den Teilnehmern:';

  @override
  String get inviteCodeCopied => 'Einladungscode kopiert';

  @override
  String get tapToCopy => 'Tippen zum Kopieren';

  @override
  String get showQrCode => 'QR-Code Anzeigen';

  @override
  String get addEmailForInviteOnly =>
      'Fuege mindestens eine E-Mail fuer den Nur-Einladungs-Modus hinzu';

  @override
  String get emailAlreadyAdded => 'E-Mail bereits hinzugefuegt';

  @override
  String get settings => 'Einstellungen';

  @override
  String get language => 'Sprache';

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
  String get rankPropositions => 'Vorschlaege Bewerten';

  @override
  String get placing => 'Platzierung: ';

  @override
  String rankedSuccessfully(int count) {
    return '$count Vorschlaege erfolgreich bewertet!';
  }

  @override
  String get failedToSaveRankings => 'Fehler beim Speichern der Bewertungen';

  @override
  String get chatPausedByHost => 'Chat vom Gastgeber pausiert';

  @override
  String get ratingPhaseEnded => 'Bewertungsphase beendet';

  @override
  String get goBack => 'Zurueck';

  @override
  String get ratePropositions => 'Vorschlaege Bewerten';

  @override
  String get submitRatings => 'Bewertungen Absenden';

  @override
  String failedToSubmitRatings(String error) {
    return 'Fehler beim Absenden der Bewertungen: $error';
  }

  @override
  String roundResults(int roundNumber) {
    return 'Ergebnisse Runde $roundNumber';
  }

  @override
  String get noPropositionsToDisplay => 'Keine Vorschlaege zum Anzeigen';

  @override
  String get noPreviousWinner => 'Kein vorheriger Gewinner';

  @override
  String roundWinner(int roundNumber) {
    return 'Gewinner Runde $roundNumber';
  }

  @override
  String roundWinners(int roundNumber) {
    return 'Gewinner Runde $roundNumber';
  }

  @override
  String get unknownProposition => 'Unbekannter Vorschlag';

  @override
  String score(String score) {
    return 'Punktzahl: $score';
  }

  @override
  String soleWinsProgress(int current, int required) {
    return 'Alleinige Siege: $current/$required';
  }

  @override
  String get tiedWinNoConsensus =>
      'Unentschieden (zaehlt nicht fuer Konvergenz)';

  @override
  String nWayTie(int count) {
    return '$count-WAY TIE';
  }

  @override
  String winnerIndexOfTotal(int current, int total) {
    return '$current of $total';
  }

  @override
  String get seeAllResults => 'Alle Ergebnisse Anzeigen';

  @override
  String get startPhase => 'Phase Starten';

  @override
  String get waiting => 'Warten';

  @override
  String get waitingForHostToStart => 'Warte auf Start durch den Gastgeber...';

  @override
  String roundNumber(int roundNumber) {
    return 'Runde $roundNumber';
  }

  @override
  String get viewAllPropositions => 'Alle Vorschlaege anzeigen';

  @override
  String get chatIsPaused => 'Chat pausiert...';

  @override
  String get shareYourIdea => 'Teile deine Idee...';

  @override
  String get addAnotherIdea => 'Weitere Idee hinzufuegen...';

  @override
  String get submit => 'Absenden';

  @override
  String get addProposition => 'Vorschlag Hinzufuegen';

  @override
  String get waitingForRatingPhase => 'Warte auf Bewertungsphase...';

  @override
  String get endProposingStartRating =>
      'Vorschlaege Beenden und Bewertung Starten';

  @override
  String get proposingComplete => 'Vorschlaege Abgeschlossen';

  @override
  String get reviewPropositionsStartRating =>
      'Ueberpruefe die Vorschlaege und starte die Bewertung, wenn du bereit bist.';

  @override
  String get waitingForHostToStartRating =>
      'Warte auf den Gastgeber zum Starten der Bewertungsphase.';

  @override
  String get startRatingPhase => 'Bewertungsphase Starten';

  @override
  String get ratingComplete => 'Bewertung Abgeschlossen';

  @override
  String get waitingForRatingPhaseEnd => 'Warte auf Ende der Bewertungsphase.';

  @override
  String rateAllPropositions(int count) {
    return 'Bewerte alle $count Vorschlaege';
  }

  @override
  String get continueRating => 'Bewertung Fortsetzen';

  @override
  String get startRating => 'Bewertung Starten';

  @override
  String get endRatingStartNextRound =>
      'Bewertung Beenden und Naechste Runde Starten';

  @override
  String get chatPaused => 'Chat Pausiert';

  @override
  String get chatPausedByHostTitle => 'Chat vom Gastgeber Pausiert';

  @override
  String get timerStoppedTapResume =>
      'Der Timer ist gestoppt. Tippe auf Fortsetzen in der Leiste, um fortzufahren.';

  @override
  String get hostPausedPleaseWait =>
      'Der Gastgeber hat diesen Chat pausiert. Bitte warte, bis er fortgesetzt wird.';

  @override
  String get previousWinner => 'Vorheriger Gewinner';

  @override
  String get yourProposition => 'Dein Vorschlag';

  @override
  String get yourPropositions => 'Deine Vorschlaege';

  @override
  String get rate => 'Bewerten';

  @override
  String get participants => 'Teilnehmer';

  @override
  String get chatInfo => 'Chat-Info';

  @override
  String get shareQrCode => 'QR-Code Teilen';

  @override
  String get joinRequests => 'Beitrittsanfragen';

  @override
  String get resumeChat => 'Chat Fortsetzen';

  @override
  String get pauseChat => 'Chat Pausieren';

  @override
  String get leaveChat => 'Chat Verlassen';

  @override
  String get deleteChat => 'Chat Loeschen';

  @override
  String get host => 'Gastgeber';

  @override
  String get deletePropositionQuestion => 'Vorschlag Loeschen?';

  @override
  String get areYouSureDeleteProposition =>
      'Bist du sicher, dass du diesen Vorschlag loeschen moechtest?';

  @override
  String get deleteChatQuestion => 'Chat Loeschen?';

  @override
  String get leaveChatQuestion => 'Chat Verlassen?';

  @override
  String get kickParticipantQuestion => 'Teilnehmer Entfernen?';

  @override
  String get pauseChatQuestion => 'Chat Pausieren?';

  @override
  String get removePaymentMethodQuestion => 'Zahlungsmethode Entfernen?';

  @override
  String get propositionDeleted => 'Vorschlag geloescht';

  @override
  String get chatDeleted => 'Chat geloescht';

  @override
  String get youHaveLeftChat => 'Du hast den Chat verlassen';

  @override
  String get youHaveBeenRemoved => 'Du wurdest aus diesem Chat entfernt';

  @override
  String get chatHasBeenDeleted => 'Dieser Chat wurde geloescht';

  @override
  String participantRemoved(String name) {
    return '$name wurde entfernt';
  }

  @override
  String get chatPausedSuccess => 'Chat pausiert';

  @override
  String get requestApproved => 'Anfrage genehmigt';

  @override
  String get requestDenied => 'Anfrage abgelehnt';

  @override
  String failedToSubmit(String error) {
    return 'Fehler beim Absenden: $error';
  }

  @override
  String get duplicateProposition =>
      'Dieser Vorschlag existiert bereits in dieser Runde';

  @override
  String failedToStartPhase(String error) {
    return 'Fehler beim Starten der Phase: $error';
  }

  @override
  String failedToAdvancePhase(String error) {
    return 'Fehler beim Fortschreiten der Phase: $error';
  }

  @override
  String failedToCompleteRating(String error) {
    return 'Fehler beim Abschliessen der Bewertung: $error';
  }

  @override
  String failedToDelete(String error) {
    return 'Fehler beim Loeschen: $error';
  }

  @override
  String failedToDeleteChat(String error) {
    return 'Fehler beim Loeschen des Chats: $error';
  }

  @override
  String failedToLeaveChat(String error) {
    return 'Fehler beim Verlassen des Chats: $error';
  }

  @override
  String failedToKickParticipant(String error) {
    return 'Fehler beim Entfernen des Teilnehmers: $error';
  }

  @override
  String failedToPauseChat(String error) {
    return 'Fehler beim Pausieren des Chats: $error';
  }

  @override
  String error(String error) {
    return 'Fehler: $error';
  }

  @override
  String get noPendingRequests => 'Keine ausstehenden Anfragen';

  @override
  String get newRequestsWillAppear => 'Neue Anfragen erscheinen hier';

  @override
  String participantsJoined(int count) {
    return '$count Teilnehmer sind beigetreten';
  }

  @override
  String waitingForMoreParticipants(int count) {
    return 'Warte auf $count weitere Teilnehmer';
  }

  @override
  String get noMembersYetShareHint =>
      'Noch keine anderen Mitglieder. Tippe oben auf den Teilen-Button, um Personen einzuladen.';

  @override
  String get scheduled => 'Geplant';

  @override
  String get chatOutsideSchedule =>
      'Chat ausserhalb des geplanten Zeitfensters';

  @override
  String nextWindowStarts(String dateTime) {
    return 'Naechstes Fenster beginnt $dateTime';
  }

  @override
  String get scheduleWindows => 'Geplante Zeitfenster:';

  @override
  String get scheduledToStart => 'Geplanter Start';

  @override
  String get chatWillAutoStart =>
      'Der Chat startet automatisch zur geplanten Zeit.';

  @override
  String submittedCount(int submitted, int total) {
    return '$submitted/$total eingereicht';
  }

  @override
  String propositionCollected(int count) {
    return '$count Vorschlag gesammelt';
  }

  @override
  String propositionsCollected(int count) {
    return '$count Vorschlaege gesammelt';
  }

  @override
  String get timeExpired => 'Zeit abgelaufen';

  @override
  String get noDataAvailable => 'Keine Daten verfuegbar';

  @override
  String get tryAgain => 'Erneut Versuchen';

  @override
  String get requireApproval => 'Genehmigung erforderlich';

  @override
  String get requireAuthentication => 'Authentifizierung erforderlich';

  @override
  String get showPreviousResults =>
      'Vollstaendige Ergebnisse frueherer Runden anzeigen';

  @override
  String get enableAdaptiveDuration => 'Adaptive Dauer aktivieren';

  @override
  String get enableOneMindAI => 'OneMind AI aktivieren';

  @override
  String get enableAutoAdvanceProposing => 'Aktivieren fuer Ideen';

  @override
  String get enableAutoAdvanceRating => 'Aktivieren fuer Bewertungen';

  @override
  String get hideWhenOutsideSchedule => 'Ausserhalb des Zeitplans verbergen';

  @override
  String get chatVisibleButPaused =>
      'Chat sichtbar aber pausiert ausserhalb des Zeitplans';

  @override
  String get chatHiddenUntilNext =>
      'Chat verborgen bis zum naechsten geplanten Fenster';

  @override
  String get timezone => 'Zeitzone';

  @override
  String get scheduleType => 'Zeitplan-Typ';

  @override
  String get oneTime => 'Einmalig';

  @override
  String get recurring => 'Wiederkehrend';

  @override
  String get startDateTime => 'Startdatum und -zeit';

  @override
  String get scheduleWindowsLabel => 'Zeitplan-Fenster';

  @override
  String get addWindow => 'Fenster Hinzufuegen';

  @override
  String get searchTimezone => 'Zeitzone suchen...';

  @override
  String get manual => 'Manuell';

  @override
  String get auto => 'Automatisch';

  @override
  String get credits => 'Guthaben';

  @override
  String get refillAmountMustBeGreater =>
      'Aufladebetrag muss groesser als der Schwellenwert sein';

  @override
  String get autoRefillSettingsUpdated =>
      'Auto-Aufladeeinstellungen aktualisiert';

  @override
  String get autoRefillEnabled => 'Auto-Aufladung aktiviert';

  @override
  String get autoRefillDisabled => 'Auto-Aufladung deaktiviert';

  @override
  String get saveSettings => 'Einstellungen Speichern';

  @override
  String get removeCard => 'Karte Entfernen';

  @override
  String get purchaseWithStripe => 'Mit Stripe Kaufen';

  @override
  String get processing => 'Verarbeitung...';

  @override
  String get pageNotFound => 'Seite Nicht Gefunden';

  @override
  String get goHome => 'Zur Startseite';

  @override
  String allPropositionsCount(int count) {
    return 'Alle Vorschlaege ($count)';
  }

  @override
  String get hostCanModerateContent =>
      'Als Gastgeber kannst du Inhalte moderieren. Die Identitaet des Einreichers ist verborgen.';

  @override
  String get yourPropositionLabel => '(Dein Vorschlag)';

  @override
  String get previousWinnerLabel => '(Vorheriger Gewinner)';

  @override
  String get cannotBeUndone =>
      'Diese Aktion kann nicht rueckgaengig gemacht werden.';

  @override
  String deleteChatConfirmation(String chatName) {
    return 'Bist du sicher, dass du \"$chatName\" loeschen moechtest?\n\nDies loescht dauerhaft alle Vorschlaege, Bewertungen und den Verlauf. Diese Aktion kann nicht rueckgaengig gemacht werden.';
  }

  @override
  String leaveChatConfirmation(String chatName) {
    return 'Bist du sicher, dass du \"$chatName\" verlassen moechtest?\n\nDu wirst diesen Chat nicht mehr in deiner Liste sehen.';
  }

  @override
  String kickParticipantConfirmation(String participantName) {
    return 'Bist du sicher, dass du \"$participantName\" aus diesem Chat entfernen moechtest?\n\nEr kann ohne Genehmigung nicht wieder beitreten.';
  }

  @override
  String get pauseChatConfirmation =>
      'Dies pausiert den Timer der aktuellen Phase. Teilnehmer sehen, dass der Chat vom Gastgeber pausiert wurde.';

  @override
  String get approveOrDenyRequests =>
      'Anfragen zum Beitreten dieses Chats genehmigen oder ablehnen.';

  @override
  String get signedIn => 'Angemeldet';

  @override
  String get guest => 'Gast';

  @override
  String get approve => 'Genehmigen';

  @override
  String get deny => 'Ablehnen';

  @override
  String get initialMessage => 'Initiale Nachricht';

  @override
  String consensusNumber(int number) {
    return 'Konvergenz #$number';
  }

  @override
  String get kickParticipant => 'Teilnehmer entfernen';

  @override
  String get propositions => 'Vorschlaege';

  @override
  String get leaderboard => 'Rangliste';

  @override
  String get noLeaderboardData => 'Keine Ranglistendaten verfuegbar';

  @override
  String get skip => 'Ueberspringen';

  @override
  String get skipped => 'Uebersprungen';

  @override
  String skipsRemaining(int remaining) {
    return '$remaining Ueberspruenge verbleibend';
  }

  @override
  String get createChatTitle => 'Chat Erstellen';

  @override
  String get enterYourNameLabel => 'Gib deinen Namen ein';

  @override
  String get nameVisibleToAll => 'Dein Name wird allen Teilnehmern angezeigt';

  @override
  String get basicInfo => 'Grundlegende Informationen';

  @override
  String get chatNameRequired => 'Chat-Name *';

  @override
  String get chatNameHint => 'z.B., Team-Mittagessen Freitag';

  @override
  String get required => 'Erforderlich';

  @override
  String get initialMessageRequired => 'Initiale Nachricht *';

  @override
  String get initialMessageOptional => 'Initiale Nachricht (Optional)';

  @override
  String get initialMessageHint => 'Das Eroeffnungsthema oder die Frage';

  @override
  String get initialMessageHelperText =>
      'Teilnehmer wissen, dass du dies geschrieben hast, da du den Chat erstellt hast';

  @override
  String get descriptionOptional => 'Beschreibung (Optional)';

  @override
  String get descriptionHint => 'Zusaetzlicher Kontext';

  @override
  String get visibility => 'Sichtbarkeit';

  @override
  String get whoCanJoin => 'Wer kann diesen Chat finden und beitreten?';

  @override
  String get accessPublic => 'Oeffentlich';

  @override
  String get accessPublicDesc => 'Jeder kann entdecken und beitreten';

  @override
  String get accessCode => 'Einladungscode';

  @override
  String get accessCodeDesc => 'Teile einen 6-stelligen Code zum Beitreten';

  @override
  String get accessEmail => 'Nur per E-Mail';

  @override
  String get accessEmailDesc =>
      'Nur eingeladene E-Mail-Adressen koennen beitreten';

  @override
  String get instantJoin => 'Benutzer treten sofort bei';

  @override
  String get inviteByEmail => 'Per E-Mail Einladen';

  @override
  String get inviteEmailOnly =>
      'Nur eingeladene E-Mail-Adressen koennen diesem Chat beitreten';

  @override
  String get emailAddress => 'E-Mail-Adresse';

  @override
  String get emailHint => 'benutzer@beispiel.de';

  @override
  String get invalidEmail => 'Bitte gib eine gueltige E-Mail ein';

  @override
  String get addEmailToSend =>
      'Fuege mindestens eine E-Mail hinzu, um Einladungen zu senden';

  @override
  String get facilitationMode => 'Wie Phasen Ablaufen';

  @override
  String get facilitationDesc =>
      'Waehle zwischen manueller Steuerung oder automatischen Timern fuer Phasenuebergaenge.';

  @override
  String get modeManual => 'Manuell';

  @override
  String get modeAuto => 'Auto';

  @override
  String get modeManualDesc =>
      'Du kontrollierst, wann jede Phase beginnt und endet. Keine Timer.';

  @override
  String get modeAutoDesc =>
      'Timer laufen automatisch. Du kannst Phasen trotzdem frueh beenden.';

  @override
  String get autoStartParticipants => 'Starten wenn diese Anzahl beitritt';

  @override
  String get ratingStartMode => 'Bewertungs-Startmodus';

  @override
  String get ratingStartModeDesc =>
      'Steuert, wie die Bewertungsphase nach den Vorschlaegen beginnt.';

  @override
  String get ratingAutoDesc =>
      'Die Bewertung beginnt sofort nach den Vorschlaegen oder wenn der Schwellenwert erreicht ist.';

  @override
  String get ratingManualDesc =>
      'Nach den Vorschlaegen waehlen Sie, wann die Bewertung beginnt (z.B. am naechsten Tag).';

  @override
  String phaseFlowExplanation(String duration, int threshold, int minimum) {
    return 'Jede Phase laeuft bis zu $duration, endet aber frueh wenn $threshold Personen teilnehmen. Endet nicht bis mindestens $minimum Ideen existieren (Timer verlaengert sich bei Bedarf).';
  }

  @override
  String get enableSchedule => 'Zeitplan Aktivieren';

  @override
  String get restrictChatRoom =>
      'Einschraenken, wann der Chatraum geoeffnet ist';

  @override
  String get timers => 'Timer';

  @override
  String get useSameDuration => 'Gleiche Dauer fur beide Phasen';

  @override
  String get useSameDurationDesc =>
      'Gleiches Zeitlimit fur Vorschlage und Bewertung verwenden';

  @override
  String get phaseDuration => 'Phasendauer';

  @override
  String get proposing => 'Vorschlaege';

  @override
  String get rating => 'Bewertung';

  @override
  String get preset5min => '5 Min';

  @override
  String get preset30min => '30 Min';

  @override
  String get preset1hour => '1 Stunde';

  @override
  String get preset1day => '1 Tag';

  @override
  String get presetCustom => 'Benutzerdefiniert';

  @override
  String get duration1min => '1 Min';

  @override
  String get duration2min => '2 Min';

  @override
  String get duration10min => '10 Min';

  @override
  String get duration2hours => '2 Stunden';

  @override
  String get duration4hours => '4 Stunden';

  @override
  String get duration8hours => '8 Stunden';

  @override
  String get duration12hours => '12 Stunden';

  @override
  String get hours => 'Stunden';

  @override
  String get minutes => 'Minuten';

  @override
  String get max24h => '(max 24h)';

  @override
  String get minimumToAdvance => 'Erforderliche Teilnahme';

  @override
  String get timeExtendsAutomatically =>
      'Die Phase endet nicht, bis die Anforderungen erfuellt sind';

  @override
  String get proposingMinimum => 'Benoetigte Ideen';

  @override
  String proposingMinimumDesc(int count) {
    return 'Die Phase endet nicht, bis $count Ideen eingereicht sind';
  }

  @override
  String get ratingMinimum => 'Benoetigte Bewertungen';

  @override
  String ratingMinimumDesc(int count) {
    return 'Die Phase endet nicht, bis jede Idee $count Bewertungen hat';
  }

  @override
  String get autoAdvanceAt => 'Phase Frueh Beenden';

  @override
  String get skipTimerEarly =>
      'Die Phase kann frueh enden, wenn die Schwellenwerte erreicht sind';

  @override
  String whenPercentSubmit(int percent) {
    return 'Wenn $percent% der Teilnehmer einreichen';
  }

  @override
  String get minParticipantsSubmit => 'Benoetigte Ideen';

  @override
  String get minAvgRaters => 'Benoetigte Bewertungen';

  @override
  String proposingThresholdPreview(
    int threshold,
    int participants,
    int percent,
  ) {
    return 'Phase endet frueh wenn $threshold von $participants Teilnehmern Ideen einreichen ($percent%)';
  }

  @override
  String proposingThresholdPreviewSimple(int threshold) {
    return 'Phase endet frueh, wenn $threshold Ideen eingereicht sind';
  }

  @override
  String ratingThresholdPreview(int threshold) {
    return 'Phase endet frueh, wenn jede Idee $threshold Bewertungen hat';
  }

  @override
  String get consensusSettings => 'Konvergenz-Einstellungen';

  @override
  String get confirmationRounds => 'Bestaetigungsrunden';

  @override
  String get firstWinnerConsensus =>
      'Der erste Gewinner erreicht sofort Konvergenz';

  @override
  String mustWinConsecutive(int count) {
    return 'Derselbe Vorschlag muss $count Runden hintereinander gewinnen';
  }

  @override
  String get showFullResults =>
      'Vollstaendige Ergebnisse aus frueheren Runden anzeigen';

  @override
  String get seeAllPropositions =>
      'Benutzer sehen alle Vorschlaege und Bewertungen';

  @override
  String get seeWinningOnly => 'Benutzer sehen nur den Gewinnervorschlag';

  @override
  String get propositionLimits => 'Vorschlagslimits';

  @override
  String get propositionsPerUser => 'Vorschlaege pro Benutzer';

  @override
  String get onePropositionPerRound =>
      'Jeder Benutzer kann 1 Vorschlag pro Runde einreichen';

  @override
  String nPropositionsPerRound(int count) {
    return 'Jeder Benutzer kann bis zu $count Vorschlaege pro Runde einreichen';
  }

  @override
  String get adaptiveDuration => 'Adaptive Dauer';

  @override
  String get adjustDurationDesc =>
      'Phasendauer automatisch basierend auf Teilnahme anpassen';

  @override
  String get durationAdjusts => 'Dauer passt sich basierend auf Teilnahme an';

  @override
  String get fixedDurations => 'Feste Phasendauern';

  @override
  String get usesThresholds =>
      'Verwendet Frueh-Vorlauf-Schwellenwerte zur Bestimmung der Teilnahme';

  @override
  String adjustmentPercent(int percent) {
    return 'Anpassung: $percent%';
  }

  @override
  String get minDuration => 'Mindestdauer';

  @override
  String get maxDuration => 'Maximaldauer';

  @override
  String get aiParticipant => 'KI-Teilnehmer';

  @override
  String get enableAI => 'OneMind AI aktivieren';

  @override
  String get aiPropositionsPerRound => 'KI-Vorschlaege pro Runde';

  @override
  String get scheduleTypeLabel => 'Zeitplan-Typ';

  @override
  String get scheduleOneTime => 'Einmalig';

  @override
  String get scheduleRecurring => 'Wiederkehrend';

  @override
  String get hideOutsideSchedule => 'Ausserhalb des Zeitplans verbergen';

  @override
  String get visiblePaused =>
      'Chat sichtbar aber pausiert ausserhalb des Zeitplans';

  @override
  String get hiddenUntilWindow =>
      'Chat verborgen bis zum naechsten geplanten Fenster';

  @override
  String get timezoneLabel => 'Zeitzone';

  @override
  String get scheduleWindowsTitle => 'Zeitplan-Fenster';

  @override
  String get addWindowButton => 'Fenster Hinzufuegen';

  @override
  String get scheduleWindowsDesc =>
      'Lege fest, wann der Chat aktiv ist. Unterstuetzt Nachtfenster (z.B. 23 Uhr bis 1 Uhr am naechsten Tag).';

  @override
  String windowNumber(int n) {
    return 'Fenster $n';
  }

  @override
  String get removeWindow => 'Fenster entfernen';

  @override
  String get startDay => 'Starttag';

  @override
  String get endDay => 'Endtag';

  @override
  String get daySun => 'So';

  @override
  String get dayMon => 'Mo';

  @override
  String get dayTue => 'Di';

  @override
  String get dayWed => 'Mi';

  @override
  String get dayThu => 'Do';

  @override
  String get dayFri => 'Fr';

  @override
  String get daySat => 'Sa';

  @override
  String get timerWarningTitle => 'Timer-Warnung';

  @override
  String timerWarningContent(int minutes) {
    return 'Deine Phasen-Timer sind laenger als das $minutes-Minuten-Zeitfenster.\n\nPhasen koennen ueber die geplante Zeit hinausgehen oder pausieren, wenn das Fenster schliesst.\n\nErwaege kuerzere Timer (5 Min oder 30 Min) fuer geplante Sitzungen.';
  }

  @override
  String get adjustSettingsButton => 'Einstellungen Anpassen';

  @override
  String get continueAnywayButton => 'Trotzdem Fortfahren';

  @override
  String get chatCreatedTitle => 'Chat Erstellt!';

  @override
  String get chatNowPublicTitle => 'Dein Chat ist jetzt oeffentlich!';

  @override
  String anyoneCanJoinDiscover(String name) {
    return 'Jeder kann \"$name\" auf der Entdecken-Seite finden und beitreten.';
  }

  @override
  String invitesSentTitle(int count) {
    return '$count Einladungen gesendet!';
  }

  @override
  String get noInvitesSentTitle => 'Keine Einladungen gesendet';

  @override
  String get inviteOnlyMessage =>
      'Nur eingeladene Benutzer koennen diesem Chat beitreten.';

  @override
  String get shareCodeInstruction => 'Teile diesen Code mit den Teilnehmern:';

  @override
  String get codeCopied => 'Einladungscode kopiert';

  @override
  String get joinScreenTitle => 'Chat Beitreten';

  @override
  String get noTokenOrCode => 'Kein Einladungs-Token oder -Code angegeben';

  @override
  String get invalidExpiredInvite =>
      'Dieser Einladungslink ist ungueltig oder abgelaufen';

  @override
  String get inviteOnlyError =>
      'Dieser Chat erfordert eine E-Mail-Einladung. Bitte verwende den an deine E-Mail gesendeten Link.';

  @override
  String get invalidInviteTitle => 'Ungueltige Einladung';

  @override
  String get invalidInviteDefault => 'Dieser Einladungslink ist nicht gueltig.';

  @override
  String get invitedToJoin => 'Du bist eingeladen beizutreten';

  @override
  String get enterNameToJoin => 'Gib deinen Namen ein, um beizutreten:';

  @override
  String get nameVisibleNotice =>
      'Dieser Name wird anderen Teilnehmern angezeigt.';

  @override
  String get requiresApprovalNotice =>
      'Dieser Chat erfordert die Genehmigung des Gastgebers zum Beitreten.';

  @override
  String get requestToJoinButton => 'Beitritt Anfragen';

  @override
  String get joinChatButton => 'Chat Beitreten';

  @override
  String get creditsTitle => 'Guthaben';

  @override
  String get yourBalance => 'Dein Kontostand';

  @override
  String get paidCredits => 'Bezahlte Guthaben';

  @override
  String get freeThisMonth => 'Gratis diesen Monat';

  @override
  String get totalAvailable => 'Gesamt Verfuegbar';

  @override
  String get userRounds => 'Benutzer-Runden';

  @override
  String freeTierResets(String date) {
    return 'Gratis-Stufe wird zurueckgesetzt $date';
  }

  @override
  String get buyCredits => 'Guthaben Kaufen';

  @override
  String get pricingInfo => '1 Guthaben = 1 Benutzer-Runde = 0,01\$';

  @override
  String get total => 'Gesamt';

  @override
  String get autoRefillTitle => 'Auto-Aufladung';

  @override
  String get autoRefillDesc =>
      'Guthaben automatisch kaufen, wenn der Kontostand unter den Schwellenwert faellt';

  @override
  String lastError(String error) {
    return 'Letzter Fehler: $error';
  }

  @override
  String get autoRefillComingSoon =>
      'Auto-Aufladung-Einrichtung bald verfuegbar. Kaufe vorerst Guthaben manuell oben.';

  @override
  String get whenBelow => 'Wenn unter';

  @override
  String get refillTo => 'Aufladen auf';

  @override
  String get disableAutoRefillMessage =>
      'Dies wird die Auto-Aufladung deaktivieren. Du kannst spaeter eine neue Zahlungsmethode hinzufuegen.';

  @override
  String get recentTransactions => 'Letzte Transaktionen';

  @override
  String get noTransactionHistory => 'Keine Transaktionshistorie';

  @override
  String get chatSettingsTitle => 'Chat-Einstellungen';

  @override
  String get accessVisibility => 'Zugang & Sichtbarkeit';

  @override
  String get accessMethod => 'Zugriffsmethode';

  @override
  String get facilitation => 'Moderation';

  @override
  String get startMode => 'Startmodus';

  @override
  String get autoStartThreshold => 'Auto-Start-Schwelle';

  @override
  String nParticipants(int n) {
    return '$n Teilnehmer';
  }

  @override
  String get proposingDuration => 'Vorschlagsdauer';

  @override
  String get ratingDuration => 'Bewertungsdauer';

  @override
  String nSeconds(int n) {
    return '$n Sekunden';
  }

  @override
  String nMinutes(int n) {
    return '$n Minuten';
  }

  @override
  String nHours(int n) {
    return '$n Stunden';
  }

  @override
  String nDays(int n) {
    return '$n Tage';
  }

  @override
  String get minimumRequirements => 'Mindestanforderungen';

  @override
  String nPropositions(int n) {
    return '$n Vorschlaege';
  }

  @override
  String nAvgRaters(double n) {
    return '$n durchschnittliche Bewerter pro Vorschlag';
  }

  @override
  String get earlyAdvanceThresholds => 'Frueh-Vorlauf-Schwellenwerte';

  @override
  String get proposingThreshold => 'Vorschlags-Schwelle';

  @override
  String get ratingThreshold => 'Bewertungs-Schwelle';

  @override
  String nConsecutiveWins(int n) {
    return '$n aufeinanderfolgende Siege';
  }

  @override
  String get enabled => 'Aktiviert';

  @override
  String nPerRound(int n) {
    return '$n pro Runde';
  }

  @override
  String get scheduledStart => 'Geplanter Start';

  @override
  String get windows => 'Fenster';

  @override
  String nConfigured(int n) {
    return '$n konfiguriert';
  }

  @override
  String get visibleOutsideSchedule => 'Sichtbar Ausserhalb des Zeitplans';

  @override
  String get chatSettings => 'Chat-Einstellungen';

  @override
  String get chatName => 'Name';

  @override
  String get chatDescription => 'Beschreibung';

  @override
  String get accessAndVisibility => 'Zugang und Sichtbarkeit';

  @override
  String get autoMode => 'Automatisch';

  @override
  String get avgRatersPerProposition =>
      'durchschnittliche Bewerter pro Vorschlag';

  @override
  String get consensus => 'Konvergenz';

  @override
  String get aiPropositions => 'KI-Vorschläge';

  @override
  String get perRound => 'pro Runde';

  @override
  String get schedule => 'Zeitplan';

  @override
  String get configured => 'konfiguriert';

  @override
  String get publicAccess => 'Öffentlich';

  @override
  String get inviteCodeAccess => 'Einladungscode';

  @override
  String get inviteOnlyAccess => 'Nur auf Einladung';

  @override
  String get privacyPolicyTitle => 'Datenschutzrichtlinie';

  @override
  String get termsOfServiceTitle => 'Nutzungsbedingungen';

  @override
  String get legalDocuments => 'Legal';

  @override
  String get byContinuingYouAgree => 'By continuing, you agree to our';

  @override
  String get andText => 'and';

  @override
  String lastUpdated(String date) {
    return 'Letzte Aktualisierung: $date';
  }

  @override
  String shareLinkTitle(String chatName) {
    return 'Link teilen, um $chatName beizutreten';
  }

  @override
  String get shareButton => 'Teilen';

  @override
  String get copyLinkButton => 'Link kopieren';

  @override
  String get linkCopied => 'Link in Zwischenablage kopiert';

  @override
  String get enterCodeManually => 'Oder Code manuell eingeben:';

  @override
  String get shareNotSupported => 'Teilen nicht verfuegbar - Link kopiert';

  @override
  String get orScan => 'oder scannen';

  @override
  String get tutorialTemplateCommunity => 'Gemeinschaftsentscheidung';

  @override
  String get tutorialTemplateCommunityDesc =>
      'Was sollte unsere Nachbarschaft gemeinsam tun?';

  @override
  String get tutorialTemplateWorkplace => 'Arbeitskultur';

  @override
  String get tutorialTemplateWorkplaceDesc =>
      'Worauf sollte unser Team sich konzentrieren?';

  @override
  String get tutorialTemplateWorld => 'Globale Themen';

  @override
  String get tutorialTemplateWorldDesc =>
      'Welches globale Thema ist am wichtigsten?';

  @override
  String get tutorialTemplateFamily => 'Familie';

  @override
  String get tutorialTemplateFamilyDesc =>
      'Wohin sollen wir in den Urlaub fahren?';

  @override
  String get tutorialTemplatePersonal => 'Persönliche Entscheidung';

  @override
  String get tutorialTemplatePersonalDesc =>
      'Was soll ich nach dem Abschluss tun?';

  @override
  String get tutorialTemplateGovernment => 'Stadthaushalt';

  @override
  String get tutorialTemplateGovernmentDesc =>
      'Wie sollen wir den Stadthaushalt ausgeben?';

  @override
  String get tutorialTemplateCustom => 'Eigenes Thema';

  @override
  String get tutorialTemplateCustomDesc => 'Eigene Frage eingeben';

  @override
  String get tutorialCustomQuestionHint => 'Frage eingeben...';

  @override
  String tutorialRound1ResultTemplate(String winner) {
    return '\'$winner\' hat diese Runde gewonnen! Aber es ist noch nicht endgültig. Es muss die naechste Runde gewinnen, um dauerhaft zum Gruppenchat hinzugefügt zu werden.';
  }

  @override
  String tutorialRound2PromptTemplate(String winner) {
    return 'Der Gewinner \'$winner\' wird automatisch uebernommen, um erneut anzutreten. Er muss 2 Runden hintereinander gewinnen, um eine dauerhafte Antwort zu werden.';
  }

  @override
  String get tutorialAppBarTitle => 'OneMind-Tutorial';

  @override
  String get tutorialWelcomeTitle => 'Willkommen!';

  @override
  String get tutorialWelcomeSubtitle => 'Wähle ein Übungsszenario';

  @override
  String get tutorialTheQuestion => 'Die Frage:';

  @override
  String get tutorialQuestion => 'Was schaetzen wir?';

  @override
  String get tutorialStartButton => 'Tutorial Starten';

  @override
  String get tutorialSkipButton => 'Tutorial ueberspringen';

  @override
  String get tutorialConsensusReached => 'Konvergenz Erreicht!';

  @override
  String tutorialWonTwoRounds(String proposition) {
    return '\"$proposition\" hat 2 Runden hintereinander gewonnen.';
  }

  @override
  String get tutorialAddedToChat =>
      'Es wurde jetzt zum Chat oben hinzugefuegt.';

  @override
  String get tutorialFinishButton => 'Tutorial Beenden';

  @override
  String get tutorialRound1Result =>
      '\'Erfolg\' hat diese Runde gewonnen! Aber es ist noch nicht endgültig. Es muss die naechste Runde gewinnen, um dauerhaft zum Gruppenchat hinzugefügt zu werden.';

  @override
  String get tutorialProposingHint =>
      'Reiche eine Idee ein, die zur Antwort der Gruppe werden soll.';

  @override
  String tutorialTimeRemaining(String time) {
    return 'Du hast noch $time.';
  }

  @override
  String get tutorialProposingHintWithWinner =>
      'Reiche eine neue Idee ein. Sie wird zusammen mit dem vorherigen Gewinner bewertet.';

  @override
  String get tutorialRatingHint =>
      'Jetzt bewertet jeder die Ideen der anderen. Tippe auf die Schaltflaeche, um mit der Bewertung zu beginnen.';

  @override
  String get tutorialRatingPhaseExplanation =>
      'Die Bewertungsphase beginnt, sobald alle Nutzer ihre Ideen eingereicht haben oder der Timer ablaeuft.';

  @override
  String tutorialRatingTimeRemaining(String time) {
    return 'Du hast noch $time, um die Bewertungsphase abzuschliessen.';
  }

  @override
  String get tutorialRatingBinaryHint =>
      'Dir werden zuerst 2 zufaellige, von Nutzern eingereichte Vorschlaege praesentiert. Setze den, den du mehr bevorzugst, auf 100. Tippe auf [swap] um sie zu wechseln, und tippe dann auf [check] um zu bestaetigen. Hinweis: Dein eigener Vorschlag wird dir nicht zur Bewertung angezeigt.';

  @override
  String get tutorialRatingPositioningHint =>
      'Tippe und halte [up] und [down] um die hervorgehobene Idee zu verschieben. Tippe auf [check] um sie zu platzieren. Tippe auf [undo] um eine Platzierung rueckgaengig zu machen, und [zoomin] [zoomout] zum Vergroessern und Verkleinern.';

  @override
  String tutorialRound2Result(String proposition) {
    return 'Deine Idee \"$proposition\" hat gewonnen! Wenn sie auch die naechste Runde gewinnt, wird sie eine dauerhafte Antwort.';
  }

  @override
  String get tutorialRound2Prompt =>
      'Der Gewinner \'Erfolg\' wird automatisch uebernommen, um erneut anzutreten. Er muss 2 Runden hintereinander gewinnen, um eine dauerhafte Antwort zu werden.';

  @override
  String get tutorialRatingCarryForwardHint =>
      'Das ist der Gewinner der letzten Runde. Wenn er diese Runde erneut gewinnt, wird er dauerhaft zum Chat hinzugefuegt.';

  @override
  String get tutorialRound2PromptSimplified =>
      'Zeit fuer die naechste Runde! Faellt dir etwas Besseres ein?';

  @override
  String tutorialRound2PromptSimplifiedTemplate(String winner) {
    return 'Zeit fuer die naechste Runde! Faellt dir etwas Besseres ein als \'$winner\'?';
  }

  @override
  String get tutorialPropSuccess => 'Erfolg';

  @override
  String get tutorialPropAdventure => 'Abenteuer';

  @override
  String get tutorialPropGrowth => 'Wachstum';

  @override
  String get tutorialPropHarmony => 'Harmonie';

  @override
  String get tutorialPropInnovation => 'Innovation';

  @override
  String get tutorialPropFreedom => 'Freiheit';

  @override
  String get tutorialPropSecurity => 'Sicherheit';

  @override
  String get tutorialPropStability => 'Stabilitaet';

  @override
  String get tutorialPropTravelAbroad => 'Auslandsreise';

  @override
  String get tutorialPropStartABusiness => 'Unternehmen gruenden';

  @override
  String get tutorialPropGraduateSchool => 'Masterstudium';

  @override
  String get tutorialPropGetAJobFirst => 'Erst einen Job finden';

  @override
  String get tutorialPropTakeAGapYear => 'Auszeit nehmen';

  @override
  String get tutorialPropFreelance => 'Freiberuflich arbeiten';

  @override
  String get tutorialPropMoveToANewCity => 'In eine neue Stadt ziehen';

  @override
  String get tutorialPropVolunteerProgram => 'Freiwilligenprogramm';

  @override
  String get tutorialPropBeachResort => 'Strandresort';

  @override
  String get tutorialPropMountainCabin => 'Berghuette';

  @override
  String get tutorialPropCityTrip => 'Staedtereise';

  @override
  String get tutorialPropRoadTrip => 'Roadtrip';

  @override
  String get tutorialPropCampingAdventure => 'Campingabenteuer';

  @override
  String get tutorialPropCruise => 'Kreuzfahrt';

  @override
  String get tutorialPropThemePark => 'Freizeitpark';

  @override
  String get tutorialPropCulturalExchange => 'Kulturaustausch';

  @override
  String get tutorialPropBlockParty => 'Strassenfest';

  @override
  String get tutorialPropCommunityGarden => 'Gemeinschaftsgarten';

  @override
  String get tutorialPropNeighborhoodWatch => 'Nachbarschaftswache';

  @override
  String get tutorialPropToolLibrary => 'Werkzeugbibliothek';

  @override
  String get tutorialPropMutualAidFund => 'Solidaritaetsfonds';

  @override
  String get tutorialPropFreeLittleLibrary => 'Offener Buecherschrank';

  @override
  String get tutorialPropStreetMural => 'Strassenwandbild';

  @override
  String get tutorialPropSkillShareNight => 'Faehigkeiten-Abend';

  @override
  String get tutorialPropFlexibleHours => 'Flexible Arbeitszeiten';

  @override
  String get tutorialPropMentalHealthSupport => 'Psychische Gesundheit';

  @override
  String get tutorialPropTeamBuilding => 'Teambildung';

  @override
  String get tutorialPropSkillsTraining => 'Weiterbildung';

  @override
  String get tutorialPropOpenCommunication => 'Offene Kommunikation';

  @override
  String get tutorialPropFairCompensation => 'Faire Verguetung';

  @override
  String get tutorialPropWorkLifeBalance => 'Work-Life-Balance';

  @override
  String get tutorialPropInnovationTime => 'Innovationszeit';

  @override
  String get tutorialPropPublicTransportation => 'Nahverkehr';

  @override
  String get tutorialPropSchoolFunding => 'Schulfinanzierung';

  @override
  String get tutorialPropEmergencyServices => 'Rettungsdienste';

  @override
  String get tutorialPropRoadRepairs => 'Strassensanierung';

  @override
  String get tutorialPropPublicHealth => 'Gesundheitswesen';

  @override
  String get tutorialPropAffordableHousing => 'Bezahlbarer Wohnraum';

  @override
  String get tutorialPropSmallBusinessGrants => 'KMU-Foerderung';

  @override
  String get tutorialPropParksAndRecreation => 'Parks & Erholung';

  @override
  String get tutorialPropClimateChange => 'Klimawandel';

  @override
  String get tutorialPropGlobalPoverty => 'Globale Armut';

  @override
  String get tutorialPropAiGovernance => 'KI-Governance';

  @override
  String get tutorialPropPandemicPreparedness => 'Pandemievorsorge';

  @override
  String get tutorialPropNuclearDisarmament => 'Nukleare Abruestung';

  @override
  String get tutorialPropOceanConservation => 'Meeresschutz';

  @override
  String get tutorialPropDigitalRights => 'Digitale Rechte';

  @override
  String get tutorialPropSpaceCooperation => 'Weltraumkooperation';

  @override
  String get tutorialDuplicateProposition =>
      'Diese Idee existiert bereits in dieser Runde. Versuche etwas anderes!';

  @override
  String get tutorialShareTitle => 'Teile Deinen Chat';

  @override
  String get tutorialShareExplanation =>
      'Um andere einzuladen, deinem Chat beizutreten, tippe auf den Teilen-Button oben auf deinem Bildschirm.';

  @override
  String get tutorialShareTryIt => 'Probiere es jetzt!';

  @override
  String get tutorialShareButtonHint =>
      'Tippe auf den Teilen-Button oben rechts ↗';

  @override
  String get tutorialSkipMenuItem => 'Tutorial Ueberspringen';

  @override
  String get tutorialSkipConfirmTitle => 'Tutorial Ueberspringen?';

  @override
  String get tutorialSkipConfirmMessage =>
      'Du kannst das Tutorial spaeter jederzeit vom Startbildschirm aus aufrufen.';

  @override
  String get tutorialSkipConfirmYes => 'Ja, Ueberspringen';

  @override
  String get tutorialSkipConfirmNo => 'Tutorial Fortsetzen';

  @override
  String get tutorialShareTooltip => 'Chat Teilen';

  @override
  String get tutorialYourIdea => 'Deine Idee';

  @override
  String get tutorialRateIdeas => 'Ideen Bewerten';

  @override
  String tutorialResultsBackHint(String winner) {
    return '\'$winner\' hat gewonnen! Druecke den Zurueck-Pfeil, wenn du mit dem Ansehen der Ergebnisse fertig bist.';
  }

  @override
  String deleteConsensusTitle(int number) {
    return 'Konvergenz #$number loeschen?';
  }

  @override
  String get deleteConsensusMessage =>
      'This will restart the current cycle with a fresh round.';

  @override
  String get deleteInitialMessageTitle => 'Delete Initial Message?';

  @override
  String get deleteInitialMessageMessage =>
      'This will restart the current cycle with a fresh round.';

  @override
  String get editInitialMessage => 'Edit Initial Message';

  @override
  String get consensusDeleted => 'Konvergenz geloescht';

  @override
  String get initialMessageUpdated => 'Initial message updated';

  @override
  String get initialMessageDeleted => 'Initial message deleted';

  @override
  String failedToDeleteConsensus(String error) {
    return 'Fehler beim Loeschen der Konvergenz: $error';
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
  String get deleteTaskResultMessage =>
      'The agent will re-research on the next heartbeat.';

  @override
  String get taskResultDeleted => 'Research results deleted';

  @override
  String failedToDeleteTaskResult(String error) {
    return 'Failed to delete research results: $error';
  }

  @override
  String get wizardStep1Title => 'Worueber moechtest du sprechen?';

  @override
  String get wizardStep1Subtitle => 'Dies ist das Herzstück deines Chats';

  @override
  String get wizardStep2Title => 'Tempo festlegen';

  @override
  String get wizardStep2Subtitle => 'Wie lange fuer jede Phase?';

  @override
  String get wizardOneLastThing => 'Noch eine Sache...';

  @override
  String get wizardProposingLabel => 'Vorschlagen (Ideen einreichen)';

  @override
  String get wizardRatingLabel => 'Bewerten (Ideen ranken)';

  @override
  String get back => 'Zurueck';

  @override
  String get spectatingInsufficientCredits =>
      'Spectating — insufficient credits';

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
  String get forceAsConsensus => 'Als Konvergenz erzwingen';

  @override
  String get forceAsConsensusDescription =>
      'Direkt als Konvergenz einreichen, Abstimmung ueberspringen';

  @override
  String get forceConsensus => 'Konvergenz Erzwingen';

  @override
  String get forceConsensusTitle => 'Konvergenz Erzwingen?';

  @override
  String get forceConsensusMessage =>
      'Dies wird deinen Vorschlag sofort als Konvergenz festlegen und einen neuen Zyklus starten. Aller aktuelle Rundenfortschritt geht verloren.';

  @override
  String get forceConsensusSuccess => 'Konvergenz erfolgreich erzwungen';

  @override
  String failedToForceConsensus(String error) {
    return 'Fehler beim Erzwingen der Konvergenz: $error';
  }

  @override
  String get glossaryUserRoundTitle => 'user-round';

  @override
  String get glossaryUserRoundDef =>
      'One participant completing one round of rating. Each user-round costs 1 credit (\$0.01).';

  @override
  String get glossaryConsensusTitle => 'Konvergenz';

  @override
  String get glossaryConsensusDef =>
      'Wenn derselbe Vorschlag mehrere aufeinanderfolgende Runden gewinnt, hat die Gruppe eine Konvergenz zu dieser Idee erreicht.';

  @override
  String get glossaryProposingTitle => 'proposing';

  @override
  String get glossaryProposingDef =>
      'The phase where participants submit their ideas anonymously for the group to consider.';

  @override
  String get glossaryRatingTitle => 'rating';

  @override
  String get glossaryRatingDef =>
      'The phase where participants rank all propositions on a 0–100 grid to determine the winner.';

  @override
  String get glossaryCycleTitle => 'cycle';

  @override
  String get glossaryCycleDef =>
      'Eine Abfolge von Runden auf dem Weg zur Konvergenz. Ein neuer Zyklus beginnt, nachdem die Konvergenz erreicht wurde.';

  @override
  String get glossaryCreditBalanceTitle => 'credit balance';

  @override
  String get glossaryCreditBalanceDef =>
      'Credits fund rounds. 1 credit = 1 user-round = \$0.01. Free credits reset monthly.';

  @override
  String get enterTaskResult => 'Enter task result...';

  @override
  String get submitResult => 'Submit Result';

  @override
  String get taskResultSubmitted => 'Task result submitted';
}
