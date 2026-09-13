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
    'mcp:Konfiguruj i zarządzaj serwerami MCP'
    'plugin:Zarządzaj wtyczkami Claude Code'
    'agents:Zarządzaj agentami w tle'
    'attach:Otwórz sesję w tle w tym terminalu'
    'logs:Wypisz ostatnie wyjście terminala sesji w tle'
    'stop:Zatrzymaj sesję w tle (jej rozmowa zostaje zachowana)'
    'respawn:Uruchom ponownie sesję w tle, aby działała na bieżącej wersji Claude Code'
    'rm:Usuń sesję w tle, a także jej worktree, gdy jest to bezpieczne'
    'auth:Zarządzaj uwierzytelnianiem'
    'auto-mode:Sprawdź lub zresetuj konfigurację klasyfikatora trybu automatycznego'
    'gateway:Uruchom firmową bramę uwierzytelniania/telemetrii'
    'import:Zaimportuj konfigurację innego agenta AI do programowania do Claude Code'
    'project:Zarządzaj stanem projektu Claude Code'
    'ultrareview:Uruchom wieloagentowy przegląd kodu w chmurze i wyświetl wyniki'
    'setup-token:Skonfiguruj długoterminowy token uwierzytelniający (wymaga subskrypcji Claude)'
    'doctor:Sprawdzenie kondycji automatycznego aktualizatora Claude Code'
    'update:Sprawdź dostępność aktualizacji i zainstaluj je'
    'install:Zainstaluj natywną kompilację Claude Code'
  )

  local -a main_options
  main_options=(
    '(-d --debug)'{-d,--debug}'[Włącz tryb debugowania z opcjonalnym filtrowaniem kategorii (np. "api,hooks" lub "!statsig,!file")]:filter:'
    '--verbose[Zastąp ustawienie trybu szczegółowego z pliku konfiguracyjnego]'
    '(-p --print)'{-p,--print}'[Wydrukuj odpowiedź i zakończ (do użycia z potokami). Uwaga: używaj tylko w zaufanych katalogach]'
    '--output-format[Format wyjściowy (z --print): "text" (domyślny), "json" (pojedynczy wynik) lub "stream-json" (streaming w czasie rzeczywistym)]:format:(text json stream-json)'
    '--json-schema[Schemat JSON do walidacji ustrukturyzowanego wyjścia]:schema:'
    '--include-partial-messages[Dołącz fragmenty częściowych wiadomości w miarę ich napływania (z --print i --output-format=stream-json)]'
    '--input-format[Format wejściowy (z --print): "text" (domyślny) lub "stream-json" (streaming wejściowy w czasie rzeczywistym)]:format:(text stream-json)'
    '--mcp-debug[\[Przestarzałe. Użyj zamiast tego --debug\] Włącz tryb debugowania MCP (wyświetla błędy serwera MCP)]'
    '--dangerously-skip-permissions[Pomiń wszystkie sprawdzenia uprawnień. Zalecane tylko dla piaskownicy bez dostępu do internetu]'
    '--allow-dangerously-skip-permissions[Włącz opcję pomijania sprawdzania uprawnień bez domyślnego włączania]'
    '--restricted[Tryb ograniczony: usuwa narzędzia uruchamiające polecenia lub kod oraz WebFetch, ignoruje ustawienia user/project/local i ogranicza narzędzia plikowe do katalogów roboczych]'
    '--max-budget-usd[Maksymalna kwota w dolarach do wydania na wywołania API (tylko --print)]:amount:'
    '--replay-user-messages[Ponownie wyślij wiadomości użytkownika z stdin na stdout w celu potwierdzenia]'
    '--allowed-tools[Lista dozwolonych nazw narzędzi oddzielona przecinkami lub spacjami (np. "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Lista dozwolonych nazw narzędzi oddzielona przecinkami lub spacjami (format camelCase)]:tools:'
    '--tools[Określ listę dostępnych narzędzi z wbudowanego zestawu. Tylko tryb drukowania]:tools:'
    '--disallowed-tools[Lista niedozwolonych nazw narzędzi oddzielona przecinkami lub spacjami (np. "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Lista niedozwolonych nazw narzędzi oddzielona przecinkami lub spacjami (format camelCase)]:tools:'
    '--mcp-config[Załaduj serwery MCP z pliku JSON lub ciągu znaków (oddzielone spacjami)]:configs:'
    '--system-prompt[Prompt systemowy do użycia w sesji]:prompt:'
    '--system-prompt-file[Wczytaj prompt systemowy z pliku]:file:_files'
    '--append-system-prompt[Dołącz prompt systemowy do domyślnego promptu systemowego]:prompt:'
    '--append-system-prompt-file[Wczytaj prompt systemowy z pliku i dołącz go do domyślnego promptu systemowego]:file:_files'
    '--system-prompt-snapshot[Zapisz prompt systemowy raz na rozmowę i używaj go bez zmian przy każdym żądaniu i wznowieniu (on, domyślnie) albo generuj go na nowo przy każdym żądaniu (off)]:mode:(on off)'
    '--permission-mode[Tryb uprawnień do użycia w sesji]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '--permission-prompts[Kto odpowiada na pytania o uprawnienia przy --print: "host" (host SDK lub --permission-prompt-tool) albo "none" (wszystko, co wymagałoby pytania, jest odrzucane)]:target:(host none)'
    '--permission-prompt-tool[Narzędzie MCP do pytań o uprawnienia (tylko --print)]:tool:'
    '(-c --continue)'{-c,--continue}'[Kontynuuj najnowszą konwersację]'
    '(-r --resume)'{-r,--resume}'[Wznów konwersację - podaj identyfikator sesji lub wybierz interaktywnie]:sessionId:_claude_sessions'
    '--fork-session[Utwórz nowy identyfikator sesji zamiast ponownego użycia oryginalnego przy wznawianiu (z --resume lub --continue)]'
    '--no-session-persistence[Wyłącz trwałość sesji - sesje nie będą zapisywane (tylko --print)]'
    '--model[Model dla bieżącej sesji. Określ alias dla najnowszego modelu (np. '\''sonnet'\'' lub '\''opus'\'')]:model:_claude_model_names'
    '--agent[Agent dla bieżącej sesji. Zastępuje ustawienie '\''agent'\'']:agent:_claude_agent_names'
    '--betas[Nagłówki beta do dołączenia w żądaniach API (tylko użytkownicy klucza API)]:betas:'
    '--fallback-model[Włącz automatyczne przełączanie na określony model gdy domyślny model jest przeciążony (tylko --print)]:model:_claude_model_names'
    '--settings[Ścieżka do pliku JSON z ustawieniami lub ciąg JSON do załadowania dodatkowych ustawień]:file-or-json:_files'
    '--add-dir[Dodatkowe katalogi z dostępem dla narzędzi]:directories:_directories'
    '--ide[Automatycznie połącz z IDE przy starcie jeśli dostępne jest dokładnie jedno prawidłowe IDE]'
    '--strict-mcp-config[Używaj tylko serwerów MCP z --mcp-config i ignoruj wszystkie inne ustawienia MCP]'
    '--session-id[Określony identyfikator sesji do użycia w konwersacji (musi być prawidłowym UUID)]:uuid:'
    '--agents[Obiekt JSON definiujący niestandardowych agentów]:json:'
    '--setting-sources[Lista źródeł ustawień oddzielona przecinkami do załadowania (user, project, local)]:sources:'
    '--plugin-dir[Katalog do załadowania wtyczek tylko dla tej sesji (powtarzalne)]:paths:_directories'
    '--disable-slash-commands[Wyłącz wszystkie polecenia ukośnika]'
    '(--bg --background)'{--bg,--background}'[Uruchom sesję jako agenta w tle i natychmiast wróć]'
    '(-w --worktree)'{-w,--worktree}'[Utwórz nowy git worktree dla tej sesji (opcjonalnie podaj nazwę)]::name:'
    '--tmux=-[Utwórz sesję tmux dla worktree (wymaga --worktree). Używa natywnych paneli iTerm2, gdy są dostępne; --tmux=classic dla tradycyjnego tmux]::mode:(classic)'
    '(-n --name)'{-n,--name}'[Ustaw wyświetlaną nazwę dla tej sesji]:name:'
    '--effort[Poziom wysiłku dla bieżącej sesji]:level:(low medium high xhigh max)'
    '--autocompact[Rozmiar okna automatycznej kompaktacji (auto lub 100k-1M tokenów)]:size:(auto)'
    '--debug-file[Zapisuj logi debugowania do określonej ścieżki pliku (niejawnie włącza tryb debugowania)]:path:_files'
    '--from-pr[Wznów sesję powiązaną z PR przez numer/URL lub otwórz interaktywny wybór]::value:'
    '--teleport[Wznów sesję teleport, opcjonalnie podając ID sesji]::session:'
    '--cloud[Utwórz sesję w chmurze z podanym opisem albo podłącz się do istniejącej po ID sesji lub URL claude.ai/code]::description-or-session:'
    '--environment[Utwórz nową sesję w chmurze działającą we wskazanym środowisku self-hosted (ccpool_...)]:environment_id:'
    '--remote-control[Uruchom interaktywną sesję z włączonym Remote Control (opcjonalnie nazwaną)]::name:'
    '--remote-control-session-name-prefix[Prefiks dla automatycznie generowanych nazw sesji Remote Control]:prefix:'
    '--chrome[Włącz integrację Claude w Chrome]'
    '--no-chrome[Wyłącz integrację Claude w Chrome]'
    '--plugin-url[Pobierz plik .zip wtyczki z URL tylko dla tej sesji (powtarzalne)]:url:'
    '--file[Zasoby plików do pobrania przy starcie (format: file_id:relative_path)]:specs:'
    '--prompt-suggestions[Włącz sugestie promptów (emituje przewidywany następny prompt w trybie print/SDK)]::value:(true false 1 0 yes no on off)'
    '--forward-subagent-text[Przekazuj tekst i bloki myślenia podagenta jako wiadomości (z --print i stream-json)]'
    '--include-hook-events[Dołącz wszystkie zdarzenia cyklu życia hooków w strumieniu wyjściowym (z stream-json)]'
    '--exclude-dynamic-system-prompt-sections[Przenieś sekcje specyficzne dla maszyny do pierwszej wiadomości użytkownika, aby poprawić ponowne wykorzystanie pamięci podręcznej promptów]'
    '--brief[Włącz narzędzie SendUserMessage do komunikacji agent-użytkownik]'
    '--safe-mode[Uruchom z wyłączonymi wszystkimi dostosowaniami (przydatne do rozwiązywania problemów z uszkodzoną konfiguracją)]'
    '--bare[Tryb minimalny: pomiń hooki, LSP, synchronizację wtyczek, atrybucję, auto-pamięć i automatyczne wykrywanie CLAUDE.md]'
    '--ax-screen-reader[Renderuj wyjście przyjazne dla czytników ekranu (płaski tekst, bez dekoracyjnych obramowań ani animacji)]'
    '(-v --version)'{-v,--version}'[Wyświetl numer wersji]'
    '(-h --help)'{-h,--help}'[Wyświetl pomoc dla polecenia]'
  )

  _arguments -C \
    $main_options \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'polecenia claude' main_commands
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
            '(-h --help)'{-h,--help}'[Wyświetl pomoc dla polecenia]' \
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
          _message "brak argumentów"
          ;;
      esac
      ;;
  esac
}

