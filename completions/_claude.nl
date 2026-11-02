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
    'mcp:MCP-servers configureren en beheren'
    'plugin:Claude Code plugins beheren'
    'agents:Achtergrondagents beheren'
    'attach:Een achtergrondsessie in deze terminal openen'
    'logs:De recente terminaluitvoer van een achtergrondsessie weergeven'
    'stop:Een achtergrondsessie stoppen (het gesprek blijft bewaard)'
    'respawn:Een achtergrondsessie herstarten zodat deze de huidige Claude Code-versie draait'
    'rm:Een achtergrondsessie verwijderen, en de worktree ervan als dat veilig kan'
    'remote-control:Lokale sessies bedienen vanuit claude.ai/code of de mobiele Claude-app'
    'daemon:De supervisor voor achtergrondsessies beheren'
    'auth:Authenticatie beheren'
    'auto-mode:Configuratie van auto-modus-classifier inspecteren of resetten'
    'gateway:De enterprise-auth/telemetrie-gateway uitvoeren'
    'self-hosted-runner:Claude Code-cloudsessies hosten op deze machine of container'
    'import:Configuratie van een andere AI-codeeragent in Claude Code importeren'
    'project:Claude Code projectstatus beheren'
    'purge:Alle Claude Code-status voor een project verwijderen (transcripties, taken, bestandsgeschiedenis, configuratie-invoer)'
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
    '--dangerously-skip-permissions[Alle toestemmingscontroles omzeilen. Alleen aanbevolen voor sandboxes zonder internettoegang]'
    '--allow-dangerously-skip-permissions[Optie inschakelen om toestemmingscontroles te omzeilen zonder dit standaard in te schakelen]'
    '--restricted[Beperkte modus: tools die opdrachten of code uitvoeren en WebFetch verwijderen, user/project/local-instellingen negeren en bestandstools tot de werkmappen beperken]'
    '--max-budget-usd[Maximaal dollarbedrag te besteden aan API-aanroepen (alleen --print)]:amount:'
    '--max-turns[Het aantal agentische beurten beperken (alleen --print)]:turns:'
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
    '(--append-subagent-system-prompt-file)--append-subagent-system-prompt[Tekst toevoegen aan de systeemprompt van elke subagent (alleen --print)]:prompt:'
    '(--append-subagent-system-prompt)--append-subagent-system-prompt-file[Tekst uit een bestand lezen en toevoegen aan de systeemprompts van subagents (alleen --print)]:file:_files'
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
    '--advisor[De server-side adviseurtool voor deze sessie inschakelen met een modelalias of volledige model-ID]:model:_claude_model_names'
    '--teammate-mode[Hoe teamgenoten in een agentteam worden weergegeven]:mode:(in-process auto tmux iterm2)'
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
    '(--remote)--cloud[Een cloudsessie met de opgegeven beschrijving aanmaken, of koppelen aan een bestaande via sessie-ID of claude.ai/code-URL]::description-or-session:'
    '(--cloud)--remote[Verouderde alias voor --cloud]::description-or-session:'
    '--environment[Een nieuwe cloudsessie aanmaken die draait op de opgegeven zelfgehoste omgeving (ccpool_...)]:environment_id:'
    '--ref[Met --environment: de checkout van de nieuwe sessie baseren op een benoemde ref in plaats van lokale HEAD]:branch:'
    '(--remote-control --rc)'{--remote-control,--rc}'[Een interactieve sessie starten met Remote Control ingeschakeld (optioneel benoemd)]::name:'
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
    '*--channels[(Onderzoeksvoorbeeld) MCP-servers waarvan naar kanaalmeldingen wordt geluisterd (plugin\:<name>@<marketplace>)]:entries:'
    '*--dangerously-load-development-channels[Kanalen die niet op de goedgekeurde toelatingslijst staan inschakelen, voor lokale ontwikkeling (plugin\:<name>@<marketplace> of server\:<name>)]:entries:'
    '--init[Setup-hooks met de init-matcher uitvoeren vóór de sessie (alleen --print)]'
    '--init-only[Setup- en SessionStart-hooks uitvoeren en daarna afsluiten zonder een gesprek te starten]'
    '--maintenance[Setup-hooks met de maintenance-matcher uitvoeren vóór de sessie (alleen --print)]'
    '--safe-mode[Starten met alle aanpassingen uitgeschakeld (handig voor het oplossen van een kapotte configuratie)]'
    '--bare[Minimale modus: hooks, LSP, plugin-synchronisatie, attributie, auto-geheugen en CLAUDE.md-autodetectie overslaan]'
    '--ax-screen-reader[Schermlezervriendelijke uitvoer weergeven (platte tekst, geen decoratieve randen of animaties)]'
    '(-v --version)'{-v,--version}'[Versienummer weergeven]'
    '(-h --help)'{-h,--help}'[Help voor commando weergeven]'
  )

  # Stop at the first non-option word, so that the options after a command reach
  # that command's own specs instead of being consumed here
  _arguments -C -A '-*' \
    $main_options \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'claude commando’s' main_commands
      ;;
    args)
      case $words[1] in
        mcp)
          _claude_mcp
          ;;
        plugin|plugins)
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
        remote-control|rc|remote|sync|bridge)
          _claude_remote_control
          ;;
        daemon)
          _claude_daemon
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
        self-hosted-runner)
          _claude_self_hosted_runner
          ;;
        import)
          _claude_import
          ;;
        project)
          _claude_project
          ;;
        purge)
          _claude_purge
          ;;
        ultrareview)
          _claude_ultrareview
          ;;
        setup-token|doctor|update|upgrade)
          _arguments \
            '(-h --help)'{-h,--help}'[Help voor commando weergeven]'
          ;;
        *)
          # Not a command but the prompt: options may still follow it
          _arguments \
            $main_options \
            '*: :'
          ;;
      esac
      ;;
  esac
  local ret=$?

  # The last step, such as listing commands for --r, can fail although options
  # were added before it. Report success then: on failure zsh moves on to the
  # next completers, and _correct or _approximate pile on corrections
  (( compstate[nmatches] > 0 )) || return $ret
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
      _describe -t commands 'mcp commando’s' mcp_commands
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
      _describe -t commands 'plugin commando’s' plugin_commands
      ;;
    args)
      case $words[1] in
        validate)
          _arguments \
            '--strict[Waarschuwingen als fouten behandelen (exitcode 1)]' \
            '--profile[Ook afsluiten met exit 1 als de benoemde catalogus een inzending van de plugin zou weigeren op een controle die dit commando uitvoert]:name:(directory)' \
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
            '--accept-command[Het door de marketplace gedeclareerde commando accepteren waarvan een eerdere --json-run de sha256 als shownCommand.sha256 meldde]:sha256:' \
            '*--config[Een in het pluginmanifest gedeclareerde userConfig-optie instellen (herhaalbaar)]:key=value:' \
            '--marketplace[De plugin op kale naam installeren vanuit de marketplace op deze bron (owner/repo, git- of https-URL, of pad), en die zo nodig eerst toevoegen]:source:' \
            '--registry[Voor een package@npm-installatie: resolven en downloaden vanuit dit npm-register]:url:' \
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
            '--accept-command[Het door de marketplace gedeclareerde commando accepteren waarvan een eerdere --json-run de sha256 als shownCommand.sha256 meldde]:sha256:' \
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
            '--data-size[De opgeslagen datamap van elke geïnstalleerde plugin meten, of alleen van de benoemde plugin (vereist --json)]::plugin:_claude_installed_plugins' \
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
          if [[ $words[2] == init ]]; then
            _arguments \
              '--bare[Een leeg sjabloon schrijven in plaats van het interview uit te voeren]' \
              '--eval-dir[Map onder de huidige map waarin cases worden geschreven]:dir:_directories' \
              '(-i --interactive)'{-i,--interactive}'[Het opstelinterview uitvoeren (vereist een interactieve terminal)]' \
              '(-h --help)'{-h,--help}'[Help weergeven]' \
              '::name:'
            return
          fi
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
            '*--disallow-tools[Ingebouwde tools die Claude in elk geval worden onthouden, ook als ze zijn toegestaan]:tools:' \
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
            '::target: _alternative "commands\:eval command\:(init)" "plugins\:installed plugin\:_claude_installed_plugins" "files\:path\:_files"'
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
      _describe -t commands 'marketplace commando’s' marketplace_commands
      ;;
    args)
      case $words[1] in
        add)
          _arguments \
            '--sparse[Checkout beperken tot specifieke mappen via git sparse-checkout (voor monorepo'\''s)]:paths:' \
            '--scope[Waar de marketplace wordt gedeclareerd]:scope:(user project local)' \
            '--json[Eén machineleesbare resultaatregel afdrukken als laatste regel op stdout]' \
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
            '--json[Eén machineleesbare resultaatregel afdrukken als laatste regel op stdout]' \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:name:'
          ;;
        update)
          _arguments \
            '--json[Met een marketplacenaam: één machineleesbare resultaatregel afdrukken als laatste regel op stdout]' \
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
      _describe -t commands 'auth commando’s' auth_commands
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
      _describe -t commands 'auto-mode commando’s' auto_mode_commands
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
      _describe -t commands 'project commando’s' project_commands
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

