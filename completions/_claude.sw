#compdef claude
# Kazi za ukamilishaji zinazobadilika
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
    'mcp:Sanidi na simamia seva za MCP'
    'plugin:Simamia programu-jalizi za Claude Code'
    'setup-token:Weka alama ya uthibitishaji wa muda mrefu (inahitaji usajili wa Claude)'
    'doctor:Ukaguzi wa afya kwa auto-updater ya Claude Code'
    'update:Angalia na sakinisha masasisho'
    'install:Sakinisha ujenzi asili wa Claude Code'
  )
  local -a main_options
  main_options=(
    '(-d --debug)'{-d,--debug}'[Washa mtindo wa utatuzi na kichujio cha jamii cha hiari (mfano: "api,hooks" au "!statsig,!file")]:filter:'
    '--verbose[Batilisha mpangilio wa mtindo wa maneno mengi kutoka kwa faili ya usanidi]'
    '(-p --print)'{-p,--print}'[Chapisha jibu na utoke (kwa matumizi na mifereji). Kumbuka: tumia tu katika saraka zinazotunzwa]'
    '--output-format[Muundo wa matokeo (pamoja na --print): "text" (chaguo-msingi), "json" (matokeo moja), au "stream-json" (mkondo wa wakati halisi)]:format:(text json stream-json)'
    '--json-schema[Muundo wa JSON kwa uthibitishaji wa matokeo yaliyopangwa]:schema:'
    '--include-partial-messages[Jumuisha vipande vya ujumbe vya sehemu vinavyowasili (pamoja na --print na --output-format=stream-json)]'
    '--input-format[Muundo wa ingizo (pamoja na --print): "text" (chaguo-msingi) au "stream-json" (mkondo wa ingizo wa wakati halisi)]:format:(text stream-json)'
    '--mcp-debug[\[Haipendekezi tena. Tumia --debug badala yake\] Washa mtindo wa utatuzi wa MCP (inaonyesha makosa ya seva za MCP)]'
    '--dangerously-skip-permissions[Ruka ukaguzi wote wa ruhusa. Inashauriwa tu kwa sanduku za uchawi bila upatikanaji wa mtandao]'
    '--allow-dangerously-skip-permissions[Wezesha chaguo la kuruka ukaguzi wa ruhusa bila kuwezesha kwa chaguo-msingi]'
    '--replay-user-messages[Tuma tena ujumbe wa mtumiaji kutoka stdin kwenye stdout kwa uthibitishaji]'
    '--allowed-tools[Orodha ya majina ya zana zinazoruhusiwa yaliyotenganishwa kwa koma au nafasi (mfano: "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Orodha ya majina ya zana zinazoruhusiwa yaliyotenganishwa kwa koma au nafasi (muundo wa camelCase)]:tools:'
    '--tools[Bainisha orodha ya zana zinazopatikana kutoka kwa seti iliyojengwa ndani. Mtindo wa kuchapisha tu]:tools:'
    '--disallowed-tools[Orodha ya majina ya zana ambazo haziruhusiwi yaliyotenganishwa kwa koma au nafasi (mfano: "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Orodha ya majina ya zana ambazo haziruhusiwi yaliyotenganishwa kwa koma au nafasi (muundo wa camelCase)]:tools:'
    '--mcp-config[Pakia seva za MCP kutoka kwa faili ya JSON au mfuatano (uliotenganishwa kwa nafasi)]:configs:'
    '--system-prompt[Orodhesha mfumo wa kutumia kwa kipindi]:prompt:'
    '--append-system-prompt[Ongeza orodhesha mfumo kwenye orodhesha chaguo-msingi ya mfumo]:prompt:'
    '--permission-mode[Mtindo wa ruhusa wa kutumia kwa kipindi]:mode:(acceptEdits bypassPermissions default dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Endelea na mazungumzo ya hivi karibuni]'
    '(-r --resume)'{-r,--resume}'[Rudisha mazungumzo - bainisha kitambulisho cha kipindi au chagua kwa njia ya mwingiliano]:sessionId:_claude_sessions'
    '--fork-session[Unda kitambulisho kipya cha kipindi badala ya kutumia tena kitambulisho cha asili cha kipindi wakati wa kurudisha (pamoja na --resume au --continue)]'
    '--model[Modeli kwa kipindi cha sasa. Bainisha jina-mbadala kwa modeli mpya (mfano: '\''sonnet'\'' au '\''opus'\'')]:model:'
    '--fallback-model[Wezesha kubadilika kiotomatiki kwa modeli iliyobainishwa wakati modeli chaguo-msingi imelemewa (--print tu)]:model:'
    '--settings[Njia ya faili ya JSON ya mipangilio au mfuatano wa JSON wa kupakia mipangilio ya ziada]:file-or-json:_files'
    '--add-dir[Saraka za ziada za kuruhusu upatikanaji wa zana]:directories:_directories'
    '--ide[Unganisha-kiotomatiki kwa IDE wakati wa kuanzisha ikiwa kuna IDE moja halali inapatikana]'
    '--strict-mcp-config[Tumia seva za MCP kutoka kwa --mcp-config tu na upuuzie mipangilio mingine yote ya MCP]'
    '--session-id[Kitambulisho mahususi cha kipindi cha kutumia kwa mazungumzo (lazima iwe UUID halali)]:uuid:'
    '--agents[Kipengele cha JSON kinachobainisha wakala maalum]:json:'
    '--setting-sources[Orodha ya vyanzo vya mipangilio iliyotenganishwa kwa koma ya kupakia (user, project, local)]:sources:'
    '--plugin-dir[Saraka ya kupakia programu-jalizi kutoka kwa kipindi hiki tu (inaweza kurudiwa)]:paths:_directories'
    '(-v --version)'{-v,--version}'[Toa nambari ya toleo]'
    '(-h --help)'{-h,--help}'[Onyesha msaada kwa amri]'
  )
  _arguments -C \
    $main_options \
    '1: :->command' \
    '*::arg:->args'
  case $state in
    command)
      _describe -t commands 'amri za claude' main_commands
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
          _message "hakuna hoja"
          ;;
      esac
      ;;
  esac
}
_claude_mcp() {
  local -a mcp_commands
  mcp_commands=(
    'serve:Anzisha seva ya MCP ya Claude Code'
    'add:Ongeza seva ya MCP kwa Claude Code'
    'remove:Ondoa seva ya MCP'
    'list:Orodhesha seva za MCP zilizosanidiwa'
    'get:Pata maelezo ya seva ya MCP'
    'add-json:Ongeza seva ya MCP (stdio au SSE) kwa mfuatano wa JSON'
    'add-from-claude-desktop:Leta seva za MCP kutoka kwa Claude Desktop (Mac na WSL tu)'
    'reset-project-choices:Weka upya seva zote za kipindi cha mradi (zilizoidhinishwa/kukataliwa) (.mcp.json) katika mradi huu'
    'help:Onyesha msaada'
  )
  local curcontext="$curcontext" state line
  typeset -A opt_args
  _arguments -C \
    '(-h --help)'{-h,--help}'[Onyesha msaada]' \
    '1: :->command' \
    '*::arg:->args'
  case $state in
    command)
      _describe -t commands 'amri za mcp' mcp_commands
      ;;
    args)
      case $words[1] in
        serve)
          _arguments \
            '(-d --debug)'{-d,--debug}'[Washa mtindo wa utatuzi]' \
            '--verbose[Batilisha mpangilio wa mtindo wa maneno mengi kutoka kwa faili ya usanidi]' \
            '(-h --help)'{-h,--help}'[Onyesha msaada]'
          ;;
        add)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Upeo wa usanidi (local, user, project)]:scope:(local user project)' \
            '(-t --transport)'{-t,--transport}'[Aina ya usafirishaji (stdio, sse, http)]:transport:(stdio sse http)' \
            '(-e --env)'{-e,--env}'[Weka thamani badilika ya mazingira (mfano: -e KEY=value)]:env:' \
            '(-H --header)'{-H,--header}'[Weka kichwa cha WebSocket]:header:' \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:name:' \
            '2:commandOrUrl:' \
            '*:args:'
          ;;
        remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Upeo wa usanidi (local, user, project) - ondoa kutoka kwa upeo uliopo ikiwa haujabainishwa]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:name:_claude_mcp_servers'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Onyesha msaada]'
          ;;
        get)
          _arguments \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:name:_claude_mcp_servers'
          ;;
        add-json)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Upeo wa usanidi (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:name:' \
            '2:json:'
          ;;
        add-from-claude-desktop)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Upeo wa usanidi (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Onyesha msaada]'
          ;;
        reset-project-choices)
          _arguments \
            '(-h --help)'{-h,--help}'[Onyesha msaada]'
          ;;
      esac
      ;;
  esac
}
_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:Thibitisha programu-jalizi au faharasa ya soko'
    'marketplace:Simamia masoko ya Claude Code'
    'install:Sakinisha programu-jalizi kutoka kwa masoko yanayopatikana'
    'i:Sakinisha programu-jalizi kutoka kwa masoko yanayopatikana (fupi kwa install)'
    'uninstall:Ondoa programu-jalizi iliyosakinishwa'
    'remove:Ondoa programu-jalizi iliyosakinishwa (jina-mbadala kwa uninstall)'
    'enable:Wezesha programu-jalizi iliyozimwa'
    'disable:Zima programu-jalizi iliyowashwa'
    'help:Onyesha msaada'
  )
  local curcontext="$curcontext" state line
  typeset -A opt_args
  _arguments -C \
    '(-h --help)'{-h,--help}'[Onyesha msaada]' \
    '1: :->command' \
    '*::arg:->args'
  case $state in
    command)
      _describe -t commands 'amri za plugin' plugin_commands
      ;;
    args)
      case $words[1] in
        validate)
          _arguments \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:plugin:_claude_installed_plugins'
          ;;
      esac
      ;;
  esac
}
_claude_plugin_marketplace() {
  local -a marketplace_commands
  marketplace_commands=(
    'add:Ongeza soko kutoka kwa URL, njia, au hifadhi ya GitHub'
    'list:Orodhesha masoko yaliyosanidiwa'
    'remove:Ondoa soko lililosaidiwa'
    'rm:Ondoa soko lililosaidiwa (jina-mbadala kwa remove)'
    'update:Sasisha soko kutoka kwa chanzo - sasisha vyote ikiwa hakuna jina lililotajwa'
    'help:Onyesha msaada'
  )
  local curcontext="$curcontext" state line
  typeset -A opt_args
  _arguments -C \
    '(-h --help)'{-h,--help}'[Onyesha msaada]' \
    '1: :->command' \
    '*::arg:->args'
  case $state in
    command)
      _describe -t commands 'amri za marketplace' marketplace_commands
      ;;
    args)
      case $words[1] in
        add)
          _arguments \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Onyesha msaada]'
          ;;
        remove|rm)
          _arguments \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:name:'
          ;;
        update)
          _arguments \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '::name:'
          ;;
      esac
      ;;
  esac
}
_claude_install() {
  _arguments \
    '--force[Lazimisha usakinishaji hata kama tayari umesakinishwa]' \
    '(-h --help)'{-h,--help}'[Onyesha msaada]' \
    '::target:(stable latest)'
}
(( $+_comps[claude] )) || compdef _claude claude
