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
    'mcp:Наладзіць і кіраваць MCP серверамі'
    'plugin:Кіраваць плагінамі Claude Code'
    'agents:Кіраваць фонавымі агентамі'
    'attach:Адкрыць фонавую сесію ў гэтым тэрмінале'
    'logs:Вывесці апошні вывад тэрмінала фонавай сесіі'
    'stop:Спыніць фонавую сесію (яе размова захоўваецца)'
    'respawn:Перазапусціць фонавую сесію, каб яна працавала на бягучай версіі Claude Code'
    'rm:Выдаліць фонавую сесію, а таксама яе worktree, калі гэта бяспечна'
    'auth:Кіраваць аўтэнтыфікацыяй'
    'auto-mode:Прагледзець або скінуць канфігурацыю класіфікатара аўтаматычнага рэжыму'
    'gateway:Запусціць карпаратыўны шлюз аўтэнтыфікацыі/тэлеметрыі'
    'import:Імпартаваць канфігурацыю з іншага AI агента для праграмавання ў Claude Code'
    'project:Кіраваць станам праекта Claude Code'
    'ultrareview:Запусціць размешчаны ў воблаку мультыагентны агляд кода і вывесці вынікі'
    'setup-token:Наладзіць токен доўгатэрміновай аўтэнтыфікацыі (патрабуецца падпіска Claude)'
    'doctor:Праверка здароўя сістэмы аўтаабнаўлення Claude Code'
    'update:Праверыць і ўсталяваць абнаўленні'
    'install:Усталяваць натыўную зборку Claude Code'
  )

  local -a main_options
  main_options=(
    '(-d --debug)'{-d,--debug}'[Уключыць рэжым адладкі з апцыянальнай фільтрацыяй катэгорый (напрыклад, "api,hooks" або "!statsig,!file")]:filter:'
    '--verbose[Перавызначыць наладу рэжыму падрабязнага вываду з канфігурацыйнага файла]'
    '(-p --print)'{-p,--print}'[Вывесці адказ і выйсці (для выкарыстання з pipe). Заўвага: выкарыстоўвайце толькі ў давераных дырэкторыях]'
    '--output-format[Фармат вываду (з --print): "text" (па змаўчанні), "json" (адзін вынік), або "stream-json" (патокавая перадача ў рэальным часе)]:format:(text json stream-json)'
    '--json-schema[JSON схема для валідацыі структураванага вываду]:schema:'
    '--include-partial-messages[Уключыць часткавыя фрагменты паведамленняў пры іх паступленні (з --print і --output-format=stream-json)]'
    '--input-format[Фармат уводу (з --print): "text" (па змаўчанні) або "stream-json" (патокавы ўвод у рэальным часе)]:format:(text stream-json)'
    '--mcp-debug[\[Састарэлае. Выкарыстоўвайце --debug замест гэтага\] Уключыць рэжым адладкі MCP (паказвае памылкі MCP сервера)]'
    '--dangerously-skip-permissions[Абмінуць усе праверкі дазволаў. Рэкамендуецца толькі для пясочніц без доступу да інтэрнэту]'
    '--allow-dangerously-skip-permissions[Уключыць опцыю абходу правероў дазволаў без уключэння па змаўчанні]'
    '--restricted[Абмежаваны рэжым: прыбраць інструменты, якія выконваюць каманды або код, і WebFetch, ігнараваць налады user/project/local і абмежаваць файлавыя інструменты працоўнымі дырэкторыямі]'
    '--max-budget-usd[Максімальная сума ў доларах для выдаткаў на API выклікі (толькі --print)]:amount:'
    '--replay-user-messages[Паўторна адправіць паведамленні карыстальніка з stdin на stdout для пацверджання]'
    '--allowed-tools[Спіс дазволеных імёнаў інструментаў праз коску або прабел (напрыклад, "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Спіс дазволеных імёнаў інструментаў праз коску або прабел (фармат camelCase)]:tools:'
    '--tools[Указаць спіс даступных інструментаў з убудаванага набору. Толькі ў рэжыме print]:tools:'
    '--disallowed-tools[Спіс забароненых імёнаў інструментаў праз коску або прабел (напрыклад, "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Спіс забароненых імёнаў інструментаў праз коску або прабел (фармат camelCase)]:tools:'
    '--mcp-config[Загрузіць MCP серверы з JSON файла або радка (падзеленыя прабеламі)]:configs:'
    '--system-prompt[Сістэмны промпт для выкарыстання ў сесіі]:prompt:'
    '--system-prompt-file[Прачытаць сістэмны промпт з файла]:file:_files'
    '--append-system-prompt[Дадаць сістэмны промпт да стандартнага сістэмнага промпту]:prompt:'
    '--append-system-prompt-file[Прачытаць сістэмны промпт з файла і дадаць яго да стандартнага сістэмнага промпту]:file:_files'
    '--system-prompt-snapshot[Запісаць сістэмны промпт адзін раз на размову і паўторна выкарыстоўваць яго дакладна без змен пры кожным запыце і аднаўленні (on, па змаўчанні) або фарміраваць яго нанова пры кожным запыце (off)]:mode:(on off)'
    '--permission-mode[Рэжым дазволаў для выкарыстання ў сесіі]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '--permission-prompts[Хто адказвае на запыты дазволаў з --print: "host" (хост SDK або --permission-prompt-tool) або "none" (усё, што запатрабавала б запыту, адхіляецца)]:target:(host none)'
    '--permission-prompt-tool[MCP інструмент для запытаў дазволаў (толькі --print)]:tool:'
    '(-c --continue)'{-c,--continue}'[Працягнуць апошнюю размову]'
    '(-r --resume)'{-r,--resume}'[Аднавіць размову - укажыце ідэнтыфікатар сесіі або выберыце інтэрактыўна]:sessionId:_claude_sessions'
    '--fork-session[Стварыць новы ідэнтыфікатар сесіі замест паўторнага выкарыстання арыгінальнага пры аднаўленні (з --resume або --continue)]'
    '--no-session-persistence[Адключыць захаванне сесіі - сесіі не будуць захаваны (толькі --print)]'
    '--model[Мадэль для бягучай сесіі. Укажыце псеўданім для апошняй мадэлі (напрыклад, '\''sonnet'\'' або '\''opus'\'')]:model:_claude_model_names'
    '--agent[Агент для бягучай сесіі. Перавызначае наладу '\''agent'\'']:agent:_claude_agent_names'
    '--betas[Beta загалоўкі для ўключэння ў API запыты (толькі для карыстальнікаў API ключа)]:betas:'
    '--fallback-model[Уключыць аўтаматычны пераход на ўказаную мадэль, калі мадэль па змаўчанні перагружана (толькі --print)]:model:_claude_model_names'
    '--settings[Шлях да JSON файла налад або JSON радок для загрузкі дадатковых налад]:file-or-json:_files'
    '--add-dir[Дадатковыя дырэкторыі для надання доступу інструментам]:directories:_directories'
    '--ide[Аўтаматычна падключыцца да IDE пры запуску, калі даступная роўна адна валідная IDE]'
    '--desktop[Адкрыць у праграме Claude Desktop замест тэрмінала (з --continue або --resume <id>, каб выбраць сесію)]'
    '--strict-mcp-config[Выкарыстоўваць толькі MCP серверы з --mcp-config і ігнараваць усе іншыя налады MCP]'
    '--session-id[Канкрэтны ідэнтыфікатар сесіі для выкарыстання ў размове (павінен быць валідны UUID)]:uuid:'
    '--agents[JSON аб'\''ект, які вызначае карыстальніцкія агенты]:json:'
    '--setting-sources[Спіс крыніц налад праз коску для загрузкі (user, project, local)]:sources:'
    '--plugin-dir[Дырэкторыя для загрузкі плагінаў толькі для гэтай сесіі (можна паўтараць)]:paths:_directories'
    '--disable-slash-commands[Адключыць усе слэш-каманды]'
    '(--bg --background)'{--bg,--background}'[Запусціць сесію як фонавы агент і адразу вярнуцца]'
    '(-w --worktree)'{-w,--worktree}'[Стварыць новы git worktree для гэтай сесіі (можна ўказаць назву)]::name:'
    '--tmux=-[Стварыць tmux сесію для worktree (патрабуецца --worktree). Выкарыстоўвае натыўныя панэлі iTerm2, калі даступныя; --tmux=classic для традыцыйнага tmux]::mode:(classic)'
    '(-n --name)'{-n,--name}'[Задаць адлюстроўваемую назву для гэтай сесіі]:name:'
    '--effort[Узровень намаганняў для бягучай сесіі]:level:(low medium high xhigh max)'
    '--autocompact[Памер акна аўтаматычнага сціскання (auto або 100k-1M токенаў)]:size:(auto)'
    '--debug-file[Запісваць логі адладкі ў пэўны файл (няяўна ўключае рэжым адладкі)]:path:_files'
    '--from-pr[Аднавіць сесію, звязаную з PR па нумары/URL, або адкрыць інтэрактыўны выбар]::value:'
    '--teleport[Аднавіць teleport сесію, з магчымасцю ўказаць ідэнтыфікатар сесіі]::session:'
    '--cloud[Стварыць воблачную сесію з зададзеным апісаннем або падключыцца да існуючай па ідэнтыфікатары сесіі або URL claude.ai/code]::description-or-session:'
    '--environment[Стварыць новую воблачную сесію, якая працуе ў зададзеным самастойна размешчаным асяроддзі (ccpool_...)]:environment_id:'
    '--remote-control[Запусціць інтэрактыўную сесію з уключаным Remote Control (можна назваць)]::name:'
    '--remote-control-session-name-prefix[Прэфікс для аўтаматычна генераваных назваў сесій Remote Control]:prefix:'
    '--chrome[Уключыць інтэграцыю Claude у Chrome]'
    '--no-chrome[Адключыць інтэграцыю Claude у Chrome]'
    '--plugin-url[Атрымаць плагін .zip з URL толькі для гэтай сесіі (можна паўтараць)]:url:'
    '--file[Файлавыя рэсурсы для спампоўкі пры запуску (фармат: file_id:relative_path)]:specs:'
    '--prompt-suggestions[Уключыць прапановы промптаў (выдае прагназаваны наступны промпт у рэжыме print/SDK)]::value:(true false 1 0 yes no on off)'
    '--forward-subagent-text[Перадаваць тэкст субагента і блокі разважанняў як паведамленні (з --print і stream-json)]'
    '--include-hook-events[Уключыць усе падзеі жыццёвага цыклу хукаў у паток вываду (з stream-json)]'
    '--exclude-dynamic-system-prompt-sections[Перамясціць секцыі, залежныя ад машыны, у першае паведамленне карыстальніка для паляпшэння паўторнага выкарыстання кэша промптаў]'
    '--brief[Уключыць інструмент SendUserMessage для сувязі агента з карыстальнікам]'
    '--safe-mode[Запусціць з адключанымі ўсімі наладкамі (карысна для дыягностыкі зламанай канфігурацыі)]'
    '--bare[Мінімальны рэжым: прапусціць хукі, LSP, сінхранізацыю плагінаў, атрыбуцыю, аўтапамяць і аўтаматычнае выяўленне CLAUDE.md]'
    '--ax-screen-reader[Выводзіць вывад, зручны для чытачоў з экрана (плоскі тэкст, без дэкаратыўных рамак ці анімацый)]'
    '(-v --version)'{-v,--version}'[Вывесці нумар версіі]'
    '(-h --help)'{-h,--help}'[Паказаць даведку для каманды]'
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
            '(-h --help)'{-h,--help}'[Паказаць даведку для каманды]' \
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
          _message "без аргументаў"
          ;;
      esac
      ;;
  esac
}

