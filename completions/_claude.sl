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
    'mcp:Konfiguracija in upravljanje MCP strežnikov'
    'plugin:Upravljanje vtičnikov Claude Code'
    'agents:Upravljanje agentov v ozadju'
    'auth:Upravljanje avtentikacije'
    'auto-mode:Preglej ali ponastavi konfiguracijo klasifikatorja samodejnega načina'
    'gateway:Zaženi prehod za podjetniško avtentikacijo/telemetrijo'
    'project:Upravljanje stanja projekta Claude Code'
    'ultrareview:Zaženi večagentni pregled kode v oblaku in izpiši ugotovitve'
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
    '--max-budget-usd[Največji dolarski znesek za porabo pri klicih API (samo --print)]:amount:'
    '--replay-user-messages[Ponovno pošlji uporabniška sporočila iz stdin na stdout za potrditev]'
    '--allowed-tools[Seznam dovoljenih imen orodij ločenih z vejico ali presledkom (npr. "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Seznam dovoljenih imen orodij ločenih z vejico ali presledkom (format camelCase)]:tools:'
    '--tools[Določi seznam razpoložljivih orodij iz vgrajene zbirke. Samo v načinu print]:tools:'
    '--disallowed-tools[Seznam prepovedanih imen orodij ločenih z vejico ali presledkom (npr. "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Seznam prepovedanih imen orodij ločenih z vejico ali presledkom (format camelCase)]:tools:'
    '--mcp-config[Naloži MCP strežnike iz JSON datoteke ali niza (ločeni s presledki)]:configs:'
    '--system-prompt[Sistemski prompt za uporabo v seji]:prompt:'
    '--append-system-prompt[Dodaj sistemski prompt standardnemu sistemskemu promptu]:prompt:'
    '--permission-mode[Način dovoljenj za uporabo v seji]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Nadaljuj zadnji pogovor]'
    '(-r --resume)'{-r,--resume}'[Obnovi pogovor - navedi identifikator seje ali izberi interaktivno]:sessionId:_claude_sessions'
    '--fork-session[Ustvari nov identifikator seje namesto ponovne uporabe izvirnega pri obnovi (z --resume ali --continue)]'
    '--no-session-persistence[Onemogoči ohranjanje seje - seje ne bodo shranjene (samo --print)]'
    '--model[Model za trenutno sejo. Navedi vzdevek za najnovejši model (npr. '\''sonnet'\'' ali '\''opus'\'')]:model:'
    '--agent[Agent za trenutno sejo. Preglasi nastavitev '\''agent'\'']:agent:'
    '--betas[Beta glave za vključitev v zahteve API (samo uporabniki s ključem API)]:betas:'
    '--fallback-model[Omogoči samodejno preklop na navedeni model ko je privzeti model preobremenjen (samo --print)]:model:'
    '--settings[Pot do JSON datoteke z nastavitvami ali JSON niz za nalaganje dodatnih nastavitev]:file-or-json:_files'
    '--add-dir[Dodatni imeniki za zagotavljanje dostopa orodjem]:directories:_directories'
    '--ide[Samodejno se poveži z IDE ob zagonu če je na voljo točno en veljaven IDE]'
    '--strict-mcp-config[Uporabi samo MCP strežnike iz --mcp-config in prezri vse druge MCP nastavitve]'
    '--session-id[Določen identifikator seje za uporabo v pogovoru (mora biti veljaven UUID)]:uuid:'
    '--agents[JSON objekt, ki definira oblikovane agente]:json:'
    '--setting-sources[Seznam virov nastavitev ločenih z vejico za nalaganje (user, project, local)]:sources:'
    '--plugin-dir[Imenik za nalaganje vtičnikov samo za to sejo (lahko se ponovi)]:paths:_directories'
    '--disable-slash-commands[Onemogoči vse poševne ukaze]'
    '(--bg --background)'{--bg,--background}'[Zaženi sejo kot agenta v ozadju in se takoj vrni]'
    '(-w --worktree)'{-w,--worktree}'[Ustvari novo git delovno drevo za to sejo (izbirno navedi ime)]::name:'
    '--tmux[Ustvari sejo tmux za delovno drevo (zahteva --worktree)]'
    '(-n --name)'{-n,--name}'[Nastavi prikazno ime za to sejo]:name:'
    '--effort[Raven napora za trenutno sejo]:level:(low medium high xhigh max)'
    '--debug-file[Zapiši dnevnike odpravljanja napak na določeno pot datoteke (implicitno vklopi način odpravljanja napak)]:path:_files'
    '--from-pr[Obnovi sejo, povezano s PR po številki/URL, ali odpri interaktivni izbirnik]::value:'
    '--remote-control[Zaženi interaktivno sejo z omogočenim daljinskim upravljanjem (izbirno poimenovano)]::name:'
    '--remote-control-session-name-prefix[Predpona za samodejno ustvarjena imena sej daljinskega upravljanja]:prefix:'
    '--chrome[Omogoči integracijo Claude v Chrome]'
    '--no-chrome[Onemogoči integracijo Claude v Chrome]'
    '--plugin-url[Pridobi .zip vtičnika z URL samo za to sejo (lahko se ponovi)]:url:'
    '--file[Datotečni viri za prenos ob zagonu (format: file_id:relative_path)]:specs:'
    '--prompt-suggestions[Omogoči predloge promptov (odda predviden naslednji prompt v načinu print/SDK)]::value:(true false 1 0 yes no on off)'
    '--forward-subagent-text[Posreduj besedilo podagenta in bloke razmišljanja kot sporočila (z --print in stream-json)]'
    '--include-hook-events[Vključi vse dogodke življenjskega cikla kljuk v izhodni tok (s stream-json)]'
    '--exclude-dynamic-system-prompt-sections[Premakni odseke za posamezno napravo v prvo uporabniško sporočilo za izboljšanje ponovne uporabe predpomnilnika promptov]'
    '--brief[Omogoči orodje SendUserMessage za komunikacijo agent-uporabnik]'
    '--safe-mode[Zaženi z onemogočenimi vsemi prilagoditvami (uporabno za odpravljanje težav s pokvarjeno konfiguracijo)]'
    '--bare[Minimalni način: preskoči kljuke, LSP, sinhronizacijo vtičnikov, pripisovanje, samodejni pomnilnik in samodejno odkrivanje CLAUDE.md]'
    '--ax-screen-reader[Prikaži izpis prijazen bralnikom zaslona (ravno besedilo, brez okrasnih obrob ali animacij)]'
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
    'login:Avtenticiraj se z MCP strežnikom (HTTP, SSE ali claude.ai konektor)'
    'logout:Počisti shranjene poverilnice OAuth za MCP strežnik'
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
        login|logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:name:_claude_mcp_servers'
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
    'list:Prikaži seznam nameščenih vtičnikov'
    'details:Prikaži inventar komponent in predvideni strošek žetonov za vtičnik'
    'install:Namesti vtičnik iz razpoložljivih tržnic'
    'i:Namesti vtičnik iz razpoložljivih tržnic (okrajšava za install)'
    'init:Ustvari ogrodje novega vtičnika (samodejno se naloži v naslednji seji)'
    'uninstall:Odstrani nameščen vtičnik'
    'remove:Odstrani nameščen vtičnik (vzdevek za uninstall)'
    'enable:Omogoči onemogočen vtičnik'
    'disable:Onemogoči omogočen vtičnik'
    'update:Posodobi vtičnik na najnovejšo različico'
    'eval:Zaženi primere ocenjevanja proti vtičniku in poročaj ocenjene rezultate'
    'prune:Odstrani samodejno nameščene odvisnosti, ki niso več potrebne'
    'tag:Ustvari git oznako {name}--v{version} za izdajo vtičnika'
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
            '(-s --scope)'{-s,--scope}'[Obseg namestitve]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Obseg namestitve]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Obseg namestitve]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Obseg namestitve]:scope:(user project local managed)' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list|prune)
          _arguments \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init)
          _arguments \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:target:'
          ;;
        tag)
          _arguments \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:path:_files'
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

