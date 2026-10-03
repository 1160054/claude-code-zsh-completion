#compdef claude

# Dynamic completion functions

# Directories Claude Code keeps its state in (agents, plugins, sessions).
# CLAUDE_CONFIG_DIR replaces the default location when it is set.
_claude_state_dirs() {
  if [[ -n "$CLAUDE_CONFIG_DIR" ]]; then
    print -r -- "$CLAUDE_CONFIG_DIR"
  else
    print -l -- "$HOME/.claude" "$HOME/.config/claude"
  fi
}

# JSON files that may hold MCP server definitions.
_claude_config_files() {
  if [[ -n "$CLAUDE_CONFIG_DIR" ]]; then
    print -l -- "$CLAUDE_CONFIG_DIR/.claude.json" "$CLAUDE_CONFIG_DIR/mcp.json"
  else
    print -l -- "$HOME/.claude.json" "$HOME/.claude/mcp.json" "$HOME/.config/claude/mcp.json"
  fi
}

_claude_mcp_servers() {
  local config_file
  local -a server_list

  # Parse config files using grep/sed (no external dependencies)
  for config_file in ${(f)"$(_claude_config_files)"}; do
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
  local state_dir manifest

  # Installed plugins are "name@marketplace" keys in
  # plugins/installed_plugins.json - the directories beside it are caches.
  for state_dir in ${(f)"$(_claude_state_dirs)"}; do
    manifest="$state_dir/plugins/installed_plugins.json"
    [[ -f "$manifest" ]] || continue
    plugins+=(${(f)"$(grep -oE '"[^"]+@[^"]+"[[:space:]]*:' "$manifest" 2>/dev/null | \
      sed 's/[[:space:]]*:$//; s/"//g')"})
  done

  plugins=(${(u)plugins})

  compadd -a plugins
}

_claude_sessions() {
  setopt localoptions extendedglob

  local -a sessions project_dirs
  local state_dir project_dir cwd session_file uuid summary

  # Sessions live under <config>/projects/<cwd with / and . turned into ->.
  # A symlinked working directory is recorded under its resolved path, so
  # try that as well as the one the shell reports.
  for cwd in "$PWD" "${PWD:A}"; do
    project_dirs+=(${${cwd//\//-}//./-})
  done
  project_dirs=(${(u)project_dirs})

  for state_dir in ${(f)"$(_claude_state_dirs)"}; do
    for project_dir in $project_dirs; do
      [[ -d "$state_dir/projects/$project_dir" ]] || continue

      # Newest first, capped so completion stays instant on long-lived projects
      for session_file in ${state_dir}/projects/${project_dir}/*.jsonl(Nom[1,20]); do
        uuid=${session_file:t:r}
        [[ $uuid == [0-9a-f](#c8)-[0-9a-f](#c4)-[0-9a-f](#c4)-[0-9a-f](#c4)-[0-9a-f](#c12) ]] || continue

        # Describe each session by the name it was given (/rename or --name),
        # else by the first thing you typed in it. A name is appended near the
        # end of the transcript and the first message sits at the start, so
        # only those ends are read - these files grow into the megabytes.
        summary=$(tail -c 100000 "$session_file" 2>/dev/null | \
          grep -o '"customTitle":"[^"]*"' 2>/dev/null | tail -1 | \
          sed 's/^"customTitle":"//; s/"$//')
        if [[ -z $summary ]]; then
          summary=$(head -c 200000 "$session_file" 2>/dev/null | \
            grep -m 1 -o '"role":"user","content":"[^"]\{1,60\}' 2>/dev/null | \
            sed 's/.*"content":"//; s/\\n/ /g; s/\\*$//')
        fi
        sessions+=("${uuid}:${summary:-no description}")
      done
    done
  done

  _describe -t sessions 'session' sessions
}

_claude_agent_names() {
  local -a agents agent_dirs
  local state_dir agent_dir agent_file name

  # User-level and project-level agent definitions
  for state_dir in ${(f)"$(_claude_state_dirs)"}; do
    agent_dirs+=("$state_dir/agents")
  done
  agent_dirs+=(.claude/agents)

  for agent_dir in $agent_dirs; do
    [[ -d "$agent_dir" ]] || continue

    for agent_file in ${agent_dir}/*.md(N); do
      # Prefer the name declared in the front matter, fall back to the filename
      name=$(sed -n '1,10{s/^name:[[:space:]]*\([^[:space:]]*\).*/\1/p;}' "$agent_file" 2>/dev/null | head -1)
      agents+=(${name:-${agent_file:t:r}})
    done
  done

  agents=(${(u)agents})

  compadd -a agents
}

_claude_background_sessions() {
  local -a sessions state_files
  local -A names states
  local state_dir state_file line id rest

  # Background sessions (`claude --bg`) live in <config>/jobs/<id>/, where
  # <id> is the short id that attach, logs, stop, respawn and rm take.
  for state_dir in ${(f)"$(_claude_state_dirs)"}; do
    # Newest first
    state_files=(${state_dir}/jobs/*/state.json(Nom))
    (( ${#state_files} )) || continue

    # One grep for all of them; the first "name" and "state" it reports for a
    # file are that file's top-level ones
    names=() states=()
    for line in ${(f)"$(grep -HoE '"(name|state)"[[:space:]]*:[[:space:]]*"[^"]*"' $state_files 2>/dev/null)"}; do
      id=${${line%%/state.json:*}:t}
      rest=${line#*/state.json:}
      case $rest in
        \"name\"*)  [[ -z $names[$id] ]]  && names[$id]=${${rest#*:*\"}%\"} ;;
        \"state\"*) [[ -z $states[$id] ]] && states[$id]=${${rest#*:*\"}%\"} ;;
      esac
    done

    for state_file in $state_files; do
      id=${state_file:h:t}
      sessions+=("${id}:${names[$id]:-no name}${states[$id]:+ (${states[$id]})}")
    done
  done

  _describe -t sessions 'background session' sessions
}

_claude_model_names() {
  local -a models config_files
  local state_dir config_file

  # Aliases always resolve to the latest model of that family
  models=(default fable opus sonnet haiku)

  # Full model names the user has already configured
  for state_dir in ${(f)"$(_claude_state_dirs)"}; do
    config_files+=("$state_dir/settings.json" "$state_dir/settings.local.json")
  done
  config_files+=(${(f)"$(_claude_config_files)"})

  for config_file in $config_files; do
    [[ -f "$config_file" ]] || continue
    models+=(${(f)"$(grep -oE '"(model|fallbackModel)"[[:space:]]*:[[:space:]]*"[^"]+"' "$config_file" 2>/dev/null | \
      sed 's/.*:[[:space:]]*"\([^"]*\)"/\1/')"})
  done

  # Remove duplicates
  models=(${(u)models})

  compadd -a models
}

_claude() {
  local curcontext="$curcontext" state line
  typeset -A opt_args

  local -a main_commands
  main_commands=(
    'mcp:Configurare e gestire sos serbidores MCP'
    'plugin:Gestire sos plugins de Claude Code'
    'agents:Gestire sos agentes in segundu pianu'
    'attach:Abèrrere una sessione in segundu pianu in custu terminale'
    'logs:Imprentare s'\''essida de terminale reghente de una sessione in segundu pianu'
    'stop:Firmare una sessione in segundu pianu (sa cunversatzione sua est mantesa)'
    'respawn:Torrare a aviare una sessione in segundu pianu pro chi impreet sa versione atuale de Claude Code'
    'rm:Cantzellare una sessione in segundu pianu, e su worktree suo cando est seguru'
    'auth:Gestire s'\''autenticatzione'
    'auto-mode:Ispetzionare o ripristinare sa cunfiguratzione de su classificadore de sa modalidade automàtica'
    'gateway:Aviare su gateway de autenticatzione/telemetria pro s'\''impresa'
    'import:Importare sa cunfiguratzione dae un'\''àteru agente de programmatzione IA in Claude Code'
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
    '--restricted[Modalidade limitada: bogare sos ainas chi esecutant cumandos o còdighe e WebFetch, ignorare sas impostattziones user/project/local, e limitare sos ainas de archìviu a sos directorios de traballu]'
    '--max-budget-usd[Importu màssimu in dòllaros de ispèndere in sas ciamadas API (isceti --print)]:amount:'
    '--replay-user-messages[Torrare a imbiare sos mensàgios de s'\''utente dae stdin a stdout pro cunfirmatzione]'
    '--allowed-tools[Lista separada cun vìrgulas o ispàtzios de sos nùmenes de sos ainas permìtidos (es: "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Lista separada cun vìrgulas o ispàtzios de sos nùmenes de sos ainas permìtidos (formadu camelCase)]:tools:'
    '--tools[Ispetzificare sa lista de sos ainas disponìbiles dae su grupu integradu. Modalidade de imprentu isceti]:tools:'
    '--disallowed-tools[Lista separada cun vìrgulas o ispàtzios de sos nùmenes de sos ainas non permìtidos (es: "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Lista separada cun vìrgulas o ispàtzios de sos nùmenes de sos ainas non permìtidos (formadu camelCase)]:tools:'
    '--mcp-config[Carrigare sos serbidores MCP dae archìviu JSON o cadena (separados cun ispàtzios)]:configs:'
    '--system-prompt[Prompt de sistema de impreare pro sa sessione]:prompt:'
    '--system-prompt-file[Lèghere su prompt de sistema dae unu archìviu]:file:_files'
    '--append-system-prompt[Agiùnghere unu prompt de sistema a su prompt de sistema predefinidu]:prompt:'
    '--append-system-prompt-file[Lèghere su prompt de sistema dae unu archìviu e l'\''agiùnghere a su prompt de sistema predefinidu]:file:_files'
    '--system-prompt-snapshot[Registrare su prompt de sistema una borta pro cunversatzione e lu torrare a impreare tale e cale in ogni rechesta e ripigliada (on, su predefinidu) o lu generare de nou in ogni rechesta (off)]:mode:(on off)'
    '--permission-mode[Modalidade de permissos de impreare pro sa sessione]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '--permission-prompts[Chie rispondet a sas rechestas de permissu cun --print: "host" (s'\''host de s'\''SDK o --permission-prompt-tool) o "none" (totu su chi diat pedire unu permissu est refudadu)]:target:(host none)'
    '--permission-prompt-tool[Aina MCP de impreare pro sas rechestas de permissu (isceti --print)]:tool:'
    '(-c --continue)'{-c,--continue}'[Sighire sa cunversatzione prus reghente]'
    '(-r --resume)'{-r,--resume}'[Ripigliare una cunversatzione - ispetzificare s'\''ID de sessione o seletzionare in manera interativa]:sessionId:_claude_sessions'
    '--fork-session[Creare unu nou ID de sessione imbetzes de torrare a impreare s'\''ID de sessione originale cando si ripìglliat (cun --resume o --continue)]'
    '--no-session-persistence[Disativare sa persistèntzia de sa sessione - sas sessiones no ant a èssere sarvadas (isceti --print)]'
    '--model[Modellu pro sa sessione atuale. Ispetzificare un alias pro su modellu prus reghente (es: '\''sonnet'\'' o '\''opus'\'')]:model:_claude_model_names'
    '--agent[Agente pro sa sessione atuale. Subra iscrìet s'\''impostatzione '\''agent'\'']:agent:_claude_agent_names'
    '--betas[Intestatziones beta de includere in sas rechestas API (isceti utentes cun crae API)]:betas:'
    '--fallback-model[Atibare su cambiu automàticu a su modellu ispetzificadu cando su modellu predefinidu est sobrecarrigadu (isceti --print)]:model:_claude_model_names'
    '--settings[Càmminu a archìviu JSON de impostattziones o cadena JSON pro carrigare impostattziones additzionales]:file-or-json:_files'
    '--add-dir[Directorios additzionales pro permìtere s'\''atzessu a sos ainas]:directories:_directories'
    '--ide[Connessione automàtica a s'\''IDE a s'\''aviamentu si petzi unu IDE bàlidu est disponìbile]'
    '--desktop[Abèrrere in s'\''aplicatzione Claude Desktop imbetzes de su terminale (cun --continue o --resume <id> pro seberare sa sessione)]'
    '--strict-mcp-config[Impreare isceti sos serbidores MCP dae --mcp-config e ignorare totu sas àteras impostattziones MCP]'
    '--session-id[ID de sessione ispetzìficu de impreare pro sa cunversatzione (depet èssere UUID bàlidu)]:uuid:'
    '--agents[Ogetu JSON chi definit agentes personalizados]:json:'
    '--setting-sources[Lista separada cun vìrgulas de fontes de impostattziones de carrigare (user, project, local)]:sources:'
    '--plugin-dir[Diretòriu pro carrigare plugins isceti pro cussa sessione (repetìbile)]:paths:_directories'
    '--disable-slash-commands[Disativare totu sos cumandos cun barra]'
    '(--bg --background)'{--bg,--background}'[Aviare sa sessione comente agente in segundu pianu e torrare deretu]'
    '(-w --worktree)'{-w,--worktree}'[Creare unu nou worktree git pro custa sessione (optzionalmente ispetzificare unu nùmene)]::name:'
    '--tmux=-[Creare una sessione tmux pro su worktree (recheret --worktree). Impreat sos pannellos nativos de iTerm2 cando sunt disponìbiles; --tmux=classic pro su tmux traditzionale]::mode:(classic)'
    '(-n --name)'{-n,--name}'[Definire unu nùmene de ammustrare pro custa sessione]:name:'
    '--effort[Livellu de impinnu pro sa sessione atuale]:level:(low medium high xhigh max)'
    '--autocompact[Mannària de sa ventana de cumpatatzione automàtica (auto, o dae 100k a 1M token)]:size:(auto)'
    '--debug-file[Iscrìere sos registros de debug in unu càmminu de archìviu ispetzìficu (atibat sa modalidade de debug in manera implìtzita)]:path:_files'
    '--from-pr[Ripigliare una sessione ligada a unu PR pro nùmeru/URL, o abèrrere su seletzionadore interativu]::value:'
    '--teleport[Ripigliare una sessione de teleport, optzionalmente ispetzificare s'\''ID de sessione]::session:'
    '--cloud[Creare una sessione in cloud cun sa descritzione dada, o si connètere a una esistente pro ID de sessione o URL claude.ai/code]::description-or-session:'
    '--environment[Creare una sessione noa in cloud chi funtzionat in s'\''ambiente autospitadu dadu (ccpool_...)]:environment_id:'
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
        attach|logs|stop|kill)
          _arguments \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu pro su cumandu]' \
            '1:session:_claude_background_sessions'
          ;;
        respawn)
          _claude_respawn
          ;;
        rm)
          _claude_rm
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
        import)
          _claude_import
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
            '--client-id[ID de cliente OAuth pro sos serbidores HTTP/SSE]:clientId:' \
            '--client-secret[Pedire su segretu de cliente OAuth (o definire sa variàbile de ambiente MCP_CLIENT_SECRET)]' \
            '--callback-port[Porta fissa pro sa callback OAuth (pro sos serbidores chi rechedent URI de redirectzione pre-registradas)]:port:' \
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
            '--client-secret[Pedire su segretu de cliente OAuth (o definire sa variàbile de ambiente MCP_CLIENT_SECRET)]' \
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
        login)
          _arguments \
            '--no-browser[Imprentare sa URL de autorizatzione imbetzes de abèrrere unu navigadore (pro sessiones SSH/chene interfache gràfica)]' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:name:_claude_mcp_servers'
          ;;
        logout)
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
    'configure:Ammustare sas optziones de unu plugin e cales non sunt definidas, o sarvare valores dae stdin'
    'install:Installare unu plugin dae sos mercados disponìbiles'
    'i:Installare unu plugin dae sos mercados disponìbiles (forma curtza de install)'
    'init:Creare s'\''ischeletru de unu nou plugin (si càrrigat in automàticu sa sessione sighente)'
    'new:Creare s'\''ischeletru de unu nou plugin (alias pro init)'
    'uninstall:Disinstallare unu plugin installadu'
    'remove:Disinstallare unu plugin installadu (alias pro uninstall)'
    'enable:Atibare unu plugin disativadu'
    'disable:Disatibare unu plugin ativadu'
    'update:Agiornare unu plugin a sa versione prus reghente'
    'eval:Aviare sos casos de eval contra unu plugin e informare sos resultados puntuados'
    'prune:Bogare sas dipendèntzias installadas in automàticu chi non serbint prus'
    'autoremove:Bogare sas dipendèntzias installadas in automàticu chi non serbint prus (alias pro prune)'
    'tag:Creare unu tag git {name}--v{version} pro una publicatzione de plugin'
    'test:Esecutare sos test de una mod'
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
            '--strict[Tratare sos avisos comente errores (còdighe de essida 1)]' \
            '--json[Imprentare su resocontu de validatzione comente JSON (sos matessi còdighes de essida)]' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Àmbitu de installatzione]:scope:(user project local)' \
            '*--config[Definire un'\''optzione userConfig declarada in su manifestu de su plugin (repetìbile)]:key=value:' \
            '(-y --yes)'{-y,--yes}'[Atzetare su cumandu ammustradu declaradu dae su mercadu chene sa rechesta de cunfirma]' \
            '--json[Imprentare una lìnia de resultadu legìbile dae sa màchina imbetzes de su mensàgiu pro sas persones]' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Àmbitu de installatzione]:scope:(user project local)' \
            '--keep-data[Mantènnere su diretòriu de sos datos persistentes de su plugin]' \
            '--prune[Bogare fintzas sas dipendèntzias installadas in automàticu chi non serbint prus]' \
            '(-y --yes)'{-y,--yes}'[Brincare sa rechesta de cunfirma de --prune]' \
            '--json[Imprentare una lìnia de resultadu legìbile dae sa màchina imbetzes de su mensàgiu pro sas persones (non cun --prune)]' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Àmbitu de installatzione]:scope:(user project local)' \
            '--json[Imprentare una lìnia de resultadu legìbile dae sa màchina imbetzes de su mensàgiu pro sas persones]' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        disable)
          _arguments \
            '(-a --all)'{-a,--all}'[Disativare totu sos plugins ativados]' \
            '(-s --scope)'{-s,--scope}'[Àmbitu de installatzione]:scope:(user project local)' \
            '--json[Imprentare una lìnia de resultadu legìbile dae sa màchina imbetzes de su mensàgiu pro sas persones]' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '::plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Àmbitu de installatzione]:scope:(user project local managed)' \
            '(-y --yes)'{-y,--yes}'[Atzetare su cumandu ammustradu declaradu dae su mercadu chene sa rechesta de cunfirma]' \
            '--json[Imprentare una lìnia de resultadu legìbile dae sa màchina imbetzes de su mensàgiu pro sas persones]' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list)
          _arguments \
            '--json[Imprentare comente JSON]' \
            '--available[Includere sos plugins disponìbiles dae sos mercados (recheret --json)]' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]'
          ;;
        prune|autoremove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Bogare sas dipendèntzias in s'\''àmbitu]:scope:(user project local)' \
            '--dry-run[Elencare su chi diat èssere bogadu chene bogare nudda]' \
            '(-y --yes)'{-y,--yes}'[Brincare sa rechesta de cunfirma]' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]'
          ;;
        configure)
          _arguments \
            '--json[Imprentare comente JSON]' \
            '--values-stdin[Lèghere sos valores de sas optziones dae stdin comente ogetu JSON de cadenas de una lìnia; sas optziones lassadas a fora mantenent sos valores issoro]' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init|new)
          _arguments \
            '--description[Descritzione de su manifestu]:text:' \
            '--author[Nùmene de s'\''autore (predefinidu: git config user.name)]:name:' \
            '--author-email[Email de s'\''autore (predefinidu: git config user.email)]:email:' \
            '--with[Cumponentes de creare fintzas issos comente ischeletru]:components:' \
            '(-f --force)'{-f,--force}'[Subra iscrìere unu .claude-plugin/ esistente in sa destinatzione]' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '--case[Filtrare sos casos pro glob de nùmene]:glob:' \
            '*--tag[Filtrare sos casos pro tag (repetìbile)]:tag:' \
            '--runs[Subra iscrìere su nùmeru de esecutziones pro casu (predefinidu: case.runs, si nono 3)]:n:' \
            '(-j --concurrency)'{-j,--concurrency}'[Esecutare finas a n esecutziones de agente a su matessi tempus (1-8; predefinidu 1)]:n:' \
            '--model[Subra iscrìere su modellu pro totu sos casos]:model:_claude_model_names' \
            '--judge-model[Subra iscrìere su modellu de s'\''avaluadore LLM (predefinidu: haiku)]:model:_claude_model_names' \
            '--max-cost-usd[Lìmite màssimu de costu; si est lòmpidu, interrumpere e informare sos resultados partziales (còdighe de essida 2)]:usd:' \
            '--output-dir[Diretòriu pro aggregate-result.json]:dir:_directories' \
            '--eval-dir[Nùmene de su diretòriu (suta de su plugin) chi cuntenet sos casos de eval]:dir:' \
            '--json[Imprentare su resultadu cumpletu de s'\''esecutzione comente JSON in stdout, o l'\''iscrìere in custu archìviu .json]::path:_files' \
            '--threshold[Essire cun còdighe de essida 1 si su puntègiu de calicunu casu est suta de custa sòglia (predefinidu: 1.0)]:threshold:' \
            '*--allow-tools[Autorizatzione de s'\''operadore pro sos ainas controllados (Bash, Write, Edit, WebFetch, mcp__*)]:tools:' \
            '(--no-scaffold)--scaffold[Esecutare su scaffold_script de ogni casu (esecutat bash frunidu dae s'\''autore a nòmine tuo; disativadu pro predefinidu)]' \
            '(--scaffold)--no-scaffold[Brincare in manera esplìtzita su scaffold_script]' \
            '--trust-plugin[Declarare chi ti fidas de custu plugin e de sa suite de eval sua, brinchende sa rechesta de fidùtzia de su primu aviamentu (pro CI)]' \
            '--ablation[Esecutare unu grupu de cunfrontu de base chene plugin e informare sa diferèntzia de puntègiu]:mode:(none with-without)' \
            '--mocks[Sostitutos simulados (mock) pro sos serbidores MCP, dae <eval dir>/mocks/]:mode:(record off)' \
            '--allow-real-servers[Cun --mocks record: aviare fintzas sos protzessos de sos serbidores MCP reales chi non tenent mock]' \
            '--keep-temp[Mantènnere sos directorios de ischeletru pro su debug]' \
            '--verbose[Registrare sos eventos de tratzamentu pro mensàgiu in su registru de debug]' \
            '--report[Iscrìere su resocontu HTML autònomu in custu càmminu imbetzes de su diretòriu de sos resultados]:path:_files' \
            '(--no-publish)--publish-report[Rechèrrere fintzas sa publicatzione de su resocontu in claude.ai]' \
            '(--publish-report)--no-publish[Mantènnere su resocontu HTML isceti in locale; brincare sa publicatzione in claude.ai]' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '::target: _alternative "plugins\:installed plugin\:_claude_installed_plugins" "files\:path\:_files"'
          ;;
        tag)
          _arguments \
            '--push[Imbiare su tag a --remote a pustis de l'\''àere creadu]' \
            '--dry-run[Imprentare su chi diat èssere etichetadu chene creare su tag]' \
            '(-f --force)'{-f,--force}'[Brincare sas verificatziones de àrbore de traballu cun modìficas e de tag giai esistente]' \
            '(-m --message)'{-m,--message}'[Mensàgiu de annotatzione de su tag (impreare %s pro sa versione)]:msg:' \
            '--remote[Remote a ue imbiare cun --push]:name:' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '::path:_files'
          ;;
        test)
          _arguments \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '::dir:_directories'
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
            '--sparse[Limitare su checkout a directorios ispetzìficos cun git sparse-checkout (pro monorepos)]:paths:' \
            '--scope[In ue declarare su mercadu]:scope:(user project local)' \
            '--claudeai[Agiùnghere su mercadu cun custu nùmene chi claude.ai ospitat pro tene]' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '--json[Imprentare comente JSON]' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu]'
          ;;
        remove|rm)
          _arguments \
            '--scope[Bogare sa declaratzione de su mercadu dae un'\''àmbitu de impostattziones ispetzìficu (omìtere pro la bogare dae ogni àmbitu)]:scope:(user project local)' \
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
    '--agent[Agente predefinidu pro sas sessiones inviadas dae sa vista de sos agentes]:agent:_claude_agent_names' \
    '--all[Cun --json: includere fintzas sas sessiones in segundu pianu cumpletadas]' \
    '--allow-dangerously-skip-permissions[Rèndere sa modalidade bypass-permissions disponìbile pro sas sessiones inviadas]' \
    '--cwd[Ammustare isceti sas sessiones in segundu pianu aviadas suta su càmminu]:path:_directories' \
    '--dangerously-skip-permissions[Alias pro --permission-mode bypassPermissions]' \
    '--effort[Livellu de impinnu predefinidu pro sas sessiones inviadas]:level:(low medium high xhigh max)' \
    '--json[Imprentare sas sessiones ativas comente array JSON e essire]' \
    '*--mcp-config[Cunfiguratzione de su serbidore MCP de aplicare a sas sessiones inviadas]:config:' \
    '--model[Modellu predefinidu pro sas sessiones inviadas dae sa vista de sos agentes]:model:_claude_model_names' \
    '--permission-mode[Modalidade de permissos predefinida pro sas sessiones inviadas]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Carrigare plugins dae su diretòriu pro sa vista de sos agentes e sas sessiones inviadas]:path:_directories' \
    '--setting-sources[Lista separada cun vìrgulas de fontes de impostattziones de carrigare (user, project, local)]:sources:' \
    '--settings[Archìviu de impostattziones o cadena JSON de aplicare]:file-or-json:_files' \
    '--strict-mcp-config[Impreare isceti sos serbidores MCP dae --mcp-config in sas sessiones inviadas]' \
    '--restricted[Aviare sas sessiones inviadas in modalidade limitada]' \
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
        login)
          _arguments \
            '--email[Pre-cumpilare s'\''indiritzu email in sa pàgina de intrada]:email:' \
            '--sso[Fortziare su flussu de intrada SSO]' \
            '(--claudeai)--console[Impreare Anthropic Console (fatturatzione pro impreu de s'\''API) imbetzes de s'\''abbonamentu Claude]' \
            '(--console)--claudeai[Impreare s'\''abbonamentu Claude (predefinidu)]' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu pro su cumandu]'
          ;;
        status)
          _arguments \
            '(--text)--json[Imprentare comente JSON (predefinidu)]' \
            '(--json)--text[Imprentare comente testu legìbile dae sas persones]' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu pro su cumandu]'
          ;;
        logout)
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
        critique)
          _arguments \
            '--model[Subra iscrìere su modellu impreadu]:model:_claude_model_names' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu pro su cumandu]'
          ;;
        defaults)
          _arguments \
            '--label[Ammustare isceti sas règulas chi s'\''eticheta issoro cumintzat cun custu prefissu (chene distìnghere maiùsculas e minùsculas)]:prefix:' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu pro su cumandu]'
          ;;
        reset)
          _arguments \
            '(-y --yes)'{-y,--yes}'[Brincare sa rechesta de cunfirma]' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu pro su cumandu]'
          ;;
        config)
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
            '--dry-run[Elencare su chi diat èssere cantzelladu chene cantzellare nudda]' \
            '(-y --yes)'{-y,--yes}'[Brincare sa rechesta de cunfirma]' \
            '(-i --interactive)'{-i,--interactive}'[Pedire cunfirma pro ogni elementu in antis de cantzellare]' \
            '(1)--all[Cantzellare s'\''istadu de ogni progetu (esclusivu cun unu càmminu)]' \
            '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu pro su cumandu]' \
            '(--all)::path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Imprentare su càrrigu bugs.json grezzu imbetzes de sos resultados formatados]' \
    '--timeout[Minutos màssimos de isetare pro chi sa revisione acabbet (predefinidu: 45)]:minutes:' \
    '(--no-post)--post[Publicare sos resultados de sa revisione acabbada in su PR a nòmine tuo (isceti pro destinatziones PR; unu cumentu sèmplitze, non una revisione)]' \
    '(--post)--no-post[Non publicare sos resultados in su PR (su predefinidu)]' \
    '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu pro su cumandu]' \
    '1:target:'
}

