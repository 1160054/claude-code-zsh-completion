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
    'mcp:Konfiguracija in upravljanje MCP strežnikov'
    'plugin:Upravljanje vtičnikov Claude Code'
    'agents:Upravljanje agentov v ozadju'
    'attach:Odpri sejo v ozadju v tem terminalu'
    'logs:Izpiši nedavni izpis terminala seje v ozadju'
    'stop:Ustavi sejo v ozadju (njen pogovor se ohrani)'
    'respawn:Znova zaženi sejo v ozadju, da bo tekla na trenutni različici Claude Code'
    'rm:Izbriši sejo v ozadju in njeno delovno drevo, kadar je to varno'
    'remote-control:Upravljaj lokalne seje iz claude.ai/code ali mobilne aplikacije Claude'
    'daemon:Upravljanje nadzornika sej v ozadju'
    'auth:Upravljanje avtentikacije'
    'auto-mode:Preglej ali ponastavi konfiguracijo klasifikatorja samodejnega načina'
    'gateway:Zaženi prehod za podjetniško avtentikacijo/telemetrijo'
    'self-hosted-runner:Gosti oblačne seje Claude Code na tem računalniku ali vsebniku'
    'import:Uvozi konfiguracijo iz drugega agenta UI za programiranje v Claude Code'
    'project:Upravljanje stanja projekta Claude Code'
    'purge:Izbriši vse stanje Claude Code za projekt (prepisi, opravila, zgodovina datotek, konfiguracijski vnos)'
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
    '--dangerously-skip-permissions[Obid vseh preverjanj dovoljenj. Priporočljivo samo za peskovnike brez dostopa do interneta]'
    '--allow-dangerously-skip-permissions[Omogoči možnost obida preverjanj dovoljenj brez omogočanja privzeto]'
    '--restricted[Omejeni način: odstrani orodja, ki izvajajo ukaze ali kodo, in WebFetch, prezri nastavitve user/project/local ter omeji datotečna orodja na delovne imenike]'
    '--max-budget-usd[Največji dolarski znesek za porabo pri klicih API (samo --print)]:amount:'
    '--max-turns[Omeji število agentnih korakov (samo --print)]:turns:'
    '--replay-user-messages[Ponovno pošlji uporabniška sporočila iz stdin na stdout za potrditev]'
    '--allowed-tools[Seznam dovoljenih imen orodij ločenih z vejico ali presledkom (npr. "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Seznam dovoljenih imen orodij ločenih z vejico ali presledkom (format camelCase)]:tools:'
    '--tools[Določi seznam razpoložljivih orodij iz vgrajene zbirke. Samo v načinu print]:tools:'
    '--disallowed-tools[Seznam prepovedanih imen orodij ločenih z vejico ali presledkom (npr. "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Seznam prepovedanih imen orodij ločenih z vejico ali presledkom (format camelCase)]:tools:'
    '--mcp-config[Naloži MCP strežnike iz JSON datoteke ali niza (ločeni s presledki)]:configs:'
    '--system-prompt[Sistemski prompt za uporabo v seji]:prompt:'
    '--system-prompt-file[Preberi sistemski prompt iz datoteke]:file:_files'
    '--append-system-prompt[Dodaj sistemski prompt standardnemu sistemskemu promptu]:prompt:'
    '--append-system-prompt-file[Preberi sistemski prompt iz datoteke in ga dodaj privzetemu sistemskemu promptu]:file:_files'
    '(--append-subagent-system-prompt-file)--append-subagent-system-prompt[Dodaj besedilo sistemskemu pozivu vsakega podagenta (samo --print)]:prompt:'
    '(--append-subagent-system-prompt)--append-subagent-system-prompt-file[Preberi besedilo iz datoteke in ga dodaj sistemskim pozivom podagentov (samo --print)]:file:_files'
    '--system-prompt-snapshot[Zapiši sistemski prompt enkrat na pogovor in ga dobesedno ponovno uporabi pri vsaki zahtevi in obnovi (on, privzeto) ali ga ob vsaki zahtevi sestavi na novo (off)]:mode:(on off)'
    '--permission-mode[Način dovoljenj za uporabo v seji]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '--permission-prompts[Kdo odgovarja na pozive za dovoljenja z --print: "host" (gostitelj SDK ali --permission-prompt-tool) ali "none" (vse, kar bi sprožilo poziv, je zavrnjeno)]:target:(host none)'
    '--permission-prompt-tool[Orodje MCP za pozive za dovoljenja (samo --print)]:tool:'
    '(-c --continue)'{-c,--continue}'[Nadaljuj zadnji pogovor]'
    '(-r --resume)'{-r,--resume}'[Obnovi pogovor - navedi identifikator seje ali izberi interaktivno]:sessionId:_claude_sessions'
    '--fork-session[Ustvari nov identifikator seje namesto ponovne uporabe izvirnega pri obnovi (z --resume ali --continue)]'
    '--no-session-persistence[Onemogoči ohranjanje seje - seje ne bodo shranjene (samo --print)]'
    '--model[Model za trenutno sejo. Navedi vzdevek za najnovejši model (npr. '\''sonnet'\'' ali '\''opus'\'')]:model:_claude_model_names'
    '--agent[Agent za trenutno sejo. Preglasi nastavitev '\''agent'\'']:agent:_claude_agent_names'
    '--betas[Beta glave za vključitev v zahteve API (samo uporabniki s ključem API)]:betas:'
    '--fallback-model[Omogoči samodejno preklop na navedeni model ko je privzeti model preobremenjen (samo --print)]:model:_claude_model_names'
    '--settings[Pot do JSON datoteke z nastavitvami ali JSON niz za nalaganje dodatnih nastavitev]:file-or-json:_files'
    '--add-dir[Dodatni imeniki za zagotavljanje dostopa orodjem]:directories:_directories'
    '--ide[Samodejno se poveži z IDE ob zagonu če je na voljo točno en veljaven IDE]'
    '--desktop[Odpri v aplikaciji Claude Desktop namesto v terminalu (z --continue ali --resume <id> za izbiro seje)]'
    '--strict-mcp-config[Uporabi samo MCP strežnike iz --mcp-config in prezri vse druge MCP nastavitve]'
    '--session-id[Določen identifikator seje za uporabo v pogovoru (mora biti veljaven UUID)]:uuid:'
    '--agents[JSON objekt, ki definira oblikovane agente]:json:'
    '--advisor[Omogoči strežniško orodje svetovalca za to sejo z vzdevkom modela ali polnim ID-jem modela]:model:_claude_model_names'
    '--teammate-mode[Kako so prikazani člani ekipe agentov]:mode:(in-process auto tmux iterm2)'
    '--setting-sources[Seznam virov nastavitev ločenih z vejico za nalaganje (user, project, local)]:sources:'
    '--plugin-dir[Imenik za nalaganje vtičnikov samo za to sejo (lahko se ponovi)]:paths:_directories'
    '--disable-slash-commands[Onemogoči vse poševne ukaze]'
    '(--bg --background)'{--bg,--background}'[Zaženi sejo kot agenta v ozadju in se takoj vrni]'
    '(-w --worktree)'{-w,--worktree}'[Ustvari novo git delovno drevo za to sejo (izbirno navedi ime)]::name:'
    '--tmux=-[Ustvari sejo tmux za delovno drevo (zahteva --worktree). Uporabi izvorna podokna iTerm2, kadar so na voljo; --tmux=classic za klasični tmux]::mode:(classic)'
    '(-n --name)'{-n,--name}'[Nastavi prikazno ime za to sejo]:name:'
    '--effort[Raven napora za trenutno sejo]:level:(low medium high xhigh max)'
    '--autocompact[Velikost okna za samodejno zgoščevanje (auto ali 100k-1M žetonov)]:size:(auto)'
    '--debug-file[Zapiši dnevnike odpravljanja napak na določeno pot datoteke (implicitno vklopi način odpravljanja napak)]:path:_files'
    '--from-pr[Obnovi sejo, povezano s PR po številki/URL, ali odpri interaktivni izbirnik]::value:'
    '--teleport[Obnovi teleport sejo, izbirno navedi identifikator seje]::session:'
    '(--remote)--cloud[Ustvari sejo v oblaku z navedenim opisom ali se priključi obstoječi prek identifikatorja seje ali URL claude.ai/code]::description-or-session:'
    '(--cloud)--remote[Zastarel vzdevek za --cloud]::description-or-session:'
    '--environment[Ustvari novo sejo v oblaku, ki teče v navedenem samostojno gostovanem okolju (ccpool_...)]:environment_id:'
    '--ref[Z --environment: osnuj checkout nove seje na poimenovani ref namesto na lokalnem HEAD]:branch:'
    '(--remote-control --rc)'{--remote-control,--rc}'[Zaženi interaktivno sejo z omogočenim daljinskim upravljanjem (izbirno poimenovano)]::name:'
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
    '*--channels[(Raziskovalni predogled) Strežniki MCP, katerih obvestila kanalov naj se poslušajo (plugin\:<name>@<marketplace>)]:entries:'
    '*--dangerously-load-development-channels[Omogoči kanale, ki niso na odobrenem seznamu, za lokalni razvoj (plugin\:<name>@<marketplace> ali server\:<name>)]:entries:'
    '--init[Pred sejo zaženi kljuke Setup z ujemalnikom init (samo --print)]'
    '--init-only[Zaženi kljuke Setup in SessionStart, nato končaj brez začetka pogovora]'
    '--maintenance[Pred sejo zaženi kljuke Setup z ujemalnikom maintenance (samo --print)]'
    '--safe-mode[Zaženi z onemogočenimi vsemi prilagoditvami (uporabno za odpravljanje težav s pokvarjeno konfiguracijo)]'
    '--bare[Minimalni način: preskoči kljuke, LSP, sinhronizacijo vtičnikov, pripisovanje, samodejni pomnilnik in samodejno odkrivanje CLAUDE.md]'
    '--ax-screen-reader[Prikaži izpis prijazen bralnikom zaslona (ravno besedilo, brez okrasnih obrob ali animacij)]'
    '(-v --version)'{-v,--version}'[Izpiši številko različice]'
    '(-h --help)'{-h,--help}'[Prikaži pomoč za ukaz]'
  )

  # Stop at the first non-option word, so that the options after a command reach
  # that command's own specs instead of being consumed here
  _arguments -C -A '-*' \
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
        plugin|plugins)
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
            '(-h --help)'{-h,--help}'[Prikaži pomoč za ukaz]' \
            '1:session:_claude_background_sessions'
          ;;
        respawn)
          _claude_respawn
          ;;
        rm)
          _claude_rm
          ;;
        remote-control|rc|remote|sync|bridge)
          _claude_remote_control
          ;;
        daemon)
          _claude_daemon
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
        self-hosted-runner)
          _claude_self_hosted_runner
          ;;
        import)
          _claude_import
          ;;
        project)
          _claude_project
          ;;
        purge)
          _claude_purge
          ;;
        ultrareview)
          _claude_ultrareview
          ;;
        setup-token|doctor|update|upgrade)
          _arguments \
            '(-h --help)'{-h,--help}'[Prikaži pomoč za ukaz]'
          ;;
        *)
          # Not a command but the prompt: options may still follow it
          _arguments \
            $main_options \
            '*: :'
          ;;
      esac
      ;;
  esac
  local ret=$?

  # The last step, such as listing commands for --r, can fail although options
  # were added before it. Report success then: on failure zsh moves on to the
  # next completers, and _correct or _approximate pile on corrections
  (( compstate[nmatches] > 0 )) || return $ret
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
            '--client-id[ID odjemalca OAuth za strežnike HTTP/SSE]:clientId:' \
            '--client-secret[Pozovi k vnosu skrivnosti odjemalca OAuth (ali nastavi spremenljivko okolja MCP_CLIENT_SECRET)]' \
            '--callback-port[Fiksna vrata za povratni klic OAuth (za strežnike, ki zahtevajo vnaprej registrirane URI-je za preusmeritev)]:port:' \
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
            '--client-secret[Pozovi k vnosu skrivnosti odjemalca OAuth (ali nastavi spremenljivko okolja MCP_CLIENT_SECRET)]' \
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
        login)
          _arguments \
            '--no-browser[Izpiši URL za avtorizacijo namesto odpiranja brskalnika (za seje SSH/brez grafičnega vmesnika)]' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:name:_claude_mcp_servers'
          ;;
        logout)
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
    'configure:Prikaži možnosti vtičnika in katere niso nastavljene ali shrani vrednosti iz stdin'
    'install:Namesti vtičnik iz razpoložljivih tržnic'
    'i:Namesti vtičnik iz razpoložljivih tržnic (okrajšava za install)'
    'init:Ustvari ogrodje novega vtičnika (samodejno se naloži v naslednji seji)'
    'new:Ustvari ogrodje novega vtičnika (vzdevek za init)'
    'uninstall:Odstrani nameščen vtičnik'
    'remove:Odstrani nameščen vtičnik (vzdevek za uninstall)'
    'enable:Omogoči onemogočen vtičnik'
    'disable:Onemogoči omogočen vtičnik'
    'update:Posodobi vtičnik na najnovejšo različico'
    'eval:Zaženi primere ocenjevanja proti vtičniku in poročaj ocenjene rezultate'
    'prune:Odstrani samodejno nameščene odvisnosti, ki niso več potrebne'
    'autoremove:Odstrani samodejno nameščene odvisnosti, ki niso več potrebne (vzdevek za prune)'
    'tag:Ustvari git oznako {name}--v{version} za izdajo vtičnika'
    'test:Zaženi teste moda'
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
            '--strict[Obravnavaj opozorila kot napake (izhodna koda 1)]' \
            '--profile[Končaj z 1 tudi, ko bi poimenovani katalog zavrnil oddajo vtičnika pri preverjanju, ki ga izvede ta ukaz]:name:(directory)' \
            '--json[Izpiši poročilo o validaciji kot JSON (enake izhodne kode)]' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Obseg namestitve]:scope:(user project local)' \
            '--accept-command[Sprejmi ukaz, ki ga deklarira tržnica in katerega sha256 je prejšnji zagon z --json sporočil kot shownCommand.sha256]:sha256:' \
            '*--config[Nastavi možnost userConfig, deklarirano v manifestu vtičnika (lahko se ponovi)]:key=value:' \
            '--marketplace[Namesti vtičnik po golem imenu iz tržnice na tem viru (owner/repo, URL git ali https ali pot), po potrebi jo najprej dodaj]:source:' \
            '--registry[Za namestitev package@npm: razreši in prenesi iz tega registra npm]:url:' \
            '(-y --yes)'{-y,--yes}'[Sprejmi prikazani ukaz, ki ga deklarira tržnica, brez potrditvenega poziva]' \
            '--json[Izpiši eno strojno berljivo vrstico rezultata namesto sporočila za ljudi]' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Obseg namestitve]:scope:(user project local)' \
            '--keep-data[Ohrani imenik trajnih podatkov vtičnika]' \
            '--prune[Odstrani tudi samodejno nameščene odvisnosti, ki niso več potrebne]' \
            '(-y --yes)'{-y,--yes}'[Preskoči potrditveni poziv za --prune]' \
            '--json[Izpiši eno strojno berljivo vrstico rezultata namesto sporočila za ljudi (ne z --prune)]' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Obseg namestitve]:scope:(user project local)' \
            '--json[Izpiši eno strojno berljivo vrstico rezultata namesto sporočila za ljudi]' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        disable)
          _arguments \
            '(-a --all)'{-a,--all}'[Onemogoči vse omogočene vtičnike]' \
            '(-s --scope)'{-s,--scope}'[Obseg namestitve]:scope:(user project local)' \
            '--json[Izpiši eno strojno berljivo vrstico rezultata namesto sporočila za ljudi]' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '::plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '--accept-command[Sprejmi ukaz, ki ga deklarira tržnica in katerega sha256 je prejšnji zagon z --json sporočil kot shownCommand.sha256]:sha256:' \
            '(-s --scope)'{-s,--scope}'[Obseg namestitve]:scope:(user project local managed)' \
            '(-y --yes)'{-y,--yes}'[Sprejmi prikazani ukaz, ki ga deklarira tržnica, brez potrditvenega poziva]' \
            '--json[Izpiši eno strojno berljivo vrstico rezultata namesto sporočila za ljudi]' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list)
          _arguments \
            '--json[Izpiši kot JSON]' \
            '--available[Vključi razpoložljive vtičnike iz tržnic (zahteva --json)]' \
            '--data-size[Izmeri imenik shranjenih podatkov vsakega nameščenega vtičnika ali samo poimenovanega vtičnika (zahteva --json)]::plugin:_claude_installed_plugins' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]'
          ;;
        prune|autoremove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Počisti v obsegu]:scope:(user project local)' \
            '--dry-run[Prikaži seznam tega, kar bi bilo odstranjeno, brez odstranjevanja]' \
            '(-y --yes)'{-y,--yes}'[Preskoči potrditveni poziv]' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]'
          ;;
        configure)
          _arguments \
            '--json[Izpiši kot JSON]' \
            '--values-stdin[Preberi vrednosti možnosti iz stdin kot JSON objekt enovrstičnih nizov; izpuščene možnosti ohranijo svoje vrednosti]' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init|new)
          _arguments \
            '--description[Opis manifesta]:text:' \
            '--author[Ime avtorja (privzeto: git config user.name)]:name:' \
            '--author-email[E-pošta avtorja (privzeto: git config user.email)]:email:' \
            '--with[Komponente, za katere naj se prav tako ustvari ogrodje]:components:' \
            '(-f --force)'{-f,--force}'[Prepiši obstoječi .claude-plugin/ na cilju]' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:name:'
          ;;
        eval)
          if [[ $words[2] == init ]]; then
            _arguments \
              '--bare[Zapiši prazno predlogo namesto izvedbe intervjuja]' \
              '--eval-dir[Imenik pod trenutnim imenikom, v katerega se zapišejo primeri]:dir:_directories' \
              '(-i --interactive)'{-i,--interactive}'[Zaženi avtorski intervju (zahteva interaktivni terminal)]' \
              '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
              '::name:'
            return
          fi
          _arguments \
            '--case[Filtriraj primere po vzorcu glob imena]:glob:' \
            '*--tag[Filtriraj primere po oznaki (lahko se ponovi)]:tag:' \
            '--runs[Preglasi število zagonov na primer (privzeto: case.runs, sicer 3)]:n:' \
            '(-j --concurrency)'{-j,--concurrency}'[Izvajaj do n zagonov agenta hkrati (1-8; privzeto 1)]:n:' \
            '--model[Preglasi model za vse primere]:model:_claude_model_names' \
            '--judge-model[Preglasi model ocenjevalca LLM (privzeto: haiku)]:model:_claude_model_names' \
            '--max-cost-usd[Trda zgornja meja stroškov; ob dosegu prekini in poročaj delne rezultate (izhodna koda 2)]:usd:' \
            '--output-dir[Imenik za aggregate-result.json]:dir:_directories' \
            '--eval-dir[Ime imenika (pod vtičnikom), ki vsebuje primere ocenjevanja]:dir:' \
            '--json[Izpiši celoten rezultat zagona kot JSON na stdout ali ga zapiši v to datoteko .json]::path:_files' \
            '--threshold[Končaj z izhodno kodo 1, če je ocena katerega koli primera pod tem pragom (privzeto: 1.0)]:threshold:' \
            '*--allow-tools[Dovoljenje operaterja za zaklenjena orodja (Bash, Write, Edit, WebFetch, mcp__*)]:tools:' \
            '*--disallow-tools[Vgrajena orodja, ki jih Claude v nobenem primeru ne dobi, tudi če so odobrena]:tools:' \
            '(--no-scaffold)--scaffold[Zaženi scaffold_script vsakega primera (izvaja bash, ki ga priskrbi avtor, pod vašim računom; privzeto izklopljeno)]' \
            '(--scaffold)--no-scaffold[Izrecno preskoči scaffold_script]' \
            '--trust-plugin[Potrdi, da zaupate temu vtičniku in njegovemu naboru ocenjevanj, in preskoči poziv za zaupanje ob prvem zagonu (za CI)]' \
            '--ablation[Zaženi primerjalno skupino brez vtičnika in poročaj razliko v oceni]:mode:(none with-without)' \
            '--mocks[Nadomestne imitacije za MCP strežnike iz <eval dir>/mocks/]:mode:(record off)' \
            '--allow-real-servers[Z --mocks record: zaženi tudi procese pravih MCP strežnikov, ki nimajo imitacije]' \
            '--keep-temp[Ohrani imenike ogrodja za odpravljanje napak]' \
            '--verbose[Beleži dogodke sledenja za posamezno sporočilo v dnevnik odpravljanja napak]' \
            '--report[Zapiši samostojno poročilo HTML na to pot namesto v imenik rezultatov]:path:_files' \
            '(--no-publish)--publish-report[Zahtevaj tudi objavo poročila na claude.ai]' \
            '(--publish-report)--no-publish[Ohrani poročilo HTML samo lokalno; preskoči objavo na claude.ai]' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '::target: _alternative "commands\:eval command\:(init)" "plugins\:installed plugin\:_claude_installed_plugins" "files\:path\:_files"'
          ;;
        tag)
          _arguments \
            '--push[Po ustvarjanju potisni oznako na --remote]' \
            '--dry-run[Izpiši, kaj bi bilo označeno, brez ustvarjanja oznake]' \
            '(-f --force)'{-f,--force}'[Preskoči preverjanji neočiščenega delovnega drevesa in že obstoječe oznake]' \
            '(-m --message)'{-m,--message}'[Sporočilo anotacije oznake (uporabi %s za različico)]:msg:' \
            '--remote[Oddaljeni repozitorij za potiskanje z --push]:name:' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '::path:_files'
          ;;
        test)
          _arguments \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '::dir:_directories'
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
            '--sparse[Omeji checkout na določene imenike prek git sparse-checkout (za monorepozitorije)]:paths:' \
            '--scope[Kje deklarirati tržnico]:scope:(user project local)' \
            '--json[Izpiši eno strojno berljivo vrstico rezultata kot zadnjo vrstico na stdout]' \
            '--claudeai[Dodaj tržnico s tem imenom, ki jo claude.ai gosti za vas]' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '--json[Izpiši kot JSON]' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]'
          ;;
        remove|rm)
          _arguments \
            '--scope[Odstrani deklaracijo tržnice iz določenega obsega nastavitev (izpusti za odstranitev iz vseh obsegov)]:scope:(user project local)' \
            '--json[Izpiši eno strojno berljivo vrstico rezultata kot zadnjo vrstico na stdout]' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč]' \
            '1:name:'
          ;;
        update)
          _arguments \
            '--json[Z imenom tržnice: izpiši eno strojno berljivo vrstico rezultata kot zadnjo vrstico na stdout]' \
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
    '--agent[Privzeti agent za seje, razporejene iz pogleda agentov]:agent:_claude_agent_names' \
    '--all[Z --json: vključi tudi dokončane seje v ozadju]' \
    '--allow-dangerously-skip-permissions[Omogoči način obida dovoljenj razporejenim sejam]' \
    '--cwd[Prikaži samo seje v ozadju, zagnane pod potjo]:path:_directories' \
    '--dangerously-skip-permissions[Vzdevek za --permission-mode bypassPermissions]' \
    '--effort[Privzeta raven napora za razporejene seje]:level:(low medium high xhigh max)' \
    '--json[Izpiši aktivne seje kot JSON polje in izhod]' \
    '*--mcp-config[Konfiguracija MCP strežnika za uporabo v razporejenih sejah]:config:' \
    '--model[Privzeti model za seje, razporejene iz pogleda agentov]:model:_claude_model_names' \
    '--permission-mode[Privzeti način dovoljenj za razporejene seje]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Naloži vtičnike iz imenika za pogled agentov in razporejene seje]:path:_directories' \
    '--setting-sources[Seznam virov nastavitev ločenih z vejico za nalaganje (user, project, local)]:sources:' \
    '--settings[Datoteka z nastavitvami ali JSON niz za uporabo]:file-or-json:_files' \
    '--strict-mcp-config[Uporabi samo MCP strežnike iz --mcp-config v razporejenih sejah]' \
    '--restricted[Zaženi razporejene seje v omejenem načinu]' \
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
        login)
          _arguments \
            '--email[Vnaprej izpolni e-poštni naslov na strani za prijavo]:email:' \
            '--sso[Vsili postopek prijave SSO]' \
            '(--claudeai)--console[Uporabi Anthropic Console (obračun po porabi API) namesto naročnine Claude]' \
            '(--console)--claudeai[Uporabi naročnino Claude (privzeto)]' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč za ukaz]'
          ;;
        status)
          _arguments \
            '(--text)--json[Izpiši kot JSON (privzeto)]' \
            '(--json)--text[Izpiši kot človeku berljivo besedilo]' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč za ukaz]'
          ;;
        logout)
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
        critique)
          _arguments \
            '--model[Preglasi uporabljeni model]:model:_claude_model_names' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč za ukaz]'
          ;;
        defaults)
          _arguments \
            '--label[Prikaži samo pravila, katerih oznaka se začne s to predpono (ne glede na velike/male črke)]:prefix:' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč za ukaz]'
          ;;
        reset)
          _arguments \
            '(-y --yes)'{-y,--yes}'[Preskoči potrditveni poziv]' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč za ukaz]'
          ;;
        config)
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
            '--dry-run[Prikaži seznam tega, kar bi bilo izbrisano, brez brisanja česarkoli]' \
            '(-y --yes)'{-y,--yes}'[Preskoči potrditveni poziv]' \
            '(-i --interactive)'{-i,--interactive}'[Pred brisanjem pozovi za vsak element]' \
            '(1)--all[Počisti stanje za vse projekte (medsebojno izključujoče s potjo)]' \
            '(-h --help)'{-h,--help}'[Prikaži pomoč za ukaz]' \
            '(--all)::path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_purge() {
  _arguments \
    '--dry-run[Prikaži seznam tega, kar bi bilo izbrisano, brez brisanja česarkoli]' \
    '(-y --yes)'{-y,--yes}'[Preskoči potrditveni poziv]' \
    '(-i --interactive)'{-i,--interactive}'[Pred brisanjem pozovi za vsak element]' \
    '(1)--all[Počisti stanje za vse projekte (medsebojno izključujoče s potjo)]' \
    '(-h --help)'{-h,--help}'[Prikaži pomoč za ukaz]' \
    '(--all)::path:_directories'
}

