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
    'mcp:Konfigurera och hantera MCP-servrar'
    'plugin:Hantera Claude Code-tillägg'
    'agents:Hantera bakgrundsagenter'
    'attach:Öppna en bakgrundssession i den här terminalen'
    'logs:Visa den senaste terminalutdatan från en bakgrundssession'
    'stop:Stoppa en bakgrundssession (konversationen sparas)'
    'respawn:Starta om en bakgrundssession så att den kör den aktuella versionen av Claude Code'
    'rm:Ta bort en bakgrundssession, och dess worktree när det är säkert'
    'auth:Hantera autentisering'
    'auto-mode:Inspektera eller återställ konfiguration för auto-läge-klassificerare'
    'gateway:Kör företagets autentiserings-/telemetrigateway'
    'import:Importera konfiguration från en annan AI-kodagent till Claude Code'
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
    '--restricted[Begränsat läge: ta bort verktygen som kör kommandon eller kod samt WebFetch, ignorera user/project/local-inställningar och begränsa filverktygen till arbetskatalogerna]'
    '--max-budget-usd[Maximalt dollarbelopp att spendera på API-anrop (endast --print)]:amount:'
    '--replay-user-messages[Skicka användarmeddelanden från stdin på stdout för bekräftelse]'
    '--allowed-tools[Komma- eller mellanslagseparerad lista över tillåtna verktygsnamn (t.ex. "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Komma- eller mellanslagseparerad lista över tillåtna verktygsnamn (camelCase-format)]:tools:'
    '--tools[Ange lista över tillgängliga verktyg från inbyggd uppsättning. Endast utskriftsläge]:tools:'
    '--disallowed-tools[Komma- eller mellanslagseparerad lista över otillåtna verktygsnamn (t.ex. "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Komma- eller mellanslagseparerad lista över otillåtna verktygsnamn (camelCase-format)]:tools:'
    '--mcp-config[Ladda MCP-servrar från JSON-fil eller sträng (mellanslagseparerad)]:configs:'
    '--system-prompt[Systemprompt att använda för session]:prompt:'
    '--system-prompt-file[Läs systemprompt från en fil]:file:_files'
    '--append-system-prompt[Lägg till systemprompt till standardsystemprompt]:prompt:'
    '--append-system-prompt-file[Läs systemprompt från en fil och lägg till den i standardsystemprompten]:file:_files'
    '--system-prompt-snapshot[Spara systemprompten en gång per konversation och återanvänd den ordagrant vid varje begäran och återupptagning (on, standard) eller generera den på nytt vid varje begäran (off)]:mode:(on off)'
    '--permission-mode[Behörighetsläge att använda för session]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '--permission-prompts[Vem som besvarar behörighetsfrågor med --print: "host" (SDK-värden eller --permission-prompt-tool) eller "none" (allt som skulle ge en fråga nekas)]:target:(host none)'
    '--permission-prompt-tool[MCP-verktyg för behörighetsfrågor (endast --print)]:tool:'
    '(-c --continue)'{-c,--continue}'[Fortsätt den senaste konversationen]'
    '(-r --resume)'{-r,--resume}'[Återuppta en konversation - ange sessions-ID eller välj interaktivt]:sessionId:_claude_sessions'
    '--fork-session[Skapa nytt sessions-ID istället för att återanvända ursprungligt sessions-ID vid återupptagning (med --resume eller --continue)]'
    '--no-session-persistence[Inaktivera sessionsbeständighet - sessioner sparas inte (endast --print)]'
    '--model[Modell för aktuell session. Ange alias för senaste modell (t.ex. '\''sonnet'\'' eller '\''opus'\'')]:model:_claude_model_names'
    '--agent[Agent för aktuell session. Åsidosätter '\''agent'\''-inställningen]:agent:_claude_agent_names'
    '--betas[Beta-huvuden att inkludera i API-förfrågningar (endast API-nyckelanvändare)]:betas:'
    '--fallback-model[Aktivera automatisk återgång till angiven modell när standardmodellen är överbelastad (endast --print)]:model:_claude_model_names'
    '--settings[Sökväg till inställningar JSON-fil eller JSON-sträng för att ladda ytterligare inställningar]:file-or-json:_files'
    '--add-dir[Ytterligare kataloger att tillåta verktygsåtkomst]:directories:_directories'
    '--ide[Anslut automatiskt till IDE vid start om exakt en giltig IDE är tillgänglig]'
    '--desktop[Öppna i Claude Desktop-appen i stället för terminalen (med --continue eller --resume <id> för att välja session)]'
    '--strict-mcp-config[Använd endast MCP-servrar från --mcp-config och ignorera alla andra MCP-inställningar]'
    '--session-id[Specifikt sessions-ID att använda för konversation (måste vara giltig UUID)]:uuid:'
    '--agents[JSON-objekt som definierar anpassade agenter]:json:'
    '--setting-sources[Kommaseparerad lista över inställningskällor att ladda (user, project, local)]:sources:'
    '--plugin-dir[Katalog att ladda tillägg från endast för denna session (upprepningsbar)]:paths:_directories'
    '--disable-slash-commands[Inaktivera alla snedstreckskommandon]'
    '(--bg --background)'{--bg,--background}'[Starta sessionen som en bakgrundsagent och återgå omedelbart]'
    '(-w --worktree)'{-w,--worktree}'[Skapa en ny git-worktree för denna session (ange valfritt ett namn)]::name:'
    '--tmux=-[Skapa en tmux-session för worktreen (kräver --worktree). Använder inbyggda iTerm2-paneler när de finns; --tmux=classic för traditionell tmux]::mode:(classic)'
    '(-n --name)'{-n,--name}'[Ange ett visningsnamn för denna session]:name:'
    '--effort[Ansträngningsnivå för aktuell session]:level:(low medium high xhigh max)'
    '--autocompact[Fönsterstorlek för automatisk komprimering (auto, eller 100k-1M tokens)]:size:(auto)'
    '--debug-file[Skriv felsökningsloggar till en specifik filsökväg (aktiverar implicit felsökningsläge)]:path:_files'
    '--from-pr[Återuppta en session länkad till en PR via nummer/URL, eller öppna interaktiv väljare]::value:'
    '--teleport[Återuppta en teleportsession, ange valfritt sessions-ID]::session:'
    '--cloud[Skapa en molnsession med den angivna beskrivningen, eller anslut till en befintlig via sessions-ID eller claude.ai/code-URL]::description-or-session:'
    '--environment[Skapa en ny molnsession som körs i den angivna självhostade miljön (ccpool_...)]:environment_id:'
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
        attach|logs|stop|kill)
          _arguments \
            '(-h --help)'{-h,--help}'[Visa hjälp för kommando]' \
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
            '--client-id[OAuth-klient-ID för HTTP/SSE-servrar]:clientId:' \
            '--client-secret[Fråga efter OAuth-klienthemlighet (eller sätt miljövariabeln MCP_CLIENT_SECRET)]' \
            '--callback-port[Fast port för OAuth-återanrop (för servrar som kräver förregistrerade omdirigerings-URI:er)]:port:' \
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
            '--client-secret[Fråga efter OAuth-klienthemlighet (eller sätt miljövariabeln MCP_CLIENT_SECRET)]' \
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
        login)
          _arguments \
            '--no-browser[Visa auktoriserings-URL:en i stället för att öppna en webbläsare (för SSH/headless-sessioner)]' \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:name:_claude_mcp_servers'
          ;;
        logout)
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
    'configure:Visa ett tilläggs alternativ och vilka som inte är satta, eller spara värden från stdin'
    'install:Installera ett tillägg från tillgängliga marknadsplatser'
    'i:Installera ett tillägg från tillgängliga marknadsplatser (kort för install)'
    'init:Skapa ett nytt tillägg (laddas automatiskt nästa session)'
    'new:Skapa en grundstruktur för ett nytt tillägg (alias för init)'
    'uninstall:Avinstallera ett installerat tillägg'
    'remove:Avinstallera ett installerat tillägg (alias för uninstall)'
    'enable:Aktivera ett inaktiverat tillägg'
    'disable:Inaktivera ett aktiverat tillägg'
    'update:Uppdatera ett tillägg till den senaste versionen'
    'eval:Kör eval-fall mot ett tillägg och rapportera poängsatta resultat'
    'prune:Ta bort automatiskt installerade beroenden som inte längre behövs'
    'autoremove:Ta bort automatiskt installerade beroenden som inte längre behövs (alias för prune)'
    'tag:Skapa en {name}--v{version} git-tagg för en tilläggsutgåva'
    'test:Kör testerna för en mod'
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
            '--strict[Behandla varningar som fel (slutkod 1)]' \
            '--json[Skriv ut valideringsrapporten som JSON (samma slutkoder)]' \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Installationsomfång]:scope:(user project local)' \
            '*--config[Sätt ett userConfig-alternativ som deklareras i tilläggsmanifestet (kan upprepas)]:key=value:' \
            '(-y --yes)'{-y,--yes}'[Godkänn det visade kommandot som marknadsplatsen deklarerar utan bekräftelsefråga]' \
            '--json[Skriv ut en maskinläsbar resultatrad i stället för meddelandet för människor]' \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Installationsomfång]:scope:(user project local)' \
            '--keep-data[Behåll tilläggets katalog för beständiga data]' \
            '--prune[Ta även bort automatiskt installerade beroenden som inte längre behövs]' \
            '(-y --yes)'{-y,--yes}'[Hoppa över bekräftelsefrågan för --prune]' \
            '--json[Skriv ut en maskinläsbar resultatrad i stället för meddelandet för människor (inte med --prune)]' \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Installationsomfång]:scope:(user project local)' \
            '--json[Skriv ut en maskinläsbar resultatrad i stället för meddelandet för människor]' \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        disable)
          _arguments \
            '(-a --all)'{-a,--all}'[Inaktivera alla aktiverade tillägg]' \
            '(-s --scope)'{-s,--scope}'[Installationsomfång]:scope:(user project local)' \
            '--json[Skriv ut en maskinläsbar resultatrad i stället för meddelandet för människor]' \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '::plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Installationsomfång]:scope:(user project local managed)' \
            '(-y --yes)'{-y,--yes}'[Godkänn det visade kommandot som marknadsplatsen deklarerar utan bekräftelsefråga]' \
            '--json[Skriv ut en maskinläsbar resultatrad i stället för meddelandet för människor]' \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list)
          _arguments \
            '--json[Utdata som JSON]' \
            '--available[Inkludera tillgängliga tillägg från marknadsplatser (kräver --json)]' \
            '(-h --help)'{-h,--help}'[Visa hjälp]'
          ;;
        prune|autoremove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Rensa i omfång]:scope:(user project local)' \
            '--dry-run[Lista vad som skulle tas bort utan att ta bort]' \
            '(-y --yes)'{-y,--yes}'[Hoppa över bekräftelsefrågan]' \
            '(-h --help)'{-h,--help}'[Visa hjälp]'
          ;;
        configure)
          _arguments \
            '--json[Utdata som JSON]' \
            '--values-stdin[Läs alternativvärden från stdin som ett JSON-objekt med enradiga strängar; utelämnade alternativ behåller sina värden]' \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init|new)
          _arguments \
            '--description[Beskrivning i manifestet]:text:' \
            '--author[Författarens namn (standard: git config user.name)]:name:' \
            '--author-email[Författarens e-postadress (standard: git config user.email)]:email:' \
            '--with[Komponenter att också skapa grundstruktur för]:components:' \
            '(-f --force)'{-f,--force}'[Skriv över en befintlig .claude-plugin/ i målet]' \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '--case[Filtrera fall efter namn-glob]:glob:' \
            '*--tag[Filtrera fall efter tagg (kan upprepas)]:tag:' \
            '--runs[Åsidosätt antal körningar per fall (standard: case.runs, annars 3)]:n:' \
            '(-j --concurrency)'{-j,--concurrency}'[Kör upp till n agentkörningar samtidigt (1-8; standard 1)]:n:' \
            '--model[Åsidosätt modellen för alla fall]:model:_claude_model_names' \
            '--judge-model[Åsidosätt modellen för LLM-bedömaren (standard: haiku)]:model:_claude_model_names' \
            '--max-cost-usd[Fast kostnadstak; avbryt och rapportera delresultat om det nås (slutkod 2)]:usd:' \
            '--output-dir[Katalog för aggregate-result.json]:dir:_directories' \
            '--eval-dir[Katalognamn (under tillägget) som innehåller utvärderingsfallen]:dir:' \
            '--json[Skriv ut hela körresultatet som JSON till stdout, eller skriv det till den här .json-filen]::path:_files' \
            '--threshold[Avsluta med slutkod 1 om något falls poäng är under detta tröskelvärde (standard: 1.0)]:threshold:' \
            '*--allow-tools[Operatörens tillstånd för spärrade verktyg (Bash, Write, Edit, WebFetch, mcp__*)]:tools:' \
            '(--no-scaffold)--scaffold[Kör varje falls scaffold_script (kör bash från författaren under ditt konto; av som standard)]' \
            '(--scaffold)--no-scaffold[Hoppa uttryckligen över scaffold_script]' \
            '--trust-plugin[Intyga att du litar på det här tillägget och dess utvärderingssvit, så att förtroendefrågan vid första körningen hoppas över (för CI)]' \
            '--ablation[Kör en baslinje utan tillägg och rapportera poängskillnaden]:mode:(none with-without)' \
            '--mocks[Mock-ersättare för MCP-servrar, från <eval dir>/mocks/]:mode:(record off)' \
            '--allow-real-servers[Med --mocks record: starta även de riktiga MCP-serverprocesserna som saknar mock]' \
            '--keep-temp[Behåll scaffold-kataloger för felsökning]' \
            '--verbose[Logga spårningshändelser per meddelande i felsökningsloggen]' \
            '--report[Skriv den fristående HTML-rapporten till den här sökvägen i stället för resultatkatalogen]:path:_files' \
            '(--no-publish)--publish-report[Kräv även att rapporten publiceras på claude.ai]' \
            '(--publish-report)--no-publish[Behåll HTML-rapporten endast lokalt; publicera den inte på claude.ai]' \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '::target: _alternative "plugins\:installed plugin\:_claude_installed_plugins" "files\:path\:_files"'
          ;;
        tag)
          _arguments \
            '--push[Pusha taggen till --remote när den har skapats]' \
            '--dry-run[Visa vad som skulle taggas utan att skapa taggen]' \
            '(-f --force)'{-f,--force}'[Hoppa över kontrollerna för ändrat arbetsträd och redan befintlig tagg]' \
            '(-m --message)'{-m,--message}'[Annoteringsmeddelande för taggen (använd %s för versionen)]:msg:' \
            '--remote[Fjärrförråd att pusha till med --push]:name:' \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '::path:_files'
          ;;
        test)
          _arguments \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '::dir:_directories'
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
            '--sparse[Begränsa utcheckningen till specifika kataloger via git sparse-checkout (för monorepon)]:paths:' \
            '--scope[Var marknadsplatsen ska deklareras]:scope:(user project local)' \
            '--claudeai[Lägg till marknadsplatsen med det här namnet som claude.ai är värd för åt dig]' \
            '(-h --help)'{-h,--help}'[Visa hjälp]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '--json[Utdata som JSON]' \
            '(-h --help)'{-h,--help}'[Visa hjälp]'
          ;;
        remove|rm)
          _arguments \
            '--scope[Ta bort marknadsplatsdeklarationen från ett visst inställningsomfång (utelämna för att ta bort den från alla omfång)]:scope:(user project local)' \
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
    '--agent[Standardagent för sessioner utsända från agentvyn]:agent:_claude_agent_names' \
    '--all[Med --json: inkludera även slutförda bakgrundssessioner]' \
    '--allow-dangerously-skip-permissions[Gör läget kringgå-behörigheter tillgängligt för utsända sessioner]' \
    '--cwd[Visa endast bakgrundssessioner startade under sökväg]:path:_directories' \
    '--dangerously-skip-permissions[Alias för --permission-mode bypassPermissions]' \
    '--effort[Standardansträngningsnivå för utsända sessioner]:level:(low medium high xhigh max)' \
    '--json[Skriv ut aktiva sessioner som en JSON-array och avsluta]' \
    '*--mcp-config[MCP-serverkonfiguration att tillämpa på utsända sessioner]:config:' \
    '--model[Standardmodell för sessioner utsända från agentvyn]:model:_claude_model_names' \
    '--permission-mode[Standardbehörighetsläge för utsända sessioner]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Ladda tillägg från katalog för agentvyn och utsända sessioner]:path:_directories' \
    '--setting-sources[Kommaseparerad lista över inställningskällor att ladda (user, project, local)]:sources:' \
    '--settings[Inställningsfil eller JSON-sträng att tillämpa]:file-or-json:_files' \
    '--strict-mcp-config[Använd endast MCP-servrar från --mcp-config i utsända sessioner]' \
    '--restricted[Starta utsända sessioner i begränsat läge]' \
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
        login)
          _arguments \
            '--email[Fyll i e-postadressen i förväg på inloggningssidan]:email:' \
            '--sso[Tvinga SSO-inloggningsflöde]' \
            '(--claudeai)--console[Använd Anthropic Console (fakturering per API-användning) i stället för Claude-prenumeration]' \
            '(--console)--claudeai[Använd Claude-prenumeration (standard)]' \
            '(-h --help)'{-h,--help}'[Visa hjälp för kommando]'
          ;;
        status)
          _arguments \
            '(--text)--json[Utdata som JSON (standard)]' \
            '(--json)--text[Utdata som läsbar text]' \
            '(-h --help)'{-h,--help}'[Visa hjälp för kommando]'
          ;;
        logout)
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
        critique)
          _arguments \
            '--model[Åsidosätt vilken modell som används]:model:_claude_model_names' \
            '(-h --help)'{-h,--help}'[Visa hjälp för kommando]'
          ;;
        defaults)
          _arguments \
            '--label[Visa endast regler vars etikett börjar med detta prefix (skiftlägesokänsligt)]:prefix:' \
            '(-h --help)'{-h,--help}'[Visa hjälp för kommando]'
          ;;
        reset)
          _arguments \
            '(-y --yes)'{-y,--yes}'[Hoppa över bekräftelsefrågan]' \
            '(-h --help)'{-h,--help}'[Visa hjälp för kommando]'
          ;;
        config)
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
            '--dry-run[Lista vad som skulle tas bort utan att ta bort något]' \
            '(-y --yes)'{-y,--yes}'[Hoppa över bekräftelsefrågan]' \
            '(-i --interactive)'{-i,--interactive}'[Fråga för varje objekt innan det tas bort]' \
            '(1)--all[Rensa tillståndet för alla projekt (kan inte kombineras med en sökväg)]' \
            '(-h --help)'{-h,--help}'[Visa hjälp för kommando]' \
            '(--all)::path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Skriv ut den råa bugs.json-nyttolasten istället för formaterade resultat]' \
    '--timeout[Maximalt antal minuter att vänta på att granskningen blir klar (standard: 45)]:minutes:' \
    '(--no-post)--post[Publicera den färdiga granskningens fynd i PR:en i ditt namn (endast PR-mål; en vanlig kommentar, inte en granskning)]' \
    '(--post)--no-post[Publicera inte fynden i PR:en (standard)]' \
    '(-h --help)'{-h,--help}'[Visa hjälp för kommando]' \
    '1:target:'
}

