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
    'mcp:Konfigurera och hantera MCP-servrar'
    'plugin:Hantera Claude Code-tillägg'
    'agents:Hantera bakgrundsagenter'
    'auth:Hantera autentisering'
    'auto-mode:Inspektera eller återställ konfiguration för auto-läge-klassificerare'
    'gateway:Kör företagets autentiserings-/telemetrigateway'
    'project:Hantera Claude Code-projekttillstånd'
    'ultrareview:Kör en molnbaserad kodgranskning med flera agenter och skriv ut resultaten'
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
    '--max-budget-usd[Maximalt dollarbelopp att spendera på API-anrop (endast --print)]:amount:'
    '--replay-user-messages[Skicka användarmeddelanden från stdin på stdout för bekräftelse]'
    '--allowed-tools[Komma- eller mellanslagseparerad lista över tillåtna verktygsnamn (t.ex. "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Komma- eller mellanslagseparerad lista över tillåtna verktygsnamn (camelCase-format)]:tools:'
    '--tools[Ange lista över tillgängliga verktyg från inbyggd uppsättning. Endast utskriftsläge]:tools:'
    '--disallowed-tools[Komma- eller mellanslagseparerad lista över otillåtna verktygsnamn (t.ex. "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Komma- eller mellanslagseparerad lista över otillåtna verktygsnamn (camelCase-format)]:tools:'
    '--mcp-config[Ladda MCP-servrar från JSON-fil eller sträng (mellanslagseparerad)]:configs:'
    '--system-prompt[Systemprompt att använda för session]:prompt:'
    '--append-system-prompt[Lägg till systemprompt till standardsystemprompt]:prompt:'
    '--permission-mode[Behörighetsläge att använda för session]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Fortsätt den senaste konversationen]'
    '(-r --resume)'{-r,--resume}'[Återuppta en konversation - ange sessions-ID eller välj interaktivt]:sessionId:_claude_sessions'
    '--fork-session[Skapa nytt sessions-ID istället för att återanvända ursprungligt sessions-ID vid återupptagning (med --resume eller --continue)]'
    '--no-session-persistence[Inaktivera sessionsbeständighet - sessioner sparas inte (endast --print)]'
    '--model[Modell för aktuell session. Ange alias för senaste modell (t.ex. '\''sonnet'\'' eller '\''opus'\'')]:model:'
    '--agent[Agent för aktuell session. Åsidosätter '\''agent'\''-inställningen]:agent:'
    '--betas[Beta-huvuden att inkludera i API-förfrågningar (endast API-nyckelanvändare)]:betas:'
    '--fallback-model[Aktivera automatisk återgång till angiven modell när standardmodellen är överbelastad (endast --print)]:model:'
    '--settings[Sökväg till inställningar JSON-fil eller JSON-sträng för att ladda ytterligare inställningar]:file-or-json:_files'
    '--add-dir[Ytterligare kataloger att tillåta verktygsåtkomst]:directories:_directories'
    '--ide[Anslut automatiskt till IDE vid start om exakt en giltig IDE är tillgänglig]'
    '--strict-mcp-config[Använd endast MCP-servrar från --mcp-config och ignorera alla andra MCP-inställningar]'
    '--session-id[Specifikt sessions-ID att använda för konversation (måste vara giltig UUID)]:uuid:'
    '--agents[JSON-objekt som definierar anpassade agenter]:json:'
    '--setting-sources[Kommaseparerad lista över inställningskällor att ladda (user, project, local)]:sources:'
    '--plugin-dir[Katalog att ladda tillägg från endast för denna session (upprepningsbar)]:paths:_directories'
    '--disable-slash-commands[Inaktivera alla snedstreckskommandon]'
    '(--bg --background)'{--bg,--background}'[Starta sessionen som en bakgrundsagent och återgå omedelbart]'
    '(-w --worktree)'{-w,--worktree}'[Skapa en ny git-worktree för denna session (ange valfritt ett namn)]::name:'
    '--tmux[Skapa en tmux-session för worktree (kräver --worktree)]'
    '(-n --name)'{-n,--name}'[Ange ett visningsnamn för denna session]:name:'
    '--effort[Ansträngningsnivå för aktuell session]:level:(low medium high xhigh max)'
    '--debug-file[Skriv felsökningsloggar till en specifik filsökväg (aktiverar implicit felsökningsläge)]:path:_files'
    '--from-pr[Återuppta en session länkad till en PR via nummer/URL, eller öppna interaktiv väljare]::value:'
    '--remote-control[Starta en interaktiv session med Fjärrkontroll aktiverad (valfritt namngiven)]::name:'
    '--remote-control-session-name-prefix[Prefix för automatiskt genererade Fjärrkontroll-sessionsnamn]:prefix:'
    '--chrome[Aktivera Claude i Chrome-integration]'
    '--no-chrome[Inaktivera Claude i Chrome-integration]'
    '--plugin-url[Hämta en tilläggs-.zip från en URL endast för denna session (upprepningsbar)]:url:'
    '--file[Filresurser att ladda ner vid start (format: file_id:relative_path)]:specs:'
    '--prompt-suggestions[Aktivera promptförslag (avger en förutspådd nästa prompt i utskrifts-/SDK-läge)]::value:(true false 1 0 yes no on off)'
    '--forward-subagent-text[Vidarebefordra underagentstext och tankeblock som meddelanden (med --print och stream-json)]'
    '--include-hook-events[Inkludera alla hook-livscykelhändelser i utdataströmmen (med stream-json)]'
    '--exclude-dynamic-system-prompt-sections[Flytta per-maskin-sektioner till det första användarmeddelandet för att förbättra promptcache-återanvändning]'
    '--brief[Aktivera SendUserMessage-verktyget för kommunikation mellan agent och användare]'
    '--safe-mode[Starta med alla anpassningar inaktiverade (användbart för felsökning av en trasig konfiguration)]'
    '--bare[Minimalt läge: hoppa över hooks, LSP, tilläggssynkronisering, attribution, auto-minne och CLAUDE.md-autoidentifiering]'
    '--ax-screen-reader[Rendera skärmläsarvänlig utdata (platt text, inga dekorativa kanter eller animationer)]'
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
    'login:Autentisera med en MCP-server (HTTP, SSE eller claude.ai-anslutning)'
    'logout:Rensa lagrade OAuth-autentiseringsuppgifter för en MCP-server'
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
        login|logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:name:_claude_mcp_servers'
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
    'list:Lista installerade tillägg'
    'details:Visa komponentinventering och beräknad tokenkostnad för ett tillägg'
    'install:Installera ett tillägg från tillgängliga marknadsplatser'
    'i:Installera ett tillägg från tillgängliga marknadsplatser (kort för install)'
    'init:Skapa ett nytt tillägg (laddas automatiskt nästa session)'
    'uninstall:Avinstallera ett installerat tillägg'
    'remove:Avinstallera ett installerat tillägg (alias för uninstall)'
    'enable:Aktivera ett inaktiverat tillägg'
    'disable:Inaktivera ett aktiverat tillägg'
    'update:Uppdatera ett tillägg till den senaste versionen'
    'eval:Kör eval-fall mot ett tillägg och rapportera poängsatta resultat'
    'prune:Ta bort automatiskt installerade beroenden som inte längre behövs'
    'tag:Skapa en {name}--v{version} git-tagg för en tilläggsutgåva'
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
            '(-s --scope)'{-s,--scope}'[Installationsomfång]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Installationsomfång]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Installationsomfång]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Installationsomfång]:scope:(user project local managed)' \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list|prune)
          _arguments \
            '(-h --help)'{-h,--help}'[Visa hjälp]'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init)
          _arguments \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:target:'
          ;;
        tag)
          _arguments \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:path:_files'
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

