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

        # Describe each session by the name it was given (/rename or --name),
        # else by the first thing you typed in it. A name is appended near the
        # end of the transcript and the first message sits at the start, so
        # only those ends are read - these files grow into the megabytes.
        summary=$(tail -c 100000 "$session_file" 2>/dev/null | \
          grep -o '"customTitle":"[^"]*"' 2>/dev/null | tail -1 | \
          sed 's/^"customTitle":"//; s/"$//')
        if [[ -z $summary ]]; then
          summary=$(head -c 200000 "$session_file" 2>/dev/null | \
            grep -m 1 -o '"role":"user","content":"[^"]\{1,60\}' 2>/dev/null | \
            sed 's/.*"content":"//; s/\\n/ /g; s/\\*$//')
        fi
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
    'mcp:Konfigurace a správa MCP serverů'
    'plugin:Správa pluginů Claude Code'
    'agents:Správa agentů na pozadí'
    'attach:Otevřít relaci na pozadí v tomto terminálu'
    'logs:Vypsat nedávný výstup terminálu relace na pozadí'
    'stop:Zastavit relaci na pozadí (její konverzace zůstane zachována)'
    'respawn:Restartovat relaci na pozadí, aby běžela na aktuální verzi Claude Code'
    'rm:Smazat relaci na pozadí a její worktree, pokud je to bezpečné'
    'auth:Správa autentizace'
    'auto-mode:Prohlédnout nebo resetovat konfiguraci klasifikátoru automatického režimu'
    'gateway:Spustit podnikovou bránu pro autentizaci/telemetrii'
    'import:Importovat konfiguraci z jiného AI agenta pro programování do Claude Code'
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
    '--restricted[Omezený režim: odebrat nástroje spouštějící příkazy nebo kód a WebFetch, ignorovat nastavení user/project/local a omezit souborové nástroje na pracovní adresáře]'
    '--max-budget-usd[Maximální částka v dolarech, kterou lze utratit za volání API (pouze --print)]:amount:'
    '--replay-user-messages[Znovu odeslat uživatelské zprávy ze stdin na stdout pro potvrzení]'
    '--allowed-tools[Seznam povolených názvů nástrojů oddělených čárkou nebo mezerou (např. "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Seznam povolených názvů nástrojů oddělených čárkou nebo mezerou (formát camelCase)]:tools:'
    '--tools[Určit seznam dostupných nástrojů z vestavěné sady. Pouze v režimu print]:tools:'
    '--disallowed-tools[Seznam zakázaných názvů nástrojů oddělených čárkou nebo mezerou (např. "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Seznam zakázaných názvů nástrojů oddělených čárkou nebo mezerou (formát camelCase)]:tools:'
    '--mcp-config[Načíst MCP servery z JSON souboru nebo řetězce (oddělené mezerami)]:configs:'
    '--system-prompt[Systémový prompt pro použití v relaci]:prompt:'
    '--system-prompt-file[Načíst systémový prompt ze souboru]:file:_files'
    '--append-system-prompt[Připojit systémový prompt ke standardnímu systémovému promptu]:prompt:'
    '--append-system-prompt-file[Načíst systémový prompt ze souboru a připojit ho ke standardnímu systémovému promptu]:file:_files'
    '--system-prompt-snapshot[Zaznamenat systémový prompt jednou za konverzaci a doslovně ho znovu použít při každém požadavku a obnovení (on, výchozí) nebo ho při každém požadavku vykreslit znovu (off)]:mode:(on off)'
    '--permission-mode[Režim oprávnění pro použití v relaci]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '--permission-prompts[Kdo odpovídá na výzvy k oprávnění s --print: "host" (SDK host nebo --permission-prompt-tool) nebo "none" (vše, co by vyžadovalo výzvu, je zamítnuto)]:target:(host none)'
    '--permission-prompt-tool[MCP nástroj pro výzvy k oprávnění (pouze --print)]:tool:'
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
    '--desktop[Otevřít v aplikaci Claude Desktop místo terminálu (s --continue nebo --resume <id> pro výběr relace)]'
    '--strict-mcp-config[Použít pouze MCP servery z --mcp-config a ignorovat všechna ostatní MCP nastavení]'
    '--session-id[Konkrétní identifikátor relace pro použití v konverzaci (musí být platné UUID)]:uuid:'
    '--agents[JSON objekt definující vlastní agenty]:json:'
    '--setting-sources[Seznam zdrojů nastavení oddělených čárkou pro načtení (user, project, local)]:sources:'
    '--plugin-dir[Adresář pro načtení pluginů pouze pro tuto relaci (lze opakovat)]:paths:_directories'
    '--disable-slash-commands[Zakázat všechny lomítkové příkazy]'
    '(--bg --background)'{--bg,--background}'[Spustit relaci jako agenta na pozadí a okamžitě se vrátit]'
    '(-w --worktree)'{-w,--worktree}'[Vytvořit nový git worktree pro tuto relaci (volitelně zadejte název)]::name:'
    '--tmux=-[Vytvořit tmux relaci pro worktree (vyžaduje --worktree). Použije nativní panely iTerm2, pokud jsou dostupné; --tmux=classic pro tradiční tmux]::mode:(classic)'
    '(-n --name)'{-n,--name}'[Nastavit zobrazovaný název pro tuto relaci]:name:'
    '--effort[Úroveň úsilí pro aktuální relaci]:level:(low medium high xhigh max)'
    '--autocompact[Velikost okna automatické komprimace (auto, nebo 100k-1M tokenů)]:size:(auto)'
    '--debug-file[Zapisovat ladicí logy do konkrétní cesty souboru (implicitně zapne režim ladění)]:path:_files'
    '--from-pr[Obnovit relaci propojenou s PR podle čísla/URL, nebo otevřít interaktivní výběr]::value:'
    '--teleport[Obnovit teleport relaci, volitelně zadat identifikátor relace]::session:'
    '--cloud[Vytvořit cloudovou relaci se zadaným popisem, nebo se připojit k existující podle identifikátoru relace nebo URL claude.ai/code]::description-or-session:'
    '--environment[Vytvořit novou cloudovou relaci, která běží v zadaném self-hosted prostředí (ccpool_...)]:environment_id:'
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
        attach|logs|stop|kill)
          _arguments \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu pro příkaz]' \
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
            '--client-id[OAuth client ID pro HTTP/SSE servery]:clientId:' \
            '--client-secret[Vyžádat zadání OAuth client secret (nebo nastavit proměnnou prostředí MCP_CLIENT_SECRET)]' \
            '--callback-port[Pevný port pro OAuth callback (pro servery vyžadující předregistrované přesměrovací URI)]:port:' \
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
            '--client-secret[Vyžádat zadání OAuth client secret (nebo nastavit proměnnou prostředí MCP_CLIENT_SECRET)]' \
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
        login)
          _arguments \
            '--no-browser[Vypsat autorizační URL místo otevření prohlížeče (pro SSH/headless relace)]' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:name:_claude_mcp_servers'
          ;;
        logout)
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
    'configure:Zobrazit možnosti pluginu a které z nich nejsou nastaveny, nebo uložit hodnoty ze stdin'
    'install:Nainstalovat plugin z dostupných marketplace'
    'i:Nainstalovat plugin z dostupných marketplace (zkratka pro install)'
    'init:Vytvořit kostru nového pluginu (automaticky se načte při další relaci)'
    'new:Vytvořit kostru nového pluginu (alias pro init)'
    'uninstall:Odinstalovat nainstalovaný plugin'
    'remove:Odinstalovat nainstalovaný plugin (alias pro uninstall)'
    'enable:Povolit zakázaný plugin'
    'disable:Zakázat povolený plugin'
    'update:Aktualizovat plugin na nejnovější verzi'
    'eval:Spustit evaluační případy proti pluginu a nahlásit obodované výsledky'
    'prune:Odstranit automaticky nainstalované závislosti, které již nejsou potřeba'
    'autoremove:Odstranit automaticky nainstalované závislosti, které již nejsou potřeba (alias pro prune)'
    'tag:Vytvořit git tag {name}--v{version} pro vydání pluginu'
    'test:Spustit testy modu'
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
            '--strict[Považovat varování za chyby (exit kód 1)]' \
            '--json[Vypsat validační zprávu jako JSON (stejné exit kódy)]' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Rozsah instalace]:scope:(user project local)' \
            '*--config[Nastavit možnost userConfig deklarovanou v manifestu pluginu (lze opakovat)]:key=value:' \
            '(-y --yes)'{-y,--yes}'[Přijmout zobrazený příkaz deklarovaný marketplace bez potvrzovací výzvy]' \
            '--json[Vypsat jeden strojově čitelný řádek s výsledkem místo zprávy pro člověka]' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Rozsah instalace]:scope:(user project local)' \
            '--keep-data[Zachovat adresář trvalých dat pluginu]' \
            '--prune[Odstranit také automaticky nainstalované závislosti, které již nejsou potřeba]' \
            '(-y --yes)'{-y,--yes}'[Přeskočit potvrzovací výzvu --prune]' \
            '--json[Vypsat jeden strojově čitelný řádek s výsledkem místo zprávy pro člověka (ne s --prune)]' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Rozsah instalace]:scope:(user project local)' \
            '--json[Vypsat jeden strojově čitelný řádek s výsledkem místo zprávy pro člověka]' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        disable)
          _arguments \
            '(-a --all)'{-a,--all}'[Zakázat všechny povolené pluginy]' \
            '(-s --scope)'{-s,--scope}'[Rozsah instalace]:scope:(user project local)' \
            '--json[Vypsat jeden strojově čitelný řádek s výsledkem místo zprávy pro člověka]' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '::plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Rozsah instalace]:scope:(user project local managed)' \
            '(-y --yes)'{-y,--yes}'[Přijmout zobrazený příkaz deklarovaný marketplace bez potvrzovací výzvy]' \
            '--json[Vypsat jeden strojově čitelný řádek s výsledkem místo zprávy pro člověka]' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list)
          _arguments \
            '--json[Výstup jako JSON]' \
            '--available[Zahrnout dostupné pluginy z marketplace (vyžaduje --json)]' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]'
          ;;
        prune|autoremove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Pročistit v rozsahu]:scope:(user project local)' \
            '--dry-run[Vypsat, co by bylo odstraněno, bez odstranění]' \
            '(-y --yes)'{-y,--yes}'[Přeskočit potvrzovací výzvu]' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]'
          ;;
        configure)
          _arguments \
            '--json[Výstup jako JSON]' \
            '--values-stdin[Načíst hodnoty možností ze stdin jako JSON objekt jednořádkových řetězců; vynechané možnosti si ponechají své hodnoty]' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init|new)
          _arguments \
            '--description[Popis v manifestu]:text:' \
            '--author[Jméno autora (výchozí: git config user.name)]:name:' \
            '--author-email[E-mail autora (výchozí: git config user.email)]:email:' \
            '--with[Komponenty, pro které se má také vytvořit kostra]:components:' \
            '(-f --force)'{-f,--force}'[Přepsat existující .claude-plugin/ v cíli]' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '--case[Filtrovat případy podle glob vzoru názvu]:glob:' \
            '*--tag[Filtrovat případy podle tagu (lze opakovat)]:tag:' \
            '--runs[Přepsat počet běhů na případ (výchozí: case.runs, jinak 3)]:n:' \
            '(-j --concurrency)'{-j,--concurrency}'[Spustit až n běhů agenta současně (1-8; výchozí 1)]:n:' \
            '--model[Přepsat model pro všechny případy]:model:_claude_model_names' \
            '--judge-model[Přepsat model LLM hodnotitele (výchozí: haiku)]:model:_claude_model_names' \
            '--max-cost-usd[Pevný limit nákladů; při jeho dosažení přerušit a nahlásit částečné výsledky (exit kód 2)]:usd:' \
            '--output-dir[Adresář pro aggregate-result.json]:dir:_directories' \
            '--eval-dir[Název adresáře (pod pluginem), který obsahuje evaluační případy]:dir:' \
            '--json[Vypsat úplný výsledek běhu jako JSON na stdout, nebo ho zapsat do tohoto .json souboru]::path:_files' \
            '--threshold[Ukončit s exit kódem 1, pokud je skóre některého případu pod tímto prahem (výchozí: 1.0)]:threshold:' \
            '*--allow-tools[Oprávnění udělené operátorem pro chráněné nástroje (Bash, Write, Edit, WebFetch, mcp__*)]:tools:' \
            '(--no-scaffold)--scaffold[Spustit scaffold_script každého případu (spouští bash dodaný autorem pod vaším účtem; ve výchozím stavu vypnuto)]' \
            '(--scaffold)--no-scaffold[Výslovně přeskočit scaffold_script]' \
            '--trust-plugin[Potvrdit, že tomuto pluginu a jeho evaluační sadě důvěřujete, a přeskočit výzvu k důvěře při prvním spuštění (pro CI)]' \
            '--ablation[Spustit srovnávací kontrolní skupinu bez pluginu a nahlásit rozdíl skóre]:mode:(none with-without)' \
            '--mocks[Mock náhrady za MCP servery, z <eval dir>/mocks/]:mode:(record off)' \
            '--allow-real-servers[S --mocks record: spustit také skutečné procesy MCP serverů, které nemají mock]' \
            '--keep-temp[Zachovat adresáře kostry pro ladění]' \
            '--verbose[Zapisovat události trasování jednotlivých zpráv do ladicího logu]' \
            '--report[Zapsat samostatnou HTML zprávu do této cesty místo adresáře s výsledky]:path:_files' \
            '(--no-publish)--publish-report[Vyžadovat také publikování zprávy na claude.ai]' \
            '(--publish-report)--no-publish[Ponechat HTML zprávu pouze lokálně; přeskočit její publikování na claude.ai]' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '::target: _alternative "plugins\:installed plugin\:_claude_installed_plugins" "files\:path\:_files"'
          ;;
        tag)
          _arguments \
            '--push[Po vytvoření odeslat tag do --remote]' \
            '--dry-run[Vypsat, co by bylo otagováno, bez vytvoření tagu]' \
            '(-f --force)'{-f,--force}'[Přeskočit kontroly nečistého pracovního stromu a již existujícího tagu]' \
            '(-m --message)'{-m,--message}'[Zpráva anotace tagu (použijte %s pro verzi)]:msg:' \
            '--remote[Remote, kam odeslat s --push]:name:' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '::path:_files'
          ;;
        test)
          _arguments \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '::dir:_directories'
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
            '--sparse[Omezit checkout na konkrétní adresáře pomocí git sparse-checkout (pro monorepa)]:paths:' \
            '--scope[Kde deklarovat marketplace]:scope:(user project local)' \
            '--claudeai[Přidat marketplace s tímto názvem, který pro vás hostuje claude.ai]' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '--json[Výstup jako JSON]' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu]'
          ;;
        remove|rm)
          _arguments \
            '--scope[Odstranit deklaraci marketplace z konkrétního rozsahu nastavení (vynechejte pro odstranění ze všech rozsahů)]:scope:(user project local)' \
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
    '--restricted[Spouštět odeslané relace v omezeném režimu]' \
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
        login)
          _arguments \
            '--email[Předvyplnit e-mailovou adresu na přihlašovací stránce]:email:' \
            '--sso[Vynutit přihlášení přes SSO]' \
            '(--claudeai)--console[Použít Anthropic Console (účtování podle využití API) místo předplatného Claude]' \
            '(--console)--claudeai[Použít předplatné Claude (výchozí)]' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu pro příkaz]'
          ;;
        status)
          _arguments \
            '(--text)--json[Výstup jako JSON (výchozí)]' \
            '(--json)--text[Výstup jako text čitelný pro člověka]' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu pro příkaz]'
          ;;
        logout)
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
        critique)
          _arguments \
            '--model[Přepsat použitý model]:model:_claude_model_names' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu pro příkaz]'
          ;;
        defaults)
          _arguments \
            '--label[Zobrazit pouze pravidla, jejichž popisek začíná touto předponou (bez rozlišení velikosti písmen)]:prefix:' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu pro příkaz]'
          ;;
        reset)
          _arguments \
            '(-y --yes)'{-y,--yes}'[Přeskočit potvrzovací výzvu]' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu pro příkaz]'
          ;;
        config)
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
            '--dry-run[Vypsat, co by bylo smazáno, bez mazání čehokoli]' \
            '(-y --yes)'{-y,--yes}'[Přeskočit potvrzovací výzvu]' \
            '(-i --interactive)'{-i,--interactive}'[Před smazáním se u každé položky zeptat]' \
            '(1)--all[Smazat stav pro všechny projekty (vzájemně se vylučuje s cestou)]' \
            '(-h --help)'{-h,--help}'[Zobrazit nápovědu pro příkaz]' \
            '(--all)::path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Vypsat surová data bugs.json místo formátovaných zjištění]' \
    '--timeout[Maximální počet minut čekání na dokončení revize (výchozí: 45)]:minutes:' \
    '(--no-post)--post[Zveřejnit zjištění z dokončené revize do PR pod vaším účtem (pouze cíle typu PR; jeden prostý komentář, ne revize)]' \
    '(--post)--no-post[Nezveřejňovat zjištění do PR (výchozí)]' \
    '(-h --help)'{-h,--help}'[Zobrazit nápovědu pro příkaz]' \
    '1:target:'
}

