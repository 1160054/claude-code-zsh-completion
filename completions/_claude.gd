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
    'mcp:Rèitich agus stiùir frithealaichean MCP'
    'plugin:Stiùir plugain Claude Code'
    'agents:Stiùir àidseantan cùil'
    'attach:Fosgail seisean cùil san tèirmineal seo'
    'logs:Clò-bhuail an toradh tèirmineil o chionn ghoirid aig seisean cùil'
    'stop:Cuir stad air seisean cùil (thèid an còmhradh aige a ghleidheadh)'
    'respawn:Ath-thòisich seisean cùil gus an ruith e an tionndadh làithreach de Claude Code'
    'rm:Sguab às seisean cùil, agus a chraobh-obrach nuair a tha sin sàbhailte'
    'auth:Stiùir dearbhadh'
    'auto-mode:Sgrùd no ath-shuidhich rèiteachadh seòrsaiche modh fèin-obrachaidh'
    'gateway:Ruith an geata dearbhaidh/cian-thomhais fiosrachaidh na h-iomairt'
    'import:Ion-phortaich rèiteachadh bho àidseant còdaidh IF eile a-steach do Claude Code'
    'project:Stiùir staid pròiseact Claude Code'
    'ultrareview:Ruith lèirmheas còd ioma-àidseant air a òstadh sa neul agus clò-bhuail na toraidhean'
    'setup-token:Suidhich tòcan dearbhaidh fad-ùine (feumaidh fo-sgrìobhadh Claude)'
    'doctor:Sgrùdadh slàinte airson ùrachadair Claude Code'
    'update:Thoir sùil airson agus stàlaich ùrachaidhean'
    'install:Stàlaich togail dhùthchasach Claude Code'
  )

  local -a main_options
  main_options=(
    '(-d --debug)'{-d,--debug}'[Cuir an comas modh dì-bhugachaidh le sìoladh roinn-seòrsa roghainneil (m.e., "api,hooks" no "!statsig,!file")]:sìoltachan:'
    '--verbose[Tar-àithn suidheachadh modh briathrach bhon fhaidhle rèiteachaidh]'
    '(-p --print)'{-p,--print}'[Clò-bhuail freagairt agus fàg (airson cleachdadh le pìoban). Nòta: cleachd a-mhàin ann an eòlaireann earbsach]'
    '--output-format[Cruth toraidh (le --print): "text" (roghainn bhunaiteach), "json" (toradh singilte), no "stream-json" (sruthadh fìor-ùine)]:cruth:(text json stream-json)'
    '--json-schema[Sgeama JSON airson dearbhadh toraidh structarail]:sgeama:'
    '--include-partial-messages[Gabh a-steach mìrean teachdaireachd pàirteach mar a ruigeas iad (le --print agus --output-format=stream-json)]'
    '--input-format[Cruth ion-chuir (le --print): "text" (roghainn bhunaiteach) no "stream-json" (ion-chur sruthadh fìor-ùine)]:cruth:(text stream-json)'
    '--mcp-debug[\[Air a dhì-mholadh. Cleachd --debug an àite sin\] Cuir an comas modh dì-bhugachaidh MCP (seall mearachdan frithealaiche MCP)]'
    '--dangerously-skip-permissions[Seachain gach sgrùdadh cead. A-mhàin air a mholadh airson bogsaichean-gainmhich gun inntrigeadh eadar-lìn]'
    '--allow-dangerously-skip-permissions[Ceadaich roghainn gus sgrùdaidhean cead a sheachnadh gun a chur an comas mar roghainn bhunaiteach]'
    '--restricted[Modh cuingichte: thoir air falbh na h-innealan a ruitheas àitheantan no còd agus WebFetch, leig seachad roghainnean user/project/local, agus cuingich innealan faidhle ris na h-eòlairean obrach]'
    '--max-budget-usd[An t-suim dolar as motha ri chosg air gairmean API (--print a-mhàin)]:suim:'
    '--replay-user-messages[Ath-chuir teachdaireachdan cleachdaiche bho stdin air stdout airson dearbhadh]'
    '--allowed-tools[Liosta air a sgaradh le cromag no àite de dh'\''ainmean innealan a tha ceadaichte (m.e., "Bash(git:*) Edit")]:innealan:'
    '--allowedTools[Liosta air a sgaradh le cromag no àite de dh'\''ainmean innealan a tha ceadaichte (cruth camelCase)]:innealan:'
    '--tools[Sònraich liosta de dh'\''innealan ri fhaighinn bhon t-seata togail a-steach. Modh clò-bhualaidh a-mhàin]:innealan:'
    '--disallowed-tools[Liosta air a sgaradh le cromag no àite de dh'\''ainmean innealan nach eil ceadaichte (m.e., "Bash(git:*) Edit")]:innealan:'
    '--disallowedTools[Liosta air a sgaradh le cromag no àite de dh'\''ainmean innealan nach eil ceadaichte (cruth camelCase)]:innealan:'
    '--mcp-config[Luchdaich frithealaichean MCP bho fhaidhle JSON no sreang JSON (air a sgaradh le àite)]:rèiteachaidhean:'
    '--system-prompt[Brosnachadh siostam airson a chleachdadh airson an t-seisein]:brosnachadh:'
    '--system-prompt-file[Leugh brosnachadh siostam bho fhaidhle]:file:_files'
    '--append-system-prompt[Cuir brosnachadh siostam ris a'\'' bhrosnachadh siostam bhunaiteach]:brosnachadh:'
    '--append-system-prompt-file[Leugh brosnachadh siostam bho fhaidhle agus cuir ris a'\'' bhrosnachadh siostam bhunaiteach e]:file:_files'
    '--system-prompt-snapshot[Clàraich am brosnachadh siostam aon turas gach còmhradh agus ath-chleachd e facal air an fhacal air gach iarrtas agus ath-thòiseachadh (on, an roghainn bhunaiteach) no cruthaich às ùr e air gach iarrtas (off)]:mode:(on off)'
    '--permission-mode[Modh cead airson a chleachdadh airson an t-seisein]:modh:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '--permission-prompts[Cò a fhreagras brosnachaidhean cead le --print: "host" (an t-òstair SDK no --permission-prompt-tool) no "none" (thèid rud sam bith a dh'\''iarradh cead a dhiùltadh)]:target:(host none)'
    '--permission-prompt-tool[Inneal MCP ri chleachdadh airson brosnachaidhean cead (--print a-mhàin)]:tool:'
    '(-c --continue)'{-c,--continue}'[Lean air adhart leis a'\'' chòmhradh as ùire]'
    '(-r --resume)'{-r,--resume}'[Ath-thòisich còmhradh - sònraich ID seisein no tagh gu h-eadar-ghnìomhach]:IDseisein:_claude_sessions'
    '--fork-session[Cruthaich ID seisein ùr an àite ID seisein tùsail ath-chleachdadh nuair a thòisicheas tu a-rithist (le --resume no --continue)]'
    '--no-session-persistence[Cuir à comas maireannachd seisein - cha tèid seiseanan a shàbhaladh (--print a-mhàin)]'
    '--model[Modail airson an t-seisein làithreach. Sònraich alias airson a'\'' mhodail as ùire (m.e., '\''sonnet'\'' no '\''opus'\'')]:modail:_claude_model_names'
    '--agent[Àidseant airson an t-seisein làithreach. Tar-àithnidh e an suidheachadh '\''agent'\'']:àidseant:_claude_agent_names'
    '--betas[Bannan-cinn beta ri ghabhail a-steach ann an iarrtasan API (luchd-cleachdaidh iuchair API a-mhàin)]:betas:'
    '--fallback-model[Cuir an comas tuiteam fèin-ghluasadach chun mhodail a chaidh a shònrachadh nuair a tha am modail bunaiteach air a luchdachadh thar a chomais (--print a-mhàin)]:modail:_claude_model_names'
    '--settings[Slighe gu faidhle JSON roghainnean no sreang JSON gus roghainnean a bharrachd a luchdachadh]:faidhle-no-json:_files'
    '--add-dir[Eòlaireann a bharrachd gus cead inntrigidh innealan]:eòlaireann:_directories'
    '--ide[Fèin-cheangail ri IDE aig toiseach tòiseachaidh ma tha dìreach aon IDE dligheach ri fhaighinn]'
    '--desktop[Fosgail san aplacaid Claude Desktop an àite an tèirmineil (le --continue no --resume <id> gus an seisean a thaghadh)]'
    '--strict-mcp-config[Cleachd dìreach frithealaichean MCP bho --mcp-config agus leig seachad gach roghainn MCP eile]'
    '--session-id[ID seisein sònraichte airson a chleachdadh airson a'\'' chòmhraidh (feumaidh e bhith na UUID dligheach)]:uuid:'
    '--agents[Nì JSON a mhìnicheas àidseantan gnàthaichte]:json:'
    '--setting-sources[Liosta air a sgaradh le cromag de thùsan roghainnean ri luchdachadh (user, project, local)]:tùsan:'
    '--plugin-dir[Eòlaire gus plugain a luchdachadh às airson an t-seisein seo a-mhàin (ath-dhèante)]:slighean:_directories'
    '--disable-slash-commands[Cuir à comas gach àithne slais]'
    '(--bg --background)'{--bg,--background}'[Tòisich an seisean mar àidseant cùil agus till sa bhad]'
    '(-w --worktree)'{-w,--worktree}'[Cruthaich craobh-obrach git ùr airson an t-seisein seo (sònraich ainm gu roghainneil)]::ainm:'
    '--tmux=-[Cruthaich seisean tmux airson na craoibh-obrach (feumaidh --worktree). Cleachdaidh e leòsain dhùthchasach iTerm2 nuair a bhios iad ri fhaighinn; --tmux=classic airson tmux traidiseanta]::mode:(classic)'
    '(-n --name)'{-n,--name}'[Suidhich ainm-taisbeanaidh airson an t-seisein seo]:ainm:'
    '--effort[Ìre oidhirp airson an t-seisein làithreach]:ìre:(low medium high xhigh max)'
    '--autocompact[Meud uinneag an fhèin-dhùmhlachaidh (auto, no 100k-1M tòcan)]:size:(auto)'
    '--debug-file[Sgrìobh logaichean dì-bhugachaidh gu slighe faidhle sònraichte (cuiridh e an comas modh dì-bhugachaidh gu fillte)]:slighe:_files'
    '--from-pr[Ath-thòisich seisean ceangailte ri PR a rèir àireamh/URL, no fosgail roghnaichear eadar-ghnìomhach]::luach:'
    '--teleport[Ath-thòisich seisean teleport, sònraich ID seisein gu roghainneil]::session:'
    '--cloud[Cruthaich seisean neòil leis an tuairisgeul a chaidh a thoirt, no ceangail ri seisean a tha ann mu thràth a rèir ID seisein no URL claude.ai/code]::description-or-session:'
    '--environment[Cruthaich seisean neòil ùr a ruitheas air an àrainneachd fèin-òstaichte a chaidh a thoirt (ccpool_...)]:environment_id:'
    '--remote-control[Tòisich seisean eadar-ghnìomhach le Smachd Cèin an comas (ainmichte gu roghainneil)]::ainm:'
    '--remote-control-session-name-prefix[Ro-leasachan airson ainmean seisein Smachd Cèin fèin-ghinte]:ro-leasachan:'
    '--chrome[Cuir an comas amalachadh Claude ann an Chrome]'
    '--no-chrome[Cuir à comas amalachadh Claude ann an Chrome]'
    '--plugin-url[Faigh .zip plugan bho URL airson an t-seisein seo a-mhàin (ath-dhèante)]:url:'
    '--file[Goireasan faidhle ri luchdachadh a-nuas aig toiseach tòiseachaidh (cruth: file_id:relative_path)]:sonrachaidhean:'
    '--prompt-suggestions[Cuir an comas molaidhean brosnachaidh (leigidh e a-mach ath-bhrosnachadh ro-innsichte ann am modh print/SDK)]::luach:(true false 1 0 yes no on off)'
    '--forward-subagent-text[Cuir air adhart teacsa fo-àidseant agus blocaichean smaoineachaidh mar theachdaireachdan (le --print agus stream-json)]'
    '--include-hook-events[Gabh a-steach gach tachartas cuairt-beatha dubhain san t-sruth toraidh (le stream-json)]'
    '--exclude-dynamic-system-prompt-sections[Gluais earrannan gach-inneal a-steach don chiad teachdaireachd cleachdaiche gus ath-chleachdadh tasgadan-brosnachaidh a leasachadh]'
    '--brief[Cuir an comas an t-inneal SendUserMessage airson conaltradh àidseant-gu-cleachdaiche]'
    '--safe-mode[Tòisich le gach gnàthachadh à comas (feumail airson fuasgladh dhuilgheadasan le rèiteachadh briste)]'
    '--bare[Modh as lugha: leig seachad dubhain, LSP, sioncronachadh plugan, buileachadh, fèin-chuimhne, agus fèin-lorg CLAUDE.md]'
    '--ax-screen-reader[Dèan toradh càirdeil do leughadair-sgrìn (teacsa rèidh, gun oirean sgeadachaidh no beòthachaidhean)]'
    '(-v --version)'{-v,--version}'[Toradh àireamh tionndaidh]'
    '(-h --help)'{-h,--help}'[Seall cobhair airson àithne]'
  )

  _arguments -C \
    $main_options \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'àitheantan claude' main_commands
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
            '(-h --help)'{-h,--help}'[Seall cobhair airson àithne]' \
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
          _message "gun argamaidean"
          ;;
      esac
      ;;
  esac
}

