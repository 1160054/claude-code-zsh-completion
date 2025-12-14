#compdef claude

# Dynamic completion functions
_claude_mcp_servers() {
  local servers config_file
  local -a server_list

  # Read directly from config files instead of running 'claude mcp list'
  for config_file in ~/.claude/mcp.json ~/.claude.json ~/.config/claude/mcp.json; do
    [[ -f "$config_file" ]] || continue

    # Extract server names from JSON (mcpServers section)
    servers=$(grep -oP '(?<="mcpServers":\s*\{)[^}]+' "$config_file" 2>/dev/null | \
              grep -oP '(?<=")[^"]+(?="\s*:)' 2>/dev/null)

    [[ -n "$servers" ]] && server_list+=(${(f)servers})
  done

  # Fallback to claude mcp list if config parsing fails
  if [[ ${#server_list[@]} -eq 0 ]]; then
    server_list=(${(f)"$(claude mcp list 2>/dev/null | sed -n 's/^\([^:]*\):.*/\1/p' | grep -v '^Checking')"})
  fi

  _describe 'serbidores mcp' server_list
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

  _describe 'plugins installados' plugins
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

  _describe 'IDs de sessione' sessions
}

_claude() {
  local curcontext="$curcontext" state line
  typeset -A opt_args

  local -a main_commands
  main_commands=(
    'mcp:Configurare e gestire sos serbidores MCP'
    'plugin:Gestire sos plugins de Claude Code'
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
    '--replay-user-messages[Torrare a imbiare sos mensàgios de s'\''utente dae stdin a stdout pro cunfirmatzione]'
    '--allowed-tools[Lista separada cun vìrgulas o ispàtzios de sos nùmenes de sos ainas permìtidos (es: "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Lista separada cun vìrgulas o ispàtzios de sos nùmenes de sos ainas permìtidos (formadu camelCase)]:tools:'
    '--tools[Ispetzificare sa lista de sos ainas disponìbiles dae su grupu integradu. Modalidade de imprentu isceti]:tools:'
    '--disallowed-tools[Lista separada cun vìrgulas o ispàtzios de sos nùmenes de sos ainas non permìtidos (es: "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Lista separada cun vìrgulas o ispàtzios de sos nùmenes de sos ainas non permìtidos (formadu camelCase)]:tools:'
    '--mcp-config[Carrigare sos serbidores MCP dae archìviu JSON o cadena (separados cun ispàtzios)]:configs:'
    '--system-prompt[Prompt de sistema de impreare pro sa sessione]:prompt:'
    '--append-system-prompt[Agiùnghere unu prompt de sistema a su prompt de sistema predefinidu]:prompt:'
    '--permission-mode[Modalidade de permissos de impreare pro sa sessione]:mode:(acceptEdits bypassPermissions default dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Sighire sa cunversatzione prus reghente]'
    '(-r --resume)'{-r,--resume}'[Ripigliare una cunversatzione - ispetzificare s'\''ID de sessione o seletzionare in manera interativa]:sessionId:_claude_sessions'
    '--fork-session[Creare unu nou ID de sessione imbetzes de torrare a impreare s'\''ID de sessione originale cando si ripìglliat (cun --resume o --continue)]'
    '--model[Modellu pro sa sessione atuale. Ispetzificare un alias pro su modellu prus reghente (es: '\''sonnet'\'' o '\''opus'\'')]:model:'
    '--fallback-model[Atibare su cambiu automàticu a su modellu ispetzificadu cando su modellu predefinidu est sobrecarrigadu (isceti --print)]:model:'
    '--settings[Càmminu a archìviu JSON de impostattziones o cadena JSON pro carrigare impostattziones additzionales]:file-or-json:_files'
    '--add-dir[Directorios additzionales pro permìtere s'\''atzessu a sos ainas]:directories:_directories'
    '--ide[Connessione automàtica a s'\''IDE a s'\''aviamentu si petzi unu IDE bàlidu est disponìbile]'
    '--strict-mcp-config[Impreare isceti sos serbidores MCP dae --mcp-config e ignorare totu sas àteras impostattziones MCP]'
    '--session-id[ID de sessione ispetzìficu de impreare pro sa cunversatzione (depet èssere UUID bàlidu)]:uuid:'
    '--agents[Ogetu JSON chi definit agentes personalizados]:json:'
    '--setting-sources[Lista separada cun vìrgulas de fontes de impostattziones de carrigare (user, project, local)]:sources:'
    '--plugin-dir[Diretòriu pro carrigare plugins isceti pro cussa sessione (repetìbile)]:paths:_directories'
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
      esac
      ;;
  esac
}

_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:Validare unu plugin o unu manifestu de mercadu'
    'marketplace:Gestire sos mercados de Claude Code'
    'install:Installare unu plugin dae sos mercados disponìbiles'
    'i:Installare unu plugin dae sos mercados disponìbiles (forma curtza de install)'
    'uninstall:Disinstallare unu plugin installadu'
    'remove:Disinstallare unu plugin installadu (alias pro uninstall)'
    'enable:Atibare unu plugin disativadu'
    'disable:Disatibare unu plugin ativadu'
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
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:plugin:_claude_installed_plugins'
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

(( $+_comps[claude] )) || compdef _claude claude
