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
    'agents:Simamia wakala wa mandharinyuma'
    'auth:Simamia uthibitishaji'
    'auto-mode:Kagua au weka upya usanidi wa kiainishi cha hali otomatiki'
    'gateway:Endesha lango la uthibitishaji/telemetria la biashara'
    'project:Simamia hali ya mradi ya Claude Code'
    'ultrareview:Endesha ukaguzi wa msimbo wa mawakala wengi ulioko wingu na uchapishe matokeo'
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
    '--max-budget-usd[Kiasi cha juu cha dola cha kutumia kwenye simu za API (--print tu)]:amount:'
    '--replay-user-messages[Tuma tena ujumbe wa mtumiaji kutoka stdin kwenye stdout kwa uthibitishaji]'
    '--allowed-tools[Orodha ya majina ya zana zinazoruhusiwa yaliyotenganishwa kwa koma au nafasi (mfano: "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Orodha ya majina ya zana zinazoruhusiwa yaliyotenganishwa kwa koma au nafasi (muundo wa camelCase)]:tools:'
    '--tools[Bainisha orodha ya zana zinazopatikana kutoka kwa seti iliyojengwa ndani. Mtindo wa kuchapisha tu]:tools:'
    '--disallowed-tools[Orodha ya majina ya zana ambazo haziruhusiwi yaliyotenganishwa kwa koma au nafasi (mfano: "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Orodha ya majina ya zana ambazo haziruhusiwi yaliyotenganishwa kwa koma au nafasi (muundo wa camelCase)]:tools:'
    '--mcp-config[Pakia seva za MCP kutoka kwa faili ya JSON au mfuatano (uliotenganishwa kwa nafasi)]:configs:'
    '--system-prompt[Orodhesha mfumo wa kutumia kwa kipindi]:prompt:'
    '--append-system-prompt[Ongeza orodhesha mfumo kwenye orodhesha chaguo-msingi ya mfumo]:prompt:'
    '--permission-mode[Mtindo wa ruhusa wa kutumia kwa kipindi]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Endelea na mazungumzo ya hivi karibuni]'
    '(-r --resume)'{-r,--resume}'[Rudisha mazungumzo - bainisha kitambulisho cha kipindi au chagua kwa njia ya mwingiliano]:sessionId:_claude_sessions'
    '--fork-session[Unda kitambulisho kipya cha kipindi badala ya kutumia tena kitambulisho cha asili cha kipindi wakati wa kurudisha (pamoja na --resume au --continue)]'
    '--no-session-persistence[Zima uhifadhi wa kipindi - vipindi havitahifadhiwa (--print tu)]'
    '--model[Modeli kwa kipindi cha sasa. Bainisha jina-mbadala kwa modeli mpya (mfano: '\''sonnet'\'' au '\''opus'\'')]:model:'
    '--agent[Wakala kwa kipindi cha sasa. Inabatilisha mpangilio wa '\''agent'\'']:agent:'
    '--betas[Vichwa vya beta vya kujumuisha katika maombi ya API (watumiaji wa ufunguo wa API tu)]:betas:'
    '--fallback-model[Wezesha kubadilika kiotomatiki kwa modeli iliyobainishwa wakati modeli chaguo-msingi imelemewa (--print tu)]:model:'
    '--settings[Njia ya faili ya JSON ya mipangilio au mfuatano wa JSON wa kupakia mipangilio ya ziada]:file-or-json:_files'
    '--add-dir[Saraka za ziada za kuruhusu upatikanaji wa zana]:directories:_directories'
    '--ide[Unganisha-kiotomatiki kwa IDE wakati wa kuanzisha ikiwa kuna IDE moja halali inapatikana]'
    '--strict-mcp-config[Tumia seva za MCP kutoka kwa --mcp-config tu na upuuzie mipangilio mingine yote ya MCP]'
    '--session-id[Kitambulisho mahususi cha kipindi cha kutumia kwa mazungumzo (lazima iwe UUID halali)]:uuid:'
    '--agents[Kipengele cha JSON kinachobainisha wakala maalum]:json:'
    '--setting-sources[Orodha ya vyanzo vya mipangilio iliyotenganishwa kwa koma ya kupakia (user, project, local)]:sources:'
    '--plugin-dir[Saraka ya kupakia programu-jalizi kutoka kwa kipindi hiki tu (inaweza kurudiwa)]:paths:_directories'
    '--disable-slash-commands[Zima amri zote za mkwaju]'
    '(--bg --background)'{--bg,--background}'[Anzisha kipindi kama wakala wa mandharinyuma na urudi mara moja]'
    '(-w --worktree)'{-w,--worktree}'[Unda git worktree mpya kwa kipindi hiki (kwa hiari bainisha jina)]::name:'
    '--tmux[Unda kipindi cha tmux kwa worktree (inahitaji --worktree)]'
    '(-n --name)'{-n,--name}'[Weka jina la kuonyesha kwa kipindi hiki]:name:'
    '--effort[Kiwango cha juhudi kwa kipindi cha sasa]:level:(low medium high xhigh max)'
    '--debug-file[Andika kumbukumbu za utatuzi kwenye njia mahususi ya faili (huwezesha mtindo wa utatuzi kwa dhahiri)]:path:_files'
    '--from-pr[Rudisha kipindi kilichounganishwa na PR kwa nambari/URL, au fungua kichaguzi cha mwingiliano]::value:'
    '--remote-control[Anzisha kipindi cha mwingiliano na Udhibiti wa Mbali umewezeshwa (kwa hiari na jina)]::name:'
    '--remote-control-session-name-prefix[Kiambishi awali cha majina ya vipindi vya Udhibiti wa Mbali yaliyozalishwa kiotomatiki]:prefix:'
    '--chrome[Wezesha muunganisho wa Claude katika Chrome]'
    '--no-chrome[Zima muunganisho wa Claude katika Chrome]'
    '--plugin-url[Leta .zip ya programu-jalizi kutoka kwa URL kwa kipindi hiki tu (inaweza kurudiwa)]:url:'
    '--file[Rasilimali za faili za kupakua wakati wa kuanzisha (muundo: file_id:relative_path)]:specs:'
    '--prompt-suggestions[Wezesha mapendekezo ya orodhesha (hutoa orodhesha inayotabiriwa inayofuata katika mtindo wa print/SDK)]::value:(true false 1 0 yes no on off)'
    '--forward-subagent-text[Peleka maandishi ya wakala mdogo na vizuizi vya kufikiri kama ujumbe (pamoja na --print na stream-json)]'
    '--include-hook-events[Jumuisha matukio yote ya mzunguko wa maisha wa hook katika mkondo wa matokeo (pamoja na stream-json)]'
    '--exclude-dynamic-system-prompt-sections[Hamisha sehemu za kila-mashine kwenye ujumbe wa kwanza wa mtumiaji ili kuboresha utumiaji upya wa akiba ya orodhesha]'
    '--brief[Wezesha zana ya SendUserMessage kwa mawasiliano ya wakala-kwa-mtumiaji]'
    '--safe-mode[Anzisha na ubinafsishaji wote umezimwa (muhimu kwa kutatua usanidi uliovunjika)]'
    '--bare[Mtindo mdogo: ruka hooks, LSP, ulandanishi wa programu-jalizi, sifa, kumbukumbu-otomatiki, na ugunduzi-otomatiki wa CLAUDE.md]'
    '--ax-screen-reader[Toa matokeo yanayofaa kisomaji-skrini (maandishi tambarare, hakuna mipaka ya mapambo au uhuishaji)]'
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
    'login:Thibitisha na seva ya MCP (HTTP, SSE, au kiunganishi cha claude.ai)'
    'logout:Futa kitambulisho cha OAuth kilichohifadhiwa kwa seva ya MCP'
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
        login|logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:name:_claude_mcp_servers'
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
    'list:Orodhesha programu-jalizi zilizosakinishwa'
    'details:Onyesha orodha ya vipengele na gharama ya tokeni inayotarajiwa kwa programu-jalizi'
    'install:Sakinisha programu-jalizi kutoka kwa masoko yanayopatikana'
    'i:Sakinisha programu-jalizi kutoka kwa masoko yanayopatikana (fupi kwa install)'
    'init:Tengeneza programu-jalizi mpya (hupakia kiotomatiki kipindi kijacho)'
    'uninstall:Ondoa programu-jalizi iliyosakinishwa'
    'remove:Ondoa programu-jalizi iliyosakinishwa (jina-mbadala kwa uninstall)'
    'enable:Wezesha programu-jalizi iliyozimwa'
    'disable:Zima programu-jalizi iliyowashwa'
    'update:Sasisha programu-jalizi hadi toleo la hivi punde'
    'eval:Endesha kesi za tathmini dhidi ya programu-jalizi na uripoti matokeo yaliyopimwa'
    'prune:Ondoa tegemezi zilizosakinishwa kiotomatiki ambazo hazihitajiki tena'
    'tag:Unda git tag ya {name}--v{version} kwa toleo la programu-jalizi'
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
            '(-s --scope)'{-s,--scope}'[Upeo wa usakinishaji]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Upeo wa usakinishaji]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Upeo wa usakinishaji]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Upeo wa usakinishaji]:scope:(user project local managed)' \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list|prune)
          _arguments \
            '(-h --help)'{-h,--help}'[Onyesha msaada]'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init)
          _arguments \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:target:'
          ;;
        tag)
          _arguments \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:path:_files'
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