_claude_ultrareview() {
  _arguments \
    '--json[Izpiši surovo vsebino bugs.json namesto oblikovanih ugotovitev]' \
    '--timeout[Največ minut za čakanje na dokončanje pregleda (privzeto: 45)]:minutes:' \
    '(--no-post)--post[Objavi ugotovitve dokončanega pregleda v PR pod vašim imenom (samo za cilje PR; en navaden komentar, ne pregled)]' \
    '(--post)--no-post[Ne objavi ugotovitev v PR (privzeto)]' \
    '--trust-workspace[Zaupaj trenutni mapi samo za ta zagon, brez vprašanja (za skripte in CI)]' \
    '(-h --help)'{-h,--help}'[Prikaži pomoč za ukaz]' \
    '1:target:'
}

_claude_respawn() {
  _arguments \
    '(1)--all[Znova zaženi vse tekoče seje v ozadju]' \
    '(-h --help)'{-h,--help}'[Prikaži pomoč za ukaz]' \
    '(--all)::session:_claude_background_sessions'
}

_claude_rm() {
  _arguments \
    '--discard-unpushed[Zavrzi tudi nepotisnjene commite in neuveljavljene spremembe delovnega drevesa (podaj commit@worktree-id, ki ga je sporočil prejšnji claude rm)]:commit@worktree-id:' \
    '--force-remove-worktree[Izbriši imenik delovnega drevesa, čeprav ga kljuka WorktreeRemove ali git nista mogla odstraniti (podaj worktree-id, ki ga je sporočil prejšnji claude rm)]:worktree-id:' \
    '(-h --help)'{-h,--help}'[Prikaži pomoč za ukaz]' \
    '1:session:_claude_background_sessions'
}

