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
    'mcp:Rèitich agus stiùir frithealaichean MCP'
    'plugin:Stiùir plugain Claude Code'
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
    '--replay-user-messages[Ath-chuir teachdaireachdan cleachdaiche bho stdin air stdout airson dearbhadh]'
    '--allowed-tools[Liosta air a sgaradh le cromag no àite de dh'\''ainmean innealan a tha ceadaichte (m.e., "Bash(git:*) Edit")]:innealan:'
    '--allowedTools[Liosta air a sgaradh le cromag no àite de dh'\''ainmean innealan a tha ceadaichte (cruth camelCase)]:innealan:'
    '--tools[Sònraich liosta de dh'\''innealan ri fhaighinn bhon t-seata togail a-steach. Modh clò-bhualaidh a-mhàin]:innealan:'
    '--disallowed-tools[Liosta air a sgaradh le cromag no àite de dh'\''ainmean innealan nach eil ceadaichte (m.e., "Bash(git:*) Edit")]:innealan:'
    '--disallowedTools[Liosta air a sgaradh le cromag no àite de dh'\''ainmean innealan nach eil ceadaichte (cruth camelCase)]:innealan:'
    '--mcp-config[Luchdaich frithealaichean MCP bho fhaidhle JSON no sreang JSON (air a sgaradh le àite)]:rèiteachaidhean:'
    '--system-prompt[Brosnachadh siostam airson a chleachdadh airson an t-seisein]:brosnachadh:'
    '--append-system-prompt[Cuir brosnachadh siostam ris a'\'' bhrosnachadh siostam bhunaiteach]:brosnachadh:'
    '--permission-mode[Modh cead airson a chleachdadh airson an t-seisein]:modh:(acceptEdits bypassPermissions default dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Lean air adhart leis a'\'' chòmhradh as ùire]'
    '(-r --resume)'{-r,--resume}'[Ath-thòisich còmhradh - sònraich ID seisein no tagh gu h-eadar-ghnìomhach]:IDseisein:_claude_sessions'
    '--fork-session[Cruthaich ID seisein ùr an àite ID seisein tùsail ath-chleachdadh nuair a thòisicheas tu a-rithist (le --resume no --continue)]'
    '--model[Modail airson an t-seisein làithreach. Sònraich alias airson a'\'' mhodail as ùire (m.e., '\''sonnet'\'' no '\''opus'\'')]:modail:'
    '--fallback-model[Cuir an comas tuiteam fèin-ghluasadach chun mhodail a chaidh a shònrachadh nuair a tha am modail bunaiteach air a luchdachadh thar a chomais (--print a-mhàin)]:modail:'
    '--settings[Slighe gu faidhle JSON roghainnean no sreang JSON gus roghainnean a bharrachd a luchdachadh]:faidhle-no-json:_files'
    '--add-dir[Eòlaireann a bharrachd gus cead inntrigidh innealan]:eòlaireann:_directories'
    '--ide[Fèin-cheangail ri IDE aig toiseach tòiseachaidh ma tha dìreach aon IDE dligheach ri fhaighinn]'
    '--strict-mcp-config[Cleachd dìreach frithealaichean MCP bho --mcp-config agus leig seachad gach roghainn MCP eile]'
    '--session-id[ID seisein sònraichte airson a chleachdadh airson a'\'' chòmhraidh (feumaidh e bhith na UUID dligheach)]:uuid:'
    '--agents[Nì JSON a mhìnicheas àidseantan gnàthaichte]:json:'
    '--setting-sources[Liosta air a sgaradh le cromag de thùsan roghainnean ri luchdachadh (user, project, local)]:tùsan:'
    '--plugin-dir[Eòlaire gus plugain a luchdachadh às airson an t-seisein seo a-mhàin (ath-dhèante)]:slighean:_directories'
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
      esac
      ;;
  esac
}
_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:Dearbh plugan no ainm-clàr margaidh'
    'marketplace:Stiùir margaidhean Claude Code'
    'install:Stàlaich plugan bho mhargaidhean ri fhaighinn'
    'i:Stàlaich plugan bho mhargaidhean ri fhaighinn (geàrr-slighe airson install)'
    'uninstall:Dì-stàlaich plugan air a stàladh'
    'remove:Dì-stàlaich plugan air a stàladh (ainm eile airson uninstall)'
    'enable:Cuir an comas plugan air a chur à comas'
    'disable:Cuir à comas plugan air a chur an comas'
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
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:plugan:'
          ;;
        uninstall|remove)
          _arguments \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:plugan:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-h --help)'{-h,--help}'[Seall cobhair]' \
            '1:plugan:_claude_installed_plugins'
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
(( $+_comps[claude] )) || compdef _claude claude
