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
    'mcp:MCP-servers konfigurearje en behearje'
    'plugin:Claude Code-plugins behearje'
    'agents:Eftergrûnaginten behearje'
    'attach:In eftergrûnsesje yn dizze terminal iepenje'
    'logs:De resinte terminalútfier fan in eftergrûnsesje printsje'
    'stop:In eftergrûnsesje stopje (it petear wurdt bewarre)'
    'respawn:In eftergrûnsesje opnij starte sadat dy de hjoeddeistige Claude Code-ferzje útfiert'
    'rm:In eftergrûnsesje wiskje, en de worktree dêrfan as dat feilich is'
    'auth:Autentikaasje behearje'
    'auto-mode:Auto-modus klassifisearderkonfiguraasje ynspektearje of weromsette'
    'gateway:De enterprise-auth/telemetry-gateway útfiere'
    'import:Konfiguraasje fan in oare AI-kodearagint yn Claude Code ymportearje'
    'project:Claude Code-projektsteat behearje'
    'ultrareview:In cloud-hoste multi-agint koade-review útfiere en de befinings printsje'
    'setup-token:Langetermyn-autentikaasjetoken ynstelle (fereasket Claude-abonnemint)'
    'doctor:Sûnenskontrôle foar de Claude Code auto-updater'
    'update:Kontrolearje op en ynstallearje updates'
    'install:Claude Code native build ynstallearje'
  )

  local -a main_options
  main_options=(
    '(-d --debug)'{-d,--debug}'[Debugmodus ynskeakelje mei opsjonele kategoryfiltering (bygl. "api,hooks" of "!statsig,!file")]:filter:'
    '--verbose[Verbose-modus-ynstelling út konfiguraasjetriem oerskriuwe]'
    '(-p --print)'{-p,--print}'[Antwurd printsje en ôfslute (foar gebrûk mei pipes). Noat: allinne yn fertroude mappen brûke]'
    '--output-format[Útfierformaat (mei --print): "text" (standert), "json" (inkeld resultaat), of "stream-json" (realtime streaming)]:format:(text json stream-json)'
    '--json-schema[JSON-skema foar strukturearre útfierfalidaasje]:schema:'
    '--include-partial-messages[Partiële berjochtstikken opnimme sadree't se oankomme (mei --print en --output-format=stream-json)]'
    '--input-format[Ynfierformaat (mei --print): "text" (standert) of "stream-json" (realtime streaming-ynfier)]:format:(text stream-json)'
    '--mcp-debug[\[Ôfrieden. Brûk ynstee --debug\] MCP-debugmodus ynskeakelje (toant MCP-serverflaters)]'
    '--dangerously-skip-permissions[Alle tastimmingskontrôles omsile. Allinne oanret foar sandboxes sûnder ynternettagong]'
    '--allow-dangerously-skip-permissions[Opsje ynskeakelje om tastimmingskontrôles te omsilen sûnder standert yn te skeakeljen]'
    '--restricted[Beheinde modus: de tools dy'\''t kommando'\''s of koade útfiere en WebFetch fuortsmite, user/project/local-ynstellings negearje, en triemtools beheine ta de wurkmappen]'
    '--max-budget-usd[Maksimaal dollarbedrach om oan API-oanroppen út te jaan (allinne --print)]:amount:'
    '--replay-user-messages[Brûkersberjochten fan stdin op stdout opnij ferstjoere foar befêstiging]'
    '--allowed-tools[Komma- of spaasjeskieden list mei tastiene toolnammen (bygl. "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Komma- of spaasjeskieden list mei tastiene toolnammen (camelCase-formaat)]:tools:'
    '--tools[Jou list mei beskikbere tools út ynboude set op. Allinne printmodus]:tools:'
    '--disallowed-tools[Komma- of spaasjeskieden list mei net-tastiene toolnammen (bygl. "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Komma- of spaasjeskieden list mei net-tastiene toolnammen (camelCase-formaat)]:tools:'
    '--mcp-config[MCP-servers lade út JSON-triem of string (spaasjeskieden)]:configs:'
    '--system-prompt[Systeemprompt om te brûken foar de sesje]:prompt:'
    '--system-prompt-file[Systeemprompt út in triem lêze]:file:_files'
    '--append-system-prompt[Systeemprompt oan standert systeemprompt taheakje]:prompt:'
    '--append-system-prompt-file[Systeemprompt út in triem lêze en oan de standert systeemprompt taheakje]:file:_files'
    '--system-prompt-snapshot[De systeemprompt ien kear per petear fêstlizze en dy letterlik op '\''e nij brûke by elk fersyk en by it ferfetsjen (on, de standert) of dy by elk fersyk nij opbouwe (off)]:mode:(on off)'
    '--permission-mode[Tastimmingsmodus om te brûken foar de sesje]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '--permission-prompts[Wa'\''t tastimmingsprompts beantwurdet mei --print: "host" (de SDK-host of --permission-prompt-tool) of "none" (alles wat in prompt jaan soe, wurdt wegere)]:target:(host none)'
    '--permission-prompt-tool[MCP-tool om te brûken foar tastimmingsprompts (allinne --print)]:tool:'
    '(-c --continue)'{-c,--continue}'[Trochgean mei it meast resinte petear]'
    '(-r --resume)'{-r,--resume}'[In petear ferfetsje - jou sesje-ID op of selektearje ynteraktyf]:sessionId:_claude_sessions'
    '--fork-session[Nije sesje-ID oanmeitsje ynstee fan de orizjinele sesje-ID op '\''e nij te brûken by it ferfetsjen (mei --resume of --continue)]'
    '--no-session-persistence[Sesjepersistinsje útskeakelje - sesjes wurde net bewarre (allinne --print)]'
    '--model[Model foar de hjoeddeistige sesje. Jou alias op foar it nijste model (bygl. '\''sonnet'\'' of '\''opus'\'')]:model:_claude_model_names'
    '--agent[Agint foar de hjoeddeistige sesje. Oerskriuwt de '\''agent'\''-ynstelling]:agent:_claude_agent_names'
    '--betas[Beta-headers om op te nimmen yn API-fersiken (allinne API-kaaibrûkers)]:betas:'
    '--fallback-model[Automatyske fallback nei oanjûn model ynskeakelje as it standertmodel oerladen is (allinne --print)]:model:_claude_model_names'
    '--settings[Paad nei ynstellings-JSON-triem of JSON-string om ekstra ynstellings te laden]:file-or-json:_files'
    '--add-dir[Ekstra mappen om tooltagong ta te stean]:directories:_directories'
    '--ide[Automatysk ferbine mei IDE by it opstarten as der krekt ien jildige IDE beskikber is]'
    '--desktop[Iepenje yn de Claude Desktop-app ynstee fan de terminal (mei --continue of --resume <id> om de sesje te kiezen)]'
    '--strict-mcp-config[Allinne MCP-servers út --mcp-config brûke en alle oare MCP-ynstellings negearje]'
    '--session-id[Spesifike sesje-ID om te brûken foar it petear (moat jildige UUID wêze)]:uuid:'
    '--agents[JSON-objekt dat oanpaste aginten definiearret]:json:'
    '--setting-sources[Kommaskieden list mei ynstellingsboarnen om te laden (user, project, local)]:sources:'
    '--plugin-dir[Map om plugins út te laden allinne foar dizze sesje (werhelber)]:paths:_directories'
    '--disable-slash-commands[Alle slash-kommando'\''s útskeakelje]'
    '(--bg --background)'{--bg,--background}'[De sesje starte as eftergrûnagint en fuortendaliks weromkeare]'
    '(-w --worktree)'{-w,--worktree}'[In nije git-worktree oanmeitsje foar dizze sesje (opsjoneel in namme opjaan)]::name:'
    '--tmux=-[In tmux-sesje oanmeitsje foar de worktree (fereasket --worktree). Brûkt native iTerm2-panelen as dy beskikber binne; --tmux=classic foar tradisjonele tmux]::mode:(classic)'
    '(-n --name)'{-n,--name}'[In werjeftenamme foar dizze sesje ynstelle]:name:'
    '--effort[Ynspanningsnivo foar de hjoeddeistige sesje]:level:(low medium high xhigh max)'
    '--autocompact[Finstergrutte foar auto-compact (auto, of 100k-1M tokens)]:size:(auto)'
    '--debug-file[Debuglochs nei in spesifyk triempaad skriuwe (skeakelet ymplisyt debugmodus yn)]:path:_files'
    '--from-pr[In sesje ferfetsje dy'\''t oan in PR keppele is op nûmer/URL, of iepenje ynteraktive kiezer]::value:'
    '--teleport[In teleport-sesje ferfetsje, opsjoneel sesje-ID opjaan]::session:'
    '--cloud[In cloudsesje oanmeitsje mei de opjûne beskriuwing, of ferbine mei in besteande fia sesje-ID of claude.ai/code-URL]::description-or-session:'
    '--environment[In nije cloudsesje oanmeitsje dy'\''t rint op de opjûne self-hosted omjouwing (ccpool_...)]:environment_id:'
    '--remote-control[In ynteraktive sesje starte mei Remote Control ynskeakele (opsjoneel mei namme)]::name:'
    '--remote-control-session-name-prefix[Foarheaksel foar automatysk oanmakke Remote Control-sesjenammen]:prefix:'
    '--chrome[Claude yn Chrome-yntegraasje ynskeakelje]'
    '--no-chrome[Claude yn Chrome-yntegraasje útskeakelje]'
    '--plugin-url[In plugin-.zip fan in URL ophelje allinne foar dizze sesje (werhelber)]:url:'
    '--file[Triemboarnen om by it opstarten te downloaden (formaat: file_id:relative_path)]:specs:'
    '--prompt-suggestions[Promptsuggestjes ynskeakelje (jout in foarsizze folgjende prompt yn print/SDK-modus)]::value:(true false 1 0 yes no on off)'
    '--forward-subagent-text[Subagint-tekst en tinkblokken as berjochten trochstjoere (mei --print en stream-json)]'
    '--include-hook-events[Alle hook-libbenssyklusfoarfallen opnimme yn de útfierstream (mei stream-json)]'
    '--exclude-dynamic-system-prompt-sections[Per-masine-seksjes ferpleatse nei it earste brûkersberjocht om prompt-cache-hergebrûk te ferbetterjen]'
    '--brief[SendUserMessage-tool ynskeakelje foar agint-nei-brûker-kommunikaasje]'
    '--safe-mode[Starte mei alle oanpassingen útskeakele (nuttich foar it oplossen fan in stikkene konfiguraasje)]'
    '--bare[Minimale modus: hooks, LSP, pluginsyngronisaasje, attribúsje, auto-memory en CLAUDE.md-auto-ûntdekking oerslaan]'
    '--ax-screen-reader[Skermlêzerfreonlike útfier werjaan (platte tekst, gjin dekorative rânen of animaasjes)]'
    '(-v --version)'{-v,--version}'[Ferzjenûmer útfiere]'
    '(-h --help)'{-h,--help}'[Help foar kommando sjen litte]'
  )

  _arguments -C \
    $main_options \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'claude kommandos' main_commands
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
            '(-h --help)'{-h,--help}'[Help foar kommando sjen litte]' \
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
          _message "gjin arguminten"
          ;;
      esac
      ;;
  esac
}