_claude_mcp() {
  local -a mcp_commands
  mcp_commands=(
    'serve:Uruchom serwer MCP Claude Code'
    'add:Dodaj serwer MCP do Claude Code'
    'remove:Usuń serwer MCP'
    'list:Wyświetl skonfigurowane serwery MCP'
    'get:Pobierz szczegóły serwera MCP'
    'add-json:Dodaj serwer MCP (stdio lub SSE) z ciągiem JSON'
    'add-from-claude-desktop:Importuj serwery MCP z Claude Desktop (tylko Mac i WSL)'
    'reset-project-choices:Zresetuj wszystkie zatwierdzone/odrzucone serwery w zakresie projektu (.mcp.json) w tym projekcie'
    'login:Uwierzytelnij się z serwerem MCP (HTTP, SSE lub konektor claude.ai)'
    'logout:Wyczyść zapisane poświadczenia OAuth dla serwera MCP'
    'help:Wyświetl pomoc'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'polecenia mcp' mcp_commands
      ;;
    args)
      case $words[1] in
        serve)
          _arguments \
            '(-d --debug)'{-d,--debug}'[Włącz tryb debugowania]' \
            '--verbose[Zastąp ustawienie trybu szczegółowego z pliku konfiguracyjnego]' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]'
          ;;
        add)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Zakres konfiguracji (local, user, project)]:scope:(local user project)' \
            '(-t --transport)'{-t,--transport}'[Typ transportu (stdio, sse, http)]:transport:(stdio sse http)' \
            '(-e --env)'{-e,--env}'[Ustaw zmienną środowiskową (np. -e KLUCZ=wartość)]:env:' \
            '(-H --header)'{-H,--header}'[Ustaw nagłówek WebSocket]:header:' \
            '--client-id[ID klienta OAuth dla serwerów HTTP/SSE]:clientId:' \
            '--client-secret[Zapytaj o sekret klienta OAuth (lub ustaw zmienną środowiskową MCP_CLIENT_SECRET)]' \
            '--callback-port[Stały port dla wywołania zwrotnego OAuth (dla serwerów wymagających wcześniej zarejestrowanych URI przekierowania)]:port:' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:name:' \
            '2:commandOrUrl:' \
            '*:args:'
          ;;
        remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Zakres konfiguracji (local, user, project) - usuń z istniejącego zakresu jeśli nieokreślony]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:name:_claude_mcp_servers'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]'
          ;;
        get)
          _arguments \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:name:_claude_mcp_servers'
          ;;
        add-json)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Zakres konfiguracji (local, user, project)]:scope:(local user project)' \
            '--client-secret[Zapytaj o sekret klienta OAuth (lub ustaw zmienną środowiskową MCP_CLIENT_SECRET)]' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:name:' \
            '2:json:'
          ;;
        add-from-claude-desktop)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Zakres konfiguracji (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]'
          ;;
        reset-project-choices)
          _arguments \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]'
          ;;
        login)
          _arguments \
            '--no-browser[Wypisz URL autoryzacji zamiast otwierać przeglądarkę (dla sesji SSH/bez interfejsu)]' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:name:_claude_mcp_servers'
          ;;
        logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:name:_claude_mcp_servers'
          ;;
      esac
      ;;
  esac
}

