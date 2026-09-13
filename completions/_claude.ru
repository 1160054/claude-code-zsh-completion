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
    'mcp:Настройка и управление MCP серверами'
    'plugin:Управление плагинами Claude Code'
    'agents:Управление фоновыми агентами'
    'attach:Открыть фоновую сессию в этом терминале'
    'logs:Вывести недавний вывод терминала фоновой сессии'
    'stop:Остановить фоновую сессию (её диалог сохраняется)'
    'respawn:Перезапустить фоновую сессию, чтобы она работала на текущей версии Claude Code'
    'rm:Удалить фоновую сессию, а также её worktree, если это безопасно'
    'auth:Управление аутентификацией'
    'auto-mode:Просмотр или сброс конфигурации классификатора авторежима'
    'gateway:Запустить корпоративный шлюз аутентификации/телеметрии'
    'import:Импортировать конфигурацию другого ИИ-агента для программирования в Claude Code'
    'project:Управление состоянием проекта Claude Code'
    'ultrareview:Запустить облачную мультиагентную проверку кода и вывести результаты'
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
    '--restricted[Ограниченный режим: убирает инструменты, выполняющие команды или код, и WebFetch, игнорирует настройки user/project/local и ограничивает файловые инструменты рабочими каталогами]'
    '--max-budget-usd[Максимальная сумма в долларах для расходов на вызовы API (только --print)]:amount:'
    '--replay-user-messages[Повторно отправить сообщения пользователя из stdin в stdout для подтверждения]'
    '--allowed-tools[Список разрешенных инструментов через запятую или пробел (например, "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Список разрешенных инструментов через запятую или пробел (формат camelCase)]:tools:'
    '--tools[Указать список доступных инструментов из встроенного набора. Только для режима вывода]:tools:'
    '--disallowed-tools[Список запрещенных инструментов через запятую или пробел (например, "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Список запрещенных инструментов через запятую или пробел (формат camelCase)]:tools:'
    '--mcp-config[Загрузить MCP серверы из JSON файла или строки (разделенные пробелом)]:configs:'
    '--system-prompt[Системный промпт для использования в сессии]:prompt:'
    '--system-prompt-file[Прочитать системный промпт из файла]:file:_files'
    '--append-system-prompt[Добавить системный промпт к системному промпту по умолчанию]:prompt:'
    '--append-system-prompt-file[Прочитать системный промпт из файла и добавить к системному промпту по умолчанию]:file:_files'
    '--system-prompt-snapshot[Записать системный промпт один раз на диалог и использовать его без изменений при каждом запросе и возобновлении (on, по умолчанию) или формировать заново при каждом запросе (off)]:mode:(on off)'
    '--permission-mode[Режим разрешений для использования в сессии]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)'
    '--permission-prompts[Кто отвечает на запросы разрешений при --print: "host" (хост SDK или --permission-prompt-tool) или "none" (всё, что потребовало бы запроса, отклоняется)]:target:(host none)'
    '--permission-prompt-tool[MCP-инструмент для запросов разрешений (только --print)]:tool:'
    '(-c --continue)'{-c,--continue}'[Продолжить самый последний разговор]'
    '(-r --resume)'{-r,--resume}'[Возобновить разговор - укажите ID сессии или выберите интерактивно]:sessionId:_claude_sessions'
    '--fork-session[Создать новый ID сессии вместо повторного использования исходного ID сессии при возобновлении (с --resume или --continue)]'
    '--no-session-persistence[Отключить сохранение сессий - сессии не будут сохраняться (только --print)]'
    '--model[Модель для текущей сессии. Укажите псевдоним для последней модели (например, '\''sonnet'\'' или '\''opus'\'')]:model:_claude_model_names'
    '--agent[Агент для текущей сессии. Переопределяет настройку '\''agent'\'']:agent:_claude_agent_names'
    '--betas[Бета-заголовки для включения в запросы API (только для пользователей с API ключом)]:betas:'
    '--fallback-model[Включить автоматический переход на указанную модель при перегрузке модели по умолчанию (только --print)]:model:_claude_model_names'
    '--settings[Путь к JSON файлу настроек или JSON строка для загрузки дополнительных настроек]:file-or-json:_files'
    '--add-dir[Дополнительные директории для разрешения доступа инструментов]:directories:_directories'
    '--ide[Автоматически подключиться к IDE при запуске, если доступна ровно одна валидная IDE]'
    '--strict-mcp-config[Использовать только MCP серверы из --mcp-config и игнорировать все остальные настройки MCP]'
    '--session-id[Конкретный ID сессии для использования в разговоре (должен быть валидным UUID)]:uuid:'
    '--agents[JSON объект, определяющий пользовательских агентов]:json:'
    '--setting-sources[Список источников настроек через запятую для загрузки (user, project, local)]:sources:'
    '--plugin-dir[Директория для загрузки плагинов только для этой сессии (может повторяться)]:paths:_directories'
    '--disable-slash-commands[Отключить все слэш-команды]'
    '(--bg --background)'{--bg,--background}'[Запустить сессию как фонового агента и немедленно вернуться]'
    '(-w --worktree)'{-w,--worktree}'[Создать новое git worktree для этой сессии (опционально указать имя)]::name:'
    '--tmux=-[Создать tmux сессию для worktree (требуется --worktree). По возможности использует нативные панели iTerm2; --tmux=classic для обычного tmux]::mode:(classic)'
    '(-n --name)'{-n,--name}'[Задать отображаемое имя для этой сессии]:name:'
    '--effort[Уровень усилий для текущей сессии]:level:(low medium high xhigh max)'
    '--autocompact[Размер окна автосжатия (auto или от 100k до 1M токенов)]:size:(auto)'
    '--debug-file[Записывать журналы отладки в указанный файл (неявно включает режим отладки)]:path:_files'
    '--from-pr[Возобновить сессию, связанную с PR по номеру/URL, или открыть интерактивный выбор]::value:'
    '--teleport[Возобновить teleport-сессию, опционально указав ID сессии]::session:'
    '--cloud[Создать облачную сессию с указанным описанием или подключиться к существующей по ID сессии или URL claude.ai/code]::description-or-session:'
    '--environment[Создать новую облачную сессию, работающую в указанном самостоятельно размещённом окружении (ccpool_...)]:environment_id:'
    '--remote-control[Запустить интерактивную сессию с включенным удаленным управлением (опционально с именем)]::name:'
    '--remote-control-session-name-prefix[Префикс для автоматически генерируемых имен сессий удаленного управления]:prefix:'
    '--chrome[Включить интеграцию Claude в Chrome]'
    '--no-chrome[Отключить интеграцию Claude в Chrome]'
    '--plugin-url[Загрузить плагин .zip по URL только для этой сессии (может повторяться)]:url:'
    '--file[Файловые ресурсы для загрузки при запуске (формат: file_id:relative_path)]:specs:'
    '--prompt-suggestions[Включить подсказки промптов (выдает предсказанный следующий промпт в режиме print/SDK)]::value:(true false 1 0 yes no on off)'
    '--forward-subagent-text[Пересылать текст и блоки размышлений субагента как сообщения (с --print и stream-json)]'
    '--include-hook-events[Включить все события жизненного цикла хуков в поток вывода (с stream-json)]'
    '--exclude-dynamic-system-prompt-sections[Переместить секции для конкретной машины в первое сообщение пользователя для улучшения переиспользования кэша промптов]'
    '--brief[Включить инструмент SendUserMessage для связи агента с пользователем]'
    '--safe-mode[Запуск со всеми отключенными настройками (полезно для устранения неполадок сломанной конфигурации)]'
    '--bare[Минимальный режим: пропустить хуки, LSP, синхронизацию плагинов, атрибуцию, авто-память и автообнаружение CLAUDE.md]'
    '--ax-screen-reader[Выводить дружественный к экранному диктору вывод (плоский текст, без декоративных границ или анимаций)]'
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
        agents)
          _claude_agents
          ;;
        attach|logs|stop|kill)
          _arguments \
            '(-h --help)'{-h,--help}'[Показать справку по команде]' \
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
    'login:Аутентификация на MCP сервере (HTTP, SSE или коннектор claude.ai)'
    'logout:Очистить сохраненные учетные данные OAuth для MCP сервера'
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
            '--client-id[OAuth client ID для HTTP/SSE серверов]:clientId:' \
            '--client-secret[Запросить OAuth client secret (или задать переменную окружения MCP_CLIENT_SECRET)]' \
            '--callback-port[Фиксированный порт для OAuth callback (для серверов, требующих заранее зарегистрированные redirect URI)]:port:' \
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
            '--client-secret[Запросить OAuth client secret (или задать переменную окружения MCP_CLIENT_SECRET)]' \
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
        login)
          _arguments \
            '--no-browser[Вывести URL авторизации вместо открытия браузера (для SSH/headless сессий)]' \
            '(-h --help)'{-h,--help}'[Показать справку]' \
            '1:name:_claude_mcp_servers'
          ;;
        logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Показать справку]' \
            '1:name:_claude_mcp_servers'
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
    'list:Показать список установленных плагинов'
    'details:Показать инвентарь компонентов и прогнозируемую стоимость в токенах для плагина'
    'install:Установить плагин из доступных маркетплейсов'
    'i:Установить плагин из доступных маркетплейсов (сокращение для install)'
    'init:Создать шаблон нового плагина (автоматически загружается в следующей сессии)'
    'new:Создать заготовку нового плагина (псевдоним init)'
    'uninstall:Удалить установленный плагин'
    'remove:Удалить установленный плагин (псевдоним для uninstall)'
    'enable:Включить отключенный плагин'
    'disable:Отключить включенный плагин'
    'update:Обновить плагин до последней версии'
    'eval:Запустить тестовые сценарии для плагина и вывести оцененные результаты'
    'prune:Удалить автоматически установленные зависимости, которые больше не нужны'
    'autoremove:Удалить автоматически установленные зависимости, которые больше не нужны (псевдоним prune)'
    'tag:Создать git тег {name}--v{version} для релиза плагина'
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
            '--strict[Считать предупреждения ошибками (код выхода 1)]' \
            '--json[Вывести отчёт валидации в JSON (те же коды выхода)]' \
            '(-h --help)'{-h,--help}'[Показать справку]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Область установки]:scope:(user project local)' \
            '*--config[Задать опцию userConfig, объявленную в манифесте плагина (можно повторять)]:key=value:' \
            '(-y --yes)'{-y,--yes}'[Принять показанную команду, объявленную маркетплейсом, без запроса подтверждения]' \
            '--json[Вывести одну машиночитаемую строку результата вместо сообщения для человека]' \
            '(-h --help)'{-h,--help}'[Показать справку]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Область установки]:scope:(user project local)' \
            '--keep-data[Сохранить каталог постоянных данных плагина]' \
            '--prune[Также удалить автоматически установленные зависимости, которые больше не нужны]' \
            '(-y --yes)'{-y,--yes}'[Пропустить запрос подтверждения --prune]' \
            '--json[Вывести одну машиночитаемую строку результата вместо сообщения для человека (не вместе с --prune)]' \
            '(-h --help)'{-h,--help}'[Показать справку]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Область установки]:scope:(user project local)' \
            '--json[Вывести одну машиночитаемую строку результата вместо сообщения для человека]' \
            '(-h --help)'{-h,--help}'[Показать справку]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        disable)
          _arguments \
            '(-a --all)'{-a,--all}'[Отключить все включённые плагины]' \
            '(-s --scope)'{-s,--scope}'[Область установки]:scope:(user project local)' \
            '--json[Вывести одну машиночитаемую строку результата вместо сообщения для человека]' \
            '(-h --help)'{-h,--help}'[Показать справку]' \
            '::plugin:_claude_installed_plugins'
          ;;
        update)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Область установки]:scope:(user project local managed)' \
            '(-y --yes)'{-y,--yes}'[Принять показанную команду, объявленную маркетплейсом, без запроса подтверждения]' \
            '--json[Вывести одну машиночитаемую строку результата вместо сообщения для человека]' \
            '(-h --help)'{-h,--help}'[Показать справку]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        list)
          _arguments \
            '--json[Вывод в JSON]' \
            '--available[Включить доступные плагины из маркетплейсов (требуется --json)]' \
            '(-h --help)'{-h,--help}'[Показать справку]'
          ;;
        prune|autoremove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Область, в которой выполнять очистку]:scope:(user project local)' \
            '--dry-run[Показать, что будет удалено, ничего не удаляя]' \
            '(-y --yes)'{-y,--yes}'[Пропустить запрос подтверждения]' \
            '(-h --help)'{-h,--help}'[Показать справку]'
          ;;
        details)
          _arguments \
            '(-h --help)'{-h,--help}'[Показать справку]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        init|new)
          _arguments \
            '--description[Описание в манифесте]:text:' \
            '--author[Имя автора (по умолчанию: git config user.name)]:name:' \
            '--author-email[Email автора (по умолчанию: git config user.email)]:email:' \
            '--with[Компоненты, заготовки которых также нужно создать]:components:' \
            '(-f --force)'{-f,--force}'[Перезаписать существующий .claude-plugin/ в целевом каталоге]' \
            '(-h --help)'{-h,--help}'[Показать справку]' \
            '1:name:'
          ;;
        eval)
          _arguments \
            '--case[Фильтровать кейсы по glob-шаблону имени]:glob:' \
            '*--tag[Фильтровать кейсы по тегу (можно повторять)]:tag:' \
            '--runs[Переопределить число запусков на кейс (по умолчанию: case.runs, иначе 3)]:n:' \
            '(-j --concurrency)'{-j,--concurrency}'[Запускать до n агентов одновременно (1-8; по умолчанию 1)]:n:' \
            '--model[Переопределить модель для всех кейсов]:model:_claude_model_names' \
            '--judge-model[Переопределить модель LLM-оценщика (по умолчанию: haiku)]:model:_claude_model_names' \
            '--max-cost-usd[Жёсткий потолок стоимости; при достижении прервать и вывести частичные результаты (код выхода 2)]:usd:' \
            '--output-dir[Каталог для aggregate-result.json]:dir:_directories' \
            '--eval-dir[Имя каталога (внутри плагина) с кейсами оценки]:dir:' \
            '--json[Вывести полный результат запуска в JSON в stdout или записать в этот .json файл]::path:_files' \
            '--threshold[Выйти с кодом 1, если оценка любого кейса ниже этого порога (по умолчанию: 1.0)]:threshold:' \
            '*--allow-tools[Разрешение оператора для ограниченных инструментов (Bash, Write, Edit, WebFetch, mcp__*)]:tools:' \
            '(--no-scaffold)--scaffold[Запускать scaffold_script каждого кейса (выполняет bash от автора от вашего имени; по умолчанию выключено)]' \
            '(--scaffold)--no-scaffold[Явно пропустить scaffold_script]' \
            '--trust-plugin[Подтвердить доверие к этому плагину и его набору оценок, пропустив запрос доверия при первом запуске (для CI)]' \
            '--ablation[Дополнительно выполнить базовый прогон без плагина и показать разницу оценок]:mode:(none with-without)' \
            '--mocks[Мок-заменители MCP серверов из <eval dir>/mocks/]:mode:(record off)' \
            '--allow-real-servers[С --mocks record: также запускать реальные процессы MCP серверов, у которых нет мока]' \
            '--keep-temp[Сохранять каталоги scaffold для отладки]' \
            '--verbose[Записывать события трассировки по каждому сообщению в журнал отладки]' \
            '--report[Записать автономный HTML-отчёт по этому пути вместо каталога результатов]:path:_files' \
            '(--no-publish)--publish-report[Также требовать публикации отчёта на claude.ai]' \
            '(--publish-report)--no-publish[Оставить HTML-отчёт только локально; не публиковать на claude.ai]' \
            '(-h --help)'{-h,--help}'[Показать справку]' \
            '::target: _alternative "plugins\:installed plugin\:_claude_installed_plugins" "files\:path\:_files"'
          ;;
        tag)
          _arguments \
            '--push[Отправить тег в --remote после создания]' \
            '--dry-run[Показать, что будет помечено тегом, не создавая его]' \
            '(-f --force)'{-f,--force}'[Пропустить проверки незакоммиченных изменений и существующего тега]' \
            '(-m --message)'{-m,--message}'[Сообщение аннотации тега (%s заменяется версией)]:msg:' \
            '--remote[Удалённый репозиторий для отправки с --push]:name:' \
            '(-h --help)'{-h,--help}'[Показать справку]' \
            '::path:_files'
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
            '--sparse[Ограничить checkout отдельными каталогами через git sparse-checkout (для монорепозиториев)]:paths:' \
            '--scope[Где объявить маркетплейс]:scope:(user project local)' \
            '--claudeai[Добавить маркетплейс с этим именем, который claude.ai размещает для вас]' \
            '(-h --help)'{-h,--help}'[Показать справку]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '--json[Вывод в JSON]' \
            '(-h --help)'{-h,--help}'[Показать справку]'
          ;;
        remove|rm)
          _arguments \
            '--scope[Удалить объявление маркетплейса из указанной области настроек (без указания — из всех областей)]:scope:(user project local)' \
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

