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

  _describe 'mcp-servrar' server_list
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

  _describe 'installerade tillägg' plugins
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

  _describe 'sessions-ID' sessions
}

_claude() {
  local curcontext="$curcontext" state line
  typeset -A opt_args

  local -a main_commands
  main_commands=(
    'mcp:Konfigurera och hantera MCP-servrar'
    'plugin:Hantera Claude Code-tillägg'
    'setup-token:Konfigurera långsiktig autentiseringstoken (kräver Claude-prenumeration)'
    'doctor:Hälsokontroll för Claude Code-automatisk uppdaterare'
    'update:Sök efter och installera uppdateringar'
    'install:Installera Claude Code native build'
  )

  local -a main_options
  main_options=(
    '(-d --debug)'{-d,--debug}'[Aktivera felsökningsläge med valfri kategorifiltrering (t.ex. "api,hooks" eller "!statsig,!file")]:filter:'
    '--verbose[Åsidosätt utförligt läge från konfigurationsfil]'
    '(-p --print)'{-p,--print}'[Skriv ut svar och avsluta (för användning med pipes). Obs: använd endast i betrodda kataloger]'
    '--output-format[Utdataformat (med --print): "text" (standard), "json" (enskilt resultat) eller "stream-json" (realtidsströmning)]:format:(text json stream-json)'
    '--json-schema[JSON-schema för strukturerad utdatavalidering]:schema:'
    '--include-partial-messages[Inkludera partiella meddelandebitar när de anländer (med --print och --output-format=stream-json)]'
    '--input-format[Indataformat (med --print): "text" (standard) eller "stream-json" (realtidsströmning)]:format:(text stream-json)'
    '--mcp-debug[\[Föråldrat. Använd --debug istället\] Aktivera MCP-felsökningsläge (visar MCP-serverfel)]'
    '--dangerously-skip-permissions[Kringgå alla behörighetskontroller. Rekommenderas endast för sandlådor utan internetåtkomst]'
    '--allow-dangerously-skip-permissions[Aktivera alternativ för att kringgå behörighetskontroller utan att aktivera som standard]'
    '--replay-user-messages[Skicka användarmeddelanden från stdin på stdout för bekräftelse]'
    '--allowed-tools[Komma- eller mellanslagseparerad lista över tillåtna verktygsnamn (t.ex. "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Komma- eller mellanslagseparerad lista över tillåtna verktygsnamn (camelCase-format)]:tools:'
    '--tools[Ange lista över tillgängliga verktyg från inbyggd uppsättning. Endast utskriftsläge]:tools:'
    '--disallowed-tools[Komma- eller mellanslagseparerad lista över otillåtna verktygsnamn (t.ex. "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Komma- eller mellanslagseparerad lista över otillåtna verktygsnamn (camelCase-format)]:tools:'
    '--mcp-config[Ladda MCP-servrar från JSON-fil eller sträng (mellanslagseparerad)]:configs:'
    '--system-prompt[Systemprompt att använda för session]:prompt:'
    '--append-system-prompt[Lägg till systemprompt till standardsystemprompt]:prompt:'
    '--permission-mode[Behörighetsläge att använda för session]:mode:(acceptEdits bypassPermissions default dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Fortsätt den senaste konversationen]'
    '(-r --resume)'{-r,--resume}'[Återuppta en konversation - ange sessions-ID eller välj interaktivt]:sessionId:_claude_sessions'
    '--fork-session[Skapa nytt sessions-ID istället för att återanvända ursprungligt sessions-ID vid återupptagning (med --resume eller --continue)]'
    '--model[Modell för aktuell session. Ange alias för senaste modell (t.ex. '\''sonnet'\'' eller '\''opus'\'')]:model:'
    '--fallback-model[Aktivera automatisk återgång till angiven modell när standardmodellen är överbelastad (endast --print)]:model:'
    '--settings[Sökväg till inställningar JSON-fil eller JSON-sträng för att ladda ytterligare inställningar]:file-or-json:_files'
    '--add-dir[Ytterligare kataloger att tillåta verktygsåtkomst]:directories:_directories'
    '--ide[Anslut automatiskt till IDE vid start om exakt en giltig IDE är tillgänglig]'
    '--strict-mcp-config[Använd endast MCP-servrar från --mcp-config och ignorera alla andra MCP-inställningar]'
    '--session-id[Specifikt sessions-ID att använda för konversation (måste vara giltig UUID)]:uuid:'
    '--agents[JSON-objekt som definierar anpassade agenter]:json:'
    '--setting-sources[Kommaseparerad lista över inställningskällor att ladda (user, project, local)]:sources:'
    '--plugin-dir[Katalog att ladda tillägg från endast för denna session (upprepningsbar)]:paths:_directories'
    '(-v --version)'{-v,--version}'[Visa versionsnummer]'
    '(-h --help)'{-h,--help}'[Visa hjälp för kommando]'
  )

  _arguments -C \
    $main_options \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'claude-kommandon' main_commands
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
          _message "inga argument"
          ;;
      esac
      ;;
  esac
}