_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:Waliduj wtyczkę lub manifest marketplace'
    'marketplace:Zarządzaj marketplace Claude Code'
    'list:Wyświetl zainstalowane wtyczki'
    'details:Pokaż inwentarz komponentów i przewidywany koszt tokenów dla wtyczki'
    'install:Zainstaluj wtyczkę z dostępnych marketplace'
    'i:Zainstaluj wtyczkę z dostępnych marketplace (skrót dla install)'
    'init:Utwórz szkielet nowej wtyczki (ładuje się automatycznie w następnej sesji)'
    'new:Utwórz szkielet nowej wtyczki (alias dla init)'
    'uninstall:Odinstaluj zainstalowaną wtyczkę'
    'remove:Odinstaluj zainstalowaną wtyczkę (alias dla uninstall)'
    'enable:Włącz wyłączoną wtyczkę'
    'disable:Wyłącz włączoną wtyczkę'
    'update:Zaktualizuj wtyczkę do najnowszej wersji'
    'eval:Uruchom przypadki testowe dla wtyczki i zgłoś ocenione wyniki'
    'prune:Usuń automatycznie zainstalowane zależności, które nie są już potrzebne'
    'autoremove:Usuń automatycznie zainstalowane zależności, które nie są już potrzebne (alias dla prune)'
    'tag:Utwórz tag git {name}--v{version} dla wydania wtyczki'
    'help:Wyświetl pomoc'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'polecenia plugin' plugin_commands
      ;;
    args)
      case $words[1] in
        validate)
          _arguments \
            '--strict[Traktuj ostrzeżenia jako błędy (kod wyjścia 1)]' \
            '--json[Wypisz raport walidacji jako JSON (te same kody wyjścia)]' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Zakres instalacji]:scope:(user project local)' \
            '*--config[Ustaw opcję userConfig zadeklarowaną w manifeście wtyczki (można powtarzać)]:key=value:' \
            '(-y --yes)'{-y,--yes}'[Zaakceptuj wyświetlone polecenie zadeklarowane przez marketplace bez pytania o potwierdzenie]' \
            '--json[Wypisz jedną linię wyniku czytelną maszynowo zamiast komunikatu dla człowieka]' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Zakres instalacji]:scope:(user project local)' \
            '--keep-data[Zachowaj katalog trwałych danych wtyczki]' \
            '--prune[Usuń także automatycznie zainstalowane zależności, które nie są już potrzebne]' \
            '(-y --yes)'{-y,--yes}'[Pomiń pytanie o potwierdzenie --prune]' \
            '--json[Wypisz jedną linię wyniku czytelną maszynowo zamiast komunikatu dla człowieka (nie z --prune)]' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Zakres instalacji]:scope:(user project local)' \
            '--json[Wypisz jedną linię wyniku czytelną maszynowo zamiast komunikatu dla człowieka]' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        disable)
          _arguments \
            '(-a --all)'{-a,--all}'[Wyłącz wszystkie włączone wtyczki]' \
            '(-s --scope)'{-s,--scope}'[Zakres instalacji]:scope:(user project local)' \
            '--json[Wypisz jedną linię wyniku czytelną maszynowo zamiast komunikatu dla człowieka]' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '::plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Zakres instalacji]:scope:(user project local managed)' \
            '(-y --yes)'{-y,--yes}'[Zaakceptuj wyświetlone polecenie zadeklarowane przez marketplace bez pytania o potwierdzenie]' \
            '--json[Wypisz jedną linię wyniku czytelną maszynowo zamiast komunikatu dla człowieka]' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list)
          _arguments \
            '--json[Wyjście w formacie JSON]' \
            '--available[Uwzględnij wtyczki dostępne w marketplace (wymaga --json)]' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]'
          ;;
        prune|autoremove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Zakres, w którym wykonać czyszczenie]:scope:(user project local)' \
            '--dry-run[Wypisz, co zostałoby usunięte, bez usuwania]' \
            '(-y --yes)'{-y,--yes}'[Pomiń pytanie o potwierdzenie]' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init|new)
          _arguments \
            '--description[Opis w manifeście]:text:' \
            '--author[Nazwa autora (domyślnie: git config user.name)]:name:' \
            '--author-email[E-mail autora (domyślnie: git config user.email)]:email:' \
            '--with[Komponenty, których szkielet również utworzyć]:components:' \
            '(-f --force)'{-f,--force}'[Nadpisz istniejący .claude-plugin/ w miejscu docelowym]' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '--case[Filtruj przypadki według wzorca glob nazwy]:glob:' \
            '*--tag[Filtruj przypadki według tagu (można powtarzać)]:tag:' \
            '--runs[Nadpisz liczbę uruchomień na przypadek (domyślnie: case.runs, w przeciwnym razie 3)]:n:' \
            '(-j --concurrency)'{-j,--concurrency}'[Uruchamiaj do n agentów jednocześnie (1-8; domyślnie 1)]:n:' \
            '--model[Nadpisz model dla wszystkich przypadków]:model:_claude_model_names' \
            '--judge-model[Nadpisz model oceniającego LLM (domyślnie: haiku)]:model:_claude_model_names' \
            '--max-cost-usd[Twardy limit kosztów; po osiągnięciu przerwij i zgłoś częściowe wyniki (kod wyjścia 2)]:usd:' \
            '--output-dir[Katalog dla aggregate-result.json]:dir:_directories' \
            '--eval-dir[Nazwa katalogu (wewnątrz wtyczki) z przypadkami ewaluacji]:dir:' \
            '--json[Wypisz pełny wynik uruchomienia jako JSON na stdout lub zapisz go do tego pliku .json]::path:_files' \
            '--threshold[Zakończ z kodem 1, jeśli wynik któregokolwiek przypadku jest poniżej tego progu (domyślnie: 1.0)]:threshold:' \
            '*--allow-tools[Zgoda operatora na narzędzia objęte kontrolą (Bash, Write, Edit, WebFetch, mcp__*)]:tools:' \
            '(--no-scaffold)--scaffold[Uruchamiaj scaffold_script każdego przypadku (wykonuje bash dostarczony przez autora na Twoim koncie; domyślnie wyłączone)]' \
            '(--scaffold)--no-scaffold[Jawnie pomiń scaffold_script]' \
            '--trust-plugin[Zadeklaruj zaufanie do tej wtyczki i jej zestawu ewaluacji, pomijając pytanie o zaufanie przy pierwszym uruchomieniu (dla CI)]' \
            '--ablation[Uruchom także przebieg bazowy bez wtyczki i zgłoś różnicę wyników]:mode:(none with-without)' \
            '--mocks[Atrapy zastępujące serwery MCP, z <eval dir>/mocks/]:mode:(record off)' \
            '--allow-real-servers[Z --mocks record: uruchom także prawdziwe procesy serwerów MCP, które nie mają atrapy]' \
            '--keep-temp[Zachowaj katalogi scaffold do debugowania]' \
            '--verbose[Zapisuj zdarzenia śledzenia dla każdej wiadomości w dzienniku debugowania]' \
            '--report[Zapisz samodzielny raport HTML pod tą ścieżką zamiast w katalogu wyników]:path:_files' \
            '(--no-publish)--publish-report[Wymagaj także opublikowania raportu na claude.ai]' \
            '(--publish-report)--no-publish[Zachowaj raport HTML tylko lokalnie; nie publikuj go na claude.ai]' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '::target: _alternative "plugins\:installed plugin\:_claude_installed_plugins" "files\:path\:_files"'
          ;;
        tag)
          _arguments \
            '--push[Wypchnij tag do --remote po jego utworzeniu]' \
            '--dry-run[Wypisz, co zostałoby otagowane, bez tworzenia tagu]' \
            '(-f --force)'{-f,--force}'[Pomiń sprawdzanie niezatwierdzonych zmian i istniejącego już tagu]' \
            '(-m --message)'{-m,--message}'[Komunikat adnotacji tagu (użyj %s dla wersji)]:msg:' \
            '--remote[Zdalne repozytorium, do którego wypchnąć przy --push]:name:' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '::path:_files'
          ;;
      esac
      ;;
  esac
}