_claude_mcp() {
  local -a mcp_commands
  mcp_commands=(
    'serve:Tòisich frithealaiche MCP Claude Code'
    'add:Cuir frithealaiche MCP ri Claude Code'
    'remove:Thoir air falbh frithealaiche MCP'
    'list:Liostaich frithealaichean MCP air an rèiteachadh'
    'get:Faigh mion-fhiosrachadh frithealaiche MCP'
    'add-json:Cuir frithealaiche MCP (stdio no SSE) le sreang JSON'
    'add-from-claude-desktop:Ion-phortaich frithealaichean MCP bho Claude Desktop (Mac agus WSL a-mhàin)'
    'reset-project-choices:Ath-shuidhich gach frithealaiche (.mcp.json) air a cheadachadh/air a dhiùltadh sa phròiseact seo'
    'login:Dearbh le frithealaiche MCP (HTTP, SSE, no ceanglaiche claude.ai)'
    'logout:Falamhaich teisteanasan OAuth stòraichte airson frithealaiche MCP'
    'help:Seall cobhair'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Seall cobhair]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'àitheantan mcp' mcp_commands
      ;;
    args)
      case $words[1] in
        serve)
          _arguments \
            '(-d --debug)'{-d,--debug}'[Cuir an comas modh dì-bhugachaidh]' \
            '--verbose[Tar-àithn suidheachadh modh briathrach bhon fhaidhle rèiteachaidh]' \
            '(-h --help)'{-h,--help}'[Seall cobhair]'
          ;;
        add)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Sgòp rèiteachaidh (local, user, project)]:sgòp:(local user project)' \
            '(-t --transport)'{-t,--transport}'[Seòrsa còmhdhail (stdio, sse, http)]:còmhdhail:(stdio sse http)' \
            '(-e --env)'{-e,--env}'[Suidhich caochladair àrainneachd (m.e., -e KEY=value)]:env:' \
            '(-H --header)'{-H,--header}'[Suidhich bann-cinn WebSocket]:bann-cinn:' \
            '--client-id[ID cliant OAuth airson frithealaichean HTTP/SSE]:clientId:' \
            '--client-secret[Iarr rùn cliant OAuth (no suidhich an caochladair àrainneachd MCP_CLIENT_SECRET)]' \
            '--callback-port[Port suidhichte airson ais-ghairm OAuth (airson frithealaichean a dh'\''fheumas URIan ath-stiùiridh ro-chlàraichte)]:port:' \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:ainm:' \
            '2:àithneNoUrl:' \
            '*:argamaidean:'
          ;;
        remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Sgòp rèiteachaidh (local, user, project) - thoir air falbh bho sgòp làithreach mura h-eilear a'\'' sònrachadh]:sgòp:(local user project)' \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:ainm:_claude_mcp_servers'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Seall cobhair]'
          ;;
        get)
          _arguments \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:ainm:_claude_mcp_servers'
          ;;
        add-json)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Sgòp rèiteachaidh (local, user, project)]:sgòp:(local user project)' \
            '--client-secret[Iarr rùn cliant OAuth (no suidhich an caochladair àrainneachd MCP_CLIENT_SECRET)]' \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:ainm:' \
            '2:json:'
          ;;
        add-from-claude-desktop)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Sgòp rèiteachaidh (local, user, project)]:sgòp:(local user project)' \
            '(-h --help)'{-h,--help}'[Seall cobhair]'
          ;;
        reset-project-choices)
          _arguments \
            '(-h --help)'{-h,--help}'[Seall cobhair]'
          ;;
        login)
          _arguments \
            '--no-browser[Clò-bhuail an URL ùghdarrachaidh an àite brabhsair fhosgladh (airson seiseanan SSH/gun cheann)]' \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:name:_claude_mcp_servers'
          ;;
        logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:ainm:_claude_mcp_servers'
          ;;
      esac
      ;;
  esac
}

