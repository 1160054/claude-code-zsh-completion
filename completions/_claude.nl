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
    'mcp:MCP-servers configureren en beheren'
    'plugin:Claude Code plugins beheren'
    'agents:Achtergrondagents beheren'
    'auth:Authenticatie beheren'
    'auto-mode:Configuratie van auto-modus-classifier inspecteren of resetten'
    'gateway:De enterprise-auth/telemetrie-gateway uitvoeren'
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
    '--max-budget-usd[Maximaal dollarbedrag te besteden aan API-aanroepen (alleen --print)]:amount:'
    '--replay-user-messages[Gebruikersberichten opnieuw verzenden van stdin naar stdout ter bevestiging]'
    '--allowed-tools[Komma- of spatiegescheiden lijst van toegestane toolnamen (bijv. "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Komma- of spatiegescheiden lijst van toegestane toolnamen (camelCase-formaat)]:tools:'
    '--tools[Lijst van beschikbare tools uit ingebouwde set specificeren. Alleen printmodus]:tools:'
    '--disallowed-tools[Komma- of spatiegescheiden lijst van niet-toegestane toolnamen (bijv. "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Komma- of spatiegescheiden lijst van niet-toegestane toolnamen (camelCase-formaat)]:tools:'
    '--mcp-config[MCP-servers laden uit JSON-bestand of -string (spatiegescheiden)]:configs:'
    '--system-prompt[Systeemprompt te gebruiken voor sessie]:prompt:'
    '--append-system-prompt[Systeemprompt toevoegen aan standaard systeemprompt]:prompt:'
    '--permission-mode[Toestemmingsmodus te gebruiken voor sessie]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Het meest recente gesprek voortzetten]'
    '(-r --resume)'{-r,--resume}'[Een gesprek hervatten - specificeer sessie-ID of selecteer interactief]:sessionId:_claude_sessions'
    '--fork-session[Nieuwe sessie-ID aanmaken in plaats van originele sessie-ID hergebruiken bij hervatten (met --resume of --continue)]'
    '--no-session-persistence[Sessiepersistentie uitschakelen - sessies worden niet opgeslagen (alleen --print)]'
    '--model[Model voor huidige sessie. Specificeer alias voor nieuwste model (bijv. '\''sonnet'\'' of '\''opus'\'')]:model:'
    '--agent[Agent voor de huidige sessie. Overschrijft de '\''agent'\''-instelling]:agent:'
    '--betas[Beta-headers om op te nemen in API-verzoeken (alleen API-sleutelgebruikers)]:betas:'
    '--fallback-model[Automatische terugval naar gespecificeerd model inschakelen wanneer standaardmodel overbelast is (alleen --print)]:model:'
    '--settings[Pad naar instellingen-JSON-bestand of JSON-string om aanvullende instellingen te laden]:file-or-json:_files'
    '--add-dir[Aanvullende mappen om tooltoegang toe te staan]:directories:_directories'
    '--ide[Automatisch verbinden met IDE bij opstarten als precies één geldige IDE beschikbaar is]'
    '--strict-mcp-config[Alleen MCP-servers uit --mcp-config gebruiken en alle andere MCP-instellingen negeren]'
    '--session-id[Specifieke sessie-ID te gebruiken voor gesprek (moet geldige UUID zijn)]:uuid:'
    '--agents[JSON-object dat aangepaste agents definieert]:json:'
    '--setting-sources[Kommagescheiden lijst van instellingsbronnen te laden (user, project, local)]:sources:'
    '--plugin-dir[Map om plugins uit te laden voor alleen deze sessie (herhaalbaar)]:paths:_directories'
    '--disable-slash-commands[Alle slash-commando'\''s uitschakelen]'
    '(--bg --background)'{--bg,--background}'[De sessie starten als achtergrondagent en direct terugkeren]'
    '(-w --worktree)'{-w,--worktree}'[Een nieuwe git-worktree voor deze sessie aanmaken (optioneel een naam specificeren)]::name:'
    '--tmux[Een tmux-sessie voor de worktree aanmaken (vereist --worktree)]'
    '(-n --name)'{-n,--name}'[Een weergavenaam voor deze sessie instellen]:name:'
    '--effort[Inspanningsniveau voor de huidige sessie]:level:(low medium high xhigh max)'
    '--debug-file[Debuglogs naar een specifiek bestandspad schrijven (schakelt impliciet debugmodus in)]:path:_files'
    '--from-pr[Een sessie gekoppeld aan een PR hervatten via nummer/URL, of interactieve kiezer openen]::value:'
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
        login|logout)
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
    'install:Een plugin installeren vanuit beschikbare marketplaces'
    'i:Een plugin installeren vanuit beschikbare marketplaces (kort voor install)'
    'init:Een nieuwe plugin opzetten (laadt automatisch bij volgende sessie)'
    'uninstall:Een geïnstalleerde plugin verwijderen'
    'remove:Een geïnstalleerde plugin verwijderen (alias voor uninstall)'
    'enable:Een uitgeschakelde plugin inschakelen'
    'disable:Een ingeschakelde plugin uitschakelen'
    'update:Een plugin bijwerken naar de nieuwste versie'
    'eval:Eval-cases uitvoeren tegen een plugin en gescoorde resultaten rapporteren'
    'prune:Automatisch geïnstalleerde afhankelijkheden verwijderen die niet meer nodig zijn'
    'tag:Een {name}--v{version} git-tag aanmaken voor een plugin-release'
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
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Installatiebereik]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Installatiebereik]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Installatiebereik]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Installatiebereik]:scope:(user project local managed)' \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list|prune)
          _arguments \
            '(-h --help)'{-h,--help}'[Help weergeven]'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init)
          _arguments \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:target:'
          ;;
        tag)
          _arguments \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:path:_files'
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
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Help weergeven]'
          ;;
        remove|rm)
          _arguments \
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
    '--agent[Standaardagent voor sessies verzonden vanuit agentweergave]:agent:' \
    '--all[Met --json: ook voltooide achtergrondsessies opnemen]' \
    '--allow-dangerously-skip-permissions[Bypass-permissions-modus beschikbaar maken voor verzonden sessies]' \
    '--cwd[Alleen achtergrondsessies weergeven die onder pad zijn gestart]:path:_directories' \
    '--dangerously-skip-permissions[Alias voor --permission-mode bypassPermissions]' \
    '--effort[Standaard inspanningsniveau voor verzonden sessies]:level:(low medium high xhigh max)' \
    '--json[Actieve sessies afdrukken als JSON-array en afsluiten]' \
    '*--mcp-config[MCP-serverconfiguratie om toe te passen op verzonden sessies]:config:' \
    '--model[Standaardmodel voor sessies verzonden vanuit agentweergave]:model:' \
    '--permission-mode[Standaard toestemmingsmodus voor verzonden sessies]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Plugins laden uit map voor de agentweergave en verzonden sessies]:path:_directories' \
    '--setting-sources[Kommagescheiden lijst van instellingsbronnen te laden (user, project, local)]:sources:' \
    '--settings[Instellingenbestand of JSON-string om toe te passen]:file-or-json:_files' \
    '--strict-mcp-config[Alleen MCP-servers uit --mcp-config gebruiken in verzonden sessies]' \
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
        login|logout|status)
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
        config|critique|defaults|reset)
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
            '(-h --help)'{-h,--help}'[Help voor commando weergeven]' \
            '1:path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[De ruwe bugs.json-payload afdrukken in plaats van geformatteerde bevindingen]' \
    '--timeout[Maximum aantal minuten om te wachten tot de review klaar is]:minutes:' \
    '(-h --help)'{-h,--help}'[Help voor commando weergeven]' \
    '1:target:'
}

(( $+_comps[claude] )) || compdef _claude claude
