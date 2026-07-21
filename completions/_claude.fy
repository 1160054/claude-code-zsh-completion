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
    'mcp:MCP-servers konfigurearje en behearje'
    'plugin:Claude Code-plugins behearje'
    'agents:Eftergrûnaginten behearje'
    'auth:Autentikaasje behearje'
    'auto-mode:Auto-modus klassifisearderkonfiguraasje ynspektearje of weromsette'
    'gateway:De enterprise-auth/telemetry-gateway útfiere'
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
    '--max-budget-usd[Maksimaal dollarbedrach om oan API-oanroppen út te jaan (allinne --print)]:amount:'
    '--replay-user-messages[Brûkersberjochten fan stdin op stdout opnij ferstjoere foar befêstiging]'
    '--allowed-tools[Komma- of spaasjeskieden list mei tastiene toolnammen (bygl. "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Komma- of spaasjeskieden list mei tastiene toolnammen (camelCase-formaat)]:tools:'
    '--tools[Jou list mei beskikbere tools út ynboude set op. Allinne printmodus]:tools:'
    '--disallowed-tools[Komma- of spaasjeskieden list mei net-tastiene toolnammen (bygl. "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Komma- of spaasjeskieden list mei net-tastiene toolnammen (camelCase-formaat)]:tools:'
    '--mcp-config[MCP-servers lade út JSON-triem of string (spaasjeskieden)]:configs:'
    '--system-prompt[Systeemprompt om te brûken foar de sesje]:prompt:'
    '--append-system-prompt[Systeemprompt oan standert systeemprompt taheakje]:prompt:'
    '--permission-mode[Tastimmingsmodus om te brûken foar de sesje]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Trochgean mei it meast resinte petear]'
    '(-r --resume)'{-r,--resume}'[In petear ferfetsje - jou sesje-ID op of selektearje ynteraktyf]:sessionId:_claude_sessions'
    '--fork-session[Nije sesje-ID oanmeitsje ynstee fan de orizjinele sesje-ID op '\''e nij te brûken by it ferfetsjen (mei --resume of --continue)]'
    '--no-session-persistence[Sesjepersistinsje útskeakelje - sesjes wurde net bewarre (allinne --print)]'
    '--model[Model foar de hjoeddeistige sesje. Jou alias op foar it nijste model (bygl. '\''sonnet'\'' of '\''opus'\'')]:model:'
    '--agent[Agint foar de hjoeddeistige sesje. Oerskriuwt de '\''agent'\''-ynstelling]:agent:'
    '--betas[Beta-headers om op te nimmen yn API-fersiken (allinne API-kaaibrûkers)]:betas:'
    '--fallback-model[Automatyske fallback nei oanjûn model ynskeakelje as it standertmodel oerladen is (allinne --print)]:model:'
    '--settings[Paad nei ynstellings-JSON-triem of JSON-string om ekstra ynstellings te laden]:file-or-json:_files'
    '--add-dir[Ekstra mappen om tooltagong ta te stean]:directories:_directories'
    '--ide[Automatysk ferbine mei IDE by it opstarten as der krekt ien jildige IDE beskikber is]'
    '--strict-mcp-config[Allinne MCP-servers út --mcp-config brûke en alle oare MCP-ynstellings negearje]'
    '--session-id[Spesifike sesje-ID om te brûken foar it petear (moat jildige UUID wêze)]:uuid:'
    '--agents[JSON-objekt dat oanpaste aginten definiearret]:json:'
    '--setting-sources[Kommaskieden list mei ynstellingsboarnen om te laden (user, project, local)]:sources:'
    '--plugin-dir[Map om plugins út te laden allinne foar dizze sesje (werhelber)]:paths:_directories'
    '--disable-slash-commands[Alle slash-kommando'\''s útskeakelje]'
    '(--bg --background)'{--bg,--background}'[De sesje starte as eftergrûnagint en fuortendaliks weromkeare]'
    '(-w --worktree)'{-w,--worktree}'[In nije git-worktree oanmeitsje foar dizze sesje (opsjoneel in namme opjaan)]::name:'
    '--tmux[In tmux-sesje oanmeitsje foar de worktree (fereasket --worktree)]'
    '(-n --name)'{-n,--name}'[In werjeftenamme foar dizze sesje ynstelle]:name:'
    '--effort[Ynspanningsnivo foar de hjoeddeistige sesje]:level:(low medium high xhigh max)'
    '--debug-file[Debuglochs nei in spesifyk triempaad skriuwe (skeakelet ymplisyt debugmodus yn)]:path:_files'
    '--from-pr[In sesje ferfetsje dy'\''t oan in PR keppele is op nûmer/URL, of iepenje ynteraktive kiezer]::value:'
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
        login|logout)
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
    'install:In plugin ynstallearje út beskikbere marketplaces'
    'i:In plugin ynstallearje út beskikbere marketplaces (koart foar install)'
    'init:In nije plugin opsette (laadt automatysk yn folgjende sesje)'
    'uninstall:In ynstallearre plugin de-ynstallearje'
    'remove:In ynstallearre plugin de-ynstallearje (alias foar uninstall)'
    'enable:In útskeakele plugin ynskeakelje'
    'disable:In ynskeakele plugin útskeakelje'
    'update:In plugin bywurkje nei de nijste ferzje'
    'eval:Eval-gefallen tsjin in plugin útfiere en beskoarde resultaten rapportearje'
    'prune:Automatysk ynstallearre ôfhinklikheden fuortsmite dy'\''t net mear nedich binne'
    'tag:In {name}--v{version} git-tag oanmeitsje foar in pluginrelease'
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
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Ynstallaasjeberik]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Ynstallaasjeberik]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Ynstallaasjeberik]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Ynstallaasjeberik]:scope:(user project local managed)' \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list|prune)
          _arguments \
            '(-h --help)'{-h,--help}'[Help sjen litte]'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init)
          _arguments \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '1:target:'
          ;;
        tag)
          _arguments \
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '1:path:_files'
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
            '(-h --help)'{-h,--help}'[Help sjen litte]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Help sjen litte]'
          ;;
        remove|rm)
          _arguments \
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
    '--agent[Standertagint foar sesjes ferstjoerd út de agintwerjefte]:agent:' \
    '--all[Mei --json: nim ek foltôge eftergrûnsesjes op]' \
    '--allow-dangerously-skip-permissions[Bypass-permissions-modus beskikber meitsje foar ferstjoerde sesjes]' \
    '--cwd[Allinne eftergrûnsesjes toane dy'\''t ûnder paad starten binne]:path:_directories' \
    '--dangerously-skip-permissions[Alias foar --permission-mode bypassPermissions]' \
    '--effort[Standert ynspanningsnivo foar ferstjoerde sesjes]:level:(low medium high xhigh max)' \
    '--json[Aktive sesjes as JSON-array printsje en ôfslute]' \
    '*--mcp-config[MCP-serverkonfiguraasje om ta te passen op ferstjoerde sesjes]:config:' \
    '--model[Standertmodel foar sesjes ferstjoerd út de agintwerjefte]:model:' \
    '--permission-mode[Standert tastimmingsmodus foar ferstjoerde sesjes]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Plugins lade út map foar de agintwerjefte en ferstjoerde sesjes]:path:_directories' \
    '--setting-sources[Kommaskieden list mei ynstellingsboarnen om te laden (user, project, local)]:sources:' \
    '--settings[Ynstellingstriem of JSON-string om ta te passen]:file-or-json:_files' \
    '--strict-mcp-config[Allinne MCP-servers út --mcp-config brûke yn ferstjoerde sesjes]' \
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
        login|logout|status)
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
        config|critique|defaults|reset)
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
            '(-h --help)'{-h,--help}'[Help foar kommando sjen litte]' \
            '1:path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[De rûge bugs.json-payload printsje ynstee fan opmakke befinings]' \
    '--timeout[Maksimaal oantal minuten om te wachtsjen oant de review klear is]:minutes:' \
    '(-h --help)'{-h,--help}'[Help foar kommando sjen litte]' \
    '1:target:'
}

(( $+_comps[claude] )) || compdef _claude claude