_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:Dearbh plugan no ainm-clàr margaidh'
    'marketplace:Stiùir margaidhean Claude Code'
    'list:Liostaich plugain air an stàladh'
    'details:Seall clàr-tasgaidh cho-phàirtean agus cosgais tòcan ro-mheasta airson plugan'
    'configure:Seall roghainnean plugain agus an fheadhainn nach deach a shuidheachadh, no sàbhail luachan bho stdin'
    'install:Stàlaich plugan bho mhargaidhean ri fhaighinn'
    'i:Stàlaich plugan bho mhargaidhean ri fhaighinn (geàrr-slighe airson install)'
    'init:Sgafall plugan ùr (fèin-luchdachadh san ath sheisean)'
    'new:Sgafall plugan ùr (ainm eile airson init)'
    'uninstall:Dì-stàlaich plugan air a stàladh'
    'remove:Dì-stàlaich plugan air a stàladh (ainm eile airson uninstall)'
    'enable:Cuir an comas plugan air a chur à comas'
    'disable:Cuir à comas plugan air a chur an comas'
    'update:Ùraich plugan chun tionndaidh as ùire'
    'eval:Ruith cùisean measaidh an aghaidh plugan agus aithris toraidhean le sgòr'
    'prune:Thoir air falbh eisimeileachdan fèin-stàlaichte nach eil a dhìth tuilleadh'
    'autoremove:Thoir air falbh eisimeileachdan fèin-stàlaichte nach eil a dhìth tuilleadh (ainm eile airson prune)'
    'tag:Cruthaich taga git {name}--v{version} airson sgaoileadh plugan'
    'test:Ruith deuchainnean mod'
    'help:Seall cobhair'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Seall cobhair]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'àitheantan plugin' plugin_commands
      ;;
    args)
      case $words[1] in
        validate)
          _arguments \
            '--strict[Dèilig ri rabhaidhean mar mhearachdan (còd fàgail 1)]' \
            '--json[Cuir a-mach an aithisg dhearbhaidh mar JSON (na h-aon chòdan fàgail)]' \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:slighe:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Sgòp stàlaidh]:sgòp:(user project local)' \
            '*--config[Suidhich roghainn userConfig a chaidh a ghairm ann am manifest a'\'' phlugain (ath-dhèante)]:key=value:' \
            '(-y --yes)'{-y,--yes}'[Gabh ris an àithne a chaidh a ghairm leis a'\'' mhargadh '\''s a tha ga sealltainn gun bhrosnachadh dearbhaidh]' \
            '--json[Clò-bhuail aon loidhne toraidh a ghabhas leughadh le inneal an àite na teachdaireachd daonna]' \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:plugan:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Sgòp stàlaidh]:sgòp:(user project local)' \
            '--keep-data[Glèidh eòlaire dàta maireannach a'\'' phlugain]' \
            '--prune[Thoir air falbh cuideachd eisimeileachdan fèin-stàlaichte nach eil a dhìth tuilleadh]' \
            '(-y --yes)'{-y,--yes}'[Leum thairis air brosnachadh dearbhaidh --prune]' \
            '--json[Clò-bhuail aon loidhne toraidh a ghabhas leughadh le inneal an àite na teachdaireachd daonna (chan ann le --prune)]' \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:plugan:_claude_installed_plugins'
          ;;
        enable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Sgòp stàlaidh]:sgòp:(user project local)' \
            '--json[Clò-bhuail aon loidhne toraidh a ghabhas leughadh le inneal an àite na teachdaireachd daonna]' \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:plugan:_claude_installed_plugins'
          ;;
        disable)
          _arguments \
            '(-a --all)'{-a,--all}'[Cuir à comas gach plugan a tha an comas]' \
            '(-s --scope)'{-s,--scope}'[Sgòp stàlaidh]:scope:(user project local)' \
            '--json[Clò-bhuail aon loidhne toraidh a ghabhas leughadh le inneal an àite na teachdaireachd daonna]' \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '::plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Sgòp stàlaidh]:sgòp:(user project local managed)' \
            '(-y --yes)'{-y,--yes}'[Gabh ris an àithne a chaidh a ghairm leis a'\'' mhargadh '\''s a tha ga sealltainn gun bhrosnachadh dearbhaidh]' \
            '--json[Clò-bhuail aon loidhne toraidh a ghabhas leughadh le inneal an àite na teachdaireachd daonna]' \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:plugan:_claude_installed_plugins'
          ;;
        list)
          _arguments \
            '--json[Cuir a-mach mar JSON]' \
            '--available[Gabh a-steach plugain ri fhaighinn bho mhargaidhean (feumaidh --json)]' \
            '(-h --help)'{-h,--help}'[Seall cobhair]'
          ;;
        prune|autoremove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Bearr aig sgòp]:scope:(user project local)' \
            '--dry-run[Liostaich na rachadh a thoirt air falbh gun a thoirt air falbh]' \
            '(-y --yes)'{-y,--yes}'[Leum thairis air a'\'' bhrosnachadh dearbhaidh]' \
            '(-h --help)'{-h,--help}'[Seall cobhair]'
          ;;
        configure)
          _arguments \
            '--json[Cuir a-mach mar JSON]' \
            '--values-stdin[Leugh luachan roghainn bho stdin mar nì JSON de shreangan aon-loidhne; cumaidh roghainnean a chaidh fhàgail às an luachan]' \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:plugan:_claude_installed_plugins'
          ;;
        init|new)
          _arguments \
            '--description[Tuairisgeul a'\'' mhanifest]:text:' \
            '--author[Ainm an ùghdair (roghainn bhunaiteach: git config user.name)]:name:' \
            '--author-email[Post-d an ùghdair (roghainn bhunaiteach: git config user.email)]:email:' \
            '--with[Co-phàirtean ri sgafall cuideachd]:components:' \
            '(-f --force)'{-f,--force}'[Sgrìobh thairis air .claude-plugin/ a tha ann mu thràth aig an targaid]' \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:ainm:'
          ;;
        eval)
          _arguments \
            '--case[Sìolaidh cùisean a rèir glob ainm]:glob:' \
            '*--tag[Sìolaidh cùisean a rèir taga (ath-dhèante)]:tag:' \
            '--runs[Tar-àithn an àireamh de ruithean gach cùis (roghainn bhunaiteach: case.runs, no 3 mura h-eil)]:n:' \
            '(-j --concurrency)'{-j,--concurrency}'[Ruith suas ri n ruithean àidseant aig an aon àm (1-8; roghainn bhunaiteach 1)]:n:' \
            '--model[Tar-àithn am modail airson gach cùis]:model:_claude_model_names' \
            '--judge-model[Tar-àithn modail a'\'' ghrèidiche LLM (roghainn bhunaiteach: haiku)]:model:_claude_model_names' \
            '--max-cost-usd[Mullach cosgais teann; sguir dheth agus aithris toraidhean pàirteach ma ruigear e (còd fàgail 2)]:usd:' \
            '--output-dir[Eòlaire airson aggregate-result.json]:dir:_directories' \
            '--eval-dir[Ainm an eòlaire (fon phlugan) anns a bheil na cùisean measaidh]:dir:' \
            '--json[Clò-bhuail toradh slàn na ruith mar JSON gu stdout, no sgrìobh e dhan fhaidhle .json seo]::path:_files' \
            '--threshold[Fàg le còd fàgail 1 ma tha sgòr cùis sam bith fon stairsneach seo (roghainn bhunaiteach: 1.0)]:threshold:' \
            '*--allow-tools[Ceadachadh gnìomhaiche airson innealan fo gheata (Bash, Write, Edit, WebFetch, mcp__*)]:tools:' \
            '(--no-scaffold)--scaffold[Ruith scaffold_script gach cùis (ruithidh e bash a thug an t-ùghdar seachad fon chunntas agad fhèin; dheth mar roghainn bhunaiteach)]' \
            '(--scaffold)--no-scaffold[Leum thairis air scaffold_script gu soilleir]' \
            '--trust-plugin[Dearbh gu bheil earbsa agad sa phlugan seo agus san t-sreath mheasaidh aige, a'\'' leum thairis air brosnachadh earbsa a'\'' chiad ruith (airson CI)]' \
            '--ablation[Ruith buidheann coimeasaidh bun-loidhne gun phlugan agus aithris an diofar sgòir]:mode:(none with-without)' \
            '--mocks[Riochdairean brèige an àite frithealaichean MCP, bho <eval dir>/mocks/]:mode:(record off)' \
            '--allow-real-servers[Le --mocks record: tòisich cuideachd na pròiseasan frithealaiche MCP fìor aig nach eil riochdaire brèige]' \
            '--keep-temp[Glèidh eòlairean an sgafaill airson dì-bhugachadh]' \
            '--verbose[Clàraich tachartasan lorg gach teachdaireachd gu loga an dì-bhugachaidh]' \
            '--report[Sgrìobh an aithisg HTML fhèin-ghlèidhte dhan t-slighe seo an àite eòlaire nan toraidhean]:path:_files' \
            '(--no-publish)--publish-report[Iarr cuideachd gun tèid an aithisg fhoillseachadh air claude.ai]' \
            '(--publish-report)--no-publish[Cùm an aithisg HTML ionadail a-mhàin; leum thairis air a foillseachadh air claude.ai]' \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '::target: _alternative "plugins\:installed plugin\:_claude_installed_plugins" "files\:path\:_files"'
          ;;
        tag)
          _arguments \
            '--push[Brùth an taga gu --remote às dèidh a chruthachadh]' \
            '--dry-run[Clò-bhuail na rachadh a thagadh gun a chruthachadh]' \
            '(-f --force)'{-f,--force}'[Leum thairis air na sgrùdaidhean craobh-obrach shalach agus taga a tha ann mu thràth]' \
            '(-m --message)'{-m,--message}'[Teachdaireachd nòtachaidh an taga (cleachd %s airson an tionndaidh)]:msg:' \
            '--remote[An t-ionad cèin gus brùthadh thuige le --push]:name:' \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '::path:_files'
          ;;
        test)
          _arguments \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '::dir:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_plugin_marketplace() {
  local -a marketplace_commands
  marketplace_commands=(
    'add:Cuir margadh bho URL, slighe, no stòr-lann GitHub'
    'list:Liostaich margaidhean air an rèiteachadh'
    'remove:Thoir air falbh margadh air a rèiteachadh'
    'rm:Thoir air falbh margadh air a rèiteachadh (ainm eile airson remove)'
    'update:Ùraich margadh bhon tùs - ùraich a h-uile ma nach eilear ainm a'\'' sònrachadh'
    'help:Seall cobhair'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Seall cobhair]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'àitheantan marketplace' marketplace_commands
      ;;
    args)
      case $words[1] in
        add)
          _arguments \
            '--sparse[Cuingich an checkout ri eòlairean sònraichte le git sparse-checkout (airson monorepos)]:paths:' \
            '--scope[Càite an tèid am margadh a ghairm]:scope:(user project local)' \
            '--claudeai[Cuir ris am margadh leis an ainm seo a tha claude.ai ag òstadh dhut]' \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:tùs:'
          ;;
        list)
          _arguments \
            '--json[Cuir a-mach mar JSON]' \
            '(-h --help)'{-h,--help}'[Seall cobhair]'
          ;;
        remove|rm)
          _arguments \
            '--scope[Thoir air falbh gairm a'\'' mhargaidh bho sgòp roghainnean sònraichte (fàg às gus a thoirt air falbh bho gach sgòp)]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:ainm:'
          ;;
        update)
          _arguments \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '::ainm:'
          ;;
      esac
      ;;
  esac
}