_claude_mcp() {
  local -a mcp_commands
  mcp_commands=(
    'serve:In Claude Code MCP-server starte'
    'add:In MCP-server oan Claude Code tafoegje'
    'remove:In MCP-server fuortsmite'
    'list:Konfigurearre MCP-servers oplistje'
    'get:MCP-serverdetails opfreegje'
    'add-json:In MCP-server (stdio of SSE) tafoegje mei JSON-string'
    'add-from-claude-desktop:MCP-servers ymportearje fan Claude Desktop (allinne Mac en WSL)'
    'reset-project-choices:Alle goedkarde/ôfkarde projektskope (.mcp.json) servers yn dit projekt weromsette'
    'login:Autentisearje mei in MCP-server (HTTP, SSE, of claude.ai-connector)'
    'logout:Bewarre OAuth-oanmeldgegevens foar in MCP-server wiskje'
    'help:Help sjen litte'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Help sjen litte]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'mcp kommandos' mcp_commands
      ;;
    args)
      case $words[1] in
        serve)
          _arguments \
            '(-d --debug)'{-d,--debug}'[Debugmodus ynskeakelje]' \
            '--verbose[Verbose-modus-ynstelling út konfiguraasjetriem oerskriuwe]' \
            '(-h --help)'{-h,--help}'[Help sjen litte]'
          ;;
        add)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Konfiguraasjeberik (local, user, project)]:scope:(local user project)' \
            '(-t --transport)'{-t,--transport}'[Transporttype (stdio, sse, http)]:transport:(stdio sse http)' \
            '(-e --env)'{-e,--env}'[Omjouwingsfariabele ynstelle (bygl. -e KEY=value)]:env:' \
            '(-H --header)'{-H,--header}'[WebSocket-header ynstelle]:header:' \
            '--client-id[OAuth-client-ID foar HTTP/SSE-servers]:clientId:' \
            '--client-secret[Freegje om OAuth-client-geheim (of stel de omjouwingsfariabele MCP_CLIENT_SECRET yn)]' \
            '--callback-port[Fêste poarte foar OAuth-callback (foar servers dy'\''t foarôf registrearre redirect-URI'\''s fereaskje)]:port:' \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '1:name:' \
            '2:commandOrUrl:' \
            '*:args:'
          ;;
        remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Konfiguraasjeberik (local, user, project) - fuortsmite út besteand berik as net oanjûn]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '1:name:_claude_mcp_servers'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Help sjen litte]'
          ;;
        get)
          _arguments \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '1:name:_claude_mcp_servers'
          ;;
        add-json)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Konfiguraasjeberik (local, user, project)]:scope:(local user project)' \
            '--client-secret[Freegje om OAuth-client-geheim (of stel de omjouwingsfariabele MCP_CLIENT_SECRET yn)]' \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '1:name:' \
            '2:json:'
          ;;
        add-from-claude-desktop)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Konfiguraasjeberik (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Help sjen litte]'
          ;;
        reset-project-choices)
          _arguments \
            '(-h --help)'{-h,--help}'[Help sjen litte]'
          ;;
        login)
          _arguments \
            '--no-browser[De autorisaasje-URL printsje ynstee fan in browser te iepenjen (foar SSH/headless-sesjes)]' \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '1:name:_claude_mcp_servers'
          ;;
        logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '1:name:_claude_mcp_servers'
          ;;
      esac
      ;;
  esac
}