_claude_agents() {
  _arguments \
    '*--add-dir[Ytterligare katalog att tillåta verktygsåtkomst till i utsända sessioner]:directory:_directories' \
    '--agent[Standardagent för sessioner utsända från agentvyn]:agent:' \
    '--all[Med --json: inkludera även slutförda bakgrundssessioner]' \
    '--allow-dangerously-skip-permissions[Gör läget kringgå-behörigheter tillgängligt för utsända sessioner]' \
    '--cwd[Visa endast bakgrundssessioner startade under sökväg]:path:_directories' \
    '--dangerously-skip-permissions[Alias för --permission-mode bypassPermissions]' \
    '--effort[Standardansträngningsnivå för utsända sessioner]:level:(low medium high xhigh max)' \
    '--json[Skriv ut aktiva sessioner som en JSON-array och avsluta]' \
    '*--mcp-config[MCP-serverkonfiguration att tillämpa på utsända sessioner]:config:' \
    '--model[Standardmodell för sessioner utsända från agentvyn]:model:' \
    '--permission-mode[Standardbehörighetsläge för utsända sessioner]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Ladda tillägg från katalog för agentvyn och utsända sessioner]:path:_directories' \
    '--setting-sources[Kommaseparerad lista över inställningskällor att ladda (user, project, local)]:sources:' \
    '--settings[Inställningsfil eller JSON-sträng att tillämpa]:file-or-json:_files' \
    '--strict-mcp-config[Använd endast MCP-servrar från --mcp-config i utsända sessioner]' \
    '(-h --help)'{-h,--help}'[Visa hjälp för kommando]'
}