_claude_mcp() {
  local -a mcp_commands
  mcp_commands=(
    'serve:Запусціць MCP сервер Claude Code'
    'add:Дадаць MCP сервер да Claude Code'
    'remove:Выдаліць MCP сервер'
    'list:Паказаць спіс наладжаных MCP сервераў'
    'get:Атрымаць дэталі MCP сервера'
    'add-json:Дадаць MCP сервер (stdio або SSE) з JSON радком'
    'add-from-claude-desktop:Імпартаваць MCP серверы з Claude Desktop (толькі Mac і WSL)'
    'reset-project-choices:Скінуць усе ўхваленыя/адхіленыя серверы з абсягам дзеяння праекта (.mcp.json) у гэтым праекце'
    'login:Аўтэнтыфікавацца на MCP серверы (HTTP, SSE або канектар claude.ai)'
    'logout:Ачысціць захаваныя OAuth уліковыя даныя для MCP сервера'
    'help:Паказаць даведку'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Паказаць даведку]' \
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
            '(-d --debug)'{-d,--debug}'[Уключыць рэжым адладкі]' \
            '--verbose[Перавызначыць наладу рэжыму падрабязнага вываду з канфігурацыйнага файла]' \
            '(-h --help)'{-h,--help}'[Паказаць даведку]'
          ;;
        add)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Абсяг дзеяння канфігурацыі (local, user, project)]:scope:(local user project)' \
            '(-t --transport)'{-t,--transport}'[Тып транспарту (stdio, sse, http)]:transport:(stdio sse http)' \
            '(-e --env)'{-e,--env}'[Усталяваць зменную асяроддзя (напрыклад, -e KEY=value)]:env:' \
            '(-H --header)'{-H,--header}'[Усталяваць загаловак WebSocket]:header:' \
            '--client-id[Ідэнтыфікатар кліента OAuth для HTTP/SSE сервераў]:clientId:' \
            '--client-secret[Запытаць сакрэт кліента OAuth (або задаць зменную асяроддзя MCP_CLIENT_SECRET)]' \
            '--callback-port[Фіксаваны порт для зваротнага выкліку OAuth (для сервераў, якія патрабуюць папярэдне зарэгістраваных URI перанакіравання)]:port:' \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:name:' \
            '2:commandOrUrl:' \
            '*:args:'
          ;;
        remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Абсяг дзеяння канфігурацыі (local, user, project) - выдаліць з існуючага абсягу, калі не ўказана]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:name:_claude_mcp_servers'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Паказаць даведку]'
          ;;
        get)
          _arguments \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:name:_claude_mcp_servers'
          ;;
        add-json)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Абсяг дзеяння канфігурацыі (local, user, project)]:scope:(local user project)' \
            '--client-secret[Запытаць сакрэт кліента OAuth (або задаць зменную асяроддзя MCP_CLIENT_SECRET)]' \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:name:' \
            '2:json:'
          ;;
        add-from-claude-desktop)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Абсяг дзеяння канфігурацыі (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Паказаць даведку]'
          ;;
        reset-project-choices)
          _arguments \
            '(-h --help)'{-h,--help}'[Паказаць даведку]'
          ;;
        login)
          _arguments \
            '--no-browser[Вывесці URL аўтарызацыі замест адкрыцця браўзера (для SSH/headless сесій)]' \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:name:_claude_mcp_servers'
          ;;
        logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:name:_claude_mcp_servers'
          ;;
      esac
      ;;
  esac
}

