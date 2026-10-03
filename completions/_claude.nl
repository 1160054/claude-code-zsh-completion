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

        # Describe each session with the first thing you typed in it. Only the
        # head of the transcript is read - these files grow into the megabytes.
        summary=$(head -c 200000 "$session_file" 2>/dev/null | \
          grep -m 1 -o '"role":"user","content":"[^"]\{1,60\}' 2>/dev/null | \
          sed 's/.*"content":"//; s/\\n/ /g; s/\\*$//')
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
    'mcp:MCP-servers configureren en beheren'
    'plugin:Claude Code plugins beheren'
    'agents:Achtergrondagents beheren'
    'attach:Een achtergrondsessie in deze terminal openen'
    'logs:De recente terminaluitvoer van een achtergrondsessie weergeven'
    'stop:Een achtergrondsessie stoppen (het gesprek blijft bewaard)'
    'respawn:Een achtergrondsessie herstarten zodat deze de huidige Claude Code-versie draait'
    'rm:Een achtergrondsessie verwijderen, en de worktree ervan als dat veilig kan'
    'auth:Authenticatie beheren'
    'auto-mode:Configuratie van auto-modus-classifier inspecteren of resetten'
    'gateway:De enterprise-auth/telemetrie-gateway uitvoeren'
    'import:Configuratie van een andere AI-codeeragent in Claude Code importeren'
    'project:Claude Code projectstatus beheren'
    'ultrareview:Een cloud-gehoste multi-agent codereview uitvoeren en de bevindingen afdrukken'
    'setup-token:Langdurig authenticatietoken instellen (vereist Claude-abonnement)'
    'doctor:Gezondheidscontrole voor Claude Code auto-updater'
    'update:Controleren op en installeren van updates'
    'install:Native build van Claude Code installeren'
  )

  local -a main_options
  main_options=(
    '(-d --debug)'{-d,--debug}'[Debugmodus inschakelen met optionele categoriefiltering (bijv. "api,hooks" of "!statsig,!file")]:filter:'
    '--verbose[Verbose-modus-instelling uit configuratiebestand overschrijven]'
    '(-p --print)'{-p,--print}'[Reactie afdrukken en afsluiten (voor gebruik met pipes). Let op: alleen gebruiken in vertrouwde mappen]'
    '--output-format[Uitvoerformaat (met --print): "text" (standaard), "json" (enkel resultaat), of "stream-json" (realtime streaming)]:format:(text json stream-json)'
    '--json-schema[JSON-schema voor gestructureerde uitvoervalidatie]:schema:'
    '--include-partial-messages[Gedeeltelijke berichtfragmenten opnemen zodra ze binnenkomen (met --print en --output-format=stream-json)]'
    '--input-format[Invoerformaat (met --print): "text" (standaard) of "stream-json" (realtime streaming-invoer)]:format:(text stream-json)'
    '--mcp-debug[\[Verouderd. Gebruik --debug\] MCP-debugmodus inschakelen (toont MCP-serverfouten)]'
    '--dangerously-skip-permissions[Alle toestemmingscontroles omzeilen. Alleen aanbevolen voor sandboxes zonder internettoegang]'
    '--allow-dangerously-skip-permissions[Optie inschakelen om toestemmingscontroles te omzeilen zonder dit standaard in te schakelen]'
    '--restricted[Beperkte modus: tools die opdrachten of code uitvoeren en WebFetch verwijderen, user/project/local-instellingen negeren en bestandstools tot de werkmappen beperken]'
    '--max-budget-usd[Maximaal dollarbedrag te besteden aan API-aanroepen (alleen --print)]:amount:'
    '--replay-user-messages[Gebruikersberichten opnieuw verzenden van stdin naar stdout ter bevestiging]'
    '--allowed-tools[Komma- of spatiegescheiden lijst van toegestane toolnamen (bijv. "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Komma- of spatiegescheiden lijst van toegestane toolnamen (camelCase-formaat)]:tools:'
    '--tools[Lijst van beschikbare tools uit ingebouwde set specificeren. Alleen printmodus]:tools:'
    '--disallowed-tools[Komma- of spatiegescheiden lijst van niet-toegestane toolnamen (bijv. "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Komma- of spatiegescheiden lijst van niet-toegestane toolnamen (camelCase-formaat)]:tools:'
    '--mcp-config[MCP-servers laden uit JSON-bestand of -string (spatiegescheiden)]:configs:'
    '--system-prompt[Systeemprompt te gebruiken voor sessie]:prompt:'
    '--system-prompt-file[Systeemprompt uit een bestand lezen]:file:_files'
    '--append-system-prompt[Systeemprompt toevoegen aan standaard systeemprompt]:prompt:'
    '--append-system-prompt-file[Systeemprompt uit een bestand lezen en aan de standaard systeemprompt toevoegen]:file:_files'
    '--system-prompt-snapshot[De systeemprompt eenmaal per gesprek vastleggen en letterlijk hergebruiken bij elk verzoek en elke hervatting (on, standaard) of bij elk verzoek opnieuw opbouwen (off)]:mode:(on off)'
    '--permission-mode[Toestemmingsmodus te gebruiken voor sessie]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '--permission-prompts[Wie toestemmingsvragen beantwoordt met --print: "host" (de SDK-host of --permission-prompt-tool) of "none" (alles wat een vraag zou opleveren wordt geweigerd)]:target:(host none)'
    '--permission-prompt-tool[MCP-tool voor toestemmingsvragen (alleen --print)]:tool:'
    '(-c --continue)'{-c,--continue}'[Het meest recente gesprek voortzetten]'
    '(-r --resume)'{-r,--resume}'[Een gesprek hervatten - specificeer sessie-ID of selecteer interactief]:sessionId:_claude_sessions'
    '--fork-session[Nieuwe sessie-ID aanmaken in plaats van originele sessie-ID hergebruiken bij hervatten (met --resume of --continue)]'
    '--no-session-persistence[Sessiepersistentie uitschakelen - sessies worden niet opgeslagen (alleen --print)]'
    '--model[Model voor huidige sessie. Specificeer alias voor nieuwste model (bijv. '\''sonnet'\'' of '\''opus'\'')]:model:_claude_model_names'
    '--agent[Agent voor de huidige sessie. Overschrijft de '\''agent'\''-instelling]:agent:_claude_agent_names'
    '--betas[Beta-headers om op te nemen in API-verzoeken (alleen API-sleutelgebruikers)]:betas:'
    '--fallback-model[Automatische terugval naar gespecificeerd model inschakelen wanneer standaardmodel overbelast is (alleen --print)]:model:_claude_model_names'
    '--settings[Pad naar instellingen-JSON-bestand of JSON-string om aanvullende instellingen te laden]:file-or-json:_files'
    '--add-dir[Aanvullende mappen om tooltoegang toe te staan]:directories:_directories'
    '--ide[Automatisch verbinden met IDE bij opstarten als precies één geldige IDE beschikbaar is]'
    '--desktop[Openen in de Claude Desktop-app in plaats van de terminal (met --continue of --resume <id> om de sessie te kiezen)]'
    '--strict-mcp-config[Alleen MCP-servers uit --mcp-config gebruiken en alle andere MCP-instellingen negeren]'
    '--session-id[Specifieke sessie-ID te gebruiken voor gesprek (moet geldige UUID zijn)]:uuid:'
    '--agents[JSON-object dat aangepaste agents definieert]:json:'
    '--setting-sources[Kommagescheiden lijst van instellingsbronnen te laden (user, project, local)]:sources:'
    '--plugin-dir[Map om plugins uit te laden voor alleen deze sessie (herhaalbaar)]:paths:_directories'
    '--disable-slash-commands[Alle slash-commando'\''s uitschakelen]'
    '(--bg --background)'{--bg,--background}'[De sessie starten als achtergrondagent en direct terugkeren]'
    '(-w --worktree)'{-w,--worktree}'[Een nieuwe git-worktree voor deze sessie aanmaken (optioneel een naam specificeren)]::name:'
    '--tmux=-[Een tmux-sessie voor de worktree aanmaken (vereist --worktree). Gebruikt native iTerm2-panelen indien beschikbaar; --tmux=classic voor traditionele tmux]::mode:(classic)'
    '(-n --name)'{-n,--name}'[Een weergavenaam voor deze sessie instellen]:name:'
    '--effort[Inspanningsniveau voor de huidige sessie]:level:(low medium high xhigh max)'
    '--autocompact[Venstergrootte voor automatisch comprimeren (auto, of 100k-1M tokens)]:size:(auto)'
    '--debug-file[Debuglogs naar een specifiek bestandspad schrijven (schakelt impliciet debugmodus in)]:path:_files'
    '--from-pr[Een sessie gekoppeld aan een PR hervatten via nummer/URL, of interactieve kiezer openen]::value:'
    '--teleport[Een teleportsessie hervatten, optioneel met sessie-ID]::session:'
    '--cloud[Een cloudsessie met de opgegeven beschrijving aanmaken, of koppelen aan een bestaande via sessie-ID of claude.ai/code-URL]::description-or-session:'
    '--environment[Een nieuwe cloudsessie aanmaken die draait op de opgegeven zelfgehoste omgeving (ccpool_...)]:environment_id:'
    '--remote-control[Een interactieve sessie starten met Remote Control ingeschakeld (optioneel benoemd)]::name:'
    '--remote-control-session-name-prefix[Prefix voor automatisch gegenereerde Remote Control-sessienamen]:prefix:'
    '--chrome[Claude in Chrome-integratie inschakelen]'
    '--no-chrome[Claude in Chrome-integratie uitschakelen]'
    '--plugin-url[Een plugin-.zip ophalen van een URL voor alleen deze sessie (herhaalbaar)]:url:'
    '--file[Bestandsbronnen om te downloaden bij opstarten (formaat: file_id:relative_path)]:specs:'
    '--prompt-suggestions[Promptsuggesties inschakelen (geeft een voorspelde volgende prompt in print/SDK-modus)]::value:(true false 1 0 yes no on off)'
    '--forward-subagent-text[Subagenttekst en denkblokken doorsturen als berichten (met --print en stream-json)]'
    '--include-hook-events[Alle hook-levenscyclusgebeurtenissen opnemen in de uitvoerstroom (met stream-json)]'
    '--exclude-dynamic-system-prompt-sections[Per-machine-secties naar het eerste gebruikersbericht verplaatsen om hergebruik van promptcache te verbeteren]'
    '--brief[SendUserMessage-tool inschakelen voor agent-naar-gebruiker-communicatie]'
    '--safe-mode[Starten met alle aanpassingen uitgeschakeld (handig voor het oplossen van een kapotte configuratie)]'
    '--bare[Minimale modus: hooks, LSP, plugin-synchronisatie, attributie, auto-geheugen en CLAUDE.md-autodetectie overslaan]'
    '--ax-screen-reader[Schermlezervriendelijke uitvoer weergeven (platte tekst, geen decoratieve randen of animaties)]'
    '(-v --version)'{-v,--version}'[Versienummer weergeven]'
    '(-h --help)'{-h,--help}'[Help voor commando weergeven]'
  )

  _arguments -C \
    $main_options \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'claude commando'\''s' main_commands
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
            '(-h --help)'{-h,--help}'[Help voor commando weergeven]' \
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
          _message "geen argumenten"
          ;;
      esac
      ;;
  esac
}