_claude_install() {
  _arguments \
    '--force[Sparr stàladh eadhon ma tha e air a stàladh mu thràth]' \
    '(-h --help)'{-h,--help}'[Seall cobhair]' \
    '::targaid:(stable latest)'
}

_claude_agents() {
  _arguments \
    '*--add-dir[Eòlaire a bharrachd gus cead inntrigidh innealan ann an seiseanan air an cur a-mach]:eòlaire:_directories' \
    '--agent[Àidseant bunaiteach airson seiseanan air an cur a-mach bho shealladh àidseant]:àidseant:_claude_agent_names' \
    '--all[Le --json: gabh a-steach cuideachd seiseanan cùil crìochnaichte]' \
    '--allow-dangerously-skip-permissions[Dèan modh seachnadh-cheadan ri fhaighinn do sheiseanan air an cur a-mach]' \
    '--cwd[Seall a-mhàin seiseanan cùil a thòisich fon t-slighe]:slighe:_directories' \
    '--dangerously-skip-permissions[Alias airson --permission-mode bypassPermissions]' \
    '--effort[Ìre oidhirp bhunaiteach airson seiseanan air an cur a-mach]:ìre:(low medium high xhigh max)' \
    '--json[Clò-bhuail seiseanan gnìomhach mar sreath JSON agus fàg]' \
    '*--mcp-config[Rèiteachadh frithealaiche MCP ri chur an sàs air seiseanan air an cur a-mach]:rèiteachadh:' \
    '--model[Modail bunaiteach airson seiseanan air an cur a-mach bho shealladh àidseant]:modail:_claude_model_names' \
    '--permission-mode[Modh cead bunaiteach airson seiseanan air an cur a-mach]:modh:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Luchdaich plugain bho eòlaire airson an t-seallaidh àidseant agus seiseanan air an cur a-mach]:slighe:_directories' \
    '--setting-sources[Liosta air a sgaradh le cromag de thùsan roghainnean ri luchdachadh (user, project, local)]:tùsan:' \
    '--settings[Faidhle roghainnean no sreang JSON ri chur an sàs]:faidhle-no-json:_files' \
    '--strict-mcp-config[Cleachd a-mhàin frithealaichean MCP bho --mcp-config ann an seiseanan air an cur a-mach]' \
    '--restricted[Tòisich seiseanan air an cur a-mach ann am modh cuingichte]' \
    '(-h --help)'{-h,--help}'[Seall cobhair airson àithne]'
}