_claude_agents() {
  _arguments \
    '*--add-dir[Saraka ya ziada ya kuruhusu upatikanaji wa zana katika vipindi vilivyotumwa]:directory:_directories' \
    '--agent[Wakala chaguo-msingi kwa vipindi vilivyotumwa kutoka kwa mwonekano wa wakala]:agent:' \
    '--all[Pamoja na --json: pia jumuisha vipindi vya mandharinyuma vilivyokamilika]' \
    '--allow-dangerously-skip-permissions[Fanya mtindo wa kuruka-ruhusa upatikane kwa vipindi vilivyotumwa]' \
    '--cwd[Onyesha tu vipindi vya mandharinyuma vilivyoanzishwa chini ya njia]:path:_directories' \
    '--dangerously-skip-permissions[Jina-mbadala kwa --permission-mode bypassPermissions]' \
    '--effort[Kiwango cha juhudi chaguo-msingi kwa vipindi vilivyotumwa]:level:(low medium high xhigh max)' \
    '--json[Chapisha vipindi vinavyofanya kazi kama safu ya JSON na utoke]' \
    '*--mcp-config[Usanidi wa seva ya MCP wa kutumia kwa vipindi vilivyotumwa]:config:' \
    '--model[Modeli chaguo-msingi kwa vipindi vilivyotumwa kutoka kwa mwonekano wa wakala]:model:' \
    '--permission-mode[Mtindo wa ruhusa chaguo-msingi kwa vipindi vilivyotumwa]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Pakia programu-jalizi kutoka kwa saraka kwa mwonekano wa wakala na vipindi vilivyotumwa]:path:_directories' \
    '--setting-sources[Orodha ya vyanzo vya mipangilio iliyotenganishwa kwa koma ya kupakia (user, project, local)]:sources:' \
    '--settings[Faili ya mipangilio au mfuatano wa JSON wa kutumia]:file-or-json:_files' \
    '--strict-mcp-config[Tumia tu seva za MCP kutoka kwa --mcp-config katika vipindi vilivyotumwa]' \
    '(-h --help)'{-h,--help}'[Onyesha msaada kwa amri]'
}

