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
    'mcp:MCP серверлерін конфигурациялау және басқару'
    'plugin:Claude Code плагиндерін басқару'
    'agents:Фондық агенттерді басқару'
    'auth:Аутентификацияны басқару'
    'auto-mode:Авто режим классификаторының конфигурациясын тексеру немесе қалпына келтіру'
    'gateway:Кәсіпорын аутентификация/телеметрия шлюзін іске қосу'
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
    '--max-budget-usd[API шақыруларына жұмсалатын максималды доллар сомасы (тек --print)]:amount:'
    '--replay-user-messages[Растау үшін stdin-ден stdout-қа пайдаланушы хабарламаларын қайта жіберу]'
    '--allowed-tools[Үтірмен немесе бос орынмен бөлінген рұқсат етілген құрал атауларының тізімі (мысалы, "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Үтірмен немесе бос орынмен бөлінген рұқсат етілген құрал атауларының тізімі (camelCase форматы)]:tools:'
    '--tools[Кірістірілген жиынтықтан қолжетімді құралдар тізімін көрсету. Тек басып шығару режімі]:tools:'
    '--disallowed-tools[Үтірмен немесе бос орынмен бөлінген тыйым салынған құрал атауларының тізімі (мысалы, "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Үтірмен немесе бос орынмен бөлінген тыйым салынған құрал атауларының тізімі (camelCase форматы)]:tools:'
    '--mcp-config[JSON файлынан немесе жолдан MCP серверлерін жүктеу (бос орынмен бөлінген)]:configs:'
    '--system-prompt[Сессия үшін жүйелік ескерту]:prompt:'
    '--append-system-prompt[Әдепкі жүйелік ескертуге жүйелік ескертуді қосу]:prompt:'
    '--permission-mode[Сессия үшін рұқсат режімі]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Ең соңғы әңгімені жалғастыру]'
    '(-r --resume)'{-r,--resume}'[Әңгімені жалғастыру - сессия идентификаторын көрсетіңіз немесе интерактивті түрде таңдаңыз]:sessionId:_claude_sessions'
    '--fork-session[Жалғастыру кезінде түпнұсқа сессия идентификаторын қайта пайдалану орнына жаңа сессия идентификаторын жасау (--resume немесе --continue-мен)]'
    '--no-session-persistence[Сессия сақтауын өшіру - сессиялар сақталмайды (тек --print)]'
    '--model[Ағымдағы сессия үшін модель. Ең соңғы модель үшін бүркеншік атты көрсетіңіз (мысалы, '\''sonnet'\'' немесе '\''opus'\'')]:model:'
    '--agent[Ағымдағы сессия үшін агент. '\''agent'\'' параметрін қайта анықтайды]:agent:'
    '--betas[API сұрауларына қосылатын бета тақырыптары (тек API кілт пайдаланушылары)]:betas:'
    '--fallback-model[Әдепкі модель жүктелген кезде көрсетілген модельге автоматты қосалқы ауысуды қосу (тек --print)]:model:'
    '--settings[Қосымша параметрлерді жүктеу үшін параметрлер JSON файлы немесе JSON жолының жолы]:file-or-json:_files'
    '--add-dir[Құрал қолжетімділігіне рұқсат беру үшін қосымша каталогтар]:directories:_directories'
    '--ide[Іске қосу кезінде дәл бір жарамды IDE қол жетімді болса, автоматты түрде IDE-ге қосылу]'
    '--strict-mcp-config[Тек --mcp-config-тен MCP серверлерін пайдалану және басқа барлық MCP параметрлерін елемеу]'
    '--session-id[Әңгіме үшін арнайы сессия идентификаторы (жарамды UUID болуы керек)]:uuid:'
    '--agents[Арнайы агенттерді анықтайтын JSON нысаны]:json:'
    '--setting-sources[Жүктеу үшін үтірмен бөлінген параметр көздерінің тізімі (user, project, local)]:sources:'
    '--plugin-dir[Тек осы сессия үшін плагиндерді жүктеу үшін каталог (қайталанатын)]:paths:_directories'
    '--disable-slash-commands[Барлық қиғаш сызық командаларын өшіру]'
    '(--bg --background)'{--bg,--background}'[Сессияны фондық агент ретінде іске қосу және дереу қайту]'
    '(-w --worktree)'{-w,--worktree}'[Осы сессия үшін жаңа git worktree жасау (қосымша ат көрсетуге болады)]::name:'
    '--tmux[worktree үшін tmux сессиясын жасау (--worktree қажет)]'
    '(-n --name)'{-n,--name}'[Осы сессия үшін көрсету атауын орнату]:name:'
    '--effort[Ағымдағы сессия үшін күш деңгейі]:level:(low medium high xhigh max)'
    '--debug-file[Жөндеу журналдарын белгілі бір файл жолына жазу (жасырын түрде жөндеу режімін қосады)]:path:_files'
    '--from-pr[Нөмір/URL бойынша PR-ге байланысты сессияны жалғастыру немесе интерактивті таңдаушыны ашу]::value:'
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
        login|logout)
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
    'install:Қол жетімді нарықтардан плагин орнату'
    'i:Қол жетімді нарықтардан плагин орнату (install үшін қысқа)'
    'init:Жаңа плагинді құрастыру (келесі сессияда автоматты жүктеледі)'
    'uninstall:Орнатылған плагинді жою'
    'remove:Орнатылған плагинді жою (uninstall үшін бүркеншік ат)'
    'enable:Өшірілген плагинді қосу'
    'disable:Қосылған плагинді өшіру'
    'update:Плагинді ең соңғы нұсқаға жаңарту'
    'eval:Плагинге қарсы бағалау жағдайларын іске қосу және бағаланған нәтижелерді есептеу'
    'prune:Қажет емес автоматты орнатылған тәуелділіктерді жою'
    'tag:Плагин шығарылымы үшін {name}--v{version} git тегін жасау'
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
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Орнату аясы]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Орнату аясы]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Орнату аясы]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Орнату аясы]:scope:(user project local managed)' \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list|prune)
          _arguments \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init)
          _arguments \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '1:target:'
          ;;
        tag)
          _arguments \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '1:path:_files'
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
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Анықтаманы көрсету]'
          ;;
        remove|rm)
          _arguments \
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
    '--agent[Агент көрінісінен жіберілген сессиялар үшін әдепкі агент]:agent:' \
    '--all[--json-мен: аяқталған фондық сессияларды да қосу]' \
    '--allow-dangerously-skip-permissions[Жіберілген сессиялар үшін рұқсаттарды айналып өту режімін қолжетімді ету]' \
    '--cwd[Тек жол астында іске қосылған фондық сессияларды көрсету]:path:_directories' \
    '--dangerously-skip-permissions[--permission-mode bypassPermissions үшін бүркеншік ат]' \
    '--effort[Жіберілген сессиялар үшін әдепкі күш деңгейі]:level:(low medium high xhigh max)' \
    '--json[Белсенді сессияларды JSON массиві ретінде басып шығару және шығу]' \
    '*--mcp-config[Жіберілген сессияларға қолданылатын MCP сервер конфигурациясы]:config:' \
    '--model[Агент көрінісінен жіберілген сессиялар үшін әдепкі модель]:model:' \
    '--permission-mode[Жіберілген сессиялар үшін әдепкі рұқсат режімі]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Агент көрінісі мен жіберілген сессиялар үшін каталогтан плагиндерді жүктеу]:path:_directories' \
    '--setting-sources[Жүктеу үшін үтірмен бөлінген параметр көздерінің тізімі (user, project, local)]:sources:' \
    '--settings[Қолданылатын параметрлер файлы немесе JSON жолы]:file-or-json:_files' \
    '--strict-mcp-config[Жіберілген сессияларда тек --mcp-config-тен MCP серверлерін пайдалану]' \
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
        login|logout|status)
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
        config|critique|defaults|reset)
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
            '(-h --help)'{-h,--help}'[Команда үшін анықтаманы көрсету]' \
            '1:path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Пішімделген нәтижелердің орнына шикі bugs.json пайдалы жүктемесін басып шығару]' \
    '--timeout[Шолудың аяқталуын күтудің максималды минуттары]:minutes:' \
    '(-h --help)'{-h,--help}'[Команда үшін анықтаманы көрсету]' \
    '1:target:'
}

(( $+_comps[claude] )) || compdef _claude claude