_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:In plugin- of marketplace-manifest falidearje'
    'marketplace:Claude Code-marketplaces behearje'
    'list:Ynstallearre plugins oplistje'
    'details:Komponinte-ynventarisaasje en ferwachte tokenkosten foar in plugin sjen litte'
    'configure:De opsjes fan in plugin sjen litte en hokker net ynsteld binne, of wearden fan stdin bewarje'
    'install:In plugin ynstallearje út beskikbere marketplaces'
    'i:In plugin ynstallearje út beskikbere marketplaces (koart foar install)'
    'init:In nije plugin opsette (laadt automatysk yn folgjende sesje)'
    'new:In nije plugin opsette (alias foar init)'
    'uninstall:In ynstallearre plugin de-ynstallearje'
    'remove:In ynstallearre plugin de-ynstallearje (alias foar uninstall)'
    'enable:In útskeakele plugin ynskeakelje'
    'disable:In ynskeakele plugin útskeakelje'
    'update:In plugin bywurkje nei de nijste ferzje'
    'eval:Eval-gefallen tsjin in plugin útfiere en beskoarde resultaten rapportearje'
    'prune:Automatysk ynstallearre ôfhinklikheden fuortsmite dy'\''t net mear nedich binne'
    'autoremove:Automatysk ynstallearre ôfhinklikheden fuortsmite dy'\''t net mear nedich binne (alias foar prune)'
    'tag:In {name}--v{version} git-tag oanmeitsje foar in pluginrelease'
    'test:De tests fan in mod útfiere'
    'help:Help sjen litte'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Help sjen litte]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'plugin kommandos' plugin_commands
      ;;
    args)
      case $words[1] in
        validate)
          _arguments \
            '--strict[Warskôgings as flaters behannelje (ôfslútkoade 1)]' \
            '--json[It falidaasjerapport as JSON útfiere (deselde ôfslútkoaden)]' \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Ynstallaasjeberik]:scope:(user project local)' \
            '*--config[In userConfig-opsje ynstelle dy'\''t yn it plugin-manifest deklarearre is (werhelber)]:key=value:' \
            '(-y --yes)'{-y,--yes}'[It werjûne kommando dat troch de marketplace deklarearre is akseptearje sûnder de befêstigingsprompt]' \
            '--json[Ien masinelêsbere resultaatrigel printsje ynstee fan it berjocht foar minsken]' \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Ynstallaasjeberik]:scope:(user project local)' \
            '--keep-data[De persistinte gegevensmap fan de plugin bewarje]' \
            '--prune[Ek automatysk ynstallearre ôfhinklikheden fuortsmite dy'\''t net mear nedich binne]' \
            '(-y --yes)'{-y,--yes}'[De --prune-befêstigingsprompt oerslaan]' \
            '--json[Ien masinelêsbere resultaatrigel printsje ynstee fan it berjocht foar minsken (net mei --prune)]' \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Ynstallaasjeberik]:scope:(user project local)' \
            '--json[Ien masinelêsbere resultaatrigel printsje ynstee fan it berjocht foar minsken]' \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        disable)
          _arguments \
            '(-a --all)'{-a,--all}'[Alle ynskeakele plugins útskeakelje]' \
            '(-s --scope)'{-s,--scope}'[Ynstallaasjeberik]:scope:(user project local)' \
            '--json[Ien masinelêsbere resultaatrigel printsje ynstee fan it berjocht foar minsken]' \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '::plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Ynstallaasjeberik]:scope:(user project local managed)' \
            '(-y --yes)'{-y,--yes}'[It werjûne kommando dat troch de marketplace deklarearre is akseptearje sûnder de befêstigingsprompt]' \
            '--json[Ien masinelêsbere resultaatrigel printsje ynstee fan it berjocht foar minsken]' \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list)
          _arguments \
            '--json[Útfiere as JSON]' \
            '--available[Beskikbere plugins út marketplaces opnimme (fereasket --json)]' \
            '(-h --help)'{-h,--help}'[Help sjen litte]'
          ;;
        prune|autoremove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Opromje yn berik]:scope:(user project local)' \
            '--dry-run[Oplistje wat fuortsmiten wurde soe sûnder fuort te smiten]' \
            '(-y --yes)'{-y,--yes}'[De befêstigingsprompt oerslaan]' \
            '(-h --help)'{-h,--help}'[Help sjen litte]'
          ;;
        configure)
          _arguments \
            '--json[Útfiere as JSON]' \
            '--values-stdin[Opsjewearden fan stdin lêze as in JSON-objekt mei strings fan ien rigel; weilitten opsjes hâlde har wearden]' \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init|new)
          _arguments \
            '--description[Manifestbeskriuwing]:text:' \
            '--author[Namme fan de auteur (standert: git config user.name)]:name:' \
            '--author-email[E-mail fan de auteur (standert: git config user.email)]:email:' \
            '--with[Komponinten om ek op te setten]:components:' \
            '(-f --force)'{-f,--force}'[In besteande .claude-plugin/ op it doel oerskriuwe]' \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '--case[Gefallen filterje op namme-glob]:glob:' \
            '*--tag[Gefallen filterje op tag (werhelber)]:tag:' \
            '--runs[Oantal runs per gefal oerskriuwe (standert: case.runs, oars 3)]:n:' \
            '(-j --concurrency)'{-j,--concurrency}'[Oant n agintruns tagelyk útfiere (1-8; standert 1)]:n:' \
            '--model[Model foar alle gefallen oerskriuwe]:model:_claude_model_names' \
            '--judge-model[Model fan de LLM-beoardieler oerskriuwe (standert: haiku)]:model:_claude_model_names' \
            '--max-cost-usd[Hurde kostegrins; ôfbrekke en partiële resultaten rapportearje as dy berikt wurdt (ôfslútkoade 2)]:usd:' \
            '--output-dir[Map foar aggregate-result.json]:dir:_directories' \
            '--eval-dir[Mapnamme (ûnder de plugin) dy'\''t de eval-gefallen befettet]:dir:' \
            '--json[It folsleine runresultaat as JSON nei stdout printsje, of it nei dizze .json-triem skriuwe]::path:_files' \
            '--threshold[Ôfslute mei ôfslútkoade 1 as in gefalsskoare ûnder dizze drompel leit (standert: 1.0)]:threshold:' \
            '*--allow-tools[Operatortastimming foar beskerme tools (Bash, Write, Edit, WebFetch, mcp__*)]:tools:' \
            '(--no-scaffold)--scaffold[It scaffold_script fan elk gefal útfiere (fiert troch de auteur levere bash út ûnder jo akkount; standert út)]' \
            '(--scaffold)--no-scaffold[scaffold_script eksplisyt oerslaan]' \
            '--trust-plugin[Ferklearje dat jo dizze plugin en syn eval-suite fertrouwe, en de fertrouwensprompt by de earste run oerslaan (foar CI)]' \
            '--ablation[In baseline-fergelikingsgroep sûnder plugin útfiere en it skoareferskil rapportearje]:mode:(none with-without)' \
            '--mocks[Mock-ferfangers foar MCP-servers, út <eval dir>/mocks/]:mode:(record off)' \
            '--allow-real-servers[Mei --mocks record: ek de echte MCP-serverprosessen starte dy'\''t gjin mock hawwe]' \
            '--keep-temp[Scaffold-mappen bewarje foar debuggen]' \
            '--verbose[Trace-foarfallen per berjocht yn it debuglochboek skriuwe]' \
            '--report[It selsstannige HTML-rapport nei dit paad skriuwe ynstee fan de resultatemap]:path:_files' \
            '(--no-publish)--publish-report[Ek fereaskje dat it rapport op claude.ai publisearre wurdt]' \
            '(--publish-report)--no-publish[It HTML-rapport allinne lokaal hâlde; publisearjen op claude.ai oerslaan]' \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '::target: _alternative "plugins\:installed plugin\:_claude_installed_plugins" "files\:path\:_files"'
          ;;
        tag)
          _arguments \
            '--push[De tag nei --remote pushe nei it oanmeitsjen]' \
            '--dry-run[Printsje wat tagge wurde soe sûnder it oan te meitsjen]' \
            '(-f --force)'{-f,--force}'[De kontrôles op in net-skjinne wurkbeam en in al besteande tag oerslaan]' \
            '(-m --message)'{-m,--message}'[Annotaasjeberjocht fan de tag (brûk %s foar de ferzje)]:msg:' \
            '--remote[Remote om nei te pushen mei --push]:name:' \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '::path:_files'
          ;;
        test)
          _arguments \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '::dir:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_plugin_marketplace() {
  local -a marketplace_commands
  marketplace_commands=(
    'add:In marketplace tafoegje fan URL, paad of GitHub-repository'
    'list:Konfigurearre marketplaces oplistje'
    'remove:In konfigurearre marketplace fuortsmite'
    'rm:In konfigurearre marketplace fuortsmite (alias foar remove)'
    'update:Marketplace bywurkje fan boarne - alles bywurkje as gjin namme oanjûn'
    'help:Help sjen litte'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Help sjen litte]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'marketplace kommandos' marketplace_commands
      ;;
    args)
      case $words[1] in
        add)
          _arguments \
            '--sparse[Checkout beheine ta spesifike mappen fia git sparse-checkout (foar monorepo'\''s)]:paths:' \
            '--scope[Wêr'\''t de marketplace deklarearre wurde moat]:scope:(user project local)' \
            '--claudeai[De marketplace mei dizze namme tafoegje dy'\''t claude.ai foar jo host]' \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '--json[Útfiere as JSON]' \
            '(-h --help)'{-h,--help}'[Help sjen litte]'
          ;;
        remove|rm)
          _arguments \
            '--scope[De marketplace-deklaraasje fuortsmite út in spesifyk ynstellingsberik (weilitte om it út elk berik fuort te smiten)]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '1:name:'
          ;;
        update)
          _arguments \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '::name:'
          ;;
      esac
      ;;
  esac
}