_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:Валідаваць плагін або маніфест маркетплэйса'
    'marketplace:Кіраваць маркетплэйсамі Claude Code'
    'list:Паказаць спіс усталяваных плагінаў'
    'details:Паказаць інвентар кампанентаў і прагназаваны кошт токенаў для плагіна'
    'configure:Паказаць опцыі плагіна і якія з іх не зададзены, або захаваць значэнні з stdin'
    'install:Усталяваць плагін з даступных маркетплэйсаў'
    'i:Усталяваць плагін з даступных маркетплэйсаў (скарочана для install)'
    'init:Стварыць каркас новага плагіна (аўтаматычна загружаецца ў наступнай сесіі)'
    'new:Стварыць каркас новага плагіна (псеўданім для init)'
    'uninstall:Выдаліць усталяваны плагін'
    'remove:Выдаліць усталяваны плагін (псеўданім для uninstall)'
    'enable:Уключыць выключаны плагін'
    'disable:Выключыць уключаны плагін'
    'update:Абнавіць плагін да апошняй версіі'
    'eval:Запусціць eval выпадкі супраць плагіна і паведаміць ацэненыя вынікі'
    'prune:Выдаліць аўтаматычна ўсталяваныя залежнасці, якія больш не патрэбны'
    'autoremove:Выдаліць аўтаматычна ўсталяваныя залежнасці, якія больш не патрэбны (псеўданім для prune)'
    'tag:Стварыць git тэг {name}--v{version} для рэлізу плагіна'
    'test:Запусціць тэсты мода'
    'help:Паказаць даведку'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Паказаць даведку]' \
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
            '--strict[Лічыць папярэджанні памылкамі (код выхаду 1)]' \
            '--json[Вывесці справаздачу аб валідацыі як JSON (тыя ж коды выхаду)]' \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Абсяг усталёўкі]:scope:(user project local)' \
            '*--config[Задаць опцыю userConfig, аб'\''яўленую ў маніфесце плагіна (можна паўтараць)]:key=value:' \
            '(-y --yes)'{-y,--yes}'[Прыняць паказаную каманду, аб'\''яўленую маркетплэйсам, без запыту пацверджання]' \
            '--json[Вывесці адзін машыначытэльны радок выніку замест паведамлення для чалавека]' \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Абсяг усталёўкі]:scope:(user project local)' \
            '--keep-data[Захаваць дырэкторыю пастаянных даных плагіна]' \
            '--prune[Таксама выдаліць аўтаматычна ўсталяваныя залежнасці, якія больш не патрэбны]' \
            '(-y --yes)'{-y,--yes}'[Прапусціць запыт пацверджання --prune]' \
            '--json[Вывесці адзін машыначытэльны радок выніку замест паведамлення для чалавека (не з --prune)]' \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Абсяг усталёўкі]:scope:(user project local)' \
            '--json[Вывесці адзін машыначытэльны радок выніку замест паведамлення для чалавека]' \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        disable)
          _arguments \
            '(-a --all)'{-a,--all}'[Выключыць усе ўключаныя плагіны]' \
            '(-s --scope)'{-s,--scope}'[Абсяг усталёўкі]:scope:(user project local)' \
            '--json[Вывесці адзін машыначытэльны радок выніку замест паведамлення для чалавека]' \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '::plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Абсяг усталёўкі]:scope:(user project local managed)' \
            '(-y --yes)'{-y,--yes}'[Прыняць паказаную каманду, аб'\''яўленую маркетплэйсам, без запыту пацверджання]' \
            '--json[Вывесці адзін машыначытэльны радок выніку замест паведамлення для чалавека]' \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list)
          _arguments \
            '--json[Вывесці як JSON]' \
            '--available[Уключыць даступныя плагіны з маркетплэйсаў (патрабуецца --json)]' \
            '(-h --help)'{-h,--help}'[Паказаць даведку]'
          ;;
        prune|autoremove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Ачысціць у абсягу]:scope:(user project local)' \
            '--dry-run[Паказаць спіс таго, што было б выдалена, без выдалення]' \
            '(-y --yes)'{-y,--yes}'[Прапусціць запыт пацверджання]' \
            '(-h --help)'{-h,--help}'[Паказаць даведку]'
          ;;
        configure)
          _arguments \
            '--json[Вывесці як JSON]' \
            '--values-stdin[Прачытаць значэнні опцый з stdin як JSON аб'\''ект аднарадковых радкоў; неўказаныя опцыі захоўваюць свае значэнні]' \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init|new)
          _arguments \
            '--description[Апісанне маніфеста]:text:' \
            '--author[Імя аўтара (па змаўчанні: git config user.name)]:name:' \
            '--author-email[Email аўтара (па змаўчанні: git config user.email)]:email:' \
            '--with[Кампаненты, для якіх таксама стварыць каркас]:components:' \
            '(-f --force)'{-f,--force}'[Перазапісаць існуючы .claude-plugin/ у мэтавым месцы]' \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '--case[Фільтраваць выпадкі па glob-шаблоне назвы]:glob:' \
            '*--tag[Фільтраваць выпадкі па тэгу (можна паўтараць)]:tag:' \
            '--runs[Перавызначыць колькасць запускаў на выпадак (па змаўчанні: case.runs, інакш 3)]:n:' \
            '(-j --concurrency)'{-j,--concurrency}'[Выконваць да n запускаў агента адначасова (1-8; па змаўчанні 1)]:n:' \
            '--model[Перавызначыць мадэль для ўсіх выпадкаў]:model:_claude_model_names' \
            '--judge-model[Перавызначыць мадэль LLM-ацэншчыка (па змаўчанні: haiku)]:model:_claude_model_names' \
            '--max-cost-usd[Жорсткі ліміт выдаткаў; пры яго дасягненні перапыніць і паведаміць частковыя вынікі (код выхаду 2)]:usd:' \
            '--output-dir[Дырэкторыя для aggregate-result.json]:dir:_directories' \
            '--eval-dir[Назва дырэкторыі (унутры плагіна), якая змяшчае eval выпадкі]:dir:' \
            '--json[Вывесці поўны вынік запуску як JSON у stdout або запісаць яго ў гэты .json файл]::path:_files' \
            '--threshold[Выйсці з кодам выхаду 1, калі ацэнка любога выпадку ніжэй за гэты парог (па змаўчанні: 1.0)]:threshold:' \
            '*--allow-tools[Дазвол аператара для абмежаваных інструментаў (Bash, Write, Edit, WebFetch, mcp__*)]:tools:' \
            '(--no-scaffold)--scaffold[Запускаць scaffold_script кожнага выпадку (выконвае bash, нададзены аўтарам, ад вашага імя; па змаўчанні выключана)]' \
            '(--scaffold)--no-scaffold[Яўна прапусціць scaffold_script]' \
            '--trust-plugin[Пацвердзіць, што вы давяраеце гэтаму плагіну і яго набору eval, прапусціўшы запыт даверу пры першым запуску (для CI)]' \
            '--ablation[Запусціць кантрольную групу без плагіна і паведаміць розніцу ацэнак]:mode:(none with-without)' \
            '--mocks[Mock-замены для MCP сервераў з <eval dir>/mocks/]:mode:(record off)' \
            '--allow-real-servers[З --mocks record: таксама запусціць рэальныя працэсы MCP сервераў, для якіх няма mock]' \
            '--keep-temp[Захаваць дырэкторыі каркаса для адладкі]' \
            '--verbose[Запісваць падзеі трасіроўкі для кожнага паведамлення ў лог адладкі]' \
            '--report[Запісаць аўтаномную HTML справаздачу па гэтым шляху замест дырэкторыі вынікаў]:path:_files' \
            '(--no-publish)--publish-report[Таксама патрабаваць публікацыі справаздачы на claude.ai]' \
            '(--publish-report)--no-publish[Захоўваць HTML справаздачу толькі лакальна; не публікаваць яе на claude.ai]' \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '::target: _alternative "plugins\:installed plugin\:_claude_installed_plugins" "files\:path\:_files"'
          ;;
        tag)
          _arguments \
            '--push[Адправіць тэг у --remote пасля яго стварэння]' \
            '--dry-run[Вывесці, што было б пазначана тэгам, без яго стварэння]' \
            '(-f --force)'{-f,--force}'[Прапусціць праверкі на незакамічаныя змены ў працоўным дрэве і на ўжо існуючы тэг]' \
            '(-m --message)'{-m,--message}'[Паведамленне анатацыі тэга (выкарыстоўвайце %s для версіі)]:msg:' \
            '--remote[Remote, у які адпраўляць з --push]:name:' \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '::path:_files'
          ;;
        test)
          _arguments \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '::dir:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_plugin_marketplace() {
  local -a marketplace_commands
  marketplace_commands=(
    'add:Дадаць маркетплэйс з URL, шляху або GitHub рэпазіторыя'
    'list:Паказаць спіс наладжаных маркетплэйсаў'
    'remove:Выдаліць наладжаны маркетплэйс'
    'rm:Выдаліць наладжаны маркетплэйс (псеўданім для remove)'
    'update:Абнавіць маркетплэйс з крыніцы - абнавіць усе, калі назва не ўказана'
    'help:Паказаць даведку'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Паказаць даведку]' \
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
            '--sparse[Абмежаваць checkout пэўнымі дырэкторыямі праз git sparse-checkout (для монарэпазіторыяў)]:paths:' \
            '--scope[Дзе аб'\''явіць маркетплэйс]:scope:(user project local)' \
            '--claudeai[Дадаць маркетплэйс з гэтай назвай, які claude.ai размяшчае для вас]' \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '--json[Вывесці як JSON]' \
            '(-h --help)'{-h,--help}'[Паказаць даведку]'
          ;;
        remove|rm)
          _arguments \
            '--scope[Выдаліць аб'\''яву маркетплэйса з пэўнага абсягу налад (не ўказвайце, каб выдаліць яе з усіх абсягаў)]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:name:'
          ;;
        update)
          _arguments \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '::name:'
          ;;
      esac
      ;;
  esac
}