_claude_agents() {
  _arguments \
    '*--add-dir[Dodatni imenik za dostop orodij v razporejenih sejah]:directory:_directories' \
    '--agent[Privzeti agent za seje, razporejene iz pogleda agentov]:agent:' \
    '--all[Z --json: vključi tudi dokončane seje v ozadju]' \
    '--allow-dangerously-skip-permissions[Omogoči način obida dovoljenj razporejenim sejam]' \
    '--cwd[Prikaži samo seje v ozadju, zagnane pod potjo]:path:_directories' \
    '--dangerously-skip-permissions[Vzdevek za --permission-mode bypassPermissions]' \
    '--effort[Privzeta raven napora za razporejene seje]:level:(low medium high xhigh max)' \
    '--json[Izpiši aktivne seje kot JSON polje in izhod]' \
    '*--mcp-config[Konfiguracija MCP strežnika za uporabo v razporejenih sejah]:config:' \
    '--model[Privzeti model za seje, razporejene iz pogleda agentov]:model:' \
    '--permission-mode[Privzeti način dovoljenj za razporejene seje]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Naloži vtičnike iz imenika za pogled agentov in razporejene seje]:path:_directories' \
    '--setting-sources[Seznam virov nastavitev ločenih z vejico za nalaganje (user, project, local)]:sources:' \
    '--settings[Datoteka z nastavitvami ali JSON niz za uporabo]:file-or-json:_files' \
    '--strict-mcp-config[Uporabi samo MCP strežnike iz --mcp-config v razporejenih sejah]' \
    '(-h --help)'{-h,--help}'[Prikaži pomoč za ukaz]'
}