_claude_install() {
  _arguments \
    '--force[Ynstallaasje forsearje ek al is it al ynstallearre]' \
    '(-h --help)'{-h,--help}'[Help sjen litte]' \
    '::target:(stable latest)'
}

_claude_agents() {
  _arguments \
    '*--add-dir[Ekstra map om tooltagong ta te stean yn ferstjoerde sesjes]:directory:_directories' \
    '--agent[Standertagint foar sesjes ferstjoerd út de agintwerjefte]:agent:_claude_agent_names' \
    '--all[Mei --json: nim ek foltôge eftergrûnsesjes op]' \
    '--allow-dangerously-skip-permissions[Bypass-permissions-modus beskikber meitsje foar ferstjoerde sesjes]' \
    '--cwd[Allinne eftergrûnsesjes toane dy'\''t ûnder paad starten binne]:path:_directories' \
    '--dangerously-skip-permissions[Alias foar --permission-mode bypassPermissions]' \
    '--effort[Standert ynspanningsnivo foar ferstjoerde sesjes]:level:(low medium high xhigh max)' \
    '--json[Aktive sesjes as JSON-array printsje en ôfslute]' \
    '*--mcp-config[MCP-serverkonfiguraasje om ta te passen op ferstjoerde sesjes]:config:' \
    '--model[Standertmodel foar sesjes ferstjoerd út de agintwerjefte]:model:_claude_model_names' \
    '--permission-mode[Standert tastimmingsmodus foar ferstjoerde sesjes]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Plugins lade út map foar de agintwerjefte en ferstjoerde sesjes]:path:_directories' \
    '--setting-sources[Kommaskieden list mei ynstellingsboarnen om te laden (user, project, local)]:sources:' \
    '--settings[Ynstellingstriem of JSON-string om ta te passen]:file-or-json:_files' \
    '--strict-mcp-config[Allinne MCP-servers út --mcp-config brûke yn ferstjoerde sesjes]' \
    '--restricted[Ferstjoerde sesjes yn beheinde modus starte]' \
    '(-h --help)'{-h,--help}'[Help foar kommando sjen litte]'
}

