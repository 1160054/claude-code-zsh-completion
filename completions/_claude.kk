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
    'mcp:MCP серверлерін конфигурациялау және басқару'
    'plugin:Claude Code плагиндерін басқару'
    'agents:Фондық агенттерді басқару'
    'attach:Фондық сессияны осы терминалда ашу'
    'logs:Фондық сессияның соңғы терминал шығысын басып шығару'
    'stop:Фондық сессияны тоқтату (оның әңгімесі сақталады)'
    'respawn:Фондық сессия Claude Code-тың ағымдағы нұсқасында жұмыс істеуі үшін оны қайта іске қосу'
    'rm:Фондық сессияны және қауіпсіз болса, оның worktree-ін жою'
    'auth:Аутентификацияны басқару'
    'auto-mode:Авто режим классификаторының конфигурациясын тексеру немесе қалпына келтіру'
    'gateway:Кәсіпорын аутентификация/телеметрия шлюзін іске қосу'
    'import:Басқа AI кодтау агентінен конфигурацияны Claude Code-қа импорттау'
    'project:Claude Code жоба күйін басқару'
    'ultrareview:Бұлтта орналастырылған көп агентті код шолуын іске қосу және нәтижелерін басып шығару'
    'setup-token:Ұзақ мерзімді аутентификация токенін орнату (Claude жазылымы қажет)'
    'doctor:Claude Code автоматты жаңартқышы үшін денсаулық тексеруі'
    'update:Жаңартуларды тексеру және орнату'
    'install:Claude Code жергілікті құрылысын орнату'
  )

  local -a main_options
  main_options=(
    '(-d --debug)'{-d,--debug}'[Санат сүзгісімен жөндеу режімін қосу (мысалы, "api,hooks" немесе "!statsig,!file")]:filter:'
    '--verbose[Конфигурация файлынан толық режим параметрін қайта анықтау]'
    '(-p --print)'{-p,--print}'[Жауапты басып шығару және шығу (құбырлармен пайдалану үшін). Ескерту: тек сенімді каталогтарда пайдаланыңыз]'
    '--output-format[Шығыс форматы (--print-пен): "text" (әдепкі), "json" (жалғыз нәтиже), немесе "stream-json" (нақты уақыттағы ағын)]:format:(text json stream-json)'
    '--json-schema[Құрылымдық шығысты тексеру үшін JSON схемасы]:schema:'
    '--include-partial-messages[Келген кезде ішінара хабарлама бөліктерін қосу (--print және --output-format=stream-json-мен)]'
    '--input-format[Кіріс форматы (--print-пен): "text" (әдепкі) немесе "stream-json" (нақты уақыттағы ағын кірісі)]:format:(text stream-json)'
    '--mcp-debug[\[Ескірген. Оның орнына --debug пайдаланыңыз\] MCP жөндеу режімін қосу (MCP сервер қателерін көрсетеді)]'
    '--dangerously-skip-permissions[Барлық рұқсат тексерулерінен өту. Тек интернетке қол жетімсіз sandbox ортасы үшін ұсынылады]'
    '--allow-dangerously-skip-permissions[Әдепкі бойынша қоспай-ақ рұқсат тексерулерінен өту опциясын қосу]'
    '--restricted[Шектеулі режим: командаларды немесе кодты іске қосатын құралдарды және WebFetch-ті алып тастау, user/project/local параметрлерін елемеу және файл құралдарын жұмыс каталогтарымен шектеу]'
    '--max-budget-usd[API шақыруларына жұмсалатын максималды доллар сомасы (тек --print)]:amount:'
    '--replay-user-messages[Растау үшін stdin-ден stdout-қа пайдаланушы хабарламаларын қайта жіберу]'
    '--allowed-tools[Үтірмен немесе бос орынмен бөлінген рұқсат етілген құрал атауларының тізімі (мысалы, "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Үтірмен немесе бос орынмен бөлінген рұқсат етілген құрал атауларының тізімі (camelCase форматы)]:tools:'
    '--tools[Кірістірілген жиынтықтан қолжетімді құралдар тізімін көрсету. Тек басып шығару режімі]:tools:'
    '--disallowed-tools[Үтірмен немесе бос орынмен бөлінген тыйым салынған құрал атауларының тізімі (мысалы, "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Үтірмен немесе бос орынмен бөлінген тыйым салынған құрал атауларының тізімі (camelCase форматы)]:tools:'
    '--mcp-config[JSON файлынан немесе жолдан MCP серверлерін жүктеу (бос орынмен бөлінген)]:configs:'
    '--system-prompt[Сессия үшін жүйелік ескерту]:prompt:'
    '--system-prompt-file[Жүйелік ескертуді файлдан оқу]:file:_files'
    '--append-system-prompt[Әдепкі жүйелік ескертуге жүйелік ескертуді қосу]:prompt:'
    '--append-system-prompt-file[Жүйелік ескертуді файлдан оқу және әдепкі жүйелік ескертуге қосу]:file:_files'
    '--system-prompt-snapshot[Жүйелік ескертуді әр әңгімеге бір рет жазып алып, оны әр сұрауда және жалғастыруда сөзбе-сөз қайта пайдалану (on, әдепкі) немесе әр сұрауда жаңадан құрастыру (off)]:mode:(on off)'
    '--permission-mode[Сессия үшін рұқсат режімі]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '--permission-prompts[--print кезінде рұқсат сұрауларына кім жауап береді: "host" (SDK хосты немесе --permission-prompt-tool) немесе "none" (сұрау тудыратын кез келген әрекет қабылданбайды)]:target:(host none)'
    '--permission-prompt-tool[Рұқсат сұраулары үшін пайдаланылатын MCP құралы (тек --print)]:tool:'
    '(-c --continue)'{-c,--continue}'[Ең соңғы әңгімені жалғастыру]'
    '(-r --resume)'{-r,--resume}'[Әңгімені жалғастыру - сессия идентификаторын көрсетіңіз немесе интерактивті түрде таңдаңыз]:sessionId:_claude_sessions'
    '--fork-session[Жалғастыру кезінде түпнұсқа сессия идентификаторын қайта пайдалану орнына жаңа сессия идентификаторын жасау (--resume немесе --continue-мен)]'
    '--no-session-persistence[Сессия сақтауын өшіру - сессиялар сақталмайды (тек --print)]'
    '--model[Ағымдағы сессия үшін модель. Ең соңғы модель үшін бүркеншік атты көрсетіңіз (мысалы, '\''sonnet'\'' немесе '\''opus'\'')]:model:_claude_model_names'
    '--agent[Ағымдағы сессия үшін агент. '\''agent'\'' параметрін қайта анықтайды]:agent:_claude_agent_names'
    '--betas[API сұрауларына қосылатын бета тақырыптары (тек API кілт пайдаланушылары)]:betas:'
    '--fallback-model[Әдепкі модель жүктелген кезде көрсетілген модельге автоматты қосалқы ауысуды қосу (тек --print)]:model:_claude_model_names'
    '--settings[Қосымша параметрлерді жүктеу үшін параметрлер JSON файлы немесе JSON жолының жолы]:file-or-json:_files'
    '--add-dir[Құрал қолжетімділігіне рұқсат беру үшін қосымша каталогтар]:directories:_directories'
    '--ide[Іске қосу кезінде дәл бір жарамды IDE қол жетімді болса, автоматты түрде IDE-ге қосылу]'
    '--desktop[Терминалдың орнына Claude Desktop қолданбасында ашу (сессияны таңдау үшін --continue немесе --resume <id>-мен)]'
    '--strict-mcp-config[Тек --mcp-config-тен MCP серверлерін пайдалану және басқа барлық MCP параметрлерін елемеу]'
    '--session-id[Әңгіме үшін арнайы сессия идентификаторы (жарамды UUID болуы керек)]:uuid:'
    '--agents[Арнайы агенттерді анықтайтын JSON нысаны]:json:'
    '--setting-sources[Жүктеу үшін үтірмен бөлінген параметр көздерінің тізімі (user, project, local)]:sources:'
    '--plugin-dir[Тек осы сессия үшін плагиндерді жүктеу үшін каталог (қайталанатын)]:paths:_directories'
    '--disable-slash-commands[Барлық қиғаш сызық командаларын өшіру]'
    '(--bg --background)'{--bg,--background}'[Сессияны фондық агент ретінде іске қосу және дереу қайту]'
    '(-w --worktree)'{-w,--worktree}'[Осы сессия үшін жаңа git worktree жасау (қосымша ат көрсетуге болады)]::name:'
    '--tmux=-[worktree үшін tmux сессиясын жасау (--worktree қажет). Қолжетімді болса, iTerm2 кірістірілген панельдерін пайдаланады; дәстүрлі tmux үшін --tmux=classic]::mode:(classic)'
    '(-n --name)'{-n,--name}'[Осы сессия үшін көрсету атауын орнату]:name:'
    '--effort[Ағымдағы сессия үшін күш деңгейі]:level:(low medium high xhigh max)'
    '--autocompact[Авто-ықшамдау терезесінің өлшемі (auto немесе 100k-1M токен)]:size:(auto)'
    '--debug-file[Жөндеу журналдарын белгілі бір файл жолына жазу (жасырын түрде жөндеу режімін қосады)]:path:_files'
    '--from-pr[Нөмір/URL бойынша PR-ге байланысты сессияны жалғастыру немесе интерактивті таңдаушыны ашу]::value:'
    '--teleport[Teleport сессиясын жалғастыру, қосымша сессия идентификаторын көрсетуге болады]::session:'
    '--cloud[Берілген сипаттамамен бұлттық сессия жасау немесе сессия идентификаторы не claude.ai/code URL бойынша бар сессияға қосылу]::description-or-session:'
    '--environment[Берілген өзіндік хостталған ортада (ccpool_...) жұмыс істейтін жаңа бұлттық сессия жасау]:environment_id:'
    '--remote-control[Қашықтан басқару қосылған интерактивті сессияны іске қосу (қосымша атаумен)]::name:'
    '--remote-control-session-name-prefix[Автоматты жасалатын Қашықтан басқару сессия атауларының префиксі]:prefix:'
    '--chrome[Chrome-дағы Claude интеграциясын қосу]'
    '--no-chrome[Chrome-дағы Claude интеграциясын өшіру]'
    '--plugin-url[Тек осы сессия үшін URL-ден плагин .zip алу (қайталанатын)]:url:'
    '--file[Іске қосу кезінде жүктелетін файл ресурстары (формат: file_id:relative_path)]:specs:'
    '--prompt-suggestions[Ескерту ұсыныстарын қосу (print/SDK режімінде болжамды келесі ескертуді шығарады)]::value:(true false 1 0 yes no on off)'
    '--forward-subagent-text[Ішкі агент мәтіні мен ойлау блоктарын хабарлама ретінде бағыттау (--print және stream-json-мен)]'
    '--include-hook-events[Барлық hook өмірлік цикл оқиғаларын шығыс ағынына қосу (stream-json-мен)]'
    '--exclude-dynamic-system-prompt-sections[Ескерту кэшін қайта пайдалануды жақсарту үшін әр машинаға қатысты бөлімдерді бірінші пайдаланушы хабарламасына жылжыту]'
    '--brief[Агент-пайдаланушы байланысы үшін SendUserMessage құралын қосу]'
    '--safe-mode[Барлық баптаулар өшірілген күйде іске қосу (бұзылған конфигурацияны жөндеуге пайдалы)]'
    '--bare[Минималды режім: hook-тарды, LSP, плагин синхрондауын, атрибуцияны, авто-жадты және CLAUDE.md автоматты табуды өткізіп жіберу]'
    '--ax-screen-reader[Экран оқығышқа ыңғайлы шығысты көрсету (тегіс мәтін, әшекейлі жиектер немесе анимациялар жоқ)]'
    '(-v --version)'{-v,--version}'[Нұсқа нөмірін шығару]'
    '(-h --help)'{-h,--help}'[Команда үшін анықтаманы көрсету]'
  )

  _arguments -C \
    $main_options \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'claude commands' main_commands
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
            '(-h --help)'{-h,--help}'[Команда үшін анықтаманы көрсету]' \
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
          _message "аргументтер жоқ"
          ;;
      esac
      ;;
  esac
}