_claude_purge() {
  _arguments \
    '--dry-run[Tonen wat verwijderd zou worden zonder iets te verwijderen]' \
    '(-y --yes)'{-y,--yes}'[De bevestigingsvraag overslaan]' \
    '(-i --interactive)'{-i,--interactive}'[Vóór het verwijderen per item om bevestiging vragen]' \
    '(1)--all[De status van elk project wissen (niet te combineren met een pad)]' \
    '(-h --help)'{-h,--help}'[Help voor commando weergeven]' \
    '(--all)::path:_directories'
}

_claude_ultrareview() {
  _arguments \
    '--json[De ruwe bugs.json-payload afdrukken in plaats van geformatteerde bevindingen]' \
    '--timeout[Maximaal aantal minuten wachten tot de review klaar is (standaard: 45)]:minutes:' \
    '(--no-post)--post[De bevindingen van de voltooide review namens jou in de PR plaatsen (alleen voor PR'\''s; één gewone opmerking, geen review)]' \
    '(--post)--no-post[De bevindingen niet in de PR plaatsen (standaard)]' \
    '--trust-workspace[De huidige map alleen voor deze run vertrouwen, zonder te vragen (voor scripts en CI)]' \
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

_claude_self_hosted_runner() {
  _arguments \
    '--api-url[API-basis-URL (standaard: https://api.anthropic.com)]:url:' \
    '--environment-secret-file[Pad naar het geheimenbestand van de omgeving]:path:_files' \
    '--lock-to-account[Runner bij registratie vastzetten op één account]:id:' \
    '--client-label[Observability-label dat bij registratie wordt verzonden (standaard: hostname)]:label:' \
    '(--proxy-authorization-file --agent-proxy-url)--proxy-authorization-command[Commando waarvan de stdout de Proxy-Authorization-header voor uitgaande proxy’s is]:shell command:' \
    '(--proxy-authorization-command --agent-proxy-url)--proxy-authorization-file[Bestand met de Proxy-Authorization-header voor uitgaande proxy’s]:path:_files' \
    '(--proxy-authorization-command --proxy-authorization-file)--agent-proxy-url[Elke sessie via de agentproxy op deze URL leiden (alleen https)]:url:' \
    '--capacity[Maximaal aantal gelijktijdige sessies (standaard: 1)]:n:' \
    '--base-dir[Basismap voor repo-checkouts (standaard: /workspace)]:path:_directories' \
    '--exec-path[Binary om te starten voor kindsessies (standaard: deze binary)]:path:_files' \
    '--hooks-dir[Map met lifecycle-hookscripts (checkout, command, post-session)]:path:_directories' \
    '--session-stop-grace-sec[Hoe lang op een nette afsluiting wordt gewacht nadat een sessie eindigt (standaard: 5)]:n:' \
    '--post-session-hook-timeout-sec[SIGTERM-tijdsbudget voor de post-session-hook (standaard: 60)]:n:' \
    '--checkout-hook-timeout-min[Wandkloktijdbudget voor elke run van de checkout-hook (standaard: 30; 0 schakelt uit)]:n:' \
    '--drain-wait-sec[Bij SIGTERM/SIGINT tot N seconden wachten op lopend werk (standaard: 0)]:n:' \
    '--drain-marker-file[Markeringsbestand waarmee de host een nette drain aankondigt]:path:_files' \
    '*--git-ssh-rewrite[https://<host>/...-bron-URL’s herschrijven naar git@<host>:... (herhaalbaar)]:host:' \
    '*--git-host-rewrite[https://<f>/...-bron-URL’s herschrijven naar https://<t>/... (herhaalbaar)]:from=to:' \
    '--use-anthropic-git-proxy[Door Anthropic beheerde git gebruiken. WAARSCHUWING: verwijdert en vervangt de git-configuratie op HOME-niveau, alleen gebruiken onder een speciaal account]' \
    '--configure-git[De globale git-identiteit instellen en commit-ondertekening inschakelen via de ondertekeningsservice van Anthropic. Schrijft ~/.gitconfig]' \
    '--push-outcome-on-release[Gevolgde resultaatbranches pushen bij een door de runner geïnitieerd, niet-voltooid sessie-einde]' \
    '--trust-workspace[Persistent vertrouwen voor de repopaden van elke sessie vooraf instellen (standaard: true)]::bool:(true false)' \
    '--remove-session-state[Status per sessie verwijderen wanneer een sessie eindigt (standaard: false)]::bool:(true false)' \
    '--diff-finds-nested-repository[Een in een submap gekloonde repository tonen in het Changes-paneel; vereist --capacity 1 (standaard: false)]::bool:(true false)' \
    '--confine-repo-settings[Bewakingsmodus die in de repo gecommitte instellingen beperkt (standaard: warn)]:mode:(warn enforce off)' \
    '--server-auto-mode-lists[Welke classifierlijsten voor auto-modus een sessie van de server mag ontvangen (standaard: no-allow)]:mode:(all no-allow none)' \
    '--host-config-snapshot[Waar de opstartsnapshot van de hostconfiguratie wordt bewaard (standaard: disk)]:mode:(disk memory)' \
    '--health-port[Poort voor de /healthz-HTTP-listener (standaard: 8080; 0 schakelt uit)]:port:' \
    '--log-level[Logniveau (standaard: info)]:level:(info debug)' \
    '--log-file[Runnerlogs ook in toevoegmodus naar een bestand schrijven (tee)]:path:_files' \
    '--exit-if-unused-min[De runner afsluiten als er N minuten lang nooit werk is toegewezen]:n:' \
    '--drain-grace-sec[Seconden om na afloop van actieve sessies te blijven pollen naar werk (standaard: 0)]:n:' \
    '--retire-at[De runner op dit absolute Unix-tijdstip, in seconden, buiten gebruik stellen]:epoch-seconds:' \
    '--defer-shutdown-max-min[Bij de eerste SIGTERM/SIGINT stoppen met werk aannemen en het afsluiten M minuten later voltooien (standaard: 0)]:m:' \
    '--release-idle-session-min[Een sessieslot vrijgeven na N minuten zonder gebruikersinvoer]:n:' \
    '--startup-timeout-min[Een sessieslot vrijgeven als het kindproces na N minuten nog niet klaar is met opstarten (standaard: 15; 0 schakelt uit)]:n:' \
    '--kill-session-after-min[De wandklok-levensduur van een sessiekindproces beperken tot N minuten]:n:' \
    '--debug-token-dir[ALLEEN VOOR DEBUGGEN: schrijft live tokens naar schijf. Niet gebruiken in productie]:path:_directories' \
    '(-h --help)'{-h,--help}'[Dit helpbericht weergeven]'
}