_claude_respawn() {
  _arguments \
    '(1)--all[Torrare a aviare ogni sessione in segundu pianu in esecutzione]' \
    '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu pro su cumandu]' \
    '(--all)::session:_claude_background_sessions'
}

_claude_rm() {
  _arguments \
    '--discard-unpushed[Iscartare fintzas sos commit non imbiados e sas modìficas non cunfirmadas de su worktree (passare su commit@worktree-id chi at informadu unu claude rm anteriore)]:commit@worktree-id:' \
    '--force-remove-worktree[Cantzellare su diretòriu de su worktree fintzas si su hook WorktreeRemove o git no l'\''ant pòdidu bogare (passare su worktree-id chi at informadu unu claude rm anteriore)]:worktree-id:' \
    '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu pro su cumandu]' \
    '1:session:_claude_background_sessions'
}

_claude_import() {
  _arguments \
    '--dry-run[Ammustare su chi diat èssere importadu chene iscrìere nudda]' \
    '--yes[Brincare su seletzionadore interativu (in sas superfìtzies chene interfache gràfica, passare --yes=<digest> dae s'\''anteprima de /import)]' \
    '(-h --help)'{-h,--help}'[Ammustare s'\''agiudu pro su cumandu]' \
    '::source:(codex gemini cursor)'
}

(( $+_comps[claude] )) || compdef _claude claude