_claude_mcp() {
  local -a mcp_commands
  mcp_commands=(
    'serve:Claude Code MCP серверін іске қосу'
    'add:Claude Code-қа MCP серверін қосу'
    'remove:MCP серверін жою'
    'list:Конфигурацияланған MCP серверлерінің тізімі'
    'get:MCP сервер мәліметтерін алу'
    'add-json:JSON жолымен MCP серверін қосу (stdio немесе SSE)'
    'add-from-claude-desktop:Claude Desktop-тан MCP серверлерін импорттау (тек Mac және WSL)'
    'reset-project-choices:Осы жобадағы барлық бекітілген/қабылданбаған жоба аясындағы (.mcp.json) серверлерді қалпына келтіру'
    'login:MCP серверімен аутентификациялау (HTTP, SSE немесе claude.ai коннекторы)'
    'logout:MCP сервері үшін сақталған OAuth тіркелгі деректерін тазалау'
    'help:Анықтаманы көрсету'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'mcp commands' mcp_commands
      ;;
    args)
      case $words[1] in
        serve)
          _arguments \
            '(-d --debug)'{-d,--debug}'[Жөндеу режімін қосу]' \
            '--verbose[Конфигурация файлынан толық режим параметрін қайта анықтау]' \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]'
          ;;
        add)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Конфигурация аясы (local, user, project)]:scope:(local user project)' \
            '(-t --transport)'{-t,--transport}'[Тасымалдау түрі (stdio, sse, http)]:transport:(stdio sse http)' \
            '(-e --env)'{-e,--env}'[Орта айнымалысын орнату (мысалы, -e KEY=value)]:env:' \
            '(-H --header)'{-H,--header}'[WebSocket тақырыбын орнату]:header:' \
            '--client-id[HTTP/SSE серверлері үшін OAuth клиент идентификаторы]:clientId:' \
            '--client-secret[OAuth клиент құпиясын сұрау (немесе MCP_CLIENT_SECRET орта айнымалысын орнатыңыз)]' \
            '--callback-port[OAuth кері шақыруы үшін тұрақты порт (алдын ала тіркелген қайта бағыттау URI-лерін талап ететін серверлер үшін)]:port:' \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '1:name:' \
            '2:commandOrUrl:' \
            '*:args:'
          ;;
        remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Конфигурация аясы (local, user, project) - көрсетілмеген жағдайда қолданыстағы аясынан жою]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '1:name:_claude_mcp_servers'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]'
          ;;
        get)
          _arguments \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '1:name:_claude_mcp_servers'
          ;;
        add-json)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Конфигурация аясы (local, user, project)]:scope:(local user project)' \
            '--client-secret[OAuth клиент құпиясын сұрау (немесе MCP_CLIENT_SECRET орта айнымалысын орнатыңыз)]' \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '1:name:' \
            '2:json:'
          ;;
        add-from-claude-desktop)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Конфигурация аясы (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]'
          ;;
        reset-project-choices)
          _arguments \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]'
          ;;
        login)
          _arguments \
            '--no-browser[Браузерді ашудың орнына авторизация URL-ін басып шығару (SSH/headless сессиялары үшін)]' \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '1:name:_claude_mcp_servers'
          ;;
        logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '1:name:_claude_mcp_servers'
          ;;
      esac
      ;;
  esac
}

