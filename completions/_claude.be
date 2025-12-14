#compdef claude

# Дынамічныя функцыі аўтазапаўнення
_claude_mcp_servers() {
  local servers config_file
  local -a server_list

  # Чытанне непасрэдна з канфігурацыйных файлаў замест выканання 'claude mcp list'
  for config_file in ~/.claude/mcp.json ~/.claude.json ~/.config/claude/mcp.json; do
    [[ -f "$config_file" ]] || continue

    # Выцягванне назваў сервераў з JSON (секцыя mcpServers)
    servers=$(grep -oP '(?<="mcpServers":\s*\{)[^}]+' "$config_file" 2>/dev/null | \
              grep -oP '(?<=")[^"]+(?="\s*:)' 2>/dev/null)

    [[ -n "$servers" ]] && server_list+=(${(f)servers})
  done

  # Рэзервовы варыянт: claude mcp list, калі парсінг канфігурацыі не ўдаўся
  if [[ ${#server_list[@]} -eq 0 ]]; then
    server_list=(${(f)"$(claude mcp list 2>/dev/null | sed -n 's/^\([^:]*\):.*/\1/p' | grep -v '^Checking')"})
  fi

  _describe 'mcp серверы' server_list
}

_claude_installed_plugins() {
  local -a plugins
  local config_file plugin_dir

  # Праверка дырэкторый плагінаў непасрэдна
  for plugin_dir in ~/.claude/plugins ~/.config/claude/plugins; do
    [[ -d "$plugin_dir" ]] || continue
    plugins+=(${plugin_dir}/*(N:t))
  done

  # Выдаленне дублікатаў
  plugins=(${(u)plugins})

  _describe 'усталяваныя плагіны' plugins
}

_claude_sessions() {
  local -a sessions
  local session_dir

  # Праверка дырэкторыі сесій
  for session_dir in ~/.claude/sessions ~/.config/claude/sessions; do
    [[ -d "$session_dir" ]] || continue

    # Выцягванне UUID непасрэдна з імёнаў файлаў
    sessions+=(${session_dir}/*~*.zwc(N:t:r))
  done

  # Фільтраванне толькі валідных UUID
  sessions=(${(M)sessions:#[0-9a-f](#c8)-[0-9a-f](#c4)-[0-9a-f](#c4)-[0-9a-f](#c4)-[0-9a-f](#c12)})

  _describe 'ідэнтыфікатары сесій' sessions
}

_claude() {
  local curcontext="$curcontext" state line
  typeset -A opt_args

  local -a main_commands
  main_commands=(
    'mcp:Наладзіць і кіраваць MCP серверамі'
    'plugin:Кіраваць плагінамі Claude Code'
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
    '--replay-user-messages[Паўторна адправіць паведамленні карыстальніка з stdin на stdout для пацверджання]'
    '--allowed-tools[Спіс дазволеных імёнаў інструментаў праз коску або прабел (напрыклад, "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Спіс дазволеных імёнаў інструментаў праз коску або прабел (фармат camelCase)]:tools:'
    '--tools[Указаць спіс даступных інструментаў з убудаванага набору. Толькі ў рэжыме print]:tools:'
    '--disallowed-tools[Спіс забароненых імёнаў інструментаў праз коску або прабел (напрыклад, "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Спіс забароненых імёнаў інструментаў праз коску або прабел (фармат camelCase)]:tools:'
    '--mcp-config[Загрузіць MCP серверы з JSON файла або радка (падзеленыя прабеламі)]:configs:'
    '--system-prompt[Сістэмны промпт для выкарыстання ў сесіі]:prompt:'
    '--append-system-prompt[Дадаць сістэмны промпт да стандартнага сістэмнага промпту]:prompt:'
    '--permission-mode[Рэжым дазволаў для выкарыстання ў сесіі]:mode:(acceptEdits bypassPermissions default dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Працягнуць апошнюю размову]'
    '(-r --resume)'{-r,--resume}'[Аднавіць размову - укажыце ідэнтыфікатар сесіі або выберыце інтэрактыўна]:sessionId:_claude_sessions'
    '--fork-session[Стварыць новы ідэнтыфікатар сесіі замест паўторнага выкарыстання арыгінальнага пры аднаўленні (з --resume або --continue)]'
    '--model[Мадэль для бягучай сесіі. Укажыце псеўданім для апошняй мадэлі (напрыклад, '\''sonnet'\'' або '\''opus'\'')]:model:'
    '--fallback-model[Уключыць аўтаматычны пераход на ўказаную мадэль, калі мадэль па змаўчанні перагружана (толькі --print)]:model:'
    '--settings[Шлях да JSON файла налад або JSON радок для загрузкі дадатковых налад]:file-or-json:_files'
    '--add-dir[Дадатковыя дырэкторыі для надання доступу інструментам]:directories:_directories'
    '--ide[Аўтаматычна падключыцца да IDE пры запуску, калі даступная роўна адна валідная IDE]'
    '--strict-mcp-config[Выкарыстоўваць толькі MCP серверы з --mcp-config і ігнараваць усе іншыя налады MCP]'
    '--session-id[Канкрэтны ідэнтыфікатар сесіі для выкарыстання ў размове (павінен быць валідны UUID)]:uuid:'
    '--agents[JSON аб'\''ект, які вызначае карыстальніцкія агенты]:json:'
    '--setting-sources[Спіс крыніц налад праз коску для загрузкі (user, project, local)]:sources:'
    '--plugin-dir[Дырэкторыя для загрузкі плагінаў толькі для гэтай сесіі (можна паўтараць)]:paths:_directories'
    '(-v --version)'{-v,--version}'[Вывесці нумар версіі]'
    '(-h --help)'{-h,--help}'[Паказаць даведку для каманды]'
  )

  _arguments -C \
    $main_options \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'каманды claude' main_commands
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
      _describe -t commands 'каманды mcp' mcp_commands
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
      esac
      ;;
  esac
}

_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:Валідаваць плагін або маніфест маркетплэйса'
    'marketplace:Кіраваць маркетплэйсамі Claude Code'
    'install:Усталяваць плагін з даступных маркетплэйсаў'
    'i:Усталяваць плагін з даступных маркетплэйсаў (скарочана для install)'
    'uninstall:Выдаліць усталяваны плагін'
    'remove:Выдаліць усталяваны плагін (псеўданім для uninstall)'
    'enable:Уключыць выключаны плагін'
    'disable:Выключыць уключаны плагін'
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
      _describe -t commands 'каманды plugin' plugin_commands
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
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-h --help)'{-h,--help}'[Паказаць даведку]' \
            '1:plugin:_claude_installed_plugins'
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
      _describe -t commands 'каманды marketplace' marketplace_commands
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

(( $+_comps[claude] )) || compdef _claude claude
