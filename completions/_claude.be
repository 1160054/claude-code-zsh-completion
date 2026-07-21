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
    'mcp:Наладзіць і кіраваць MCP серверамі'
    'plugin:Кіраваць плагінамі Claude Code'
    'agents:Кіраваць фонавымі агентамі'
    'auth:Кіраваць аўтэнтыфікацыяй'
    'auto-mode:Прагледзець або скінуць канфігурацыю класіфікатара аўтаматычнага рэжыму'
    'gateway:Запусціць карпаратыўны шлюз аўтэнтыфікацыі/тэлеметрыі'
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
    '--max-budget-usd[Максімальная сума ў доларах для выдаткаў на API выклікі (толькі --print)]:amount:'
    '--replay-user-messages[Паўторна адправіць паведамленні карыстальніка з stdin на stdout для пацверджання]'
    '--allowed-tools[Спіс дазволеных імёнаў інструментаў праз коску або прабел (напрыклад, "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Спіс дазволеных імёнаў інструментаў праз коску або прабел (фармат camelCase)]:tools:'
    '--tools[Указаць спіс даступных інструментаў з убудаванага набору. Толькі ў рэжыме print]:tools:'
    '--disallowed-tools[Спіс забароненых імёнаў інструментаў праз коску або прабел (напрыклад, "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Спіс забароненых імёнаў інструментаў праз коску або прабел (фармат camelCase)]:tools:'
    '--mcp-config[Загрузіць MCP серверы з JSON файла або радка (падзеленыя прабеламі)]:configs:'
    '--system-prompt[Сістэмны промпт для выкарыстання ў сесіі]:prompt:'
    '--append-system-prompt[Дадаць сістэмны промпт да стандартнага сістэмнага промпту]:prompt:'
    '--permission-mode[Рэжым дазволаў для выкарыстання ў сесіі]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Працягнуць апошнюю размову]'
    '(-r --resume)'{-r,--resume}'[Аднавіць размову - укажыце ідэнтыфікатар сесіі або выберыце інтэрактыўна]:sessionId:_claude_sessions'
    '--fork-session[Стварыць новы ідэнтыфікатар сесіі замест паўторнага выкарыстання арыгінальнага пры аднаўленні (з --resume або --continue)]'
    '--no-session-persistence[Адключыць захаванне сесіі - сесіі не будуць захаваны (толькі --print)]'
    '--model[Мадэль для бягучай сесіі. Укажыце псеўданім для апошняй мадэлі (напрыклад, '\''sonnet'\'' або '\''opus'\'')]:model:'
    '--agent[Агент для бягучай сесіі. Перавызначае наладу '\''agent'\'']:agent:'
    '--betas[Beta загалоўкі для ўключэння ў API запыты (толькі для карыстальнікаў API ключа)]:betas:'
    '--fallback-model[Уключыць аўтаматычны пераход на ўказаную мадэль, калі мадэль па змаўчанні перагружана (толькі --print)]:model:'
    '--settings[Шлях да JSON файла налад або JSON радок для загрузкі дадатковых налад]:file-or-json:_files'
    '--add-dir[Дадатковыя дырэкторыі для надання доступу інструментам]:directories:_directories'
    '--ide[Аўтаматычна падключыцца да IDE пры запуску, калі даступная роўна адна валідная IDE]'
    '--strict-mcp-config[Выкарыстоўваць толькі MCP серверы з --mcp-config і ігнараваць усе іншыя налады MCP]'
    '--session-id[Канкрэтны ідэнтыфікатар сесіі для выкарыстання ў размове (павінен быць валідны UUID)]:uuid:'
    '--agents[JSON аб'\''ект, які вызначае карыстальніцкія агенты]:json:'
    '--setting-sources[Спіс крыніц налад праз коску для загрузкі (user, project, local)]:sources:'
    '--plugin-dir[Дырэкторыя для загрузкі плагінаў толькі для гэтай сесіі (можна паўтараць)]:paths:_directories'
    '--disable-slash-commands[Адключыць усе слэш-каманды]'
    '(--bg --background)'{--bg,--background}'[Запусціць сесію як фонавы агент і адразу вярнуцца]'
    '(-w --worktree)'{-w,--worktree}'[Стварыць новы git worktree для гэтай сесіі (можна ўказаць назву)]::name:'
    '--tmux[Стварыць tmux сесію для worktree (патрабуецца --worktree)]'
    '(-n --name)'{-n,--name}'[Задаць адлюстроўваемую назву для гэтай сесіі]:name:'
    '--effort[Узровень намаганняў для бягучай сесіі]:level:(low medium high xhigh max)'
    '--debug-file[Запісваць логі адладкі ў пэўны файл (няяўна ўключае рэжым адладкі)]:path:_files'
    '--from-pr[Аднавіць сесію, звязаную з PR па нумары/URL, або адкрыць інтэрактыўны выбар]::value:'
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
        login|logout)
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
    'install:Усталяваць плагін з даступных маркетплэйсаў'
    'i:Усталяваць плагін з даступных маркетплэйсаў (скарочана для install)'
    'init:Стварыць каркас новага плагіна (аўтаматычна загружаецца ў наступнай сесіі)'
    'uninstall:Выдаліць усталяваны плагін'
    'remove:Выдаліць усталяваны плагін (псеўданім для uninstall)'
    'enable:Уключыць выключаны плагін'
    'disable:Выключыць уключаны плагін'
    'update:Абнавіць плагін да апошняй версіі'
    'eval:Запусціць eval выпадкі супраць плагіна і паведаміць ацэненыя вынікі'
    'prune:Выдаліць аўтаматычна ўсталяваныя залежнасці, якія больш не патрэбны'
    'tag:Стварыць git тэг {name}--v{version} для рэлізу плагіна'
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
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Абсяг усталёўкі]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Абсяг усталёўкі]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Абсяг усталёўкі]:scope:(user project local)' \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Абсяг усталёўкі]:scope:(user project local managed)' \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list|prune)
          _arguments \
            '(-h --help)'{-h,--help}'[Паказаць даведку]'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init)
          _arguments \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:target:'
          ;;
        tag)
          _arguments \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:path:_files'
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
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Паказаць даведку]'
          ;;
        remove|rm)
          _arguments \
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
    '--agent[Агент па змаўчанні для сесій, дыспетчарызаваных з выгляду агентаў]:agent:' \
    '--all[З --json: таксама ўключыць завершаныя фонавыя сесіі]' \
    '--allow-dangerously-skip-permissions[Зрабіць рэжым абыходу дазволаў даступным для дыспетчарызаваных сесій]' \
    '--cwd[Паказаць толькі фонавыя сесіі, запушчаныя пад шляхам]:path:_directories' \
    '--dangerously-skip-permissions[Псеўданім для --permission-mode bypassPermissions]' \
    '--effort[Узровень намаганняў па змаўчанні для дыспетчарызаваных сесій]:level:(low medium high xhigh max)' \
    '--json[Вывесці актыўныя сесіі як JSON масіў і выйсці]' \
    '*--mcp-config[Канфігурацыя MCP сервера для прымянення да дыспетчарызаваных сесій]:config:' \
    '--model[Мадэль па змаўчанні для сесій, дыспетчарызаваных з выгляду агентаў]:model:' \
    '--permission-mode[Рэжым дазволаў па змаўчанні для дыспетчарызаваных сесій]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Загружаць плагіны з дырэкторыі для выгляду агентаў і дыспетчарызаваных сесій]:path:_directories' \
    '--setting-sources[Спіс крыніц налад праз коску для загрузкі (user, project, local)]:sources:' \
    '--settings[Файл налад або JSON радок для прымянення]:file-or-json:_files' \
    '--strict-mcp-config[Выкарыстоўваць толькі MCP серверы з --mcp-config у дыспетчарызаваных сесіях]' \
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
        login|logout|status)
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
        config|critique|defaults|reset)
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
            '(-h --help)'{-h,--help}'[Паказаць даведку для каманды]' \
            '1:path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Вывесці неапрацаваны bugs.json замест адфарматаваных вынікаў]' \
    '--timeout[Максімальная колькасць хвілін чакання завяршэння агляду]:minutes:' \
    '(-h --help)'{-h,--help}'[Паказаць даведку для каманды]' \
    '1:target:'
}

(( $+_comps[claude] )) || compdef _claude claude