_claude_agents() {
  _arguments \
    '*--add-dir[Дополнительная директория для разрешения доступа инструментов в запущенных сессиях]:directory:_directories' \
    '--agent[Агент по умолчанию для сессий, запущенных из представления агентов]:agent:_claude_agent_names' \
    '--all[С --json: также включить завершенные фоновые сессии]' \
    '--allow-dangerously-skip-permissions[Сделать режим обхода разрешений доступным для запущенных сессий]' \
    '--cwd[Показать только фоновые сессии, запущенные по указанному пути]:path:_directories' \
    '--dangerously-skip-permissions[Псевдоним для --permission-mode bypassPermissions]' \
    '--effort[Уровень усилий по умолчанию для запущенных сессий]:level:(low medium high xhigh max)' \
    '--json[Вывести активные сессии как JSON массив и выйти]' \
    '*--mcp-config[Конфигурация MCP сервера для применения к запущенным сессиям]:config:' \
    '--model[Модель по умолчанию для сессий, запущенных из представления агентов]:model:_claude_model_names' \
    '--permission-mode[Режим разрешений по умолчанию для запущенных сессий]:mode:(acceptEdits auto bypassPermissions manual dontAsk plan)' \
    '*--plugin-dir[Загружать плагины из директории для представления агентов и запущенных сессий]:path:_directories' \
    '--setting-sources[Список источников настроек через запятую для загрузки (user, project, local)]:sources:' \
    '--settings[Файл настроек или JSON строка для применения]:file-or-json:_files' \
    '--strict-mcp-config[Использовать только MCP серверы из --mcp-config в запущенных сессиях]' \
    '--restricted[Запускать порождаемые сессии в ограниченном режиме]' \
    '(-h --help)'{-h,--help}'[Показать справку по команде]'
}