_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:Плагин немесе нарық манифестін тексеру'
    'marketplace:Claude Code нарықтарын басқару'
    'list:Орнатылған плагиндердің тізімі'
    'details:Плагин үшін компонент тізімі мен болжамды токен құнын көрсету'
    'configure:Плагин опцияларын және қайсысы орнатылмағанын көрсету немесе мәндерді stdin-нен сақтау'
    'install:Қол жетімді нарықтардан плагин орнату'
    'i:Қол жетімді нарықтардан плагин орнату (install үшін қысқа)'
    'init:Жаңа плагинді құрастыру (келесі сессияда автоматты жүктеледі)'
    'new:Жаңа плагинді құрастыру (init үшін бүркеншік ат)'
    'uninstall:Орнатылған плагинді жою'
    'remove:Орнатылған плагинді жою (uninstall үшін бүркеншік ат)'
    'enable:Өшірілген плагинді қосу'
    'disable:Қосылған плагинді өшіру'
    'update:Плагинді ең соңғы нұсқаға жаңарту'
    'eval:Плагинге қарсы бағалау жағдайларын іске қосу және бағаланған нәтижелерді есептеу'
    'prune:Қажет емес автоматты орнатылған тәуелділіктерді жою'
    'autoremove:Енді қажет емес автоматты орнатылған тәуелділіктерді жою (prune үшін бүркеншік ат)'
    'tag:Плагин шығарылымы үшін {name}--v{version} git тегін жасау'
    'test:Мод тесттерін іске қосу'
    'help:Анықтаманы көрсету'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'plugin commands' plugin_commands
      ;;
    args)
      case $words[1] in
        validate)
          _arguments \
            '--strict[Ескертулерді қате ретінде қарастыру (шығу коды 1)]' \
            '--json[Тексеру есебін JSON ретінде шығару (шығу кодтары бірдей)]' \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Орнату аясы]:scope:(user project local)' \
            '*--config[Плагин манифестінде жарияланған userConfig опциясын орнату (қайталанатын)]:key=value:' \
            '(-y --yes)'{-y,--yes}'[Нарық жариялаған көрсетілген команданы растау сұрауынсыз қабылдау]' \
            '--json[Адамға арналған хабарламаның орнына машина оқитын бір нәтиже жолын басып шығару]' \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Орнату аясы]:scope:(user project local)' \
            '--keep-data[Плагиннің тұрақты деректер каталогын сақтау]' \
            '--prune[Сондай-ақ енді қажет емес автоматты орнатылған тәуелділіктерді жою]' \
            '(-y --yes)'{-y,--yes}'[--prune растау сұрауын өткізіп жіберу]' \
            '--json[Адамға арналған хабарламаның орнына машина оқитын бір нәтиже жолын басып шығару (--prune-мен емес)]' \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Орнату аясы]:scope:(user project local)' \
            '--json[Адамға арналған хабарламаның орнына машина оқитын бір нәтиже жолын басып шығару]' \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        disable)
          _arguments \
            '(-a --all)'{-a,--all}'[Барлық қосылған плагиндерді өшіру]' \
            '(-s --scope)'{-s,--scope}'[Орнату аясы]:scope:(user project local)' \
            '--json[Адамға арналған хабарламаның орнына машина оқитын бір нәтиже жолын басып шығару]' \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '::plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Орнату аясы]:scope:(user project local managed)' \
            '(-y --yes)'{-y,--yes}'[Нарық жариялаған көрсетілген команданы растау сұрауынсыз қабылдау]' \
            '--json[Адамға арналған хабарламаның орнына машина оқитын бір нәтиже жолын басып шығару]' \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list)
          _arguments \
            '--json[JSON ретінде шығару]' \
            '--available[Нарықтардағы қолжетімді плагиндерді қосу (--json қажет)]' \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]'
          ;;
        prune|autoremove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Көрсетілген аяда тазалау]:scope:(user project local)' \
            '--dry-run[Жоймай-ақ, не жойылатынын тізімдеу]' \
            '(-y --yes)'{-y,--yes}'[Растау сұрауын өткізіп жіберу]' \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]'
          ;;
        configure)
          _arguments \
            '--json[JSON ретінде шығару]' \
            '--values-stdin[Опция мәндерін stdin-нен бір жолды жолдардан тұратын JSON нысаны ретінде оқу; көрсетілмеген опциялар өз мәндерін сақтайды]' \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init|new)
          _arguments \
            '--description[Манифест сипаттамасы]:text:' \
            '--author[Автор аты (әдепкі: git config user.name)]:name:' \
            '--author-email[Автор электрондық поштасы (әдепкі: git config user.email)]:email:' \
            '--with[Қосымша құрастырылатын компоненттер]:components:' \
            '(-f --force)'{-f,--force}'[Мақсаттағы бар .claude-plugin/ каталогын қайта жазу]' \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '--case[Жағдайларды атау glob үлгісі бойынша сүзу]:glob:' \
            '*--tag[Жағдайларды тег бойынша сүзу (қайталанатын)]:tag:' \
            '--runs[Әр жағдайдағы іске қосулар санын қайта анықтау (әдепкі: case.runs, болмаса 3)]:n:' \
            '(-j --concurrency)'{-j,--concurrency}'[Агент іске қосуларының n-ге дейінін бір уақытта орындау (1-8; әдепкі 1)]:n:' \
            '--model[Барлық жағдайлар үшін модельді қайта анықтау]:model:_claude_model_names' \
            '--judge-model[LLM-бағалаушы модельді қайта анықтау (әдепкі: haiku)]:model:_claude_model_names' \
            '--max-cost-usd[Шығынның қатаң шегі; оған жеткенде тоқтатып, ішінара нәтижелерді хабарлау (шығу коды 2)]:usd:' \
            '--output-dir[aggregate-result.json үшін каталог]:dir:_directories' \
            '--eval-dir[Бағалау жағдайларын сақтайтын каталог атауы (плагин астында)]:dir:' \
            '--json[Толық іске қосу нәтижесін JSON ретінде stdout-қа басып шығару немесе оны осы .json файлына жазу]::path:_files' \
            '--threshold[Кез келген жағдайдың ұпайы осы шектен төмен болса, 1 шығу кодымен шығу (әдепкі: 1.0)]:threshold:' \
            '*--allow-tools[Шектелген құралдарға оператор рұқсаты (Bash, Write, Edit, WebFetch, mcp__*)]:tools:' \
            '(--no-scaffold)--scaffold[Әр жағдайдың scaffold_script-ін іске қосу (автор берген bash-ты сіздің атыңыздан іске қосады; әдепкі бойынша өшірулі)]' \
            '(--scaffold)--no-scaffold[scaffold_script-ті анық түрде өткізіп жіберу]' \
            '--trust-plugin[Осы плагинге және оның бағалау жиынтығына сенетініңізді растап, алғашқы іске қосудағы сенім сұрауын өткізіп жіберу (CI үшін)]' \
            '--ablation[Плагинсіз базалық салыстыру тобын іске қосу және ұпай айырмасын хабарлау]:mode:(none with-without)' \
            '--mocks[MCP серверлерінің орнын басатын mock-тар, <eval dir>/mocks/ ішінен]:mode:(record off)' \
            '--allow-real-servers[--mocks record-пен: mock-ы жоқ нақты MCP сервер процестерін де іске қосу]' \
            '--keep-temp[Жөндеу үшін құрастыру каталогтарын сақтау]' \
            '--verbose[Әр хабарламаның трассалау оқиғаларын жөндеу журналына жазу]' \
            '--report[Дербес HTML есебін нәтижелер каталогының орнына осы жолға жазу]:path:_files' \
            '(--no-publish)--publish-report[Сондай-ақ есепті claude.ai-ге жариялауды талап ету]' \
            '(--publish-report)--no-publish[HTML есебін тек жергілікті сақтау; оны claude.ai-ге жариялауды өткізіп жіберу]' \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '::target: _alternative "plugins\:installed plugin\:_claude_installed_plugins" "files\:path\:_files"'
          ;;
        tag)
          _arguments \
            '--push[Тегті жасағаннан кейін оны --remote-қа жіберу]' \
            '--dry-run[Тегті жасамай-ақ, не тегтелетінін басып шығару]' \
            '(-f --force)'{-f,--force}'[Жұмыс ағашының таза еместігі және тегтің бұрыннан бар екені тексерулерін өткізіп жіберу]' \
            '(-m --message)'{-m,--message}'[Тег аннотациясының хабарламасы (нұсқа үшін %s пайдаланыңыз)]:msg:' \
            '--remote[--push кезінде жіберілетін remote]:name:' \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '::path:_files'
          ;;
        test)
          _arguments \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '::dir:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_plugin_marketplace() {
  local -a marketplace_commands
  marketplace_commands=(
    'add:URL, жол немесе GitHub репозиторийінен нарық қосу'
    'list:Конфигурацияланған нарықтардың тізімі'
    'remove:Конфигурацияланған нарықты жою'
    'rm:Конфигурацияланған нарықты жою (remove үшін бүркеншік ат)'
    'update:Көзден нарықты жаңарту - аты көрсетілмесе барлығын жаңарту'
    'help:Анықтаманы көрсету'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'marketplace commands' marketplace_commands
      ;;
    args)
      case $words[1] in
        add)
          _arguments \
            '--sparse[git sparse-checkout арқылы checkout-ты белгілі бір каталогтармен шектеу (монорепозиторийлер үшін)]:paths:' \
            '--scope[Нарықты қай жерде жариялау]:scope:(user project local)' \
            '--claudeai[claude.ai сіз үшін хосттайтын осы атаулы нарықты қосу]' \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '--json[JSON ретінде шығару]' \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]'
          ;;
        remove|rm)
          _arguments \
            '--scope[Нарық жариялауын белгілі бір параметрлер аясынан жою (барлық аядан жою үшін көрсетпеңіз)]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '1:name:'
          ;;
        update)
          _arguments \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '::name:'
          ;;
      esac
      ;;
  esac
}

