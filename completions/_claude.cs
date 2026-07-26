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

  local -a sessions
  local state_dir project_dir session_file uuid summary

  # Sessions live under <config>/projects/<cwd with / and . turned into ->
  project_dir=${${PWD//\//-}//./-}

  for state_dir in ${(f)"$(_claude_state_dirs)"}; do
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
    'mcp:Konfigurace a správa MCP serverů'
    'plugin:Správa pluginů Claude Code'
    'agents:Správa agentů na pozadí'
    'auth:Správa autentizace'
    'auto-mode:Prohlédnout nebo resetovat konfiguraci klasifikátoru automatického režimu'
    'gateway:Spustit podnikovou bránu pro autentizaci/telemetrii'
    'project:Správa stavu projektu Claude Code'
    'ultrareview:Spustit cloudovou multiagentní revizi kódu a vypsat zjištění'
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
    '--max-budget-usd[Maximální částka v dolarech, kterou lze utratit za volání API (pouze --print)]:amount:'
    '--replay-user-messages[Znovu odeslat uživatelské zprávy ze stdin na stdout pro potvrzení]'
    '--allowed-tools[Seznam povolených názvů nástrojů oddělených čárkou nebo mezerou (např. "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Seznam povolených názvů nástrojů oddělených čárkou nebo mezerou (formát camelCase)]:tools:'
    '--tools[Určit seznam dostupných nástrojů z vestavěné sady. Pouze v režimu print]:tools:'
    '--disallowed-tools[Seznam zakázaných názvů nástrojů oddělených čárkou nebo mezerou (např. "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Seznam zakázaných názvů nástrojů oddělených čárkou nebo mezerou (formát camelCase)]:tools:'
    '--mcp-config[Načíst MCP servery z JSON souboru nebo řetězce (oddělené mezerami)]:configs:'
    '--system-prompt[Systémový prompt pro použití v relaci]:prompt:'
    '--append-system-prompt[Připojit systémový prompt ke standardnímu systémovému promptu]:prompt:'
    '--permission-mode[Režim oprávnění pro použití v relaci]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Pokračovat v poslední konverzaci]'
    '(-r --resume)'{-r,--resume}'[Obnovit konverzaci - zadejte identifikátor relace nebo vyberte interaktivně]:sessionId:_claude_sessions'
    '--fork-session[Vytvořit nový identifikátor relace místo opětovného použití původního při obnovení (s --resume nebo --continue)]'
    '--no-session-persistence[Zakázat trvalé ukládání relací - relace nebudou uloženy (pouze --print)]'
    '--model[Model pro aktuální relaci. Zadejte alias pro nejnovější model (např. '\''sonnet'\'' nebo '\''opus'\'')]:model:_claude_model_names'
    '--agent[Agent pro aktuální relaci. Přepíše nastavení '\''agent'\'']:agent:_claude_agent_names'
    '--betas[Beta hlavičky pro zahrnutí do API požadavků (pouze uživatelé s API klíčem)]:betas:'
    '--fallback-model[Povolit automatické přepnutí na zadaný model když je výchozí model přetížen (pouze --print)]:model:_claude_model_names'
    '--settings[Cesta k JSON souboru s nastavením nebo JSON řetězec pro načtení dodatečných nastavení]:file-or-json:_files'
    '--add-dir[Další adresáře pro poskytnutí přístupu nástrojům]:directories:_directories'
    '--ide[Automaticky se připojit k IDE při spuštění pokud je dostupné právě jedno platné IDE]'
    '--strict-mcp-config[Použít pouze MCP servery z --mcp-config a ignorovat všechna ostatní MCP nastavení]'
    '--session-id[Konkrétní identifikátor relace pro použití v konverzaci (musí být platné UUID)]:uuid:'
    '--agents[JSON objekt definující vlastní agenty]:json:'
    '--setting-sources[Seznam zdrojů nastavení oddělených čárkou pro načtení (user, project, local)]:sources:'
    '--plugin-dir[Adresář pro načtení pluginů pouze pro tuto relaci (lze opakovat)]:paths:_directories'
    '--disable-slash-commands[Zakázat všechny lomítkové příkazy]'
    '(--bg --background)'{--bg,--background}'[Spustit relaci jako agenta na pozadí a okamžitě se vrátit]'
    '(-w --worktree)'{-w,--worktree}'[Vytvořit nový git worktree pro tuto relaci (volitelně zadejte název)]::name:'
    '--tmux[Vytvořit tmux relaci pro worktree (vyžaduje --worktree)]'
    '(-n --name)'{-n,--name}'[Nastavit zobrazovaný název pro tuto relaci]:name:'
    '--effort[Úroveň úsilí pro aktuální relaci]:level:(low medium high xhigh max)'
    '--debug-file[Zapisovat ladicí logy do konkrétní cesty souboru (implicitně zapne režim ladění)]:path:_files'
    '--from-pr[Obnovit relaci propojenou s PR podle čísla/URL, nebo otevřít interaktivní výběr]::value:'
    '--remote-control[Spustit interaktivní relaci s povoleným vzdáleným ovládáním (volitelně pojmenovanou)]::name:'
    '--remote-control-session-name-prefix[Předpona pro automaticky generované názvy relací vzdáleného ovládání]:prefix:'
    '--chrome[Zapnout integraci Claude v Chrome]'
    '--no-chrome[Vypnout integraci Claude v Chrome]'
    '--plugin-url[Stáhnout .zip pluginu z URL pouze pro tuto relaci (lze opakovat)]:url:'
    '--file[Souborové zdroje ke stažení při spuštění (formát: file_id:relative_path)]:specs:'
    '--prompt-suggestions[Zapnout návrhy promptů (vydá předpovězený další prompt v režimu print/SDK)]::value:(true false 1 0 yes no on off)'
    '--forward-subagent-text[Přeposílat text subagenta a bloky přemýšlení jako zprávy (s --print a stream-json)]'
    '--include-hook-events[Zahrnout všechny události životního cyklu hooků do výstupního streamu (se stream-json)]'
    '--exclude-dynamic-system-prompt-sections[Přesunout sekce specifické pro daný stroj do první uživatelské zprávy pro lepší opětovné využití mezipaměti promptů]'
    '--brief[Zapnout nástroj SendUserMessage pro komunikaci agenta s uživatelem]'
    '--safe-mode[Spustit se všemi přizpůsobeními zakázanými (užitečné pro řešení potíží s poškozenou konfigurací)]'
    '--bare[Minimální režim: přeskočit hooky, LSP, synchronizaci pluginů, atribuci, automatickou paměť a automatické zjišťování CLAUDE.md]'
    '--ax-screen-reader[Vykreslit výstup přívětivý pro čtečky obrazovky (plochý text, bez dekorativních okrajů nebo animací)]'
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
    'login:Autentizace u MCP serveru (HTTP, SSE nebo konektor claude.ai)'
    'logout:Vymazat uložené OAuth přihlašovací údaje pro MCP server'
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
        login|logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:name:_claude_mcp_servers'
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
    'list:Zobrazit seznam nainstalovaných pluginů'
    'details:Zobrazit inventář komponent a odhadovanou cenu v tokenech pro plugin'
    'install:Nainstalovat plugin z dostupných marketplace'
    'i:Nainstalovat plugin z dostupných marketplace (zkratka pro install)'
    'init:Vytvořit kostru nového pluginu (automaticky se načte při další relaci)'
    'uninstall:Odinstalovat nainstalovaný plugin'
    'remove:Odinstalovat nainstalovaný plugin (alias pro uninstall)'
    'enable:Povolit zakázaný plugin'
    'disable:Zakázat povolený plugin'
    'update:Aktualizovat plugin na nejnovější verzi'
    'eval:Spustit evaluační případy proti pluginu a nahlásit obodované výsledky'
    'prune:Odstranit automaticky nainstalované závislosti, které již nejsou potřeba'
    'tag:Vytvořit git tag {name}--v{version} pro vydání pluginu'
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
            '(-s --scope)'{-s,--scope}'[Rozsah instalace]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Rozsah instalace]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Rozsah instalace]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Rozsah instalace]:scope:(user project local managed)' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list|prune)
          _arguments \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init)
          _arguments \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:target:'
          ;;
        tag)
          _arguments \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:path:_files'
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

