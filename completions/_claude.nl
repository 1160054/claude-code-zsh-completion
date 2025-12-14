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
    '--replay-user-messages[Gebruikersberichten opnieuw verzenden van stdin naar stdout ter bevestiging]'
    '--allowed-tools[Komma- of spatiegescheiden lijst van toegestane toolnamen (bijv. "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Komma- of spatiegescheiden lijst van toegestane toolnamen (camelCase-formaat)]:tools:'
    '--tools[Lijst van beschikbare tools uit ingebouwde set specificeren. Alleen printmodus]:tools:'
    '--disallowed-tools[Komma- of spatiegescheiden lijst van niet-toegestane toolnamen (bijv. "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Komma- of spatiegescheiden lijst van niet-toegestane toolnamen (camelCase-formaat)]:tools:'
    '--mcp-config[MCP-servers laden uit JSON-bestand of -string (spatiegescheiden)]:configs:'
    '--system-prompt[Systeemprompt te gebruiken voor sessie]:prompt:'
    '--append-system-prompt[Systeemprompt toevoegen aan standaard systeemprompt]:prompt:'
    '--permission-mode[Toestemmingsmodus te gebruiken voor sessie]:mode:(acceptEdits bypassPermissions default dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Het meest recente gesprek voortzetten]'
    '(-r --resume)'{-r,--resume}'[Een gesprek hervatten - specificeer sessie-ID of selecteer interactief]:sessionId:_claude_sessions'
    '--fork-session[Nieuwe sessie-ID aanmaken in plaats van originele sessie-ID hergebruiken bij hervatten (met --resume of --continue)]'
    '--model[Model voor huidige sessie. Specificeer alias voor nieuwste model (bijv. '\''sonnet'\'' of '\''opus'\'')]:model:'
    '--fallback-model[Automatische terugval naar gespecificeerd model inschakelen wanneer standaardmodel overbelast is (alleen --print)]:model:'
    '--settings[Pad naar instellingen-JSON-bestand of JSON-string om aanvullende instellingen te laden]:file-or-json:_files'
    '--add-dir[Aanvullende mappen om tooltoegang toe te staan]:directories:_directories'
    '--ide[Automatisch verbinden met IDE bij opstarten als precies één geldige IDE beschikbaar is]'
    '--strict-mcp-config[Alleen MCP-servers uit --mcp-config gebruiken en alle andere MCP-instellingen negeren]'
    '--session-id[Specifieke sessie-ID te gebruiken voor gesprek (moet geldige UUID zijn)]:uuid:'
    '--agents[JSON-object dat aangepaste agents definieert]:json:'
    '--setting-sources[Kommagescheiden lijst van instellingsbronnen te laden (user, project, local)]:sources:'
    '--plugin-dir[Map om plugins uit te laden voor alleen deze sessie (herhaalbaar)]:paths:_directories'
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
      esac
      ;;
  esac
}
_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:Een plugin of marketplace-manifest valideren'
    'marketplace:Claude Code marketplaces beheren'
    'install:Een plugin installeren vanuit beschikbare marketplaces'
    'i:Een plugin installeren vanuit beschikbare marketplaces (kort voor install)'
    'uninstall:Een geïnstalleerde plugin verwijderen'
    'remove:Een geïnstalleerde plugin verwijderen (alias voor uninstall)'
    'enable:Een uitgeschakelde plugin inschakelen'
    'disable:Een ingeschakelde plugin uitschakelen'
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
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-h --help)'{-h,--help}'[Help weergeven]' \
            '1:plugin:_claude_installed_plugins'
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
(( $+_comps[claude] )) || compdef _claude claude