_claude_install() {
  _arguments \
    '--force[Әлдеқашан орнатылған болса да мәжбүрлі орнату]' \
    '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
    '::target:(stable latest)'
}

_claude_agents() {
  _arguments \
    '*--add-dir[Жіберілген сессияларда құрал қолжетімділігіне рұқсат беру үшін қосымша каталог]:directory:_directories' \
    '--agent[Агент көрінісінен жіберілген сессиялар үшін әдепкі агент]:agent:_claude_agent_names' \
    '--all[--json-мен: аяқталған фондық сессияларды да қосу]' \
    '--allow-dangerously-skip-permissions[Жіберілген сессиялар үшін рұқсаттарды айналып өту режімін қолжетімді ету]' \
    '--cwd[Тек жол астында іске қосылған фондық сессияларды көрсету]:path:_directories' \
    '--dangerously-skip-permissions[--permission-mode bypassPermissions үшін бүркеншік ат]' \
    '--effort[Жіберілген сессиялар үшін әдепкі күш деңгейі]:level:(low medium high xhigh max)' \
    '--json[Белсенді сессияларды JSON массиві ретінде басып шығару және шығу]' \
    '*--mcp-config[Жіберілген сессияларға қолданылатын MCP сервер конфигурациясы]:config:' \
    '--model[Агент көрінісінен жіберілген сессиялар үшін әдепкі модель]:model:_claude_model_names' \
    '--permission-mode[Жіберілген сессиялар үшін әдепкі рұқсат режімі]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Агент көрінісі мен жіберілген сессиялар үшін каталогтан плагиндерді жүктеу]:path:_directories' \
    '--setting-sources[Жүктеу үшін үтірмен бөлінген параметр көздерінің тізімі (user, project, local)]:sources:' \
    '--settings[Қолданылатын параметрлер файлы немесе JSON жолы]:file-or-json:_files' \
    '--strict-mcp-config[Жіберілген сессияларда тек --mcp-config-тен MCP серверлерін пайдалану]' \
    '--restricted[Жіберілген сессияларды шектеулі режимде іске қосу]' \
    '(-h --help)'{-h,--help}'[Команда үшін анықтаманы көрсету]'
}

