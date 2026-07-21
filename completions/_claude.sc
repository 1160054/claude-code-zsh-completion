#compdef claude

# Dynamic completion functions
_claude_mcp_servers() {
  local config_file
  local -a server_list

  # Parse config files using grep/sed (no external dependencies)
  for config_file in ~/.claude.json ~/.claude/mcp.json ~/.config/claude/mcp.json; do
    [[ -f "$config_file" ]] || continue
    # Find entries with "command", "type", or "url" (MCP server signature)
    server_list+=(${(f)"$(grep -B 1 -E '"(command|type|url)"[[:space:]]*:' "$config_file" 2>/dev/null | \
      grep -E '"[^"]+": \{' | sed 's/.*"\([^"]*\)".*/\1/' | grep -v '/')"})
  done
  server_list=(${(u)server_list})

  # Fallback to claude mcp list
  if [[ ${#server_list[@]} -eq 0 ]]; then
    server_list=(${(f)"$(claude mcp list 2>/dev/null | sed -n 's/^\([^:]*\):.*/\1/p' | grep -v '^Checking')"})
  fi

  compadd -a server_list
}

_claude_installed_plugins() {
  local -a plugins
  local config_file plugin_dir

  # Check plugin directories directly
  for plugin_dir in ~/.claude/plugins ~/.config/claude/plugins; do
    [[ -d "$plugin_dir" ]] || continue
    plugins+=(${plugin_dir}/*(N:t))
  done

  # Remove duplicates
  plugins=(${(u)plugins})

  compadd -a plugins
}

_claude_sessions() {
  local -a sessions
  local session_dir

  # Check session directory
  for session_dir in ~/.claude/sessions ~/.config/claude/sessions; do
    [[ -d "$session_dir" ]] || continue

    # Extract UUIDs directly from filenames
    sessions+=(${session_dir}/*~*.zwc(N:t:r))
  done

  # Filter only valid UUIDs
  sessions=(${(M)sessions:#[0-9a-f](#c8)-[0-9a-f](#c4)-[0-9a-f](#c4)-[0-9a-f](#c4)-[0-9a-f](#c12)})

  compadd -a sessions
}

_claude() {
  local curcontext="$curcontext" state line
  typeset -A opt_args

  local -a main_commands
  main_commands=(
    'mcp:Configurare e gestire sos serbidores MCP'
    'plugin:Gestire sos plugins de Claude Code'
    'agents:Gestire sos agentes in segundu pianu'
    'auth:Gestire s'\''autenticatzione'
    'auto-mode:Ispetzionare o ripristinare sa cunfiguratzione de su classificadore de sa modalidade automàtica'
    'gateway:Aviare su gateway de autenticatzione/telemetria pro s'\''impresa'
    'project:Gestire s'\''istadu de su progetu de Claude Code'
    'ultrareview:Aviare una revisione de còdighe multi-agente ospitada in cloud e imprentare sos resultados'
    'setup-token:Configurare su token de autenticatzione a longu tempus (recheret abbonamentu Claude)'
    'doctor:Verificatzione de salude pro s'\''agiornamentu automàticu de Claude Code'
    'update:Verificare e installare sos agiornamentos'
    'install:Installare sa compilatzione nativa de Claude Code'
  )

  local -a main_options
  main_options=(
    '(-d --debug)'{-d,--debug}'[Atibare sa modalidade de debug cun filtramentu optzionale pro categoria (es: "api,hooks" o "!statsig,!file")]:filter:'
    '--verbose[Subra iscrìere s'\''impostatzione de modalidade detallada dae s'\''archìviu de cunfiguratzione]'
    '(-p --print)'{-p,--print}'[Imprentare sa risposta e essire (pro impreare cun pipes). Nota: impreare isceti in directorios fidados]'
    '--output-format[Formadu de essida (cun --print): "text" (predefinidu), "json" (risultadu ùnicu), o "stream-json" (trasmissione in tempus reale)]:format:(text json stream-json)'
    '--json-schema[Ischema JSON pro validatzione de essida istruturada]:schema:'
    '--include-partial-messages[Includere sos fragmentos de mensàgios partzialesmente chi arribant (cun --print e --output-format=stream-json)]'
    '--input-format[Formadu de intrada (cun --print): "text" (predefinidu) o "stream-json" (intrada in trasmissione tempus reale)]:format:(text stream-json)'
    '--mcp-debug[\[Deploradu. Impreare --debug imbetzes\] Atibare sa modalidade de debug MCP (ammustrat sos errores de su serbidore MCP)]'
    '--dangerously-skip-permissions[Surpare totu sas verificatziones de permissos. Cunsiglladu isceti pro sandboxes chene atzessu a internet]'
    '--allow-dangerously-skip-permissions[Atibare s'\''optzione de surpare sas verificatziones de permissos chene s'\''atibare pro predefinidu]'
    '--max-budget-usd[Importu màssimu in dòllaros de ispèndere in sas ciamadas API (isceti --print)]:amount:'
    '--replay-user-messages[Torrare a imbiare sos mensàgios de s'\''utente dae stdin a stdout pro cunfirmatzione]'
    '--allowed-tools[Lista separada cun vìrgulas o ispàtzios de sos nùmenes de sos ainas permìtidos (es: "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Lista separada cun vìrgulas o ispàtzios de sos nùmenes de sos ainas permìtidos (formadu camelCase)]:tools:'
    '--tools[Ispetzificare sa lista de sos ainas disponìbiles dae su grupu integradu. Modalidade de imprentu isceti]:tools:'
    '--disallowed-tools[Lista separada cun vìrgulas o ispàtzios de sos nùmenes de sos ainas non permìtidos (es: "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Lista separada cun vìrgulas o ispàtzios de sos nùmenes de sos ainas non permìtidos (formadu camelCase)]:tools:'
    '--mcp-config[Carrigare sos serbidores MCP dae archìviu JSON o cadena (separados cun ispàtzios)]:configs:'
    '--system-prompt[Prompt de sistema de impreare pro sa sessione]:prompt:'
    '--append-system-prompt[Agiùnghere unu prompt de sistema a su prompt de sistema predefinidu]:prompt:'
    '--permission-mode[Modalidade de permissos de impreare pro sa sessione]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Sighire sa cunversatzione prus reghente]'
    '(-r --resume)'{-r,--resume}'[Ripigliare una cunversatzione - ispetzificare s'\''ID de sessione o seletzionare in manera interativa]:sessionId:_claude_sessions'
    '--fork-session[Creare unu nou ID de sessione imbetzes de torrare a impreare s'\''ID de sessione originale cando si ripìglliat (cun --resume o --continue)]'
    '--no-session-persistence[Disativare sa persistèntzia de sa sessione - sas sessiones no ant a èssere sarvadas (isceti --print)]'
    '--model[Modellu pro sa sessione atuale. Ispetzificare un alias pro su modellu prus reghente (es: '\''sonnet'\'' o '\''opus'\'')]:model:'
    '--agent[Agente pro sa sessione atuale. Subra iscrìet s'\''impostatzione '\''agent'\'']:agent:'
    '--betas[Intestatziones beta de includere in sas rechestas API (isceti utentes cun crae API)]:betas:'
    '--fallback-model[Atibare su cambiu automàticu a su modellu ispetzificadu cando su modellu predefinidu est sobrecarrigadu (isceti --print)]:model:'
    '--settings[Càmminu a archìviu JSON de impostattziones o cadena JSON pro carrigare impostattziones additzionales]:file-or-json:_files'
    '--add-dir[Directorios additzionales pro permìtere s'\''atzessu a sos ainas]:directories:_directories'
    '--ide[Connessione automàtica a s'\''IDE a s'\''aviamentu si petzi unu IDE bàlidu est disponìbile]'
    '--strict-mcp-config[Impreare isceti sos serbidores MCP dae --mcp-config e ignorare totu sas àteras impostattziones MCP]'
    '--session-id[ID de sessione ispetzìficu de impreare pro sa cunversatzione (depet èssere UUID bàlidu)]:uuid:'
    '--agents[Ogetu JSON chi definit agentes personalizados]:json:'
    '--setting-sources[Lista separada cun vìrgulas de fontes de impostattziones de carrigare (user, project, local)]:sources:'
    '--plugin-dir[Diretòriu pro carrigare plugins isceti pro cussa sessione (repetìbile)]:paths:_directories'
    '--disable-slash-commands[Disativare totu sos cumandos cun barra]'
    '(--bg --background)'{--bg,--background}'[Aviare sa sessione comente agente in segundu pianu e torrare deretu]'
    '(-w --worktree)'{-w,--worktree}'[Creare unu nou worktree git pro custa sessione (optzionalmente ispetzificare unu nùmene)]::name:'
    '--tmux[Creare una sessione tmux pro su worktree (recheret --worktree)]'
    '(-n --name)'{-n,--name}'[Definire unu nùmene de ammustrare pro custa sessione]:name:'
    '--effort[Livellu de impinnu pro sa sessione atuale]:level:(low medium high xhigh max)'
    '--debug-file[Iscrìere sos registros de debug in unu càmminu de archìviu ispetzìficu (atibat sa modalidade de debug in manera implìtzita)]:path:_files'
    '--from-pr[Ripigliare una sessione ligada a unu PR pro nùmeru/URL, o abèrrere su seletzionadore interativu]::value:'
    '--remote-control[Aviare una sessione interativa cun Remote Control atibadu (optzionalmente cun nùmene)]::name:'
    '--remote-control-session-name-prefix[Prefissu pro sos nùmenes de sessione Remote Control generados in automàticu]:prefix:'
    '--chrome[Atibare s'\''integratzione de Claude in Chrome]'
    '--no-chrome[Disativare s'\''integratzione de Claude in Chrome]'
    '--plugin-url[Recuperare unu .zip de plugin dae una URL isceti pro custa sessione (repetìbile)]:url:'
    '--file[Risorsas de archìviu de iscarrigare a s'\''aviamentu (formadu: file_id:relative_path)]:specs:'
    '--prompt-suggestions[Atibare sos cussìgios de prompt (emitit unu prompt sighente previstu in modalidade print/SDK)]::value:(true false 1 0 yes no on off)'
    '--forward-subagent-text[Torrare a imbiare su testu de su subagente e sos blocos de pensamentu comente mensàgios (cun --print e stream-json)]'
    '--include-hook-events[Includere totu sos eventos de su tzìclu de vida de sos hooks in su flussu de essida (cun stream-json)]'
    '--exclude-dynamic-system-prompt-sections[Mòvere sas setziones pro màchina in su primu mensàgiu de s'\''utente pro megiorare su torradu a impreare de sa cache de prompt]'
    '--brief[Atibare s'\''aina SendUserMessage pro sa comunicatzione dae agente a utente]'
    '--safe-mode[Aviare cun totu sas personalizatziones disativadas (ùtile pro risòlvere una cunfiguratzione istropiada)]'
    '--bare[Modalidade minimale: brincare hooks, LSP, sincronizatzione de plugins, atributzione, auto-memòria e iscoberta automàtica de CLAUDE.md]'
    '--ax-screen-reader[Rèndere s'\''essida amighèvole pro sos letores de schermu (testu pranu, chene bordos decorativos o animatziones)]'
    '(-v --version)'{-v,--version}'[Ammustare su nùmeru de versione]'
    '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu pro su cumandu]'
  )

  _arguments -C \
    $main_options \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'cumandos claude' main_commands
      ;;
    args)
      case $words[1] in
        mcp)
          _claude_mcp
          ;;
        plugin)
          _claude_plugin
          ;;
        install)
          _claude_install
          ;;
        agents)
          _claude_agents
          ;;
        auth)
          _claude_auth
          ;;
        auto-mode)
          _claude_auto_mode
          ;;
        gateway)
          _claude_gateway
          ;;
        project)
          _claude_project
          ;;
        ultrareview)
          _claude_ultrareview
          ;;
        setup-token|doctor|update)
          _message "perunu argumentu"
          ;;
      esac
      ;;
  esac
}

_claude_mcp() {
  local -a mcp_commands
  mcp_commands=(
    'serve:Aviare unu serbidore MCP de Claude Code'
    'add:Agiùnghere unu serbidore MCP a Claude Code'
    'remove:Bogare unu serbidore MCP'
    'list:Elencare sos serbidores MCP cunfiguradors'
    'get:Otènnere sos detàllios de su serbidore MCP'
    'add-json:Agiùnghere unu serbidore MCP (stdio o SSE) cun una cadena JSON'
    'add-from-claude-desktop:Importare sos serbidores MCP dae Claude Desktop (isceti Mac e WSL)'
    'reset-project-choices:Ripristinare totu sos serbidores cun àmbitu de progetu (.mcp.json) aprovados/refudados in custu progetu'
    'login:Autenticare cun unu serbidore MCP (HTTP, SSE, o connettore claude.ai)'
    'logout:Isbuidare sas credentziales OAuth sarvadas pro unu serbidore MCP'
    'help:Ammustare s'\''agiudu'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'cumandos mcp' mcp_commands
      ;;
    args)
      case $words[1] in
        serve)
          _arguments \
            '(-d --debug)'{-d,--debug}'[Atibare sa modalidade de debug]' \
            '--verbose[Subra iscrìere s'\''impostatzione de modalidade detallada dae s'\''archìviu de cunfiguratzione]' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]'
          ;;
        add)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Àmbitu de cunfiguratzione (local, user, project)]:scope:(local user project)' \
            '(-t --transport)'{-t,--transport}'[Tipu de trasportu (stdio, sse, http)]:transport:(stdio sse http)' \
            '(-e --env)'{-e,--env}'[Definire una variàbile de ambiente (es: -e CRAE=valore)]:env:' \
            '(-H --header)'{-H,--header}'[Definire intestatzione WebSocket]:header:' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:name:' \
            '2:commandOrUrl:' \
            '*:args:'
          ;;
        remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Àmbitu de cunfiguratzione (local, user, project) - bogare dae s'\''àmbitu esistente si non ispetzificadu]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:name:_claude_mcp_servers'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]'
          ;;
        get)
          _arguments \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:name:_claude_mcp_servers'
          ;;
        add-json)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Àmbitu de cunfiguratzione (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:name:' \
            '2:json:'
          ;;
        add-from-claude-desktop)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Àmbitu de cunfiguratzione (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]'
          ;;
        reset-project-choices)
          _arguments \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]'
          ;;
        login|logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:name:_claude_mcp_servers'
          ;;
      esac
      ;;
  esac
}

_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:Validare unu plugin o unu manifestu de mercadu'
    'marketplace:Gestire sos mercados de Claude Code'
    'list:Elencare sos plugins installados'
    'details:Ammustare s'\''inventàriu de sos cumponentes e su costu de token previstu pro unu plugin'
    'install:Installare unu plugin dae sos mercados disponìbiles'
    'i:Installare unu plugin dae sos mercados disponìbiles (forma curtza de install)'
    'init:Creare s'\''ischeletru de unu nou plugin (si càrrigat in automàticu sa sessione sighente)'
    'uninstall:Disinstallare unu plugin installadu'
    'remove:Disinstallare unu plugin installadu (alias pro uninstall)'
    'enable:Atibare unu plugin disativadu'
    'disable:Disatibare unu plugin ativadu'
    'update:Agiornare unu plugin a sa versione prus reghente'
    'eval:Aviare sos casos de eval contra unu plugin e informare sos resultados puntuados'
    'prune:Bogare sas dipendèntzias installadas in automàticu chi non serbint prus'
    'tag:Creare unu tag git {name}--v{version} pro una publicatzione de plugin'
    'help:Ammustare s'\''agiudu'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'cumandos de plugin' plugin_commands
      ;;
    args)
      case $words[1] in
        validate)
          _arguments \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Àmbitu de installatzione]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Àmbitu de installatzione]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Àmbitu de installatzione]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Àmbitu de installatzione]:scope:(user project local managed)' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list|prune)
          _arguments \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init)
          _arguments \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:target:'
          ;;
        tag)
          _arguments \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:path:_files'
          ;;
      esac
      ;;
  esac
}

_claude_plugin_marketplace() {
  local -a marketplace_commands
  marketplace_commands=(
    'add:Agiùnghere unu mercadu dae una URL, càmminu o repositòriu GitHub'
    'list:Elencare sos mercados cunfiguradores'
    'remove:Bogare unu mercadu cunfiguradu'
    'rm:Bogare unu mercadu cunfiguradu (alias pro remove)'
    'update:Agiornare su mercadu dae sa fonte - agiornare totu si perunu nùmene ispetzificadu'
    'help:Ammustare s'\''agiudu'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'cumandos de mercadu' marketplace_commands
      ;;
    args)
      case $words[1] in
        add)
          _arguments \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]'
          ;;
        remove|rm)
          _arguments \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:name:'
          ;;
        update)
          _arguments \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '::name:'
          ;;
      esac
      ;;
  esac
}

_claude_install() {
  _arguments \
    '--force[Fortziare s'\''installatzione fintzas si giai installadu]' \
    '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
    '::target:(stable latest)'
}

_claude_agents() {
  _arguments \
    '*--add-dir[Diretòriu additzionale pro permìtere s'\''atzessu a sos ainas in sas sessiones inviadas]:directory:_directories' \
    '--agent[Agente predefinidu pro sas sessiones inviadas dae sa vista de sos agentes]:agent:' \
    '--all[Cun --json: includere fintzas sas sessiones in segundu pianu cumpletadas]' \
    '--allow-dangerously-skip-permissions[Rèndere sa modalidade bypass-permissions disponìbile pro sas sessiones inviadas]' \
    '--cwd[Ammustare isceti sas sessiones in segundu pianu aviadas suta su càmminu]:path:_directories' \
    '--dangerously-skip-permissions[Alias pro --permission-mode bypassPermissions]' \
    '--effort[Livellu de impinnu predefinidu pro sas sessiones inviadas]:level:(low medium high xhigh max)' \
    '--json[Imprentare sas sessiones ativas comente array JSON e essire]' \
    '*--mcp-config[Cunfiguratzione de su serbidore MCP de aplicare a sas sessiones inviadas]:config:' \
    '--model[Modellu predefinidu pro sas sessiones inviadas dae sa vista de sos agentes]:model:' \
    '--permission-mode[Modalidade de permissos predefinida pro sas sessiones inviadas]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Carrigare plugins dae su diretòriu pro sa vista de sos agentes e sas sessiones inviadas]:path:_directories' \
    '--setting-sources[Lista separada cun vìrgulas de fontes de impostattziones de carrigare (user, project, local)]:sources:' \
    '--settings[Archìviu de impostattziones o cadena JSON de aplicare]:file-or-json:_files' \
    '--strict-mcp-config[Impreare isceti sos serbidores MCP dae --mcp-config in sas sessiones inviadas]' \
    '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu pro su cumandu]'
}

_claude_auth() {
  local -a auth_commands
  auth_commands=(
    'login:Intrare in su contu Anthropic tuo'
    'logout:Essire dae su contu Anthropic tuo'
    'status:Ammustare s'\''istadu de s'\''autenticatzione'
    'help:Ammustare s'\''agiudu'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu pro su cumandu]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'cumandos auth' auth_commands
      ;;
    args)
      case $words[1] in
        login|logout|status)
          _arguments \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu pro su cumandu]'
          ;;
      esac
      ;;
  esac
}

_claude_auto_mode() {
  local -a auto_mode_commands
  auto_mode_commands=(
    'config:Imprentare sa cunfiguratzione efetiva de sa modalidade automàtica comente JSON'
    'critique:Otènnere unu riscontru de s'\''IA subra sas règulas personalizadas de sa modalidade automàtica'
    'defaults:Imprentare sas règulas predefinidas de sa modalidade automàtica comente JSON'
    'reset:Ripristinare sa cunfiguratzione de sa modalidade automàtica a sos valores predefinidos de fàbrica'
    'help:Ammustare s'\''agiudu'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu pro su cumandu]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'cumandos auto-mode' auto_mode_commands
      ;;
    args)
      case $words[1] in
        config|critique|defaults|reset)
          _arguments \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu pro su cumandu]'
          ;;
      esac
      ;;
  esac
}

_claude_gateway() {
  _arguments \
    '--config[Càmminu a sa cunfiguratzione YAML de su gateway]:path:_files' \
    '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu pro su cumandu]'
}

_claude_project() {
  local -a project_commands
  project_commands=(
    'purge:Cantzellare totu s'\''istadu de Claude Code pro unu progetu (trascritziones, atividades, istòria de sos archìvios, boghe de cunfiguratzione)'
    'help:Ammustare s'\''agiudu'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu pro su cumandu]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'cumandos de progetu' project_commands
      ;;
    args)
      case $words[1] in
        purge)
          _arguments \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu pro su cumandu]' \
            '1:path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Imprentare su càrrigu bugs.json grezzu imbetzes de sos resultados formatados]' \
    '--timeout[Minutos màssimos de isetare pro chi sa revisione acabbet]:minutes:' \
    '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu pro su cumandu]' \
    '1:target:'
}

(( $+_comps[claude] )) || compdef _claude claude
