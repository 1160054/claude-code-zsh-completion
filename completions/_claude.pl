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
    'mcp:Konfiguruj i zarządzaj serwerami MCP'
    'plugin:Zarządzaj wtyczkami Claude Code'
    'agents:Zarządzaj agentami w tle'
    'auth:Zarządzaj uwierzytelnianiem'
    'auto-mode:Sprawdź lub zresetuj konfigurację klasyfikatora trybu automatycznego'
    'gateway:Uruchom firmową bramę uwierzytelniania/telemetrii'
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
    '--max-budget-usd[Maksymalna kwota w dolarach do wydania na wywołania API (tylko --print)]:amount:'
    '--replay-user-messages[Ponownie wyślij wiadomości użytkownika z stdin na stdout w celu potwierdzenia]'
    '--allowed-tools[Lista dozwolonych nazw narzędzi oddzielona przecinkami lub spacjami (np. "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Lista dozwolonych nazw narzędzi oddzielona przecinkami lub spacjami (format camelCase)]:tools:'
    '--tools[Określ listę dostępnych narzędzi z wbudowanego zestawu. Tylko tryb drukowania]:tools:'
    '--disallowed-tools[Lista niedozwolonych nazw narzędzi oddzielona przecinkami lub spacjami (np. "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Lista niedozwolonych nazw narzędzi oddzielona przecinkami lub spacjami (format camelCase)]:tools:'
    '--mcp-config[Załaduj serwery MCP z pliku JSON lub ciągu znaków (oddzielone spacjami)]:configs:'
    '--system-prompt[Prompt systemowy do użycia w sesji]:prompt:'
    '--append-system-prompt[Dołącz prompt systemowy do domyślnego promptu systemowego]:prompt:'
    '--permission-mode[Tryb uprawnień do użycia w sesji]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Kontynuuj najnowszą konwersację]'
    '(-r --resume)'{-r,--resume}'[Wznów konwersację - podaj identyfikator sesji lub wybierz interaktywnie]:sessionId:_claude_sessions'
    '--fork-session[Utwórz nowy identyfikator sesji zamiast ponownego użycia oryginalnego przy wznawianiu (z --resume lub --continue)]'
    '--no-session-persistence[Wyłącz trwałość sesji - sesje nie będą zapisywane (tylko --print)]'
    '--model[Model dla bieżącej sesji. Określ alias dla najnowszego modelu (np. '\''sonnet'\'' lub '\''opus'\'')]:model:'
    '--agent[Agent dla bieżącej sesji. Zastępuje ustawienie '\''agent'\'']:agent:'
    '--betas[Nagłówki beta do dołączenia w żądaniach API (tylko użytkownicy klucza API)]:betas:'
    '--fallback-model[Włącz automatyczne przełączanie na określony model gdy domyślny model jest przeciążony (tylko --print)]:model:'
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
    '--tmux[Utwórz sesję tmux dla worktree (wymaga --worktree)]'
    '(-n --name)'{-n,--name}'[Ustaw wyświetlaną nazwę dla tej sesji]:name:'
    '--effort[Poziom wysiłku dla bieżącej sesji]:level:(low medium high xhigh max)'
    '--debug-file[Zapisuj logi debugowania do określonej ścieżki pliku (niejawnie włącza tryb debugowania)]:path:_files'
    '--from-pr[Wznów sesję powiązaną z PR przez numer/URL lub otwórz interaktywny wybór]::value:'
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
        login|logout)
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
    'uninstall:Odinstaluj zainstalowaną wtyczkę'
    'remove:Odinstaluj zainstalowaną wtyczkę (alias dla uninstall)'
    'enable:Włącz wyłączoną wtyczkę'
    'disable:Wyłącz włączoną wtyczkę'
    'update:Zaktualizuj wtyczkę do najnowszej wersji'
    'eval:Uruchom przypadki testowe dla wtyczki i zgłoś ocenione wyniki'
    'prune:Usuń automatycznie zainstalowane zależności, które nie są już potrzebne'
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
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Zakres instalacji]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Zakres instalacji]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Zakres instalacji]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Zakres instalacji]:scope:(user project local managed)' \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list|prune)
          _arguments \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init)
          _arguments \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:target:'
          ;;
        tag)
          _arguments \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:path:_files'
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
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]'
          ;;
        remove|rm)
          _arguments \
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
    '--agent[Domyślny agent dla sesji wysyłanych z widoku agentów]:agent:' \
    '--all[Z --json: dołącz również ukończone sesje w tle]' \
    '--allow-dangerously-skip-permissions[Udostępnij tryb pomijania uprawnień wysłanym sesjom]' \
    '--cwd[Pokaż tylko sesje w tle uruchomione pod ścieżką]:path:_directories' \
    '--dangerously-skip-permissions[Alias dla --permission-mode bypassPermissions]' \
    '--effort[Domyślny poziom wysiłku dla wysłanych sesji]:level:(low medium high xhigh max)' \
    '--json[Wydrukuj aktywne sesje jako tablicę JSON i zakończ]' \
    '*--mcp-config[Konfiguracja serwera MCP do zastosowania w wysłanych sesjach]:config:' \
    '--model[Domyślny model dla sesji wysyłanych z widoku agentów]:model:' \
    '--permission-mode[Domyślny tryb uprawnień dla wysłanych sesji]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Załaduj wtyczki z katalogu dla widoku agentów i wysłanych sesji]:path:_directories' \
    '--setting-sources[Lista źródeł ustawień oddzielona przecinkami do załadowania (user, project, local)]:sources:' \
    '--settings[Plik ustawień lub ciąg JSON do zastosowania]:file-or-json:_files' \
    '--strict-mcp-config[Używaj tylko serwerów MCP z --mcp-config w wysłanych sesjach]' \
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
        login|logout|status)
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
        config|critique|defaults|reset)
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
            '(-h --help)'{-h,--help}'[Wyświetl pomoc dla polecenia]' \
            '1:path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Wydrukuj surowy ładunek bugs.json zamiast sformatowanych wyników]' \
    '--timeout[Maksymalna liczba minut oczekiwania na zakończenie przeglądu]:minutes:' \
    '(-h --help)'{-h,--help}'[Wyświetl pomoc dla polecenia]' \
    '1:target:'
}

(( $+_comps[claude] )) || compdef _claude claude