_claude_auth() {
  local -a auth_commands
  auth_commands=(
    'login:Войти в свой аккаунт Anthropic'
    'logout:Выйти из своего аккаунта Anthropic'
    'status:Показать статус аутентификации'
    'help:Показать справку'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Показать справку по команде]' \
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
            '--email[Заранее подставить email на странице входа]:email:' \
            '--sso[Принудительно использовать вход через SSO]' \
            '(--claudeai)--console[Использовать Anthropic Console (оплата по использованию API) вместо подписки Claude]' \
            '(--console)--claudeai[Использовать подписку Claude (по умолчанию)]' \
            '(-h --help)'{-h,--help}'[Показать справку по команде]'
          ;;
        status)
          _arguments \
            '(--text)--json[Вывод в JSON (по умолчанию)]' \
            '(--json)--text[Вывод в виде читаемого текста]' \
            '(-h --help)'{-h,--help}'[Показать справку по команде]'
          ;;
        logout)
          _arguments \
            '(-h --help)'{-h,--help}'[Показать справку по команде]'
          ;;
      esac
      ;;
  esac
}

_claude_auto_mode() {
  local -a auto_mode_commands
  auto_mode_commands=(
    'config:Вывести действующую конфигурацию авторежима как JSON'
    'critique:Получить AI отзыв о ваших пользовательских правилах авторежима'
    'defaults:Вывести правила авторежима по умолчанию как JSON'
    'reset:Сбросить конфигурацию авторежима к поставляемым значениям по умолчанию'
    'help:Показать справку'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Показать справку по команде]' \
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
            '--model[Переопределить используемую модель]:model:_claude_model_names' \
            '(-h --help)'{-h,--help}'[Показать справку по команде]'
          ;;
        defaults)
          _arguments \
            '--label[Показывать только правила, метка которых начинается с этого префикса (без учёта регистра)]:prefix:' \
            '(-h --help)'{-h,--help}'[Показать справку по команде]'
          ;;
        reset)
          _arguments \
            '(-y --yes)'{-y,--yes}'[Пропустить запрос подтверждения]' \
            '(-h --help)'{-h,--help}'[Показать справку по команде]'
          ;;
        config)
          _arguments \
            '(-h --help)'{-h,--help}'[Показать справку по команде]'
          ;;
      esac
      ;;
  esac
}