_claude_auth() {
  local -a auth_commands
  auth_commands=(
    'login:Ingia katika akaunti yako ya Anthropic'
    'logout:Toka katika akaunti yako ya Anthropic'
    'status:Onyesha hali ya uthibitishaji'
    'help:Onyesha msaada'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Onyesha msaada kwa amri]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'amri za auth' auth_commands
      ;;
    args)
      case $words[1] in
        login|logout|status)
          _arguments \
            '(-h --help)'{-h,--help}'[Onyesha msaada kwa amri]'
          ;;
      esac
      ;;
  esac
}

_claude_auto_mode() {
  local -a auto_mode_commands
  auto_mode_commands=(
    'config:Chapisha usanidi halisi wa hali otomatiki kama JSON'
    'critique:Pata maoni ya AI kuhusu sheria zako maalum za hali otomatiki'
    'defaults:Chapisha sheria chaguo-msingi za hali otomatiki kama JSON'
    'reset:Weka upya usanidi wa hali otomatiki hadi chaguo-msingi zilizosafirishwa'
    'help:Onyesha msaada'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Onyesha msaada kwa amri]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'amri za auto-mode' auto_mode_commands
      ;;
    args)
      case $words[1] in
        config|critique|defaults|reset)
          _arguments \
            '(-h --help)'{-h,--help}'[Onyesha msaada kwa amri]'
          ;;
      esac
      ;;
  esac
}

_claude_gateway() {
  _arguments \
    '--config[Njia ya usanidi wa YAML wa lango]:path:_files' \
    '(-h --help)'{-h,--help}'[Onyesha msaada kwa amri]'
}

_claude_project() {
  local -a project_commands
  project_commands=(
    'purge:Futa hali yote ya Claude Code kwa mradi (nakala, kazi, historia ya faili, ingizo la usanidi)'
    'help:Onyesha msaada'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Onyesha msaada kwa amri]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'amri za project' project_commands
      ;;
    args)
      case $words[1] in
        purge)
          _arguments \
            '(-h --help)'{-h,--help}'[Onyesha msaada kwa amri]' \
            '1:path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Chapisha mzigo ghafi wa bugs.json badala ya matokeo yaliyoumbizwa]' \
    '--timeout[Dakika za juu za kusubiri ukaguzi ukamilike]:minutes:' \
    '(-h --help)'{-h,--help}'[Onyesha msaada kwa amri]' \
    '1:target:'
}

(( $+_comps[claude] )) || compdef _claude claude