_claude_agents() {
  _arguments \
    '*--add-dir[Další adresář pro poskytnutí přístupu nástrojům v odeslaných relacích]:directory:_directories' \
    '--agent[Výchozí agent pro relace odeslané z pohledu agentů]:agent:_claude_agent_names' \
    '--all[S --json: zahrnout také dokončené relace na pozadí]' \
    '--allow-dangerously-skip-permissions[Zpřístupnit režim obejití oprávnění odeslaným relacím]' \
    '--cwd[Zobrazit pouze relace na pozadí spuštěné pod cestou]:path:_directories' \
    '--dangerously-skip-permissions[Alias pro --permission-mode bypassPermissions]' \
    '--effort[Výchozí úroveň úsilí pro odeslané relace]:level:(low medium high xhigh max)' \
    '--json[Vypsat aktivní relace jako JSON pole a ukončit]' \
    '*--mcp-config[Konfigurace MCP serveru pro použití v odeslaných relacích]:config:' \
    '--model[Výchozí model pro relace odeslané z pohledu agentů]:model:_claude_model_names' \
    '--permission-mode[Výchozí režim oprávnění pro odeslané relace]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Načíst pluginy z adresáře pro pohled agentů a odeslané relace]:path:_directories' \
    '--setting-sources[Seznam zdrojů nastavení oddělených čárkou pro načtení (user, project, local)]:sources:' \
    '--settings[Soubor s nastavením nebo JSON řetězec k použití]:file-or-json:_files' \
    '--strict-mcp-config[Použít pouze MCP servery z --mcp-config v odeslaných relacích]' \
    '(-h --help)'{-h,--help}'[Zobrazit nápovědu pro příkaz]'
}