_claude_install() {
  _arguments \
    '--force[Прымусовая ўсталёўка, нават калі ўжо ўсталявана]' \
    '(-h --help)'{-h,--help}'[Паказаць даведку]' \
    '::target:(stable latest)'
}

_claude_agents() {
  _arguments \
    '*--add-dir[Дадатковая дырэкторыя для надання доступу інструментам у дыспетчарызаваных сесіях]:directory:_directories' \
    '--agent[Агент па змаўчанні для сесій, дыспетчарызаваных з выгляду агентаў]:agent:_claude_agent_names' \
    '--all[З --json: таксама ўключыць завершаныя фонавыя сесіі]' \
    '--allow-dangerously-skip-permissions[Зрабіць рэжым абыходу дазволаў даступным для дыспетчарызаваных сесій]' \
    '--cwd[Паказаць толькі фонавыя сесіі, запушчаныя пад шляхам]:path:_directories' \
    '--dangerously-skip-permissions[Псеўданім для --permission-mode bypassPermissions]' \
    '--effort[Узровень намаганняў па змаўчанні для дыспетчарызаваных сесій]:level:(low medium high xhigh max)' \
    '--json[Вывесці актыўныя сесіі як JSON масіў і выйсці]' \
    '*--mcp-config[Канфігурацыя MCP сервера для прымянення да дыспетчарызаваных сесій]:config:' \
    '--model[Мадэль па змаўчанні для сесій, дыспетчарызаваных з выгляду агентаў]:model:_claude_model_names' \
    '--permission-mode[Рэжым дазволаў па змаўчанні для дыспетчарызаваных сесій]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Загружаць плагіны з дырэкторыі для выгляду агентаў і дыспетчарызаваных сесій]:path:_directories' \
    '--setting-sources[Спіс крыніц налад праз коску для загрузкі (user, project, local)]:sources:' \
    '--settings[Файл налад або JSON радок для прымянення]:file-or-json:_files' \
    '--strict-mcp-config[Выкарыстоўваць толькі MCP серверы з --mcp-config у дыспетчарызаваных сесіях]' \
    '--restricted[Запускаць дыспетчарызаваныя сесіі ў абмежаваным рэжыме]' \
    '(-h --help)'{-h,--help}'[Паказаць даведку для каманды]'
}