_claude_auth() {
  local -a auth_commands
  auth_commands=(
    'login:Anthropic тіркелгіңізге кіру'
    'logout:Anthropic тіркелгіңізден шығу'
    'status:Аутентификация күйін көрсету'
    'help:Анықтаманы көрсету'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Команда үшін анықтаманы көрсету]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'auth commands' auth_commands
      ;;
    args)
      case $words[1] in
        login)
          _arguments \
            '--email[Кіру бетінде электрондық пошта мекенжайын алдын ала толтыру]:email:' \
            '--sso[SSO кіру ағынын мәжбүрлеу]' \
            '(--claudeai)--console[Claude жазылымының орнына Anthropic Console (API пайдалану бойынша төлем) пайдалану]' \
            '(--console)--claudeai[Claude жазылымын пайдалану (әдепкі)]' \
            '(-h --help)'{-h,--help}'[Команда үшін анықтаманы көрсету]'
          ;;
        status)
          _arguments \
            '(--text)--json[JSON ретінде шығару (әдепкі)]' \
            '(--json)--text[Адам оқи алатын мәтін ретінде шығару]' \
            '(-h --help)'{-h,--help}'[Команда үшін анықтаманы көрсету]'
          ;;
        logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Команда үшін анықтаманы көрсету]'
          ;;
      esac
      ;;
  esac
}

