// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Spanish Castilian (`es`).
class AppLocalizationsEs extends AppLocalizations {
  AppLocalizationsEs([String locale = 'es']) : super(locale);

  @override
  String get appTitle => 'OneMind';

  @override
  String get discover => 'Descubrir';

  @override
  String get discoverPublicChats => 'Descubrir chats publicos';

  @override
  String get discoverChats => 'Descubrir Chats';

  @override
  String get joinWithCode => 'Unirse con Codigo';

  @override
  String get joinAnExistingChatWithInviteCode =>
      'Unirse a un chat existente con codigo de invitacion';

  @override
  String get joinChat => 'Unirse al Chat';

  @override
  String get join => 'Unirse';

  @override
  String get findChat => 'Buscar Chat';

  @override
  String get requestToJoin => 'Solicitar Unirse';

  @override
  String get createChat => 'Crear Chat';

  @override
  String get createANewChat => 'Crear un nuevo chat';

  @override
  String get chatCreated => 'Chat Creado!';

  @override
  String get cancel => 'Cancelar';

  @override
  String get continue_ => 'Continuar';

  @override
  String get retry => 'Reintentar';

  @override
  String get yes => 'Si';

  @override
  String get no => 'No';

  @override
  String get officialOneMind => 'OneMind Oficial';

  @override
  String get official => 'OFICIAL';

  @override
  String get pending => 'PENDIENTE';

  @override
  String get pendingRequests => 'Solicitudes Pendientes';

  @override
  String get yourChats => 'Tus Chats';

  @override
  String get cancelRequest => 'Cancelar Solicitud';

  @override
  String cancelRequestQuestion(String chatName) {
    return 'Cancelar tu solicitud para unirte a \"$chatName\"?';
  }

  @override
  String get yesCancel => 'Si, Cancelar';

  @override
  String get requestCancelled => 'Solicitud cancelada';

  @override
  String get waitingForHostApproval => 'Esperando aprobacion del anfitrion';

  @override
  String get hostApprovalRequired =>
      'Se requiere aprobacion del anfitrion para unirse';

  @override
  String get noChatsYet => 'Sin chats aun';

  @override
  String get discoverPublicChatsJoinOrCreate =>
      'Descubre chats publicos, unete con un codigo o crea el tuyo';

  @override
  String get discoverPublicChatsButton => 'Descubrir Chats Publicos';

  @override
  String get noActiveChatsYet =>
      'Sin chats activos aun. Tus chats aprobados apareceran aqui.';

  @override
  String get loadingChats => 'Cargando chats';

  @override
  String get failedToLoadChats => 'Error al cargar chats';

  @override
  String get chatNotFound => 'Chat no encontrado';

  @override
  String get failedToLookupChat => 'Error al buscar el chat';

  @override
  String failedToJoinChat(String error) {
    return 'Error al unirse al chat: $error';
  }

  @override
  String get enterInviteCode =>
      'Ingresa el codigo de invitacion de 6 caracteres:';

  @override
  String get pleaseEnterSixCharCode =>
      'Por favor ingresa un codigo de 6 caracteres';

  @override
  String get inviteCodeHint => 'ABC123';

  @override
  String hostedBy(String hostName) {
    return 'Organizado por $hostName';
  }

  @override
  String get thisChatsRequiresInvite => 'Este chat requiere una invitacion';

  @override
  String get enterEmailForInvite =>
      'Ingresa el email al que se envio tu invitacion:';

  @override
  String get yourEmailHint => 'tu@email.com';

  @override
  String get pleaseEnterEmailAddress =>
      'Por favor ingresa tu direccion de email';

  @override
  String get pleaseEnterValidEmail => 'Por favor ingresa un email valido';

  @override
  String get noInviteFoundForEmail =>
      'No se encontro invitacion para este email';

  @override
  String get failedToValidateInvite => 'Error al validar la invitacion';

  @override
  String get pleaseVerifyEmailFirst => 'Por favor verifica tu email primero';

  @override
  String get verifyEmail => 'Verificar Email';

  @override
  String emailVerified(String email) {
    return 'Email verificado: $email';
  }

  @override
  String get enterDisplayName => 'Ingresa tu nombre visible:';

  @override
  String get yourName => 'Tu nombre';

  @override
  String get yourNamePlaceholder => 'Tu Nombre';

  @override
  String get displayName => 'Nombre visible';

  @override
  String get enterYourName => 'Ingresa tu nombre';

  @override
  String get pleaseEnterYourName => 'Por favor ingresa tu nombre';

  @override
  String get yourDisplayName => 'Tu nombre visible';

  @override
  String get yourNameVisibleToAll =>
      'Tu nombre sera visible para todos los participantes';

  @override
  String get usingSavedName => 'Usando tu nombre guardado';

  @override
  String get joinRequestSent =>
      'Solicitud enviada. Esperando aprobacion del anfitrion.';

  @override
  String get searchPublicChats => 'Buscar chats publicos...';

  @override
  String noChatsFoundFor(String query) {
    return 'No se encontraron chats para \"$query\"';
  }

  @override
  String get noPublicChatsAvailable => 'No hay chats publicos disponibles';

  @override
  String get beFirstToCreate => 'Se el primero en crear uno!';

  @override
  String failedToLoadPublicChats(String error) {
    return 'Error al cargar chats publicos: $error';
  }

  @override
  String participantCount(int count) {
    return '$count participante';
  }

  @override
  String participantsCount(int count) {
    return '$count participantes';
  }

  @override
  String get enterYourNameTitle => 'Ingresa Tu Nombre';

  @override
  String get anonymous => 'Anonimo';

  @override
  String get timerWarning => 'Advertencia de Temporizador';