_claude_auth() {
  local -a auth_commands
  auth_commands=(
    'login:Oanmelde by jo Anthropic-akkount'
    'logout:Ôfmelde fan jo Anthropic-akkount'
    'status:Autentikaasjestatus sjen litte'
    'help:Help sjen litte'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Help foar kommando sjen litte]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'auth kommandos' auth_commands
      ;;
    args)
      case $words[1] in
        login)
          _arguments \
            '--email[E-mailadres foarôf ynfolje op de oanmeldside]:email:' \
            '--sso[SSO-oanmeldproses forsearje]' \
            '(--claudeai)--console[Anthropic Console (fakturearring op API-gebrûk) brûke ynstee fan Claude-abonnemint]' \
            '(--console)--claudeai[Claude-abonnemint brûke (standert)]' \
            '(-h --help)'{-h,--help}'[Help foar kommando sjen litte]'
          ;;
        status)
          _arguments \
            '(--text)--json[Útfiere as JSON (standert)]' \
            '(--json)--text[Útfiere as foar minsken lêsbere tekst]' \
            '(-h --help)'{-h,--help}'[Help foar kommando sjen litte]'
          ;;
        logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Help foar kommando sjen litte]'
          ;;
      esac
      ;;
  esac
}

_claude_auto_mode() {
  local -a auto_mode_commands
  auto_mode_commands=(
    'config:De effektive auto-modus-konfiguraasje as JSON printsje'
    'critique:AI-feedback krije op jo oanpaste auto-modus-regels'
    'defaults:De standert auto-modus-regels as JSON printsje'
    'reset:Auto-modus-konfiguraasje weromsette nei de meilevere standerten'
    'help:Help sjen litte'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Help foar kommando sjen litte]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'auto-mode kommandos' auto_mode_commands
      ;;
    args)
      case $words[1] in
        critique)
          _arguments \
            '--model[Oerskriuwe hokker model brûkt wurdt]:model:_claude_model_names' \
            '(-h --help)'{-h,--help}'[Help foar kommando sjen litte]'
          ;;
        defaults)
          _arguments \
            '--label[Allinne regels sjen litte wêrfan it label mei dit foarheaksel begjint (net haadlettergefoelich)]:prefix:' \
            '(-h --help)'{-h,--help}'[Help foar kommando sjen litte]'
          ;;
        reset)
          _arguments \
            '(-y --yes)'{-y,--yes}'[De befêstigingsprompt oerslaan]' \
            '(-h --help)'{-h,--help}'[Help foar kommando sjen litte]'
          ;;
        config)
          _arguments \
            '(-h --help)'{-h,--help}'[Help foar kommando sjen litte]'
          ;;
      esac
      ;;
  esac
}