_claude_auto_mode() {
  local -a auto_mode_commands
  auto_mode_commands=(
    'config:Тиімді авто режим конфигурациясын JSON ретінде басып шығару'
    'critique:Арнайы авто режим ережелеріңіз бойынша AI кері байланысын алу'
    'defaults:Әдепкі авто режим ережелерін JSON ретінде басып шығару'
    'reset:Авто режим конфигурациясын жеткізілген әдепкі мәндерге қалпына келтіру'
    'help:Анықтаманы көрсету'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Команда үшін анықтаманы көрсету]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'auto-mode commands' auto_mode_commands
      ;;
    args)
      case $words[1] in
        critique)
          _arguments \
            '--model[Пайдаланылатын модельді қайта анықтау]:model:_claude_model_names' \
            '(-h --help)'{-h,--help}'[Команда үшін анықтаманы көрсету]'
          ;;
        defaults)
          _arguments \
            '--label[Белгісі осы префикстен басталатын ережелерді ғана көрсету (регистрге сезімтал емес)]:prefix:' \
            '(-h --help)'{-h,--help}'[Команда үшін анықтаманы көрсету]'
          ;;
        reset)
          _arguments \
            '(-y --yes)'{-y,--yes}'[Растау сұрауын өткізіп жіберу]' \
            '(-h --help)'{-h,--help}'[Команда үшін анықтаманы көрсету]'
          ;;
        config)
          _arguments \
            '(-h --help)'{-h,--help}'[Команда үшін анықтаманы көрсету]'
          ;;
      esac
      ;;
  esac
}