_claude_auth() {
  local -a auth_commands
  auth_commands=(
    'login:Увайсці ў ваш акаўнт Anthropic'
    'logout:Выйсці з вашага акаўнта Anthropic'
    'status:Паказаць статус аўтэнтыфікацыі'
    'help:Паказаць даведку'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Паказаць даведку для каманды]' \
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
            '--email[Папярэдне запоўніць адрас email на старонцы ўваходу]:email:' \
            '--sso[Прымусова выкарыстаць уваход праз SSO]' \
            '(--claudeai)--console[Выкарыстоўваць Anthropic Console (аплата за выкарыстанне API) замест падпіскі Claude]' \
            '(--console)--claudeai[Выкарыстоўваць падпіску Claude (па змаўчанні)]' \
            '(-h --help)'{-h,--help}'[Паказаць даведку для каманды]'
          ;;
        status)
          _arguments \
            '(--text)--json[Вывесці як JSON (па змаўчанні)]' \
            '(--json)--text[Вывесці як тэкст, зручны для чытання чалавекам]' \
            '(-h --help)'{-h,--help}'[Паказаць даведку для каманды]'
          ;;
        logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Паказаць даведку для каманды]'
          ;;
      esac
      ;;
  esac
}

_claude_auto_mode() {
  local -a auto_mode_commands
  auto_mode_commands=(
    'config:Вывесці дзейную канфігурацыю аўтаматычнага рэжыму як JSON'
    'critique:Атрымаць AI водгук па вашых карыстальніцкіх правілах аўтаматычнага рэжыму'
    'defaults:Вывесці правілы аўтаматычнага рэжыму па змаўчанні як JSON'
    'reset:Скінуць канфігурацыю аўтаматычнага рэжыму да пастаўленых значэнняў па змаўчанні'
    'help:Паказаць даведку'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Паказаць даведку для каманды]' \
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
            '--model[Перавызначыць мадэль, якая выкарыстоўваецца]:model:_claude_model_names' \
            '(-h --help)'{-h,--help}'[Паказаць даведку для каманды]'
          ;;
        defaults)
          _arguments \
            '--label[Паказаць толькі правілы, метка якіх пачынаецца з гэтага прэфікса (без уліку рэгістра)]:prefix:' \
            '(-h --help)'{-h,--help}'[Паказаць даведку для каманды]'
          ;;
        reset)
          _arguments \
            '(-y --yes)'{-y,--yes}'[Прапусціць запыт пацверджання]' \
            '(-h --help)'{-h,--help}'[Паказаць даведку для каманды]'
          ;;
        config)
          _arguments \
            '(-h --help)'{-h,--help}'[Паказаць даведку для каманды]'
          ;;
      esac
      ;;
  esac
}