_claude_plugin_marketplace() {
  local -a marketplace_commands
  marketplace_commands=(
    'add:Dodaj marketplace z URL, ścieżki lub repozytorium GitHub'
    'list:Wyświetl skonfigurowane marketplace'
    'remove:Usuń skonfigurowany marketplace'
    'rm:Usuń skonfigurowany marketplace (alias dla remove)'
    'update:Zaktualizuj marketplace ze źródła - zaktualizuj wszystkie jeśli nie podano nazwy'
    'help:Wyświetl pomoc'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'polecenia marketplace' marketplace_commands
      ;;
    args)
      case $words[1] in
        add)
          _arguments \
            '--sparse[Ogranicz checkout do wybranych katalogów przez git sparse-checkout (dla monorepo)]:paths:' \
            '--scope[Gdzie zadeklarować marketplace]:scope:(user project local)' \
            '--claudeai[Dodaj marketplace o tej nazwie hostowany dla Ciebie przez claude.ai]' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '--json[Wyjście w formacie JSON]' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]'
          ;;
        remove|rm)
          _arguments \
            '--scope[Usuń deklarację marketplace z określonego zakresu ustawień (pomiń, aby usunąć ją ze wszystkich zakresów)]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:name:'
          ;;
        update)
          _arguments \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '::name:'
          ;;
      esac
      ;;
  esac
}