_claude_self_hosted_runner() {
  _arguments \
    '--api-url[Osnovni URL API-ja (privzeto: https://api.anthropic.com)]:url:' \
    '--environment-secret-file[Pot do datoteke s skrivnostjo okolja]:path:_files' \
    '--lock-to-account[Ob registraciji zakleni izvajalnik na en sam račun]:id:' \
    '--client-label[Oznaka opazljivosti, poslana ob registraciji (privzeto: hostname)]:label:' \
    '(--proxy-authorization-file --agent-proxy-url)--proxy-authorization-command[Ukaz, katerega stdout je glava Proxy-Authorization za izhodne proxyje]:shell command:' \
    '(--proxy-authorization-command --agent-proxy-url)--proxy-authorization-file[Datoteka z glavo Proxy-Authorization za izhodne proxyje]:path:_files' \
    '(--proxy-authorization-command --proxy-authorization-file)--agent-proxy-url[Usmeri vsako sejo prek agentnega proxyja na tem URL-ju (samo https)]:url:' \
    '--capacity[Največ hkratnih sej (privzeto: 1)]:n:' \
    '--base-dir[Osnovni imenik za checkoute repozitorijev (privzeto: /workspace)]:path:_directories' \
    '--exec-path[Binarna datoteka za zagon podrejenih sej (privzeto: ta binarna datoteka)]:path:_files' \
    '--hooks-dir[Imenik skriptov kljuk življenjskega cikla (checkout, command, post-session)]:path:_directories' \
    '--session-stop-grace-sec[Kako dolgo čakati na čist izhod po koncu seje (privzeto: 5)]:n:' \
    '--post-session-hook-timeout-sec[Časovni proračun SIGTERM za kljuko post-session (privzeto: 60)]:n:' \
    '--checkout-hook-timeout-min[Proračun realnega časa za vsak zagon kljuke checkout (privzeto: 30; 0 onemogoči)]:n:' \
    '--drain-wait-sec[Ob SIGTERM/SIGINT počakaj do N sekund na delo v teku (privzeto: 0)]:n:' \
    '--drain-marker-file[Označevalna datoteka, s katero gostitelj napove nadzorovano praznjenje]:path:_files' \
    '*--git-ssh-rewrite[Prepiši izvorne URL-je https://<host>/... v git@<host>:... (lahko se ponovi)]:host:' \
    '*--git-host-rewrite[Prepiši izvorne URL-je https://<f>/... v https://<t>/... (lahko se ponovi)]:from=to:' \
    '--use-anthropic-git-proxy[Uporabi git, ki ga upravlja Anthropic. OPOZORILO: izbriše in zamenja konfiguracijo git na ravni HOME, uporabljaj samo pod namenskim računom]' \
    '--configure-git[Nastavi globalno identiteto git in omogoči podpisovanje commitov prek storitve za podpisovanje Anthropic. Zapiše ~/.gitconfig]' \
    '--push-outcome-on-release[Potisni sledene veje z rezultati, ko izvajalnik konča nedokončano sejo]' \
    '--trust-workspace[Vnaprej nastavi trajno zaupanje za poti repozitorijev vsake seje (privzeto: true)]::bool:(true false)' \
    '--remove-session-state[Odstrani stanje posamezne seje, ko se seja konča (privzeto: false)]::bool:(true false)' \
    '--diff-finds-nested-repository[Prikaži repozitorij, kloniran v podmapo, v podoknu Changes; zahteva --capacity 1 (privzeto: false)]::bool:(true false)' \
    '--confine-repo-settings[Način varovala za omejevanje nastavitev, uveljavljenih v repozitoriju (privzeto: warn)]:mode:(warn enforce off)' \
    '--server-auto-mode-lists[Katere sezname klasifikatorja samodejnega načina s strežnika lahko seja prejme (privzeto: no-allow)]:mode:(all no-allow none)' \
    '--host-config-snapshot[Kje se hrani začetni posnetek konfiguracije gostitelja (privzeto: disk)]:mode:(disk memory)' \
    '--health-port[Vrata za poslušalnik HTTP /healthz (privzeto: 8080; 0 onemogoči)]:port:' \
    '--log-level[Raven dnevnika (privzeto: info)]:level:(info debug)' \
    '--log-file[Dnevnike izvajalnika kopiraj tudi v datoteko v načinu dodajanja]:path:_files' \
    '--exit-if-unused-min[Končaj izvajalnik, če mu N minut ni dodeljeno nobeno delo]:n:' \
    '--drain-grace-sec[Sekunde nadaljnjega preverjanja za delo po koncu aktivnih sej (privzeto: 0)]:n:' \
    '--retire-at[Upokoji izvajalnik ob tem absolutnem času Unix, v sekundah]:epoch-seconds:' \
    '--defer-shutdown-max-min[Ob prvem SIGTERM/SIGINT nehaj sprejemati delo in dokončaj zaustavitev M minut pozneje (privzeto: 0)]:m:' \
    '--release-idle-session-min[Sprosti mesto seje po N minutah brez uporabnikovega vnosa]:n:' \
    '--startup-timeout-min[Sprosti mesto seje, če podrejeni proces po N minutah še ni končal zagona (privzeto: 15; 0 onemogoči)]:n:' \
    '--kill-session-after-min[Omeji življenjsko dobo podrejene seje v realnem času na N minut]:n:' \
    '--debug-token-dir[SAMO ZA ODPRAVLJANJE NAPAK: zapisuje žive žetone na disk. Ne uporabljaj v produkciji]:path:_directories' \
    '(-h --help)'{-h,--help}'[Prikaži to sporočilo pomoči]'
}