_claude_gateway() {
  _arguments \
    '--config[Paad nei gateway-YAML-konfiguraasje]:path:_files' \
    '(-h --help)'{-h,--help}'[Help foar kommando sjen litte]'
}

_claude_project() {
  local -a project_commands
  project_commands=(
    'purge:Alle Claude Code-steat foar in projekt wiskje (transkripsjes, taken, triemhistoarje, konfiguraasje-yngong)'
    'help:Help sjen litte'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Help foar kommando sjen litte]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'project kommandos' project_commands
      ;;
    args)
      case $words[1] in
        purge)
          _arguments \
            '--dry-run[Oplistje wat wiske wurde soe sûnder wat te wiskjen]' \
            '(-y --yes)'{-y,--yes}'[De befêstigingsprompt oerslaan]' \
            '(-i --interactive)'{-i,--interactive}'[Foar elk item freegje foar it wiskjen]' \
            '(1)--all[Steat foar elk projekt wiskje (ûnderling útslutend mei in paad)]' \
            '(-h --help)'{-h,--help}'[Help foar kommando sjen litte]' \
            '(--all)::path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[De rûge bugs.json-payload printsje ynstee fan opmakke befinings]' \
    '--timeout[Maksimaal oantal minuten om te wachtsjen oant de review klear is (standert: 45)]:minutes:' \
    '(--no-post)--post[De befinings fan de foltôge review ûnder jo namme op de PR pleatse (allinne PR-doelen; ien gewoane opmerking, gjin review)]' \
    '(--post)--no-post[De befinings net op de PR pleatse (de standert)]' \
    '(-h --help)'{-h,--help}'[Help foar kommando sjen litte]' \
    '1:target:'
}