_claude_install() {
  _arguments \
    '--force[Wymuś instalację nawet jeśli już zainstalowano]' \
    '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
    '::target:(stable latest)'
}

_claude_agents() {
  _arguments \
    '*--add-dir[Dodatkowy katalog z dostępem dla narzędzi w wysłanych sesjach]:directory:_directories' \
    '--agent[Domyślny agent dla sesji wysyłanych z widoku agentów]:agent:_claude_agent_names' \
    '--all[Z --json: dołącz również ukończone sesje w tle]' \
    '--allow-dangerously-skip-permissions[Udostępnij tryb pomijania uprawnień wysłanym sesjom]' \
    '--cwd[Pokaż tylko sesje w tle uruchomione pod ścieżką]:path:_directories' \
    '--dangerously-skip-permissions[Alias dla --permission-mode bypassPermissions]' \
    '--effort[Domyślny poziom wysiłku dla wysłanych sesji]:level:(low medium high xhigh max)' \
    '--json[Wydrukuj aktywne sesje jako tablicę JSON i zakończ]' \
    '*--mcp-config[Konfiguracja serwera MCP do zastosowania w wysłanych sesjach]:config:' \
    '--model[Domyślny model dla sesji wysyłanych z widoku agentów]:model:_claude_model_names' \
    '--permission-mode[Domyślny tryb uprawnień dla wysłanych sesji]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Załaduj wtyczki z katalogu dla widoku agentów i wysłanych sesji]:path:_directories' \
    '--setting-sources[Lista źródeł ustawień oddzielona przecinkami do załadowania (user, project, local)]:sources:' \
    '--settings[Plik ustawień lub ciąg JSON do zastosowania]:file-or-json:_files' \
    '--strict-mcp-config[Używaj tylko serwerów MCP z --mcp-config w wysłanych sesjach]' \
    '--restricted[Uruchamiaj wysyłane sesje w trybie ograniczonym]' \
    '(-h --help)'{-h,--help}'[Wyświetl pomoc dla polecenia]'
}