_claude_auth() {
  local -a auth_commands
  auth_commands=(
    'login:Logga in på ditt Anthropic-konto'
    'logout:Logga ut från ditt Anthropic-konto'
    'status:Visa autentiseringsstatus'
    'help:Visa hjälp'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Visa hjälp för kommando]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'auth-kommandon' auth_commands
      ;;
    args)
      case $words[1] in
        login|logout|status)
          _arguments \
            '(-h --help)'{-h,--help}'[Visa hjälp för kommando]'
          ;;
      esac
      ;;
  esac
}

_claude_auto_mode() {
  local -a auto_mode_commands
  auto_mode_commands=(
    'config:Skriv ut den effektiva auto-läge-konfigurationen som JSON'
    'critique:Få AI-feedback på dina anpassade auto-läge-regler'
    'defaults:Skriv ut standardreglerna för auto-läge som JSON'
    'reset:Återställ auto-läge-konfigurationen till de levererade standardvärdena'
    'help:Visa hjälp'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Visa hjälp för kommando]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'auto-mode-kommandon' auto_mode_commands
      ;;
    args)
      case $words[1] in
        config|critique|defaults|reset)
          _arguments \
            '(-h --help)'{-h,--help}'[Visa hjälp för kommando]'
          ;;
      esac
      ;;
  esac
}

_claude_gateway() {
  _arguments \
    '--config[Sökväg till gateway-YAML-konfiguration]:path:_files' \
    '(-h --help)'{-h,--help}'[Visa hjälp för kommando]'
}

_claude_project() {
  local -a project_commands
  project_commands=(
    'purge:Ta bort allt Claude Code-tillstånd för ett projekt (transkript, uppgifter, filhistorik, konfigurationspost)'
    'help:Visa hjälp'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Visa hjälp för kommando]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'project-kommandon' project_commands
      ;;
    args)
      case $words[1] in
        purge)
          _arguments \
            '(-h --help)'{-h,--help}'[Visa hjälp för kommando]' \
            '1:path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Skriv ut den råa bugs.json-nyttolasten istället för formaterade resultat]' \
    '--timeout[Maximalt antal minuter att vänta på att granskningen slutförs]:minutes:' \
    '(-h --help)'{-h,--help}'[Visa hjälp för kommando]' \
    '1:target:'
}

(( $+_comps[claude] )) || compdef _claude claude