_claude_respawn() {
  _arguments \
    '(1)--all[Elke rinnende eftergrûnsesje opnij starte]' \
    '(-h --help)'{-h,--help}'[Help foar kommando sjen litte]' \
    '(--all)::session:_claude_background_sessions'
}

_claude_rm() {
  _arguments \
    '--discard-unpushed[Ek de net-pushte commits en net-committe wizigingen fan de worktree ferwerpe (jou de commit@worktree-id op dy'\''t in eardere claude rm rapportearre)]:commit@worktree-id:' \
    '--force-remove-worktree[De worktree-map wiskje ek al koene de WorktreeRemove-hook of git dy net fuortsmite (jou de worktree-id op dy'\''t in eardere claude rm rapportearre)]:worktree-id:' \
    '(-h --help)'{-h,--help}'[Help foar kommando sjen litte]' \
    '1:session:_claude_background_sessions'
}

_claude_import() {
  _arguments \
    '--dry-run[Sjen litte wat ymportearre wurde soe sûnder wat te skriuwen]' \
    '--yes[De ynteraktive kiezer oerslaan (op headless-omjouwings, jou --yes=<digest> op út de /import-foarbyldwerjefte)]' \
    '(-h --help)'{-h,--help}'[Help foar kommando sjen litte]' \
    '::source:(codex gemini cursor)'
}

(( $+_comps[claude] )) || compdef _claude claude