_claude_auth() {
  local -a auth_commands
  auth_commands=(
    'login:Zaloguj się do konta Anthropic'
    'logout:Wyloguj się z konta Anthropic'
    'status:Pokaż status uwierzytelniania'
    'help:Wyświetl pomoc'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Wyświetl pomoc dla polecenia]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'polecenia auth' auth_commands
      ;;
    args)
      case $words[1] in
        login)
          _arguments \
            '--email[Wstępnie wypełnij adres e-mail na stronie logowania]:email:' \
            '--sso[Wymuś logowanie przez SSO]' \
            '(--claudeai)--console[Użyj Anthropic Console (rozliczanie za użycie API) zamiast subskrypcji Claude]' \
            '(--console)--claudeai[Użyj subskrypcji Claude (domyślnie)]' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc dla polecenia]'
          ;;
        status)
          _arguments \
            '(--text)--json[Wyjście w formacie JSON (domyślnie)]' \
            '(--json)--text[Wyjście jako czytelny tekst]' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc dla polecenia]'
          ;;
        logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc dla polecenia]'
          ;;
      esac
      ;;
  esac
}

_claude_auto_mode() {
  local -a auto_mode_commands
  auto_mode_commands=(
    'config:Wydrukuj efektywną konfigurację trybu automatycznego jako JSON'
    'critique:Uzyskaj opinię AI na temat niestandardowych reguł trybu automatycznego'
    'defaults:Wydrukuj domyślne reguły trybu automatycznego jako JSON'
    'reset:Zresetuj konfigurację trybu automatycznego do domyślnych ustawień fabrycznych'
    'help:Wyświetl pomoc'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Wyświetl pomoc dla polecenia]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'polecenia auto-mode' auto_mode_commands
      ;;
    args)
      case $words[1] in
        critique)
          _arguments \
            '--model[Nadpisz używany model]:model:_claude_model_names' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc dla polecenia]'
          ;;
        defaults)
          _arguments \
            '--label[Pokaż tylko reguły, których etykieta zaczyna się od tego prefiksu (bez rozróżniania wielkości liter)]:prefix:' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc dla polecenia]'
          ;;
        reset)
          _arguments \
            '(-y --yes)'{-y,--yes}'[Pomiń pytanie o potwierdzenie]' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc dla polecenia]'
          ;;
        config)
          _arguments \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc dla polecenia]'
          ;;
      esac
      ;;
  esac
}