_claude_remote_control() {
  _arguments \
    '--name[Naam voor de sessie (getoond in claude.ai/code)]:name:' \
    '--remote-control-session-name-prefix[Voorvoegsel voor automatisch gegenereerde sessienamen (standaard: hostname)]:prefix:' \
    '(-c --continue --session-id)'{-c,--continue}'[Opnieuw verbinden met de sessie die het laatst is vastgelegd voor deze map of een van haar git-worktrees]' \
    '(-c --continue --session-id)--session-id[Opnieuw verbinden met een specifieke sessie via ID]:id:' \
    '--permission-mode[Toestemmingsmodus voor gestarte sessies]:mode:(acceptEdits auto bypassPermissions default dontAsk plan)' \
    '(--no-chrome)--chrome[Claude in Chrome inschakelen voor gestarte sessies]' \
    '(--chrome)--no-chrome[Claude in Chrome uitschakelen voor gestarte sessies]' \
    '(-d --debug)'{-d,--debug}'[Debugmodus inschakelen met optionele categoriefiltering]::filter:' \
    '--debug-file[Debuglogs naar bestand schrijven]:path:_files' \
    '(-v --verbose)'{-v,--verbose}'[Uitgebreide uitvoer inschakelen]' \
    '--spawn[Startmodus (standaard: same-dir)]:mode:(same-dir worktree session)' \
    '--capacity[Maximaal aantal gelijktijdige sessies in worktree- of same-dir-modus (standaard: 32)]:n:' \
    '(--no-create-session-in-dir)--create-session-in-dir[Vooraf een sessie aanmaken in de huidige map (standaard)]' \
    '(--create-session-in-dir)--no-create-session-in-dir[Geen sessie vooraf aanmaken in de huidige map]' \
    '(-h --help)'{-h,--help}'[Deze help weergeven]'
}