_claude_respawn() {
  _arguments \
    '(1)--all[Restartovat všechny běžící relace na pozadí]' \
    '(-h --help)'{-h,--help}'[Zobrazit nápovědu pro příkaz]' \
    '(--all)::session:_claude_background_sessions'
}

_claude_rm() {
  _arguments \
    '--discard-unpushed[Zahodit také neodeslané commity a necommitnuté změny worktree (předejte commit@worktree-id, které nahlásil předchozí claude rm)]:commit@worktree-id:' \
    '--force-remove-worktree[Smazat adresář worktree, i když ho hook WorktreeRemove nebo git nedokázal odstranit (předejte worktree-id, které nahlásil předchozí claude rm)]:worktree-id:' \
    '(-h --help)'{-h,--help}'[Zobrazit nápovědu pro příkaz]' \
    '1:session:_claude_background_sessions'
}

_claude_import() {
  _arguments \
    '--dry-run[Zobrazit, co by bylo importováno, bez zápisu čehokoli]' \
    '--yes[Přeskočit interaktivní výběr (na headless rozhraních předejte --yes=<digest> z náhledu /import)]' \
    '(-h --help)'{-h,--help}'[Zobrazit nápovědu pro příkaz]' \
    '::source:(codex gemini cursor)'
}

(( $+_comps[claude] )) || compdef _claude claude
