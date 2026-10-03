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
    'mcp:Sanidi na simamia seva za MCP'
    'plugin:Simamia programu-jalizi za Claude Code'
    'agents:Simamia wakala wa mandharinyuma'
    'attach:Fungua kipindi cha mandharinyuma katika terminal hii'
    'logs:Chapisha matokeo ya hivi karibuni ya terminal ya kipindi cha mandharinyuma'
    'stop:Simamisha kipindi cha mandharinyuma (mazungumzo yake yanahifadhiwa)'
    'respawn:Anzisha upya kipindi cha mandharinyuma ili kiendeshe toleo la sasa la Claude Code'
    'rm:Futa kipindi cha mandharinyuma, na worktree yake inapokuwa salama kufanya hivyo'
    'auth:Simamia uthibitishaji'
    'auto-mode:Kagua au weka upya usanidi wa kiainishi cha hali otomatiki'
    'gateway:Endesha lango la uthibitishaji/telemetria la biashara'
    'import:Leta usanidi kutoka kwa wakala mwingine wa AI wa kuandika msimbo hadi Claude Code'
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
    '--restricted[Mtindo wenye vikwazo: ondoa zana zinazoendesha amri au msimbo na WebFetch, puuza mipangilio ya user/project/local, na weka kikomo cha zana za faili kwenye saraka za kazi pekee]'
    '--max-budget-usd[Kiasi cha juu cha dola cha kutumia kwenye simu za API (--print tu)]:amount:'
    '--replay-user-messages[Tuma tena ujumbe wa mtumiaji kutoka stdin kwenye stdout kwa uthibitishaji]'
    '--allowed-tools[Orodha ya majina ya zana zinazoruhusiwa yaliyotenganishwa kwa koma au nafasi (mfano: "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Orodha ya majina ya zana zinazoruhusiwa yaliyotenganishwa kwa koma au nafasi (muundo wa camelCase)]:tools:'
    '--tools[Bainisha orodha ya zana zinazopatikana kutoka kwa seti iliyojengwa ndani. Mtindo wa kuchapisha tu]:tools:'
    '--disallowed-tools[Orodha ya majina ya zana ambazo haziruhusiwi yaliyotenganishwa kwa koma au nafasi (mfano: "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Orodha ya majina ya zana ambazo haziruhusiwi yaliyotenganishwa kwa koma au nafasi (muundo wa camelCase)]:tools:'
    '--mcp-config[Pakia seva za MCP kutoka kwa faili ya JSON au mfuatano (uliotenganishwa kwa nafasi)]:configs:'
    '--system-prompt[Orodhesha mfumo wa kutumia kwa kipindi]:prompt:'
    '--system-prompt-file[Soma kidokezo cha mfumo kutoka kwa faili]:file:_files'
    '--append-system-prompt[Ongeza orodhesha mfumo kwenye orodhesha chaguo-msingi ya mfumo]:prompt:'
    '--append-system-prompt-file[Soma kidokezo cha mfumo kutoka kwa faili na ukiongeze kwenye kidokezo chaguo-msingi cha mfumo]:file:_files'
    '--system-prompt-snapshot[Rekodi kidokezo cha mfumo mara moja kwa kila mazungumzo na ukitumie tena neno kwa neno katika kila ombi na urejeshaji (on, chaguo-msingi) au ukitengeneze upya katika kila ombi (off)]:mode:(on off)'
    '--permission-mode[Mtindo wa ruhusa wa kutumia kwa kipindi]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '--permission-prompts[Nani hujibu maombi ya ruhusa pamoja na --print: "host" (mwenyeji wa SDK au --permission-prompt-tool) au "none" (chochote ambacho kingeomba ruhusa kinakataliwa)]:target:(host none)'
    '--permission-prompt-tool[Zana ya MCP ya kutumia kwa maombi ya ruhusa (--print tu)]:tool:'
    '(-c --continue)'{-c,--continue}'[Endelea na mazungumzo ya hivi karibuni]'
    '(-r --resume)'{-r,--resume}'[Rudisha mazungumzo - bainisha kitambulisho cha kipindi au chagua kwa njia ya mwingiliano]:sessionId:_claude_sessions'
    '--fork-session[Unda kitambulisho kipya cha kipindi badala ya kutumia tena kitambulisho cha asili cha kipindi wakati wa kurudisha (pamoja na --resume au --continue)]'
    '--no-session-persistence[Zima uhifadhi wa kipindi - vipindi havitahifadhiwa (--print tu)]'
    '--model[Modeli kwa kipindi cha sasa. Bainisha jina-mbadala kwa modeli mpya (mfano: '\''sonnet'\'' au '\''opus'\'')]:model:_claude_model_names'
    '--agent[Wakala kwa kipindi cha sasa. Inabatilisha mpangilio wa '\''agent'\'']:agent:_claude_agent_names'
    '--betas[Vichwa vya beta vya kujumuisha katika maombi ya API (watumiaji wa ufunguo wa API tu)]:betas:'
    '--fallback-model[Wezesha kubadilika kiotomatiki kwa modeli iliyobainishwa wakati modeli chaguo-msingi imelemewa (--print tu)]:model:_claude_model_names'
    '--settings[Njia ya faili ya JSON ya mipangilio au mfuatano wa JSON wa kupakia mipangilio ya ziada]:file-or-json:_files'
    '--add-dir[Saraka za ziada za kuruhusu upatikanaji wa zana]:directories:_directories'
    '--ide[Unganisha-kiotomatiki kwa IDE wakati wa kuanzisha ikiwa kuna IDE moja halali inapatikana]'
    '--desktop[Fungua katika programu ya Claude Desktop badala ya terminal (pamoja na --continue au --resume <id> ili kuchagua kipindi)]'
    '--strict-mcp-config[Tumia seva za MCP kutoka kwa --mcp-config tu na upuuzie mipangilio mingine yote ya MCP]'
    '--session-id[Kitambulisho mahususi cha kipindi cha kutumia kwa mazungumzo (lazima iwe UUID halali)]:uuid:'
    '--agents[Kipengele cha JSON kinachobainisha wakala maalum]:json:'
    '--setting-sources[Orodha ya vyanzo vya mipangilio iliyotenganishwa kwa koma ya kupakia (user, project, local)]:sources:'
    '--plugin-dir[Saraka ya kupakia programu-jalizi kutoka kwa kipindi hiki tu (inaweza kurudiwa)]:paths:_directories'
    '--disable-slash-commands[Zima amri zote za mkwaju]'
    '(--bg --background)'{--bg,--background}'[Anzisha kipindi kama wakala wa mandharinyuma na urudi mara moja]'
    '(-w --worktree)'{-w,--worktree}'[Unda git worktree mpya kwa kipindi hiki (kwa hiari bainisha jina)]::name:'
    '--tmux=-[Unda kipindi cha tmux kwa worktree (inahitaji --worktree). Hutumia vidirisha asili vya iTerm2 vinapopatikana; --tmux=classic kwa tmux ya kawaida]::mode:(classic)'
    '(-n --name)'{-n,--name}'[Weka jina la kuonyesha kwa kipindi hiki]:name:'
    '--effort[Kiwango cha juhudi kwa kipindi cha sasa]:level:(low medium high xhigh max)'
    '--autocompact[Ukubwa wa dirisha la kubana-kiotomatiki (auto, au tokeni 100k-1M)]:size:(auto)'
    '--debug-file[Andika kumbukumbu za utatuzi kwenye njia mahususi ya faili (huwezesha mtindo wa utatuzi kwa dhahiri)]:path:_files'
    '--from-pr[Rudisha kipindi kilichounganishwa na PR kwa nambari/URL, au fungua kichaguzi cha mwingiliano]::value:'
    '--teleport[Rudisha kipindi cha teleport, kwa hiari bainisha kitambulisho cha kipindi]::session:'
    '--cloud[Unda kipindi cha wingu kwa maelezo uliyotoa, au unganisha na kilichopo kwa kitambulisho cha kipindi au URL ya claude.ai/code]::description-or-session:'
    '--environment[Unda kipindi kipya cha wingu kinachoendeshwa kwenye mazingira uliyobainisha yanayojipangishia (ccpool_...)]:environment_id:'
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
        attach|logs|stop|kill)
          _arguments \
            '(-h --help)'{-h,--help}'[Onyesha msaada kwa amri]' \
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
            '--client-id[Kitambulisho cha mteja wa OAuth kwa seva za HTTP/SSE]:clientId:' \
            '--client-secret[Omba siri ya mteja wa OAuth (au weka thamani badilika ya mazingira MCP_CLIENT_SECRET)]' \
            '--callback-port[Mlango thabiti wa callback ya OAuth (kwa seva zinazohitaji URI za kuelekeza upya zilizosajiliwa mapema)]:port:' \
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
            '--client-secret[Omba siri ya mteja wa OAuth (au weka thamani badilika ya mazingira MCP_CLIENT_SECRET)]' \
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
        login)
          _arguments \
            '--no-browser[Chapisha URL ya uidhinishaji badala ya kufungua kivinjari (kwa vipindi vya SSH/bila kiolesura)]' \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:name:_claude_mcp_servers'
          ;;
        logout)
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
    'configure:Onyesha chaguo za programu-jalizi na zipi hazijawekwa, au hifadhi thamani kutoka stdin'
    'install:Sakinisha programu-jalizi kutoka kwa masoko yanayopatikana'
    'i:Sakinisha programu-jalizi kutoka kwa masoko yanayopatikana (fupi kwa install)'
    'init:Tengeneza programu-jalizi mpya (hupakia kiotomatiki kipindi kijacho)'
    'new:Tengeneza programu-jalizi mpya (jina-mbadala kwa init)'
    'uninstall:Ondoa programu-jalizi iliyosakinishwa'
    'remove:Ondoa programu-jalizi iliyosakinishwa (jina-mbadala kwa uninstall)'
    'enable:Wezesha programu-jalizi iliyozimwa'
    'disable:Zima programu-jalizi iliyowashwa'
    'update:Sasisha programu-jalizi hadi toleo la hivi punde'
    'eval:Endesha kesi za tathmini dhidi ya programu-jalizi na uripoti matokeo yaliyopimwa'
    'prune:Ondoa tegemezi zilizosakinishwa kiotomatiki ambazo hazihitajiki tena'
    'autoremove:Ondoa tegemezi zilizosakinishwa kiotomatiki ambazo hazihitajiki tena (jina-mbadala kwa prune)'
    'tag:Unda git tag ya {name}--v{version} kwa toleo la programu-jalizi'
    'test:Endesha majaribio ya mod'
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
            '--strict[Chukulia maonyo kama makosa (msimbo wa kutoka 1)]' \
            '--json[Toa ripoti ya uthibitishaji kama JSON (misimbo ile ile ya kutoka)]' \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Upeo wa usakinishaji]:scope:(user project local)' \
            '*--config[Weka chaguo la userConfig lililotangazwa katika manifest ya programu-jalizi (inaweza kurudiwa)]:key=value:' \
            '(-y --yes)'{-y,--yes}'[Kubali amri iliyoonyeshwa iliyotangazwa na soko bila ombi la uthibitisho]' \
            '--json[Chapisha mstari mmoja wa matokeo unaosomeka na mashine badala ya ujumbe wa binadamu]' \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Upeo wa usakinishaji]:scope:(user project local)' \
            '--keep-data[Hifadhi saraka ya data ya kudumu ya programu-jalizi]' \
            '--prune[Pia ondoa tegemezi zilizosakinishwa kiotomatiki ambazo hazihitajiki tena]' \
            '(-y --yes)'{-y,--yes}'[Ruka ombi la uthibitisho la --prune]' \
            '--json[Chapisha mstari mmoja wa matokeo unaosomeka na mashine badala ya ujumbe wa binadamu (si pamoja na --prune)]' \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Upeo wa usakinishaji]:scope:(user project local)' \
            '--json[Chapisha mstari mmoja wa matokeo unaosomeka na mashine badala ya ujumbe wa binadamu]' \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        disable)
          _arguments \
            '(-a --all)'{-a,--all}'[Zima programu-jalizi zote zilizowashwa]' \
            '(-s --scope)'{-s,--scope}'[Upeo wa usakinishaji]:scope:(user project local)' \
            '--json[Chapisha mstari mmoja wa matokeo unaosomeka na mashine badala ya ujumbe wa binadamu]' \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '::plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Upeo wa usakinishaji]:scope:(user project local managed)' \
            '(-y --yes)'{-y,--yes}'[Kubali amri iliyoonyeshwa iliyotangazwa na soko bila ombi la uthibitisho]' \
            '--json[Chapisha mstari mmoja wa matokeo unaosomeka na mashine badala ya ujumbe wa binadamu]' \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list)
          _arguments \
            '--json[Toa matokeo kama JSON]' \
            '--available[Jumuisha programu-jalizi zinazopatikana kutoka kwa masoko (inahitaji --json)]' \
            '(-h --help)'{-h,--help}'[Onyesha msaada]'
          ;;
        prune|autoremove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Safisha katika upeo]:scope:(user project local)' \
            '--dry-run[Orodhesha kile ambacho kingeondolewa bila kuondoa]' \
            '(-y --yes)'{-y,--yes}'[Ruka ombi la uthibitisho]' \
            '(-h --help)'{-h,--help}'[Onyesha msaada]'
          ;;
        configure)
          _arguments \
            '--json[Toa matokeo kama JSON]' \
            '--values-stdin[Soma thamani za chaguo kutoka stdin kama kipengele cha JSON cha mifuatano ya mstari mmoja; chaguo zisizojumuishwa zinabaki na thamani zake]' \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init|new)
          _arguments \
            '--description[Maelezo ya manifest]:text:' \
            '--author[Jina la mwandishi (chaguo-msingi: git config user.name)]:name:' \
            '--author-email[Barua pepe ya mwandishi (chaguo-msingi: git config user.email)]:email:' \
            '--with[Vipengele vya kutengeneza pia]:components:' \
            '(-f --force)'{-f,--force}'[Andika juu ya .claude-plugin/ iliyopo kwenye lengo]' \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '--case[Chuja kesi kwa glob ya jina]:glob:' \
            '*--tag[Chuja kesi kwa lebo (inaweza kurudiwa)]:tag:' \
            '--runs[Batilisha idadi ya uendeshaji kwa kila kesi (chaguo-msingi: case.runs, vinginevyo 3)]:n:' \
            '(-j --concurrency)'{-j,--concurrency}'[Endesha hadi uendeshaji n wa wakala kwa wakati mmoja (1-8; chaguo-msingi 1)]:n:' \
            '--model[Batilisha modeli kwa kesi zote]:model:_claude_model_names' \
            '--judge-model[Batilisha modeli ya mtathmini wa LLM (chaguo-msingi: haiku)]:model:_claude_model_names' \
            '--max-cost-usd[Kikomo kigumu cha gharama; sitisha na uripoti matokeo ya sehemu kikifikiwa (msimbo wa kutoka 2)]:usd:' \
            '--output-dir[Saraka ya aggregate-result.json]:dir:_directories' \
            '--eval-dir[Jina la saraka (chini ya programu-jalizi) linalohifadhi kesi za tathmini]:dir:' \
            '--json[Chapisha matokeo kamili ya uendeshaji kama JSON kwenye stdout, au yaandike kwenye faili hii ya .json]::path:_files' \
            '--threshold[Toka kwa msimbo wa kutoka 1 ikiwa alama ya kesi yoyote iko chini ya kizingiti hiki (chaguo-msingi: 1.0)]:threshold:' \
            '*--allow-tools[Ruhusa ya mwendeshaji kwa zana zinazodhibitiwa (Bash, Write, Edit, WebFetch, mcp__*)]:tools:' \
            '(--no-scaffold)--scaffold[Endesha scaffold_script ya kila kesi (huendesha bash iliyotolewa na mwandishi kwa jina lako; imezimwa kwa chaguo-msingi)]' \
            '(--scaffold)--no-scaffold[Ruka scaffold_script kwa dhahiri]' \
            '--trust-plugin[Thibitisha kwamba unaamini programu-jalizi hii na seti yake ya tathmini, ukiruka ombi la uaminifu la uendeshaji wa kwanza (kwa CI)]' \
            '--ablation[Endesha kikundi cha msingi cha kulinganisha bila programu-jalizi na uripoti tofauti ya alama]:mode:(none with-without)' \
            '--mocks[Vibadala bandia vya seva za MCP, kutoka <eval dir>/mocks/]:mode:(record off)' \
            '--allow-real-servers[Pamoja na --mocks record: pia anzisha michakato halisi ya seva za MCP ambazo hazina kibadala bandia]' \
            '--keep-temp[Hifadhi saraka za scaffold kwa utatuzi]' \
            '--verbose[Rekodi matukio ya ufuatiliaji ya kila ujumbe kwenye kumbukumbu ya utatuzi]' \
            '--report[Andika ripoti ya HTML inayojitosheleza kwenye njia hii badala ya saraka ya matokeo]:path:_files' \
            '(--no-publish)--publish-report[Pia hitaji kuchapisha ripoti kwenye claude.ai]' \
            '(--publish-report)--no-publish[Weka ripoti ya HTML kwenye kompyuta ya ndani tu; ruka kuichapisha kwenye claude.ai]' \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '::target: _alternative "plugins\:installed plugin\:_claude_installed_plugins" "files\:path\:_files"'
          ;;
        tag)
          _arguments \
            '--push[Sukuma tag kwenye --remote baada ya kuiunda]' \
            '--dry-run[Chapisha kile ambacho kingewekewa tag bila kuiunda]' \
            '(-f --force)'{-f,--force}'[Ruka ukaguzi wa mti wa kazi wenye mabadiliko na wa tag kuwepo tayari]' \
            '(-m --message)'{-m,--message}'[Ujumbe wa maelezo ya tag (tumia %s kwa toleo)]:msg:' \
            '--remote[Remote ya kusukumia pamoja na --push]:name:' \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '::path:_files'
          ;;
        test)
          _arguments \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '::dir:_directories'
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
            '--sparse[Weka kikomo cha checkout kwa saraka mahususi kupitia git sparse-checkout (kwa monorepo)]:paths:' \
            '--scope[Mahali pa kutangaza soko]:scope:(user project local)' \
            '--claudeai[Ongeza soko la jina hili ambalo claude.ai hukupangishia]' \
            '(-h --help)'{-h,--help}'[Onyesha msaada]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '--json[Toa matokeo kama JSON]' \
            '(-h --help)'{-h,--help}'[Onyesha msaada]'
          ;;
        remove|rm)
          _arguments \
            '--scope[Ondoa tangazo la soko kutoka kwa upeo mahususi wa mipangilio (usiubainishe upeo ili kuliondoa kutoka kwa kila upeo)]:scope:(user project local)' \
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
    '--agent[Wakala chaguo-msingi kwa vipindi vilivyotumwa kutoka kwa mwonekano wa wakala]:agent:_claude_agent_names' \
    '--all[Pamoja na --json: pia jumuisha vipindi vya mandharinyuma vilivyokamilika]' \
    '--allow-dangerously-skip-permissions[Fanya mtindo wa kuruka-ruhusa upatikane kwa vipindi vilivyotumwa]' \
    '--cwd[Onyesha tu vipindi vya mandharinyuma vilivyoanzishwa chini ya njia]:path:_directories' \
    '--dangerously-skip-permissions[Jina-mbadala kwa --permission-mode bypassPermissions]' \
    '--effort[Kiwango cha juhudi chaguo-msingi kwa vipindi vilivyotumwa]:level:(low medium high xhigh max)' \
    '--json[Chapisha vipindi vinavyofanya kazi kama safu ya JSON na utoke]' \
    '*--mcp-config[Usanidi wa seva ya MCP wa kutumia kwa vipindi vilivyotumwa]:config:' \
    '--model[Modeli chaguo-msingi kwa vipindi vilivyotumwa kutoka kwa mwonekano wa wakala]:model:_claude_model_names' \
    '--permission-mode[Mtindo wa ruhusa chaguo-msingi kwa vipindi vilivyotumwa]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Pakia programu-jalizi kutoka kwa saraka kwa mwonekano wa wakala na vipindi vilivyotumwa]:path:_directories' \
    '--setting-sources[Orodha ya vyanzo vya mipangilio iliyotenganishwa kwa koma ya kupakia (user, project, local)]:sources:' \
    '--settings[Faili ya mipangilio au mfuatano wa JSON wa kutumia]:file-or-json:_files' \
    '--strict-mcp-config[Tumia tu seva za MCP kutoka kwa --mcp-config katika vipindi vilivyotumwa]' \
    '--restricted[Anzisha vipindi vilivyotumwa katika mtindo wenye vikwazo]' \
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
        login)
          _arguments \
            '--email[Jaza mapema anwani ya barua pepe kwenye ukurasa wa kuingia]:email:' \
            '--sso[Lazimisha mtiririko wa kuingia kwa SSO]' \
            '(--claudeai)--console[Tumia Anthropic Console (malipo kwa matumizi ya API) badala ya usajili wa Claude]' \
            '(--console)--claudeai[Tumia usajili wa Claude (chaguo-msingi)]' \
            '(-h --help)'{-h,--help}'[Onyesha msaada kwa amri]'
          ;;
        status)
          _arguments \
            '(--text)--json[Toa matokeo kama JSON (chaguo-msingi)]' \
            '(--json)--text[Toa matokeo kama maandishi yanayosomeka na binadamu]' \
            '(-h --help)'{-h,--help}'[Onyesha msaada kwa amri]'
          ;;
        logout)
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
        critique)
          _arguments \
            '--model[Batilisha modeli inayotumika]:model:_claude_model_names' \
            '(-h --help)'{-h,--help}'[Onyesha msaada kwa amri]'
          ;;
        defaults)
          _arguments \
            '--label[Onyesha tu sheria ambazo lebo yake inaanza na kiambishi awali hiki (bila kujali herufi kubwa au ndogo)]:prefix:' \
            '(-h --help)'{-h,--help}'[Onyesha msaada kwa amri]'
          ;;
        reset)
          _arguments \
            '(-y --yes)'{-y,--yes}'[Ruka ombi la uthibitisho]' \
            '(-h --help)'{-h,--help}'[Onyesha msaada kwa amri]'
          ;;
        config)
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
            '--dry-run[Orodhesha kile ambacho kingefutwa bila kufuta chochote]' \
            '(-y --yes)'{-y,--yes}'[Ruka ombi la uthibitisho]' \
            '(-i --interactive)'{-i,--interactive}'[Uliza kwa kila kipengee kabla ya kufuta]' \
            '(1)--all[Futa hali kwa kila mradi (haiwezi kutumika pamoja na njia)]' \
            '(-h --help)'{-h,--help}'[Onyesha msaada kwa amri]' \
            '(--all)::path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Chapisha mzigo ghafi wa bugs.json badala ya matokeo yaliyoumbizwa]' \
    '--timeout[Dakika za juu za kusubiri ukaguzi ukamilike (chaguo-msingi: 45)]:minutes:' \
    '(--no-post)--post[Chapisha matokeo ya ukaguzi uliokamilika kwenye PR kwa jina lako (malengo ya PR tu; maoni moja ya kawaida, si ukaguzi)]' \
    '(--post)--no-post[Usichapishe matokeo kwenye PR (chaguo-msingi)]' \
    '(-h --help)'{-h,--help}'[Onyesha msaada kwa amri]' \
    '1:target:'
}