_claude_remote_control() {
  _arguments \
    '--name[Ime seje (prikazano v claude.ai/code)]:name:' \
    '--remote-control-session-name-prefix[Predpona za samodejno ustvarjena imena sej (privzeto: hostname)]:prefix:' \
    '(-c --continue --session-id)'{-c,--continue}'[Ponovno se pripni na sejo, nazadnje zabeleženo za ta imenik ali eno od njegovih git delovnih dreves]' \
    '(-c --continue --session-id)--session-id[Ponovno se pripni na določeno sejo po ID-ju]:id:' \
    '--permission-mode[Način dovoljenj za zagnane seje]:mode:(acceptEdits auto bypassPermissions default dontAsk plan)' \
    '(--no-chrome)--chrome[Omogoči Claude in Chrome za zagnane seje]' \
    '(--chrome)--no-chrome[Onemogoči Claude in Chrome za zagnane seje]' \
    '(-d --debug)'{-d,--debug}'[Vklop načina odpravljanja napak z izbirnim filtriranjem kategorij]::filter:' \
    '--debug-file[Zapiši dnevnike odpravljanja napak v datoteko]:path:_files' \
    '(-v --verbose)'{-v,--verbose}'[Omogoči podroben izpis]' \
    '--spawn[Način zagona (privzeto: same-dir)]:mode:(same-dir worktree session)' \
    '--capacity[Največ hkratnih sej v načinu worktree ali same-dir (privzeto: 32)]:n:' \
    '(--no-create-session-in-dir)--create-session-in-dir[Vnaprej ustvari sejo v trenutnem imeniku (privzeto)]' \
    '(--create-session-in-dir)--no-create-session-in-dir[Ne ustvari seje vnaprej v trenutnem imeniku]' \
    '(-h --help)'{-h,--help}'[Prikaži to pomoč]'
}