_claude_gateway() {
  _arguments \
    '--config[Шлюз YAML конфигурациясының жолы]:path:_files' \
    '(-h --help)'{-h,--help}'[Команда үшін анықтаманы көрсету]'
}

_claude_project() {
  local -a project_commands
  project_commands=(
    'purge:Жоба үшін барлық Claude Code күйін жою (транскрипттер, тапсырмалар, файл тарихы, конфигурация жазбасы)'
    'help:Анықтаманы көрсету'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Команда үшін анықтаманы көрсету]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'project commands' project_commands
      ;;
    args)
      case $words[1] in
        purge)
          _arguments \
            '--dry-run[Ештеңені жоймай-ақ, не жойылатынын тізімдеу]' \
            '(-y --yes)'{-y,--yes}'[Растау сұрауын өткізіп жіберу]' \
            '(-i --interactive)'{-i,--interactive}'[Жою алдында әр элемент үшін сұрау]' \
            '(1)--all[Барлық жобалар үшін күйді тазалау (жолмен бірге қолданылмайды)]' \
            '(-h --help)'{-h,--help}'[Команда үшін анықтаманы көрсету]' \
            '(--all)::path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Пішімделген нәтижелердің орнына шикі bugs.json пайдалы жүктемесін басып шығару]' \
    '--timeout[Шолудың аяқталуын күтудің максималды минуттары (әдепкі: 45)]:minutes:' \
    '(--no-post)--post[Аяқталған шолу нәтижелерін PR-ге сіздің атыңыздан жариялау (тек PR мақсаттары үшін; шолу емес, бір қарапайым түсініктеме)]' \
    '(--post)--no-post[Нәтижелерді PR-ге жарияламау (әдепкі)]' \
    '(-h --help)'{-h,--help}'[Команда үшін анықтаманы көрсету]' \
    '1:target:'
}