_claude_mcp() {
  local -a mcp_commands
  mcp_commands=(
    'serve:Een Claude Code MCP-server starten'
    'add:Een MCP-server toevoegen aan Claude Code'
    'remove:Een MCP-server verwijderen'
    'list:Geconfigureerde MCP-servers weergeven'
    'get:MCP-serverdetails ophalen'
    'add-json:Een MCP-server (stdio of SSE) toevoegen met JSON-string'
    'add-from-claude-desktop:MCP-servers importeren vanuit Claude Desktop (alleen Mac en WSL)'
    'reset-project-choices:Alle goedgekeurde/afgewezen projectgebonden (.mcp.json) servers in dit project resetten'
    'login:Authenticeren bij een MCP-server (HTTP, SSE, of claude.ai-connector)'
    'logout:Opgeslagen OAuth-inloggegevens voor een MCP-server wissen'
    'help:Help weergeven'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Help weergeven]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'mcp commando'\''s' mcp_commands
      ;;
    args)
      case $words[1] in
        serve)
          _arguments \
            '(-d --debug)'{-d,--debug}'[Debugmodus inschakelen]' \
            '--verbose[Verbose-modus-instelling uit configuratiebestand overschrijven]' \
            '(-h --help)'{-h,--help}'[Help weergeven]'
          ;;
        add)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Configuratiebereik (local, user, project)]:scope:(local user project)' \
            '(-t --transport)'{-t,--transport}'[Transporttype (stdio, sse, http)]:transport:(stdio sse http)' \
            '(-e --env)'{-e,--env}'[Omgevingsvariabele instellen (bijv. -e KEY=value)]:env:' \
            '(-H --header)'{-H,--header}'[WebSocket-header instellen]:header:' \
            '--client-id[OAuth-client-ID voor HTTP/SSE-servers]:clientId:' \
            '--client-secret[Om het OAuth-clientgeheim vragen (of de omgevingsvariabele MCP_CLIENT_SECRET instellen)]' \
            '--callback-port[Vaste poort voor de OAuth-callback (voor servers die vooraf geregistreerde redirect-URI'\''s vereisen)]:port:' \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:name:' \
            '2:commandOrUrl:' \
            '*:args:'
          ;;
        remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Configuratiebereik (local, user, project) - verwijderen uit bestaand bereik indien niet gespecificeerd]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:name:_claude_mcp_servers'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Help weergeven]'
          ;;
        get)
          _arguments \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:name:_claude_mcp_servers'
          ;;
        add-json)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Configuratiebereik (local, user, project)]:scope:(local user project)' \
            '--client-secret[Om het OAuth-clientgeheim vragen (of de omgevingsvariabele MCP_CLIENT_SECRET instellen)]' \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:name:' \
            '2:json:'
          ;;
        add-from-claude-desktop)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Configuratiebereik (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Help weergeven]'
          ;;
        reset-project-choices)
          _arguments \
            '(-h --help)'{-h,--help}'[Help weergeven]'
          ;;
        login)
          _arguments \
            '--no-browser[De autorisatie-URL weergeven in plaats van een browser te openen (voor SSH/headless-sessies)]' \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:name:_claude_mcp_servers'
          ;;
        logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:name:_claude_mcp_servers'
          ;;
      esac
      ;;
  esac
}

