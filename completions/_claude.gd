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
    'mcp:Rèitich agus stiùir frithealaichean MCP'
    'plugin:Stiùir plugain Claude Code'
    'agents:Stiùir àidseantan cùil'
    'auth:Stiùir dearbhadh'
    'auto-mode:Sgrùd no ath-shuidhich rèiteachadh seòrsaiche modh fèin-obrachaidh'
    'gateway:Ruith an geata dearbhaidh/cian-thomhais fiosrachaidh na h-iomairt'
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
    '--max-budget-usd[An t-suim dolar as motha ri chosg air gairmean API (--print a-mhàin)]:suim:'
    '--replay-user-messages[Ath-chuir teachdaireachdan cleachdaiche bho stdin air stdout airson dearbhadh]'
    '--allowed-tools[Liosta air a sgaradh le cromag no àite de dh'\''ainmean innealan a tha ceadaichte (m.e., "Bash(git:*) Edit")]:innealan:'
    '--allowedTools[Liosta air a sgaradh le cromag no àite de dh'\''ainmean innealan a tha ceadaichte (cruth camelCase)]:innealan:'
    '--tools[Sònraich liosta de dh'\''innealan ri fhaighinn bhon t-seata togail a-steach. Modh clò-bhualaidh a-mhàin]:innealan:'
    '--disallowed-tools[Liosta air a sgaradh le cromag no àite de dh'\''ainmean innealan nach eil ceadaichte (m.e., "Bash(git:*) Edit")]:innealan:'
    '--disallowedTools[Liosta air a sgaradh le cromag no àite de dh'\''ainmean innealan nach eil ceadaichte (cruth camelCase)]:innealan:'
    '--mcp-config[Luchdaich frithealaichean MCP bho fhaidhle JSON no sreang JSON (air a sgaradh le àite)]:rèiteachaidhean:'
    '--system-prompt[Brosnachadh siostam airson a chleachdadh airson an t-seisein]:brosnachadh:'
    '--append-system-prompt[Cuir brosnachadh siostam ris a'\'' bhrosnachadh siostam bhunaiteach]:brosnachadh:'
    '--permission-mode[Modh cead airson a chleachdadh airson an t-seisein]:modh:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Lean air adhart leis a'\'' chòmhradh as ùire]'
    '(-r --resume)'{-r,--resume}'[Ath-thòisich còmhradh - sònraich ID seisein no tagh gu h-eadar-ghnìomhach]:IDseisein:_claude_sessions'
    '--fork-session[Cruthaich ID seisein ùr an àite ID seisein tùsail ath-chleachdadh nuair a thòisicheas tu a-rithist (le --resume no --continue)]'
    '--no-session-persistence[Cuir à comas maireannachd seisein - cha tèid seiseanan a shàbhaladh (--print a-mhàin)]'
    '--model[Modail airson an t-seisein làithreach. Sònraich alias airson a'\'' mhodail as ùire (m.e., '\''sonnet'\'' no '\''opus'\'')]:modail:'
    '--agent[Àidseant airson an t-seisein làithreach. Tar-àithnidh e an suidheachadh '\''agent'\'']:àidseant:'
    '--betas[Bannan-cinn beta ri ghabhail a-steach ann an iarrtasan API (luchd-cleachdaidh iuchair API a-mhàin)]:betas:'
    '--fallback-model[Cuir an comas tuiteam fèin-ghluasadach chun mhodail a chaidh a shònrachadh nuair a tha am modail bunaiteach air a luchdachadh thar a chomais (--print a-mhàin)]:modail:'
    '--settings[Slighe gu faidhle JSON roghainnean no sreang JSON gus roghainnean a bharrachd a luchdachadh]:faidhle-no-json:_files'
    '--add-dir[Eòlaireann a bharrachd gus cead inntrigidh innealan]:eòlaireann:_directories'
    '--ide[Fèin-cheangail ri IDE aig toiseach tòiseachaidh ma tha dìreach aon IDE dligheach ri fhaighinn]'
    '--strict-mcp-config[Cleachd dìreach frithealaichean MCP bho --mcp-config agus leig seachad gach roghainn MCP eile]'
    '--session-id[ID seisein sònraichte airson a chleachdadh airson a'\'' chòmhraidh (feumaidh e bhith na UUID dligheach)]:uuid:'
    '--agents[Nì JSON a mhìnicheas àidseantan gnàthaichte]:json:'
    '--setting-sources[Liosta air a sgaradh le cromag de thùsan roghainnean ri luchdachadh (user, project, local)]:tùsan:'
    '--plugin-dir[Eòlaire gus plugain a luchdachadh às airson an t-seisein seo a-mhàin (ath-dhèante)]:slighean:_directories'
    '--disable-slash-commands[Cuir à comas gach àithne slais]'
    '(--bg --background)'{--bg,--background}'[Tòisich an seisean mar àidseant cùil agus till sa bhad]'
    '(-w --worktree)'{-w,--worktree}'[Cruthaich craobh-obrach git ùr airson an t-seisein seo (sònraich ainm gu roghainneil)]::ainm:'
    '--tmux[Cruthaich seisean tmux airson na craoibh-obrach (feumaidh --worktree)]'
    '(-n --name)'{-n,--name}'[Suidhich ainm-taisbeanaidh airson an t-seisein seo]:ainm:'
    '--effort[Ìre oidhirp airson an t-seisein làithreach]:ìre:(low medium high xhigh max)'
    '--debug-file[Sgrìobh logaichean dì-bhugachaidh gu slighe faidhle sònraichte (cuiridh e an comas modh dì-bhugachaidh gu fillte)]:slighe:_files'
    '--from-pr[Ath-thòisich seisean ceangailte ri PR a rèir àireamh/URL, no fosgail roghnaichear eadar-ghnìomhach]::luach:'
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
        login|logout)
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
    'install:Stàlaich plugan bho mhargaidhean ri fhaighinn'
    'i:Stàlaich plugan bho mhargaidhean ri fhaighinn (geàrr-slighe airson install)'
    'init:Sgafall plugan ùr (fèin-luchdachadh san ath sheisean)'
    'uninstall:Dì-stàlaich plugan air a stàladh'
    'remove:Dì-stàlaich plugan air a stàladh (ainm eile airson uninstall)'
    'enable:Cuir an comas plugan air a chur à comas'
    'disable:Cuir à comas plugan air a chur an comas'
    'update:Ùraich plugan chun tionndaidh as ùire'
    'eval:Ruith cùisean measaidh an aghaidh plugan agus aithris toraidhean le sgòr'
    'prune:Thoir air falbh eisimeileachdan fèin-stàlaichte nach eil a dhìth tuilleadh'
    'tag:Cruthaich taga git {name}--v{version} airson sgaoileadh plugan'
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
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:slighe:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Sgòp stàlaidh]:sgòp:(user project local)' \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:plugan:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Sgòp stàlaidh]:sgòp:(user project local)' \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:plugan:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Sgòp stàlaidh]:sgòp:(user project local)' \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:plugan:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Sgòp stàlaidh]:sgòp:(user project local managed)' \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:plugan:_claude_installed_plugins'
          ;;
        list|prune)
          _arguments \
            '(-h --help)'{-h,--help}'[Seall cobhair]'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:plugan:_claude_installed_plugins'
          ;;
        init)
          _arguments \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:ainm:'
          ;;
        eval)
          _arguments \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:targaid:'
          ;;
        tag)
          _arguments \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:slighe:_files'
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
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:tùs:'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Seall cobhair]'
          ;;
        remove|rm)
          _arguments \
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
    '--agent[Àidseant bunaiteach airson seiseanan air an cur a-mach bho shealladh àidseant]:àidseant:' \
    '--all[Le --json: gabh a-steach cuideachd seiseanan cùil crìochnaichte]' \
    '--allow-dangerously-skip-permissions[Dèan modh seachnadh-cheadan ri fhaighinn do sheiseanan air an cur a-mach]' \
    '--cwd[Seall a-mhàin seiseanan cùil a thòisich fon t-slighe]:slighe:_directories' \
    '--dangerously-skip-permissions[Alias airson --permission-mode bypassPermissions]' \
    '--effort[Ìre oidhirp bhunaiteach airson seiseanan air an cur a-mach]:ìre:(low medium high xhigh max)' \
    '--json[Clò-bhuail seiseanan gnìomhach mar sreath JSON agus fàg]' \
    '*--mcp-config[Rèiteachadh frithealaiche MCP ri chur an sàs air seiseanan air an cur a-mach]:rèiteachadh:' \
    '--model[Modail bunaiteach airson seiseanan air an cur a-mach bho shealladh àidseant]:modail:' \
    '--permission-mode[Modh cead bunaiteach airson seiseanan air an cur a-mach]:modh:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Luchdaich plugain bho eòlaire airson an t-seallaidh àidseant agus seiseanan air an cur a-mach]:slighe:_directories' \
    '--setting-sources[Liosta air a sgaradh le cromag de thùsan roghainnean ri luchdachadh (user, project, local)]:tùsan:' \
    '--settings[Faidhle roghainnean no sreang JSON ri chur an sàs]:faidhle-no-json:_files' \
    '--strict-mcp-config[Cleachd a-mhàin frithealaichean MCP bho --mcp-config ann an seiseanan air an cur a-mach]' \
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
        login|logout|status)
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
        config|critique|defaults|reset)
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
            '(-h --help)'{-h,--help}'[Seall cobhair airson àithne]' \
            '1:slighe:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Clò-bhuail an luchd bugs.json amh an àite toraidhean cruthaichte]' \
    '--timeout[Àireamh as motha de mhionaidean ri feitheamh gus an crìochnaich an lèirmheas]:mionaidean:' \
    '(-h --help)'{-h,--help}'[Seall cobhair airson àithne]' \
    '1:targaid:'
}

(( $+_comps[claude] )) || compdef _claude claude