  @override
  String timerWarningMessage(int minutes) {
    return 'Tus temporizadores de fase son mas largos que la ventana de $minutes minutos programada.\n\nLas fases pueden extenderse mas alla del tiempo programado, o pausarse cuando la ventana se cierre.\n\nConsidera usar temporizadores mas cortos (5 min o 30 min) para sesiones programadas.';
  }

  @override
  String get adjustSettings => 'Ajustar Configuracion';

  @override
  String get continueAnyway => 'Continuar de Todas Formas';

  @override
  String get chatNowPublic => 'Tu chat es ahora publico!';

  @override
  String anyoneCanJoinFrom(String chatName) {
    return 'Cualquiera puede encontrar y unirse a \"$chatName\" desde la pagina Descubrir.';
  }

  @override
  String invitesSent(int count) {
    return '$count invitacion enviada!';
  }

  @override
  String invitesSentPlural(int count) {
    return '$count invitaciones enviadas!';
  }

  @override
  String get noInvitesSent => 'No se enviaron invitaciones';

  @override
  String get onlyInvitedUsersCanJoin =>
      'Solo los usuarios invitados pueden unirse a este chat.';

  @override
  String get shareCodeWithParticipants =>
      'Comparte este codigo con los participantes:';

  @override
  String get inviteCodeCopied => 'Codigo de invitacion copiado al portapapeles';

  @override
  String get tapToCopy => 'Toca para copiar';

  @override
  String get showQrCode => 'Mostrar Codigo QR';

  @override
  String get addEmailForInviteOnly =>
      'Agrega al menos un email para el modo solo invitados';

  @override
  String get settings => 'Configuracion';

  @override
  String get language => 'Idioma';

  @override
  String get english => 'English';

  @override
  String get spanish => 'Espanol';

  @override
  String get rankPropositions => 'Clasificar Propuestas';

  @override
  String get placing => 'Colocando: ';

  @override
  String rankedSuccessfully(int count) {
    return '$count propuestas clasificadas exitosamente!';
  }

  @override
  String get failedToSaveRankings => 'Error al guardar las clasificaciones';

  @override
  String get chatPausedByHost => 'El chat fue pausado por el anfitrion';

  @override
  String get goBack => 'Volver';

  @override
  String get ratePropositions => 'Calificar Propuestas';

  @override
  String get submitRatings => 'Enviar Calificaciones';

  @override
  String failedToSubmitRatings(String error) {
    return 'Error al enviar calificaciones: $error';
  }

  @override
  String roundResults(int roundNumber) {
    return 'Resultados de la Ronda $roundNumber';
  }

  @override
  String get noPropositionsToDisplay => 'No hay propuestas para mostrar';

  @override
  String get noPreviousWinner => 'Sin ganador anterior';

  @override
  String roundWinner(int roundNumber) {
    return 'Ganador de la Ronda $roundNumber';
  }

  @override
  String roundWinners(int roundNumber) {
    return 'Ganadores de la Ronda $roundNumber';
  }

  @override
  String get unknownProposition => 'Propuesta desconocida';

  @override
  String score(String score) {
    return 'Puntuacion: $score';
  }

  @override
  String soleWinsProgress(int current, int required) {
    return 'Victorias unicas: $current/$required';
  }

  @override
  String get tiedWinNoConsensus => 'Empate (no cuenta para el consenso)';

  @override
  String get seeAllResults => 'Ver Todos los Resultados';

  @override
  String get startPhase => 'Iniciar Fase';

  @override
  String get waiting => 'Esperando';

  @override
  String get waitingForHostToStart => 'Esperando que el anfitrion inicie...';

  @override
  String roundNumber(int roundNumber) {
    return 'Ronda $roundNumber';
  }

  @override
  String get viewAllPropositions => 'Ver todas las propuestas';

  @override
  String get chatIsPaused => 'Chat pausado...';

  @override
  String get shareYourIdea => 'Comparte tu idea...';

  @override
  String get addAnotherIdea => 'Agregar otra idea...';

  @override
  String get submit => 'Enviar';

  @override
  String get addProposition => 'Agregar Propuesta';

  @override
  String get waitingForRatingPhase => 'Esperando fase de calificacion...';

  @override
  String get endProposingStartRating =>
      'Terminar Propuestas e Iniciar Calificacion';

  @override
  String get proposingComplete => 'Propuestas Completas';

  @override
  String get reviewPropositionsStartRating =>
      'Revisa las propuestas e inicia la calificacion cuando estes listo.';

  @override
  String get waitingForHostToStartRating =>
      'Esperando que el anfitrion inicie la fase de calificacion.';

  @override
  String get startRatingPhase => 'Iniciar Fase de Calificacion';

  @override
  String get ratingComplete => 'Calificacion Completa';

  @override
  String get waitingForRatingPhaseEnd =>
      'Esperando que termine la fase de calificacion.';

  @override
  String rateAllPropositions(int count) {
    return 'Califica las $count propuestas';
  }

  @override
  String get continueRating => 'Continuar Calificando';

  @override
  String get startRating => 'Iniciar Calificacion';

  @override
  String get endRatingStartNextRound =>
      'Terminar Calificacion e Iniciar Siguiente Ronda';

  @override
  String get chatPaused => 'Chat Pausado';

  @override
  String get chatPausedByHostTitle => 'Chat Pausado por el Anfitrion';

  @override
  String get timerStoppedTapResume =>
      'El temporizador esta detenido. Toca Reanudar en la barra para continuar.';

  @override
  String get hostPausedPleaseWait =>
      'El anfitrion ha pausado este chat. Por favor espera a que lo reanude.';
}