_claude_daemon() {
  local -a daemon_commands common_options
  daemon_commands=(
    'run:De supervisor op de voorgrond uitvoeren'
    'status:Pid, versie en uptime van de daemon weergeven'
    'logs:Het daemonlog volgen (Ctrl-C om te stoppen)'
    'uninstall:De achtergrondservice verwijderen (launchctl/systemd)'
    'stop:De supervisor afsluiten en achtergrondsessies beëindigen'
  )
  common_options=(
    '--json-path[Configuratiebestand (standaard: ~/.claude/daemon.json)]:path:_files'
    '--log-file[Logbestand (standaard: ~/.claude/daemon.log)]:path:_files'
    '(-h --help)'{-h,--help}'[Deze help weergeven]'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    $common_options \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'daemon commando’s' daemon_commands
      ;;
    args)
      case $words[1] in
        run)
          _arguments \
            $common_options \
            '::json-path:_files'
          ;;
        stop)
          _arguments \
            $common_options \
            '--any[Ook een tijdelijke daemon (geen service) stoppen]' \
            '--keep-workers[Losgekoppelde sessies laten doorlopen]'
          ;;
        status|logs|uninstall)
          _arguments \
            $common_options
          ;;
      esac
      ;;
  esac
}

_claude_import() {
  _arguments \
    '--dry-run[Tonen wat geïmporteerd zou worden zonder iets te schrijven]' \
    '--yes[De interactieve keuzelijst overslaan (in headless-omgevingen --yes=<digest> uit de /import-voorvertoning opgeven)]' \
    '(-h --help)'{-h,--help}'[Help voor commando weergeven]' \
    '::source:(codex gemini cursor)'
}

# compinit autoloads this file, and that first call only defines the functions
# above: complete right away so the first TAB already works. Sourced directly,
# there is nothing to complete yet, only the registration.
if [[ $funcstack[1] == _claude ]]; then
  _claude "$@"
else
  (( $+_comps[claude] )) || compdef _claude claude
fi