_claude_auth() {
  local -a auth_commands
  auth_commands=(
    'login:Prijava v vaš račun Anthropic'
    'logout:Odjava iz vašega računa Anthropic'
    'status:Prikaži stanje avtentikacije'
    'help:Prikaži pomoč'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Prikaži pomoč za ukaz]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'ukazi auth' auth_commands
      ;;
    args)
      case $words[1] in
        login|logout|status)
          _arguments \
            '(-h --help)'{-h,--help}'[Prikaži pomoč za ukaz]'
          ;;
      esac
      ;;
  esac
}

_claude_auto_mode() {
  local -a auto_mode_commands
  auto_mode_commands=(
    'config:Izpiši veljavno konfiguracijo samodejnega načina kot JSON'
    'critique:Pridobi povratne informacije UI o vaših prilagojenih pravilih samodejnega načina'
    'defaults:Izpiši privzeta pravila samodejnega načina kot JSON'
    'reset:Ponastavi konfiguracijo samodejnega načina na priložene privzete vrednosti'
    'help:Prikaži pomoč'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Prikaži pomoč za ukaz]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'ukazi auto-mode' auto_mode_commands
      ;;
    args)
      case $words[1] in
        config|critique|defaults|reset)
          _arguments \
            '(-h --help)'{-h,--help}'[Prikaži pomoč za ukaz]'
          ;;
      esac
      ;;
  esac
}

_claude_gateway() {
  _arguments \
    '--config[Pot do YAML konfiguracije prehoda]:path:_files' \
    '(-h --help)'{-h,--help}'[Prikaži pomoč za ukaz]'
}

_claude_project() {
  local -a project_commands
  project_commands=(
    'purge:Izbriši vse stanje Claude Code za projekt (prepisi, opravila, zgodovina datotek, konfiguracijski vnos)'
    'help:Prikaži pomoč'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Prikaži pomoč za ukaz]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'ukazi project' project_commands
      ;;
    args)
      case $words[1] in
        purge)
          _arguments \
            '(-h --help)'{-h,--help}'[Prikaži pomoč za ukaz]' \
            '1:path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Izpiši surovo vsebino bugs.json namesto oblikovanih ugotovitev]' \
    '--timeout[Največ minut za čakanje na dokončanje pregleda]:minutes:' \
    '(-h --help)'{-h,--help}'[Prikaži pomoč za ukaz]' \
    '1:target:'
}

(( $+_comps[claude] )) || compdef _claude claude