_claude_gateway() {
  _arguments \
    '--config[Шлях да YAML канфігурацыі шлюза]:path:_files' \
    '(-h --help)'{-h,--help}'[Паказаць даведку для каманды]'
}

_claude_project() {
  local -a project_commands
  project_commands=(
    'purge:Выдаліць увесь стан Claude Code для праекта (транскрыпты, задачы, гісторыя файлаў, запіс канфігурацыі)'
    'help:Паказаць даведку'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Паказаць даведку для каманды]' \
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
            '--dry-run[Паказаць спіс таго, што было б выдалена, нічога не выдаляючы]' \
            '(-y --yes)'{-y,--yes}'[Прапусціць запыт пацверджання]' \
            '(-i --interactive)'{-i,--interactive}'[Запытваць пацверджанне для кожнага элемента перад выдаленнем]' \
            '(1)--all[Выдаліць стан для ўсіх праектаў (узаемна выключае ўказанне шляху)]' \
            '(-h --help)'{-h,--help}'[Паказаць даведку для каманды]' \
            '(--all)::path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Вывесці неапрацаваны bugs.json замест адфарматаваных вынікаў]' \
    '--timeout[Максімальная колькасць хвілін чакання завяршэння агляду (па змаўчанні: 45)]:minutes:' \
    '(--no-post)--post[Апублікаваць вынікі завершанага агляду ў PR ад вашага імя (толькі для мэтаў-PR; адзін звычайны каментарый, не review)]' \
    '(--post)--no-post[Не публікаваць вынікі ў PR (па змаўчанні)]' \
    '(-h --help)'{-h,--help}'[Паказаць даведку для каманды]' \
    '1:target:'
}

