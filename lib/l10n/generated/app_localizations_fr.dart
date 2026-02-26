// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'OneMind';

  @override
  String get howItWorks => 'Comment ca marche';

  @override
  String get discover => 'Decouvrir';

  @override
  String get discoverPublicChats => 'Decouvrir les chats publics';

  @override
  String get discoverChats => 'Decouvrir les Chats';

  @override
  String get joinWithCode => 'Rejoindre avec un Code';

  @override
  String get joinAnExistingChatWithInviteCode =>
      'Rejoindre un chat existant avec un code d\'invitation';

  @override
  String get joinChat => 'Rejoindre le Chat';

  @override
  String get join => 'Rejoindre';

  @override
  String get joined => 'Rejoint';

  @override
  String get findChat => 'Trouver un Chat';

  @override
  String get requestToJoin => 'Demander a Rejoindre';

  @override
  String get createChat => 'Creer un Chat';

  @override
  String get createANewChat => 'Creer un nouveau chat';

  @override
  String get chatCreated => 'Chat Cree!';

  @override
  String get cancel => 'Annuler';

  @override
  String get continue_ => 'Continuer';

  @override
  String get retry => 'Reessayer';

  @override
  String get yes => 'Oui';

  @override
  String get no => 'Non';

  @override
  String get delete => 'Supprimer';

  @override
  String get leave => 'Quitter';

  @override
  String get kick => 'Expulser';

  @override
  String get pause => 'Pause';

  @override
  String get resume => 'Reprendre';

  @override
  String get remove => 'Retirer';

  @override
  String get clear => 'Effacer';

  @override
  String get done => 'Termine';

  @override
  String get save => 'Enregistrer';

  @override
  String get official => 'OFFICIEL';

  @override
  String get pending => 'EN ATTENTE';

  @override
  String get pendingRequests => 'Demandes en Attente';

  @override
  String get yourChats => 'Vos Chats';

  @override
  String get cancelRequest => 'Annuler la Demande';

  @override
  String cancelRequestQuestion(String chatName) {
    return 'Annuler votre demande pour rejoindre \"$chatName\"?';
  }

  @override
  String get yesCancel => 'Oui, Annuler';

  @override
  String get requestCancelled => 'Demande annulee';

  @override
  String get waitingForHostApproval =>
      'En attente de l\'approbation de l\'hote';

  @override
  String get hostApprovalRequired => 'L\'hote doit approuver chaque demande';

  @override
  String get noChatsYet => 'Aucun chat pour l\'instant';

  @override
  String get discoverPublicChatsJoinOrCreate =>
      'Recherchez des chats publics ci-dessus, ou appuyez sur + pour creer le votre.';

  @override
  String get discoverPublicChatsButton => 'Decouvrir les Chats Publics';

  @override
  String get noActiveChatsYet =>
      'Aucun chat actif pour l\'instant. Vos chats approuves apparaitront ici.';

  @override
  String get loadingChats => 'Chargement des chats';

  @override
  String get failedToLoadChats => 'Echec du chargement des chats';

  @override
  String get chatNotFound => 'Chat non trouve';

  @override
  String get failedToLookupChat => 'Echec de la recherche du chat';

  @override
  String failedToJoinChat(String error) {
    return 'Echec pour rejoindre le chat: $error';
  }

  @override
  String get enterInviteCode => 'Entrez le code d\'invitation a 6 caracteres:';

  @override
  String get pleaseEnterSixCharCode => 'Veuillez entrer un code a 6 caracteres';

  @override
  String get inviteCodeHint => 'ABC123';

  @override
  String hostedBy(String hostName) {
    return 'Organise par $hostName';
  }

  @override
  String get thisChatsRequiresInvite => 'Ce chat necessite une invitation';

  @override
  String get enterEmailForInvite =>
      'Entrez l\'email auquel votre invitation a ete envoyee:';

  @override
  String get yourEmailHint => 'votre@email.com';

  @override
  String get pleaseEnterEmailAddress => 'Veuillez entrer votre adresse email';

  @override
  String get pleaseEnterValidEmail => 'Veuillez entrer un email valide';

  @override
  String get noInviteFoundForEmail =>
      'Aucune invitation trouvee pour cet email';

  @override
  String get failedToValidateInvite =>
      'Echec de la validation de l\'invitation';

  @override
  String get pleaseVerifyEmailFirst => 'Veuillez d\'abord verifier votre email';

  @override
  String get verifyEmail => 'Verifier l\'Email';

  @override
  String emailVerified(String email) {
    return 'Email verifie: $email';
  }

  @override
  String get enterDisplayName => 'Entrez votre nom d\'affichage:';

  @override
  String get yourName => 'Votre Nom';

  @override
  String get yourNamePlaceholder => 'Votre Nom';

  @override
  String get displayName => 'Nom d\'affichage';

  @override
  String get enterYourName => 'Entrez votre nom';

  @override
  String get pleaseEnterYourName => 'Veuillez entrer votre nom';

  @override
  String get yourDisplayName => 'Votre nom d\'affichage';

  @override
  String get yourNameVisibleToAll =>
      'Votre nom sera visible par tous les participants';

  @override
  String get usingSavedName => 'Utilisation de votre nom enregistre';

  @override
  String get joinRequestSent =>
      'Demande envoyee. En attente de l\'approbation de l\'hote.';

  @override
  String get searchPublicChats => 'Rechercher des chats publics...';

  @override
  String noChatsFoundFor(String query) {
    return 'Aucun chat trouve pour \"$query\"';
  }

  @override
  String get noPublicChatsAvailable => 'Aucun chat public disponible';

  @override
  String get beFirstToCreate => 'Soyez le premier a en creer un!';

  @override
  String failedToLoadPublicChats(String error) {
    return 'Echec du chargement des chats publics: $error';
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
  String get enterYourNameTitle => 'Entrez Votre Nom';

  @override
  String get anonymous => 'Anonyme';

  @override
  String get timerWarning => 'Avertissement du Minuteur';

  @override
  String timerWarningMessage(int minutes) {
    return 'Vos minuteurs de phase sont plus longs que la fenetre de $minutes minutes programmee.\n\nLes phases peuvent s\'etendre au-dela du temps programme ou se mettre en pause a la fermeture de la fenetre.\n\nEnvisagez d\'utiliser des minuteurs plus courts (5 min ou 30 min) pour les sessions programmees.';
  }

  @override
  String get adjustSettings => 'Ajuster les Parametres';

  @override
  String get continueAnyway => 'Continuer Quand Meme';

  @override
  String get chatNowPublic => 'Votre chat est maintenant public!';

  @override
  String anyoneCanJoinFrom(String chatName) {
    return 'N\'importe qui peut trouver et rejoindre \"$chatName\" depuis la page Decouvrir.';
  }

  @override
  String invitesSent(int count) {
    return '$count invitation envoyee!';
  }

  @override
  String invitesSentPlural(int count) {
    return '$count invitations envoyees!';
  }

  @override
  String get noInvitesSent => 'Aucune invitation envoyee';

  @override
  String get onlyInvitedUsersCanJoin =>
      'Seuls les utilisateurs invites peuvent rejoindre ce chat.';

  @override
  String get shareCodeWithParticipants =>
      'Partagez ce code avec les participants:';

  @override
  String get inviteCodeCopied => 'Code d\'invitation copie';

  @override
  String get tapToCopy => 'Appuyez pour copier';

  @override
  String get showQrCode => 'Afficher le Code QR';

  @override
  String get addEmailForInviteOnly =>
      'Ajoutez au moins un email pour le mode invitation uniquement';

  @override
  String get emailAlreadyAdded => 'Email deja ajoute';

  @override
  String get settings => 'Parametres';

  @override
  String get language => 'Langue';

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
  String get rankPropositions => 'Classer les Propositions';

  @override
  String get placing => 'Classement: ';

  @override
  String rankedSuccessfully(int count) {
    return '$count propositions classees avec succes!';
  }

  @override
  String get failedToSaveRankings =>
      'Echec de l\'enregistrement des classements';

  @override
  String get chatPausedByHost => 'Chat mis en pause par l\'hote';

  @override
  String get ratingPhaseEnded => 'La phase d\'evaluation est terminee';

  @override
  String get goBack => 'Retour';

  @override
  String get ratePropositions => 'Evaluer les Propositions';

  @override
  String get submitRatings => 'Soumettre les Evaluations';

  @override
  String failedToSubmitRatings(String error) {
    return 'Echec de la soumission des evaluations: $error';
  }

  @override
  String get roundResults => 'Résultats du vote';

  @override
  String get noPropositionsToDisplay => 'Aucune proposition a afficher';

  @override
  String get noPreviousWinner => 'Pas encore d\'émergence';

  @override
  String roundWinner(int roundNumber) {
    return 'Gagnant du Tour $roundNumber';
  }

  @override
  String roundWinners(int roundNumber) {
    return 'Gagnants du Tour $roundNumber';
  }

  @override
  String get unknownProposition => 'Proposition inconnue';

  @override
  String score(String score) {
    return 'Score: $score';
  }

  @override
  String soleWinsProgress(int current, int required) {
    return 'Victoires uniques: $current/$required';
  }

  @override
  String get tiedWinNoConsensus =>
      'Egalite (ne compte pas pour la convergence)';

  @override
  String nWayTie(int count) {
    return '$count-WAY TIE';
  }

  @override
  String winnerIndexOfTotal(int current, int total) {
    return '$current of $total';
  }

  @override
  String get seeAllResults => 'Voir Tous les Resultats';

  @override
  String get viewAllRatings => 'Voir Toutes les Notes';

  @override
  String get startPhase => 'Demarrer la Phase';

  @override
  String get waiting => 'En Attente';

  @override
  String get waitingForHostToStart => 'En attente que l\'hote demarre...';

  @override
  String roundNumber(int roundNumber) {
    return 'Tour $roundNumber';
  }

  @override
  String get viewAllPropositions => 'Voir toutes les propositions';

  @override
  String get chatIsPaused => 'Chat en pause...';

  @override
  String get shareYourIdea => 'Partagez votre idee...';

  @override
  String get addAnotherIdea => 'Ajouter une autre idee...';

  @override
  String get submit => 'Soumettre';

  @override
  String get addProposition => 'Ajouter une Proposition';

  @override
  String get waitingForRatingPhase => 'En attente de la phase d\'evaluation...';

  @override
  String get endProposingStartRating =>
      'Terminer les Propositions et Demarrer l\'Evaluation';

  @override
  String get proposingComplete => 'Propositions Terminees';

  @override
  String get reviewPropositionsStartRating =>
      'Examinez les propositions et demarrez l\'evaluation quand vous etes pret.';

  @override
  String get waitingForHostToStartRating =>
      'En attente que l\'hote demarre la phase d\'evaluation.';

  @override
  String get startRatingPhase => 'Demarrer la Phase d\'Evaluation';

  @override
  String get ratingComplete => 'Evaluation Terminee';

  @override
  String get waitingForRatingPhaseEnd =>
      'En attente de la fin de la phase d\'evaluation.';

  @override
  String rateAllPropositions(int count) {
    return 'Evaluez les $count propositions';
  }

  @override
  String get continueRating => 'Continuer l\'Evaluation';

  @override
  String get startRating => 'Commencer l\'Evaluation';

  @override
  String get endRatingStartNextRound =>
      'Terminer l\'Evaluation et Demarrer le Prochain Tour';

  @override
  String get chatPaused => 'Chat en Pause';

  @override
  String get chatPausedByHostTitle => 'Chat Mis en Pause par l\'Hote';

  @override
  String get timerStoppedTapResume =>
      'Le minuteur est arrete. Appuyez sur Reprendre dans la barre pour continuer.';

  @override
  String get hostPausedPleaseWait =>
      'L\'hote a mis ce chat en pause. Veuillez attendre qu\'il reprenne.';

  @override
  String get previousWinner => 'Émergence';

  @override
  String get yourProposition => 'Votre Proposition';

  @override
  String get yourPropositions => 'Vos Propositions';

  @override
  String get rate => 'Evaluer';

  @override
  String get participants => 'Participants';

  @override
  String get chatInfo => 'Info du Chat';

  @override
  String get shareQrCode => 'Partager le Code QR';

  @override
  String get joinRequests => 'Demandes d\'Adhesion';

  @override
  String get resumeChat => 'Reprendre le Chat';

  @override
  String get pauseChat => 'Mettre en Pause le Chat';

  @override
  String get leaveChat => 'Quitter le Chat';

  @override
  String get deleteChat => 'Supprimer le Chat';

  @override
  String get host => 'Hote';

  @override
  String get deletePropositionQuestion => 'Supprimer la Proposition?';

  @override
  String get areYouSureDeleteProposition =>
      'Etes-vous sur de vouloir supprimer cette proposition?';

  @override
  String get deleteChatQuestion => 'Supprimer le Chat?';

  @override
  String get leaveChatQuestion => 'Quitter le Chat?';

  @override
  String get kickParticipantQuestion => 'Expulser le Participant?';

  @override
  String get pauseChatQuestion => 'Mettre en Pause le Chat?';

  @override
  String get removePaymentMethodQuestion => 'Retirer le Moyen de Paiement?';

  @override
  String get propositionDeleted => 'Proposition supprimee';

  @override
  String get chatDeleted => 'Chat supprime';

  @override
  String get youHaveLeftChat => 'Vous avez quitte le chat';

  @override
  String get youHaveBeenRemoved => 'Vous avez ete retire de ce chat';

  @override
  String get chatHasBeenDeleted => 'Ce chat a ete supprime';

  @override
  String participantRemoved(String name) {
    return '$name a ete retire';
  }

  @override
  String get chatPausedSuccess => 'Chat mis en pause';

  @override
  String get requestApproved => 'Demande approuvee';

  @override
  String get requestDenied => 'Demande refusee';

  @override
  String failedToSubmit(String error) {
    return 'Echec de la soumission: $error';
  }

  @override
  String get duplicateProposition =>
      'Cette proposition existe deja dans ce tour';

  @override
  String failedToStartPhase(String error) {
    return 'Echec du demarrage de la phase: $error';
  }

  @override
  String failedToAdvancePhase(String error) {
    return 'Echec de l\'avancement de la phase: $error';
  }

  @override
  String failedToCompleteRating(String error) {
    return 'Echec de la completion de l\'evaluation: $error';
  }

  @override
  String failedToDelete(String error) {
    return 'Echec de la suppression: $error';
  }

  @override
  String failedToDeleteChat(String error) {
    return 'Echec de la suppression du chat: $error';
  }

  @override
  String failedToLeaveChat(String error) {
    return 'Echec pour quitter le chat: $error';
  }

  @override
  String failedToKickParticipant(String error) {
    return 'Echec de l\'expulsion du participant: $error';
  }

  @override
  String failedToPauseChat(String error) {
    return 'Echec de la mise en pause du chat: $error';
  }

  @override
  String error(String error) {
    return 'Erreur: $error';
  }

  @override
  String get noPendingRequests => 'Aucune demande en attente';

  @override
  String get newRequestsWillAppear => 'Les nouvelles demandes apparaitront ici';

  @override
  String participantsJoined(int count) {
    return '$count participants ont rejoint';
  }

  @override
  String waitingForMoreParticipants(int count) {
    return 'En attente de $count participant(s) supplementaire(s)';
  }

  @override
  String get noMembersYetShareHint =>
      'Pas encore d\'autres membres. Appuyez sur le bouton de partage ci-dessus pour inviter des personnes.';

  @override
  String get scheduled => 'Programme';

  @override
  String get chatOutsideSchedule => 'Chat en dehors de la fenetre programmee';

  @override
  String nextWindowStarts(String dateTime) {
    return 'Prochaine fenetre commence $dateTime';
  }

  @override
  String get scheduleWindows => 'Fenetres programmees:';

  @override
  String get scheduledToStart => 'Programme pour demarrer';

  @override
  String get chatWillAutoStart =>
      'Le chat demarrera automatiquement a l\'heure programmee.';

  @override
  String submittedCount(int submitted, int total) {
    return '$submitted/$total soumis';
  }

  @override
  String propositionCollected(int count) {
    return '$count proposition collectee';
  }

  @override
  String propositionsCollected(int count) {
    return '$count propositions collectees';
  }

  @override
  String get timeExpired => 'Temps expire';

  @override
  String get noDataAvailable => 'Aucune donnee disponible';

  @override
  String get tryAgain => 'Reessayer';

  @override
  String get requireApproval => 'Necessiter l\'approbation';

  @override
  String get requireAuthentication => 'Necessiter l\'authentification';

  @override
  String get showPreviousResults =>
      'Afficher les resultats complets des tours precedents';

  @override
  String get enableAdaptiveDuration => 'Activer la duree adaptative';

  @override
  String get enableOneMindAI => 'Activer OneMind AI';

  @override
  String get enableAutoAdvanceProposing => 'Activer pour les idees';

  @override
  String get enableAutoAdvanceRating => 'Activer pour les evaluations';

  @override
  String get hideWhenOutsideSchedule => 'Masquer en dehors du planning';

  @override
  String get chatVisibleButPaused =>
      'Chat visible mais en pause en dehors du planning';

  @override
  String get chatHiddenUntilNext =>
      'Chat masque jusqu\'a la prochaine fenetre programmee';

  @override
  String get timezone => 'Fuseau horaire';

  @override
  String get scheduleType => 'Type de Planning';

  @override
  String get oneTime => 'Unique';

  @override
  String get recurring => 'Recurrent';

  @override
  String get startDateTime => 'Date et Heure de Debut';

  @override
  String get scheduleWindowsLabel => 'Fenetres de Planning';

  @override
  String get addWindow => 'Ajouter une Fenetre';

  @override
  String get searchTimezone => 'Rechercher un fuseau horaire...';

  @override
  String get manual => 'Manuel';

  @override
  String get auto => 'Automatique';

  @override
  String get credits => 'Credits';

  @override
  String get refillAmountMustBeGreater =>
      'Le montant de recharge doit etre superieur au seuil';

  @override
  String get autoRefillSettingsUpdated =>
      'Parametres de recharge automatique mis a jour';

  @override
  String get autoRefillEnabled => 'Recharge automatique activee';

  @override
  String get autoRefillDisabled => 'Recharge automatique desactivee';

  @override
  String get saveSettings => 'Enregistrer les Parametres';

  @override
  String get removeCard => 'Retirer la Carte';

  @override
  String get purchaseWithStripe => 'Acheter avec Stripe';

  @override
  String get processing => 'Traitement...';

  @override
  String get pageNotFound => 'Page Non Trouvee';

  @override
  String get goHome => 'Aller a l\'Accueil';

  @override
  String get somethingWentWrong => 'Quelque chose s\'est mal passe';

  @override
  String get pageNotFoundMessage =>
      'La page que vous recherchez n\'existe pas.';

  @override
  String get demoTitle => 'Demo';

  @override
  String allPropositionsCount(int count) {
    return 'Toutes les Propositions ($count)';
  }

  @override
  String get hostCanModerateContent =>
      'En tant qu\'hote, vous pouvez moderer le contenu. L\'identite de l\'auteur est masquee.';

  @override
  String get yourPropositionLabel => '(Votre proposition)';

  @override
  String get previousWinnerLabel => '(Émergence)';

  @override
  String get cannotBeUndone => 'Cette action ne peut pas etre annulee.';

  @override
  String deleteChatConfirmation(String chatName) {
    return 'Etes-vous sur de vouloir supprimer \"$chatName\"?\n\nCela supprimera definitivement toutes les propositions, evaluations et l\'historique. Cette action ne peut pas etre annulee.';
  }

  @override
  String leaveChatConfirmation(String chatName) {
    return 'Etes-vous sur de vouloir quitter \"$chatName\"?\n\nVous ne verrez plus ce chat dans votre liste.';
  }

  @override
  String kickParticipantConfirmation(String participantName) {
    return 'Etes-vous sur de vouloir retirer \"$participantName\" de ce chat?\n\nIl ne pourra pas rejoindre a nouveau sans approbation.';
  }

  @override
  String get pauseChatConfirmation =>
      'Cela mettra en pause le minuteur de la phase actuelle. Les participants verront que le chat est en pause par l\'hote.';

  @override
  String get approveOrDenyRequests =>
      'Approuver ou refuser les demandes pour rejoindre ce chat.';

  @override
  String get signedIn => 'Connecte';

  @override
  String get guest => 'Invite';

  @override
  String get approve => 'Approuver';

  @override
  String get deny => 'Refuser';

  @override
  String get initialMessage => 'Message Initial';

  @override
  String consensusNumber(int number) {
    return 'Convergence #$number';
  }

  @override
  String get kickParticipant => 'Expulser le participant';

  @override
  String get propositions => 'Propositions';

  @override
  String get leaderboard => 'Classement';

  @override
  String get noLeaderboardData => 'Aucune donnee de classement disponible';

  @override
  String get skip => 'Passer';

  @override
  String get skipped => 'Passe';

  @override
  String skipsRemaining(int remaining) {
    return '$remaining passages restants';
  }

  @override
  String get createChatTitle => 'Creer un Chat';

  @override
  String get enterYourNameLabel => 'Entrez votre nom';

  @override
  String get nameVisibleToAll =>
      'Votre nom sera visible par tous les participants';

  @override
  String get basicInfo => 'Informations de Base';

  @override
  String get chatNameRequired => 'Nom du Chat *';

  @override
  String get chatNameHint => 'ex., Dejeuner d\'Equipe Vendredi';

  @override
  String get required => 'Requis';

  @override
  String get initialMessageRequired => 'Message Initial *';

  @override
  String get initialMessageOptional => 'Message Initial (Optionnel)';

  @override
  String get initialMessageHint => 'Le sujet ou la question initiale';

  @override
  String get initialMessageHelperText =>
      'Les participants sauront que vous avez ecrit ceci puisque vous avez cree le chat';

  @override
  String get descriptionOptional => 'Description (Optionnelle)';

  @override
  String get descriptionHint => 'Contexte supplementaire';

  @override
  String get visibility => 'Visibilite';

  @override
  String get whoCanJoin => 'Qui peut trouver et rejoindre ce chat?';

  @override
  String get accessPublic => 'Public';

  @override
  String get accessPublicDesc => 'N\'importe qui peut decouvrir et rejoindre';

  @override
  String get accessCode => 'Code d\'Invitation';

  @override
  String get accessCodeDesc => 'Partagez un code a 6 caracteres pour rejoindre';

  @override
  String get accessEmail => 'Email Uniquement';

  @override
  String get accessEmailDesc =>
      'Seules les adresses email invitees peuvent rejoindre';

  @override
  String get instantJoin => 'Les utilisateurs rejoignent instantanement';

  @override
  String get inviteByEmail => 'Inviter par Email';

  @override
  String get inviteEmailOnly =>
      'Seules les adresses email invitees peuvent rejoindre ce chat';

  @override
  String get emailAddress => 'Adresse email';

  @override
  String get emailHint => 'utilisateur@exemple.com';

  @override
  String get invalidEmail => 'Veuillez entrer un email valide';

  @override
  String get addEmailToSend =>
      'Ajoutez au moins un email pour envoyer des invitations';

  @override
  String get facilitationMode => 'Comment les Phases Fonctionnent';

  @override
  String get facilitationDesc =>
      'Choisissez entre controle manuel ou minuteurs automatiques pour les transitions de phase.';

  @override
  String get modeManual => 'Manuel';

  @override
  String get modeAuto => 'Auto';

  @override
  String get modeManualDesc =>
      'Vous controlez quand chaque phase commence et se termine. Pas de minuteurs.';

  @override
  String get modeAutoDesc =>
      'Les minuteurs s\'executent automatiquement. Vous pouvez toujours terminer les phases plus tot.';

  @override
  String get autoStartParticipants => 'Demarrer quand ce nombre rejoint';

  @override
  String get ratingStartMode => 'Mode de Demarrage d\'Evaluation';

  @override
  String get ratingStartModeDesc =>
      'Controle comment la phase d\'evaluation commence apres les propositions.';

  @override
  String get ratingAutoDesc =>
      'L\'evaluation commence immediatement apres les propositions ou quand le seuil est atteint.';

  @override
  String get ratingManualDesc =>
      'Apres les propositions, vous choisissez quand demarrer l\'evaluation (ex., le lendemain).';

  @override
  String phaseFlowExplanation(String duration, int threshold, int minimum) {
    return 'Chaque phase dure jusqu\'a $duration, mais se termine tot si $threshold personnes participent. Ne se terminera pas tant qu\'au moins $minimum idees n\'existent (le minuteur s\'etend si necessaire).';
  }

  @override
  String get enableSchedule => 'Activer le Planning';

  @override
  String get restrictChatRoom =>
      'Restreindre quand la salle de chat est ouverte';

  @override
  String get timers => 'Minuteurs';

  @override
  String get useSameDuration => 'Meme duree pour les deux phases';

  @override
  String get useSameDurationDesc =>
      'Utiliser la meme limite de temps pour les propositions et l\'evaluation';

  @override
  String get phaseDuration => 'Duree de Phase';

  @override
  String get proposing => 'Propositions';

  @override
  String get rating => 'Evaluation';

  @override
  String get preset5min => '5 min';

  @override
  String get preset30min => '30 min';

  @override
  String get preset1hour => '1 heure';

  @override
  String get preset1day => '1 jour';

  @override
  String get presetCustom => 'Personnalise';

  @override
  String get duration1min => '1 min';

  @override
  String get duration2min => '2 min';

  @override
  String get duration10min => '10 min';

  @override
  String get duration2hours => '2 heures';

  @override
  String get duration4hours => '4 heures';

  @override
  String get duration8hours => '8 heures';

  @override
  String get duration12hours => '12 heures';

  @override
  String get hours => 'Heures';

  @override
  String get minutes => 'Minutes';

  @override
  String get max24h => '(max 24h)';

  @override
  String get minimumToAdvance => 'Participation Requise';

  @override
  String get timeExtendsAutomatically =>
      'La phase ne se terminera pas tant que les exigences ne sont pas satisfaites';

  @override
  String get proposingMinimum => 'Idees necessaires';

  @override
  String proposingMinimumDesc(int count) {
    return 'La phase ne se terminera pas tant que $count idees ne sont pas soumises';
  }

  @override
  String get ratingMinimum => 'Evaluations necessaires';

  @override
  String ratingMinimumDesc(int count) {
    return 'La phase ne se terminera pas tant que chaque idee n\'a pas $count evaluations';
  }

  @override
  String get autoAdvanceAt => 'Terminer la Phase Tot';

  @override
  String get skipTimerEarly =>
      'La phase peut se terminer tot lorsque les seuils sont atteints';

  @override
  String whenPercentSubmit(int percent) {
    return 'Quand $percent% des participants soumettent';
  }

  @override
  String get minParticipantsSubmit => 'Idees necessaires';

  @override
  String get minAvgRaters => 'Evaluations necessaires';

  @override
  String proposingThresholdPreview(
    int threshold,
    int participants,
    int percent,
  ) {
    return 'La phase se termine tot quand $threshold sur $participants participants soumettent des idees ($percent%)';
  }

  @override
  String proposingThresholdPreviewSimple(int threshold) {
    return 'La phase se termine tot quand $threshold idees sont soumises';
  }

  @override
  String ratingThresholdPreview(int threshold) {
    return 'La phase se termine tot quand chaque idee a $threshold evaluations';
  }

  @override
  String get consensusSettings => 'Parametres de Convergence';

  @override
  String get confirmationRounds => 'Tours de confirmation';

  @override
  String get firstWinnerConsensus =>
      'Le premier gagnant atteint la convergence immediatement';

  @override
  String mustWinConsecutive(int count) {
    return 'La meme proposition doit gagner $count tours consecutifs';
  }

  @override
  String get showFullResults =>
      'Afficher les resultats complets des tours precedents';

  @override
  String get seeAllPropositions =>
      'Les utilisateurs voient toutes les propositions et evaluations';

  @override
  String get seeWinningOnly =>
      'Les utilisateurs ne voient que la proposition gagnante';

  @override
  String get propositionLimits => 'Limites de Propositions';

  @override
  String get propositionsPerUser => 'Propositions par utilisateur';

  @override
  String get onePropositionPerRound =>
      'Chaque utilisateur peut soumettre 1 proposition par tour';

  @override
  String nPropositionsPerRound(int count) {
    return 'Chaque utilisateur peut soumettre jusqu\'a $count propositions par tour';
  }

  @override
  String get adaptiveDuration => 'Duree Adaptative';

  @override
  String get adjustDurationDesc =>
      'Auto-ajuster la duree de phase selon la participation';

  @override
  String get durationAdjusts => 'La duree s\'ajuste selon la participation';

  @override
  String get fixedDurations => 'Durees de phase fixes';

  @override
  String get usesThresholds =>
      'Utilise les seuils d\'avance anticipee pour determiner la participation';

  @override
  String adjustmentPercent(int percent) {
    return 'Ajustement: $percent%';
  }

  @override
  String get minDuration => 'Duree minimum';

  @override
  String get maxDuration => 'Duree maximum';

  @override
  String get aiParticipant => 'Participant IA';

  @override
  String get enableAI => 'Activer OneMind AI';

  @override
  String get aiPropositionsPerRound => 'Propositions IA par tour';

  @override
  String get scheduleTypeLabel => 'Type de Planning';

  @override
  String get scheduleOneTime => 'Une fois';

  @override
  String get scheduleRecurring => 'Recurrent';

  @override
  String get hideOutsideSchedule => 'Masquer hors planning';

  @override
  String get visiblePaused => 'Chat visible mais en pause hors planning';

  @override
  String get hiddenUntilWindow =>
      'Chat masque jusqu\'a la prochaine fenetre planifiee';

  @override
  String get timezoneLabel => 'Fuseau Horaire';

  @override
  String get scheduleWindowsTitle => 'Fenetres de Planning';

  @override
  String get addWindowButton => 'Ajouter une Fenetre';

  @override
  String get scheduleWindowsDesc =>
      'Definissez quand le chat est actif. Supporte les fenetres nocturnes (ex., 23h a 1h le lendemain).';

  @override
  String windowNumber(int n) {
    return 'Fenetre $n';
  }

  @override
  String get removeWindow => 'Supprimer la fenetre';

  @override
  String get startDay => 'Jour de Debut';

  @override
  String get endDay => 'Jour de Fin';

  @override
  String get daySun => 'Dim';

  @override
  String get dayMon => 'Lun';

  @override
  String get dayTue => 'Mar';

  @override
  String get dayWed => 'Mer';

  @override
  String get dayThu => 'Jeu';

  @override
  String get dayFri => 'Ven';

  @override
  String get daySat => 'Sam';

  @override
  String get timerWarningTitle => 'Avertissement de Minuteur';

  @override
  String timerWarningContent(int minutes) {
    return 'Vos minuteurs de phase sont plus longs que la fenetre de $minutes minutes.\n\nLes phases peuvent s\'etendre au-dela du temps planifie, ou se mettre en pause a la fermeture de la fenetre.\n\nEnvisagez d\'utiliser des minuteurs plus courts (5 min ou 30 min) pour les sessions planifiees.';
  }

  @override
  String get adjustSettingsButton => 'Ajuster les Parametres';

  @override
  String get continueAnywayButton => 'Continuer Quand Meme';

  @override
  String get chatCreatedTitle => 'Chat Cree!';

  @override
  String get chatNowPublicTitle => 'Votre chat est maintenant public!';

  @override
  String anyoneCanJoinDiscover(String name) {
    return 'N\'importe qui peut trouver et rejoindre \"$name\" depuis la page Decouvrir.';
  }

  @override
  String invitesSentTitle(int count) {
    return '$count invitations envoyees!';
  }

  @override
  String get noInvitesSentTitle => 'Aucune invitation envoyee';

  @override
  String get inviteOnlyMessage =>
      'Seuls les utilisateurs invites peuvent rejoindre ce chat.';

  @override
  String get shareCodeInstruction => 'Partagez ce code avec les participants:';

  @override
  String get codeCopied => 'Code d\'invitation copie';

  @override
  String get joinScreenTitle => 'Rejoindre le Chat';

  @override
  String get noTokenOrCode => 'Aucun token ou code d\'invitation fourni';

  @override
  String get invalidExpiredInvite =>
      'Ce lien d\'invitation est invalide ou a expire';

  @override
  String get inviteOnlyError =>
      'Ce chat necessite une invitation par email. Veuillez utiliser le lien envoye a votre email.';

  @override
  String get invalidInviteTitle => 'Invitation Invalide';

  @override
  String get invalidInviteDefault => 'Ce lien d\'invitation n\'est pas valide.';

  @override
  String get invitedToJoin => 'Vous etes invite a rejoindre';

  @override
  String get enterNameToJoin => 'Entrez votre nom pour rejoindre:';

  @override
  String get nameVisibleNotice =>
      'Ce nom sera visible par les autres participants.';

  @override
  String get requiresApprovalNotice =>
      'Ce chat necessite l\'approbation de l\'hote pour rejoindre.';

  @override
  String get requestToJoinButton => 'Demander a Rejoindre';

  @override
  String get joinChatButton => 'Rejoindre le Chat';

  @override
  String get creditsTitle => 'Credits';

  @override
  String get yourBalance => 'Votre Solde';

  @override
  String get paidCredits => 'Credits Payes';

  @override
  String get freeThisMonth => 'Gratuits ce Mois';

  @override
  String get totalAvailable => 'Total Disponible';

  @override
  String get userRounds => 'tours-utilisateur';

  @override
  String freeTierResets(String date) {
    return 'Le niveau gratuit se reinitialise $date';
  }

  @override
  String get buyCredits => 'Acheter des Credits';

  @override
  String get pricingInfo => '1 credit = 1 tour-utilisateur = 0,01\$';

  @override
  String get total => 'Total';

  @override
  String get autoRefillTitle => 'Auto-Recharge';

  @override
  String get autoRefillDesc =>
      'Acheter des credits automatiquement quand le solde passe sous le seuil';

  @override
  String lastError(String error) {
    return 'Derniere erreur: $error';
  }

  @override
  String get autoRefillComingSoon =>
      'Configuration de l\'auto-recharge bientot disponible. Pour l\'instant, achetez des credits manuellement ci-dessus.';

  @override
  String get whenBelow => 'Quand en dessous de';

  @override
  String get refillTo => 'Recharger a';

  @override
  String get disableAutoRefillMessage =>
      'Cela desactivera l\'auto-recharge. Vous pouvez ajouter un nouveau moyen de paiement plus tard.';

  @override
  String get recentTransactions => 'Transactions Recentes';

  @override
  String get noTransactionHistory => 'Aucun historique de transactions';

  @override
  String get chatSettingsTitle => 'Parametres du Chat';

  @override
  String get accessVisibility => 'Acces et Visibilite';

  @override
  String get accessMethod => 'Methode d\'Acces';

  @override
  String get facilitation => 'Facilitation';

  @override
  String get startMode => 'Mode de Demarrage';

  @override
  String get autoStartThreshold => 'Seuil d\'Auto-Demarrage';

  @override
  String nParticipants(int n) {
    return '$n participants';
  }

  @override
  String get proposingDuration => 'Duree des Propositions';

  @override
  String get ratingDuration => 'Duree d\'Evaluation';

  @override
  String nSeconds(int n) {
    return '$n secondes';
  }

  @override
  String nMinutes(int n) {
    return '$n minutes';
  }

  @override
  String nHours(int n) {
    return '$n heures';
  }

  @override
  String nDays(int n) {
    return '$n jours';
  }

  @override
  String get minimumRequirements => 'Exigences Minimales';

  @override
  String nPropositions(int n) {
    return '$n propositions';
  }

  @override
  String nAvgRaters(double n) {
    return '$n evaluateurs en moyenne par proposition';
  }

  @override
  String get earlyAdvanceThresholds => 'Seuils d\'Avance Anticipee';

  @override
  String get proposingThreshold => 'Seuil de Propositions';

  @override
  String get ratingThreshold => 'Seuil d\'Evaluation';

  @override
  String nConsecutiveWins(int n) {
    return '$n victoires consecutives';
  }

  @override
  String get enabled => 'Active';

  @override
  String nPerRound(int n) {
    return '$n par tour';
  }

  @override
  String get scheduledStart => 'Demarrage Planifie';

  @override
  String get windows => 'Fenetres';

  @override
  String nConfigured(int n) {
    return '$n configurees';
  }

  @override
  String get visibleOutsideSchedule => 'Visible Hors Planning';

  @override
  String get chatSettings => 'Paramètres du Chat';

  @override
  String get chatName => 'Nom';

  @override
  String get chatDescription => 'Description';

  @override
  String get accessAndVisibility => 'Accès et Visibilité';

  @override
  String get autoMode => 'Automatique';

  @override
  String get avgRatersPerProposition => 'évaluateurs moyens par proposition';

  @override
  String get consensus => 'Convergence';

  @override
  String get aiPropositions => 'Propositions IA';

  @override
  String get perRound => 'par tour';

  @override
  String get schedule => 'Horaire';

  @override
  String get configured => 'configuré';

  @override
  String get publicAccess => 'Public';

  @override
  String get inviteCodeAccess => 'Code d\'Invitation';

  @override
  String get inviteOnlyAccess => 'Sur Invitation Uniquement';

  @override
  String get privacyPolicyTitle => 'Politique de Confidentialite';

  @override
  String get termsOfServiceTitle => 'Conditions d\'Utilisation';

  @override
  String get legalDocuments => 'Legal';

  @override
  String get byContinuingYouAgree => 'By continuing, you agree to our';

  @override
  String get andText => 'and';

  @override
  String lastUpdated(String date) {
    return 'Derniere mise a jour: $date';
  }

  @override
  String shareLinkTitle(String chatName) {
    return 'Partager le lien pour rejoindre $chatName';
  }

  @override
  String get shareButton => 'Partager';

  @override
  String get copyLinkButton => 'Copier le Lien';

  @override
  String get linkCopied => 'Lien copie dans le presse-papiers';

  @override
  String get enterCodeManually => 'Ou entrez le code manuellement:';

  @override
  String get shareNotSupported => 'Partage non disponible - lien copie';

  @override
  String get orScan => 'ou scanner';

  @override
  String get tutorialTemplateCommunity => 'Décision communautaire';

  @override
  String get tutorialTemplateCommunityDesc =>
      'Que devrait faire notre quartier ensemble ?';

  @override
  String get tutorialTemplateWorkplace => 'Culture d\'entreprise';

  @override
  String get tutorialTemplateWorkplaceDesc =>
      'Sur quoi notre équipe devrait-elle se concentrer ?';

  @override
  String get tutorialTemplateWorld => 'Enjeux mondiaux';

  @override
  String get tutorialTemplateWorldDesc =>
      'Quel problème mondial est le plus important ?';

  @override
  String get tutorialTemplateFamily => 'Famille';

  @override
  String get tutorialTemplateFamilyDesc =>
      'Où devrions-nous partir en vacances ?';

  @override
  String get tutorialTemplatePersonal => 'Décision personnelle';

  @override
  String get tutorialTemplatePersonalDesc =>
      'Que devrais-je faire après mes études ?';

  @override
  String get tutorialTemplateGovernment => 'Budget municipal';

  @override
  String get tutorialTemplateGovernmentDesc =>
      'Comment dépenser le budget municipal ?';

  @override
  String get tutorialTemplateCustom => 'Sujet personnalisé';

  @override
  String get tutorialTemplateCustomDesc => 'Entrez votre propre question';

  @override
  String get tutorialCustomQuestionHint => 'Tapez votre question...';

  @override
  String tutorialRound1ResultTemplate(String winner) {
    return '\'$winner\' a gagné le Tour 1 !';
  }

  @override
  String get tutorialAppBarTitle => 'Tutoriel OneMind';

  @override
  String get tutorialWelcomeTitle => 'Bienvenue sur OneMind !';

  @override
  String get tutorialWelcomeDescription =>
      'Rassemblez des personnes pour partager des idées anonymement, évaluer de manière indépendante et atteindre des résultats auxquels tout le monde peut faire confiance.';

  @override
  String get tutorialWelcomeSubtitle =>
      'Choisissez un sujet pour vous entraîner';

  @override
  String get tutorialTheQuestion => 'La question:';

  @override
  String get tutorialQuestion => 'Qu\'est-ce que nous valorisons?';

  @override
  String get tutorialStartButton => 'Commencer le Tutoriel';

  @override
  String get tutorialSkipButton => 'Passer le tutoriel';

  @override
  String get tutorialConsensusReached => 'Convergence Atteinte!';

  @override
  String tutorialWonTwoRounds(String proposition) {
    return '\"$proposition\" a gagne 2 tours d\'affilee.';
  }

  @override
  String get tutorialAddedToChat =>
      'Vous avez egalement ete automatiquement ajoute au chat Officiel OneMind, ou tout le monde discute de sujets ensemble.';

  @override
  String get tutorialFinishButton => 'Terminer le Tutoriel';

  @override
  String get tutorialRound1Result => '\'Succès\' a gagné le Tour 1 !';

  @override
  String get tutorialProposingHint =>
      'Soumettez votre idée — elle sera en compétition avec celles de tous les autres.';

  @override
  String tutorialTimeRemaining(String time) {
    return 'Il vous reste $time.';
  }

  @override
  String get tutorialProposingHintWithWinner =>
      'Soumettez une nouvelle idée pour concurrencer le gagnant du tour précédent.';

  @override
  String get tutorialRatingHint =>
      'Évaluez maintenant les idées de tous. L\'idée la mieux notée remporte le tour.';

  @override
  String get tutorialRatingPhaseExplanation =>
      'Tout le monde a soumis. Évaluez maintenant leurs idées pour choisir un gagnant !';

  @override
  String tutorialRatingTimeRemaining(String time) {
    return 'Il vous reste $time pour évaluer.';
  }

  @override
  String get tutorialRatingBinaryHint =>
      'L\'idée du haut obtient un score plus élevé. Appuyez sur [swap] pour mettre votre idée préférée en haut, puis [check] pour confirmer.';

  @override
  String get tutorialRatingPositioningHint =>
      'Placez chaque idée sur l\'échelle. Utilisez [up] [down] pour déplacer, puis [check] pour confirmer.';

  @override
  String tutorialRound2Result(String proposition, String previousWinner) {
    return 'Votre idée \"$proposition\" a gagné ! Elle remplace \"$previousWinner\" comme celle à battre. Gagnez le prochain tour et c\'est décidé !';
  }

  @override
  String get tutorialRatingCarryForwardHint =>
      'Le gagnant du tour précédent est reporté pour concourir à nouveau.';

  @override
  String tutorialTapTabHint(String tabName) {
    return 'Appuyez sur \"$tabName\" ci-dessus pour continuer.';
  }

  @override
  String tutorialResultTapTabHint(String tabName) {
    return 'Vous pensez pouvoir faire mieux ? Appuyez sur \"$tabName\" pour soumettre votre prochaine idée.';
  }

  @override
  String get tutorialRound2PromptSimplified =>
      'Le gagnant sera de nouveau en compétition ce tour. S\'il gagne encore, c\'est la convergence — la réponse du groupe. Pouvez-vous faire mieux ?';

  @override
  String tutorialRound2PromptSimplifiedTemplate(String winner) {
    return '\'$winner\' sera de nouveau en compétition ce tour. S\'il gagne encore, c\'est la convergence — la réponse du groupe. Pouvez-vous faire mieux ?';
  }

  @override
  String get tutorialRound3Prompt =>
      'Votre idée a remplacé le dernier gagnant. Encore une victoire et c\'est la convergence !';

  @override
  String tutorialRound3PromptTemplate(String winner, String previousWinner) {
    return '\'$winner\' a remplacé \'$previousWinner\'. Encore une victoire et c\'est la convergence !';
  }

  @override
  String get tutorialR2ResultsHint =>
      'Votre idée a gagné ! Appuyez sur la flèche retour pour continuer.';

  @override
  String get tutorialRound3ConvergenceHint =>
      'Si elle gagne encore, personne n\'a pu la battre — c\'est la convergence.';

  @override
  String get tutorialHintSubmitIdea => 'Soumettez votre idée';

  @override
  String get tutorialHintRateIdeas => 'Évaluer les idées';

  @override
  String get tutorialHintRoundResults => 'Résultats du vote';

  @override
  String get tutorialHintRound2 => 'Tour 2';

  @override
  String get tutorialHintYouWon => 'Vous avez gagné !';

  @override
  String get tutorialHintCompare => 'Comparer les idées';

  @override
  String get tutorialHintPosition => 'Positionner les idées';

  @override
  String get tutorialHintCarryForward => 'Report';

  @override
  String get tutorialPropSuccess => 'Succes';

  @override
  String get tutorialPropAdventure => 'Aventure';

  @override
  String get tutorialPropGrowth => 'Croissance';

  @override
  String get tutorialPropHarmony => 'Harmonie';

  @override
  String get tutorialPropInnovation => 'Innovation';

  @override
  String get tutorialPropFreedom => 'Liberte';

  @override
  String get tutorialPropSecurity => 'Securite';

  @override
  String get tutorialPropStability => 'Stabilite';

  @override
  String get tutorialPropTravelAbroad => 'Voyager a l\'etranger';

  @override
  String get tutorialPropStartABusiness => 'Creer une entreprise';

  @override
  String get tutorialPropGraduateSchool => 'Etudes superieures';

  @override
  String get tutorialPropGetAJobFirst => 'Trouver un emploi';

  @override
  String get tutorialPropTakeAGapYear => 'Annee sabbatique';

  @override
  String get tutorialPropFreelance => 'Freelance';

  @override
  String get tutorialPropMoveToANewCity => 'Demenager en ville';

  @override
  String get tutorialPropVolunteerProgram => 'Benevolat';

  @override
  String get tutorialPropBeachResort => 'Station balneaire';

  @override
  String get tutorialPropMountainCabin => 'Chalet de montagne';

  @override
  String get tutorialPropCityTrip => 'Escapade urbaine';

  @override
  String get tutorialPropRoadTrip => 'Road trip';

  @override
  String get tutorialPropCampingAdventure => 'Aventure camping';

  @override
  String get tutorialPropCruise => 'Croisiere';

  @override
  String get tutorialPropThemePark => 'Parc a themes';

  @override
  String get tutorialPropCulturalExchange => 'Echange culturel';

  @override
  String get tutorialPropBlockParty => 'Fete de quartier';

  @override
  String get tutorialPropCommunityGarden => 'Jardin communautaire';

  @override
  String get tutorialPropNeighborhoodWatch => 'Surveillance de quartier';

  @override
  String get tutorialPropToolLibrary => 'Outils en partage';

  @override
  String get tutorialPropMutualAidFund => 'Caisse d\'entraide';

  @override
  String get tutorialPropFreeLittleLibrary => 'Boite a livres';

  @override
  String get tutorialPropStreetMural => 'Fresque murale';

  @override
  String get tutorialPropSkillShareNight => 'Soiree partage';

  @override
  String get tutorialPropFlexibleHours => 'Horaires flexibles';

  @override
  String get tutorialPropMentalHealthSupport => 'Sante mentale';

  @override
  String get tutorialPropTeamBuilding => 'Esprit d\'equipe';

  @override
  String get tutorialPropSkillsTraining => 'Formation';

  @override
  String get tutorialPropOpenCommunication => 'Communication ouverte';

  @override
  String get tutorialPropFairCompensation => 'Remuneration juste';

  @override
  String get tutorialPropWorkLifeBalance => 'Equilibre pro/perso';

  @override
  String get tutorialPropInnovationTime => 'Temps d\'innovation';

  @override
  String get tutorialPropPublicTransportation => 'Transports publics';

  @override
  String get tutorialPropSchoolFunding => 'Budget scolaire';

  @override
  String get tutorialPropEmergencyServices => 'Services d\'urgence';

  @override
  String get tutorialPropRoadRepairs => 'Reparation des routes';

  @override
  String get tutorialPropPublicHealth => 'Sante publique';

  @override
  String get tutorialPropAffordableHousing => 'Logement abordable';

  @override
  String get tutorialPropSmallBusinessGrants => 'Aides aux PME';

  @override
  String get tutorialPropParksAndRecreation => 'Parcs & loisirs';

  @override
  String get tutorialPropClimateChange => 'Changement climatique';

  @override
  String get tutorialPropGlobalPoverty => 'Pauvrete mondiale';

  @override
  String get tutorialPropAiGovernance => 'Gouvernance de l\'IA';

  @override
  String get tutorialPropPandemicPreparedness => 'Preparation pandemique';

  @override
  String get tutorialPropNuclearDisarmament => 'Desarmement nucleaire';

  @override
  String get tutorialPropOceanConservation => 'Protection des oceans';

  @override
  String get tutorialPropDigitalRights => 'Droits numeriques';

  @override
  String get tutorialPropSpaceCooperation => 'Cooperation spatiale';

  @override
  String get tutorialDuplicateProposition =>
      'Cette idee existe deja dans ce tour. Essayez quelque chose de different!';

  @override
  String get tutorialShareTitle => 'Partagez Votre Chat';

  @override
  String get tutorialShareExplanation =>
      'Pour inviter d\'autres personnes a rejoindre votre chat, appuyez sur le bouton de partage en haut de votre ecran.';

  @override
  String get tutorialShareTryIt => 'Essayez maintenant!';

  @override
  String get tutorialShareButtonHint =>
      'Appuyez sur le bouton de partage en haut a droite ↗';

  @override
  String get tutorialSkipMenuItem => 'Passer le Tutoriel';

  @override
  String get tutorialSkipConfirmTitle => 'Passer le Tutoriel?';

  @override
  String get tutorialSkipConfirmMessage =>
      'Vous pouvez toujours acceder au tutoriel plus tard depuis l\'ecran d\'accueil.';

  @override
  String get tutorialSkipConfirmYes => 'Oui, Passer';

  @override
  String get tutorialSkipConfirmNo => 'Continuer le Tutoriel';

  @override
  String get tutorialShareTooltip => 'Partager le Chat';

  @override
  String get tutorialYourIdea => 'Votre idee';

  @override
  String get tutorialTransitionTitle => 'Tutoriel du chat terminé !';

  @override
  String get tutorialTransitionDesc =>
      'Jetons maintenant un coup d\'œil à l\'écran d\'accueil, où vous trouverez tous vos chats.';

  @override
  String get tutorialRateIdeas => 'Evaluer les Idees';

  @override
  String tutorialResultsBackHint(String winner) {
    return '\'$winner\' a gagné ! Appuyez sur la flèche retour pour continuer.';
  }

  @override
  String deleteConsensusTitle(int number) {
    return 'Supprimer la Convergence #$number?';
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
  String get consensusDeleted => 'Convergence supprimee';

  @override
  String get initialMessageUpdated => 'Initial message updated';

  @override
  String get initialMessageDeleted => 'Initial message deleted';

  @override
  String failedToDeleteConsensus(String error) {
    return 'Echec de la suppression de la convergence: $error';
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
  String get wizardStep1Title => 'De quoi voulez-vous parler?';

  @override
  String get wizardStep1Subtitle => 'C\'est le coeur de votre chat';

  @override
  String get wizardStep2Title => 'Definir le rythme';

  @override
  String get wizardStep2Subtitle => 'Combien de temps pour chaque phase?';

  @override
  String get wizardOneLastThing => 'Une derniere chose...';

  @override
  String get wizardProposingLabel => 'Proposer (soumettre des idees)';

  @override
  String get wizardRatingLabel => 'Evaluer (classer les idees)';

  @override
  String get back => 'Retour';

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
  String get forceAsConsensus => 'Forcer comme Convergence';

  @override
  String get forceAsConsensusDescription =>
      'Soumettre directement comme convergence, en sautant le vote';

  @override
  String get forceConsensus => 'Forcer la Convergence';

  @override
  String get forceConsensusTitle => 'Forcer la Convergence?';

  @override
  String get forceConsensusMessage =>
      'Cela definira immediatement votre proposition comme la convergence et demarrera un nouveau cycle. Toute la progression du tour actuel sera perdue.';

  @override
  String get forceConsensusSuccess => 'Convergence forcee avec succes';

  @override
  String failedToForceConsensus(String error) {
    return 'Echec du forcage de la convergence: $error';
  }

  @override
  String get glossaryUserRoundTitle => 'user-round';

  @override
  String get glossaryUserRoundDef =>
      'One participant completing one round of rating. Each user-round costs 1 credit (\$0.01).';

  @override
  String get glossaryConsensusTitle => 'convergence';

  @override
  String get glossaryConsensusDef =>
      'Lorsque personne ne peut battre la même proposition sur plusieurs tours, la convergence est atteinte.';

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
      'Une sequence de tours visant la convergence. Un nouveau cycle commence apres que la convergence est atteinte.';

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

  @override
  String get homeTourPendingRequestTitle => 'Demandes en Attente';

  @override
  String get homeTourPendingRequestDesc =>
      'Quand vous demandez a rejoindre un chat, l\'hote examine votre demande. Vous la verrez ici avec un badge \'En attente\' jusqu\'a approbation.';

  @override
  String get homeTourYourChatsTitle => 'Vos Chats';

  @override
  String get homeTourYourChatsDesc =>
      'Vos chats actifs apparaissent ici. Chaque carte affiche la phase en cours, le nombre de participants et les langues.';

  @override
  String get homeTourCreateFabTitle => 'Creer un Chat';

  @override
  String get homeTourCreateFabDesc =>
      'Appuyez sur + pour creer votre propre chat. Choisissez le sujet, invitez des amis et construisez un consensus ensemble.';

  @override
  String get homeTourDemoTitle => 'Essayer la Démo';

  @override
  String get homeTourDemoDesc =>
      'Vous voulez voir comment fonctionne le vote ? Appuyez ici pour essayer une démo interactive rapide.';

  @override
  String get homeTourHowItWorksTitle => 'Comment ça Marche';

  @override
  String get homeTourHowItWorksDesc =>
      'Besoin d\'un rappel ? Appuyez ici pour revoir le tutoriel à tout moment.';

  @override
  String get homeTourLegalDocsTitle => 'Documents Légaux';

  @override
  String get homeTourLegalDocsDesc =>
      'Consultez la Politique de Confidentialité et les Conditions d\'Utilisation ici.';

  @override
  String get searchOrJoinWithCode =>
      'Rechercher des chats ou entrer un code d\'invitation...';

  @override
  String get searchYourChatsOrJoinWithCode =>
      'Rechercher vos chats ou entrer un code d\'invitation...';

  @override
  String get noMatchingChats => 'Aucun chat correspondant';

  @override
  String inviteCodeDetected(String code) {
    return 'Rejoindre avec le code d\'invitation : $code';
  }

  @override
  String get wizardVisibilityTitle => 'Qui peut rejoindre ?';

  @override
  String get wizardVisibilitySubtitle =>
      'Choisissez qui peut trouver et rejoindre votre chat';

  @override
  String get wizardVisibilityPublicTitle => 'Public';

  @override
  String get wizardVisibilityPublicDesc =>
      'Tout le monde peut decouvrir et rejoindre ce chat';

  @override
  String get wizardVisibilityPrivateTitle => 'Prive';

  @override
  String get wizardVisibilityPrivateDesc =>
      'Seules les personnes avec le code d\'invitation peuvent rejoindre';

  @override
  String get homeTourSearchBarTitle => 'Rechercher Vos Chats';

  @override
  String get homeTourSearchBarDesc =>
      'Filtrez vos chats par nom, ou entrez un code d\'invitation de 6 caracteres pour rejoindre un chat prive.';

  @override
  String get homeTourExploreButtonTitle => 'Explorer les Chats Publics';

  @override
  String get homeTourExploreButtonDesc =>
      'Appuyez ici pour decouvrir et rejoindre des chats publics crees par d\'autres utilisateurs.';

  @override
  String get homeTourLanguageSelectorTitle => 'Changer la Langue';

  @override
  String get homeTourLanguageSelectorDesc =>
      'Appuyez ici pour changer la langue de l\'application. OneMind est disponible en anglais, espagnol, portugais, francais et allemand.';

  @override
  String get homeTourSkip => 'Passer la visite';

  @override
  String get homeTourNext => 'Suivant';

  @override
  String get homeTourFinish => 'Compris!';

  @override
  String homeTourStepOf(int current, int total) {
    return 'Etape $current sur $total';
  }

  @override
  String get wizardTranslationsTitle => 'Langues';

  @override
  String get wizardTranslationsSubtitle =>
      'Choisissez les langues prises en charge par ce chat';

  @override
  String get singleLanguageToggle => 'Langue unique';

  @override
  String get singleLanguageDesc =>
      'Tout le monde participe dans une seule langue';

  @override
  String get multiLanguageDesc =>
      'Les propositions sont automatiquement traduites entre les langues';

  @override
  String get chatLanguageLabel => 'Langue du chat';

  @override
  String get selectLanguages => 'Langues prises en charge :';

  @override
  String get autoTranslateHint =>
      'Les propositions seront automatiquement traduites entre toutes les langues selectionnees';

  @override
  String get translationsSection => 'Langues';

  @override
  String get translationLanguagesLabel => 'Langues';

  @override
  String get autoTranslateLabel => 'Traduction automatique';

  @override
  String get chatAutoTranslated => 'Traduit automatiquement';

  @override
  String welcomeName(String name) {
    return 'Bienvenue, $name';
  }

  @override
  String get editName => 'Modifier le nom';

  @override
  String get primaryLanguage => 'Langue principale';

  @override
  String get iAlsoSpeak => 'Je parle aussi';

  @override
  String get spokenLanguages => 'Langues parlees';

  @override
  String get homeTourWelcomeNameTitle => 'Votre nom d\'affichage';

  @override
  String get homeTourWelcomeNameDesc =>
      'C\'est votre nom d\'affichage. Appuyez sur l\'icone du crayon pour le modifier a tout moment !';

  @override
  String get chatTourTitleTitle => 'Nom du Chat';

  @override
  String get chatTourTitleDesc =>
      'C\'est le nom du chat. Chaque chat a un sujet que tout le monde discute ensemble.';

  @override
  String get chatTourMessageTitle => 'Question de Discussion';

  @override
  String get chatTourMessageDesc =>
      'C\'est la question en cours de discussion. Tout le monde soumet des idees en reponse.';

  @override
  String get chatTourProposingTitle => 'Soumettre des Idees';

  @override
  String get chatTourProposingDesc =>
      'C\'est ici que vous soumettez des idées. À chaque tour, tout le monde propose puis évalue.';

  @override
  String get chatTourParticipantsTitle => 'Participants';

  @override
  String get chatTourParticipantsDesc =>
      'Rencontrez les participants du tutoriel : Alice, Bob et Carol. Appuyez ici pour voir qui est dans le chat.';

  @override
  String get chatTourShareTitle => 'Partager le Chat';

  @override
  String get chatTourShareDesc =>
      'Partagez ce chat avec des amis en utilisant un lien d\'invitation ou un code QR.';

  @override
  String get tutorialShareContinueHint =>
      'Appuyez sur le bouton Continuer pour continuer le tutoriel.';
}