_claude_gateway() {
  _arguments \
    '--config[Ścieżka do konfiguracji YAML bramy]:path:_files' \
    '(-h --help)'{-h,--help}'[Wyświetl pomoc dla polecenia]'
}

_claude_project() {
  local -a project_commands
  project_commands=(
    'purge:Usuń cały stan Claude Code dla projektu (transkrypcje, zadania, historia plików, wpis konfiguracji)'
    'help:Wyświetl pomoc'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Wyświetl pomoc dla polecenia]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'polecenia project' project_commands
      ;;
    args)
      case $words[1] in
        purge)
          _arguments \
            '--dry-run[Wypisz, co zostałoby usunięte, bez usuwania czegokolwiek]' \
            '(-y --yes)'{-y,--yes}'[Pomiń pytanie o potwierdzenie]' \
            '(-i --interactive)'{-i,--interactive}'[Pytaj o każdy element przed usunięciem]' \
            '(1)--all[Wyczyść stan wszystkich projektów (wyklucza się ze ścieżką)]' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc dla polecenia]' \
            '(--all)::path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Wydrukuj surowy ładunek bugs.json zamiast sformatowanych wyników]' \
    '--timeout[Maksymalna liczba minut oczekiwania na zakończenie przeglądu (domyślnie: 45)]:minutes:' \
    '(--no-post)--post[Opublikuj wyniki zakończonego przeglądu w PR w Twoim imieniu (tylko cele PR; jeden zwykły komentarz, nie review)]' \
    '(--post)--no-post[Nie publikuj wyników w PR (domyślnie)]' \
    '(-h --help)'{-h,--help}'[Wyświetl pomoc dla polecenia]' \
    '1:target:'
}