_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:Een plugin of marketplace-manifest valideren'
    'marketplace:Claude Code marketplaces beheren'
    'list:Geïnstalleerde plugins weergeven'
    'details:Componentinventaris en verwachte tokenkosten voor een plugin weergeven'
    'configure:De opties van een plugin tonen en welke niet zijn ingesteld, of waarden uit stdin opslaan'
    'install:Een plugin installeren vanuit beschikbare marketplaces'
    'i:Een plugin installeren vanuit beschikbare marketplaces (kort voor install)'
    'init:Een nieuwe plugin opzetten (laadt automatisch bij volgende sessie)'
    'new:Een basisopzet voor een nieuwe plugin aanmaken (alias voor init)'
    'uninstall:Een geïnstalleerde plugin verwijderen'
    'remove:Een geïnstalleerde plugin verwijderen (alias voor uninstall)'
    'enable:Een uitgeschakelde plugin inschakelen'
    'disable:Een ingeschakelde plugin uitschakelen'
    'update:Een plugin bijwerken naar de nieuwste versie'
    'eval:Eval-cases uitvoeren tegen een plugin en gescoorde resultaten rapporteren'
    'prune:Automatisch geïnstalleerde afhankelijkheden verwijderen die niet meer nodig zijn'
    'autoremove:Automatisch geïnstalleerde afhankelijkheden die niet meer nodig zijn verwijderen (alias voor prune)'
    'tag:Een {name}--v{version} git-tag aanmaken voor een plugin-release'
    'test:De tests van een mod uitvoeren'
    'help:Help weergeven'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Help weergeven]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'plugin commando'\''s' plugin_commands
      ;;
    args)
      case $words[1] in
        validate)
          _arguments \
            '--strict[Waarschuwingen als fouten behandelen (exitcode 1)]' \
            '--json[Het validatierapport als JSON uitvoeren (zelfde exitcodes)]' \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Installatiebereik]:scope:(user project local)' \
            '*--config[Een in het pluginmanifest gedeclareerde userConfig-optie instellen (herhaalbaar)]:key=value:' \
            '(-y --yes)'{-y,--yes}'[De getoonde, door de marketplace gedeclareerde opdracht accepteren zonder bevestigingsvraag]' \
            '--json[Eén machineleesbare resultaatregel weergeven in plaats van het bericht voor mensen]' \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Installatiebereik]:scope:(user project local)' \
            '--keep-data[De map met persistente plugingegevens behouden]' \
            '--prune[Ook automatisch geïnstalleerde afhankelijkheden verwijderen die niet meer nodig zijn]' \
            '(-y --yes)'{-y,--yes}'[De bevestigingsvraag van --prune overslaan]' \
            '--json[Eén machineleesbare resultaatregel weergeven in plaats van het bericht voor mensen (niet met --prune)]' \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Installatiebereik]:scope:(user project local)' \
            '--json[Eén machineleesbare resultaatregel weergeven in plaats van het bericht voor mensen]' \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        disable)
          _arguments \
            '(-a --all)'{-a,--all}'[Alle ingeschakelde plugins uitschakelen]' \
            '(-s --scope)'{-s,--scope}'[Installatiebereik]:scope:(user project local)' \
            '--json[Eén machineleesbare resultaatregel weergeven in plaats van het bericht voor mensen]' \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '::plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Installatiebereik]:scope:(user project local managed)' \
            '(-y --yes)'{-y,--yes}'[De getoonde, door de marketplace gedeclareerde opdracht accepteren zonder bevestigingsvraag]' \
            '--json[Eén machineleesbare resultaatregel weergeven in plaats van het bericht voor mensen]' \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list)
          _arguments \
            '--json[Uitvoer als JSON]' \
            '--available[Beschikbare plugins uit marketplaces opnemen (vereist --json)]' \
            '(-h --help)'{-h,--help}'[Help weergeven]'
          ;;
        prune|autoremove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Opschonen binnen bereik]:scope:(user project local)' \
            '--dry-run[Tonen wat verwijderd zou worden zonder te verwijderen]' \
            '(-y --yes)'{-y,--yes}'[De bevestigingsvraag overslaan]' \
            '(-h --help)'{-h,--help}'[Help weergeven]'
          ;;
        configure)
          _arguments \
            '--json[Uitvoer als JSON]' \
            '--values-stdin[Optiewaarden uit stdin lezen als JSON-object met strings van één regel; weggelaten opties behouden hun waarde]' \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init|new)
          _arguments \
            '--description[Beschrijving in het manifest]:text:' \
            '--author[Naam van de auteur (standaard: git config user.name)]:name:' \
            '--author-email[E-mailadres van de auteur (standaard: git config user.email)]:email:' \
            '--with[Componenten waarvoor ook een basisopzet wordt aangemaakt]:components:' \
            '(-f --force)'{-f,--force}'[Een bestaande .claude-plugin/ op de doellocatie overschrijven]' \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '--case[Cases filteren op naam-glob]:glob:' \
            '*--tag[Cases filteren op tag (herhaalbaar)]:tag:' \
            '--runs[Aantal runs per case overschrijven (standaard: case.runs, anders 3)]:n:' \
            '(-j --concurrency)'{-j,--concurrency}'[Tot n agentruns tegelijk uitvoeren (1-8; standaard 1)]:n:' \
            '--model[Model voor alle cases overschrijven]:model:_claude_model_names' \
            '--judge-model[Model van de LLM-beoordelaar overschrijven (standaard: haiku)]:model:_claude_model_names' \
            '--max-cost-usd[Harde kostenlimiet; bij bereiken afbreken en gedeeltelijke resultaten rapporteren (exitcode 2)]:usd:' \
            '--output-dir[Map voor aggregate-result.json]:dir:_directories' \
            '--eval-dir[Mapnaam (binnen de plugin) met de evaluatiecases]:dir:' \
            '--json[Het volledige runresultaat als JSON naar stdout schrijven, of naar dit .json-bestand]::path:_files' \
            '--threshold[Afsluiten met exitcode 1 als een casescore onder deze drempel ligt (standaard: 1.0)]:threshold:' \
            '*--allow-tools[Toestemming van de operator voor afgeschermde tools (Bash, Write, Edit, WebFetch, mcp__*)]:tools:' \
            '(--no-scaffold)--scaffold[Het scaffold_script van elke case uitvoeren (voert door de auteur geleverde bash uit onder jouw account; standaard uit)]' \
            '(--scaffold)--no-scaffold[scaffold_script expliciet overslaan]' \
            '--trust-plugin[Verklaren dat je deze plugin en de evaluatiesuite vertrouwt, zodat de vertrouwensvraag bij de eerste run wordt overgeslagen (voor CI)]' \
            '--ablation[Een basislijn zonder plugin uitvoeren en het scoreverschil rapporteren]:mode:(none with-without)' \
            '--mocks[Mock-vervangers voor MCP-servers, uit <eval dir>/mocks/]:mode:(record off)' \
            '--allow-real-servers[Met --mocks record: ook de echte MCP-serverprocessen starten waarvoor geen mock bestaat]' \
            '--keep-temp[Scaffold-mappen bewaren voor debuggen]' \
            '--verbose[Trace-gebeurtenissen per bericht in het debuglog vastleggen]' \
            '--report[Het zelfstandige HTML-rapport naar dit pad schrijven in plaats van naar de resultatenmap]:path:_files' \
            '(--no-publish)--publish-report[Ook vereisen dat het rapport op claude.ai wordt gepubliceerd]' \
            '(--publish-report)--no-publish[Het HTML-rapport alleen lokaal houden; niet publiceren op claude.ai]' \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '::target: _alternative "plugins\:installed plugin\:_claude_installed_plugins" "files\:path\:_files"'
          ;;
        tag)
          _arguments \
            '--push[De tag na het aanmaken naar --remote pushen]' \
            '--dry-run[Tonen wat getagd zou worden zonder de tag aan te maken]' \
            '(-f --force)'{-f,--force}'[De controles op een gewijzigde werkmap en een al bestaande tag overslaan]' \
            '(-m --message)'{-m,--message}'[Annotatiebericht van de tag (gebruik %s voor de versie)]:msg:' \
            '--remote[Remote waarnaar met --push wordt gepusht]:name:' \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '::path:_files'
          ;;
        test)
          _arguments \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '::dir:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_plugin_marketplace() {
  local -a marketplace_commands
  marketplace_commands=(
    'add:Een marketplace toevoegen vanuit URL, pad, of GitHub-repository'
    'list:Geconfigureerde marketplaces weergeven'
    'remove:Een geconfigureerde marketplace verwijderen'
    'rm:Een geconfigureerde marketplace verwijderen (alias voor remove)'
    'update:Marketplace bijwerken vanuit bron - alles bijwerken als geen naam gespecificeerd'
    'help:Help weergeven'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Help weergeven]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'marketplace commando'\''s' marketplace_commands
      ;;
    args)
      case $words[1] in
        add)
          _arguments \
            '--sparse[Checkout beperken tot specifieke mappen via git sparse-checkout (voor monorepo'\''s)]:paths:' \
            '--scope[Waar de marketplace wordt gedeclareerd]:scope:(user project local)' \
            '--claudeai[De marketplace met deze naam toevoegen die claude.ai voor je host]' \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '--json[Uitvoer als JSON]' \
            '(-h --help)'{-h,--help}'[Help weergeven]'
          ;;
        remove|rm)
          _arguments \
            '--scope[De marketplacedeclaratie uit een specifiek instellingenbereik verwijderen (weglaten om uit elk bereik te verwijderen)]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:name:'
          ;;
        update)
          _arguments \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '::name:'
          ;;
      esac
      ;;
  esac
}

