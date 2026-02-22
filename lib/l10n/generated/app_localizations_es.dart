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
  String get howItWorks => 'Como funciona';

  @override
  String get discover => 'Descubrir';

  @override
  String get discoverPublicChats => 'Descubrir chats publicos';

  @override
  String get discoverChats => 'Descubrir Chats';

  @override
  String get joinWithCode => 'Unirse con Codigo';

  @override
  String get joinAnExistingChatWithInviteCode => 'Unirse a un chat existente con codigo de invitacion';

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
  String get delete => 'Eliminar';

  @override
  String get leave => 'Salir';

  @override
  String get kick => 'Expulsar';

  @override
  String get pause => 'Pausar';

  @override
  String get resume => 'Reanudar';

  @override
  String get remove => 'Quitar';

  @override
  String get clear => 'Borrar';

  @override
  String get done => 'Listo';

  @override
  String get save => 'Guardar';

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
  String get hostApprovalRequired => 'El anfitrion debe aprobar cada solicitud';

  @override
  String get noChatsYet => 'Sin chats aun';

  @override
  String get discoverPublicChatsJoinOrCreate => 'Descubre chats publicos, unete con un codigo o crea el tuyo';

  @override
  String get discoverPublicChatsButton => 'Descubrir Chats Publicos';

  @override
  String get noActiveChatsYet => 'Sin chats activos aun. Tus chats aprobados apareceran aqui.';

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
  String get enterInviteCode => 'Ingresa el codigo de invitacion de 6 caracteres:';

  @override
  String get pleaseEnterSixCharCode => 'Por favor ingresa un codigo de 6 caracteres';

  @override
  String get inviteCodeHint => 'ABC123';

  @override
  String hostedBy(String hostName) {
    return 'Organizado por $hostName';
  }

  @override
  String get thisChatsRequiresInvite => 'Este chat requiere una invitacion';

  @override
  String get enterEmailForInvite => 'Ingresa el email al que se envio tu invitacion:';

  @override
  String get yourEmailHint => 'tu@email.com';

  @override
  String get pleaseEnterEmailAddress => 'Por favor ingresa tu direccion de email';

  @override
  String get pleaseEnterValidEmail => 'Por favor ingresa un email valido';

  @override
  String get noInviteFoundForEmail => 'No se encontro invitacion para este email';

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
  String get yourName => 'Tu Nombre';

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
  String get yourNameVisibleToAll => 'Tu nombre sera visible para todos los participantes';

  @override
  String get usingSavedName => 'Usando tu nombre guardado';

  @override
  String get joinRequestSent => 'Solicitud enviada. Esperando aprobacion del anfitrion.';

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
  String get onlyInvitedUsersCanJoin => 'Solo los usuarios invitados pueden unirse a este chat.';

  @override
  String get shareCodeWithParticipants => 'Comparte este codigo con los participantes:';

  @override
  String get inviteCodeCopied => 'Codigo de invitacion copiado al portapapeles';

  @override
  String get tapToCopy => 'Toca para copiar';

  @override
  String get showQrCode => 'Mostrar Codigo QR';

  @override
  String get addEmailForInviteOnly => 'Agrega al menos un email para el modo solo invitados';

  @override
  String get emailAlreadyAdded => 'Email ya agregado';

  @override
  String get settings => 'Configuracion';

  @override
  String get language => 'Idioma';

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
  String get ratingPhaseEnded => 'La fase de calificacion ha terminado';

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
  String nWayTie(int count) {
    return '$count-WAY TIE';
  }

  @override
  String winnerIndexOfTotal(int current, int total) {
    return '$current of $total';
  }

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
  String get endProposingStartRating => 'Terminar Propuestas e Iniciar Calificacion';

  @override
  String get proposingComplete => 'Propuestas Completas';

  @override
  String get reviewPropositionsStartRating => 'Revisa las propuestas e inicia la calificacion cuando estes listo.';

  @override
  String get waitingForHostToStartRating => 'Esperando que el anfitrion inicie la fase de calificacion.';

  @override
  String get startRatingPhase => 'Iniciar Fase de Calificacion';

  @override
  String get ratingComplete => 'Calificacion Completa';

  @override
  String get waitingForRatingPhaseEnd => 'Esperando que termine la fase de calificacion.';

  @override
  String rateAllPropositions(int count) {
    return 'Califica las $count propuestas';
  }

  @override
  String get continueRating => 'Continuar Calificando';

  @override
  String get startRating => 'Iniciar Calificacion';

  @override
  String get endRatingStartNextRound => 'Terminar Calificacion e Iniciar Siguiente Ronda';

  @override
  String get chatPaused => 'Chat Pausado';

  @override
  String get chatPausedByHostTitle => 'Chat Pausado por el Anfitrion';

  @override
  String get timerStoppedTapResume => 'El temporizador esta detenido. Toca Reanudar en la barra para continuar.';

  @override
  String get hostPausedPleaseWait => 'El anfitrion ha pausado este chat. Por favor espera a que lo reanude.';

  @override
  String get previousWinner => 'Ganador';

  @override
  String get yourProposition => 'Tu Propuesta';

  @override
  String get yourPropositions => 'Tus Propuestas';

  @override
  String get rate => 'Calificar';

  @override
  String get participants => 'Participantes';

  @override
  String get chatInfo => 'Info del Chat';

  @override
  String get shareQrCode => 'Compartir Codigo QR';

  @override
  String get joinRequests => 'Solicitudes de Union';

  @override
  String get resumeChat => 'Reanudar Chat';

  @override
  String get pauseChat => 'Pausar Chat';

  @override
  String get leaveChat => 'Salir del Chat';

  @override
  String get deleteChat => 'Eliminar Chat';

  @override
  String get host => 'Anfitrion';

  @override
  String get deletePropositionQuestion => 'Eliminar Propuesta?';

  @override
  String get areYouSureDeleteProposition => 'Estas seguro de que quieres eliminar esta propuesta?';

  @override
  String get deleteChatQuestion => 'Eliminar Chat?';

  @override
  String get leaveChatQuestion => 'Salir del Chat?';

  @override
  String get kickParticipantQuestion => 'Expulsar Participante?';

  @override
  String get pauseChatQuestion => 'Pausar Chat?';

  @override
  String get removePaymentMethodQuestion => 'Quitar Metodo de Pago?';

  @override
  String get propositionDeleted => 'Propuesta eliminada';

  @override
  String get chatDeleted => 'Chat eliminado';

  @override
  String get youHaveLeftChat => 'Has salido del chat';

  @override
  String get youHaveBeenRemoved => 'Has sido eliminado de este chat';

  @override
  String get chatHasBeenDeleted => 'Este chat ha sido eliminado';

  @override
  String participantRemoved(String name) {
    return '$name ha sido eliminado';
  }

  @override
  String get chatPausedSuccess => 'Chat pausado';

  @override
  String get requestApproved => 'Solicitud aprobada';

  @override
  String get requestDenied => 'Solicitud denegada';

  @override
  String failedToSubmit(String error) {
    return 'Error al enviar: $error';
  }

  @override
  String get duplicateProposition => 'Esta propuesta ya existe en esta ronda';

  @override
  String failedToStartPhase(String error) {
    return 'Error al iniciar fase: $error';
  }

  @override
  String failedToAdvancePhase(String error) {
    return 'Error al avanzar fase: $error';
  }

  @override
  String failedToCompleteRating(String error) {
    return 'Error al completar calificacion: $error';
  }

  @override
  String failedToDelete(String error) {
    return 'Error al eliminar: $error';
  }

  @override
  String failedToDeleteChat(String error) {
    return 'Error al eliminar chat: $error';
  }

  @override
  String failedToLeaveChat(String error) {
    return 'Error al salir del chat: $error';
  }

  @override
  String failedToKickParticipant(String error) {
    return 'Error al expulsar participante: $error';
  }

  @override
  String failedToPauseChat(String error) {
    return 'Error al pausar chat: $error';
  }

  @override
  String error(String error) {
    return 'Error: $error';
  }

  @override
  String get noPendingRequests => 'Sin solicitudes pendientes';

  @override
  String get newRequestsWillAppear => 'Las nuevas solicitudes apareceran aqui';

  @override
  String participantsJoined(int count) {
    return '$count participantes se han unido';
  }

  @override
  String waitingForMoreParticipants(int count) {
    return 'Esperando que se unan $count participante(s) mas';
  }

  @override
  String get scheduled => 'Programado';

  @override
  String get chatOutsideSchedule => 'Chat fuera de la ventana programada';

  @override
  String nextWindowStarts(String dateTime) {
    return 'La proxima ventana comienza $dateTime';
  }

  @override
  String get scheduleWindows => 'Ventanas programadas:';

  @override
  String get scheduledToStart => 'Programado para iniciar';

  @override
  String get chatWillAutoStart => 'El chat iniciara automaticamente a la hora programada.';

  @override
  String submittedCount(int submitted, int total) {
    return '$submitted/$total enviados';
  }

  @override
  String propositionCollected(int count) {
    return '$count propuesta recopilada';
  }

  @override
  String propositionsCollected(int count) {
    return '$count propuestas recopiladas';
  }

  @override
  String get timeExpired => 'Tiempo expirado';

  @override
  String get noDataAvailable => 'Sin datos disponibles';

  @override
  String get tryAgain => 'Intentar de Nuevo';

  @override
  String get requireApproval => 'Requerir aprobacion';

  @override
  String get requireAuthentication => 'Requerir autenticacion';

  @override
  String get showPreviousResults => 'Mostrar resultados completos de rondas anteriores';

  @override
  String get enableAdaptiveDuration => 'Habilitar duracion adaptativa';

  @override
  String get enableOneMindAI => 'Habilitar OneMind AI';

  @override
  String get enableAutoAdvanceProposing => 'Habilitar para ideas';

  @override
  String get enableAutoAdvanceRating => 'Habilitar para calificaciones';

  @override
  String get hideWhenOutsideSchedule => 'Ocultar fuera de horario';

  @override
  String get chatVisibleButPaused => 'Chat visible pero pausado fuera de horario';

  @override
  String get chatHiddenUntilNext => 'Chat oculto hasta la proxima ventana programada';

  @override
  String get timezone => 'Zona horaria';

  @override
  String get scheduleType => 'Tipo de Horario';

  @override
  String get oneTime => 'Una vez';

  @override
  String get recurring => 'Recurrente';

  @override
  String get startDateTime => 'Fecha y Hora de Inicio';

  @override
  String get scheduleWindowsLabel => 'Ventanas de Horario';

  @override
  String get addWindow => 'Agregar Ventana';

  @override
  String get searchTimezone => 'Buscar zona horaria...';

  @override
  String get manual => 'Manual';

  @override
  String get auto => 'Automatico';

  @override
  String get credits => 'Creditos';

  @override
  String get refillAmountMustBeGreater => 'El monto de recarga debe ser mayor que el umbral';

  @override
  String get autoRefillSettingsUpdated => 'Configuracion de recarga automatica actualizada';

  @override
  String get autoRefillEnabled => 'Recarga automatica habilitada';

  @override
  String get autoRefillDisabled => 'Recarga automatica deshabilitada';

  @override
  String get saveSettings => 'Guardar Configuracion';

  @override
  String get removeCard => 'Quitar Tarjeta';

  @override
  String get purchaseWithStripe => 'Comprar con Stripe';

  @override
  String get processing => 'Procesando...';

  @override
  String get pageNotFound => 'Pagina No Encontrada';

  @override
  String get goHome => 'Ir al Inicio';

  @override
  String allPropositionsCount(int count) {
    return 'Todas las Propuestas ($count)';
  }

  @override
  String get hostCanModerateContent => 'Como anfitrion, puedes moderar el contenido. La identidad del remitente esta oculta.';

  @override
  String get yourPropositionLabel => '(Tu propuesta)';

  @override
  String get previousWinnerLabel => '(Ganador anterior)';

  @override
  String get cannotBeUndone => 'Esta accion no se puede deshacer.';

  @override
  String deleteChatConfirmation(String chatName) {
    return 'Estas seguro de que quieres eliminar \"$chatName\"?\n\nEsto eliminara permanentemente todas las propuestas, calificaciones e historial. Esta accion no se puede deshacer.';
  }

  @override
  String leaveChatConfirmation(String chatName) {
    return 'Estas seguro de que quieres salir de \"$chatName\"?\n\nYa no veras este chat en tu lista.';
  }

  @override
  String kickParticipantConfirmation(String participantName) {
    return 'Estas seguro de que quieres eliminar a \"$participantName\" de este chat?\n\nNo podra volver a unirse sin aprobacion.';
  }

  @override
  String get pauseChatConfirmation => 'Esto pausara el temporizador de la fase actual. Los participantes veran que el chat esta pausado por el anfitrion.';

  @override
  String get approveOrDenyRequests => 'Aprobar o denegar solicitudes para unirse a este chat.';

  @override
  String get signedIn => 'Conectado';

  @override
  String get guest => 'Invitado';

  @override
  String get approve => 'Aprobar';

  @override
  String get deny => 'Denegar';

  @override
  String get initialMessage => 'Mensaje Inicial';

  @override
  String consensusNumber(int number) {
    return 'Consenso #$number';
  }

  @override
  String get kickParticipant => 'Expulsar participante';

  @override
  String get propositions => 'Propuestas';

  @override
  String get leaderboard => 'Clasificacion';

  @override
  String get noLeaderboardData => 'No hay datos de clasificacion disponibles';

  @override
  String get skip => 'Saltar';

  @override
  String get skipped => 'Saltado';

  @override
  String skipsRemaining(int remaining) {
    return '$remaining saltos restantes';
  }

  @override
  String get createChatTitle => 'Crear Chat';

  @override
  String get enterYourNameLabel => 'Ingresa tu nombre';

  @override
  String get nameVisibleToAll => 'Tu nombre sera visible para todos los participantes';

  @override
  String get basicInfo => 'Informacion Basica';

  @override
  String get chatNameRequired => 'Nombre del Chat *';

  @override
  String get chatNameHint => 'ej., Almuerzo del Equipo Viernes';

  @override
  String get required => 'Requerido';

  @override
  String get initialMessageRequired => 'Mensaje Inicial *';

  @override
  String get initialMessageOptional => 'Mensaje Inicial (Opcional)';

  @override
  String get initialMessageHint => 'El tema o pregunta inicial';

  @override
  String get initialMessageHelperText => 'Los participantes sabran que escribiste esto ya que creaste el chat';

  @override
  String get descriptionOptional => 'Descripcion (Opcional)';

  @override
  String get descriptionHint => 'Contexto adicional';

  @override
  String get visibility => 'Visibilidad';

  @override
  String get whoCanJoin => 'Quien puede encontrar y unirse a este chat?';

  @override
  String get accessPublic => 'Publico';

  @override
  String get accessPublicDesc => 'Cualquiera puede descubrir y unirse';

  @override
  String get accessCode => 'Codigo de Invitacion';

  @override
  String get accessCodeDesc => 'Comparte un codigo de 6 caracteres para unirse';

  @override
  String get accessEmail => 'Solo por Email';

  @override
  String get accessEmailDesc => 'Solo direcciones de email invitadas pueden unirse';

  @override
  String get instantJoin => 'Los usuarios se unen instantaneamente';

  @override
  String get inviteByEmail => 'Invitar por Email';

  @override
  String get inviteEmailOnly => 'Solo direcciones de email invitadas pueden unirse a este chat';

  @override
  String get emailAddress => 'Direccion de email';

  @override
  String get emailHint => 'usuario@ejemplo.com';

  @override
  String get invalidEmail => 'Por favor ingresa un email valido';

  @override
  String get addEmailToSend => 'Agrega al menos un email para enviar invitaciones';

  @override
  String get facilitationMode => 'Como Funcionan las Fases';

  @override
  String get facilitationDesc => 'Elige entre control manual o temporizadores automaticos para transiciones de fase.';

  @override
  String get modeManual => 'Manual';

  @override
  String get modeAuto => 'Automatico';

  @override
  String get modeManualDesc => 'Tu controlas cuando comienza y termina cada fase. Sin temporizadores.';

  @override
  String get modeAutoDesc => 'Los temporizadores funcionan automaticamente. Aun puedes terminar fases antes.';

  @override
  String get autoStartParticipants => 'Iniciar cuando se unan';

  @override
  String get ratingStartMode => 'Modo de Inicio de Calificacion';

  @override
  String get ratingStartModeDesc => 'Controla como comienza la fase de calificacion despues de terminar las propuestas.';

  @override
  String get ratingAutoDesc => 'La calificacion comienza inmediatamente despues de que terminan las propuestas o se alcanza el umbral.';

  @override
  String get ratingManualDesc => 'Despues de terminar las propuestas, tu eliges cuando iniciar la calificacion (ej., al dia siguiente).';

  @override
  String phaseFlowExplanation(String duration, int threshold, int minimum) {
    return 'Cada fase dura hasta $duration, pero termina antes si $threshold personas participan. No terminara hasta que existan al menos $minimum ideas (el temporizador se extiende si es necesario).';
  }

  @override
  String get enableSchedule => 'Habilitar Horario';

  @override
  String get restrictChatRoom => 'Restringir cuando la sala de chat esta abierta';

  @override
  String get timers => 'Temporizadores';

  @override
  String get useSameDuration => 'Misma duracion para ambas fases';

  @override
  String get useSameDurationDesc => 'Usar el mismo limite de tiempo para propuestas y calificacion';

  @override
  String get phaseDuration => 'Duracion de Fase';

  @override
  String get proposing => 'Propuestas';

  @override
  String get rating => 'Calificacion';

  @override
  String get preset5min => '5 min';

  @override
  String get preset30min => '30 min';

  @override
  String get preset1hour => '1 hora';

  @override
  String get preset1day => '1 dia';

  @override
  String get presetCustom => 'Personalizado';

  @override
  String get duration1min => '1 min';

  @override
  String get duration2min => '2 min';

  @override
  String get duration10min => '10 min';

  @override
  String get duration2hours => '2 horas';

  @override
  String get duration4hours => '4 horas';

  @override
  String get duration8hours => '8 horas';

  @override
  String get duration12hours => '12 horas';

  @override
  String get hours => 'Horas';

  @override
  String get minutes => 'Minutos';

  @override
  String get max24h => '(max 24h)';

  @override
  String get minimumToAdvance => 'Participacion Requerida';

  @override
  String get timeExtendsAutomatically => 'La fase no terminara hasta que se cumplan los requisitos';

  @override
  String get proposingMinimum => 'Ideas necesarias';

  @override
  String proposingMinimumDesc(int count) {
    return 'La fase no terminara hasta que se envien $count ideas';
  }

  @override
  String get ratingMinimum => 'Calificaciones necesarias';

  @override
  String ratingMinimumDesc(int count) {
    return 'La fase no terminara hasta que cada idea tenga $count calificaciones';
  }

  @override
  String get autoAdvanceAt => 'Terminar Fase Antes';

  @override
  String get skipTimerEarly => 'La fase puede terminar antes cuando se alcancen los limites';

  @override
  String whenPercentSubmit(int percent) {
    return 'Cuando $percent% de participantes envian';
  }

  @override
  String get minParticipantsSubmit => 'Ideas necesarias';

  @override
  String get minAvgRaters => 'Calificaciones necesarias';

  @override
  String proposingThresholdPreview(int threshold, int participants, int percent) {
    return 'La fase termina antes cuando $threshold de $participants participantes envian ideas ($percent%)';
  }

  @override
  String proposingThresholdPreviewSimple(int threshold) {
    return 'La fase termina antes cuando se envien $threshold ideas';
  }

  @override
  String ratingThresholdPreview(int threshold) {
    return 'La fase termina antes cuando cada idea tenga $threshold calificaciones';
  }

  @override
  String get consensusSettings => 'Configuracion de Consenso';

  @override
  String get confirmationRounds => 'Rondas de confirmacion';

  @override
  String get firstWinnerConsensus => 'El primer ganador alcanza consenso inmediatamente';

  @override
  String mustWinConsecutive(int count) {
    return 'La misma propuesta debe ganar $count rondas consecutivas';
  }

  @override
  String get showFullResults => 'Mostrar resultados completos de rondas anteriores';

  @override
  String get seeAllPropositions => 'Los usuarios ven todas las propuestas y calificaciones';

  @override
  String get seeWinningOnly => 'Los usuarios solo ven la propuesta ganadora';

  @override
  String get propositionLimits => 'Limites de Propuestas';

  @override
  String get propositionsPerUser => 'Propuestas por usuario';

  @override
  String get onePropositionPerRound => 'Cada usuario puede enviar 1 propuesta por ronda';

  @override
  String nPropositionsPerRound(int count) {
    return 'Cada usuario puede enviar hasta $count propuestas por ronda';
  }

  @override
  String get adaptiveDuration => 'Duracion Adaptativa';

  @override
  String get adjustDurationDesc => 'Auto-ajustar la duracion de fase segun la participacion';

  @override
  String get durationAdjusts => 'La duracion se ajusta segun la participacion';

  @override
  String get fixedDurations => 'Duraciones de fase fijas';

  @override
  String get usesThresholds => 'Usa umbrales de avance temprano para determinar la participacion';

  @override
  String adjustmentPercent(int percent) {
    return 'Ajuste: $percent%';
  }

  @override
  String get minDuration => 'Duracion minima';

  @override
  String get maxDuration => 'Duracion maxima';

  @override
  String get aiParticipant => 'Participante IA';

  @override
  String get enableAI => 'Habilitar OneMind AI';

  @override
  String get aiPropositionsPerRound => 'Propuestas de IA por ronda';

  @override
  String get scheduleTypeLabel => 'Tipo de Horario';

  @override
  String get scheduleOneTime => 'Una vez';

  @override
  String get scheduleRecurring => 'Recurrente';

  @override
  String get hideOutsideSchedule => 'Ocultar fuera de horario';

  @override
  String get visiblePaused => 'Chat visible pero pausado fuera de horario';

  @override
  String get hiddenUntilWindow => 'Chat oculto hasta la proxima ventana programada';

  @override
  String get timezoneLabel => 'Zona Horaria';

  @override
  String get scheduleWindowsTitle => 'Ventanas de Horario';

  @override
  String get addWindowButton => 'Agregar Ventana';

  @override
  String get scheduleWindowsDesc => 'Define cuando el chat esta activo. Soporta ventanas nocturnas (ej., 11pm a 1am del dia siguiente).';

  @override
  String windowNumber(int n) {
    return 'Ventana $n';
  }

  @override
  String get removeWindow => 'Eliminar ventana';

  @override
  String get startDay => 'Dia de Inicio';

  @override
  String get endDay => 'Dia de Fin';

  @override
  String get daySun => 'Dom';

  @override
  String get dayMon => 'Lun';

  @override
  String get dayTue => 'Mar';

  @override
  String get dayWed => 'Mie';

  @override
  String get dayThu => 'Jue';

  @override
  String get dayFri => 'Vie';

  @override
  String get daySat => 'Sab';

  @override
  String get timerWarningTitle => 'Advertencia de Temporizador';

  @override
  String timerWarningContent(int minutes) {
    return 'Tus temporizadores de fase son mas largos que la ventana de $minutes minutos.\n\nLas fases pueden extenderse mas alla del tiempo programado, o pausarse cuando la ventana se cierre.\n\nConsidera usar temporizadores mas cortos (5 min o 30 min) para sesiones programadas.';
  }

  @override
  String get adjustSettingsButton => 'Ajustar Configuracion';

  @override
  String get continueAnywayButton => 'Continuar de Todos Modos';

  @override
  String get chatCreatedTitle => 'Chat Creado!';

  @override
  String get chatNowPublicTitle => 'Tu chat es ahora publico!';

  @override
  String anyoneCanJoinDiscover(String name) {
    return 'Cualquiera puede encontrar y unirse a \"$name\" desde la pagina Descubrir.';
  }

  @override
  String invitesSentTitle(int count) {
    return '$count invitaciones enviadas!';
  }

  @override
  String get noInvitesSentTitle => 'Sin invitaciones enviadas';

  @override
  String get inviteOnlyMessage => 'Solo usuarios invitados pueden unirse a este chat.';

  @override
  String get shareCodeInstruction => 'Comparte este codigo con los participantes:';

  @override
  String get codeCopied => 'Codigo de invitacion copiado';

  @override
  String get joinScreenTitle => 'Unirse al Chat';

  @override
  String get noTokenOrCode => 'No se proporciono token o codigo de invitacion';

  @override
  String get invalidExpiredInvite => 'Este enlace de invitacion es invalido o ha expirado';

  @override
  String get inviteOnlyError => 'Este chat requiere una invitacion por email. Por favor usa el enlace enviado a tu email.';

  @override
  String get invalidInviteTitle => 'Invitacion Invalida';

  @override
  String get invalidInviteDefault => 'Este enlace de invitacion no es valido.';

  @override
  String get invitedToJoin => 'Estas invitado a unirte';

  @override
  String get enterNameToJoin => 'Ingresa tu nombre para unirte:';

  @override
  String get nameVisibleNotice => 'Este nombre sera visible para otros participantes.';

  @override
  String get requiresApprovalNotice => 'Este chat requiere aprobacion del anfitrion para unirse.';

  @override
  String get requestToJoinButton => 'Solicitar Unirse';

  @override
  String get joinChatButton => 'Unirse al Chat';

  @override
  String get creditsTitle => 'Creditos';

  @override
  String get yourBalance => 'Tu Saldo';

  @override
  String get paidCredits => 'Creditos Pagados';

  @override
  String get freeThisMonth => 'Gratis Este Mes';

  @override
  String get totalAvailable => 'Total Disponible';

  @override
  String get userRounds => 'rondas-usuario';

  @override
  String freeTierResets(String date) {
    return 'El nivel gratuito se reinicia $date';
  }

  @override
  String get buyCredits => 'Comprar Creditos';

  @override
  String get pricingInfo => '1 credito = 1 ronda-usuario = \$0.01';

  @override
  String get total => 'Total';

  @override
  String get autoRefillTitle => 'Auto-Recarga';

  @override
  String get autoRefillDesc => 'Comprar creditos automaticamente cuando el saldo cae bajo el umbral';

  @override
  String lastError(String error) {
    return 'Ultimo error: $error';
  }

  @override
  String get autoRefillComingSoon => 'Configuracion de auto-recarga proximamente. Por ahora, compra creditos manualmente arriba.';

  @override
  String get whenBelow => 'Cuando este bajo';

  @override
  String get refillTo => 'Recargar a';

  @override
  String get disableAutoRefillMessage => 'Esto deshabilitara la auto-recarga. Puedes agregar un nuevo metodo de pago despues.';

  @override
  String get recentTransactions => 'Transacciones Recientes';

  @override
  String get noTransactionHistory => 'Sin historial de transacciones';

  @override
  String get chatSettingsTitle => 'Configuracion del Chat';

  @override
  String get accessVisibility => 'Acceso y Visibilidad';

  @override
  String get accessMethod => 'Metodo de Acceso';

  @override
  String get facilitation => 'Facilitacion';

  @override
  String get startMode => 'Modo de Inicio';

  @override
  String get autoStartThreshold => 'Umbral de Auto-Inicio';

  @override
  String nParticipants(int n) {
    return '$n participantes';
  }

  @override
  String get proposingDuration => 'Duracion de Propuestas';

  @override
  String get ratingDuration => 'Duracion de Calificacion';

  @override
  String nSeconds(int n) {
    return '$n segundos';
  }

  @override
  String nMinutes(int n) {
    return '$n minutos';
  }

  @override
  String nHours(int n) {
    return '$n horas';
  }

  @override
  String nDays(int n) {
    return '$n dias';
  }

  @override
  String get minimumRequirements => 'Requisitos Minimos';

  @override
  String nPropositions(int n) {
    return '$n propuestas';
  }

  @override
  String nAvgRaters(double n) {
    return '$n calificadores promedio por propuesta';
  }

  @override
  String get earlyAdvanceThresholds => 'Umbrales de Avance Temprano';

  @override
  String get proposingThreshold => 'Umbral de Propuestas';

  @override
  String get ratingThreshold => 'Umbral de Calificacion';

  @override
  String nConsecutiveWins(int n) {
    return '$n victorias consecutivas';
  }

  @override
  String get enabled => 'Habilitado';

  @override
  String nPerRound(int n) {
    return '$n por ronda';
  }

  @override
  String get scheduledStart => 'Inicio Programado';

  @override
  String get windows => 'Ventanas';

  @override
  String nConfigured(int n) {
    return '$n configuradas';
  }

  @override
  String get visibleOutsideSchedule => 'Visible Fuera de Horario';

  @override
  String get chatSettings => 'Configuración del Chat';

  @override
  String get chatName => 'Nombre';

  @override
  String get chatDescription => 'Descripción';

  @override
  String get accessAndVisibility => 'Acceso y Visibilidad';

  @override
  String get autoMode => 'Automático';

  @override
  String get avgRatersPerProposition => 'calificadores promedio por proposición';

  @override
  String get consensus => 'Consenso';

  @override
  String get aiPropositions => 'Proposiciones de IA';

  @override
  String get perRound => 'por ronda';

  @override
  String get schedule => 'Horario';

  @override
  String get configured => 'configurado';

  @override
  String get publicAccess => 'Público';

  @override
  String get inviteCodeAccess => 'Código de Invitación';

  @override
  String get inviteOnlyAccess => 'Solo por Invitación';

  @override
  String get privacyPolicyTitle => 'Politica de Privacidad';

  @override
  String get termsOfServiceTitle => 'Terminos de Servicio';

  @override
  String get legalDocuments => 'Legal';

  @override
  String get byContinuingYouAgree => 'By continuing, you agree to our';

  @override
  String get andText => 'and';

  @override
  String lastUpdated(String date) {
    return 'Ultima actualizacion: $date';
  }

  @override
  String shareLinkTitle(String chatName) {
    return 'Compartir enlace para unirse a $chatName';
  }

  @override
  String get shareButton => 'Compartir';

  @override
  String get copyLinkButton => 'Copiar Enlace';

  @override
  String get linkCopied => 'Enlace copiado al portapapeles';

  @override
  String get enterCodeManually => 'O ingresa el codigo manualmente:';

  @override
  String get shareNotSupported => 'Compartir no disponible - enlace copiado';

  @override
  String get orScan => 'o escanea';

  @override
  String get tutorialNextButton => 'Siguiente';

  @override
  String get tutorialChooseTemplate => 'Personaliza tu tutorial';

  @override
  String get tutorialChooseTemplateSubtitle => 'Elige un escenario que te importe';

  @override
  String get tutorialTemplateCommunity => 'Decisión comunitaria';

  @override
  String get tutorialTemplateCommunityDesc => '¿Qué debería hacer nuestro barrio juntos?';

  @override
  String get tutorialTemplateWorkplace => 'Cultura laboral';

  @override
  String get tutorialTemplateWorkplaceDesc => '¿En qué debería enfocarse nuestro equipo?';

  @override
  String get tutorialTemplateWorld => 'Temas globales';

  @override
  String get tutorialTemplateWorldDesc => '¿Qué problema global es más importante?';

  @override
  String get tutorialTemplateFamily => 'Familia';

  @override
  String get tutorialTemplateFamilyDesc => '¿Adónde deberíamos ir de vacaciones?';

  @override
  String get tutorialTemplatePersonal => 'Decisión personal';

  @override
  String get tutorialTemplatePersonalDesc => '¿Qué debería hacer después de graduarme?';

  @override
  String get tutorialTemplateGovernment => 'Presupuesto municipal';

  @override
  String get tutorialTemplateGovernmentDesc => '¿Cómo deberíamos gastar el presupuesto municipal?';

  @override
  String get tutorialTemplateCustom => 'Tema personalizado';

  @override
  String get tutorialTemplateCustomDesc => 'Escribe tu propia pregunta';

  @override
  String get tutorialCustomQuestionHint => 'Escribe tu pregunta...';

  @override
  String tutorialRound1ResultTemplate(String winner) {
    return '¡\'$winner\' ganó esta ronda! Para convertirse en respuesta permanente, debe ganar de nuevo en la próxima ronda.';
  }

  @override
  String tutorialRound2PromptTemplate(String winner) {
    return 'Viendo \'$winner\' como la respuesta actual del grupo, ¿puedes pensar en algo mejor?';
  }

  @override
  String get tutorialWelcomeTitle => 'Bienvenido a OneMind';

  @override
  String get tutorialWelcomeSubtitle => 'Aprende como los grupos alcanzan consenso juntos';

  @override
  String get tutorialWhatYoullLearn => 'En este tutorial:';

  @override
  String get tutorialBullet1 => 'Envia tus ideas de forma anonima';

  @override
  String get tutorialBullet2 => 'Califica ideas de otros';

  @override
  String get tutorialBullet3 => 'Ve como se alcanza el consenso';

  @override
  String get tutorialTheQuestion => 'La pregunta:';

  @override
  String get tutorialQuestion => 'Que valoramos?';

  @override
  String get tutorialStartButton => 'Iniciar Tutorial';

  @override
  String get tutorialSkipButton => 'Saltar tutorial';

  @override
  String get tutorialConsensusReached => 'Consenso Alcanzado!';

  @override
  String tutorialWonTwoRounds(String proposition) {
    return '\"$proposition\" gano 2 rondas seguidas.';
  }

  @override
  String get tutorialAddedToChat => 'Ahora se agrego al chat arriba.';

  @override
  String get tutorialFinishButton => 'Terminar Tutorial';

  @override
  String get tutorialRound1Result => '\'Exito\' gano esta ronda! Para ser una respuesta permanente, debe ganar de nuevo en la proxima ronda.';

  @override
  String get tutorialProposingHint => 'Envia una idea que quieras que sea la respuesta del grupo.';

  @override
  String get tutorialProposingHintWithWinner => 'Puedes pensar en algo mejor? Envia una idea para desafiar al ganador actual.';

  @override
  String get tutorialRatingHint => 'Para evitar sesgo, todos califican todas las ideas excepto la suya. La tuya esta oculta para ti pero otros la calificaran.';

  @override
  String get tutorialRatingBinaryHint => 'Cual idea prefieres? Colocala en la parte superior (100). Usa el boton de intercambio para invertirlas, luego toca la marca de verificacion para confirmar.';

  @override
  String get tutorialRatingPositioningHint => 'Usa las flechas para mover la idea resaltada hacia arriba o hacia abajo. Mas arriba = mas de acuerdo. Toca la marca de verificacion para colocarla.';

  @override
  String get tutorialRatingSwap => 'Intercambiar';

  @override
  String get tutorialRatingConfirm => 'Confirmar';

  @override
  String get tutorialRatingUp => 'Arriba';

  @override
  String get tutorialRatingDown => 'Abajo';

  @override
  String get tutorialRatingPlace => 'Colocar';

  @override
  String tutorialRound2Result(String proposition) {
    return 'Tu idea \"$proposition\" gano! Si gana en la proxima ronda, sera agregada permanentemente al chat.';
  }

  @override
  String get tutorialRound2Prompt => 'Viendo \'Exito\' como la respuesta actual del grupo - que crees que REALMENTE valoramos?';

  @override
  String get tutorialPropSuccess => 'Exito';

  @override
  String get tutorialPropAdventure => 'Aventura';

  @override
  String get tutorialPropGrowth => 'Crecimiento';

  @override
  String get tutorialPropHarmony => 'Armonia';

  @override
  String get tutorialPropInnovation => 'Innovacion';

  @override
  String get tutorialPropFreedom => 'Libertad';

  @override
  String get tutorialPropSecurity => 'Seguridad';

  @override
  String get tutorialPropStability => 'Estabilidad';

  @override
  String get tutorialPropTravelAbroad => 'Viajar al extranjero';

  @override
  String get tutorialPropStartABusiness => 'Iniciar un negocio';

  @override
  String get tutorialPropGraduateSchool => 'Posgrado';

  @override
  String get tutorialPropGetAJobFirst => 'Conseguir empleo';

  @override
  String get tutorialPropTakeAGapYear => 'Tomar un año sabático';

  @override
  String get tutorialPropFreelance => 'Freelance';

  @override
  String get tutorialPropMoveToANewCity => 'Mudarse de ciudad';

  @override
  String get tutorialPropVolunteerProgram => 'Voluntariado';

  @override
  String get tutorialPropBeachResort => 'Resort de playa';

  @override
  String get tutorialPropMountainCabin => 'Cabaña de montaña';

  @override
  String get tutorialPropCityTrip => 'Viaje urbano';

  @override
  String get tutorialPropRoadTrip => 'Viaje por carretera';

  @override
  String get tutorialPropCampingAdventure => 'Aventura de camping';

  @override
  String get tutorialPropCruise => 'Crucero';

  @override
  String get tutorialPropThemePark => 'Parque temático';

  @override
  String get tutorialPropCulturalExchange => 'Intercambio cultural';

  @override
  String get tutorialPropBlockParty => 'Fiesta de barrio';

  @override
  String get tutorialPropCommunityGarden => 'Huerto comunitario';

  @override
  String get tutorialPropNeighborhoodWatch => 'Vigilancia vecinal';

  @override
  String get tutorialPropToolLibrary => 'Biblioteca de herramientas';

  @override
  String get tutorialPropMutualAidFund => 'Fondo de ayuda mutua';

  @override
  String get tutorialPropFreeLittleLibrary => 'Biblioteca libre';

  @override
  String get tutorialPropStreetMural => 'Mural callejero';

  @override
  String get tutorialPropSkillShareNight => 'Noche de talentos';

  @override
  String get tutorialPropFlexibleHours => 'Horario flexible';

  @override
  String get tutorialPropMentalHealthSupport => 'Salud mental';

  @override
  String get tutorialPropTeamBuilding => 'Trabajo en equipo';

  @override
  String get tutorialPropSkillsTraining => 'Capacitación';

  @override
  String get tutorialPropOpenCommunication => 'Comunicación abierta';

  @override
  String get tutorialPropFairCompensation => 'Compensación justa';

  @override
  String get tutorialPropWorkLifeBalance => 'Equilibrio laboral';

  @override
  String get tutorialPropInnovationTime => 'Tiempo de innovación';

  @override
  String get tutorialPropPublicTransportation => 'Transporte público';

  @override
  String get tutorialPropSchoolFunding => 'Fondos escolares';

  @override
  String get tutorialPropEmergencyServices => 'Servicios de emergencia';

  @override
  String get tutorialPropRoadRepairs => 'Reparación de calles';

  @override
  String get tutorialPropPublicHealth => 'Salud pública';

  @override
  String get tutorialPropAffordableHousing => 'Vivienda accesible';

  @override
  String get tutorialPropSmallBusinessGrants => 'Becas para pymes';

  @override
  String get tutorialPropParksAndRecreation => 'Parques y recreación';

  @override
  String get tutorialPropClimateChange => 'Cambio climático';

  @override
  String get tutorialPropGlobalPoverty => 'Pobreza global';

  @override
  String get tutorialPropAiGovernance => 'Gobernanza de IA';

  @override
  String get tutorialPropPandemicPreparedness => 'Preparación pandémica';

  @override
  String get tutorialPropNuclearDisarmament => 'Desarme nuclear';

  @override
  String get tutorialPropOceanConservation => 'Conservación marina';

  @override
  String get tutorialPropDigitalRights => 'Derechos digitales';

  @override
  String get tutorialPropSpaceCooperation => 'Cooperación espacial';

  @override
  String get tutorialDuplicateProposition => 'Esta idea ya existe en esta ronda. Prueba algo diferente!';

  @override
  String get tutorialShareTitle => 'Comparte Tu Chat';

  @override
  String get tutorialShareExplanation => 'Para invitar a otros a unirse a tu chat, toca el boton de compartir en la parte superior de tu pantalla.';

  @override
  String get tutorialShareTryIt => 'Pruebalo ahora!';

  @override
  String get tutorialShareButtonHint => 'Toca el boton de compartir arriba a la derecha ↗';

  @override
  String get tutorialSkipMenuItem => 'Saltar Tutorial';

  @override
  String get tutorialSkipConfirmTitle => 'Saltar Tutorial?';

  @override
  String get tutorialSkipConfirmMessage => 'Siempre puedes acceder al tutorial mas tarde desde la pantalla de inicio.';

  @override
  String get tutorialSkipConfirmYes => 'Si, Saltar';

  @override
  String get tutorialSkipConfirmNo => 'Continuar Tutorial';

  @override
  String get tutorialShareTooltip => 'Compartir Chat';

  @override
  String get tutorialYourIdea => 'Tu idea';

  @override
  String get tutorialRateIdeas => 'Calificar Ideas';

  @override
  String get tutorialSeeResultsHint => 'Toca abajo para ver como se clasificaron todas las ideas.';

  @override
  String get tutorialSeeResultsContinueHint => 'Genial! Ahora entiendes como funciona la clasificacion. Continua para intentarlo de nuevo en la Ronda 2.';

  @override
  String get tutorialResultsBackHint => 'Presiona la flecha de retroceso cuando termines de ver los resultados.';

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
  String get wizardStep1Title => 'De que quieres hablar?';

  @override
  String get wizardStep1Subtitle => 'Este es el corazon de tu chat';

  @override
  String get wizardStep2Title => 'Establece el ritmo';

  @override
  String get wizardStep2Subtitle => 'Cuanto tiempo para cada fase?';

  @override
  String get wizardOneLastThing => 'Una ultima cosa...';

  @override
  String get wizardProposingLabel => 'Proponer (enviar ideas)';

  @override
  String get wizardRatingLabel => 'Calificar (clasificar ideas)';

  @override
  String get back => 'Atras';

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