_claude_daemon() {
  local -a daemon_commands common_options
  daemon_commands=(
    'run:Zaženi nadzornika v ospredju'
    'status:Prikaži pid, različico in čas delovanja demona'
    'logs:Spremljaj dnevnik demona (Ctrl-C za ustavitev)'
    'uninstall:Odstrani storitev v ozadju (launchctl/systemd)'
    'stop:Zaustavi nadzornika in končaj seje v ozadju'
  )
  common_options=(
    '--json-path[Konfiguracijska datoteka (privzeto: ~/.claude/daemon.json)]:path:_files'
    '--log-file[Datoteka dnevnika (privzeto: ~/.claude/daemon.log)]:path:_files'
    '(-h --help)'{-h,--help}'[Prikaži to pomoč]'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    $common_options \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'ukazi daemon' daemon_commands
      ;;
    args)
      case $words[1] in
        run)
          _arguments \
            $common_options \
            '::json-path:_files'
          ;;
        stop)
          _arguments \
            $common_options \
            '--any[Ustavi tudi začasnega demona (ki ni storitev)]' \
            '--keep-workers[Pusti odpete seje, da tečejo naprej]'
          ;;
        status|logs|uninstall)
          _arguments \
            $common_options
          ;;
      esac
      ;;
  esac
}

_claude_import() {
  _arguments \
    '--dry-run[Prikaži, kaj bi bilo uvoženo, brez zapisovanja česarkoli]' \
    '--yes[Preskoči interaktivni izbirnik (na površinah brez grafičnega vmesnika podaj --yes=<digest> iz predogleda /import)]' \
    '(-h --help)'{-h,--help}'[Prikaži pomoč za ukaz]' \
    '::source:(codex gemini cursor)'
}

# compinit autoloads this file, and that first call only defines the functions
# above: complete right away so the first TAB already works. Sourced directly,
# there is nothing to complete yet, only the registration.
if [[ $funcstack[1] == _claude ]]; then
  _claude "$@"
else
  (( $+_comps[claude] )) || compdef _claude claude
fi