_claude_install() {
  _arguments \
    '--force[Geforceerd installeren zelfs indien al geïnstalleerd]' \
    '(-h --help)'{-h,--help}'[Help weergeven]' \
    '::target:(stable latest)'
}

_claude_agents() {
  _arguments \
    '*--add-dir[Aanvullende map om tooltoegang toe te staan in verzonden sessies]:directory:_directories' \
    '--agent[Standaardagent voor sessies verzonden vanuit agentweergave]:agent:_claude_agent_names' \
    '--all[Met --json: ook voltooide achtergrondsessies opnemen]' \
    '--allow-dangerously-skip-permissions[Bypass-permissions-modus beschikbaar maken voor verzonden sessies]' \
    '--cwd[Alleen achtergrondsessies weergeven die onder pad zijn gestart]:path:_directories' \
    '--dangerously-skip-permissions[Alias voor --permission-mode bypassPermissions]' \
    '--effort[Standaard inspanningsniveau voor verzonden sessies]:level:(low medium high xhigh max)' \
    '--json[Actieve sessies afdrukken als JSON-array en afsluiten]' \
    '*--mcp-config[MCP-serverconfiguratie om toe te passen op verzonden sessies]:config:' \
    '--model[Standaardmodel voor sessies verzonden vanuit agentweergave]:model:_claude_model_names' \
    '--permission-mode[Standaard toestemmingsmodus voor verzonden sessies]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Plugins laden uit map voor de agentweergave en verzonden sessies]:path:_directories' \
    '--setting-sources[Kommagescheiden lijst van instellingsbronnen te laden (user, project, local)]:sources:' \
    '--settings[Instellingenbestand of JSON-string om toe te passen]:file-or-json:_files' \
    '--strict-mcp-config[Alleen MCP-servers uit --mcp-config gebruiken in verzonden sessies]' \
    '--restricted[Verzonden sessies in beperkte modus starten]' \
    '(-h --help)'{-h,--help}'[Help voor commando weergeven]'
}

