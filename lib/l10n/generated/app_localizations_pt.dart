// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class AppLocalizationsPt extends AppLocalizations {
  AppLocalizationsPt([String locale = 'pt']) : super(locale);

  @override
  String get appTitle => 'OneMind';

  @override
  String get howItWorks => 'Como funciona';

  @override
  String get discover => 'Descobrir';

  @override
  String get discoverPublicChats => 'Descobrir chats publicos';

  @override
  String get discoverChats => 'Descobrir Chats';

  @override
  String get joinWithCode => 'Entrar com Codigo';

  @override
  String get joinAnExistingChatWithInviteCode =>
      'Entrar em um chat existente com codigo de convite';

  @override
  String get joinChat => 'Entrar no Chat';

  @override
  String get join => 'Entrar';

  @override
  String get findChat => 'Buscar Chat';

  @override
  String get requestToJoin => 'Solicitar Entrada';

  @override
  String get createChat => 'Criar Chat';

  @override
  String get createANewChat => 'Criar um novo chat';

  @override
  String get chatCreated => 'Chat Criado!';

  @override
  String get cancel => 'Cancelar';

  @override
  String get continue_ => 'Continuar';

  @override
  String get retry => 'Tentar Novamente';

  @override
  String get yes => 'Sim';

  @override
  String get no => 'Nao';

  @override
  String get delete => 'Excluir';

  @override
  String get leave => 'Sair';

  @override
  String get kick => 'Remover';

  @override
  String get pause => 'Pausar';

  @override
  String get resume => 'Retomar';

  @override
  String get remove => 'Remover';

  @override
  String get clear => 'Limpar';

  @override
  String get done => 'Pronto';

  @override
  String get save => 'Salvar';

  @override
  String get officialOneMind => 'OneMind Oficial';

  @override
  String get official => 'OFICIAL';

  @override
  String get pending => 'PENDENTE';

  @override
  String get pendingRequests => 'Solicitacoes Pendentes';

  @override
  String get yourChats => 'Seus Chats';

  @override
  String get cancelRequest => 'Cancelar Solicitacao';

  @override
  String cancelRequestQuestion(String chatName) {
    return 'Cancelar sua solicitacao para entrar em \"$chatName\"?';
  }

  @override
  String get yesCancel => 'Sim, Cancelar';

  @override
  String get requestCancelled => 'Solicitacao cancelada';

  @override
  String get waitingForHostApproval => 'Aguardando aprovacao do anfitriao';

  @override
  String get hostApprovalRequired =>
      'O anfitriao deve aprovar cada solicitacao';

  @override
  String get noChatsYet => 'Nenhum chat ainda';

  @override
  String get discoverPublicChatsJoinOrCreate =>
      'Descubra chats publicos, entre com um codigo ou crie o seu';

  @override
  String get discoverPublicChatsButton => 'Descobrir Chats Publicos';

  @override
  String get noActiveChatsYet =>
      'Nenhum chat ativo ainda. Seus chats aprovados aparecerão aqui.';

  @override
  String get loadingChats => 'Carregando chats';

  @override
  String get failedToLoadChats => 'Falha ao carregar chats';

  @override
  String get chatNotFound => 'Chat nao encontrado';

  @override
  String get failedToLookupChat => 'Falha ao buscar chat';

  @override
  String failedToJoinChat(String error) {
    return 'Falha ao entrar no chat: $error';
  }

  @override
  String get enterInviteCode => 'Digite o codigo de convite de 6 caracteres:';

  @override
  String get pleaseEnterSixCharCode =>
      'Por favor, digite um codigo de 6 caracteres';

  @override
  String get inviteCodeHint => 'ABC123';

  @override
  String hostedBy(String hostName) {
    return 'Organizado por $hostName';
  }

  @override
  String get thisChatsRequiresInvite => 'Este chat requer um convite';

  @override
  String get enterEmailForInvite =>
      'Digite o email para o qual seu convite foi enviado:';

  @override
  String get yourEmailHint => 'seu@email.com';

  @override
  String get pleaseEnterEmailAddress =>
      'Por favor, digite seu endereco de email';

  @override
  String get pleaseEnterValidEmail => 'Por favor, digite um email valido';

  @override
  String get noInviteFoundForEmail =>
      'Nenhum convite encontrado para este email';

  @override
  String get failedToValidateInvite => 'Falha ao validar convite';

  @override
  String get pleaseVerifyEmailFirst =>
      'Por favor, verifique seu email primeiro';

  @override
  String get verifyEmail => 'Verificar Email';

  @override
  String emailVerified(String email) {
    return 'Email verificado: $email';
  }

  @override
  String get enterDisplayName => 'Digite seu nome de exibicao:';

  @override
  String get yourName => 'Seu Nome';

  @override
  String get yourNamePlaceholder => 'Seu Nome';

  @override
  String get displayName => 'Nome de exibicao';

  @override
  String get enterYourName => 'Digite seu nome';

  @override
  String get pleaseEnterYourName => 'Por favor, digite seu nome';

  @override
  String get yourDisplayName => 'Seu nome de exibicao';

  @override
  String get yourNameVisibleToAll =>
      'Seu nome sera visivel para todos os participantes';

  @override
  String get usingSavedName => 'Usando seu nome salvo';

  @override
  String get joinRequestSent =>
      'Solicitacao enviada. Aguardando aprovacao do anfitriao.';

  @override
  String get searchPublicChats => 'Buscar chats publicos...';

  @override
  String noChatsFoundFor(String query) {
    return 'Nenhum chat encontrado para \"$query\"';
  }

  @override
  String get noPublicChatsAvailable => 'Nenhum chat publico disponivel';

  @override
  String get beFirstToCreate => 'Seja o primeiro a criar um!';

  @override
  String failedToLoadPublicChats(String error) {
    return 'Falha ao carregar chats publicos: $error';
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
  String get enterYourNameTitle => 'Digite Seu Nome';

  @override
  String get anonymous => 'Anonimo';

  @override
  String get timerWarning => 'Aviso de Temporizador';

  @override
  String timerWarningMessage(int minutes) {
    return 'Seus temporizadores de fase sao mais longos que a janela de $minutes minutos programada.\n\nAs fases podem se estender alem do tempo programado ou pausar quando a janela fechar.\n\nConsidere usar temporizadores mais curtos (5 min ou 30 min) para sessoes programadas.';
  }

  @override
  String get adjustSettings => 'Ajustar Configuracoes';

  @override
  String get continueAnyway => 'Continuar Mesmo Assim';

  @override
  String get chatNowPublic => 'Seu chat agora e publico!';

  @override
  String anyoneCanJoinFrom(String chatName) {
    return 'Qualquer pessoa pode encontrar e entrar em \"$chatName\" na pagina Descobrir.';
  }

  @override
  String invitesSent(int count) {
    return '$count convite enviado!';
  }

  @override
  String invitesSentPlural(int count) {
    return '$count convites enviados!';
  }

  @override
  String get noInvitesSent => 'Nenhum convite enviado';

  @override
  String get onlyInvitedUsersCanJoin =>
      'Apenas usuarios convidados podem entrar neste chat.';

  @override
  String get shareCodeWithParticipants =>
      'Compartilhe este codigo com os participantes:';

  @override
  String get inviteCodeCopied => 'Codigo de convite copiado';

  @override
  String get tapToCopy => 'Toque para copiar';

  @override
  String get showQrCode => 'Mostrar Codigo QR';

  @override
  String get addEmailForInviteOnly =>
      'Adicione pelo menos um email para o modo somente convite';

  @override
  String get emailAlreadyAdded => 'Email ja adicionado';

  @override
  String get settings => 'Configuracoes';

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
  String get rankPropositions => 'Classificar Propostas';

  @override
  String get placing => 'Colocando: ';

  @override
  String rankedSuccessfully(int count) {
    return '$count propostas classificadas com sucesso!';
  }

  @override
  String get failedToSaveRankings => 'Falha ao salvar classificacoes';

  @override
  String get chatPausedByHost => 'Chat pausado pelo anfitriao';

  @override
  String get ratingPhaseEnded => 'Fase de avaliacao terminou';

  @override
  String get goBack => 'Voltar';

  @override
  String get ratePropositions => 'Avaliar Propostas';

  @override
  String get submitRatings => 'Enviar Avaliacoes';

  @override
  String failedToSubmitRatings(String error) {
    return 'Falha ao enviar avaliacoes: $error';
  }

  @override
  String roundResults(int roundNumber) {
    return 'Resultados da Rodada $roundNumber';
  }

  @override
  String get noPropositionsToDisplay => 'Nenhuma proposta para exibir';

  @override
  String get noPreviousWinner => 'Nenhum vencedor anterior';

  @override
  String roundWinner(int roundNumber) {
    return 'Vencedor da Rodada $roundNumber';
  }

  @override
  String roundWinners(int roundNumber) {
    return 'Vencedores da Rodada $roundNumber';
  }

  @override
  String get unknownProposition => 'Proposta desconhecida';

  @override
  String score(String score) {
    return 'Pontuacao: $score';
  }

  @override
  String soleWinsProgress(int current, int required) {
    return 'Vitorias unicas: $current/$required';
  }

  @override
  String get tiedWinNoConsensus => 'Empate (nao conta para a convergencia)';

  @override
  String nWayTie(int count) {
    return '$count-WAY TIE';
  }

  @override
  String winnerIndexOfTotal(int current, int total) {
    return '$current of $total';
  }

  @override
  String get seeAllResults => 'Ver Todos os Resultados';

  @override
  String get startPhase => 'Iniciar Fase';

  @override
  String get waiting => 'Aguardando';

  @override
  String get waitingForHostToStart => 'Aguardando o anfitriao iniciar...';

  @override
  String roundNumber(int roundNumber) {
    return 'Rodada $roundNumber';
  }

  @override
  String get viewAllPropositions => 'Ver todas as propostas';

  @override
  String get chatIsPaused => 'Chat pausado...';

  @override
  String get shareYourIdea => 'Compartilhe sua ideia...';

  @override
  String get addAnotherIdea => 'Adicionar outra ideia...';

  @override
  String get submit => 'Enviar';

  @override
  String get addProposition => 'Adicionar Proposta';

  @override
  String get waitingForRatingPhase => 'Aguardando fase de avaliacao...';

  @override
  String get endProposingStartRating =>
      'Encerrar Propostas e Iniciar Avaliacao';

  @override
  String get proposingComplete => 'Propostas Completas';

  @override
  String get reviewPropositionsStartRating =>
      'Revise as propostas e inicie a avaliacao quando estiver pronto.';

  @override
  String get waitingForHostToStartRating =>
      'Aguardando o anfitriao iniciar a fase de avaliacao.';

  @override
  String get startRatingPhase => 'Iniciar Fase de Avaliacao';

  @override
  String get ratingComplete => 'Avaliacao Completa';

  @override
  String get waitingForRatingPhaseEnd =>
      'Aguardando o fim da fase de avaliacao.';

  @override
  String rateAllPropositions(int count) {
    return 'Avalie todas as $count propostas';
  }

  @override
  String get continueRating => 'Continuar Avaliando';

  @override
  String get startRating => 'Iniciar Avaliacao';

  @override
  String get endRatingStartNextRound =>
      'Encerrar Avaliacao e Iniciar Proxima Rodada';

  @override
  String get chatPaused => 'Chat Pausado';

  @override
  String get chatPausedByHostTitle => 'Chat Pausado pelo Anfitriao';

  @override
  String get timerStoppedTapResume =>
      'O temporizador esta parado. Toque em Retomar na barra para continuar.';

  @override
  String get hostPausedPleaseWait =>
      'O anfitriao pausou este chat. Por favor, aguarde a retomada.';

  @override
  String get previousWinner => 'Vencedor Anterior';

  @override
  String get yourProposition => 'Sua Proposta';

  @override
  String get yourPropositions => 'Suas Propostas';

  @override
  String get rate => 'Avaliar';

  @override
  String get participants => 'Participantes';

  @override
  String get chatInfo => 'Info do Chat';

  @override
  String get shareQrCode => 'Compartilhar Codigo QR';

  @override
  String get joinRequests => 'Solicitacoes de Entrada';

  @override
  String get resumeChat => 'Retomar Chat';

  @override
  String get pauseChat => 'Pausar Chat';

  @override
  String get leaveChat => 'Sair do Chat';

  @override
  String get deleteChat => 'Excluir Chat';

  @override
  String get host => 'Anfitriao';

  @override
  String get deletePropositionQuestion => 'Excluir Proposta?';

  @override
  String get areYouSureDeleteProposition =>
      'Tem certeza de que deseja excluir esta proposta?';

  @override
  String get deleteChatQuestion => 'Excluir Chat?';

  @override
  String get leaveChatQuestion => 'Sair do Chat?';

  @override
  String get kickParticipantQuestion => 'Remover Participante?';

  @override
  String get pauseChatQuestion => 'Pausar Chat?';

  @override
  String get removePaymentMethodQuestion => 'Remover Metodo de Pagamento?';

  @override
  String get propositionDeleted => 'Proposta excluida';

  @override
  String get chatDeleted => 'Chat excluido';

  @override
  String get youHaveLeftChat => 'Voce saiu do chat';

  @override
  String get youHaveBeenRemoved => 'Voce foi removido deste chat';

  @override
  String get chatHasBeenDeleted => 'Este chat foi excluido';

  @override
  String participantRemoved(String name) {
    return '$name foi removido';
  }

  @override
  String get chatPausedSuccess => 'Chat pausado';

  @override
  String get requestApproved => 'Solicitacao aprovada';

  @override
  String get requestDenied => 'Solicitacao negada';

  @override
  String failedToSubmit(String error) {
    return 'Falha ao enviar: $error';
  }

  @override
  String get duplicateProposition => 'Esta proposta ja existe nesta rodada';

  @override
  String failedToStartPhase(String error) {
    return 'Falha ao iniciar fase: $error';
  }

  @override
  String failedToAdvancePhase(String error) {
    return 'Falha ao avancar fase: $error';
  }

  @override
  String failedToCompleteRating(String error) {
    return 'Falha ao completar avaliacao: $error';
  }

  @override
  String failedToDelete(String error) {
    return 'Falha ao excluir: $error';
  }

  @override
  String failedToDeleteChat(String error) {
    return 'Falha ao excluir chat: $error';
  }

  @override
  String failedToLeaveChat(String error) {
    return 'Falha ao sair do chat: $error';
  }

  @override
  String failedToKickParticipant(String error) {
    return 'Falha ao remover participante: $error';
  }

  @override
  String failedToPauseChat(String error) {
    return 'Falha ao pausar chat: $error';
  }

  @override
  String error(String error) {
    return 'Erro: $error';
  }

  @override
  String get noPendingRequests => 'Nenhuma solicitacao pendente';

  @override
  String get newRequestsWillAppear => 'Novas solicitacoes aparecerão aqui';

  @override
  String participantsJoined(int count) {
    return '$count participantes entraram';
  }

  @override
  String waitingForMoreParticipants(int count) {
    return 'Aguardando mais $count participante(s)';
  }

  @override
  String get noMembersYetShareHint =>
      'Ainda sem outros membros. Toque no botao de compartilhar acima para convidar pessoas.';

  @override
  String get scheduled => 'Programado';

  @override
  String get chatOutsideSchedule => 'Chat fora da janela programada';

  @override
  String nextWindowStarts(String dateTime) {
    return 'Proxima janela comeca $dateTime';
  }

  @override
  String get scheduleWindows => 'Janelas programadas:';

  @override
  String get scheduledToStart => 'Programado para iniciar';

  @override
  String get chatWillAutoStart =>
      'O chat iniciara automaticamente no horario programado.';

  @override
  String submittedCount(int submitted, int total) {
    return '$submitted/$total enviados';
  }

  @override
  String propositionCollected(int count) {
    return '$count proposta coletada';
  }

  @override
  String propositionsCollected(int count) {
    return '$count propostas coletadas';
  }

  @override
  String get timeExpired => 'Tempo expirado';

  @override
  String get noDataAvailable => 'Nenhum dado disponivel';

  @override
  String get tryAgain => 'Tentar Novamente';

  @override
  String get requireApproval => 'Requer aprovacao';

  @override
  String get requireAuthentication => 'Requer autenticacao';

  @override
  String get showPreviousResults =>
      'Mostrar resultados completos de rodadas anteriores';

  @override
  String get enableAdaptiveDuration => 'Habilitar duracao adaptativa';

  @override
  String get enableOneMindAI => 'Habilitar OneMind AI';

  @override
  String get enableAutoAdvanceProposing => 'Habilitar para ideias';

  @override
  String get enableAutoAdvanceRating => 'Habilitar para avaliacoes';

  @override
  String get hideWhenOutsideSchedule => 'Ocultar fora do horario';

  @override
  String get chatVisibleButPaused => 'Chat visivel mas pausado fora do horario';

  @override
  String get chatHiddenUntilNext =>
      'Chat oculto ate a proxima janela programada';

  @override
  String get timezone => 'Fuso horario';

  @override
  String get scheduleType => 'Tipo de Agenda';

  @override
  String get oneTime => 'Unica vez';

  @override
  String get recurring => 'Recorrente';

  @override
  String get startDateTime => 'Data e Hora de Inicio';

  @override
  String get scheduleWindowsLabel => 'Janelas de Agenda';

  @override
  String get addWindow => 'Adicionar Janela';

  @override
  String get searchTimezone => 'Buscar fuso horario...';

  @override
  String get manual => 'Manual';

  @override
  String get auto => 'Automatico';

  @override
  String get credits => 'Creditos';

  @override
  String get refillAmountMustBeGreater =>
      'O valor de recarga deve ser maior que o limite';

  @override
  String get autoRefillSettingsUpdated =>
      'Configuracoes de recarga automatica atualizadas';

  @override
  String get autoRefillEnabled => 'Recarga automatica habilitada';

  @override
  String get autoRefillDisabled => 'Recarga automatica desabilitada';

  @override
  String get saveSettings => 'Salvar Configuracoes';

  @override
  String get removeCard => 'Remover Cartao';

  @override
  String get purchaseWithStripe => 'Comprar com Stripe';

  @override
  String get processing => 'Processando...';

  @override
  String get pageNotFound => 'Pagina Nao Encontrada';

  @override
  String get goHome => 'Ir para Inicio';

  @override
  String allPropositionsCount(int count) {
    return 'Todas as Propostas ($count)';
  }

  @override
  String get hostCanModerateContent =>
      'Como anfitriao, voce pode moderar o conteudo. A identidade do remetente esta oculta.';

  @override
  String get yourPropositionLabel => '(Sua proposta)';

  @override
  String get previousWinnerLabel => '(Vencedor anterior)';

  @override
  String get cannotBeUndone => 'Esta acao nao pode ser desfeita.';

  @override
  String deleteChatConfirmation(String chatName) {
    return 'Tem certeza de que deseja excluir \"$chatName\"?\n\nIsso excluira permanentemente todas as propostas, avaliacoes e historico. Esta acao nao pode ser desfeita.';
  }

  @override
  String leaveChatConfirmation(String chatName) {
    return 'Tem certeza de que deseja sair de \"$chatName\"?\n\nVoce nao vera mais este chat na sua lista.';
  }

  @override
  String kickParticipantConfirmation(String participantName) {
    return 'Tem certeza de que deseja remover \"$participantName\" deste chat?\n\nEle nao podera entrar novamente sem aprovacao.';
  }

  @override
  String get pauseChatConfirmation =>
      'Isso pausara o temporizador da fase atual. Os participantes verao que o chat foi pausado pelo anfitriao.';

  @override
  String get approveOrDenyRequests =>
      'Aprovar ou negar solicitacoes para entrar neste chat.';

  @override
  String get signedIn => 'Conectado';

  @override
  String get guest => 'Convidado';

  @override
  String get approve => 'Aprovar';

  @override
  String get deny => 'Negar';

  @override
  String get initialMessage => 'Mensagem Inicial';

  @override
  String consensusNumber(int number) {
    return 'Convergencia #$number';
  }

  @override
  String get kickParticipant => 'Remover participante';

  @override
  String get propositions => 'Propostas';

  @override
  String get leaderboard => 'Classificacao';

  @override
  String get noLeaderboardData => 'Nenhum dado de classificacao disponivel';

  @override
  String get skip => 'Pular';

  @override
  String get skipped => 'Pulado';

  @override
  String skipsRemaining(int remaining) {
    return '$remaining pulos restantes';
  }

  @override
  String get createChatTitle => 'Criar Chat';

  @override
  String get enterYourNameLabel => 'Digite seu nome';

  @override
  String get nameVisibleToAll =>
      'Seu nome sera visivel para todos os participantes';

  @override
  String get basicInfo => 'Informacoes Basicas';

  @override
  String get chatNameRequired => 'Nome do Chat *';

  @override
  String get chatNameHint => 'ex., Almoco da Equipe Sexta';

  @override
  String get required => 'Obrigatorio';

  @override
  String get initialMessageRequired => 'Mensagem Inicial *';

  @override
  String get initialMessageOptional => 'Mensagem Inicial (Opcional)';

  @override
  String get initialMessageHint => 'O topico ou pergunta inicial';

  @override
  String get initialMessageHelperText =>
      'Os participantes saberao que voce escreveu isso ja que voce criou o chat';

  @override
  String get descriptionOptional => 'Descricao (Opcional)';

  @override
  String get descriptionHint => 'Contexto adicional';

  @override
  String get visibility => 'Visibilidade';

  @override
  String get whoCanJoin => 'Quem pode encontrar e entrar neste chat?';

  @override
  String get accessPublic => 'Publico';

  @override
  String get accessPublicDesc => 'Qualquer pessoa pode descobrir e entrar';

  @override
  String get accessCode => 'Codigo de Convite';

  @override
  String get accessCodeDesc =>
      'Compartilhe um codigo de 6 caracteres para entrar';

  @override
  String get accessEmail => 'Apenas por Email';

  @override
  String get accessEmailDesc =>
      'Apenas enderecos de email convidados podem entrar';

  @override
  String get instantJoin => 'Usuarios entram instantaneamente';

  @override
  String get inviteByEmail => 'Convidar por Email';

  @override
  String get inviteEmailOnly =>
      'Apenas enderecos de email convidados podem entrar neste chat';

  @override
  String get emailAddress => 'Endereco de email';

  @override
  String get emailHint => 'usuario@exemplo.com';

  @override
  String get invalidEmail => 'Por favor, digite um email valido';

  @override
  String get addEmailToSend =>
      'Adicione pelo menos um email para enviar convites';

  @override
  String get facilitationMode => 'Como as Fases Funcionam';

  @override
  String get facilitationDesc =>
      'Escolha entre controle manual ou temporizadores automaticos para transicoes de fase.';

  @override
  String get modeManual => 'Manual';

  @override
  String get modeAuto => 'Automatico';

  @override
  String get modeManualDesc =>
      'Voce controla quando cada fase comeca e termina. Sem temporizadores.';

  @override
  String get modeAutoDesc =>
      'Os temporizadores funcionam automaticamente. Voce ainda pode terminar fases antes.';

  @override
  String get autoStartParticipants => 'Iniciar quando este numero entrar';

  @override
  String get ratingStartMode => 'Modo de Inicio da Avaliacao';

  @override
  String get ratingStartModeDesc =>
      'Controla como a fase de avaliacao comeca apos o fim das propostas.';

  @override
  String get ratingAutoDesc =>
      'A avaliacao comeca imediatamente apos o fim das propostas ou quando o limite e atingido.';

  @override
  String get ratingManualDesc =>
      'Apos o fim das propostas, voce escolhe quando iniciar a avaliacao (ex., no dia seguinte).';

  @override
  String phaseFlowExplanation(String duration, int threshold, int minimum) {
    return 'Cada fase dura ate $duration, mas termina antes se $threshold pessoas participarem. Nao terminara ate que existam pelo menos $minimum ideias (o temporizador se estende se necessario).';
  }

  @override
  String get enableSchedule => 'Habilitar Agenda';

  @override
  String get restrictChatRoom => 'Restringir quando a sala de chat esta aberta';

  @override
  String get timers => 'Temporizadores';

  @override
  String get useSameDuration => 'Mesma duracao para ambas as fases';

  @override
  String get useSameDurationDesc =>
      'Usar o mesmo limite de tempo para propostas e avaliacao';

  @override
  String get phaseDuration => 'Duracao da Fase';

  @override
  String get proposing => 'Propostas';

  @override
  String get rating => 'Avaliacao';

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
  String get minimumToAdvance => 'Participacao Obrigatoria';

  @override
  String get timeExtendsAutomatically =>
      'A fase nao terminara ate que os requisitos sejam atendidos';

  @override
  String get proposingMinimum => 'Ideias necessarias';

  @override
  String proposingMinimumDesc(int count) {
    return 'A fase nao terminara ate que $count ideias sejam enviadas';
  }

  @override
  String get ratingMinimum => 'Avaliacoes necessarias';

  @override
  String ratingMinimumDesc(int count) {
    return 'A fase nao terminara ate que cada ideia tenha $count avaliacoes';
  }

  @override
  String get autoAdvanceAt => 'Terminar Fase Antes';

  @override
  String get skipTimerEarly =>
      'A fase pode terminar antes quando os limites forem atingidos';

  @override
  String whenPercentSubmit(int percent) {
    return 'Quando $percent% dos participantes enviam';
  }

  @override
  String get minParticipantsSubmit => 'Ideias necessarias';

  @override
  String get minAvgRaters => 'Avaliacoes necessarias';

  @override
  String proposingThresholdPreview(
    int threshold,
    int participants,
    int percent,
  ) {
    return 'A fase termina antes quando $threshold de $participants participantes enviam ideias ($percent%)';
  }

  @override
  String proposingThresholdPreviewSimple(int threshold) {
    return 'A fase termina antes quando $threshold ideias sao enviadas';
  }

  @override
  String ratingThresholdPreview(int threshold) {
    return 'A fase termina antes quando cada ideia tem $threshold avaliacoes';
  }

  @override
  String get consensusSettings => 'Configuracoes de Convergencia';

  @override
  String get confirmationRounds => 'Rodadas de confirmacao';

  @override
  String get firstWinnerConsensus =>
      'O primeiro vencedor alcanca convergencia imediatamente';

  @override
  String mustWinConsecutive(int count) {
    return 'A mesma proposta deve vencer $count rodadas consecutivas';
  }

  @override
  String get showFullResults =>
      'Mostrar resultados completos de rodadas anteriores';

  @override
  String get seeAllPropositions =>
      'Usuarios veem todas as propostas e avaliacoes';

  @override
  String get seeWinningOnly => 'Usuarios veem apenas a proposta vencedora';

  @override
  String get propositionLimits => 'Limites de Propostas';

  @override
  String get propositionsPerUser => 'Propostas por usuario';

  @override
  String get onePropositionPerRound =>
      'Cada usuario pode enviar 1 proposta por rodada';

  @override
  String nPropositionsPerRound(int count) {
    return 'Cada usuario pode enviar ate $count propostas por rodada';
  }

  @override
  String get adaptiveDuration => 'Duracao Adaptativa';

  @override
  String get adjustDurationDesc =>
      'Auto-ajustar a duracao da fase com base na participacao';

  @override
  String get durationAdjusts => 'A duracao se ajusta com base na participacao';

  @override
  String get fixedDurations => 'Duracoes de fase fixas';

  @override
  String get usesThresholds =>
      'Usa limites de avanco antecipado para determinar a participacao';

  @override
  String adjustmentPercent(int percent) {
    return 'Ajuste: $percent%';
  }

  @override
  String get minDuration => 'Duracao minima';

  @override
  String get maxDuration => 'Duracao maxima';

  @override
  String get aiParticipant => 'Participante IA';

  @override
  String get enableAI => 'Habilitar OneMind AI';

  @override
  String get aiPropositionsPerRound => 'Propostas de IA por rodada';

  @override
  String get scheduleTypeLabel => 'Tipo de Agenda';

  @override
  String get scheduleOneTime => 'Uma vez';

  @override
  String get scheduleRecurring => 'Recorrente';

  @override
  String get hideOutsideSchedule => 'Ocultar fora da agenda';

  @override
  String get visiblePaused => 'Chat visivel mas pausado fora da agenda';

  @override
  String get hiddenUntilWindow => 'Chat oculto ate a proxima janela agendada';

  @override
  String get timezoneLabel => 'Fuso Horario';

  @override
  String get scheduleWindowsTitle => 'Janelas de Agenda';

  @override
  String get addWindowButton => 'Adicionar Janela';

  @override
  String get scheduleWindowsDesc =>
      'Defina quando o chat esta ativo. Suporta janelas noturnas (ex., 23h ate 1h do dia seguinte).';

  @override
  String windowNumber(int n) {
    return 'Janela $n';
  }

  @override
  String get removeWindow => 'Remover janela';

  @override
  String get startDay => 'Dia de Inicio';

  @override
  String get endDay => 'Dia de Fim';

  @override
  String get daySun => 'Dom';

  @override
  String get dayMon => 'Seg';

  @override
  String get dayTue => 'Ter';

  @override
  String get dayWed => 'Qua';

  @override
  String get dayThu => 'Qui';

  @override
  String get dayFri => 'Sex';

  @override
  String get daySat => 'Sab';

  @override
  String get timerWarningTitle => 'Aviso de Temporizador';

  @override
  String timerWarningContent(int minutes) {
    return 'Seus temporizadores de fase sao mais longos que a janela de $minutes minutos.\n\nAs fases podem se estender alem do tempo agendado, ou pausar quando a janela fechar.\n\nConsidere usar temporizadores mais curtos (5 min ou 30 min) para sessoes agendadas.';
  }

  @override
  String get adjustSettingsButton => 'Ajustar Configuracoes';

  @override
  String get continueAnywayButton => 'Continuar Mesmo Assim';

  @override
  String get chatCreatedTitle => 'Chat Criado!';

  @override
  String get chatNowPublicTitle => 'Seu chat agora e publico!';

  @override
  String anyoneCanJoinDiscover(String name) {
    return 'Qualquer pessoa pode encontrar e entrar em \"$name\" na pagina Descobrir.';
  }

  @override
  String invitesSentTitle(int count) {
    return '$count convites enviados!';
  }

  @override
  String get noInvitesSentTitle => 'Nenhum convite enviado';

  @override
  String get inviteOnlyMessage =>
      'Apenas usuarios convidados podem entrar neste chat.';

  @override
  String get shareCodeInstruction =>
      'Compartilhe este codigo com os participantes:';

  @override
  String get codeCopied => 'Codigo de convite copiado';

  @override
  String get joinScreenTitle => 'Entrar no Chat';

  @override
  String get noTokenOrCode => 'Nenhum token ou codigo de convite fornecido';

  @override
  String get invalidExpiredInvite =>
      'Este link de convite e invalido ou expirou';

  @override
  String get inviteOnlyError =>
      'Este chat requer um convite por email. Por favor, use o link enviado para seu email.';

  @override
  String get invalidInviteTitle => 'Convite Invalido';

  @override
  String get invalidInviteDefault => 'Este link de convite nao e valido.';

  @override
  String get invitedToJoin => 'Voce foi convidado a entrar';

  @override
  String get enterNameToJoin => 'Digite seu nome para entrar:';

  @override
  String get nameVisibleNotice =>
      'Este nome sera visivel para outros participantes.';

  @override
  String get requiresApprovalNotice =>
      'Este chat requer aprovacao do anfitriao para entrar.';

  @override
  String get requestToJoinButton => 'Solicitar Entrada';

  @override
  String get joinChatButton => 'Entrar no Chat';

  @override
  String get creditsTitle => 'Creditos';

  @override
  String get yourBalance => 'Seu Saldo';

  @override
  String get paidCredits => 'Creditos Pagos';

  @override
  String get freeThisMonth => 'Gratis Este Mes';

  @override
  String get totalAvailable => 'Total Disponivel';

  @override
  String get userRounds => 'rodadas-usuario';

  @override
  String freeTierResets(String date) {
    return 'O nivel gratuito reinicia $date';
  }

  @override
  String get buyCredits => 'Comprar Creditos';

  @override
  String get pricingInfo => '1 credito = 1 rodada-usuario = \$0.01';

  @override
  String get total => 'Total';

  @override
  String get autoRefillTitle => 'Auto-Recarga';

  @override
  String get autoRefillDesc =>
      'Comprar creditos automaticamente quando o saldo cai abaixo do limite';

  @override
  String lastError(String error) {
    return 'Ultimo erro: $error';
  }

  @override
  String get autoRefillComingSoon =>
      'Configuracao de auto-recarga em breve. Por enquanto, compre creditos manualmente acima.';

  @override
  String get whenBelow => 'Quando abaixo de';

  @override
  String get refillTo => 'Recarregar para';

  @override
  String get disableAutoRefillMessage =>
      'Isso desabilitara a auto-recarga. Voce pode adicionar um novo metodo de pagamento depois.';

  @override
  String get recentTransactions => 'Transacoes Recentes';

  @override
  String get noTransactionHistory => 'Sem historico de transacoes';

  @override
  String get chatSettingsTitle => 'Configuracoes do Chat';

  @override
  String get accessVisibility => 'Acesso e Visibilidade';

  @override
  String get accessMethod => 'Metodo de Acesso';

  @override
  String get facilitation => 'Facilitacao';

  @override
  String get startMode => 'Modo de Inicio';

  @override
  String get autoStartThreshold => 'Limite de Auto-Inicio';

  @override
  String nParticipants(int n) {
    return '$n participantes';
  }

  @override
  String get proposingDuration => 'Duracao de Propostas';

  @override
  String get ratingDuration => 'Duracao de Avaliacao';

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
    return '$n propostas';
  }

  @override
  String nAvgRaters(double n) {
    return '$n avaliadores em media por proposta';
  }

  @override
  String get earlyAdvanceThresholds => 'Limites de Avanco Antecipado';

  @override
  String get proposingThreshold => 'Limite de Propostas';

  @override
  String get ratingThreshold => 'Limite de Avaliacao';

  @override
  String nConsecutiveWins(int n) {
    return '$n vitorias consecutivas';
  }

  @override
  String get enabled => 'Habilitado';

  @override
  String nPerRound(int n) {
    return '$n por rodada';
  }

  @override
  String get scheduledStart => 'Inicio Agendado';

  @override
  String get windows => 'Janelas';

  @override
  String nConfigured(int n) {
    return '$n configuradas';
  }

  @override
  String get visibleOutsideSchedule => 'Visivel Fora da Agenda';

  @override
  String get chatSettings => 'Configurações do Chat';

  @override
  String get chatName => 'Nome';

  @override
  String get chatDescription => 'Descrição';

  @override
  String get accessAndVisibility => 'Acesso e Visibilidade';

  @override
  String get autoMode => 'Automático';

  @override
  String get avgRatersPerProposition => 'avaliadores médios por proposição';

  @override
  String get consensus => 'Convergencia';

  @override
  String get aiPropositions => 'Proposições de IA';

  @override
  String get perRound => 'por rodada';

  @override
  String get schedule => 'Agenda';

  @override
  String get configured => 'configurado';

  @override
  String get publicAccess => 'Público';

  @override
  String get inviteCodeAccess => 'Código de Convite';

  @override
  String get inviteOnlyAccess => 'Somente por Convite';

  @override
  String get privacyPolicyTitle => 'Politica de Privacidade';

  @override
  String get termsOfServiceTitle => 'Termos de Servico';

  @override
  String get legalDocuments => 'Legal';

  @override
  String get byContinuingYouAgree => 'By continuing, you agree to our';

  @override
  String get andText => 'and';

  @override
  String lastUpdated(String date) {
    return 'Ultima atualizacao: $date';
  }

  @override
  String shareLinkTitle(String chatName) {
    return 'Compartilhar link para entrar em $chatName';
  }

  @override
  String get shareButton => 'Compartilhar';

  @override
  String get copyLinkButton => 'Copiar Link';

  @override
  String get linkCopied => 'Link copiado para a area de transferencia';

  @override
  String get enterCodeManually => 'Ou digite o codigo manualmente:';

  @override
  String get shareNotSupported =>
      'Compartilhamento nao disponivel - link copiado';

  @override
  String get orScan => 'ou escaneie';

  @override
  String get tutorialTemplateCommunity => 'Decisão comunitária';

  @override
  String get tutorialTemplateCommunityDesc =>
      'O que nosso bairro deveria fazer junto?';

  @override
  String get tutorialTemplateWorkplace => 'Cultura de trabalho';

  @override
  String get tutorialTemplateWorkplaceDesc =>
      'No que nossa equipe deveria focar?';

  @override
  String get tutorialTemplateWorld => 'Questões globais';

  @override
  String get tutorialTemplateWorldDesc =>
      'Qual questão global é mais importante?';

  @override
  String get tutorialTemplateFamily => 'Família';

  @override
  String get tutorialTemplateFamilyDesc => 'Para onde devemos ir de férias?';

  @override
  String get tutorialTemplatePersonal => 'Decisão pessoal';

  @override
  String get tutorialTemplatePersonalDesc =>
      'O que devo fazer depois de me formar?';

  @override
  String get tutorialTemplateGovernment => 'Orçamento municipal';

  @override
  String get tutorialTemplateGovernmentDesc =>
      'Como devemos gastar o orçamento municipal?';

  @override
  String get tutorialTemplateCustom => 'Tema personalizado';

  @override
  String get tutorialTemplateCustomDesc => 'Digite sua própria pergunta';

  @override
  String get tutorialCustomQuestionHint => 'Digite sua pergunta...';

  @override
  String tutorialRound1ResultTemplate(String winner) {
    return '\'$winner\' venceu esta rodada! Mas ainda não é definitivo. Precisa vencer a próxima rodada para ser adicionado permanentemente ao chat do grupo.';
  }

  @override
  String tutorialRound2PromptTemplate(String winner) {
    return 'O vencedor \'$winner\' e automaticamente levado para competir novamente. Precisa vencer 2 rodadas seguidas para se tornar uma resposta permanente.';
  }

  @override
  String get tutorialAppBarTitle => 'Tutorial do OneMind';

  @override
  String get tutorialWelcomeTitle => 'Bem-vindo!';

  @override
  String get tutorialWelcomeSubtitle => 'Escolha um cenário de prática';

  @override
  String get tutorialTheQuestion => 'A pergunta:';

  @override
  String get tutorialQuestion => 'O que valorizamos?';

  @override
  String get tutorialStartButton => 'Iniciar Tutorial';

  @override
  String get tutorialSkipButton => 'Pular tutorial';

  @override
  String get tutorialConsensusReached => 'Convergencia Alcancada!';

  @override
  String tutorialWonTwoRounds(String proposition) {
    return '\"$proposition\" venceu 2 rodadas seguidas.';
  }

  @override
  String get tutorialAddedToChat => 'Agora foi adicionado ao chat acima.';

  @override
  String get tutorialFinishButton => 'Finalizar Tutorial';

  @override
  String get tutorialRound1Result =>
      '\'Sucesso\' venceu esta rodada! Mas ainda não é definitivo. Precisa vencer a próxima rodada para ser adicionado permanentemente ao chat do grupo.';

  @override
  String get tutorialProposingHint =>
      'Envie uma ideia que voce quer que seja a resposta do grupo.';

  @override
  String tutorialTimeRemaining(String time) {
    return 'Voce tem $time restantes.';
  }

  @override
  String get tutorialProposingHintWithWinner =>
      'Envie uma nova ideia. Ela sera avaliada junto com o vencedor anterior.';

  @override
  String get tutorialRatingHint =>
      'Agora todos avaliam as ideias uns dos outros. Toque no botao para comecar a avaliar.';

  @override
  String get tutorialRatingPhaseExplanation =>
      'A fase de avaliacao comeca quando todos os usuarios enviam suas ideias ou quando o tempo acaba.';

  @override
  String tutorialRatingTimeRemaining(String time) {
    return 'Voce tem $time restantes para completar a fase de avaliacao.';
  }

  @override
  String get tutorialRatingBinaryHint =>
      'Primeiro, sao apresentadas 2 propostas aleatorias enviadas por usuarios. Coloque a que voce prefere mais em 100. Toque em [swap] para inverte-las e toque em [check] para confirmar. Nota: Sua propria proposta nao sera apresentada a voce para avaliacao.';

  @override
  String get tutorialRatingPositioningHint =>
      'Toque e segure [up] e [down] para mover a ideia destacada. Toque em [check] para posiciona-la. Toque em [undo] para desfazer um posicionamento, e [zoomin] [zoomout] para aproximar e afastar.';

  @override
  String tutorialRound2Result(String proposition) {
    return 'Sua ideia \"$proposition\" venceu! Se vencer a proxima rodada tambem, se torna uma resposta permanente.';
  }

  @override
  String get tutorialRound2Prompt =>
      'O vencedor \'Sucesso\' e automaticamente levado para competir novamente. Precisa vencer 2 rodadas seguidas para se tornar uma resposta permanente.';

  @override
  String get tutorialRatingCarryForwardHint =>
      'Este e o vencedor da rodada anterior. Se vencer novamente esta rodada, sera adicionado permanentemente ao chat.';

  @override
  String get tutorialRound2PromptSimplified =>
      'Hora da proxima rodada! Consegue pensar em algo melhor?';

  @override
  String tutorialRound2PromptSimplifiedTemplate(String winner) {
    return 'Hora da proxima rodada! Consegue pensar em algo melhor que \'$winner\'?';
  }

  @override
  String get tutorialPropSuccess => 'Sucesso';

  @override
  String get tutorialPropAdventure => 'Aventura';

  @override
  String get tutorialPropGrowth => 'Crescimento';

  @override
  String get tutorialPropHarmony => 'Harmonia';

  @override
  String get tutorialPropInnovation => 'Inovacao';

  @override
  String get tutorialPropFreedom => 'Liberdade';

  @override
  String get tutorialPropSecurity => 'Seguranca';

  @override
  String get tutorialPropStability => 'Estabilidade';

  @override
  String get tutorialPropTravelAbroad => 'Viajar para fora';

  @override
  String get tutorialPropStartABusiness => 'Abrir um negocio';

  @override
  String get tutorialPropGraduateSchool => 'Pos-graduacao';

  @override
  String get tutorialPropGetAJobFirst => 'Conseguir emprego';

  @override
  String get tutorialPropTakeAGapYear => 'Tirar um ano sabatico';

  @override
  String get tutorialPropFreelance => 'Freelancer';

  @override
  String get tutorialPropMoveToANewCity => 'Mudar de cidade';

  @override
  String get tutorialPropVolunteerProgram => 'Voluntariado';

  @override
  String get tutorialPropBeachResort => 'Resort de praia';

  @override
  String get tutorialPropMountainCabin => 'Cabana na montanha';

  @override
  String get tutorialPropCityTrip => 'Viagem urbana';

  @override
  String get tutorialPropRoadTrip => 'Viagem de carro';

  @override
  String get tutorialPropCampingAdventure => 'Aventura de camping';

  @override
  String get tutorialPropCruise => 'Cruzeiro';

  @override
  String get tutorialPropThemePark => 'Parque tematico';

  @override
  String get tutorialPropCulturalExchange => 'Intercambio cultural';

  @override
  String get tutorialPropBlockParty => 'Festa de rua';

  @override
  String get tutorialPropCommunityGarden => 'Horta comunitaria';

  @override
  String get tutorialPropNeighborhoodWatch => 'Vigilancia de bairro';

  @override
  String get tutorialPropToolLibrary => 'Biblioteca de ferramentas';

  @override
  String get tutorialPropMutualAidFund => 'Fundo de ajuda mutua';

  @override
  String get tutorialPropFreeLittleLibrary => 'Biblioteca livre';

  @override
  String get tutorialPropStreetMural => 'Mural de rua';

  @override
  String get tutorialPropSkillShareNight => 'Noite de talentos';

  @override
  String get tutorialPropFlexibleHours => 'Horario flexivel';

  @override
  String get tutorialPropMentalHealthSupport => 'Saude mental';

  @override
  String get tutorialPropTeamBuilding => 'Trabalho em equipe';

  @override
  String get tutorialPropSkillsTraining => 'Capacitacao';

  @override
  String get tutorialPropOpenCommunication => 'Comunicacao aberta';

  @override
  String get tutorialPropFairCompensation => 'Remuneracao justa';

  @override
  String get tutorialPropWorkLifeBalance => 'Equilibrio profissional';

  @override
  String get tutorialPropInnovationTime => 'Tempo de inovacao';

  @override
  String get tutorialPropPublicTransportation => 'Transporte publico';

  @override
  String get tutorialPropSchoolFunding => 'Verba escolar';

  @override
  String get tutorialPropEmergencyServices => 'Servicos de emergencia';

  @override
  String get tutorialPropRoadRepairs => 'Reparos de ruas';

  @override
  String get tutorialPropPublicHealth => 'Saude publica';

  @override
  String get tutorialPropAffordableHousing => 'Moradia acessivel';

  @override
  String get tutorialPropSmallBusinessGrants => 'Apoio a pequenas empresas';

  @override
  String get tutorialPropParksAndRecreation => 'Parques e lazer';

  @override
  String get tutorialPropClimateChange => 'Mudanca climatica';

  @override
  String get tutorialPropGlobalPoverty => 'Pobreza global';

  @override
  String get tutorialPropAiGovernance => 'Governanca de IA';

  @override
  String get tutorialPropPandemicPreparedness => 'Preparo para pandemias';

  @override
  String get tutorialPropNuclearDisarmament => 'Desarmamento nuclear';

  @override
  String get tutorialPropOceanConservation => 'Conservacao dos oceanos';

  @override
  String get tutorialPropDigitalRights => 'Direitos digitais';

  @override
  String get tutorialPropSpaceCooperation => 'Cooperacao espacial';

  @override
  String get tutorialDuplicateProposition =>
      'Esta ideia ja existe nesta rodada. Tente algo diferente!';

  @override
  String get tutorialShareTitle => 'Compartilhe Seu Chat';

  @override
  String get tutorialShareExplanation =>
      'Para convidar outros a entrar no seu chat, toque no botao de compartilhar no topo da sua tela.';

  @override
  String get tutorialShareTryIt => 'Experimente agora!';

  @override
  String get tutorialShareButtonHint =>
      'Toque no botao de compartilhar no canto superior direito ↗';

  @override
  String get tutorialSkipMenuItem => 'Pular Tutorial';

  @override
  String get tutorialSkipConfirmTitle => 'Pular Tutorial?';

  @override
  String get tutorialSkipConfirmMessage =>
      'Voce sempre pode acessar o tutorial mais tarde na tela inicial.';

  @override
  String get tutorialSkipConfirmYes => 'Sim, Pular';

  @override
  String get tutorialSkipConfirmNo => 'Continuar Tutorial';

  @override
  String get tutorialShareTooltip => 'Compartilhar Chat';

  @override
  String get tutorialYourIdea => 'Sua ideia';

  @override
  String get tutorialRateIdeas => 'Avaliar Ideias';

  @override
  String tutorialResultsBackHint(String winner) {
    return '\'$winner\' venceu! Pressione a seta de voltar quando terminar de ver os resultados.';
  }

  @override
  String deleteConsensusTitle(int number) {
    return 'Excluir Convergencia #$number?';
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
  String get consensusDeleted => 'Convergencia excluida';

  @override
  String get initialMessageUpdated => 'Initial message updated';

  @override
  String get initialMessageDeleted => 'Initial message deleted';

  @override
  String failedToDeleteConsensus(String error) {
    return 'Falha ao excluir a convergencia: $error';
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
  String get wizardStep1Title => 'Sobre o que voce quer falar?';

  @override
  String get wizardStep1Subtitle => 'Este e o coracao do seu chat';

  @override
  String get wizardStep2Title => 'Defina o ritmo';

  @override
  String get wizardStep2Subtitle => 'Quanto tempo para cada fase?';

  @override
  String get wizardOneLastThing => 'Mais uma coisa...';

  @override
  String get wizardProposingLabel => 'Propor (enviar ideias)';

  @override
  String get wizardRatingLabel => 'Avaliar (classificar ideias)';

  @override
  String get back => 'Voltar';

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
  String get forceAsConsensus => 'Forcar como Convergencia';

  @override
  String get forceAsConsensusDescription =>
      'Enviar diretamente como convergencia, pulando a votacao';

  @override
  String get forceConsensus => 'Forcar Convergencia';

  @override
  String get forceConsensusTitle => 'Forcar Convergencia?';

  @override
  String get forceConsensusMessage =>
      'Isso definira imediatamente sua proposta como a convergencia e iniciara um novo ciclo. Todo o progresso da rodada atual sera perdido.';

  @override
  String get forceConsensusSuccess => 'Convergencia forcada com sucesso';

  @override
  String failedToForceConsensus(String error) {
    return 'Falha ao forcar a convergencia: $error';
  }

  @override
  String get glossaryUserRoundTitle => 'user-round';

  @override
  String get glossaryUserRoundDef =>
      'One participant completing one round of rating. Each user-round costs 1 credit (\$0.01).';

  @override
  String get glossaryConsensusTitle => 'convergencia';

  @override
  String get glossaryConsensusDef =>
      'Quando a mesma proposta vence varias rodadas consecutivas, o grupo alcancou convergencia nessa ideia.';

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
      'Uma sequencia de rodadas trabalhando em direcao a convergencia. Um novo ciclo comeca apos a convergencia ser alcancada.';

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