_claude_auth() {
  local -a auth_commands
  auth_commands=(
    'login:Clàraich a-steach don chunntas Anthropic agad'
    'logout:Clàraich a-mach às a'\'' chunntas Anthropic agad'
    'status:Seall staid dearbhaidh'
    'help:Seall cobhair'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Seall cobhair airson àithne]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'àitheantan auth' auth_commands
      ;;
    args)
      case $words[1] in
        login)
          _arguments \
            '--email[Ro-lìon an seòladh post-d air duilleag a'\'' chlàraidh a-steach]:email:' \
            '--sso[Sparr sruth clàraidh a-steach SSO]' \
            '(--claudeai)--console[Cleachd Anthropic Console (bileachadh cleachdadh API) an àite fo-sgrìobhadh Claude]' \
            '(--console)--claudeai[Cleachd fo-sgrìobhadh Claude (roghainn bhunaiteach)]' \
            '(-h --help)'{-h,--help}'[Seall cobhair airson àithne]'
          ;;
        status)
          _arguments \
            '(--text)--json[Cuir a-mach mar JSON (roghainn bhunaiteach)]' \
            '(--json)--text[Cuir a-mach mar theacsa a ghabhas leughadh le daoine]' \
            '(-h --help)'{-h,--help}'[Seall cobhair airson àithne]'
          ;;
        logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Seall cobhair airson àithne]'
          ;;
      esac
      ;;
  esac
}