_claude_auth() {
  local -a auth_commands
  auth_commands=(
    'login:Inloggen op je Anthropic-account'
    'logout:Uitloggen van je Anthropic-account'
    'status:Authenticatiestatus weergeven'
    'help:Help weergeven'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Help voor commando weergeven]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'auth commando'\''s' auth_commands
      ;;
    args)
      case $words[1] in
        login)
          _arguments \
            '--email[E-mailadres vooraf invullen op de inlogpagina]:email:' \
            '--sso[SSO-inlogproces afdwingen]' \
            '(--claudeai)--console[Anthropic Console (facturering op API-gebruik) gebruiken in plaats van een Claude-abonnement]' \
            '(--console)--claudeai[Claude-abonnement gebruiken (standaard)]' \
            '(-h --help)'{-h,--help}'[Help voor commando weergeven]'
          ;;
        status)
          _arguments \
            '(--text)--json[Uitvoer als JSON (standaard)]' \
            '(--json)--text[Uitvoer als voor mensen leesbare tekst]' \
            '(-h --help)'{-h,--help}'[Help voor commando weergeven]'
          ;;
        logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Help voor commando weergeven]'
          ;;
      esac
      ;;
  esac
}

_claude_auto_mode() {
  local -a auto_mode_commands
  auto_mode_commands=(
    'config:De effectieve auto-modus-configuratie afdrukken als JSON'
    'critique:AI-feedback krijgen op je aangepaste auto-modus-regels'
    'defaults:De standaard auto-modus-regels afdrukken als JSON'
    'reset:Auto-modus-configuratie resetten naar de meegeleverde standaardwaarden'
    'help:Help weergeven'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Help voor commando weergeven]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'auto-mode commando'\''s' auto_mode_commands
      ;;
    args)
      case $words[1] in
        critique)
          _arguments \
            '--model[Overschrijven welk model wordt gebruikt]:model:_claude_model_names' \
            '(-h --help)'{-h,--help}'[Help voor commando weergeven]'
          ;;
        defaults)
          _arguments \
            '--label[Alleen regels tonen waarvan het label met dit voorvoegsel begint (hoofdletterongevoelig)]:prefix:' \
            '(-h --help)'{-h,--help}'[Help voor commando weergeven]'
          ;;
        reset)
          _arguments \
            '(-y --yes)'{-y,--yes}'[De bevestigingsvraag overslaan]' \
            '(-h --help)'{-h,--help}'[Help voor commando weergeven]'
          ;;
        config)
          _arguments \
            '(-h --help)'{-h,--help}'[Help voor commando weergeven]'
          ;;
      esac
      ;;
  esac
}

