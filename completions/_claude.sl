#compdef claude
# Dinamične funkcije samodejnega dopolnjevanja
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
    'mcp:Konfiguracija in upravljanje MCP strežnikov'
    'plugin:Upravljanje vtičnikov Claude Code'
    'setup-token:Nastavitev žetona za dolgotrajno avtentikacijo (zahteva naročnino Claude)'
    'doctor:Preverjanje zdravja sistema samodejnih posodobitev Claude Code'
    'update:Preverjanje in namestitev posodobitev'
    'install:Namestitev izvorne različice Claude Code'
  )
  local -a main_options
  main_options=(
    '(-d --debug)'{-d,--debug}'[Vklop načina odpravljanja napak z izbirnim filtriranjem kategorij (npr. "api,hooks" ali "!statsig,!file")]:filter:'
    '--verbose[Preglasi nastavitev podrobnega načina iz konfiguracijske datoteke]'
    '(-p --print)'{-p,--print}'[Izpiši odgovor in izhod (za uporabo s pipe). Opomba: uporabljajte samo v zaupanja vrednih imenikih]'
    '--output-format[Format izpisa (z --print): "text" (privzeto), "json" (en rezultat), ali "stream-json" (pretočno oddajanje v realnem času)]:format:(text json stream-json)'
    '--json-schema[JSON shema za validacijo strukturiranega izpisa]:schema:'
    '--include-partial-messages[Vključi delne fragmente sporočil ob njihovem prihodu (z --print in --output-format=stream-json)]'
    '--input-format[Format vnosa (z --print): "text" (privzeto) ali "stream-json" (pretočni vnos v realnem času)]:format:(text stream-json)'
    '--mcp-debug[\[Zastarelo. Uporabite --debug namesto tega\] Vklop načina odpravljanja napak MCP (prikazuje napake MCP strežnika)]'
    '--dangerously-skip-permissions[Obid vseh preverjanj dovoljenj. Priporočljivo samo za peskovnike brez dostopa do interneta]'
    '--allow-dangerously-skip-permissions[Omogoči možnost obida preverjanj dovoljenj brez omogočanja privzeto]'
    '--replay-user-messages[Ponovno pošlji uporabniška sporočila iz stdin na stdout za potrditev]'
    '--allowed-tools[Seznam dovoljenih imen orodij ločenih z vejico ali presledkom (npr. "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Seznam dovoljenih imen orodij ločenih z vejico ali presledkom (format camelCase)]:tools:'
    '--tools[Določi seznam razpoložljivih orodij iz vgrajene zbirke. Samo v načinu print]:tools:'
    '--disallowed-tools[Seznam prepovedanih imen orodij ločenih z vejico ali presledkom (npr. "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Seznam prepovedanih imen orodij ločenih z vejico ali presledkom (format camelCase)]:tools:'
    '--mcp-config[Naloži MCP strežnike iz JSON datoteke ali niza (ločeni s presledki)]:configs:'
    '--system-prompt[Sistemski prompt za uporabo v seji]:prompt:'
    '--append-system-prompt[Dodaj sistemski prompt standardnemu sistemskemu promptu]:prompt:'
    '--permission-mode[Način dovoljenj za uporabo v seji]:mode:(acceptEdits bypassPermissions default dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Nadaljuj zadnji pogovor]'
    '(-r --resume)'{-r,--resume}'[Obnovi pogovor - navedi identifikator seje ali izberi interaktivno]:sessionId:_claude_sessions'
    '--fork-session[Ustvari nov identifikator seje namesto ponovne uporabe izvirnega pri obnovi (z --resume ali --continue)]'
    '--model[Model za trenutno sejo. Navedi vzdevek za najnovejši model (npr. '\''sonnet'\'' ali '\''opus'\'')]:model:'
    '--fallback-model[Omogoči samodejno preklop na navedeni model ko je privzeti model preobremenjen (samo --print)]:model:'
    '--settings[Pot do JSON datoteke z nastavitvami ali JSON niz za nalaganje dodatnih nastavitev]:file-or-json:_files'
    '--add-dir[Dodatni imeniki za zagotavljanje dostopa orodjem]:directories:_directories'
    '--ide[Samodejno se poveži z IDE ob zagonu če je na voljo točno en veljaven IDE]'
    '--strict-mcp-config[Uporabi samo MCP strežnike iz --mcp-config in prezri vse druge MCP nastavitve]'
    '--session-id[Določen identifikator seje za uporabo v pogovoru (mora biti veljaven UUID)]:uuid:'
    '--agents[JSON objekt, ki definira oblikovane agente]:json:'
    '--setting-sources[Seznam virov nastavitev ločenih z vejico za nalaganje (user, project, local)]:sources:'
    '--plugin-dir[Imenik za nalaganje vtičnikov samo za to sejo (lahko se ponovi)]:paths:_directories'
    '(-v --version)'{-v,--version}'[Izpiši številko različice]'
    '(-h --help)'{-h,--help}'[Prikaži pomoč za ukaz]'
  )
  _arguments -C \
    $main_options \
    '1: :->command' \
    '*::arg:->args'
  case $state in
    command)
      _describe -t commands 'ukazi claude' main_commands
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
          _message "brez argumentov"
          ;;
      esac
      ;;
  esac
}
_claude_mcp() {
  local -a mcp_commands
  mcp_commands=(
    'serve:Zaženi MCP strežnik Claude Code'
    'add:Dodaj MCP strežnik v Claude Code'
    'remove:Odstrani MCP strežnik'
    'list:Prikaži seznam konfiguriranih MCP strežnikov'
    'get:Pridobi podrobnosti MCP strežnika'
    'add-json:Dodaj MCP strežnik (stdio ali SSE) z JSON nizom'
    'add-from-claude-desktop:Uvozi MCP strežnike iz Claude Desktop (samo Mac in WSL)'
    'reset-project-choices:Ponastavi vse odobrene/zavrnjene strežnike z obsegom projekta (.mcp.json) v tem projektu'
    'help:Prikaži pomoč'
  )
  local curcontext="$curcontext" state line
  typeset -A opt_args
  _arguments -C \
    '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
    '1: :->command' \
    '*::arg:->args'
  case $state in
    command)
      _describe -t commands 'ukazi mcp' mcp_commands
      ;;
    args)
      case $words[1] in
        serve)
          _arguments \
            '(-d --debug)'{-d,--debug}'[Vklop načina odpravljanja napak]' \
            '--verbose[Preglasi nastavitev podrobnega načina iz konfiguracijske datoteke]' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]'
          ;;
        add)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Obseg konfiguracije (local, user, project)]:scope:(local user project)' \
            '(-t --transport)'{-t,--transport}'[Vrsta prenosa (stdio, sse, http)]:transport:(stdio sse http)' \
            '(-e --env)'{-e,--env}'[Nastavi spremenljivko okolja (npr. -e KEY=value)]:env:' \
            '(-H --header)'{-H,--header}'[Nastavi WebSocket glavo]:header:' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:name:' \
            '2:commandOrUrl:' \
            '*:args:'
          ;;
        remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Obseg konfiguracije (local, user, project) - odstrani iz obstoječega obsega če ni navedeno]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:name:_claude_mcp_servers'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]'
          ;;
        get)
          _arguments \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:name:_claude_mcp_servers'
          ;;
        add-json)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Obseg konfiguracije (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:name:' \
            '2:json:'
          ;;
        add-from-claude-desktop)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Obseg konfiguracije (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]'
          ;;
        reset-project-choices)
          _arguments \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]'
          ;;
      esac
      ;;
  esac
}
_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:Validiraj vtičnik ali manifest tržnice'
    'marketplace:Upravljanje tržnic Claude Code'
    'install:Namesti vtičnik iz razpoložljivih tržnic'
    'i:Namesti vtičnik iz razpoložljivih tržnic (okrajšava za install)'
    'uninstall:Odstrani nameščen vtičnik'
    'remove:Odstrani nameščen vtičnik (vzdevek za uninstall)'
    'enable:Omogoči onemogočen vtičnik'
    'disable:Onemogoči omogočen vtičnik'
    'help:Prikaži pomoč'
  )
  local curcontext="$curcontext" state line
  typeset -A opt_args
  _arguments -C \
    '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
    '1: :->command' \
    '*::arg:->args'
  case $state in
    command)
      _describe -t commands 'ukazi plugin' plugin_commands
      ;;
    args)
      case $words[1] in
        validate)
          _arguments \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:plugin:_claude_installed_plugins'
          ;;
      esac
      ;;
  esac
}
_claude_plugin_marketplace() {
  local -a marketplace_commands
  marketplace_commands=(
    'add:Dodaj tržnico iz URL, poti ali GitHub repozitorija'
    'list:Prikaži seznam konfiguriranih tržnic'
    'remove:Odstrani konfigurirano tržnico'
    'rm:Odstrani konfigurirano tržnico (vzdevek za remove)'
    'update:Posodobi tržnico iz vira - posodobi vse če ime ni navedeno'
    'help:Prikaži pomoč'
  )
  local curcontext="$curcontext" state line
  typeset -A opt_args
  _arguments -C \
    '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
    '1: :->command' \
    '*::arg:->args'
  case $state in
    command)
      _describe -t commands 'ukazi marketplace' marketplace_commands
      ;;
    args)
      case $words[1] in
        add)
          _arguments \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]'
          ;;
        remove|rm)
          _arguments \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:name:'
          ;;
        update)
          _arguments \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '::name:'
          ;;
      esac
      ;;
  esac
}
_claude_install() {
  _arguments \
    '--force[Prisili namestitev tudi če je že nameščeno]' \
    '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
    '::target:(stable latest)'
}
(( $+_comps[claude] )) || compdef _claude claude