_claude_auto_mode() {
  local -a auto_mode_commands
  auto_mode_commands=(
    'config:Clò-bhuail rèiteachadh èifeachdach modh fèin-obrachaidh mar JSON'
    'critique:Faigh fios-air-ais IF air na riaghailtean modh fèin-obrachaidh gnàthaichte agad'
    'defaults:Clò-bhuail riaghailtean bunaiteach modh fèin-obrachaidh mar JSON'
    'reset:Ath-shuidhich rèiteachadh modh fèin-obrachaidh gu na bun-roghainnean a chaidh a lìbhrigeadh'
    'help:Seall cobhair'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Seall cobhair airson àithne]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'àitheantan auto-mode' auto_mode_commands
      ;;
    args)
      case $words[1] in
        critique)
          _arguments \
            '--model[Tar-àithn dè am modail a thèid a chleachdadh]:model:_claude_model_names' \
            '(-h --help)'{-h,--help}'[Seall cobhair airson àithne]'
          ;;
        defaults)
          _arguments \
            '--label[Seall a-mhàin riaghailtean aig a bheil leubail a thòisicheas leis an ro-leasachan seo (gun aire do litrichean mòra/beaga)]:prefix:' \
            '(-h --help)'{-h,--help}'[Seall cobhair airson àithne]'
          ;;
        reset)
          _arguments \
            '(-y --yes)'{-y,--yes}'[Leum thairis air a'\'' bhrosnachadh dearbhaidh]' \
            '(-h --help)'{-h,--help}'[Seall cobhair airson àithne]'
          ;;
        config)
          _arguments \
            '(-h --help)'{-h,--help}'[Seall cobhair airson àithne]'
          ;;
      esac
      ;;
  esac
}