_claude_respawn() {
  _arguments \
    '(1)--all[Starta om alla bakgrundssessioner som körs]' \
    '(-h --help)'{-h,--help}'[Visa hjälp för kommando]' \
    '(--all)::session:_claude_background_sessions'
}

_claude_rm() {
  _arguments \
    '--discard-unpushed[Kasta även worktreens opushade commits och ändringar som inte har committats (ange det commit@worktree-id som ett tidigare claude rm rapporterade)]:commit@worktree-id:' \
    '--force-remove-worktree[Ta bort worktree-katalogen även om WorktreeRemove-hooken eller git inte kunde ta bort den (ange det worktree-id som ett tidigare claude rm rapporterade)]:worktree-id:' \
    '(-h --help)'{-h,--help}'[Visa hjälp för kommando]' \
    '1:session:_claude_background_sessions'
}

_claude_import() {
  _arguments \
    '--dry-run[Visa vad som skulle importeras utan att skriva något]' \
    '--yes[Hoppa över den interaktiva väljaren (i headless-miljöer, ange --yes=<digest> från förhandsvisningen i /import)]' \
    '(-h --help)'{-h,--help}'[Visa hjälp för kommando]' \
    '::source:(codex gemini cursor)'
}

(( $+_comps[claude] )) || compdef _claude claude