_claude_auth() {
  local -a auth_commands
  auth_commands=(
    'login:Přihlásit se k vašemu účtu Anthropic'
    'logout:Odhlásit se z vašeho účtu Anthropic'
    'status:Zobrazit stav autentizace'
    'help:Zobrazit nápovědu'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Zobrazit nápovědu pro příkaz]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'příkazy auth' auth_commands
      ;;
    args)
      case $words[1] in
        login|logout|status)
          _arguments \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu pro příkaz]'
          ;;
      esac
      ;;
  esac
}

_claude_auto_mode() {
  local -a auto_mode_commands
  auto_mode_commands=(
    'config:Vypsat efektivní konfiguraci automatického režimu jako JSON'
    'critique:Získat zpětnou vazbu AI k vašim vlastním pravidlům automatického režimu'
    'defaults:Vypsat výchozí pravidla automatického režimu jako JSON'
    'reset:Resetovat konfiguraci automatického režimu na dodané výchozí hodnoty'
    'help:Zobrazit nápovědu'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Zobrazit nápovědu pro příkaz]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'příkazy auto-mode' auto_mode_commands
      ;;
    args)
      case $words[1] in
        config|critique|defaults|reset)
          _arguments \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu pro příkaz]'
          ;;
      esac
      ;;
  esac
}

_claude_gateway() {
  _arguments \
    '--config[Cesta ke konfiguraci brány YAML]:path:_files' \
    '(-h --help)'{-h,--help}'[Zobrazit nápovědu pro příkaz]'
}

_claude_project() {
  local -a project_commands
  project_commands=(
    'purge:Smazat veškerý stav Claude Code pro projekt (přepisy, úkoly, historie souborů, položka konfigurace)'
    'help:Zobrazit nápovědu'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Zobrazit nápovědu pro příkaz]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'příkazy project' project_commands
      ;;
    args)
      case $words[1] in
        purge)
          _arguments \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu pro příkaz]' \
            '1:path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Vypsat surová data bugs.json místo formátovaných zjištění]' \
    '--timeout[Maximální počet minut čekání na dokončení revize]:minutes:' \
    '(-h --help)'{-h,--help}'[Zobrazit nápovědu pro příkaz]' \
    '1:target:'
}

(( $+_comps[claude] )) || compdef _claude claude
