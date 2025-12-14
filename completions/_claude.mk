#compdef claude

# Динамични функции за автоматско пополнување
_claude_mcp_servers() {
  local servers config_file
  local -a server_list

  # Читање директно од конфигурациските датотеки наместо извршување на 'claude mcp list'
  for config_file in ~/.claude/mcp.json ~/.claude.json ~/.config/claude/mcp.json; do
    [[ -f "$config_file" ]] || continue

    # Извлекување на имињата на серверите од JSON (секција mcpServers)
    servers=$(grep -oP '(?<="mcpServers":\s*\{)[^}]+' "$config_file" 2>/dev/null | \
              grep -oP '(?<=")[^"]+(?="\s*:)' 2>/dev/null)

    [[ -n "$servers" ]] && server_list+=(${(f)servers})
  done

  # Резервна варијанта: claude mcp list, ако парсирањето на конфигурацијата не успее
  if [[ ${#server_list[@]} -eq 0 ]]; then
    server_list=(${(f)"$(claude mcp list 2>/dev/null | sed -n 's/^\([^:]*\):.*/\1/p' | grep -v '^Checking')"})
  fi

  _describe 'mcp сервери' server_list
}

_claude_installed_plugins() {
  local -a plugins
  local config_file plugin_dir

  # Проверка на директориумите за приклучоци директно
  for plugin_dir in ~/.claude/plugins ~/.config/claude/plugins; do
    [[ -d "$plugin_dir" ]] || continue
    plugins+=(${plugin_dir}/*(N:t))
  done

  # Отстранување на дупликати
  plugins=(${(u)plugins})

  _describe 'инсталирани приклучоци' plugins
}

_claude_sessions() {
  local -a sessions
  local session_dir

  # Проверка на директориумот за сесии
  for session_dir in ~/.claude/sessions ~/.config/claude/sessions; do
    [[ -d "$session_dir" ]] || continue

    # Извлекување на UUID директно од имињата на датотеките
    sessions+=(${session_dir}/*~*.zwc(N:t:r))
  done

  # Филтрирање само на валидни UUID
  sessions=(${(M)sessions:#[0-9a-f](#c8)-[0-9a-f](#c4)-[0-9a-f](#c4)-[0-9a-f](#c4)-[0-9a-f](#c12)})

  _describe 'идентификатори на сесии' sessions
}

_claude() {
  local curcontext="$curcontext" state line
  typeset -A opt_args

  local -a main_commands
  main_commands=(
    'mcp:Конфигурирање и управување со MCP сервери'
    'plugin:Управување со приклучоци на Claude Code'
    'setup-token:Поставување на токен за долгорочна автентикација (потребна е Claude претплата)'
    'doctor:Проверка на здравјето на системот за автоматски ажурирања на Claude Code'
    'update:Проверка и инсталација на ажурирања'
    'install:Инсталација на изворна верзија на Claude Code'
  )

  local -a main_options
  main_options=(
    '(-d --debug)'{-d,--debug}'[Вклучи режим на отстранување грешки со опционално филтрирање по категории (на пр. "api,hooks" или "!statsig,!file")]:filter:'
    '--verbose[Препокриј поставка на детален режим од конфигурациската датотека]'
    '(-p --print)'{-p,--print}'[Испечати одговор и излез (за употреба со pipe). Напомена: користете само во доверливи директориуми]'
    '--output-format[Формат на излез (со --print): "text" (стандардно), "json" (еден резултат), или "stream-json" (стримување во реално време)]:format:(text json stream-json)'
    '--json-schema[JSON шема за валидација на структуриран излез]:schema:'
    '--include-partial-messages[Вклучи делумни фрагменти на пораки при нивното пристигнување (со --print и --output-format=stream-json)]'
    '--input-format[Формат на влез (со --print): "text" (стандардно) или "stream-json" (стримуван влез во реално време)]:format:(text stream-json)'
    '--mcp-debug[\[Застарено. Користете --debug наместо тоа\] Вклучи режим на отстранување грешки на MCP (прикажува грешки на MCP серверот)]'
    '--dangerously-skip-permissions[Заобиколи ги сите проверки за дозволи. Препорачливо само за sandbox окружувања без пристап до интернет]'
    '--allow-dangerously-skip-permissions[Овозможи опција за заобиколување на проверки за дозволи без овозможување стандардно]'
    '--replay-user-messages[Повторно испрати кориснички пораки од stdin на stdout за потврда]'
    '--allowed-tools[Список на дозволени имиња на алатки одделени со запирка или празно место (на пр. "Bash(git:*) Edit")]:tools:'
    '--allowedTools[Список на дозволени имиња на алатки одделени со запирка или празно место (формат camelCase)]:tools:'
    '--tools[Наведи список на достапни алатки од вградениот сет. Само во режим print]:tools:'
    '--disallowed-tools[Список на забранети имиња на алатки одделени со запирка или празно место (на пр. "Bash(git:*) Edit")]:tools:'
    '--disallowedTools[Список на забранети имиња на алатки одделени со запирка или празно место (формат camelCase)]:tools:'
    '--mcp-config[Вчитај MCP сервери од JSON датотека или стринг (одделени со празни места)]:configs:'
    '--system-prompt[Системски prompt за употреба во сесијата]:prompt:'
    '--append-system-prompt[Додај системски prompt на стандардниот системски prompt]:prompt:'
    '--permission-mode[Режим на дозволи за употреба во сесијата]:mode:(acceptEdits bypassPermissions default dontAsk plan)'
    '(-c --continue)'{-c,--continue}'[Продолжи со последниот разговор]'
    '(-r --resume)'{-r,--resume}'[Продолжи разговор - наведете идентификатор на сесија или изберете интерактивно]:sessionId:_claude_sessions'
    '--fork-session[Креирај нов идентификатор на сесија наместо повторна употреба на оригиналниот при продолжување (со --resume или --continue)]'
    '--model[Модел за тековната сесија. Наведете алијас за најновиот модел (на пр. '\''sonnet'\'' или '\''opus'\'')]:model:'
    '--fallback-model[Овозможи автоматско префрлање на наведениот модел кога стандардниот модел е преоптоварен (само --print)]:model:'
    '--settings[Патека до JSON датотека со поставки или JSON стринг за вчитување на дополнителни поставки]:file-or-json:_files'
    '--add-dir[Дополнителни директориуми за обезбедување пристап на алатки]:directories:_directories'
    '--ide[Автоматски поврзи се со IDE при стартување ако е достапен точно еден валиден IDE]'
    '--strict-mcp-config[Користи само MCP сервери од --mcp-config и игнорирај ги сите други MCP поставки]'
    '--session-id[Одреден идентификатор на сесија за употреба во разговор (мора да биде валиден UUID)]:uuid:'
    '--agents[JSON објект кој дефинира приспособени агенти]:json:'
    '--setting-sources[Список на извори на поставки одделени со запирка за вчитување (user, project, local)]:sources:'
    '--plugin-dir[Директориум за вчитување на приклучоци само за оваа сесија (може да се повтори)]:paths:_directories'
    '(-v --version)'{-v,--version}'[Испечати број на верзија]'
    '(-h --help)'{-h,--help}'[Прикажи помош за команда]'
  )

  _arguments -C \
    $main_options \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'команди на claude' main_commands
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
          _message "без аргументи"
          ;;
      esac
      ;;
  esac
}

_claude_mcp() {
  local -a mcp_commands
  mcp_commands=(
    'serve:Стартувај MCP сервер на Claude Code'
    'add:Додај MCP сервер во Claude Code'
    'remove:Отстрани MCP сервер'
    'list:Прикажи список на конфигурирани MCP сервери'
    'get:Преземи детали за MCP серверот'
    'add-json:Додај MCP сервер (stdio или SSE) со JSON стринг'
    'add-from-claude-desktop:Увези MCP сервери од Claude Desktop (само Mac и WSL)'
    'reset-project-choices:Ресетирај ги сите одобрени/одбиени сервери со опсег на проект (.mcp.json) во овој проект'
    'help:Прикажи помош'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Прикажи помош]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'команди на mcp' mcp_commands
      ;;
    args)
      case $words[1] in
        serve)
          _arguments \
            '(-d --debug)'{-d,--debug}'[Вклучи режим на отстранување грешки]' \
            '--verbose[Препокриј поставка на детален режим од конфигурациската датотека]' \
            '(-h --help)'{-h,--help}'[Прикажи помош]'
          ;;
        add)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Опсег на конфигурација (local, user, project)]:scope:(local user project)' \
            '(-t --transport)'{-t,--transport}'[Тип на пренос (stdio, sse, http)]:transport:(stdio sse http)' \
            '(-e --env)'{-e,--env}'[Постави променлива на околина (на пр. -e KEY=value)]:env:' \
            '(-H --header)'{-H,--header}'[Постави WebSocket заглавие]:header:' \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:name:' \
            '2:commandOrUrl:' \
            '*:args:'
          ;;
        remove)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Опсег на конфигурација (local, user, project) - отстрани од постоечки опсег ако не е наведено]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:name:_claude_mcp_servers'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Прикажи помош]'
          ;;
        get)
          _arguments \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:name:_claude_mcp_servers'
          ;;
        add-json)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Опсег на конфигурација (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:name:' \
            '2:json:'
          ;;
        add-from-claude-desktop)
          _arguments \
            '(-s --scope)'{-s,--scope}'[Опсег на конфигурација (local, user, project)]:scope:(local user project)' \
            '(-h --help)'{-h,--help}'[Прикажи помош]'
          ;;
        reset-project-choices)
          _arguments \
            '(-h --help)'{-h,--help}'[Прикажи помош]'
          ;;
      esac
      ;;
  esac
}

_claude_plugin() {
  local -a plugin_commands
  plugin_commands=(
    'validate:Валидирај приклучок или манифест на пазар'
    'marketplace:Управување со пазари на Claude Code'
    'install:Инсталирај приклучок од достапни пазари'
    'i:Инсталирај приклучок од достапни пазари (кратенка за install)'
    'uninstall:Деинсталирај инсталиран приклучок'
    'remove:Деинсталирај инсталиран приклучок (алијас за uninstall)'
    'enable:Овозможи оневозможен приклучок'
    'disable:Оневозможи овозможен приклучок'
    'help:Прикажи помош'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Прикажи помош]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'команди на plugin' plugin_commands
      ;;
    args)
      case $words[1] in
        validate)
          _arguments \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:path:_files'
          ;;
        marketplace)
          _claude_plugin_marketplace
          ;;
        install|i)
          _arguments \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:plugin:'
          ;;
        uninstall|remove)
          _arguments \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:plugin:_claude_installed_plugins'
          ;;
        enable|disable)
          _arguments \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:plugin:_claude_installed_plugins'
          ;;
      esac
      ;;
  esac
}

_claude_plugin_marketplace() {
  local -a marketplace_commands
  marketplace_commands=(
    'add:Додај пазар од URL, патека или GitHub репозиториум'
    'list:Прикажи список на конфигурирани пазари'
    'remove:Отстрани конфигуриран пазар'
    'rm:Отстрани конфигуриран пазар (алијас за remove)'
    'update:Ажурирај пазар од извор - ажурирај ги сите ако името не е наведено'
    'help:Прикажи помош'
  )

  local curcontext="$curcontext" state line
  typeset -A opt_args

  _arguments -C \
    '(-h --help)'{-h,--help}'[Прикажи помош]' \
    '1: :->command' \
    '*::arg:->args'

  case $state in
    command)
      _describe -t commands 'команди на marketplace' marketplace_commands
      ;;
    args)
      case $words[1] in
        add)
          _arguments \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:source:'
          ;;
        list)
          _arguments \
            '(-h --help)'{-h,--help}'[Прикажи помош]'
          ;;
        remove|rm)
          _arguments \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '1:name:'
          ;;
        update)
          _arguments \
            '(-h --help)'{-h,--help}'[Прикажи помош]' \
            '::name:'
          ;;
      esac
      ;;
  esac
}

_claude_install() {
  _arguments \
    '--force[Принудителна инсталација дури и ако е веќе инсталирано]' \
    '(-h --help)'{-h,--help}'[Прикажи помош]' \
    '::target:(stable latest)'
}

(( $+_comps[claude] )) || compdef _claude claude