_claude_mcp() {
  local -a mcp_commands
  mcp_commands=(
    'serve:Starta en Claude Code MCP-server'
    'add:Lägg till en MCP-server till Claude Code'
    'remove:Ta bort en MCP-server'
    'list:Lista konfigurerade MCP-servrar'
    'get:Hämta MCP-serverdetaljer'
    'add-json:Lägg till en MCP-server (stdio eller SSE) med JSON-sträng'
    'add-from-claude-desktop:Importera MCP-servrar från Claude Desktop (endast Mac och WSL)'
    'reset-project-choices:Återställ alla godkända/avvisade projektomfattande (.mcp.json) servrar i detta projekt'
    'help:Visa hjälp'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Visa hjälp]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'mcp-kommandon' mcp_commands
      ;;
    args)
      case $words[1] in
        serve)
          _arguments \
            '(-d --debug)'{-d,--debug}'[Aktivera felsökningsläge]' \
            '--verbose[Åsidosätt utförligt läge från konfigurationsfil]' \
            '(-h --help)'{-h,--help}'[Visa hjälp]'
          ;;
        add)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Konfigurationsomfång (local, user, project)]:scope:(local user project)' \
            '(-t --transport)'{-t,--transport}'[Transporttyp (stdio, sse, http)]:transport:(stdio sse http)' \
            '(-e --env)'{-e,--env}'[Ange miljövariabel (t.ex. -e KEY=value)]:env:' \
            '(-H --header)'{-H,--header}'[Ange WebSocket-huvud]:header:' \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:name:' \
            '2:commandOrUrl:' \
            '*:args:'
          ;;
        remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Konfigurationsomfång (local, user, project) - ta bort från befintligt omfång om ospecificerat]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:name:_claude_mcp_servers'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Visa hjälp]'
          ;;
        get)
          _arguments \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:name:_claude_mcp_servers'
          ;;
        add-json)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Konfigurationsomfång (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:name:' \
            '2:json:'
          ;;
        add-from-claude-desktop)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Konfigurationsomfång (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Visa hjälp]'
          ;;
        reset-project-choices)
          _arguments \
            '(-h --help)'{-h,--help}'[Visa hjälp]'
          ;;
      esac
      ;;
  esac
}

_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:Validera ett tillägg eller marketplace-manifest'
    'marketplace:Hantera Claude Code-marknadsplatser'
    'install:Installera ett tillägg från tillgängliga marknadsplatser'
    'i:Installera ett tillägg från tillgängliga marknadsplatser (kort för install)'
    'uninstall:Avinstallera ett installerat tillägg'
    'remove:Avinstallera ett installerat tillägg (alias för uninstall)'
    'enable:Aktivera ett inaktiverat tillägg'
    'disable:Inaktivera ett aktiverat tillägg'
    'help:Visa hjälp'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Visa hjälp]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'plugin-kommandon' plugin_commands
      ;;
    args)
      case $words[1] in
        validate)
          _arguments \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:plugin:_claude_installed_plugins'
          ;;
      esac
      ;;
  esac
}

_claude_plugin_marketplace() {
  local -a marketplace_commands
  marketplace_commands=(
    'add:Lägg till en marknadsplats från URL, sökväg eller GitHub-repositorium'
    'list:Lista konfigurerade marknadsplatser'
    'remove:Ta bort en konfigurerad marknadsplats'
    'rm:Ta bort en konfigurerad marknadsplats (alias för remove)'
    'update:Uppdatera marknadsplats från källa - uppdatera alla om inget namn anges'
    'help:Visa hjälp'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Visa hjälp]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'marketplace-kommandon' marketplace_commands
      ;;
    args)
      case $words[1] in
        add)
          _arguments \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Visa hjälp]'
          ;;
        remove|rm)
          _arguments \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:name:'
          ;;
        update)
          _arguments \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '::name:'
          ;;
      esac
      ;;
  esac
}

_claude_install() {
  _arguments \
    '--force[Tvinga installation även om redan installerad]' \
    '(-h --help)'{-h,--help}'[Visa hjälp]' \
    '::target:(stable latest)'
}

(( $+_comps[claude] )) || compdef _claude claude