_claude_respawn() {
  _arguments \
    '(1)--all[Жұмыс істеп тұрған барлық фондық сессияларды қайта іске қосу]' \
    '(-h --help)'{-h,--help}'[Команда үшін анықтаманы көрсету]' \
    '(--all)::session:_claude_background_sessions'
}

_claude_rm() {
  _arguments \
    '--discard-unpushed[Сондай-ақ worktree-дің жіберілмеген коммиттері мен коммиттелмеген өзгерістерін алып тастау (алдыңғы claude rm хабарлаған commit@worktree-id мәнін беріңіз)]:commit@worktree-id:' \
    '--force-remove-worktree[WorktreeRemove hook-ы немесе git жоя алмаса да, worktree каталогын жою (алдыңғы claude rm хабарлаған worktree-id мәнін беріңіз)]:worktree-id:' \
    '(-h --help)'{-h,--help}'[Команда үшін анықтаманы көрсету]' \
    '1:session:_claude_background_sessions'
}

_claude_import() {
  _arguments \
    '--dry-run[Ештеңе жазбай-ақ, не импортталатынын көрсету]' \
    '--yes[Интерактивті таңдаушыны өткізіп жіберу (headless ортада /import алдын ала қарауынан --yes=<digest> беріңіз)]' \
    '(-h --help)'{-h,--help}'[Команда үшін анықтаманы көрсету]' \
    '::source:(codex gemini cursor)'
}

(( $+_comps[claude] )) || compdef _claude claude