_claude_respawn() {
  _arguments \
    '(1)--all[Anzisha upya kila kipindi cha mandharinyuma kinachoendelea]' \
    '(-h --help)'{-h,--help}'[Onyesha msaada kwa amri]' \
    '(--all)::session:_claude_background_sessions'
}

_claude_rm() {
  _arguments \
    '--discard-unpushed[Pia tupa commit ambazo hazijasukumwa na mabadiliko ambayo hayajafanyiwa commit ya worktree (pitisha commit@worktree-id iliyoripotiwa na claude rm ya awali)]:commit@worktree-id:' \
    '--force-remove-worktree[Futa saraka ya worktree hata kama hook ya WorktreeRemove au git haikuweza kuiondoa (pitisha worktree-id iliyoripotiwa na claude rm ya awali)]:worktree-id:' \
    '(-h --help)'{-h,--help}'[Onyesha msaada kwa amri]' \
    '1:session:_claude_background_sessions'
}

_claude_import() {
  _arguments \
    '--dry-run[Onyesha kile ambacho kingeletwa bila kuandika chochote]' \
    '--yes[Ruka kichaguzi cha mwingiliano (kwenye mazingira bila kiolesura, pitisha --yes=<digest> kutoka kwa onyesho la awali la /import)]' \
    '(-h --help)'{-h,--help}'[Onyesha msaada kwa amri]' \
    '::source:(codex gemini cursor)'
}

(( $+_comps[claude] )) || compdef _claude claude