_claude_gateway() {
  _arguments \
    '--config[Путь к YAML конфигурации шлюза]:path:_files' \
    '(-h --help)'{-h,--help}'[Показать справку по команде]'
}

_claude_project() {
  local -a project_commands
  project_commands=(
    'purge:Удалить все состояние Claude Code для проекта (транскрипты, задачи, история файлов, запись конфигурации)'
    'help:Показать справку'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Показать справку по команде]' \
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
            '--dry-run[Показать, что будет удалено, ничего не удаляя]' \
            '(-y --yes)'{-y,--yes}'[Пропустить запрос подтверждения]' \
            '(-i --interactive)'{-i,--interactive}'[Спрашивать подтверждение для каждого элемента перед удалением]' \
            '(1)--all[Очистить состояние всех проектов (несовместимо с указанием пути)]' \
            '(-h --help)'{-h,--help}'[Показать справку по команде]' \
            '(--all)::path:_directories'
          ;;
      esac
      ;;
  esac
}

_claude_ultrareview() {
  _arguments \
    '--json[Вывести необработанный payload bugs.json вместо форматированных результатов]' \
    '--timeout[Максимальное количество минут ожидания завершения проверки (по умолчанию: 45)]:minutes:' \
    '(--no-post)--post[Опубликовать результаты завершённой проверки в PR от вашего имени (только для PR; один обычный комментарий, не review)]' \
    '(--post)--no-post[Не публиковать результаты в PR (по умолчанию)]' \
    '(-h --help)'{-h,--help}'[Показать справку по команде]' \
    '1:target:'
}

_claude_respawn() {
  _arguments \
    '(1)--all[Перезапустить все работающие фоновые сессии]' \
    '(-h --help)'{-h,--help}'[Показать справку по команде]' \
    '(--all)::session:_claude_background_sessions'
}

_claude_rm() {
  _arguments \
    '--discard-unpushed[Также отбросить неотправленные коммиты и незакоммиченные изменения worktree (передайте commit@worktree-id, который сообщил предыдущий claude rm)]:commit@worktree-id:' \
    '--force-remove-worktree[Удалить каталог worktree, даже если хук WorktreeRemove или git не смогли его убрать (передайте worktree-id, который сообщил предыдущий claude rm)]:worktree-id:' \
    '(-h --help)'{-h,--help}'[Показать справку по команде]' \
    '1:session:_claude_background_sessions'
}

_claude_import() {
  _arguments \
    '--dry-run[Показать, что будет импортировано, ничего не записывая]' \
    '--yes[Пропустить интерактивный выбор (в headless окружении передайте --yes=<digest> из предпросмотра /import)]' \
    '(-h --help)'{-h,--help}'[Показать справку по команде]' \
    '::source:(codex gemini cursor)'
}

(( $+_comps[claude] )) || compdef _claude claude