_claude_respawn() {
  _arguments \
    '(1)--all[Uruchom ponownie wszystkie działające sesje w tle]' \
    '(-h --help)'{-h,--help}'[Wyświetl pomoc dla polecenia]' \
    '(--all)::session:_claude_background_sessions'
}

_claude_rm() {
  _arguments \
    '--discard-unpushed[Odrzuć także niewypchnięte commity i niezatwierdzone zmiany worktree (podaj commit@worktree-id zgłoszone przez poprzednie claude rm)]:commit@worktree-id:' \
    '--force-remove-worktree[Usuń katalog worktree, nawet jeśli hook WorktreeRemove lub git nie mogły go usunąć (podaj worktree-id zgłoszone przez poprzednie claude rm)]:worktree-id:' \
    '(-h --help)'{-h,--help}'[Wyświetl pomoc dla polecenia]' \
    '1:session:_claude_background_sessions'
}

_claude_import() {
  _arguments \
    '--dry-run[Pokaż, co zostałoby zaimportowane, bez zapisywania czegokolwiek]' \
    '--yes[Pomiń interaktywny wybór (w środowiskach bez interfejsu podaj --yes=<digest> z podglądu /import)]' \
    '(-h --help)'{-h,--help}'[Wyświetl pomoc dla polecenia]' \
    '::source:(codex gemini cursor)'
}

(( $+_comps[claude] )) || compdef _claude claude