_claude_gateway() {
  _arguments \
    '--config[Slighe gu rèiteachadh YAML geata]:slighe:_files' \
    '(-h --help)'{-h,--help}'[Seall cobhair airson àithne]'
}

_claude_project() {
  local -a project_commands
  project_commands=(
    'purge:Sguab às gach staid Claude Code airson pròiseact (tar-sgrìobhaidhean, gnìomhan, eachdraidh faidhle, innteart rèiteachaidh)'
    'help:Seall cobhair'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Seall cobhair airson àithne]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'àitheantan project' project_commands
      ;;
    args)
      case $words[1] in
        purge)
          _arguments \
            '--dry-run[Liostaich na rachadh a sguabadh às gun dad a sguabadh às]' \
            '(-y --yes)'{-y,--yes}'[Leum thairis air a'\'' bhrosnachadh dearbhaidh]' \
            '(-i --interactive)'{-i,--interactive}'[Iarr dearbhadh airson gach nì mus tèid a sguabadh às]' \
            '(1)--all[Glan às an staid airson gach pròiseact (chan urrainnear a chleachdadh còmhla ri slighe)]' \
            '(-h --help)'{-h,--help}'[Seall cobhair airson àithne]' \
            '(--all)::path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Clò-bhuail an luchd bugs.json amh an àite toraidhean cruthaichte]' \
    '--timeout[Àireamh as motha de mhionaidean ri feitheamh gus an crìochnaich an lèirmheas (roghainn bhunaiteach: 45)]:minutes:' \
    '(--no-post)--post[Postaich toraidhean an lèirmheis chrìochnaichte dhan PR às d'\'' ainm fhèin (targaidean PR a-mhàin; aon bheachd sìmplidh, chan e lèirmheas)]' \
    '(--post)--no-post[Na postaich na toraidhean dhan PR (an roghainn bhunaiteach)]' \
    '(-h --help)'{-h,--help}'[Seall cobhair airson àithne]' \
    '1:targaid:'
}