_claude_respawn() {
  _arguments \
    '(1)--all[Перазапусціць усе запушчаныя фонавыя сесіі]' \
    '(-h --help)'{-h,--help}'[Паказаць даведку для каманды]' \
    '(--all)::session:_claude_background_sessions'
}

_claude_rm() {
  _arguments \
    '--discard-unpushed[Таксама адкінуць неадпраўленыя каміты і незакамічаныя змены worktree (перадайце commit@worktree-id, які паведаміў папярэдні claude rm)]:commit@worktree-id:' \
    '--force-remove-worktree[Выдаліць дырэкторыю worktree, нават калі хук WorktreeRemove або git не змаглі яе выдаліць (перадайце worktree-id, які паведаміў папярэдні claude rm)]:worktree-id:' \
    '(-h --help)'{-h,--help}'[Паказаць даведку для каманды]' \
    '1:session:_claude_background_sessions'
}

_claude_import() {
  _arguments \
    '--dry-run[Паказаць, што было б імпартавана, нічога не запісваючы]' \
    '--yes[Прапусціць інтэрактыўны выбар (у headless асяроддзях перадайце --yes=<digest> з папярэдняга прагляду /import)]' \
    '(-h --help)'{-h,--help}'[Паказаць даведку для каманды]' \
    '::source:(codex gemini cursor)'
}

(( $+_comps[claude] )) || compdef _claude claude
