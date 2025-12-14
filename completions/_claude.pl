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
    'mcp:Konfiguruj i zarządzaj serwerami MCP'
    'plugin:Zarządzaj wtyczkami Claude Code'
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
    '--mcp-debug[[\Przestarzałe. Użyj zamiast tego --debug\] Włącz tryb debugowania MCP (wyświetla błędy serwera MCP)]'
    '--dangerously-skip-permissions[Pomiń wszystkie sprawdzenia uprawnień. Zalecane tylko dla piaskownicy bez dostępu do internetu]'
    '--allow-dangerously-skip-permissions[Włącz opcję pomijania sprawdzania uprawnień bez domyślnego włączania]'
    '--replay-user-messages[Ponownie wyślij wiadomości użytkownika z stdin na stdout w celu potwierdzenia]'
    '--allowed-tools[Lista dozwolonych nazw narzędzi oddzielona przecinkami lub spacjami (np. "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Lista dozwolonych nazw narzędzi oddzielona przecinkami lub spacjami (format camelCase)]:tools:'
    '--tools[Określ listę dostępnych narzędzi z wbudowanego zestawu. Tylko tryb drukowania]:tools:'
    '--disallowed-tools[Lista niedozwolonych nazw narzędzi oddzielona przecinkami lub spacjami (np. "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Lista niedozwolonych nazw narzędzi oddzielona przecinkami lub spacjami (format camelCase)]:tools:'
    '--mcp-config[Załaduj serwery MCP z pliku JSON lub ciągu znaków (oddzielone spacjami)]:configs:'
    '--system-prompt[Prompt systemowy do użycia w sesji]:prompt:'
    '--append-system-prompt[Dołącz prompt systemowy do domyślnego promptu systemowego]:prompt:'
    '--permission-mode[Tryb uprawnień do użycia w sesji]:mode:(acceptEdits bypassPermissions default dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Kontynuuj najnowszą konwersację]'
    '(-r --resume)'{-r,--resume}'[Wznów konwersację - podaj identyfikator sesji lub wybierz interaktywnie]:sessionId:_claude_sessions'
    '--fork-session[Utwórz nowy identyfikator sesji zamiast ponownego użycia oryginalnego przy wznawianiu (z --resume lub --continue)]'
    '--model[Model dla bieżącej sesji. Określ alias dla najnowszego modelu (np. '\''sonnet'\'' lub '\''opus'\'')]:model:'
    '--fallback-model[Włącz automatyczne przełączanie na określony model gdy domyślny model jest przeciążony (tylko --print)]:model:'
    '--settings[Ścieżka do pliku JSON z ustawieniami lub ciąg JSON do załadowania dodatkowych ustawień]:file-or-json:_files'
    '--add-dir[Dodatkowe katalogi z dostępem dla narzędzi]:directories:_directories'
    '--ide[Automatycznie połącz z IDE przy starcie jeśli dostępne jest dokładnie jedno prawidłowe IDE]'
    '--strict-mcp-config[Używaj tylko serwerów MCP z --mcp-config i ignoruj wszystkie inne ustawienia MCP]'
    '--session-id[Określony identyfikator sesji do użycia w konwersacji (musi być prawidłowym UUID)]:uuid:'
    '--agents[Obiekt JSON definiujący niestandardowych agentów]:json:'
    '--setting-sources[Lista źródeł ustawień oddzielona przecinkami do załadowania (user, project, local)]:sources:'
    '--plugin-dir[Katalog do załadowania wtyczek tylko dla tej sesji (powtarzalne)]:paths:_directories'
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
      esac
      ;;
  esac
}
_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:Waliduj wtyczkę lub manifest marketplace'
    'marketplace:Zarządzaj marketplace Claude Code'
    'install:Zainstaluj wtyczkę z dostępnych marketplace'
    'i:Zainstaluj wtyczkę z dostępnych marketplace (skrót dla install)'
    'uninstall:Odinstaluj zainstalowaną wtyczkę'
    'remove:Odinstaluj zainstalowaną wtyczkę (alias dla uninstall)'
    'enable:Włącz wyłączoną wtyczkę'
    'disable:Wyłącz włączoną wtyczkę'
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
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-h --help)'{-h,--help}'[Wyświetl pomoc]' \
            '1:plugin:_claude_installed_plugins'
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
(( $+_comps[claude] )) || compdef _claude claude
