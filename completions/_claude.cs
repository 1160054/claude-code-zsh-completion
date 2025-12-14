#compdef claude
# Dynamické funkce automatického doplňování
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
    'mcp:Konfigurace a správa MCP serverů'
    'plugin:Správa pluginů Claude Code'
    'setup-token:Nastavení tokenu pro dlouhodobou autentizaci (vyžaduje předplatné Claude)'
    'doctor:Kontrola zdraví systému automatických aktualizací Claude Code'
    'update:Kontrola a instalace aktualizací'
    'install:Instalace nativní verze Claude Code'
  )
  local -a main_options
  main_options=(
    '(-d --debug)'{-d,--debug}'[Zapnout režim ladění s volitelným filtrováním kategorií (např. "api,hooks" nebo "!statsig,!file")]:filter:'
    '--verbose[Přepsat nastavení podrobného režimu z konfiguračního souboru]'
    '(-p --print)'{-p,--print}'[Vypsat odpověď a ukončit (pro použití s pipe). Poznámka: používejte pouze v důvěryhodných adresářích]'
    '--output-format[Formát výstupu (s --print): "text" (výchozí), "json" (jeden výsledek), nebo "stream-json" (streamování v reálném čase)]:format:(text json stream-json)'
    '--json-schema[JSON schéma pro validaci strukturovaného výstupu]:schema:'
    '--include-partial-messages[Zahrnout částečné fragmenty zpráv při jejich příchodu (s --print a --output-format=stream-json)]'
    '--input-format[Formát vstupu (s --print): "text" (výchozí) nebo "stream-json" (streamovaný vstup v reálném čase)]:format:(text stream-json)'
    '--mcp-debug[\[Zastaralé. Použijte --debug místo toho\] Zapnout režim ladění MCP (zobrazuje chyby MCP serveru)]'
    '--dangerously-skip-permissions[Obejít všechny kontroly oprávnění. Doporučeno pouze pro sandboxová prostředí bez přístupu k internetu]'
    '--allow-dangerously-skip-permissions[Povolit možnost obejití kontrol oprávnění bez povolení ve výchozím nastavení]'
    '--replay-user-messages[Znovu odeslat uživatelské zprávy ze stdin na stdout pro potvrzení]'
    '--allowed-tools[Seznam povolených názvů nástrojů oddělených čárkou nebo mezerou (např. "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Seznam povolených názvů nástrojů oddělených čárkou nebo mezerou (formát camelCase)]:tools:'
    '--tools[Určit seznam dostupných nástrojů z vestavěné sady. Pouze v režimu print]:tools:'
    '--disallowed-tools[Seznam zakázaných názvů nástrojů oddělených čárkou nebo mezerou (např. "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Seznam zakázaných názvů nástrojů oddělených čárkou nebo mezerou (formát camelCase)]:tools:'
    '--mcp-config[Načíst MCP servery z JSON souboru nebo řetězce (oddělené mezerami)]:configs:'
    '--system-prompt[Systémový prompt pro použití v relaci]:prompt:'
    '--append-system-prompt[Připojit systémový prompt ke standardnímu systémovému promptu]:prompt:'
    '--permission-mode[Režim oprávnění pro použití v relaci]:mode:(acceptEdits bypassPermissions default dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Pokračovat v poslední konverzaci]'
    '(-r --resume)'{-r,--resume}'[Obnovit konverzaci - zadejte identifikátor relace nebo vyberte interaktivně]:sessionId:_claude_sessions'
    '--fork-session[Vytvořit nový identifikátor relace místo opětovného použití původního při obnovení (s --resume nebo --continue)]'
    '--model[Model pro aktuální relaci. Zadejte alias pro nejnovější model (např. '\''sonnet'\'' nebo '\''opus'\'')]:model:'
    '--fallback-model[Povolit automatické přepnutí na zadaný model když je výchozí model přetížen (pouze --print)]:model:'
    '--settings[Cesta k JSON souboru s nastavením nebo JSON řetězec pro načtení dodatečných nastavení]:file-or-json:_files'
    '--add-dir[Další adresáře pro poskytnutí přístupu nástrojům]:directories:_directories'
    '--ide[Automaticky se připojit k IDE při spuštění pokud je dostupné právě jedno platné IDE]'
    '--strict-mcp-config[Použít pouze MCP servery z --mcp-config a ignorovat všechna ostatní MCP nastavení]'
    '--session-id[Konkrétní identifikátor relace pro použití v konverzaci (musí být platné UUID)]:uuid:'
    '--agents[JSON objekt definující vlastní agenty]:json:'
    '--setting-sources[Seznam zdrojů nastavení oddělených čárkou pro načtení (user, project, local)]:sources:'
    '--plugin-dir[Adresář pro načtení pluginů pouze pro tuto relaci (lze opakovat)]:paths:_directories'
    '(-v --version)'{-v,--version}'[Vypsat číslo verze]'
    '(-h --help)'{-h,--help}'[Zobrazit nápovědu pro příkaz]'
  )
  _arguments -C \
    $main_options \
    '1: :->command' \
    '*::arg:->args'
  case $state in
    command)
      _describe -t commands 'příkazy claude' main_commands
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
          _message "bez argumentů"
          ;;
      esac
      ;;
  esac
}
_claude_mcp() {
  local -a mcp_commands
  mcp_commands=(
    'serve:Spustit MCP server Claude Code'
    'add:Přidat MCP server do Claude Code'
    'remove:Odstranit MCP server'
    'list:Zobrazit seznam nakonfigurovaných MCP serverů'
    'get:Získat detaily MCP serveru'
    'add-json:Přidat MCP server (stdio nebo SSE) s JSON řetězcem'
    'add-from-claude-desktop:Importovat MCP servery z Claude Desktop (pouze Mac a WSL)'
    'reset-project-choices:Resetovat všechny schválené/odmítnuté servery s rozsahem projektu (.mcp.json) v tomto projektu'
    'help:Zobrazit nápovědu'
  )
  local curcontext="$curcontext" state line
  typeset -A opt_args
  _arguments -C \
    '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
    '1: :->command' \
    '*::arg:->args'
  case $state in
    command)
      _describe -t commands 'příkazy mcp' mcp_commands
      ;;
    args)
      case $words[1] in
        serve)
          _arguments \
            '(-d --debug)'{-d,--debug}'[Zapnout režim ladění]' \
            '--verbose[Přepsat nastavení podrobného režimu z konfiguračního souboru]' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]'
          ;;
        add)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Rozsah konfigurace (local, user, project)]:scope:(local user project)' \
            '(-t --transport)'{-t,--transport}'[Typ transportu (stdio, sse, http)]:transport:(stdio sse http)' \
            '(-e --env)'{-e,--env}'[Nastavit proměnnou prostředí (např. -e KEY=value)]:env:' \
            '(-H --header)'{-H,--header}'[Nastavit WebSocket hlavičku]:header:' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:name:' \
            '2:commandOrUrl:' \
            '*:args:'
          ;;
        remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Rozsah konfigurace (local, user, project) - odstranit z existujícího rozsahu pokud není zadáno]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:name:_claude_mcp_servers'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]'
          ;;
        get)
          _arguments \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:name:_claude_mcp_servers'
          ;;
        add-json)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Rozsah konfigurace (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:name:' \
            '2:json:'
          ;;
        add-from-claude-desktop)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Rozsah konfigurace (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]'
          ;;
        reset-project-choices)
          _arguments \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]'
          ;;
      esac
      ;;
  esac
}
_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:Validovat plugin nebo manifest marketplace'
    'marketplace:Správa marketplace Claude Code'
    'install:Nainstalovat plugin z dostupných marketplace'
    'i:Nainstalovat plugin z dostupných marketplace (zkratka pro install)'
    'uninstall:Odinstalovat nainstalovaný plugin'
    'remove:Odinstalovat nainstalovaný plugin (alias pro uninstall)'
    'enable:Povolit zakázaný plugin'
    'disable:Zakázat povolený plugin'
    'help:Zobrazit nápovědu'
  )
  local curcontext="$curcontext" state line
  typeset -A opt_args
  _arguments -C \
    '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
    '1: :->command' \
    '*::arg:->args'
  case $state in
    command)
      _describe -t commands 'příkazy plugin' plugin_commands
      ;;
    args)
      case $words[1] in
        validate)
          _arguments \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:plugin:_claude_installed_plugins'
          ;;
      esac
      ;;
  esac
}
_claude_plugin_marketplace() {
  local -a marketplace_commands
  marketplace_commands=(
    'add:Přidat marketplace z URL, cesty nebo GitHub repozitáře'
    'list:Zobrazit seznam nakonfigurovaných marketplace'
    'remove:Odstranit nakonfigurovaný marketplace'
    'rm:Odstranit nakonfigurovaný marketplace (alias pro remove)'
    'update:Aktualizovat marketplace ze zdroje - aktualizovat všechny pokud není zadán název'
    'help:Zobrazit nápovědu'
  )
  local curcontext="$curcontext" state line
  typeset -A opt_args
  _arguments -C \
    '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
    '1: :->command' \
    '*::arg:->args'
  case $state in
    command)
      _describe -t commands 'příkazy marketplace' marketplace_commands
      ;;
    args)
      case $words[1] in
        add)
          _arguments \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]'
          ;;
        remove|rm)
          _arguments \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:name:'
          ;;
        update)
          _arguments \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '::name:'
          ;;
      esac
      ;;
  esac
}
_claude_install() {
  _arguments \
    '--force[Vynutit instalaci i když je již nainstalováno]' \
    '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
    '::target:(stable latest)'
}
(( $+_comps[claude] )) || compdef _claude claude