_claude_gateway() {
  _arguments \
    '--config[Pad naar gateway-YAML-configuratie]:path:_files' \
    '(-h --help)'{-h,--help}'[Help voor commando weergeven]'
}

_claude_project() {
  local -a project_commands
  project_commands=(
    'purge:Alle Claude Code-status voor een project verwijderen (transcripties, taken, bestandsgeschiedenis, configuratie-invoer)'
    'help:Help weergeven'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Help voor commando weergeven]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'project commando'\''s' project_commands
      ;;
    args)
      case $words[1] in
        purge)
          _arguments \
            '--dry-run[Tonen wat verwijderd zou worden zonder iets te verwijderen]' \
            '(-y --yes)'{-y,--yes}'[De bevestigingsvraag overslaan]' \
            '(-i --interactive)'{-i,--interactive}'[Vóór het verwijderen per item om bevestiging vragen]' \
            '(1)--all[De status van elk project wissen (niet te combineren met een pad)]' \
            '(-h --help)'{-h,--help}'[Help voor commando weergeven]' \
            '(--all)::path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[De ruwe bugs.json-payload afdrukken in plaats van geformatteerde bevindingen]' \
    '--timeout[Maximaal aantal minuten wachten tot de review klaar is (standaard: 45)]:minutes:' \
    '(--no-post)--post[De bevindingen van de voltooide review namens jou in de PR plaatsen (alleen voor PR'\''s; één gewone opmerking, geen review)]' \
    '(--post)--no-post[De bevindingen niet in de PR plaatsen (standaard)]' \
    '(-h --help)'{-h,--help}'[Help voor commando weergeven]' \
    '1:target:'
}