_claude_respawn() {
  _arguments \
    '(1)--all[Ath-thòisich gach seisean cùil a tha a'\'' ruith]' \
    '(-h --help)'{-h,--help}'[Seall cobhair airson àithne]' \
    '(--all)::session:_claude_background_sessions'
}

_claude_rm() {
  _arguments \
    '--discard-unpushed[Tilg air falbh cuideachd geallaidhean gun bhrùthadh agus atharraichean gun ghealladh na craoibh-obrach (thoir seachad an commit@worktree-id a dh'\''aithris claude rm roimhe)]:commit@worktree-id:' \
    '--force-remove-worktree[Sguab às eòlaire na craoibh-obrach ged nach b'\'' urrainn don dubhan WorktreeRemove no git a thoirt air falbh (thoir seachad an worktree-id a dh'\''aithris claude rm roimhe)]:worktree-id:' \
    '(-h --help)'{-h,--help}'[Seall cobhair airson àithne]' \
    '1:session:_claude_background_sessions'
}

_claude_import() {
  _arguments \
    '--dry-run[Seall na rachadh a dh'\''ion-phortadh gun dad a sgrìobhadh]' \
    '--yes[Leum thairis air an roghnaichear eadar-ghnìomhach (air uachdaran gun cheann, thoir seachad --yes=<digest> bhon ro-shealladh /import)]' \
    '(-h --help)'{-h,--help}'[Seall cobhair airson àithne]' \
    '::source:(codex gemini cursor)'
}

(( $+_comps[claude] )) || compdef _claude claude
