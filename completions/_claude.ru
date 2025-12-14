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
    'mcp:Настройка и управление MCP серверами'
    'plugin:Управление плагинами Claude Code'
    'setup-token:Настройка токена долгосрочной аутентификации (требуется подписка Claude)'
    'doctor:Проверка работоспособности автообновления Claude Code'
    'update:Проверка и установка обновлений'
    'install:Установка нативной сборки Claude Code'
  )
  local -a main_options
  main_options=(
    '(-d --debug)'{-d,--debug}'[Включить режим отладки с опциональной фильтрацией по категориям (например, "api,hooks" или "!statsig,!file")]:filter:'
    '--verbose[Переопределить настройку режима подробного вывода из конфигурационного файла]'
    '(-p --print)'{-p,--print}'[Вывести ответ и выйти (для использования с конвейерами). Примечание: использовать только в доверенных директориях]'
    '--output-format[Формат вывода (с --print): "text" (по умолчанию), "json" (единичный результат) или "stream-json" (потоковая передача в реальном времени)]:format:(text json stream-json)'
    '--json-schema[JSON схема для валидации структурированного вывода]:schema:'
    '--include-partial-messages[Включить частичные фрагменты сообщений по мере их поступления (с --print и --output-format=stream-json)]'
    '--input-format[Формат ввода (с --print): "text" (по умолчанию) или "stream-json" (потоковый ввод в реальном времени)]:format:(text stream-json)'
    '--mcp-debug[\[Устарело. Используйте --debug вместо этого\] Включить режим отладки MCP (показывает ошибки MCP сервера)]'
    '--dangerously-skip-permissions[Обойти все проверки разрешений. Рекомендуется только для изолированных сред без доступа к интернету]'
    '--allow-dangerously-skip-permissions[Включить возможность обхода проверок разрешений без включения по умолчанию]'
    '--replay-user-messages[Повторно отправить сообщения пользователя из stdin в stdout для подтверждения]'
    '--allowed-tools[Список разрешенных инструментов через запятую или пробел (например, "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Список разрешенных инструментов через запятую или пробел (формат camelCase)]:tools:'
    '--tools[Указать список доступных инструментов из встроенного набора. Только для режима вывода]:tools:'
    '--disallowed-tools[Список запрещенных инструментов через запятую или пробел (например, "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Список запрещенных инструментов через запятую или пробел (формат camelCase)]:tools:'
    '--mcp-config[Загрузить MCP серверы из JSON файла или строки (разделенные пробелом)]:configs:'
    '--system-prompt[Системный промпт для использования в сессии]:prompt:'
    '--append-system-prompt[Добавить системный промпт к системному промпту по умолчанию]:prompt:'
    '--permission-mode[Режим разрешений для использования в сессии]:mode:(acceptEdits bypassPermissions default dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Продолжить самый последний разговор]'
    '(-r --resume)'{-r,--resume}'[Возобновить разговор - укажите ID сессии или выберите интерактивно]:sessionId:_claude_sessions'
    '--fork-session[Создать новый ID сессии вместо повторного использования исходного ID сессии при возобновлении (с --resume или --continue)]'
    '--model[Модель для текущей сессии. Укажите псевдоним для последней модели (например, '\''sonnet'\'' или '\''opus'\'')]:model:'
    '--fallback-model[Включить автоматический переход на указанную модель при перегрузке модели по умолчанию (только --print)]:model:'
    '--settings[Путь к JSON файлу настроек или JSON строка для загрузки дополнительных настроек]:file-or-json:_files'
    '--add-dir[Дополнительные директории для разрешения доступа инструментов]:directories:_directories'
    '--ide[Автоматически подключиться к IDE при запуске, если доступна ровно одна валидная IDE]'
    '--strict-mcp-config[Использовать только MCP серверы из --mcp-config и игнорировать все остальные настройки MCP]'
    '--session-id[Конкретный ID сессии для использования в разговоре (должен быть валидным UUID)]:uuid:'
    '--agents[JSON объект, определяющий пользовательских агентов]:json:'
    '--setting-sources[Список источников настроек через запятую для загрузки (user, project, local)]:sources:'
    '--plugin-dir[Директория для загрузки плагинов только для этой сессии (может повторяться)]:paths:_directories'
    '(-v --version)'{-v,--version}'[Вывести номер версии]'
    '(-h --help)'{-h,--help}'[Показать справку по команде]'
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
        setup-token|doctor|update)
          _message "no arguments"
          ;;
      esac
      ;;
  esac
}
_claude_mcp() {
  local -a mcp_commands
  mcp_commands=(
    'serve:Запустить MCP сервер Claude Code'
    'add:Добавить MCP сервер в Claude Code'
    'remove:Удалить MCP сервер'
    'list:Показать список настроенных MCP серверов'
    'get:Получить детали MCP сервера'
    'add-json:Добавить MCP сервер (stdio или SSE) с JSON строкой'
    'add-from-claude-desktop:Импортировать MCP серверы из Claude Desktop (только Mac и WSL)'
    'reset-project-choices:Сбросить все одобренные/отклоненные серверы уровня проекта (.mcp.json) в этом проекте'
    'help:Показать справку'
  )
  local curcontext="$curcontext" state line
  typeset -A opt_args
  _arguments -C \
    '(-h --help)'{-h,--help}'[Показать справку]' \
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
            '(-d --debug)'{-d,--debug}'[Включить режим отладки]' \
            '--verbose[Переопределить настройку режима подробного вывода из конфигурационного файла]' \
            '(-h --help)'{-h,--help}'[Показать справку]'
          ;;
        add)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Область конфигурации (local, user, project)]:scope:(local user project)' \
            '(-t --transport)'{-t,--transport}'[Тип транспорта (stdio, sse, http)]:transport:(stdio sse http)' \
            '(-e --env)'{-e,--env}'[Установить переменную окружения (например, -e KEY=value)]:env:' \
            '(-H --header)'{-H,--header}'[Установить заголовок WebSocket]:header:' \
            '(-h --help)'{-h,--help}'[Показать справку]' \
            '1:name:' \
            '2:commandOrUrl:' \
            '*:args:'
          ;;
        remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Область конфигурации (local, user, project) - удалить из существующей области, если не указано]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Показать справку]' \
            '1:name:_claude_mcp_servers'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Показать справку]'
          ;;
        get)
          _arguments \
            '(-h --help)'{-h,--help}'[Показать справку]' \
            '1:name:_claude_mcp_servers'
          ;;
        add-json)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Область конфигурации (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Показать справку]' \
            '1:name:' \
            '2:json:'
          ;;
        add-from-claude-desktop)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Область конфигурации (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Показать справку]'
          ;;
        reset-project-choices)
          _arguments \
            '(-h --help)'{-h,--help}'[Показать справку]'
          ;;
      esac
      ;;
  esac
}
_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:Валидировать плагин или манифест маркетплейса'
    'marketplace:Управление маркетплейсами Claude Code'
    'install:Установить плагин из доступных маркетплейсов'
    'i:Установить плагин из доступных маркетплейсов (сокращение для install)'
    'uninstall:Удалить установленный плагин'
    'remove:Удалить установленный плагин (псевдоним для uninstall)'
    'enable:Включить отключенный плагин'
    'disable:Отключить включенный плагин'
    'help:Показать справку'
  )
  local curcontext="$curcontext" state line
  typeset -A opt_args
  _arguments -C \
    '(-h --help)'{-h,--help}'[Показать справку]' \
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
            '(-h --help)'{-h,--help}'[Показать справку]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-h --help)'{-h,--help}'[Показать справку]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-h --help)'{-h,--help}'[Показать справку]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-h --help)'{-h,--help}'[Показать справку]' \
            '1:plugin:_claude_installed_plugins'
          ;;
      esac
      ;;
  esac
}
_claude_plugin_marketplace() {
  local -a marketplace_commands
  marketplace_commands=(
    'add:Добавить маркетплейс из URL, пути или GitHub репозитория'
    'list:Показать список настроенных маркетплейсов'
    'remove:Удалить настроенный маркетплейс'
    'rm:Удалить настроенный маркетплейс (псевдоним для remove)'
    'update:Обновить маркетплейс из источника - обновить все, если имя не указано'
    'help:Показать справку'
  )
  local curcontext="$curcontext" state line
  typeset -A opt_args
  _arguments -C \
    '(-h --help)'{-h,--help}'[Показать справку]' \
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
            '(-h --help)'{-h,--help}'[Показать справку]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Показать справку]'
          ;;
        remove|rm)
          _arguments \
            '(-h --help)'{-h,--help}'[Показать справку]' \
            '1:name:'
          ;;
        update)
          _arguments \
            '(-h --help)'{-h,--help}'[Показать справку]' \
            '::name:'
          ;;
      esac
      ;;
  esac
}
_claude_install() {
  _arguments \
    '--force[Принудительная установка, даже если уже установлено]' \
    '(-h --help)'{-h,--help}'[Показать справку]' \
    '::target:(stable latest)'
}
(( $+_comps[claude] )) || compdef _claude claude