_claude_respawn() {
  _arguments \
    '(1)--all[Elke actieve achtergrondsessie herstarten]' \
    '(-h --help)'{-h,--help}'[Help voor commando weergeven]' \
    '(--all)::session:_claude_background_sessions'
}

_claude_rm() {
  _arguments \
    '--discard-unpushed[Ook de niet-gepushte commits en niet-gecommitte wijzigingen van de worktree verwijderen (geef de commit@worktree-id op die een eerdere claude rm meldde)]:commit@worktree-id:' \
    '--force-remove-worktree[De worktree-map verwijderen, ook als de WorktreeRemove-hook of git deze niet kon verwijderen (geef de worktree-id op die een eerdere claude rm meldde)]:worktree-id:' \
    '(-h --help)'{-h,--help}'[Help voor commando weergeven]' \
    '1:session:_claude_background_sessions'
}

_claude_import() {
  _arguments \
    '--dry-run[Tonen wat geïmporteerd zou worden zonder iets te schrijven]' \
    '--yes[De interactieve keuzelijst overslaan (in headless-omgevingen --yes=<digest> uit de /import-voorvertoning opgeven)]' \
    '(-h --help)'{-h,--help}'[Help voor commando weergeven]' \
    '::source:(codex gemini cursor)'
}

(( $+_comps[claude] )) || compdef _claude claude
