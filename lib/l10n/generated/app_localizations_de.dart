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
  String get joined => 'Beigetreten';

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
  String get official => 'OFFIZIELL';

  @override
  String get pending => 'AUSSTEHEND';

  @override
  String get pendingRequests => 'Ausstehende Anfragen';

  @override
  String get yourChats => 'Deine Chats';

  @override
  String get nextUp => 'Als Nächstes';

  @override
  String nextUpWithCount(int count) {
    return 'Als Nächstes ($count)';
  }

  @override
  String get wrappingUp => 'Läuft aus';

  @override
  String wrappingUpWithCount(int count) {
    return 'Läuft aus ($count)';
  }

  @override
  String get inactive => 'Inaktiv';

  @override
  String inactiveWithCount(int count) {
    return 'Inaktiv ($count)';
  }

  @override
  String get allChats => 'Alle Chats';

  @override
  String allChatsWithCount(int count) {
    return 'Alle Chats ($count)';
  }

  @override
  String get noChatsHere => 'Nichts hier — alles erledigt.';

  @override
  String get enableNotificationsTitle =>
      'Werde benachrichtigt, wenn du dran bist';

  @override
  String get enableNotificationsBody =>
      'Wir melden uns, wenn eine Runde dich braucht.';

  @override
  String get enableNotificationsCta => 'Aktivieren';

  @override
  String get notificationsBlockedTitle => 'Benachrichtigungen sind blockiert';

  @override
  String get notificationsBlockedBody =>
      'Entsperre sie in den Seiteneinstellungen deines Browsers.';

  @override
  String get gotIt => 'Verstanden';

  @override
  String get notNow => 'Später';

  @override
  String get installOneMindTitle => 'OneMind installieren';

  @override
  String get installOneMindBody =>
      'Füge es zum Startbildschirm hinzu für die beste Erfahrung.';

  @override
  String get installOneMindIosBody =>
      'Tippe auf Teilen und dann \"Zum Home-Bildschirm\".';

  @override
  String get installCta => 'Installieren';

  @override
  String get lookingForMore => 'Tritt einem bei, um dranzubleiben';

  @override
  String get lookingForMoreDescription =>
      'Öffentliche Chats mit der meisten Aktivität.';

  @override
  String get discoverPublicChatsCta => 'Öffentliche Chats entdecken';

  @override
  String get seeAllPublicChats => 'Alle öffentlichen Chats anzeigen';

  @override
  String get nothingToJoinTitle => 'Gerade nichts Neues zum Beitreten';

  @override
  String get nothingToJoinDescription =>
      'Starte deinen eigenen Chat und lade andere ein.';

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
  String get hostApprovalRequired =>
      'Genehmigung des Gastgebers erforderlich, um beizutreten';

  @override
  String get noChatsYet => 'Noch keine Chats';

  @override
  String get discoverPublicChatsJoinOrCreate =>
      'Suche oben nach oeffentlichen Chats, oder tippe auf + um deinen eigenen zu erstellen.';

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
  String get roundResults => 'Bewertungsergebnisse';

  @override
  String convergenceHistory(int number) {
    return 'Konvergenz $number Verlauf';
  }

  @override
  String convergenceNumber(int number) {
    return 'Convergence #$number';
  }

  @override
  String get noPropositionsToDisplay => 'Keine Vorschlaege zum Anzeigen';

  @override
  String get noPreviousWinner => 'Noch kein Kandidat';

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
    return '$count-FACHES UNENTSCHIEDEN';
  }

  @override
  String winnerIndexOfTotal(int current, int total) {
    return '$current von $total';
  }

  @override
  String get seeAllResults => 'Alle Ergebnisse Anzeigen';

  @override
  String get viewAllRatings => 'Alle Bewertungen Anzeigen';

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
  String get previousWinner => 'Aktueller Spitzenkandidat';

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
  String get turnMusicOn => 'Musik einschalten';

  @override
  String get turnMusicOff => 'Musik ausschalten';

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
  String get startDateTime => 'Startdatum und -uhrzeit';

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
  String get somethingWentWrong => 'Etwas ist schiefgelaufen';

  @override
  String get pageNotFoundMessage =>
      'Die Seite, die Sie suchen, existiert nicht.';

  @override
  String get demoTitle => 'Demo';

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
  String get previousWinnerLabel => '(Aktueller Spitzenkandidat)';

  @override
  String get cannotBeUndone =>
      'Diese Aktion kann nicht rueckgaengig gemacht werden.';

  @override
  String deleteChatConfirmation(String chatName) {
    return 'Bist du sicher, dass du \"$chatName\" loeschen moechtest?\n\nDies loescht dauerhaft alle Vorschlaege, Bewertungen und den Verlauf. Diese Aktion kann nicht rueckgaengig gemacht werden.';
  }

  @override
  String leaveChatConfirmation(String chatName) {
    return 'Bist du sicher, dass du \"$chatName\" verlassen moechtest?';
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
  String get initialMessageLabel => 'Anfangsnachricht';

  @override
  String get setFirstMessage => 'Anfangsnachricht festlegen';

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
  String get legalDocuments => 'Rechtliches';

  @override
  String get contact => 'Kontakt';

  @override
  String get sourceCode => 'Quellcode';

  @override
  String get byContinuingYouAgree => 'Durch Fortfahren stimmst du unseren zu';

  @override
  String get andText => 'und';

  @override
  String lastUpdated(String date) {
    return 'Letzte Aktualisierung: $date';
  }

  @override
  String shareLinkTitle(String chatName) {
    return 'Jeder mit diesem Link kann $chatName beitreten';
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
  String get tutorialTemplateSaturday => 'Samstagsplaene';

  @override
  String get tutorialTemplateSaturdayDesc =>
      'Was ist die beste Art, einen freien Samstag zu verbringen?';

  @override
  String get tutorialTemplateCustom => 'Eigenes Thema';

  @override
  String get tutorialTemplateCustomDesc => 'Eigene Frage eingeben';

  @override
  String get tutorialCustomQuestionHint => 'Frage eingeben...';

  @override
  String tutorialRound1ResultTemplate(String winner) {
    return '\'$winner\' hat Runde 1 gewonnen!';
  }

  @override
  String get tutorialAppBarTitle => 'OneMind-Tutorial';

  @override
  String get tutorialWelcomeTitle => 'Willkommen bei OneMind!';

  @override
  String get tutorialWelcomeDescription => 'Die Ideenwettbewerb-Plattform';

  @override
  String get tutorialWelcomeSubtitle => 'Schau, wie es funktioniert';

  @override
  String get tutorialTheQuestion => 'Die Frage:';

  @override
  String get tutorialQuestion =>
      'Was ist die beste Art, einen freien Samstag zu verbringen?';

  @override
  String get tutorialStartButton => 'Tutorial Starten';

  @override
  String get tutorialSkipButton => 'Tutorial ueberspringen';

  @override
  String get tutorialConsensusReached => 'Konvergenz Erreicht!';

  @override
  String get tutorialWonTwoRounds =>
      '\"null\" hat 2 Runden hintereinander gewonnen und wird dauerhaft zum Chat hinzugefügt. Das nennen wir Konvergenz — die Gruppe hat sich auf eine Idee geeinigt.';

  @override
  String get tutorialConvergenceExplain => 'Tippe darauf, um fortzufahren.';

  @override
  String get tutorialCycleHistoryExplainTitle => 'Rundengewinner';

  @override
  String get tutorialCycleHistoryExplainDesc =>
      'Siehst du, wie dieselbe Idee Runde 2 und Runde 3 gewonnen hat? Das nennt man Konvergenz — die Gruppe hat sich auf eine Idee geeinigt.';

  @override
  String get tutorialCycleHistoryBackDesc => 'Drücke [back], um fortzufahren.';

  @override
  String get tutorialPressBackToContinue => 'Drücke [back], um fortzufahren.';

  @override
  String get tutorialR1LeaderboardTapDesc => 'Tap [leaderboard] to continue.';

  @override
  String get tutorialR1LeaderboardUpdatedDesc =>
      'The leaderboard has been updated.';

  @override
  String get tutorialR1LeaderboardDoneDesc => 'Press the X to continue.';

  @override
  String get tutorialR1ResultWinnerTitle => 'Round 1 Winner';

  @override
  String get tutorialR1ResultWinnerDesc =>
      'Everyone has rated. \"Movie Night\" won! It is now the new placeholder.';

  @override
  String get tutorialR1ResultTapTitle => 'Round Winners';

  @override
  String get tutorialR1ResultTapDesc => 'Tap it to continue.';

  @override
  String get tutorialR1CycleExplainTitle => 'Round Winners';

  @override
  String get tutorialR1CycleExplainDesc =>
      'This shows all completed round winners. Only 1 round has been completed so far.';

  @override
  String get tutorialR2CycleExplainDesc => 'Now there are 2 completed rounds.';

  @override
  String get tutorialR2ResultsExplainDesc =>
      '\"Movie Night\" lost this round, so it was replaced by the new winner — your idea.';

  @override
  String get tutorialR1CycleTapDesc =>
      'Tap it to view the full rating results.';

  @override
  String get tutorialR2CycleTapDesc =>
      'Tap the Round 2 winner to view the full rating results.';

  @override
  String get tutorialCarriedWinnerTitle => 'Vorheriger Gewinner';

  @override
  String get tutorialCarriedWinnerDesc =>
      '\"Movie Night\" ist der Gewinner der vorherigen Runde. Wenn er auch diese Runde gewinnt, wird er dauerhaft im Chat platziert.';

  @override
  String get tutorialProcessContinuesTitle => 'Der Prozess geht weiter';

  @override
  String get tutorialProcessContinuesDesc =>
      'Jetzt arbeitet die Gruppe auf ihre nächste Konvergenz hin.';

  @override
  String get tutorialAddedToChat =>
      'Du wurdest auch automatisch zum Offiziellen OneMind Chat hinzugefuegt, in dem alle gemeinsam Themen diskutieren.';

  @override
  String get tutorialFinishButton => 'Tutorial Beenden';

  @override
  String get tutorialRound1Result => '\'Beach Day\' hat Runde 1 gewonnen!';

  @override
  String get tutorialProposingHint =>
      'Reiche deine Idee ein — sie tritt gegen die aller anderen an.';

  @override
  String tutorialTimeRemaining(String time) {
    return 'Du hast noch $time.';
  }

  @override
  String get tutorialProposingHintWithWinner =>
      'Reiche eine neue Idee ein, um gegen den Gewinner der letzten Runde anzutreten.';

  @override
  String get tutorialRatingHint =>
      'Bewerte jetzt die Ideen aller. Die am besten bewertete Idee gewinnt die Runde.';

  @override
  String get tutorialRatingPhaseExplanation =>
      'Alle haben eingereicht. Bewerte jetzt ihre Ideen, um einen Gewinner zu wählen, bevor die Zeit abläuft!';

  @override
  String get tutorialRatingPhaseTitle => 'Bewertungsphase';

  @override
  String get tutorialRatingPhaseHint =>
      'Nachdem alle ihre Ideen eingereicht haben, beginnt die Bewertungsphase.';

  @override
  String get tutorialRatingButtonHint =>
      'Klicke auf Bewertung Starten, um die Ideen aller zu bewerten.';

  @override
  String get tutorialRatingButtonHintRich =>
      'Klicke auf [startRating], um die Ideen aller zu bewerten.';

  @override
  String get tutorialRatingIntroHint =>
      'Dies ist der Bewertungsbildschirm. Du bewertest nicht deine eigene Idee — nur die der anderen.';

  @override
  String get tutorialRatingRankHint =>
      'Je näher deine Bewertungen an denen der Gruppe sind, desto höher ist dein Rang.';

  @override
  String tutorialRatingTimeRemaining(String time) {
    return 'Du hast noch $time zum Bewerten.';
  }

  @override
  String get tutorialRatingBinaryHint =>
      'Die obere Idee erhält eine höhere Punktzahl. Tippe auf [swap], um deine bevorzugte Idee nach oben zu setzen, dann [check] zum Bestätigen.';

  @override
  String get tutorialRatingPositioningHint =>
      'Platziere jede Idee auf der Skala. Verwende [up] [down] zum Verschieben, dann [check] zum Bestätigen. Drücke [undo], um deine letzte Platzierung rückgängig zu machen.';

  @override
  String tutorialRound2Result(String proposition, String previousWinner) {
    return 'Deine Idee \"$proposition\" hat gewonnen! Sie ersetzt \"$previousWinner\" als die zu schlagende Idee. Gewinne die nächste Runde und es ist entschieden!';
  }

  @override
  String get tutorialRatingCarryForwardHint =>
      'Der Gewinner der letzten Runde wird übernommen und tritt erneut an.';

  @override
  String tutorialTapTabHint(String tabName) {
    return 'Tippe oben auf \"$tabName\" um fortzufahren.';
  }

  @override
  String tutorialResultTapTabHint(String tabName) {
    return 'Denkst du, du kannst es besser? Tippe auf \"$tabName\", um deine nächste Idee einzureichen.';
  }

  @override
  String get tutorialRound2PromptSimplified =>
      'Der Gewinner tritt in dieser Runde erneut an. Wenn er erneut gewinnt, ist das Konvergenz — die Antwort der Gruppe. Kannst du es besser?';

  @override
  String tutorialRound2PromptSimplifiedTemplate(String winner) {
    return '\'$winner\' tritt in dieser Runde erneut an. Wenn es erneut gewinnt, ist das Konvergenz — die Antwort der Gruppe. Kannst du es besser?';
  }

  @override
  String get tutorialRound3Prompt =>
      'Deine Idee hat den letzten Gewinner ersetzt. Noch ein Sieg bedeutet Konvergenz!';

  @override
  String tutorialRound3PromptTemplate(String winner, String previousWinner) {
    return '\'$winner\' hat \'$previousWinner\' ersetzt. Noch ein Sieg bedeutet Konvergenz!';
  }

  @override
  String get tutorialR2ResultsHint =>
      'Dies sind die kombinierten Bewertungen der Gruppe. Deine Idee hat gewonnen!';

  @override
  String get tutorialRound3ConvergenceHint =>
      'Wenn sie erneut gewinnt, konnte niemand sie schlagen — das ist Konvergenz.';

  @override
  String get tutorialHintSubmitIdea => 'Idee einreichen';

  @override
  String get tutorialHintRateIdeas => 'Ideen bewerten';

  @override
  String get tutorialHintRoundResults => 'Bewertungsergebnisse';

  @override
  String get tutorialHintR1Winner => 'New Placeholder';

  @override
  String tutorialHintR1WinnerDesc(String winner) {
    return '\"$winner\" won Round 1, so it replaced the previous placeholder. Now it is the new placeholder.';
  }

  @override
  String get tutorialHintConvergenceExplain => 'Konvergenz';

  @override
  String get tutorialHintConvergenceExplainDesc =>
      'Wenn der Platzhalter 2 Runden hintereinander gewinnt, wird er ein dauerhafter Teil des Chats. Das nennt man Konvergenz.';

  @override
  String get tutorialHintNewRound => 'Neue Runde';

  @override
  String get tutorialHintNewRoundDesc => 'Runde 2 beginnt jetzt.';

  @override
  String get tutorialHintRound2 => 'Runde 2';

  @override
  String get tutorialHintReplaceWinner => 'Kannst du es Besser?';

  @override
  String get tutorialHintReplaceWinnerDesc =>
      'Versuche, \"Movie Night\" zu ersetzen. Sende deine beste Idee!';

  @override
  String get tutorialHintNewRound3 => 'New Round';

  @override
  String get tutorialHintNewRound3Desc => 'Now time for Round 3.';

  @override
  String get tutorialHintR3Replace => 'Last Chance!';

  @override
  String get tutorialHintR3ReplaceDesc =>
      'Can you think of something better? Type your best idea and submit it! If you can\'t think of anything, tap [skip] to skip.';

  @override
  String get tutorialHintYouWon => 'Gewonnen!';

  @override
  String get tutorialHintCompare => 'Ideen vergleichen';

  @override
  String get tutorialHintPosition => 'Ideen positionieren';

  @override
  String get tutorialHintCarryForward => 'Übertrag';

  @override
  String get tutorialPropMovieNight => 'Filmabend';

  @override
  String get tutorialPropCookOff => 'Kochwettbewerb';

  @override
  String get tutorialPropBoardGames => 'Brettspiele';

  @override
  String get tutorialPropKaraoke => 'Karaoke';

  @override
  String get tutorialPropPotluckDinner => 'Gemeinsames Abendessen';

  @override
  String get tutorialPropDiyCraftNight => 'Bastelabend';

  @override
  String get tutorialPropTriviaNight => 'Quizabend';

  @override
  String get tutorialPropVideoGameTournament => 'Videospiel-Turnier';

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
  String get tutorialDuplicateProposition =>
      'Diese Idee existiert bereits in dieser Runde. Versuche etwas anderes!';

  @override
  String get tutorialShareTitle => 'Teile Deinen Chat';

  @override
  String get tutorialShareExplanation =>
      'Um andere einzuladen, deinem Chat beizutreten, tippe auf den Teilen-Button oben auf deinem Bildschirm.';

  @override
  String get tutorialShareTapDesc =>
      'Tippe auf den Teilen-Button, um fortzufahren.';

  @override
  String get tutorialShareCloseDesc => 'Drücke das X, um fortzufahren.';

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
  String get tutorialTransitionTitle => 'Chat-Tutorial abgeschlossen!';

  @override
  String get tutorialTransitionDesc =>
      'Werfen wir nun einen kurzen Blick auf den Startbildschirm, wo du alle deine Chats findest.';

  @override
  String get tutorialRateIdeas => 'Ideen Bewerten';

  @override
  String get tutorialResultsTitle => 'Bewertungsergebnisse';

  @override
  String get tutorialResultsWinnerHint =>
      'Alle haben fertig bewertet. \'null\' hat gewonnen!';

  @override
  String get tutorialResultsBackHint => 'Drücke [back], um fortzufahren.';

  @override
  String deleteConsensusTitle(int number) {
    return 'Konvergenz #$number loeschen?';
  }

  @override
  String get deleteConsensusMessage =>
      'Dies startet den aktuellen Zyklus mit einer neuen Runde neu.';

  @override
  String get deleteInitialMessageTitle => 'Anfangsnachricht Löschen?';

  @override
  String get deleteInitialMessageMessage =>
      'Dies startet den aktuellen Zyklus mit einer neuen Runde neu.';

  @override
  String get editInitialMessage => 'Anfangsnachricht Bearbeiten';

  @override
  String get consensusDeleted => 'Konvergenz geloescht';

  @override
  String get initialMessageUpdated => 'Anfangsnachricht aktualisiert';

  @override
  String get initialMessageDeleted => 'Anfangsnachricht gelöscht';

  @override
  String failedToDeleteConsensus(String error) {
    return 'Fehler beim Loeschen der Konvergenz: $error';
  }

  @override
  String failedToUpdateInitialMessage(String error) {
    return 'Fehler beim Aktualisieren der Anfangsnachricht: $error';
  }

  @override
  String failedToDeleteInitialMessage(String error) {
    return 'Fehler beim Löschen der Anfangsnachricht: $error';
  }

  @override
  String get deleteTaskResultTitle => 'Rechercheergebnisse Löschen?';

  @override
  String get deleteTaskResultMessage =>
      'Der Agent wird beim nächsten Herzschlag erneut recherchieren.';

  @override
  String get taskResultDeleted => 'Rechercheergebnisse gelöscht';

  @override
  String failedToDeleteTaskResult(String error) {
    return 'Fehler beim Löschen der Rechercheergebnisse: $error';
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
      'Zuschauen — unzureichende Credits';

  @override
  String get creditPausedTitle => 'Pausiert — Unzureichende Credits';

  @override
  String creditBalance(int balance) {
    return 'Guthaben: $balance Credits';
  }

  @override
  String creditsNeeded(int count) {
    return '$count Credits benötigt, um die Runde zu starten';
  }

  @override
  String get waitingForHostCredits =>
      'Warte darauf, dass der Gastgeber Credits hinzufügt';

  @override
  String get buyMoreCredits => 'Credits Kaufen';

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
  String get glossaryUserRoundTitle => 'Benutzer-Runde';

  @override
  String get glossaryUserRoundDef =>
      'Ein Teilnehmer, der eine Bewertungsrunde abschließt. Jede Benutzer-Runde kostet 1 Credit (0,01 \$).';

  @override
  String get glossaryConsensusTitle => 'Konvergenz';

  @override
  String get glossaryConsensusDef =>
      'Wenn niemand denselben Vorschlag über mehrere Runden hinweg schlagen kann, ist Konvergenz erreicht.';

  @override
  String get glossaryProposingTitle => 'Vorschläge';

  @override
  String get glossaryProposingDef =>
      'Die Phase, in der Teilnehmer ihre Ideen anonym einreichen, damit die Gruppe sie berücksichtigt.';

  @override
  String get glossaryRatingTitle => 'Bewertung';

  @override
  String get glossaryRatingDef =>
      'Die Phase, in der Teilnehmer alle Vorschläge auf einem 0-100-Raster bewerten, um den Gewinner zu bestimmen.';

  @override
  String get glossaryCycleTitle => 'Zyklus';

  @override
  String get glossaryCycleDef =>
      'Eine Abfolge von Runden auf dem Weg zur Konvergenz. Ein neuer Zyklus beginnt, nachdem die Konvergenz erreicht wurde.';

  @override
  String get glossaryCreditBalanceTitle => 'Credit-Guthaben';

  @override
  String get glossaryCreditBalanceDef =>
      'Credits finanzieren Runden. 1 Credit = 1 Benutzer-Runde = 0,01 \$. Kostenlose Credits werden monatlich erneuert.';

  @override
  String get enterTaskResult => 'Enter task result...';

  @override
  String get submitResult => 'Submit Result';

  @override
  String get taskResultSubmitted => 'Task result submitted';

  @override
  String get homeTourPendingRequestTitle => 'Ausstehende Anfragen';

  @override
  String get homeTourPendingRequestDesc =>
      'Wenn du eine Beitrittsanfrage stellst, prueft der Gastgeber deine Anfrage. Du siehst sie hier mit einem \'Ausstehend\'-Badge, bis sie genehmigt wird.';

  @override
  String get homeTourYourChatsTitle => 'Deine Chats';

  @override
  String get homeTourYourChatsDesc =>
      'Deine aktiven Chats erscheinen hier. Jede Karte zeigt die aktuelle Phase, Teilnehmerzahl und Sprachen.';

  @override
  String get homeTourCreateFabTitle => 'Chat Erstellen';

  @override
  String get homeTourCreateFabDesc =>
      'Tippe auf +, um deinen eigenen Chat zu erstellen. Waehle das Thema, lade Freunde ein und findet gemeinsam einen Konsens.';

  @override
  String get homeTourDemoTitle => 'Demo Ausprobieren';

  @override
  String get homeTourDemoDesc =>
      'Möchtest du sehen, wie die Abstimmung funktioniert? Tippe hier, um eine schnelle interaktive Demo zu starten.';

  @override
  String get homeTourHowItWorksTitle => 'So Funktioniert\'s';

  @override
  String get homeTourHowItWorksDesc =>
      'Brauchst du eine Auffrischung? Tippe hier, um das Tutorial jederzeit zu wiederholen.';

  @override
  String get homeTourLegalDocsTitle => 'Rechtliche Dokumente';

  @override
  String get homeTourLegalDocsDesc =>
      'Sieh dir die Datenschutzrichtlinie und die Nutzungsbedingungen hier an.';

  @override
  String get homeTourTutorialButtonTitle => 'So Funktioniert Es';

  @override
  String get homeTourTutorialButtonDesc =>
      'Spiele das Tutorial erneut ab, um zu lernen, wie OneMind funktioniert.';

  @override
  String get homeTourMenuTitle => 'Menü';

  @override
  String get homeTourMenuDesc =>
      'Kontaktiere uns, sieh dir den Quellcode an oder lies die rechtlichen Dokumente.';

  @override
  String get searchOrJoinWithCode =>
      'Chats suchen oder Einladungscode eingeben...';

  @override
  String get searchYourChatsOrJoinWithCode =>
      'Deine Chats suchen oder Einladungscode eingeben...';

  @override
  String get noMatchingChats => 'Keine passenden Chats';

  @override
  String inviteCodeDetected(String code) {
    return 'Mit Einladungscode beitreten: $code';
  }

  @override
  String get wizardVisibilityTitle => 'Wer kann beitreten?';

  @override
  String get wizardVisibilitySubtitle =>
      'Waehle, wer deinen Chat finden und beitreten kann';

  @override
  String get wizardVisibilityPublicTitle => 'Oeffentlich';

  @override
  String get wizardVisibilityPublicDesc =>
      'Jeder kann diesen Chat entdecken und beitreten';

  @override
  String get wizardVisibilityPrivateTitle => 'Privat';

  @override
  String get wizardVisibilityPrivateDesc =>
      'Nur Personen mit dem Einladungscode koennen beitreten';

  @override
  String get wizardVisibilityPersonalCodeTitle => 'Persoenliche Codes';

  @override
  String get wizardVisibilityPersonalCodeDesc =>
      'Erstelle einzigartige Codes fuer jede Person. Jeder Code funktioniert einmal.';

  @override
  String get personalCodes => 'Persoenliche Codes';

  @override
  String get generateNewCode => 'Neuen Code Erstellen';

  @override
  String get codeStatusActive => 'Aktiv';

  @override
  String get codeStatusReserved => 'Reserviert';

  @override
  String get codeStatusUsed => 'Benutzt';

  @override
  String get codeStatusRevoked => 'Widerrufen';

  @override
  String get revokeCode => 'Widerrufen';

  @override
  String get revokeCodeConfirm =>
      'Diesen Code widerrufen? Er kann nicht mehr zum Beitreten verwendet werden.';

  @override
  String get codeAlreadyUsed => 'Dieser Code wurde bereits verwendet.';

  @override
  String get noCodesYet =>
      'Noch keine Codes. Erstelle einen, um jemanden einzuladen.';

  @override
  String get codeGenerated => 'Code erstellt!';

  @override
  String get codeRevoked => 'Code widerrufen';

  @override
  String get homeTourSearchBarTitle => 'Deine Chats Suchen';

  @override
  String get homeTourSearchBarDesc =>
      'Filtere deine Chats nach Name, oder gib einen 6-stelligen Einladungscode ein, um einem privaten Chat beizutreten.';

  @override
  String get homeTourExploreButtonTitle => 'Oeffentliche Chats Entdecken';

  @override
  String get homeTourExploreButtonDesc =>
      'Tippe hier, um oeffentliche Chats anderer Benutzer zu entdecken und ihnen beizutreten.';

  @override
  String get homeTourLanguageSelectorTitle => 'Sprache Aendern';

  @override
  String get homeTourLanguageSelectorDesc =>
      'Tippe hier, um die App-Sprache zu aendern. OneMind ist auf Englisch, Spanisch, Portugiesisch, Franzoesisch und Deutsch verfuegbar.';

  @override
  String get homeTourSkip => 'Tour ueberspringen';

  @override
  String get homeTourNext => 'Weiter';

  @override
  String get homeTourFinish => 'Verstanden!';

  @override
  String homeTourStepOf(int current, int total) {
    return 'Schritt $current von $total';
  }

  @override
  String get wizardTranslationsTitle => 'Sprachen';

  @override
  String get wizardTranslationsSubtitle =>
      'Waehle welche Sprachen dieser Chat unterstuetzt';

  @override
  String get singleLanguageToggle => 'Einzelsprache';

  @override
  String get singleLanguageDesc => 'Alle nehmen in einer Sprache teil';

  @override
  String get multiLanguageDesc =>
      'Vorschlaege werden automatisch zwischen den Sprachen uebersetzt';

  @override
  String get chatLanguageLabel => 'Chat-Sprache';

  @override
  String get selectLanguages => 'Unterstuetzte Sprachen:';

  @override
  String get autoTranslateHint =>
      'Vorschlaege werden automatisch zwischen allen ausgewaehlten Sprachen uebersetzt';

  @override
  String get translationsSection => 'Sprachen';

  @override
  String get translationLanguagesLabel => 'Sprachen';

  @override
  String get autoTranslateLabel => 'Automatische Uebersetzung';

  @override
  String get chatAutoTranslated => 'Automatisch uebersetzt';

  @override
  String get scanQrCode => 'QR-Code Scannen';

  @override
  String get pointCameraAtQrCode =>
      'Richte deine Kamera auf einen Einladungs-QR-Code';

  @override
  String get invalidQrCode =>
      'Dieser QR-Code enthält keinen gültigen Einladungslink';

  @override
  String get cameraPermissionDenied =>
      'Kameraberechtigung ist erforderlich, um QR-Codes zu scannen';

  @override
  String get actionPickerTitle => 'Was möchtest du tun?';

  @override
  String get actionPickerCreateTitle => 'Chat Erstellen';

  @override
  String get actionPickerCreateDesc =>
      'Starte ein neues Gespräch zu jedem Thema';

  @override
  String get actionPickerJoinTitle => 'Chat Beitreten';

  @override
  String get actionPickerJoinDesc =>
      'Gib einen Einladungscode ein oder scanne einen QR-Code';

  @override
  String get actionPickerDiscoverTitle => 'Chats Entdecken';

  @override
  String get actionPickerDiscoverDesc =>
      'Durchsuche öffentliche Chats und nimm an der Unterhaltung teil';

  @override
  String get joinMethodTitle => 'Wie möchtest du beitreten?';

  @override
  String get joinMethodCodeTitle => 'Code Eingeben';

  @override
  String get joinMethodCodeDesc => 'Gib einen 6-stelligen Einladungscode ein';

  @override
  String get joinMethodScanTitle => 'QR-Code Scannen';

  @override
  String get joinMethodScanDesc =>
      'Verwende deine Kamera, um einen Einladungs-QR-Code zu scannen';

  @override
  String get wizardScheduleTitle => 'Einen Zeitplan festlegen?';

  @override
  String get wizardScheduleAlwaysTitle => 'Immer Aktiv';

  @override
  String get wizardScheduleAlwaysDesc =>
      'Der Chat läuft rund um die Uhr, ohne Zeitbeschränkungen';

  @override
  String get wizardScheduleOnceTitle => 'Startet zu einem bestimmten Zeitpunkt';

  @override
  String get wizardScheduleOnceDesc =>
      'Der Chat beginnt zu einem Datum und einer Uhrzeit deiner Wahl';

  @override
  String get wizardScheduleRecurringTitle => 'Wöchentlicher Zeitplan';

  @override
  String get wizardScheduleRecurringDesc =>
      'Der Chat ist zu festgelegten Zeitfenstern jede Woche aktiv';

  @override
  String get scheduleEndTimeLabel => 'Enddatum und -uhrzeit (optional)';

  @override
  String get scheduleEndTimeHint =>
      'Leer lassen, um den Chat nach dem Start unbegrenzt aktiv zu halten';

  @override
  String get scheduleSetEndTime => 'Endzeit festlegen';

  @override
  String get scheduleClearEndTime => 'Endzeit entfernen';

  @override
  String welcomeName(String name) {
    return 'Willkommen, $name';
  }

  @override
  String get editName => 'Name bearbeiten';

  @override
  String get primaryLanguage => 'Hauptsprache';

  @override
  String get iAlsoSpeak => 'Ich spreche auch';

  @override
  String get spokenLanguages => 'Gesprochene Sprachen';

  @override
  String get homeTourWelcomeNameTitle => 'Dein Anzeigename';

  @override
  String get homeTourWelcomeNameDesc =>
      'Das ist dein Anzeigename. Tippe auf das Stift-Symbol, um ihn jederzeit zu aendern!';

  @override
  String get chatTourIntroTitle => 'Willkommen';

  @override
  String get chatTourIntroDesc =>
      'Dies ist ein OneMind-Chat. Du wirst sehen, wie Ideen konkurrieren, bis die Gruppe eine Entscheidung trifft. Lass uns durchgehen, wie es funktioniert.';

  @override
  String get chatTourTitleTitle => 'Chat-Name';

  @override
  String get chatTourTitleDesc =>
      'Das ist der Chat-Name. Jeder Chat hat ein Thema, das alle gemeinsam diskutieren.';

  @override
  String get chatTourMessageTitle => 'Diskussionsfrage';

  @override
  String get chatTourMessageDesc =>
      'Das ist die Frage, die diskutiert wird. Alle reichen Ideen als Antwort ein.';

  @override
  String get currentLeader => 'Aktueller Anführer';

  @override
  String get chatTourPlaceholderTitle => 'Platzhalter';

  @override
  String get chatTourPlaceholderDesc =>
      'Hier wird die gewählte Idee platziert.';

  @override
  String get chatTourPlaceholderDesc2 =>
      'The chat hasn\'t started yet, so it\'s empty for now.';

  @override
  String get chatTourRoundTitle => 'Rundennummer';

  @override
  String get chatTourRoundDesc =>
      'Dies zeigt, in welcher Runde sich der Chat befindet. Die Gruppe durchläuft mehrere Runden, um die Gewinneridee zu wählen.';

  @override
  String get chatTourPhasesTitle => 'Rundenphasen';

  @override
  String get chatTourPhasesDesc =>
      'Jede Runde hat zwei Phasen: [proposing] und [rating].';

  @override
  String get chatTourPhasesDesc2 =>
      'Each round starts in the [proposing] phase.';

  @override
  String get chatTourProgressTitle => 'Teilnahme';

  @override
  String get chatTourProgressDesc =>
      'Dies ist die Teilnahmeleiste. Sie zeigt den Fortschritt der Gruppe in der aktuellen Phase.';

  @override
  String get chatTourProgressDesc2 =>
      'Once it reaches 100%, the chat moves on to the next phase.';

  @override
  String get chatTourTimerTitle => 'Phasen-Timer';

  @override
  String get chatTourTimerDesc =>
      'Jede Phase hat ein Zeitlimit — wenn es abläuft, geht der Chat weiter.';

  @override
  String get chatTourSubmitTitle => 'Ideen Einreichen';

  @override
  String get chatTourSubmitDesc =>
      'Gib hier deine beste Idee ein, um den Platzhalter oben zu ersetzen.';

  @override
  String get chatTourSubmitDesc2 =>
      'Alex, Sam, and Jordan have already submitted their ideas for this [proposing] phase.';

  @override
  String get chatTourSubmitDesc3 => 'The better the idea, the higher the rank.';

  @override
  String get tutorialR1ProposingHint =>
      'Propose your idea! Type it below and submit.';

  @override
  String get chatTourParticipantsTitle => 'Teilnehmer';

  @override
  String get chatTourParticipantsDesc =>
      'Lerne die Tutorial-Teilnehmer kennen: Alice, Bob und Carol. Tippe auf [people], um zu sehen, wer im Chat ist.';

  @override
  String get chatTourParticipantsDoneTitle => 'Teilnahmestatus';

  @override
  String get chatTourParticipantsDoneDesc =>
      '\"Fertig\" bedeutet, dass der Teilnehmer zur aktuellen Phase beigetragen hat. Sobald alle fertig sind, geht der Chat weiter.';

  @override
  String get chatTourLeaderboardParticipants => 'Teilnehmer';

  @override
  String get chatTourLeaderboardParticipantsDesc =>
      'Das sind die Teilnehmer im Chat. Du, Alex, Sam und Jordan.';

  @override
  String get chatTourLeaderboardRankings => 'Rangliste';

  @override
  String get chatTourLeaderboardRankingsDesc =>
      'Das sind die Benutzer-Rankings. Alle werden basierend auf ihrer Leistung in den [proposing]- und [rating]-Phasen über alle Runden hinweg eingestuft.';

  @override
  String get chatTourLeaderboardRankingsDesc2 =>
      'No rounds have been completed yet, so everyone starts unranked.';

  @override
  String get chatTourClosePanel => 'Rangliste Schließen';

  @override
  String get chatTourClosePanelDesc =>
      'Tippe auf das X, um die Rangliste zu schließen.';

  @override
  String get chatTourShareTitle => 'Chat Teilen';

  @override
  String get chatTourShareDesc =>
      'Teile diesen Chat mit Freunden ueber einen Einladungslink oder QR-Code.';

  @override
  String get tutorialShareContinueHint =>
      'Tippe auf die Weiter-Schaltflaeche, um das Tutorial fortzusetzen.';

  @override
  String get myLanguage => 'Meine Sprache';

  @override
  String get notJoined => 'Nicht beigetreten';

  @override
  String get noChatsMatchFilters => 'Keine Chats entsprechen deinen Filtern';

  @override
  String get tryAdjustingFilters =>
      'Versuche, deine Sprach- oder Beitrittsfilter anzupassen.';

  @override
  String get tryDifferentSearch => 'Versuche einen anderen Suchbegriff.';

  @override
  String get viewOtherPropositions => 'Vorschläge ansehen';

  @override
  String get otherPropositionsTitle => 'Vorschläge';

  @override
  String get noOtherPropositionsYet => 'Noch keine Vorschläge';

  @override
  String get donate => 'Spenden';

  @override
  String get supportOneMindTitle => 'OneMind unterstützen';

  @override
  String get supportOneMindBody =>
      'OneMind ist kostenlos und finanziert sich durch Spenden. Wenn diese Gruppe euch gerade geholfen hat, gemeinsam eine echte Entscheidung zu treffen — würdet ihr einen kleinen Beitrag leisten, damit es weitergeht?';

  @override
  String get maybeLater => 'Vielleicht später';
}
